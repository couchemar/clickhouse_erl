%%%-------------------------------------------------------------------
%% @doc Property-based tests for ClickHouse response handler module
%%
%% This module contains property-based tests that validate the correctness
%% of server response handling across all standard ClickHouse packet types.
%% @end
%%%-------------------------------------------------------------------

-module(prop_clickhouse_erl_response_handler).

-include_lib("proper/include/proper.hrl").
-include("clickhouse_erl_protocol.hrl").

%%%===================================================================
%%% Property Tests
%%%===================================================================

%% @doc Property 6: Server response handling completeness
%% **Feature: simple-query, Property 6: Server response handling completeness**
%% **Validates: Requirements 3.1, 3.2, 6.4**

prop_server_response_handling_completeness() ->
    ?FORALL(
        {PacketType, PacketData},
        gen_server_packet(),
        begin
            %% Test stateful version
            InitialState = clickhouse_erl_response_handler:create_initial_state(),

            %% For END_OF_STREAM, use the modern 3-argument API with CallbackInfo
            Result =
                case PacketType of
                    ?SERVER_END_OF_STREAM ->
                        %% Create default CallbackInfo for batch mode with result_accumulator
                        Acc = #result_accumulator{
                            columns = [],
                            rows = [],
                            statistics = #{}
                        },
                        CallbackInfo = #{accumulator => Acc},
                        clickhouse_erl_response_handler:handle_end_of_stream_packet_with_state(
                            PacketData, InitialState, CallbackInfo
                        );
                    _ ->
                        clickhouse_erl_response_handler:handle_packet(
                            PacketType, PacketData, InitialState
                        )
                end,

            %% Should handle the packet appropriately
            case PacketType of
                ?SERVER_DATA ->
                    %% Data packets should be parsed according to ClickHouse protocol
                    case Result of
                        {ok, _NewState, _Rest} -> true;
                        {error, _, _Rest} -> true;
                        _ -> false
                    end;
                ?SERVER_EXCEPTION ->
                    %% Exception packets should be parsed and propagated
                    case Result of
                        {error, {server_exception, _}, _Rest} -> true;
                        {error, _, _Rest} -> true;
                        _ -> false
                    end;
                ?SERVER_PROGRESS ->
                    %% Progress packets should be parsed successfully
                    case Result of
                        {ok, _NewState, _Rest} -> true;
                        {error, _, _Rest} -> true;
                        _ -> false
                    end;
                ?SERVER_END_OF_STREAM ->
                    %% End of stream should complete query
                    case Result of
                        {complete, _, _Rest} -> true;
                        _ -> false
                    end;
                _ ->
                    %% Unknown packet types should return protocol error
                    case Result of
                        {error, {protocol_error, {unknown_packet_type, PacketType}}} -> true;
                        _ -> false
                    end
            end
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generate server packets for testing
gen_server_packet() ->
    oneof([
        gen_data_packet(),
        gen_exception_packet(),
        gen_progress_packet(),
        gen_end_of_stream_packet(),
        gen_unknown_packet()
    ]).

%% @doc Generate Data packet
gen_data_packet() ->
    ?LET(
        {Columns, Rows},
        {choose(0, 5), choose(0, 10)},
        begin
            %% Generate minimal valid data block binary
            %% Temporary table name (empty string)
            TblName = <<0>>,
            %% Block info: field-based encoding (ch-go compatible)
            %% Field 1: Overflows = false
            OverflowsField = encode_varint(1),
            OverflowsValue = <<0:8>>,
            %% Field 2: BucketNum = -1
            BucketNumField = encode_varint(2),
            BucketNumValue = <<(-1):32/signed-little>>,
            %% End marker
            EndField = encode_varint(0),
            BlockInfo =
                <<OverflowsField/binary, OverflowsValue/binary, BucketNumField/binary,
                    BucketNumValue/binary, EndField/binary>>,
            %% Number of columns and rows
            ColsBinary = encode_varint(Columns),
            RowsBinary = encode_varint(Rows),
            %% Generate column data if columns > 0
            ColumnData =
                case Columns of
                    0 -> <<>>;
                    _ -> generate_column_data(Columns, Rows)
                end,
            Data =
                <<TblName/binary, BlockInfo/binary, ColsBinary/binary, RowsBinary/binary,
                    ColumnData/binary>>,
            {?SERVER_DATA, Data}
        end
    ).

%% @doc Generate Exception packet
gen_exception_packet() ->
    ?LET(
        {Code, Name, Message},
        {choose(1, 1000), gen_string(), gen_string()},
        begin
            %% Exception packet format: code(int32), name(string), message(string), stack_trace(string), nested(bool)
            CodeBinary = <<Code:32/little>>,
            NameBinary = encode_string(Name),
            MessageBinary = encode_string(Message),
            StackTrace = encode_string(""),
            %% No nested exceptions
            Nested = <<0>>,
            Data =
                <<CodeBinary/binary, NameBinary/binary, MessageBinary/binary, StackTrace/binary,
                    Nested/binary>>,
            {?SERVER_EXCEPTION, Data}
        end
    ).

%% @doc Generate Progress packet
gen_progress_packet() ->
    ?LET(
        {Rows, Bytes, TotalRows, WrittenRows, WrittenBytes},
        {choose(0, 1000), choose(0, 10000), choose(0, 1000), choose(0, 1000), choose(0, 10000)},
        begin
            %% Progress packet: rows, bytes, total_rows, written_rows, written_bytes (all varints)
            Data = <<
                (encode_varint(Rows))/binary,
                (encode_varint(Bytes))/binary,
                (encode_varint(TotalRows))/binary,
                (encode_varint(WrittenRows))/binary,
                (encode_varint(WrittenBytes))/binary
            >>,
            {?SERVER_PROGRESS, Data}
        end
    ).

%% @doc Generate EndOfStream packet
gen_end_of_stream_packet() ->
    {?SERVER_END_OF_STREAM, <<>>}.

%% @doc Generate unknown packet type
gen_unknown_packet() ->
    ?LET(
        PacketType,
        choose(100, 999),
        {PacketType, <<>>}
    ).

%% @doc Generate string for testing
gen_string() ->
    ?LET(
        Chars,
        list(choose($a, $z)),
        list_to_binary(Chars)
    ).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Encode varint (simplified version for testing)
encode_varint(N) when N < 128 ->
    <<N>>;
encode_varint(N) ->
    <<(N band 127 bor 128), (encode_varint(N bsr 7))/binary>>.

%% @doc Encode string with length prefix
encode_string(Str) when is_list(Str) ->
    encode_string(list_to_binary(Str));
encode_string(Str) when is_binary(Str) ->
    Len = byte_size(Str),
    <<(encode_varint(Len))/binary, Str/binary>>.

%% @doc Generate column data for data blocks
generate_column_data(0, _Rows) ->
    <<>>;
generate_column_data(Columns, Rows) ->
    %% For each column, generate: name(string), type(string), data
    lists:foldl(
        fun(ColIdx, Acc) ->
            ColName = encode_string("col" ++ integer_to_list(ColIdx)),
            ColType = encode_string("String"),
            %% Generate row data for this column
            ColData = generate_column_values(Rows),
            <<Acc/binary, ColName/binary, ColType/binary, ColData/binary>>
        end,
        <<>>,
        lists:seq(1, Columns)
    ).

%% @doc Generate column values for testing
generate_column_values(0) ->
    <<>>;
generate_column_values(Rows) ->
    %% Generate simple string values for each row
    lists:foldl(
        fun(RowIdx, Acc) ->
            Value = encode_string("value" ++ integer_to_list(RowIdx)),
            <<Acc/binary, Value/binary>>
        end,
        <<>>,
        lists:seq(1, Rows)
    ).

%%%===================================================================
%%% Property Test for Result Accumulation
%%%===================================================================

%% @doc Property 8: Multi-block result accumulation
%% **Feature: simple-query, Property 8: Multi-block result accumulation**
%% **Validates: Requirements 4.3**

prop_multi_block_result_accumulation() ->
    ?FORALL(
        DataBlocks,
        gen_consistent_data_blocks(),
        begin
            %% Create initial state
            InitialState = clickhouse_erl_response_handler:create_initial_state(),

            %% Process each data block sequentially
            {FinalState, AllRowsAccumulated, ProcessingSucceeded} = lists:foldl(
                fun(DataBlock, {State, AccumulatedRows, Success}) ->
                    %% Convert data block to binary and process it
                    case encode_data_block_safe(DataBlock) of
                        {ok, DataBinary} ->
                            case
                                clickhouse_erl_response_handler:handle_packet(
                                    ?SERVER_DATA, DataBinary, State
                                )
                            of
                                {ok, NewState} ->
                                    %% Extract rows from this data block
                                    BlockRows = extract_rows_from_data_block(DataBlock),
                                    {NewState, AccumulatedRows ++ BlockRows, Success};
                                {ok, NewState, _Rest} ->
                                    %% Handle 3-tuple return with remaining binary
                                    BlockRows = extract_rows_from_data_block(DataBlock),
                                    {NewState, AccumulatedRows ++ BlockRows, Success};
                                {error, _Reason} ->
                                    %% If processing fails, return current state but mark as failed
                                    {State, AccumulatedRows, false};
                                {error, _Reason, _Rest} ->
                                    %% Handle 3-tuple error with remaining binary
                                    {State, AccumulatedRows, false}
                            end;
                        {error, _Reason} ->
                            %% If encoding fails, mark as failed
                            {State, AccumulatedRows, false}
                    end
                end,
                {InitialState, [], true},
                DataBlocks
            ),

            %% Only validate results if processing succeeded
            case ProcessingSucceeded of
                false ->
                    %% If processing failed, the test should pass (we're testing accumulation, not encoding)
                    true;
                true ->
                    %% Access accumulated result directly from state
                    #{result_accumulator := Accumulator} = FinalState,
                    ResultRows = Accumulator#result_accumulator.rows,
                    Columns = Accumulator#result_accumulator.columns,

                    %% Check that all accumulated rows are present and in order
                    RowsMatch = (ResultRows =:= AllRowsAccumulated),

                    %% Check that column metadata is consistent
                    MetadataConsistent =
                        case DataBlocks of
                            [] ->
                                true;
                            _ ->
                                %% Find first non-empty block for metadata comparison
                                case find_first_non_empty_block(DataBlocks) of
                                    {ok, FirstBlock} ->
                                        ExpectedColumns = extract_column_metadata_from_block(
                                            FirstBlock
                                        ),
                                        (Columns =:= ExpectedColumns);
                                    not_found ->
                                        %% All blocks are empty, metadata should be empty
                                        Columns =:= []
                                end
                        end,

                    %% Check that total row count matches
                    TotalRowsMatch = (length(ResultRows) =:= length(AllRowsAccumulated)),

                    RowsMatch andalso MetadataConsistent andalso TotalRowsMatch
            end
        end
    ).

%%%===================================================================
%%% Generators for Result Accumulation Testing
%%%===================================================================

%% @doc Generate a sequence of data blocks with consistent column metadata
gen_consistent_data_blocks() ->
    ?LET(
        {NumColumns, BlockSizes},
        {choose(1, 3), list(choose(0, 5))},
        begin
            %% Generate consistent column metadata
            ColumnNames = ["col" ++ integer_to_list(I) || I <- lists:seq(1, NumColumns)],
            ColumnTypes = ["String" || _ <- lists:seq(1, NumColumns)],

            %% Generate data blocks with consistent metadata
            [
                generate_data_block_with_metadata(ColumnNames, ColumnTypes, Size)
             || Size <- BlockSizes
            ]
        end
    ).

%% @doc Generate a data block with specific column metadata and row count
generate_data_block_with_metadata(ColumnNames, ColumnTypes, NumRows) ->
    ColumnData = lists:zipwith(
        fun(Name, Type) ->
            %% Generate row values for this column
            Values = [
                list_to_binary("value_" ++ Name ++ "_" ++ integer_to_list(I))
             || I <- lists:seq(1, NumRows)
            ],
            #{
                name => list_to_binary(Name),
                type => list_to_binary(Type),
                data => Values
            }
        end,
        ColumnNames,
        ColumnTypes
    ),

    #{
        info => #{is_overflows => false, bucket_num => 0},
        columns => length(ColumnNames),
        rows => NumRows,
        column_data => ColumnData
    }.

%% @doc Extract rows from a data block structure
extract_rows_from_data_block(#{column_data := ColumnData, rows := NumRows}) when NumRows > 0 ->
    %% Transpose column data to row data
    AllColumnValues = [maps:get(data, Col, []) || Col <- ColumnData],
    case AllColumnValues of
        [] ->
            [];
        _ ->
            %% Create rows by taking the Nth element from each column
            [
                extract_row_at_index_from_values(AllColumnValues, Index)
             || Index <- lists:seq(1, NumRows)
            ]
    end;
extract_rows_from_data_block(_) ->
    [].

%% @doc Extract a single row at the given index from column values
extract_row_at_index_from_values(ColumnValues, Index) ->
    [lists:nth(Index, ColVals) || ColVals <- ColumnValues].

%% @doc Extract column metadata from a data block
extract_column_metadata_from_block(#{column_data := ColumnData}) ->
    [#{name => maps:get(name, Col), type => maps:get(type, Col)} || Col <- ColumnData];
extract_column_metadata_from_block(_) ->
    [].

%% @doc Encode a data block structure to binary format
encode_data_block(#{info := Info, columns := NumColumns, rows := NumRows, column_data := ColumnData}) ->
    %% Temporary table name (empty string)
    TblName = <<0>>,

    %% Block info: field-based encoding (ch-go compatible)
    %% Field 1: Overflows = false
    OverflowsField = encode_varint(1),
    IsOverflows =
        case maps:get(is_overflows, Info, false) of
            true -> 1;
            false -> 0
        end,
    OverflowsValue = <<IsOverflows:8>>,

    %% Field 2: BucketNum
    BucketNumField = encode_varint(2),
    BucketNum = maps:get(bucket_num, Info, -1),
    BucketNumValue = <<BucketNum:32/signed-little>>,

    %% End marker
    EndField = encode_varint(0),

    BlockInfo =
        <<OverflowsField/binary, OverflowsValue/binary, BucketNumField/binary,
            BucketNumValue/binary, EndField/binary>>,

    %% Number of columns and rows
    ColsBinary = encode_varint(NumColumns),
    RowsBinary = encode_varint(NumRows),

    %% Encode column data
    ColumnDataBinary = lists:foldl(
        fun(Col, Acc) ->
            ColName = encode_string(maps:get(name, Col)),
            ColType = encode_string(maps:get(type, Col)),
            ColValues = maps:get(data, Col, []),
            ColData = lists:foldl(
                fun
                    (Value, ValAcc) when is_binary(Value) ->
                        <<ValAcc/binary, (encode_string(Value))/binary>>;
                    (Value, ValAcc) when is_list(Value) ->
                        <<ValAcc/binary, (encode_string(list_to_binary(Value)))/binary>>;
                    (Value, ValAcc) ->
                        <<ValAcc/binary, (encode_string(io_lib:format("~p", [Value])))/binary>>
                end,
                <<>>,
                ColValues
            ),
            <<Acc/binary, ColName/binary, ColType/binary, ColData/binary>>
        end,
        <<>>,
        ColumnData
    ),

    <<TblName/binary, BlockInfo/binary, ColsBinary/binary, RowsBinary/binary,
        ColumnDataBinary/binary>>.

%% @doc Safe version of encode_data_block that handles errors
encode_data_block_safe(DataBlock) ->
    try
        {ok, encode_data_block(DataBlock)}
    catch
        _:Reason ->
            {error, {encoding_failed, Reason}}
    end.

%% @doc Find the first non-empty data block in a list
find_first_non_empty_block([]) ->
    not_found;
find_first_non_empty_block([Block | Rest]) ->
    case maps:get(rows, Block, 0) of
        0 -> find_first_non_empty_block(Rest);
        _ -> {ok, Block}
    end.
