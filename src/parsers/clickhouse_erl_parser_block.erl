%% @doc Parser for DATA (1), TOTALS (80), EXTREMES (81), and PROFILE_EVENTS (13) packets.
%%
%% The BLOCK packet contains columnar data from query results.
%% It includes a temporary table name, block metadata, and column data.
%%
%% Emitted events:
%% - `{data, temp_table_name, Name}` - String temporary table name
%% - `{data, block_info, BlockInfo}` - Map with is_overflows and bucket_num
%% - `{data, num_columns, Count}` - Varint number of columns
%% - `{data, num_rows, Count}` - Varint number of rows
%% - `{data, column, ColumnMeta}` - Map with name and type for each column
%% - `{data, column_data, ColumnData}` - Parsed column data (rows as list of values)
%%
%% The parser processes fields sequentially:
%% 1. temp_table_name (varint-prefixed UTF-8 string)
%% 2. block_info (BlockInfo structure with is_overflows and bucket_num)
%% 3. num_columns (varint)
%% 4. num_rows (varint)
%% 5. For each column:
%%    a. column name (varint-prefixed UTF-8 string)
%%    b. column type (varint-prefixed UTF-8 string)
%%    c. custom serialization flag (if supported by protocol version)
%%    d. column data (rows of values, type-specific encoding)
%%
%% Column data is parsed using type-specific decoders from clickhouse_erl_types_* modules.
%% The parser handles all ClickHouse types including primitives, temporal, extended integers,
%% decimals, enums, network types, special types, and complex types (Array, Tuple, Nullable, etc.).
%%
%% Version-dependent features are determined by checking feature support
%% via `clickhouse_erl_protocol_features:has_feature/2`.
-module(clickhouse_erl_parser_block).
-behaviour(clickhouse_erl_parser_behaviour).

-export([parse/2, init/1]).
-include_lib("kernel/include/logger.hrl").
-include("clickhouse_erl_protocol.hrl").

-type parser_state() :: #{
    stage :=
        temp_table_name
        | decompress
        | block_info
        | num_columns
        | num_rows
        | col_name
        | col_type
        | col_custom
        | col_data_header
        | col_data
        | col_data_loop
        | done,
    version := non_neg_integer(),
    current_column := non_neg_integer(),
    packet_type => atom() | undefined,
    compression_opts => map() | undefined,
    post_decompress_remainder => binary(),
    temp_table_name => binary(),
    block_info => map(),
    num_columns => non_neg_integer(),
    num_rows => non_neg_integer(),
    col_current_name => binary(),
    col_current_type => binary(),
    col_current_prep => term(),
    col_current_data => list(),
    col_current_row => non_neg_integer()
}.

-type parse_result() ::
    {done, list(), binary()}
    | {more, list(), binary(), parser_state()}
    | {error, term()}.

%% @doc Initialize parser state for BLOCK packet.
%% Requires client version from state to determine which features are supported.
-spec init(map()) -> parser_state().
init(#{version := Version} = ParentState) ->
    CompressionOpts = maps:get(compression_opts, ParentState, undefined),
    PacketType = maps:get(packet_type, ParentState, undefined),
    #{
        stage => temp_table_name,
        version => Version,
        current_column => 0,
        compression_opts => CompressionOpts,
        packet_type => PacketType
    }.

%% @doc Parse BLOCK packet payload.
%% Processes fields sequentially: temp_table_name, block_info, num_columns, num_rows,
%% then for each column: name, type, optional custom serialization flag, and column data.
%% Returns {done, Events, Rest} when complete, or {more, Events, Data, State} if incomplete.
-spec parse(binary(), parser_state()) -> parse_result().
parse(Data, State) ->
    do_parse(Data, State, []).

do_parse(Data, #{stage := temp_table_name} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, TempTableName, Rest} ->
            CompressionOpts = maps:get(compression_opts, State, undefined),
            PacketType = maps:get(packet_type, State, undefined),
            NextStage =
                case should_decompress(CompressionOpts, PacketType) of
                    true -> decompress;
                    false -> block_info
                end,
            do_parse(Rest, State#{stage => NextStage, temp_table_name => TempTableName}, Acc);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, {temp_table_name, Reason}}
    end;
do_parse(Data, #{stage := decompress} = State, Acc) ->
    case clickhouse_erl_compression:decompress(Data) of
        {ok, Decompressed, Remaining} ->
            do_parse(
                Decompressed,
                State#{stage => block_info, post_decompress_remainder => Remaining},
                Acc
            );
        {error, {invalid_compressed_block, too_small}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, {decompress, Reason}}
    end;
do_parse(Data, #{stage := block_info} = State, Acc) ->
    case decode_block_info_loop(Data, #{is_overflows => false, bucket_num => -1}) of
        {ok, BlockInfo, Rest} ->
            do_parse(Rest, State#{stage => num_columns, block_info => BlockInfo}, Acc);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, {block_info, Reason}}
    end;
do_parse(Data, #{stage := num_columns} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, NumColumns, Rest} ->
            do_parse(Rest, State#{stage => num_rows, num_columns => NumColumns}, Acc);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, {num_columns, Reason}}
    end;
do_parse(Data, #{stage := num_rows, num_columns := NumColumns} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, NumRows, Rest} ->
            case NumColumns of
                0 ->
                    %% Empty block (0 columns, 0 rows) - done immediately
                    FinalRest = resolve_remainder(Rest, State),
                    {done, lists:reverse(Acc), FinalRest};
                _ ->
                    do_parse(
                        Rest,
                        State#{stage => col_name, num_rows => NumRows, current_column => 0},
                        Acc
                    )
            end;
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, {num_rows, Reason}}
    end;
%% Column parsing loop
do_parse(Data, #{stage := col_name} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, Name, Rest} ->
            do_parse(Rest, State#{stage => col_type, col_current_name => Name}, Acc);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, {col_name, Reason}}
    end;
do_parse(Data, #{stage := col_type} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, Type, Rest} ->
            ProtocolVersion = maps:get(version, State),
            Name = maps:get(col_current_name, State),

            %% Prepare metadata (Enums/Decimals)
            Prep = prepare_type_metadata(Type),

            %% Emit column header event
            Event = {data, column, #{name => Name, type => Type}},

            NextStage =
                case
                    clickhouse_erl_protocol_features:has_feature(
                        custom_serialization, ProtocolVersion
                    )
                of
                    true -> col_custom;
                    false -> col_data_header
                end,
            do_parse(
                Rest,
                State#{
                    stage => NextStage,
                    col_current_type => Type,
                    col_current_prep => Prep
                },
                [Event | Acc]
            );
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, {col_type, Reason}}
    end;
do_parse(Data, #{stage := col_custom} = State, Acc) ->
    case Data of
        <<CustomFlag:8, Rest/binary>> ->
            do_parse(Rest, State#{stage => col_data_header, col_current_custom => CustomFlag}, Acc);
        <<>> ->
            {more, lists:reverse(Acc), Data, State};
        _Other ->
            {error, missing_custom_serialization_flag}
    end;
do_parse(Data, #{stage := col_data_header} = State, Acc) ->
    Type = maps:get(col_current_type, State),
    NumRows = maps:get(num_rows, State),
    case is_column_level_type(Type) of
        true ->
            %% Column-level types (Array, Tuple, Nullable, etc.) use column-level encoding.
            %% Pre-decode the entire column and store values for per-row emission.
            case decode_column_level_type(Type, NumRows, Data) of
                {ok, DecodedValues0, Rest} ->
                    DecodedValues = normalize_column_values(Type, DecodedValues0),
                    do_parse(
                        Rest,
                        State#{
                            stage => col_values,
                            col_current_row => 0,
                            col_precomputed_values => DecodedValues
                        },
                        Acc
                    );
                {error, {truncated_data, _}} ->
                    {more, lists:reverse(Acc), Data, State};
                {error, truncated_data} ->
                    {more, lists:reverse(Acc), Data, State};
                {error, Reason} ->
                    Name = maps:get(col_current_name, State),
                    {error, {col_values, Name, Type, Reason}}
            end;
        false ->
            %% JSON type requires reading a uint64 serialization version before column data.
            %% Version 1 = string serialization (supported), Version 0 = object serialization (not supported).
            %% Column state is only present when there are rows to decode.
            case requires_column_state(Type) andalso NumRows > 0 of
                true ->
                    case read_column_state(Type, Data) of
                        {ok, Rest2} ->
                            do_parse(Rest2, State#{stage => col_values, col_current_row => 0}, Acc);
                        {more, _} ->
                            {more, lists:reverse(Acc), Data, State};
                        {error, Reason} ->
                            Name = maps:get(col_current_name, State),
                            {error, {col_state, Name, Type, Reason}}
                    end;
                false ->
                    %% Scalar types: transition to per-value decoding.
                    do_parse(Data, State#{stage => col_values, col_current_row => 0}, Acc)
            end
    end;
do_parse(Data, #{stage := col_values} = State, Acc) ->
    NumRows = maps:get(num_rows, State),
    CurrentRow = maps:get(col_current_row, State),

    case CurrentRow < NumRows of
        true ->
            case maps:get(col_precomputed_values, State, undefined) of
                [Value | RestValues] ->
                    %% Pre-decoded column (Array types): pop next value
                    Event = {data, column_value, Value},
                    do_parse(
                        Data,
                        State#{
                            col_current_row => CurrentRow + 1,
                            col_precomputed_values => RestValues
                        },
                        [Event | Acc]
                    );
                undefined ->
                    %% Scalar types: decode from binary data
                    Type = maps:get(col_current_type, State),
                    Prep = maps:get(col_current_prep, State),
                    case decode_single_value(Type, Prep, Data) of
                        {ok, Value, Rest} ->
                            Event = {data, column_value, Value},
                            do_parse(
                                Rest,
                                State#{col_current_row => CurrentRow + 1},
                                [Event | Acc]
                            );
                        {error, {truncated_data, _}} ->
                            {more, lists:reverse(Acc), Data, State};
                        {error, Reason} ->
                            Name = maps:get(col_current_name, State),
                            {error, {col_values, Name, Type, Reason}}
                    end
            end;
        false ->
            %% Column finished
            CurrentColumn = maps:get(current_column, State),
            NumColumns = maps:get(num_columns, State),
            case CurrentColumn + 1 < NumColumns of
                true ->
                    NewState = State#{
                        stage => col_name,
                        current_column => CurrentColumn + 1
                    },
                    NewState2 = maps:without(
                        [
                            col_current_name,
                            col_current_type,
                            col_current_custom,
                            col_current_prep,
                            col_current_row,
                            col_precomputed_values
                        ],
                        NewState
                    ),
                    do_parse(Data, NewState2, Acc);
                false ->
                    %% All columns finished
                    FinalRest = resolve_remainder(Data, State),
                    {done, lists:reverse(Acc), FinalRest}
            end
    end.

prepare_type_metadata(<<"Enum8(", _/binary>> = Type) ->
    case clickhouse_erl_types_enum:parse_enum_type(Type) of
        {ok, {enum8, Mappings}} -> Mappings;
        _ -> #{}
    end;
prepare_type_metadata(<<"Enum16(", _/binary>> = Type) ->
    case clickhouse_erl_types_enum:parse_enum_type(Type) of
        {ok, {enum16, Mappings}} -> Mappings;
        _ -> #{}
    end;
prepare_type_metadata(_) ->
    #{}.

%% @doc Check if a type requires reading column state before column data.
%% JSON type requires a uint64 serialization version.
-spec requires_column_state(binary()) -> boolean().
requires_column_state(<<"JSON">>) -> true;
requires_column_state(_) -> false.

%% @doc Read column state for types that require it.
%% JSON type: reads uint64 serialization version (1 = string, 0 = object).
-spec read_column_state(binary(), binary()) ->
    {ok, binary()} | {more, binary()} | {error, term()}.
read_column_state(<<"JSON">>, <<Version:64/little-unsigned-integer, Rest/binary>>) ->
    case Version of
        1 ->
            {ok, Rest};
        0 ->
            {error,
                {json_object_serialization_not_supported,
                    <<"Enable 'output_format_native_write_json_as_string' setting">>}};
        _ ->
            {error, {invalid_json_serialization_version, Version}}
    end;
read_column_state(<<"JSON">>, Data) when byte_size(Data) < 8 ->
    {more, Data};
read_column_state(Type, _Data) ->
    {error, {unsupported_column_state_type, Type}}.

%%%===================================================================
%%% Internal Helper Functions
%%%===================================================================

%% @doc Check if a type string is a column-level encoded type.
%% These types use column-level encoding and must be pre-decoded as a whole column:
%% Array, Tuple, Map, LowCardinality, and Nullable.
%%
%% Nullable uses column-level encoding in the native protocol: all null flags first
%% (1 byte each), then all inner-type values. This is NOT interleaved per-value encoding.
-spec is_column_level_type(binary()) -> boolean().
is_column_level_type(Type) ->
    is_array_type(Type) orelse is_tuple_type(Type) orelse is_map_type(Type) orelse
        is_low_cardinality_type(Type) orelse is_nullable_type(Type).

%% @doc Decode a column-level encoded type (Array or Tuple).
%% Delegates to clickhouse_erl_protocol_data_block:decode_column_data/3.
-spec decode_column_level_type(binary(), non_neg_integer(), binary()) ->
    {ok, list(), binary()} | {error, term()}.
decode_column_level_type(Type, NumRows, Data) ->
    clickhouse_erl_protocol_data_block:decode_column_data(Type, NumRows, Data).

%% @doc Check if a type string is an Array type.
-spec is_array_type(binary()) -> boolean().
is_array_type(<<"Array(", _/binary>>) -> true;
is_array_type(_) -> false.

%% @doc Check if a type string is a Tuple type.
-spec is_tuple_type(binary()) -> boolean().
is_tuple_type(<<"Tuple(", _/binary>>) -> true;
is_tuple_type(_) -> false.

%% @doc Check if a type string is a Map type.
-spec is_map_type(binary()) -> boolean().
is_map_type(<<"Map(", _/binary>>) -> true;
is_map_type(_) -> false.

%% @doc Check if a type string is a LowCardinality type.
-spec is_low_cardinality_type(binary()) -> boolean().
is_low_cardinality_type(<<"LowCardinality(", _/binary>>) -> true;
is_low_cardinality_type(_) -> false.

%% @doc Check if a type string is a Nullable type.
-spec is_nullable_type(binary()) -> boolean().
is_nullable_type(<<"Nullable(", _/binary>>) -> true;
is_nullable_type(_) -> false.

%% @doc Normalize column-level decoded values for Nullable types.
%% decode_nullable_column returns {null}/{value, V} tagged tuples, but the
%% streaming parser emits plain null/V values for consistency with per-value decode.
-spec normalize_column_values(binary(), list()) -> list().
normalize_column_values(Type, Values) ->
    case is_nullable_type(Type) of
        true ->
            [
                case V of
                    {null} -> null;
                    {value, Inner} -> Inner
                end
             || V <- Values
            ];
        false ->
            Values
    end.

%% @doc Parse FixedString length from type string.
%% Example: "FixedString(16)" -> {ok, 16}
-spec parse_fixed_string_length(binary()) -> {ok, pos_integer()} | {error, term()}.
parse_fixed_string_length(<<"FixedString(", Rest/binary>>) ->
    case binary:split(Rest, <<")">>) of
        [LengthBin, _] ->
            try
                Length = binary_to_integer(string:trim(LengthBin)),
                {ok, Length}
            catch
                _:_ ->
                    {error, {invalid_fixed_string_length, Rest}}
            end;
        _ ->
            {error, {invalid_fixed_string_format, Rest}}
    end;
parse_fixed_string_length(Type) ->
    {error, {not_fixed_string_type, Type}}.

%% @doc Parse DateTime64 precision from type string.
%% Example: "DateTime64(3)" -> {ok, 3}
%% Example: "DateTime64(6, 'UTC')" -> {ok, 6}
-spec parse_datetime64_precision(binary()) -> {ok, non_neg_integer()} | {error, term()}.
parse_datetime64_precision(<<"DateTime64(", Rest/binary>>) ->
    case binary:split(Rest, <<")">>) of
        [ParamsBin, _] ->
            %% Split by comma to get precision (first parameter)
            case binary:split(ParamsBin, <<",">>) of
                [PrecisionBin] ->
                    %% Only precision provided
                    try
                        Precision = binary_to_integer(string:trim(PrecisionBin)),
                        {ok, Precision}
                    catch
                        _:_ ->
                            {error, {invalid_datetime64_precision, Rest}}
                    end;
                [PrecisionBin, _TimezoneBin] ->
                    %% Precision and timezone provided
                    try
                        Precision = binary_to_integer(string:trim(PrecisionBin)),
                        {ok, Precision}
                    catch
                        _:_ ->
                            {error, {invalid_datetime64_precision, Rest}}
                    end;
                _ ->
                    {error, {invalid_datetime64_format, Rest}}
            end;
        _ ->
            {error, {invalid_datetime64_format, Rest}}
    end;
parse_datetime64_precision(Type) ->
    {error, {not_datetime64_type, Type}}.

%% @doc Parse Interval unit from type string.
%% Example: "IntervalSecond" -> {ok, second}
%% Example: "IntervalDay" -> {ok, day}
-spec parse_interval_unit(binary()) -> {ok, atom()} | {error, term()}.
parse_interval_unit(<<"Interval", Rest/binary>>) ->
    %% Convert unit name to lowercase atom
    UnitBin = string:lowercase(Rest),
    try
        Unit = binary_to_atom(UnitBin, utf8),
        {ok, Unit}
    catch
        _:_ ->
            {error, {invalid_interval_unit, Rest}}
    end;
parse_interval_unit(Type) ->
    {error, {not_interval_type, Type}}.

%% Primitive types - String
decode_single_value(<<"String">>, _Prep, Data) ->
    clickhouse_erl_types_primitive:decode_string(Data);
%% Primitive types - FixedString
decode_single_value(<<"FixedString(", _/binary>> = Type, _Prep, Data) ->
    case parse_fixed_string_length(Type) of
        {ok, Length} ->
            case Data of
                <<Value:Length/binary, Rest/binary>> -> {ok, Value, Rest};
                _ -> {error, {truncated_data, {fixed_string, Length}}}
            end;
        {error, Reason} ->
            {error, Reason}
    end;
%% Integer types - Unsigned
decode_single_value(<<"UInt8">>, _Prep, Data) ->
    clickhouse_erl_types_integer:decode_uint8(Data);
decode_single_value(<<"UInt16">>, _Prep, Data) ->
    clickhouse_erl_types_integer:decode_uint16(Data);
decode_single_value(<<"UInt32">>, _Prep, Data) ->
    clickhouse_erl_types_integer:decode_uint32(Data);
decode_single_value(<<"UInt64">>, _Prep, Data) ->
    case Data of
        <<V:64/unsigned-little, Rest/binary>> -> {ok, V, Rest};
        _ -> {error, {truncated_data, uint64}}
    end;
%% Integer types - Signed
decode_single_value(<<"Int8">>, _Prep, Data) ->
    clickhouse_erl_types_integer:decode_int8(Data);
decode_single_value(<<"Int16">>, _Prep, Data) ->
    clickhouse_erl_types_integer:decode_int16(Data);
decode_single_value(<<"Int32">>, _Prep, Data) ->
    clickhouse_erl_types_integer:decode_int32(Data);
decode_single_value(<<"Int64">>, _Prep, Data) ->
    clickhouse_erl_types_integer:decode_int64(Data);
%% Boolean
decode_single_value(<<"Bool">>, _Prep, Data) ->
    clickhouse_erl_types_integer:decode_bool(Data);
%% Float types
decode_single_value(<<"Float32">>, _Prep, Data) ->
    clickhouse_erl_types_float:decode_float32(Data);
decode_single_value(<<"Float64">>, _Prep, Data) ->
    clickhouse_erl_types_float:decode_float64(Data);
%% Extended integer types
decode_single_value(<<"Int128">>, _Prep, Data) ->
    clickhouse_erl_types_extended_integer:decode_int128(Data);
decode_single_value(<<"UInt128">>, _Prep, Data) ->
    clickhouse_erl_types_extended_integer:decode_uint128(Data);
decode_single_value(<<"Int256">>, _Prep, Data) ->
    clickhouse_erl_types_extended_integer:decode_int256(Data);
decode_single_value(<<"UInt256">>, _Prep, Data) ->
    clickhouse_erl_types_extended_integer:decode_uint256(Data);
%% Decimal types
decode_single_value(<<"Decimal32(", _/binary>> = Type, _Prep, Data) ->
    case clickhouse_erl_types_decimal:parse_decimal_type(Type) of
        {ok, {decimal32, _Precision, Scale}} ->
            clickhouse_erl_types_decimal:decode_decimal32(Data, Scale);
        {error, Reason} ->
            {error, Reason}
    end;
decode_single_value(<<"Decimal64(", _/binary>> = Type, _Prep, Data) ->
    case clickhouse_erl_types_decimal:parse_decimal_type(Type) of
        {ok, {decimal64, _Precision, Scale}} ->
            clickhouse_erl_types_decimal:decode_decimal64(Data, Scale);
        {error, Reason} ->
            {error, Reason}
    end;
decode_single_value(<<"Decimal128(", _/binary>> = Type, _Prep, Data) ->
    case clickhouse_erl_types_decimal:parse_decimal_type(Type) of
        {ok, {decimal128, _Precision, Scale}} ->
            clickhouse_erl_types_decimal:decode_decimal128(Data, Scale);
        {error, Reason} ->
            {error, Reason}
    end;
decode_single_value(<<"Decimal256(", _/binary>> = Type, _Prep, Data) ->
    case clickhouse_erl_types_decimal:parse_decimal_type(Type) of
        {ok, {decimal256, _Precision, Scale}} ->
            clickhouse_erl_types_decimal:decode_decimal256(Data, Scale);
        {error, Reason} ->
            {error, Reason}
    end;
decode_single_value(<<"Decimal(", _/binary>> = Type, _Prep, Data) ->
    %% Generic Decimal(P, S) format
    case clickhouse_erl_types_decimal:parse_decimal_type(Type) of
        {ok, {decimal32, _Precision, Scale}} ->
            clickhouse_erl_types_decimal:decode_decimal32(Data, Scale);
        {ok, {decimal64, _Precision, Scale}} ->
            clickhouse_erl_types_decimal:decode_decimal64(Data, Scale);
        {ok, {decimal128, _Precision, Scale}} ->
            clickhouse_erl_types_decimal:decode_decimal128(Data, Scale);
        {ok, {decimal256, _Precision, Scale}} ->
            clickhouse_erl_types_decimal:decode_decimal256(Data, Scale);
        {error, Reason} ->
            {error, Reason}
    end;
%% Enum types
decode_single_value(<<"Enum8(", _/binary>>, Mappings, Data) ->
    clickhouse_erl_types_enum:decode_enum8(Data, Mappings);
decode_single_value(<<"Enum16(", _/binary>>, Mappings, Data) ->
    clickhouse_erl_types_enum:decode_enum16(Data, Mappings);
%% Temporal types - Date
decode_single_value(<<"Date">>, _Prep, Data) ->
    clickhouse_erl_types_temporal:decode_date(Data);
decode_single_value(<<"Date32">>, _Prep, Data) ->
    clickhouse_erl_types_temporal:decode_date32(Data);
%% Temporal types - DateTime
decode_single_value(<<"DateTime">>, _Prep, Data) ->
    clickhouse_erl_types_temporal:decode_datetime(Data);
decode_single_value(<<"DateTime(", _/binary>>, _Prep, Data) ->
    %% DateTime with timezone - decode as UInt32 (same as DateTime)
    clickhouse_erl_types_temporal:decode_datetime(Data);
decode_single_value(<<"DateTime64(", _/binary>> = Type, _Prep, Data) ->
    case parse_datetime64_precision(Type) of
        {ok, Precision} ->
            clickhouse_erl_types_temporal:decode_datetime64(Data, Precision);
        {error, Reason} ->
            {error, Reason}
    end;
%% Time types
decode_single_value(<<"Time">>, _Prep, Data) ->
    clickhouse_erl_types_time:decode_time(Data);
decode_single_value(<<"Time64(", _/binary>>, _Prep, Data) ->
    %% Time64 precision is only used for encoding, not decoding
    clickhouse_erl_types_time:decode_time64(Data);
%% Network types
decode_single_value(<<"IPv4">>, _Prep, Data) ->
    clickhouse_erl_types_network:decode_ipv4(Data);
decode_single_value(<<"IPv6">>, _Prep, Data) ->
    clickhouse_erl_types_network:decode_ipv6(Data);
%% UUID
decode_single_value(<<"UUID">>, _Prep, Data) ->
    clickhouse_erl_types_uuid:decode_uuid(Data);
%% Special types
decode_single_value(<<"Nothing">>, _Prep, Data) ->
    clickhouse_erl_types_special:decode_nothing(Data);
decode_single_value(<<"Point">>, _Prep, Data) ->
    clickhouse_erl_types_special:decode_point(Data);
decode_single_value(<<"Interval", _/binary>> = Type, _Prep, Data) ->
    case parse_interval_unit(Type) of
        {ok, Unit} ->
            clickhouse_erl_types_special:decode_interval(Data, Unit);
        {error, Reason} ->
            {error, Reason}
    end;
decode_single_value(<<"JSON">>, _Prep, Data) ->
    clickhouse_erl_types_special:decode_json(Data);
%% Nullable type — per-value decode path.
%% NOTE: Top-level Nullable columns are routed through column-level decode via
%% is_column_level_type/1. This per-value handler is only reachable from nested
%% contexts within other column-level decoders (e.g., Array(Nullable(Int32)) where
%% the Array decoder calls decode_column_data which handles Nullable at column level).
%% Kept as a safety net for any future per-value decode paths.
decode_single_value(<<"Nullable(Nullable(", _/binary>> = Type, _Prep, _Data) ->
    %% ClickHouse forbids nested Nullable
    {error, {nested_nullable_not_allowed, Type}};
decode_single_value(<<"Nullable(", _/binary>> = Type, _Prep, Data) ->
    case Data of
        <<1:8, Rest/binary>> ->
            %% Null flag = 1: value is null, but we must still consume the placeholder bytes
            InnerType = extract_nullable_inner_type(Type),
            InnerPrep = prepare_type_metadata(InnerType),
            case decode_single_value(InnerType, InnerPrep, Rest) of
                {ok, _PlaceholderValue, Rest2} ->
                    {ok, null, Rest2};
                {error, _} = Error ->
                    Error
            end;
        <<0:8, Rest/binary>> ->
            %% Null flag = 0: decode inner value
            InnerType = extract_nullable_inner_type(Type),
            InnerPrep = prepare_type_metadata(InnerType),
            decode_single_value(InnerType, InnerPrep, Rest);
        <<>> ->
            {error, {truncated_data, nullable_null_flag}}
    end;
%% LowCardinality type - decode as inner type directly
%% Dictionary encoding is column-level, not value-level.
%% In streaming (per-value) mode, strip the wrapper and decode the inner type.
decode_single_value(<<"LowCardinality(", _/binary>> = Type, _Prep, Data) ->
    InnerType = extract_low_cardinality_inner_type(Type),
    InnerPrep = prepare_type_metadata(InnerType),
    decode_single_value(InnerType, InnerPrep, Data);
%% Unsupported type
decode_single_value(Type, _Prep, _Data) ->
    {error, {unsupported_streaming_type, Type}}.

%% @doc Extract inner type from Nullable(T) type string.
%% Example: <<"Nullable(UInt32)">> -> <<"UInt32">>
%% Example: <<"Nullable(DateTime64(3))">> -> <<"DateTime64(3)">>
-spec extract_nullable_inner_type(binary()) -> binary().
extract_nullable_inner_type(<<"Nullable(", Rest/binary>>) ->
    %% Remove trailing ")"
    binary:part(Rest, 0, byte_size(Rest) - 1).

%% @doc Extract inner type from LowCardinality(T) type string.
%% Example: <<"LowCardinality(String)">> -> <<"String">>
%% Example: <<"LowCardinality(Nullable(String))">> -> <<"Nullable(String)">>
-spec extract_low_cardinality_inner_type(binary()) -> binary().
extract_low_cardinality_inner_type(<<"LowCardinality(", Rest/binary>>) ->
    %% Remove trailing ")"
    binary:part(Rest, 0, byte_size(Rest) - 1).

%% @doc Resolve the final remainder when block parsing completes.
%% If decompression was performed, the remainder is the post-compressed-block data
%% (bytes after the compressed block in the TCP stream), not leftover decompressed data.
%% If no decompression, the remainder is whatever unparsed data remains.
-spec resolve_remainder(binary(), map()) -> binary().
resolve_remainder(_DecompressedRest, #{post_decompress_remainder := Remainder}) ->
    Remainder;
resolve_remainder(Rest, _State) ->
    Rest.

%% @doc Check if decompression should be performed for this block.
%% Only SERVER_DATA (1), SERVER_TOTALS (7), and SERVER_EXTREMES (8) are compressible.
%% SERVER_PROFILE_EVENTS (14) and other block types are NOT compressed by the server,
%% even when compression is enabled on the connection.
%% See ch-go proto/server_code.go Compressible() for reference.
-spec should_decompress(map() | undefined, atom() | undefined) -> boolean().
should_decompress(undefined, _PacketType) -> false;
should_decompress(#{method := disabled}, _PacketType) -> false;
should_decompress(#{method := _}, PacketType) -> is_compressible_packet(PacketType);
should_decompress(_, _PacketType) -> false.

%% @doc Check if a packet type is compressible per ClickHouse protocol.
%% Only Data, Totals, and Extremes packets are compressed.
-spec is_compressible_packet(atom() | undefined) -> boolean().
is_compressible_packet(server_data) -> true;
is_compressible_packet(server_totals) -> true;
is_compressible_packet(server_extremes) -> true;
is_compressible_packet(_) -> false.

%% Reimplement decode_block_info_loop to properly return `{error, {truncated_data, _}}`
decode_block_info_loop(Binary, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Binary) of
        {ok, 0, Rest} ->
            {ok, Acc, Rest};
        {ok, 1, Rest} ->
            case Rest of
                <<IsOverflowsByte:8, Rest2/binary>> ->
                    decode_block_info_loop(Rest2, Acc#{is_overflows => IsOverflowsByte > 0});
                _ ->
                    {error, {truncated_data, block_info}}
            end;
        {ok, 2, Rest} ->
            case Rest of
                <<BucketNum:32/signed-little-integer, Rest2/binary>> ->
                    decode_block_info_loop(Rest2, Acc#{bucket_num => BucketNum});
                _ ->
                    {error, {truncated_data, block_info}}
            end;
        {ok, Other, _} ->
            {error, {unknown_block_info_field, Other}};
        Error ->
            Error
    end.
