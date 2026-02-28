%%%-------------------------------------------------------------------
%% @doc ClickHouse response handler module
%%
%% This module handles the processing of server response packets during
%% query execution. Based on captured traffic analysis, the server sends
%% all response packets in a single TCP transmission in this order:
%% 1. DATA packets (may be multiple)
%% 2. PROGRESS packets (optional)
%% 3. PROFILE packets (optional)
%% 4. PROFILE_EVENTS packets (optional)
%% 5. END_OF_STREAM packet (required)
%%
%% There are no unsolicited packets - all packets are sent as a response
%% to the client's query packet.
%% @end
%%%-------------------------------------------------------------------

-module(clickhouse_erl_response_handler).

-include_lib("kernel/include/logger.hrl").
-include("clickhouse_erl_protocol.hrl").

%% API
-export([
    handle_packet/3,
    handle_data_packet_with_callback/3,
    handle_data_packet_with_state/3,
    handle_totals_packet_with_state/3,
    handle_extremes_packet_with_state/3,
    handle_end_of_stream_packet_with_state/3,
    handle_progress_packet_with_state/3,
    handle_profile_packet_with_state/3,
    handle_profile_events_packet_with_state/3,
    create_initial_state/0,
    create_initial_state/1,
    create_initial_state/2,
    accumulate_data_block_callback/2
]).

-export_type([handler_state/0, callback_info/0, packet_type/0, query_type/0, handler_result/0]).

%% Type definitions
-type packet_type() :: integer().
-type query_type() :: select | insert.
-type handler_state() :: #{
    result_accumulator := result_accumulator(),
    column_metadata => [column_metadata()] | undefined,
    error_info := term() | undefined,
    protocol_version := non_neg_integer(),
    query_type := query_type(),
    start_time := integer() | undefined,
    rows_to_insert => non_neg_integer()
}.

-type handler_result() ::
    {ok, handler_state(), binary()}
    %% For backward compatibility
    | {ok, handler_state()}
    %% Added binary() for residual data
    | {ok, handler_state(), binary(), callback_info()}
    %% For streaming mode with updated CallbackInfo
    | {error, term(), binary()}
    %% For backward compatibility
    | {error, term()}
    %% Added binary() for residual data
    | {complete, query_result(), binary()}.

-type callback_info() ::
    #{
        on_data => function() | undefined,
        accumulator => term(),
        on_progress => function() | undefined,
        on_profile => function() | undefined,
        on_profile_events => function() | undefined
    }
    | undefined.

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Handle a packet received from the server with state management
%% Based on captured traffic, packets arrive in predictable order:
%% DATA -> PROGRESS -> PROFILE -> PROFILE_EVENTS -> END_OF_STREAM

-spec handle_packet(packet_type(), binary(), handler_state()) -> handler_result().
handle_packet(PacketType, Data, State) ->
    case PacketType of
        ?SERVER_DATA ->
            handle_data_packet_with_state(Data, State);
        ?SERVER_EXCEPTION ->
            handle_exception_packet_with_state(Data, State);
        ?SERVER_PROGRESS ->
            handle_progress_packet_with_state(Data, State);
        ?SERVER_END_OF_STREAM ->
            handle_end_of_stream_packet_with_state(Data, State);
        ?SERVER_PROFILE_EVENTS ->
            handle_profile_events_packet_with_state(Data, State);
        ?SERVER_PROFILE ->
            handle_profile_packet_with_state(Data, State);
        ?SERVER_TOTALS ->
            handle_totals_packet_with_state(Data, State);
        ?SERVER_EXTREMES ->
            handle_extremes_packet_with_state(Data, State);
        ?SERVER_LOG ->
            handle_log_packet_with_state(Data, State);
        ?SERVER_TABLE_COLUMNS ->
            handle_table_columns_packet_with_state(Data, State);
        _ ->
            {error, {protocol_error, {unknown_packet_type, PacketType}}}
    end.

%% @doc Create initial handler state for query execution
-spec create_initial_state() -> handler_state().
create_initial_state() ->
    % Default protocol version and SELECT query type
    create_initial_state(?PROTOCOL_VERSION, select).

%% @doc Create initial handler state for query execution with protocol version
-spec create_initial_state(non_neg_integer()) -> handler_state().
create_initial_state(ProtocolVersion) ->
    create_initial_state(ProtocolVersion, select).

%% @doc Create initial handler state for query execution with protocol version and query type
-spec create_initial_state(non_neg_integer(), query_type()) -> handler_state().
create_initial_state(ProtocolVersion, QueryType) ->
    #{
        result_accumulator => #result_accumulator{
            columns = [],
            rows = [],
            total_rows = 0,
            statistics = #{
                rows_read => 0,
                bytes_read => 0,
                elapsed_time => 0
            }
        },
        column_metadata => undefined,
        error_info => undefined,
        protocol_version => ProtocolVersion,
        query_type => QueryType,
        start_time => erlang:system_time(millisecond)
    }.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Check if an error is a truncated_data error (incomplete packet)
-spec is_truncated_data_error(term()) -> boolean().
is_truncated_data_error({truncated_data, _}) ->
    true;
is_truncated_data_error({invalid_compressed_block, too_small}) ->
    true;
is_truncated_data_error(_) ->
    false.

%% @doc Log decompression error based on error type
-spec log_decompression_error(term(), non_neg_integer()) -> ok.
log_decompression_error(DecompressError, DataSize) ->
    case is_truncated_data_error(DecompressError) of
        true ->
            ?LOG_DEBUG(
                "Incomplete compressed block (buffering): error=~p, data_size=~p",
                [DecompressError, DataSize]
            );
        false ->
            ?LOG_ERROR(
                "Failed to decompress block data: error=~p, data_size=~p",
                [DecompressError, DataSize]
            )
    end.

%% @doc Decode block data (BlockInfo + columns + rows) without temp table name
%% The temp table name has already been read before calling this function
-spec decode_block_data(binary(), non_neg_integer()) ->
    {ok, map(), binary()} | {error, term()}.
decode_block_data(Binary, ProtocolVersion) ->
    maybe
        {ok, BlockInfo, Rest1} ?= decode_block_info(Binary),
        {ok, NumColumns, Rest2} ?= clickhouse_erl_types_primitive:decode_varint(Rest1),
        {ok, NumRows, Rest3} ?= clickhouse_erl_types_primitive:decode_varint(Rest2),
        decode_columns_for_block(Rest3, NumColumns, NumRows, BlockInfo, ProtocolVersion)
    end.

%% @doc Decode block info structure
-spec decode_block_info(binary()) -> {ok, map(), binary()} | {error, term()}.
decode_block_info(Binary) ->
    decode_block_info_loop(Binary, #{is_overflows => false, bucket_num => -1}).

decode_block_info_loop(Binary, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Binary) of
        {ok, 0, Rest} ->
            {ok, Acc, Rest};
        {ok, 1, Rest} ->
            <<IsOverflowsByte:8, Rest2/binary>> = Rest,
            decode_block_info_loop(Rest2, Acc#{is_overflows => IsOverflowsByte > 0});
        {ok, 2, Rest} ->
            <<BucketNum:32/signed-little-integer, Rest2/binary>> = Rest,
            decode_block_info_loop(Rest2, Acc#{bucket_num => BucketNum});
        {ok, Other, _} ->
            {error, {unknown_block_info_field, Other}};
        Error ->
            Error
    end.

%% @doc Decode columns for a block
-spec decode_columns_for_block(
    binary(), non_neg_integer(), non_neg_integer(), map(), non_neg_integer()
) ->
    {ok, map(), binary()} | {error, term()}.
decode_columns_for_block(Binary, 0, 0, BlockInfo, _ProtocolVersion) ->
    DataBlock = #{
        info => BlockInfo,
        columns => 0,
        rows => 0,
        column_data => []
    },
    {ok, DataBlock, Binary};
decode_columns_for_block(Binary, NumColumns, NumRows, BlockInfo, ProtocolVersion) ->
    %% Use the existing column decoding logic from protocol_data_block module
    %% We need to call the internal decode_columns function
    %% For now, delegate to the full decode but reconstruct without temp table name
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),
    ReconstructedBinary = iolist_to_binary([
        TempTableName,
        encode_block_info_for_decode(BlockInfo),
        clickhouse_erl_types_primitive:encode_varint(NumColumns),
        clickhouse_erl_types_primitive:encode_varint(NumRows),
        Binary
    ]),
    case clickhouse_erl_protocol_data_block:decode(ReconstructedBinary, ProtocolVersion) of
        {ok, DataBlock, Rest} ->
            {ok, DataBlock, Rest};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Encode block info back to binary for re-decoding
-spec encode_block_info_for_decode(map()) -> iolist().
encode_block_info_for_decode(#{is_overflows := IsOverflows, bucket_num := BucketNum}) ->
    [
        clickhouse_erl_types_primitive:encode_varint(1),
        case IsOverflows of
            true -> <<1:8>>;
            false -> <<0:8>>
        end,
        clickhouse_erl_types_primitive:encode_varint(2),
        <<BucketNum:32/signed-little-integer>>,
        clickhouse_erl_types_primitive:encode_varint(0)
    ].

%% @doc Check if decompression should be applied based on compression options
%% Returns true if compression is enabled (not disabled), false otherwise
%% Requirements: 6.2, 6.3, 6.4
-spec should_decompress(CompressionOpts) -> boolean() when
    CompressionOpts :: clickhouse_erl_compression:compression_opts() | undefined.
should_decompress(undefined) ->
    false;
should_decompress(#{method := disabled}) ->
    false;
should_decompress(#{method := _Method}) ->
    true;
should_decompress(_) ->
    false.

%% @doc Safely invoke data callback with error handling
%% Wraps callback invocation in try...catch for crash handling
%% Requirements: 1.3, 5.1, 5.2
-spec invoke_data_callback(Callback, DataBlock, Acc) ->
    {ok, NewAcc} | {error, Reason}
when
    Callback :: fun((map(), term()) -> {ok, term()} | {error, term()}),
    DataBlock :: map(),
    Acc :: term(),
    NewAcc :: term(),
    Reason :: term().
invoke_data_callback(Callback, DataBlock, Acc) ->
    try
        case Callback(DataBlock, Acc) of
            {ok, NewAcc} ->
                {ok, NewAcc};
            {error, Reason} ->
                {error, Reason};
            InvalidReturn ->
                {error, {invalid_callback_return, InvalidReturn}}
        end
    catch
        Class:ErrorReason:Stacktrace ->
            {error, {callback_crashed, {Class, ErrorReason, Stacktrace}}}
    end.

%% @doc Handle Data packet with state management
%% Supports optional CallbackInfo parameter for streaming mode
%% Requirements: 1.1, 1.2, 6.2, 6.3, 6.4

-spec handle_data_packet_with_state(binary(), handler_state()) -> handler_result().
handle_data_packet_with_state(Data, State) ->
    handle_data_packet_with_state(Data, State, undefined).

-spec handle_data_packet_with_state(binary(), handler_state(), CompressionOpts) ->
    handler_result()
when
    CompressionOpts :: clickhouse_erl_compression:compression_opts() | undefined.
handle_data_packet_with_state(Data, State, CompressionOpts) ->
    ProtocolVersion = maps:get(protocol_version, State, ?PROTOCOL_VERSION),

    %% Decode and optionally decompress the data block
    case decode_and_decompress_block(Data, CompressionOpts, ProtocolVersion) of
        {ok, DataBlock, Remaining} ->
            UpdatedState = accumulate_data_block(DataBlock, State),
            {ok, UpdatedState, Remaining};
        {error, Reason, RestData} ->
            {error, Reason, RestData}
    end.

%% @doc Handle Data packet with callback support for streaming mode
%% This is the streaming-mode version that will be called from connection module
%% Requirements: 1.1, 1.2, 6.2, 6.3, 6.4
-spec handle_data_packet_with_callback(binary(), handler_state(), CallbackInfo) ->
    handler_result()
when
    CallbackInfo ::
        #{
            on_data := function(),
            accumulator := term(),
            compression_opts => clickhouse_erl_compression:compression_opts()
        }.
handle_data_packet_with_callback(Data, State, CallbackInfo) ->
    ProtocolVersion = maps:get(protocol_version, State, ?PROTOCOL_VERSION),
    CompressionOpts = maps:get(compression_opts, CallbackInfo, undefined),

    %% Decode and optionally decompress the data block
    case decode_and_decompress_block(Data, CompressionOpts, ProtocolVersion) of
        {ok, DataBlock, Remaining} ->
            %% Streaming mode - invoke callback
            #{on_data := Callback, accumulator := Acc} = CallbackInfo,
            case invoke_data_callback(Callback, DataBlock, Acc) of
                {ok, NewAcc} ->
                    NewCallbackInfo = CallbackInfo#{accumulator := NewAcc},
                    {ok, State, Remaining, NewCallbackInfo};
                {error, Reason} ->
                    {error, {callback_failed, Reason}, Remaining}
            end;
        {error, Reason, RestData} ->
            {error, Reason, RestData}
    end.

%% @doc Decode temp table name and optionally decompress block data
%% Extracted helper to avoid code duplication (DRY principle)
-spec decode_and_decompress_block(binary(), CompressionOpts, non_neg_integer()) ->
    {ok, map(), binary()} | {error, term(), binary()}
when
    CompressionOpts :: clickhouse_erl_compression:compression_opts() | undefined.
decode_and_decompress_block(Data, CompressionOpts, ProtocolVersion) ->
    %% CRITICAL: Temp table name is ALWAYS uncompressed, even when compression is enabled.
    %% Only the block data (BlockInfo + columns + rows) is compressed.

    %% Step 1: Read temp table name (uncompressed)
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, _TempTableName, RestAfterName} ->
            %% Step 2: Decompress block data if compression enabled
            case should_decompress(CompressionOpts) of
                true ->
                    decompress_and_decode_block(RestAfterName, ProtocolVersion, Data);
                false ->
                    decode_uncompressed_block(RestAfterName, ProtocolVersion)
            end;
        {error, Reason} ->
            {error, {protocol_error, {temp_table_decode_error, Reason}}, Data}
    end.

%% @doc Decompress and decode a compressed block
-spec decompress_and_decode_block(binary(), non_neg_integer(), binary()) ->
    {ok, map(), binary()} | {error, term(), binary()}.
decompress_and_decode_block(CompressedData, ProtocolVersion, OriginalData) ->
    decompress_and_apply(
        CompressedData,
        OriginalData,
        fun(Decompressed, RemainingAfterBlock) ->
            case decode_block_data(Decompressed, ProtocolVersion) of
                {ok, DataBlock, _Rest} ->
                    {ok, DataBlock, RemainingAfterBlock};
                {error, Reason} ->
                    {error, {protocol_error, {data_block_decode_error, Reason}}, Decompressed}
            end
        end,
        "Decompressed block data: ~p -> ~p bytes, ~p bytes remaining"
    ).

%% @doc Generic decompression helper that applies a function to decompressed data
%% This is the single source of truth for decompression logic.
-spec decompress_and_apply(
    binary(),
    binary(),
    fun((binary(), binary()) -> term()),
    string()
) -> term().
decompress_and_apply(CompressedData, OriginalData, ApplyFun, LogMsg) ->
    case clickhouse_erl_compression:decompress(CompressedData) of
        {ok, Decompressed, RemainingAfterBlock} ->
            ?LOG_DEBUG(LogMsg, [
                byte_size(CompressedData),
                byte_size(Decompressed),
                byte_size(RemainingAfterBlock)
            ]),
            ApplyFun(Decompressed, RemainingAfterBlock);
        {error, DecompressError} ->
            log_decompression_error(DecompressError, byte_size(CompressedData)),
            {error, {decompression_failed, DecompressError}, OriginalData}
    end.

%% @doc Helper to decompress and decode with state (for TOTALS/EXTREMES packets)
-spec decompress_and_decode_with_state(
    binary(),
    binary(),
    fun((binary(), binary(), non_neg_integer(), handler_state()) -> handler_result()),
    non_neg_integer(),
    handler_state(),
    string()
) -> handler_result().
decompress_and_decode_with_state(
    RestAfterName, OriginalData, DecodeFun, ProtocolVersion, State, LogMsg
) ->
    decompress_and_apply(
        RestAfterName,
        OriginalData,
        fun(Decompressed, RemainingAfterBlock) ->
            DecodeFun(Decompressed, RemainingAfterBlock, ProtocolVersion, State)
        end,
        LogMsg
    ).

%% @doc Decode an uncompressed block
-spec decode_uncompressed_block(binary(), non_neg_integer()) ->
    {ok, map(), binary()} | {error, term(), binary()}.
decode_uncompressed_block(BlockData, ProtocolVersion) ->
    case decode_block_data(BlockData, ProtocolVersion) of
        {ok, DataBlock, Rest} ->
            {ok, DataBlock, Rest};
        {error, Reason} ->
            {error, {protocol_error, {data_block_decode_error, Reason}}, BlockData}
    end.

%% @doc Handle Exception packet with state management

-spec handle_exception_packet_with_state(binary(), handler_state()) -> handler_result().
handle_exception_packet_with_state(Data, _State) ->
    case clickhouse_erl_protocol_exception_packet:decode(Data) of
        {ok, ExceptionInfo, Rest} ->
            {error, {server_exception, ExceptionInfo}, Rest};
        {error, Reason} ->
            %% Decode failed, return Data as Rest for buffering
            {error, Reason, Data}
    end.

%% @doc Handle Progress packet with state management

-spec handle_progress_packet_with_state(binary(), handler_state()) -> handler_result().
handle_progress_packet_with_state(Data, State) ->
    handle_progress_packet_with_state(Data, State, undefined).

-spec handle_progress_packet_with_state(
    binary(), handler_state(), callback_info() | undefined
) -> handler_result().
handle_progress_packet_with_state(Data, State, CallbackInfo) ->
    ProtocolVersion = maps:get(protocol_version, State, ?PROTOCOL_VERSION),
    handle_info_packet(
        Data,
        State,
        CallbackInfo,
        fun(D) -> decode_progress_packet(D, ProtocolVersion) end,
        on_progress,
        progress_decode_error,
        fun(Progress) ->
            Rows = maps:get(rows, Progress, 0),
            Bytes = maps:get(bytes, Progress, 0),
            TotalRows = maps:get(total_rows, Progress, 0),
            {
                "Progress received: ~p rows, ~p bytes, ~p total rows, ~p bytes remaining",
                [Rows, Bytes, TotalRows]
            }
        end
    ).

%% @doc Handle EndOfStream packet with state management
%% Supports both batch mode (no CallbackInfo) and streaming mode (with CallbackInfo)
%% Requirements: 2.3, 2.4, 9.1, 9.2, 9.4

-spec handle_end_of_stream_packet_with_state(binary(), handler_state()) -> handler_result().
handle_end_of_stream_packet_with_state(Data, State) ->
    handle_end_of_stream_packet_with_state(Data, State, undefined).

-spec handle_end_of_stream_packet_with_state(
    binary(), handler_state(), callback_info() | undefined
) -> handler_result().
handle_end_of_stream_packet_with_state(Data, State, CallbackInfo) ->
    %% Mark query as complete and return final result
    %% End of stream has no body, so Data IS the Rest

    %% Update state to mark query as complete
    CompletedState = State#{query_complete => true},

    %% Calculate elapsed time
    StartTime = maps:get(start_time, CompletedState, undefined),
    ElapsedTime =
        case StartTime of
            undefined -> 0;
            _ -> erlang:system_time(millisecond) - StartTime
        end,

    %% Return different result format based on query type
    QueryType = maps:get(query_type, CompletedState, select),
    case QueryType of
        insert ->
            %% For INSERT, return insert_result with rows_inserted and elapsed_time
            %% Use rows_to_insert from state (number of rows we sent)
            NumRows = maps:get(rows_to_insert, CompletedState, 0),
            InsertResult = #{
                rows_inserted => NumRows,
                elapsed_time => ElapsedTime
            },
            {complete, InsertResult, Data};
        select ->
            %% For SELECT, use unified 'data' key for both batch and streaming modes
            %% Requirements: 9.1, 9.2, 9.4
            %% CallbackInfo is always provided by connection module (never undefined)
            case CallbackInfo of
                #{accumulator := Acc} when is_record(Acc, result_accumulator) ->
                    %% Batch mode - accumulator is result_accumulator record
                    %% Convert to unified format with 'data' key
                    Result = #{
                        data => #{
                            columns => Acc#result_accumulator.columns,
                            rows => Acc#result_accumulator.rows
                        },
                        statistics => #{elapsed_time => ElapsedTime}
                    },
                    {complete, Result, Data};
                #{accumulator := FinalAcc} ->
                    %% Streaming mode - return user's accumulator under 'data' key
                    %% User knows they provided a callback, so they know what 'data' contains
                    Result = #{
                        data => FinalAcc,
                        statistics => #{elapsed_time => ElapsedTime}
                    },
                    {complete, Result, Data}
            end
    end.

%% @doc Handle ProfileEvents packet with state management
%% Structure: Count (VarInt), then Count * (Name (String), Value (UInt64))
-spec handle_profile_events_packet_with_state(binary(), handler_state()) -> handler_result().
handle_profile_events_packet_with_state(Data, State) ->
    handle_profile_events_packet_with_state(Data, State, undefined).

-spec handle_profile_events_packet_with_state(
    binary(), handler_state(), callback_info() | undefined
) -> handler_result().
handle_profile_events_packet_with_state(Data, State, CallbackInfo) ->
    case decode_profile_events(Data, maps:get(protocol_version, State, ?PROTOCOL_VERSION)) of
        {ok, Events, Rest} ->
            Rows = maps:get(rows, Events, 0),
            Columns = maps:get(columns, Events, 0),
            ?LOG_INFO("ProfileEvents received: ~p rows, ~p columns, ~p bytes remaining", [
                Rows,
                Columns,
                byte_size(Rest)
            ]),
            %% Invoke optional callback if provided
            case CallbackInfo of
                #{on_profile_events := Callback} when is_function(Callback) ->
                    %% Invoke callback (errors are non-fatal)
                    _ = clickhouse_erl_connection:invoke_optional_callback(Callback, Events),
                    {ok, State, Rest};
                _ ->
                    {ok, State, Rest}
            end;
        {error, Reason} ->
            {error, {protocol_error, {profile_events_decode_error, Reason}}, Data}
    end.

%% @doc Handle Profile packet with state management
%% Structure: Rows(V), Blocks(V), Bytes(V), AppliedLimit(1),
%% RowsBeforeLimit(V), CalcRowsBeforeLimit(1)
-spec handle_profile_packet_with_state(binary(), handler_state()) -> handler_result().
handle_profile_packet_with_state(Data, State) ->
    handle_profile_packet_with_state(Data, State, undefined).

-spec handle_profile_packet_with_state(
    binary(), handler_state(), callback_info() | undefined
) -> handler_result().
handle_profile_packet_with_state(Data, State, CallbackInfo) ->
    handle_info_packet(
        Data,
        State,
        CallbackInfo,
        fun decode_profile_packet/1,
        on_profile,
        profile_decode_error,
        fun(Profile) ->
            Rows = maps:get(rows, Profile, 0),
            Blocks = maps:get(blocks, Profile, 0),
            Bytes = maps:get(bytes, Profile, 0),
            {
                "Profile received: ~p rows, ~p blocks, ~p bytes, ~p bytes remaining",
                [Rows, Blocks, Bytes]
            }
        end
    ).

%% @doc Handle Totals packet with state management
%% Structure: DataBlock
%% Requirements: 6.2, 6.3, 6.4
-spec handle_totals_packet_with_state(binary(), handler_state()) -> handler_result().
handle_totals_packet_with_state(Data, State) ->
    handle_totals_packet_with_state(Data, State, undefined).

-spec handle_totals_packet_with_state(binary(), handler_state(), CompressionOpts) ->
    handler_result()
when
    CompressionOpts :: clickhouse_erl_compression:compression_opts() | undefined.
handle_totals_packet_with_state(Data, State, CompressionOpts) ->
    ProtocolVersion = maps:get(protocol_version, State, ?PROTOCOL_VERSION),

    %% CRITICAL: Temp table name is ALWAYS uncompressed, even when compression is enabled.
    %% Only the block data (BlockInfo + columns + rows) is compressed.
    %% This matches the DATA packet handling pattern.

    %% Step 1: Read temp table name (uncompressed)
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, _TempTableName, RestAfterName} ->
            %% Step 2: Decompress block data if compression enabled
            case should_decompress(CompressionOpts) of
                true ->
                    decompress_and_decode_with_state(
                        RestAfterName,
                        Data,
                        fun decode_totals_block/4,
                        ProtocolVersion,
                        State,
                        "Decompressed TOTALS packet: ~p -> ~p bytes, ~p bytes remaining"
                    );
                false ->
                    %% No compression - decode block data directly
                    decode_totals_block(RestAfterName, <<>>, ProtocolVersion, State)
            end;
        {error, Reason} ->
            {error, {protocol_error, {temp_table_decode_error, Reason}}, Data}
    end.

%% @doc Decode totals block after optional decompression
-spec decode_totals_block(binary(), binary(), non_neg_integer(), handler_state()) ->
    handler_result().
decode_totals_block(DecompressedData, RemainingAfterBlock, ProtocolVersion, State) ->
    case clickhouse_erl_protocol_data_block:decode(DecompressedData, ProtocolVersion) of
        {ok, _Block, _Rest} ->
            ?LOG_DEBUG("Processed Totals packet, remaining bytes: ~p", [
                byte_size(RemainingAfterBlock)
            ]),
            {ok, State, RemainingAfterBlock};
        {error, Reason} ->
            {error, {protocol_error, {totals_decode_error, Reason}}, DecompressedData}
    end.

%% @doc Handle Extremes packet with state management
%% Structure: DataBlock
%% Requirements: 6.2, 6.3, 6.4
-spec handle_extremes_packet_with_state(binary(), handler_state()) -> handler_result().
handle_extremes_packet_with_state(Data, State) ->
    handle_extremes_packet_with_state(Data, State, undefined).

-spec handle_extremes_packet_with_state(binary(), handler_state(), CompressionOpts) ->
    handler_result()
when
    CompressionOpts :: clickhouse_erl_compression:compression_opts() | undefined.
handle_extremes_packet_with_state(Data, State, CompressionOpts) ->
    ProtocolVersion = maps:get(protocol_version, State, ?PROTOCOL_VERSION),

    %% CRITICAL: Temp table name is ALWAYS uncompressed, even when compression is enabled.
    %% Only the block data (BlockInfo + columns + rows) is compressed.
    %% This matches the DATA packet handling pattern.

    %% Step 1: Read temp table name (uncompressed)
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, _TempTableName, RestAfterName} ->
            %% Step 2: Decompress block data if compression enabled
            case should_decompress(CompressionOpts) of
                true ->
                    decompress_and_decode_with_state(
                        RestAfterName,
                        Data,
                        fun decode_extremes_block/4,
                        ProtocolVersion,
                        State,
                        "Decompressed EXTREMES packet: ~p -> ~p bytes, ~p bytes remaining"
                    );
                false ->
                    %% No compression - decode block data directly
                    decode_extremes_block(RestAfterName, <<>>, ProtocolVersion, State)
            end;
        {error, Reason} ->
            {error, {protocol_error, {temp_table_decode_error, Reason}}, Data}
    end.

%% @doc Decode extremes block after optional decompression
-spec decode_extremes_block(binary(), binary(), non_neg_integer(), handler_state()) ->
    handler_result().
decode_extremes_block(DecompressedData, RemainingAfterBlock, ProtocolVersion, State) ->
    case clickhouse_erl_protocol_data_block:decode(DecompressedData, ProtocolVersion) of
        {ok, _Block, _Rest} ->
            ?LOG_DEBUG("Processed Extremes packet, remaining bytes: ~p", [
                byte_size(RemainingAfterBlock)
            ]),
            {ok, State, RemainingAfterBlock};
        {error, Reason} ->
            {error, {protocol_error, {extremes_decode_error, Reason}}, DecompressedData}
    end.

%% @doc Handle a Log packet (Type 10) with state management
-spec handle_log_packet_with_state(binary(), handler_state()) -> handler_result().
handle_log_packet_with_state(Data, State) ->
    case decode_log_packet(Data) of
        {ok, _Result, Rest} ->
            {ok, State, Rest};
        {error, Reason} ->
            {error, Reason, Data}
    end.

%% @doc Handle a TableColumns packet (Type 11) with state management
-spec handle_table_columns_packet_with_state(binary(), handler_state()) -> handler_result().
handle_table_columns_packet_with_state(Data, State) ->
    case decode_table_columns_packet(Data) of
        {ok, _Result, Rest} ->
            {ok, State, Rest};
        {error, Reason} ->
            {error, Reason, Data}
    end.

%% @doc Generic handler for info packets (progress, profile, etc.)
%% Reduces code duplication between similar packet handlers
-spec handle_info_packet(
    binary(),
    handler_state(),
    callback_info() | undefined,
    fun((binary()) -> {ok, map(), binary()} | {error, term()}),
    atom(),
    atom(),
    fun((map()) -> {string(), list()})
) -> handler_result().
handle_info_packet(Data, State, CallbackInfo, DecodeFun, CallbackType, ErrorType, LogFun) ->
    case DecodeFun(Data) of
        {ok, Result, Rest} ->
            {LogMsg, LogArgs} = LogFun(Result),
            ?LOG_INFO(LogMsg, LogArgs ++ [byte_size(Rest)]),
            invoke_optional_callback_if_present(CallbackInfo, CallbackType, Result),
            {ok, State, Rest};
        {error, Reason} ->
            {error, {protocol_error, {ErrorType, Reason}}, Data}
    end.

%% @doc Decode server log packet data
-spec decode_log_packet(binary()) -> {ok, term(), binary()} | {error, term()}.
decode_log_packet(Binary) ->
    %% 1. Log tag (String)
    case clickhouse_erl_types_primitive:decode_string(Binary) of
        {ok, Tag, Rest1} ->
            ?LOG_DEBUG("Received server log tag: ~s", [Tag]),
            %% 2. Data block
            FakeBinary = <<0, Rest1/binary>>,
            case clickhouse_erl_protocol_data_block:decode(FakeBinary) of
                {ok, LogBlock, Rest2} ->
                    {ok, LogBlock, Rest2};
                {error, Reason} ->
                    {error, {decoding_failed, {server_log_block, Reason}}}
            end;
        {error, Reason} ->
            {error, {decoding_failed, {server_log_tag, Reason}}}
    end.

%% @doc Decode table columns packet data
-spec decode_table_columns_packet(binary()) -> {ok, term(), binary()} | {error, term()}.
decode_table_columns_packet(Binary) ->
    %% 1. External table name (String)
    case clickhouse_erl_types_primitive:decode_string(Binary) of
        {ok, TableName, Rest1} ->
            %% 2. Columns metadata (String)
            case clickhouse_erl_types_primitive:decode_string(Rest1) of
                {ok, ColumnsMetadata, Rest2} ->
                    {ok, #{table => TableName, columns => ColumnsMetadata}, Rest2};
                {error, Reason} ->
                    {error, {decoding_failed, {table_columns_metadata, Reason}}}
            end;
        {error, Reason} ->
            {error, {decoding_failed, {table_columns_name, Reason}}}
    end.

%% @doc Decode progress packet data
-spec decode_progress_packet(binary(), integer()) -> {ok, map(), binary()} | {error, term()}.
decode_progress_packet(Data, ProtocolVersion) ->
    try
        {ok, Rows, R1} = clickhouse_erl_types_primitive:decode_varint(Data),
        {ok, Bytes, R2} = clickhouse_erl_types_primitive:decode_varint(R1),
        {ok, TotalRows, R3} = clickhouse_erl_types_primitive:decode_varint(R2),
        {ok, WrittenRows, R4} = clickhouse_erl_types_primitive:decode_varint(R3),
        {ok, WrittenBytes, R5} = clickhouse_erl_types_primitive:decode_varint(R4),

        %% Check for elapsed_ns (ClientTimeMicroseconds?) if revision >= 54449
        {ElapsedNs, Rest} =
            case ProtocolVersion >= 54449 of
                true ->
                    {ok, Val, R6} = clickhouse_erl_types_primitive:decode_varint(R5),
                    {Val, R6};
                false ->
                    {0, R5}
            end,

        Progress = #{
            rows => Rows,
            bytes => Bytes,
            total_rows => TotalRows,
            written_rows => WrittenRows,
            written_bytes => WrittenBytes,
            elapsed_ns => ElapsedNs
        },
        {ok, Progress, Rest}
    catch
        _:Reason ->
            {error, {progress_decode_failed, Reason}}
    end.

decode_profile_packet(Data) ->
    try
        {ok, Rows, R1} = clickhouse_erl_types_primitive:decode_varint(Data),
        {ok, Blocks, R2} = clickhouse_erl_types_primitive:decode_varint(R1),
        {ok, Bytes, R3} = clickhouse_erl_types_primitive:decode_varint(R2),
        <<AppliedLimit:8, R4/binary>> = R3,
        {ok, RowsBeforeLimit, R5} = clickhouse_erl_types_primitive:decode_varint(R4),
        <<CalcRowsBeforeLimit:8, Rest/binary>> = R5,

        Profile = #{
            rows => Rows,
            blocks => Blocks,
            bytes => Bytes,
            applied_limit => AppliedLimit > 0,
            rows_before_limit => RowsBeforeLimit,
            calculated_rows_before_limit => CalcRowsBeforeLimit > 0
        },
        {ok, Profile, Rest}
    catch
        _:Reason ->
            {error, {profile_decode_failed, Reason}}
    end.

decode_profile_events(Data, ProtocolVersion) ->
    %% ProfileEvents structure: String (Host?) + DataBlock
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, _HostName, Rest1} ->
            clickhouse_erl_protocol_data_block:decode(Rest1, ProtocolVersion);
        {error, Reason} ->
            {error, {profile_events_decode_failed, Reason}}
    end.

%% @doc Invoke optional callback if present in callback info.
-spec invoke_optional_callback_if_present(
    callback_info() | undefined, atom(), term()
) -> ok.
invoke_optional_callback_if_present(CallbackInfo, CallbackKey, Data) ->
    case CallbackInfo of
        #{CallbackKey := Callback} when is_function(Callback) ->
            %% Invoke callback (errors are non-fatal)
            _ = clickhouse_erl_connection:invoke_optional_callback(Callback, Data),
            ok;
        _ ->
            ok
    end.

%% @doc Accumulate data block results into handler state
-spec accumulate_data_block(map(), handler_state()) -> handler_state().
accumulate_data_block(DataBlock, State) ->
    #{result_accumulator := Accumulator} = State,

    %% Extract column information from the data block
    ColumnData = maps:get(column_data, DataBlock, []),
    NumRows = maps:get(rows, DataBlock, 0),

    %% Convert column data to the expected format for query results
    Columns = lists:map(
        fun(Col) ->
            #{
                name => maps:get(name, Col, <<>>),
                type => maps:get(type, Col, <<>>)
            }
        end,
        ColumnData
    ),

    %% Extract row data from columns
    Rows =
        case {NumRows, ColumnData} of
            {0, _} ->
                % No rows to extract
                [];
            {_, []} ->
                % No columns, no rows
                [];
            {_, _} ->
                %% Convert column-oriented data to row-oriented data
                extract_rows_from_columns(ColumnData, NumRows)
        end,

    %% For now, we'll just accumulate the column metadata from the first non-empty block
    %% and accumulate all rows
    UpdatedColumns =
        case {Accumulator#result_accumulator.columns, Columns} of
            % First block with columns
            {[], NewCols} when NewCols =/= [] -> NewCols;
            % Keep existing columns
            {ExistingCols, _} -> ExistingCols
        end,

    %% Accumulate rows
    UpdatedRows = Accumulator#result_accumulator.rows ++ Rows,

    %% Update the accumulator
    UpdatedAccumulator = Accumulator#result_accumulator{
        columns = UpdatedColumns,
        rows = UpdatedRows,
        total_rows = Accumulator#result_accumulator.total_rows + NumRows
    },

    %% Return updated state
    State#{result_accumulator => UpdatedAccumulator}.

%% @doc Callback-compatible version of accumulate_data_block for batch mode
%% This function is used as the default on_data callback when no callback is provided
%% It accumulates data blocks into a result_accumulator structure
%% Requirements: 1.5, 3.1, 4.1
-spec accumulate_data_block_callback(map(), term()) -> {ok, term()}.
accumulate_data_block_callback(DataBlock, Acc) ->
    %% Initialize accumulator if undefined (first call)
    InitialAcc =
        case Acc of
            undefined ->
                #result_accumulator{
                    columns = [],
                    rows = [],
                    total_rows = 0,
                    statistics = #{
                        rows_read => 0,
                        bytes_read => 0,
                        elapsed_time => 0
                    }
                };
            _ ->
                Acc
        end,

    %% Extract column information from the data block
    ColumnData = maps:get(column_data, DataBlock, []),
    NumRows = maps:get(rows, DataBlock, 0),

    %% Convert column data to the expected format for query results
    Columns = lists:map(
        fun(Col) ->
            #{
                name => maps:get(name, Col, <<>>),
                type => maps:get(type, Col, <<>>)
            }
        end,
        ColumnData
    ),

    %% Extract row data from columns
    Rows =
        case {NumRows, ColumnData} of
            {0, _} ->
                % No rows to extract
                [];
            {_, []} ->
                % No columns, no rows
                [];
            {_, _} ->
                %% Convert column-oriented data to row-oriented data
                extract_rows_from_columns(ColumnData, NumRows)
        end,

    %% For now, we'll just accumulate the column metadata from the first non-empty block
    %% and accumulate all rows
    UpdatedColumns =
        case {InitialAcc#result_accumulator.columns, Columns} of
            % First block with columns
            {[], NewCols} when NewCols =/= [] -> NewCols;
            % Keep existing columns
            {ExistingCols, _} -> ExistingCols
        end,

    %% Accumulate rows
    UpdatedRows = InitialAcc#result_accumulator.rows ++ Rows,

    %% Update the accumulator
    UpdatedAccumulator = InitialAcc#result_accumulator{
        columns = UpdatedColumns,
        rows = UpdatedRows,
        total_rows = InitialAcc#result_accumulator.total_rows + NumRows
    },

    %% Return updated accumulator wrapped in {ok, _} tuple
    {ok, UpdatedAccumulator}.

%% @doc Extract rows from column-oriented data
-spec extract_rows_from_columns([column_data()], non_neg_integer()) -> [list()].
extract_rows_from_columns(ColumnData, NumRows) when is_list(ColumnData), ColumnData =/= [] ->
    %% Get the data arrays from each column
    ColumnArrays = lists:map(
        fun(Col) ->
            maps:get(data, Col, [])
        end,
        ColumnData
    ),

    %% Convert from column-oriented to row-oriented
    %% Each row is a list of values, one from each column
    lists:map(
        fun(RowIndex) ->
            lists:map(
                fun(ColumnArray) ->
                    case RowIndex =< length(ColumnArray) of
                        true -> lists:nth(RowIndex, ColumnArray);
                        % Handle missing data gracefully
                        false -> undefined
                    end
                end,
                ColumnArrays
            )
        end,
        lists:seq(1, NumRows)
    ).
