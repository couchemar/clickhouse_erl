-module(clickhouse_erl_protocol_data_block).

%% Public API
-export([
    decode/1,
    decode/2,
    decode_column_data/3,
    encode_block_info/0,
    encode_blank_data_block_info/0,
    encode_blank_data_block/0,
    encode_data_block/2,
    validate_row_counts/1,
    validate_column_names/1
]).

%% Type exports
-export_type([column_data/0, data_block/0]).

-include("clickhouse_erl_protocol.hrl").
-include_lib("kernel/include/logger.hrl").

%% @doc Decode a Data packet (Type 3)
%%
%% Decodes the data block structure from the binary stream.
%% Structure:
%% 1. Temporary Table Name (String)
%% 2. Block Info (BlockInfo)
%% 3. Number of Columns (UVarInt)
%% 4. Number of Rows (UVarInt)
%% 5. Columns Metadata and Data
%%
%% validation: (from Requirements)
%% - Extract column names and types
%% - Handle empty blocks
%% - (Future) Extract column data
-spec decode(binary()) -> {ok, data_block(), binary()} | {error, term()}.
decode(Binary) ->
    %% Default to older protocol version for backward compatibility with existing tests
    decode(Binary, 54450).

%% @doc Decode a Data packet with protocol version support
-spec decode(binary(), non_neg_integer()) -> {ok, data_block(), binary()} | {error, term()}.
decode(Binary, ProtocolVersion) ->
    %% 1. Temporary Table Name
    %% For now, usually empty. We decode it but don't strictly enforce it being empty.
    maybe
        {ok, _TempTableName, Rest1} ?=
            add_decode_context(
                clickhouse_erl_types_primitive:decode_string(Binary), temp_table_name
            ),
        {ok, BlockInfo, Rest2} ?= add_decode_context(decode_block_info(Rest1), block_info),
        {ok, NumColumns, Rest3} ?=
            add_decode_context(
                clickhouse_erl_types_primitive:decode_varint(Rest2), columns_count
            ),
        {ok, NumRows, Rest4} ?=
            add_decode_context(
                clickhouse_erl_types_primitive:decode_varint(Rest3), rows_count
            ),
        {ok, Result, Rest} ?=
            decode_columns(Rest4, NumColumns, NumRows, BlockInfo, ProtocolVersion),
        {ok, Result, Rest}
    end.

%% @doc Add decoding context to error tuples for better error reporting.
-spec add_decode_context({ok, term(), binary()} | {error, term()}, atom()) ->
    {ok, term(), binary()} | {error, term()}.
add_decode_context({ok, Result, Rest}, _Context) ->
    {ok, Result, Rest};
add_decode_context({error, Reason}, Context) ->
    {error, {decoding_failed, {Context, Reason}}}.

%% @doc Decode Block Info
%% Structure:
%% 1. Info Field 1 (UVarInt) - usually 1
%% 2. Is Overflow (Boolean - 1 byte)
%% 3. Info Field 2 (UVarInt) - usually 2
%% 4. Bucket Num (Int32)
%% 5. Zero (UVarInt) - usually 0
%%
%% Only present if revision >= 51903 (which is always true for modern CH)
%% Actually, block info encoding depends on protocol version/revision, but standard modern
%% behavior uses the sequence: 1, is_overflows, 2, bucket_num, 0.
-spec decode_block_info(binary()) -> {ok, block_info(), binary()} | {error, term()}.

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

decode_columns(Binary, 0, 0, BlockInfo, _ProtocolVersion) ->
    %% Empty block
    DataBlock = #{
        info => BlockInfo,
        columns => 0,
        rows => 0,
        column_data => []
    },
    {ok, DataBlock, Binary};
decode_columns(Binary, NumColumns, NumRows, BlockInfo, ProtocolVersion) ->
    decode_columns_loop(Binary, NumColumns, NumRows, [], BlockInfo, ProtocolVersion).

decode_columns_loop(Binary, 0, _NumRows, Acc, BlockInfo, _ProtocolVersion) ->
    DataBlock = #{
        info => BlockInfo,
        columns => length(Acc),
        rows => _NumRows,
        column_data => lists:reverse(Acc)
    },
    ?LOG_DEBUG("decode_columns_loop: All columns decoded, ~p bytes remaining~n", [
        byte_size(Binary)
    ]),
    {ok, DataBlock, Binary};
decode_columns_loop(Binary, RemColumns, NumRows, Acc, BlockInfo, ProtocolVersion) ->
    InitialSize = byte_size(Binary),
    ?LOG_DEBUG(
        "decode_columns_loop: Decoding column ~p of ~p, ~p bytes available~n",
        [length(Acc) + 1, length(Acc) + RemColumns, InitialSize]
    ),
    %% Decode one column: Name, Type, Data
    maybe
        {ok, Name, Rest1} ?= clickhouse_erl_types_primitive:decode_string(Binary),
        NameBytes = InitialSize - byte_size(Rest1),
        ?LOG_DEBUG("  Column name: ~s (~p bytes)~n", [Name, NameBytes]),
        {ok, Type, Rest2} ?= clickhouse_erl_types_primitive:decode_string(Rest1),
        TypeBytes = byte_size(Rest1) - byte_size(Rest2),
        ?LOG_DEBUG("  Column type: ~s (~p bytes)~n", [Type, TypeBytes]),
        {ok, Rest3} ?= maybe_consume_custom_flag(Name, Rest2, ProtocolVersion),
        decode_column_data_and_continue(
            Name,
            Type,
            NumRows,
            Rest3,
            RemColumns,
            Acc,
            BlockInfo,
            ProtocolVersion,
            InitialSize
        )
    else
        {error, Reason} -> {error, Reason}
    end.

%% @doc Optionally consume the custom serialization flag byte for a column.
%% If the feature is supported, reads and discards the flag byte.
%% Otherwise returns the data unchanged.
-spec maybe_consume_custom_flag(binary(), binary(), non_neg_integer()) ->
    {ok, binary()} | {error, term()}.
maybe_consume_custom_flag(Name, Data, ProtocolVersion) ->
    case clickhouse_erl_protocol_features:has_feature(custom_serialization, ProtocolVersion) of
        true ->
            case extract_custom_flag(Data) of
                {ok, {CustomFlag, Rest}} ->
                    FlagBytes = byte_size(Data) - byte_size(Rest),
                    ?LOG_DEBUG("  Custom serialization flag: ~p (~p bytes)~n", [
                        CustomFlag, FlagBytes
                    ]),
                    {ok, Rest};
                {error, _} ->
                    {error, {decoding_failed, {missing_custom_serialization_flag, Name}}}
            end;
        false ->
            {ok, Data}
    end.

%% @doc Extract custom serialization flag from binary.
-spec extract_custom_flag(binary()) -> {ok, {non_neg_integer(), binary()}} | {error, term()}.
extract_custom_flag(<<CustomFlag:8, Rest/binary>>) ->
    {ok, {CustomFlag, Rest}};
extract_custom_flag(_) ->
    {error, missing_custom_serialization_flag}.

%% @doc Decode column data and continue with next column
-spec decode_column_data_and_continue(
    binary(),
    binary(),
    non_neg_integer(),
    binary(),
    pos_integer(),
    [column_data()],
    block_info(),
    non_neg_integer(),
    non_neg_integer()
) ->
    {ok, data_block(), binary()} | {error, term()}.
decode_column_data_and_continue(
    Name, Type, NumRows, Rest, RemColumns, Acc, BlockInfo, ProtocolVersion, InitialSize
) ->
    DataStartSize = byte_size(Rest),
    case NumRows of
        0 ->
            ?LOG_DEBUG("  Column data: 0 rows, 0 bytes~n", []),
            continue_with_column_data(
                Name, Type, [], Rest, RemColumns, NumRows, Acc, BlockInfo, ProtocolVersion
            );
        _ ->
            %% Decode state if the type requires it (like JSON)
            case decode_column_state(Type, Rest) of
                {ok, Rest2} ->
                    StateBytes = DataStartSize - byte_size(Rest2),
                    case StateBytes of
                        0 -> ok;
                        _ -> ?LOG_DEBUG("  Column state: ~p bytes~n", [StateBytes])
                    end,

                    case decode_column_data(Type, NumRows, Rest2) of
                        {ok, Data, Rest3} ->
                            DataBytes = byte_size(Rest2) - byte_size(Rest3),
                            TotalBytes = InitialSize - byte_size(Rest3),
                            ?LOG_DEBUG("  Column data: ~p bytes (total column: ~p bytes)~n", [
                                DataBytes, TotalBytes
                            ]),
                            continue_with_column_data(
                                Name,
                                Type,
                                Data,
                                Rest3,
                                RemColumns,
                                NumRows,
                                Acc,
                                BlockInfo,
                                ProtocolVersion
                            );
                        Error ->
                            Error
                    end;
                {error, Reason} ->
                    {error, {state_decode_failed, Name, Reason}}
            end
    end.

%% @doc Helper to continue decoding with column data
-spec continue_with_column_data(
    binary(),
    binary(),
    list(),
    binary(),
    pos_integer(),
    non_neg_integer(),
    [column_data()],
    block_info(),
    non_neg_integer()
) -> {ok, data_block(), binary()} | {error, term()}.
continue_with_column_data(
    Name, Type, Data, Rest, RemColumns, NumRows, Acc, BlockInfo, ProtocolVersion
) ->
    ColumnData = create_column_data(Name, Type, Data),
    decode_columns_loop(
        Rest, RemColumns - 1, NumRows, [ColumnData | Acc], BlockInfo, ProtocolVersion
    ).

%% @doc Create column data map.
-spec create_column_data(binary(), binary(), list()) -> map().
create_column_data(Name, Type, Data) ->
    #{
        name => Name,
        type => Type,
        data => Data
    }.

%% Basic integer types - 8-bit
decode_column_data(<<"UInt8">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 8, unsigned, little, Binary, []);
decode_column_data(<<"Int8">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 8, signed, little, Binary, []);
%% Basic integer types - 16-bit
decode_column_data(<<"UInt16">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 16, unsigned, little, Binary, []);
decode_column_data(<<"Int16">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 16, signed, little, Binary, []);
%% Basic integer types - 32-bit
decode_column_data(<<"UInt32">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 32, unsigned, little, Binary, []);
decode_column_data(<<"Int32">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 32, signed, little, Binary, []);
%% Basic integer types - 64-bit
decode_column_data(<<"UInt64">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 64, unsigned, little, Binary, []);
decode_column_data(<<"Int64">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 64, signed, little, Binary, []);
%% Extended integer types - 128-bit
decode_column_data(<<"Int128">>, NumRows, Binary) ->
    clickhouse_erl_types_extended_integer:decode_int128_column(Binary, NumRows);
decode_column_data(<<"UInt128">>, NumRows, Binary) ->
    clickhouse_erl_types_extended_integer:decode_uint128_column(Binary, NumRows);
%% Extended integer types - 256-bit
decode_column_data(<<"Int256">>, NumRows, Binary) ->
    clickhouse_erl_types_extended_integer:decode_int256_column(Binary, NumRows);
decode_column_data(<<"UInt256">>, NumRows, Binary) ->
    clickhouse_erl_types_extended_integer:decode_uint256_column(Binary, NumRows);
%% Floating point types
decode_column_data(<<"Float32">>, NumRows, Binary) ->
    decode_floats(NumRows, 32, little, Binary, []);
decode_column_data(<<"Float64">>, NumRows, Binary) ->
    decode_floats(NumRows, 64, little, Binary, []);
%% Decimal types
decode_column_data(<<"Decimal32(", _/binary>> = Type, NumRows, Binary) ->
    case clickhouse_erl_types_decimal:parse_decimal_type(Type) of
        {ok, {decimal32, _Precision, Scale}} ->
            clickhouse_erl_types_decimal:decode_decimal32_column(Binary, Scale, NumRows);
        {error, Reason} ->
            {error, Reason}
    end;
decode_column_data(<<"Decimal64(", _/binary>> = Type, NumRows, Binary) ->
    case clickhouse_erl_types_decimal:parse_decimal_type(Type) of
        {ok, {decimal64, _Precision, Scale}} ->
            clickhouse_erl_types_decimal:decode_decimal64_column(Binary, Scale, NumRows);
        {error, Reason} ->
            {error, Reason}
    end;
decode_column_data(<<"Decimal128(", _/binary>> = Type, NumRows, Binary) ->
    case clickhouse_erl_types_decimal:parse_decimal_type(Type) of
        {ok, {decimal128, _Precision, Scale}} ->
            clickhouse_erl_types_decimal:decode_decimal128_column(Binary, Scale, NumRows);
        {error, Reason} ->
            {error, Reason}
    end;
decode_column_data(<<"Decimal256(", _/binary>> = Type, NumRows, Binary) ->
    case clickhouse_erl_types_decimal:parse_decimal_type(Type) of
        {ok, {decimal256, _Precision, Scale}} ->
            clickhouse_erl_types_decimal:decode_decimal256_column(Binary, Scale, NumRows);
        {error, Reason} ->
            {error, Reason}
    end;
%% Generic Decimal(P, S) format - ClickHouse canonical representation
decode_column_data(<<"Decimal(", _/binary>> = Type, NumRows, Binary) ->
    case clickhouse_erl_types_decimal:parse_decimal_type(Type) of
        {ok, {DecimalType, _Precision, Scale}} ->
            %% Dispatch to appropriate decoder based on precision
            case DecimalType of
                decimal32 ->
                    clickhouse_erl_types_decimal:decode_decimal32_column(Binary, Scale, NumRows);
                decimal64 ->
                    clickhouse_erl_types_decimal:decode_decimal64_column(Binary, Scale, NumRows);
                decimal128 ->
                    clickhouse_erl_types_decimal:decode_decimal128_column(Binary, Scale, NumRows);
                decimal256 ->
                    clickhouse_erl_types_decimal:decode_decimal256_column(Binary, Scale, NumRows)
            end;
        {error, Reason} ->
            {error, Reason}
    end;
%% String types
decode_column_data(<<"String">>, NumRows, Binary) ->
    decode_strings(NumRows, Binary, []);
%% Date and time types
decode_column_data(<<"Date">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 16, unsigned, little, Binary, []);
decode_column_data(<<"Date32">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 32, signed, little, Binary, []);
decode_column_data(<<"DateTime">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 32, unsigned, little, Binary, []);
decode_column_data(<<"DateTime64">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 64, unsigned, little, Binary, []);
decode_column_data(<<"DateTime64(", _/binary>>, NumRows, Binary) ->
    % DateTime64 with precision - still decode as Int64
    decode_fixed_width_integers(NumRows, 64, unsigned, little, Binary, []);
%% Time types
decode_column_data(<<"Time">>, NumRows, Binary) ->
    clickhouse_erl_types_time:decode_time_column(Binary, NumRows);
decode_column_data(<<"Time64">>, NumRows, Binary) ->
    clickhouse_erl_types_time:decode_time64_column(Binary, NumRows);
%% UUID type (128-bit)
decode_column_data(<<"UUID">>, NumRows, Binary) ->
    clickhouse_erl_types_uuid:decode_uuid_column(Binary, NumRows);
%% Boolean type (alias for UInt8)
decode_column_data(<<"Bool">>, NumRows, Binary) ->
    decode_fixed_width_integers(NumRows, 8, unsigned, little, Binary, []);
%% Enum types
decode_column_data(<<"Enum8(", _/binary>> = Type, NumRows, Binary) ->
    case clickhouse_erl_types_enum:parse_enum_type(Type) of
        {ok, {enum8, Mappings}} ->
            clickhouse_erl_types_enum:decode_enum8_column(Binary, Mappings, NumRows);
        {error, Reason} ->
            {error, Reason}
    end;
decode_column_data(<<"Enum16(", _/binary>> = Type, NumRows, Binary) ->
    case clickhouse_erl_types_enum:parse_enum_type(Type) of
        {ok, {enum16, Mappings}} ->
            clickhouse_erl_types_enum:decode_enum16_column(Binary, Mappings, NumRows);
        {error, Reason} ->
            {error, Reason}
    end;
%% IPv4 and IPv6 types
decode_column_data(<<"IPv4">>, NumRows, Binary) ->
    clickhouse_erl_types_network:decode_ipv4_column(Binary, NumRows);
decode_column_data(<<"IPv6">>, NumRows, Binary) ->
    clickhouse_erl_types_network:decode_ipv6_column(Binary, NumRows);
%% Special types - Nothing
decode_column_data(<<"Nothing">>, NumRows, Binary) ->
    clickhouse_erl_types_special:decode_nothing_column(Binary, NumRows);
%% Special types - Point
decode_column_data(<<"Point">>, NumRows, Binary) ->
    clickhouse_erl_types_special:decode_point_column(Binary, NumRows);
%% Special types - Interval
decode_column_data(<<"IntervalSecond">>, NumRows, Binary) ->
    clickhouse_erl_types_special:decode_interval_column(Binary, second, NumRows);
decode_column_data(<<"IntervalMinute">>, NumRows, Binary) ->
    clickhouse_erl_types_special:decode_interval_column(Binary, minute, NumRows);
decode_column_data(<<"IntervalHour">>, NumRows, Binary) ->
    clickhouse_erl_types_special:decode_interval_column(Binary, hour, NumRows);
decode_column_data(<<"IntervalDay">>, NumRows, Binary) ->
    clickhouse_erl_types_special:decode_interval_column(Binary, day, NumRows);
decode_column_data(<<"IntervalWeek">>, NumRows, Binary) ->
    clickhouse_erl_types_special:decode_interval_column(Binary, week, NumRows);
decode_column_data(<<"IntervalMonth">>, NumRows, Binary) ->
    clickhouse_erl_types_special:decode_interval_column(Binary, month, NumRows);
decode_column_data(<<"IntervalQuarter">>, NumRows, Binary) ->
    clickhouse_erl_types_special:decode_interval_column(Binary, quarter, NumRows);
decode_column_data(<<"IntervalYear">>, NumRows, Binary) ->
    clickhouse_erl_types_special:decode_interval_column(Binary, year, NumRows);
%% Special types - JSON
decode_column_data(<<"JSON">>, NumRows, Binary) ->
    clickhouse_erl_types_special:decode_json_column(Binary, NumRows);
%% Tuple types
decode_column_data(<<"Tuple(", _/binary>> = Type, NumRows, Binary) ->
    ElementTypes = clickhouse_erl_types_tuple:parse_tuple_type(Type),
    clickhouse_erl_types_tuple:decode_tuple_column(Binary, ElementTypes, NumRows);
%% Array types
decode_column_data(<<"Array(", _/binary>> = Type, NumRows, Binary) ->
    ElementType = clickhouse_erl_types_array:parse_array_type(Type),
    clickhouse_erl_types_array:decode_array_column(Binary, ElementType, NumRows);
%% Map types
decode_column_data(<<"Map(", _/binary>> = Type, NumRows, Binary) ->
    {KeyType, ValueType} = clickhouse_erl_types_map:parse_map_type(Type),
    clickhouse_erl_types_map:decode_map_column(Binary, KeyType, ValueType, NumRows);
%% Nullable types
decode_column_data(<<"Nullable(", _/binary>> = Type, NumRows, Binary) ->
    InnerType = clickhouse_erl_types_nullable:parse_nullable_type(Type),
    clickhouse_erl_types_nullable:decode_nullable_column(Binary, InnerType, NumRows);
%% LowCardinality types
decode_column_data(<<"LowCardinality(", _/binary>> = Type, NumRows, Binary) ->
    InnerType = clickhouse_erl_types_low_cardinality:parse_low_cardinality_type(Type),
    clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(Binary, InnerType, NumRows);
decode_column_data(Type, _NumRows, _Binary) ->
    %% Truncate type for logging (show first 50 bytes max)
    TruncatedType =
        case byte_size(Type) of
            Size when Size =< 50 -> Type;
            _ ->
                <<First50:50/binary, _/binary>> = Type,
                <<First50/binary, "...">>
        end,
    {error, {unknown_column_type, TruncatedType}}.

decode_fixed_width_integers(0, _Size, _Signedness, _Endianness, Binary, Acc) ->
    {ok, lists:reverse(Acc), Binary};
decode_fixed_width_integers(N, 8, unsigned, little, Binary, Acc) ->
    case Binary of
        <<Value:8/unsigned-integer, Rest/binary>> ->
            decode_fixed_width_integers(N - 1, 8, unsigned, little, Rest, [Value | Acc]);
        _ ->
            {error, truncated_data}
    end;
decode_fixed_width_integers(N, 8, signed, little, Binary, Acc) ->
    case Binary of
        <<Value:8/signed-integer, Rest/binary>> ->
            decode_fixed_width_integers(N - 1, 8, signed, little, Rest, [Value | Acc]);
        _ ->
            {error, truncated_data}
    end;
decode_fixed_width_integers(N, 16, unsigned, little, Binary, Acc) ->
    case Binary of
        <<Value:16/little-unsigned-integer, Rest/binary>> ->
            decode_fixed_width_integers(N - 1, 16, unsigned, little, Rest, [Value | Acc]);
        _ ->
            {error, truncated_data}
    end;
decode_fixed_width_integers(N, 16, signed, little, Binary, Acc) ->
    case Binary of
        <<Value:16/little-signed-integer, Rest/binary>> ->
            decode_fixed_width_integers(N - 1, 16, signed, little, Rest, [Value | Acc]);
        _ ->
            {error, truncated_data}
    end;
decode_fixed_width_integers(N, 32, unsigned, little, Binary, Acc) ->
    case Binary of
        <<Value:32/little-unsigned-integer, Rest/binary>> ->
            decode_fixed_width_integers(N - 1, 32, unsigned, little, Rest, [Value | Acc]);
        _ ->
            {error, truncated_data}
    end;
decode_fixed_width_integers(N, 32, signed, little, Binary, Acc) ->
    case Binary of
        <<Value:32/little-signed-integer, Rest/binary>> ->
            decode_fixed_width_integers(N - 1, 32, signed, little, Rest, [Value | Acc]);
        _ ->
            {error, truncated_data}
    end;
decode_fixed_width_integers(N, 64, unsigned, little, Binary, Acc) ->
    case Binary of
        <<Value:64/little-unsigned-integer, Rest/binary>> ->
            decode_fixed_width_integers(N - 1, 64, unsigned, little, Rest, [Value | Acc]);
        _ ->
            {error, truncated_data}
    end;
decode_fixed_width_integers(N, 64, signed, little, Binary, Acc) ->
    case Binary of
        <<Value:64/little-signed-integer, Rest/binary>> ->
            decode_fixed_width_integers(N - 1, 64, signed, little, Rest, [Value | Acc]);
        _ ->
            {error, truncated_data}
    end.

decode_strings(0, Binary, Acc) ->
    {ok, lists:reverse(Acc), Binary};
decode_strings(N, Binary, Acc) ->
    case clickhouse_erl_types_primitive:decode_string(Binary) of
        {ok, String, Rest} ->
            decode_strings(N - 1, Rest, [String | Acc]);
        Error ->
            Error
    end.

%% @doc Decode floating point numbers
decode_floats(0, _Size, _Endianness, Binary, Acc) ->
    {ok, lists:reverse(Acc), Binary};
decode_floats(N, 32, little, Binary, Acc) ->
    case Binary of
        <<Value:32/little-float, Rest/binary>> ->
            decode_floats(N - 1, 32, little, Rest, [Value | Acc]);
        _ ->
            {error, truncated_data}
    end;
decode_floats(N, 64, little, Binary, Acc) ->
    case Binary of
        <<Value:64/little-float, Rest/binary>> ->
            decode_floats(N - 1, 64, little, Rest, [Value | Acc]);
        _ ->
            {error, truncated_data}
    end.

%% @doc Encode BlockInfo structure for data blocks using field-based encoding.
%%
%% Format:
%% 1. Field 1: is_overflows (Bool) = false (0)
%% 2. Field 2: bucket_num (Int32) = -1 (for data blocks with rows)
%% 3. End Marker (0)
-spec encode_block_info() -> iolist().
encode_block_info() ->
    [
        %% Field 1: is_overflows = false
        clickhouse_erl_types_primitive:encode_varint(1),
        clickhouse_erl_types_integer:encode_bool(false),

        %% Field 2: bucket_num = -1 (for data blocks)
        clickhouse_erl_types_primitive:encode_varint(2),
        clickhouse_erl_types_integer:encode_int32(-1),

        %% End Marker
        clickhouse_erl_types_primitive:encode_varint(0)
    ].

%% @doc Encode BlockInfo structure for blank blocks (end-of-stream markers).
%%
%% Format:
%% 1. Field 1: is_overflows (Bool) = false (0)
%% 2. Field 2: bucket_num (Int32) = 0 (for blank blocks, NOT -1)
%% 3. End Marker (0)
-spec encode_blank_data_block_info() -> iolist().
encode_blank_data_block_info() ->
    [
        %% Field 1: is_overflows = false
        clickhouse_erl_types_primitive:encode_varint(1),
        clickhouse_erl_types_integer:encode_bool(false),

        %% Field 2: bucket_num = 0 (for blank blocks)
        clickhouse_erl_types_primitive:encode_varint(2),
        clickhouse_erl_types_integer:encode_int32(0),

        %% End Marker
        clickhouse_erl_types_primitive:encode_varint(0)
    ].

%% @doc Validate that all columns have the same row count.
%%
%% Returns ok if all columns have the same row count, or an error tuple
%% with column names and their respective row counts if there's a mismatch.
%%
%% Error format: {error, {row_count_mismatch, [{Name, Count}, ...]}}
-spec validate_row_counts([column_data()]) ->
    ok | {error, {row_count_mismatch, [{binary(), non_neg_integer()}]}}.
validate_row_counts([]) ->
    ok;
validate_row_counts(Columns) ->
    %% Extract row counts for each column
    RowCounts = lists:map(
        fun(#{name := Name, data := Data}) ->
            {Name, length(Data)}
        end,
        Columns
    ),

    %% Check if all row counts are the same
    case lists:usort([Count || {_Name, Count} <- RowCounts]) of
        [_SingleCount] ->
            %% All columns have the same row count
            ok;
        _MultipleCounts ->
            %% Row count mismatch detected
            {error, {row_count_mismatch, RowCounts}}
    end.

%% @doc Validate that all column names are binaries.
%%
%% Returns ok if all column names are binaries, or an error tuple
%% with the first non-binary column name found.
%%
%% Error format: {error, {invalid_column_name, Value}}
-spec validate_column_names([column_data()]) ->
    ok | {error, {invalid_column_name, term()}}.
validate_column_names([]) ->
    ok;
validate_column_names(Columns) ->
    validate_column_names_loop(Columns).

validate_column_names_loop([]) ->
    ok;
validate_column_names_loop([#{name := Name} | Rest]) ->
    case is_binary(Name) of
        true ->
            validate_column_names_loop(Rest);
        false ->
            {error, {invalid_column_name, Name}}
    end.

%% @doc Encode an empty data block (used to signal end of stream).
%%
%% Structure:
%% 1. Temporary Table Name (Empty String)
%% 2. Block Info (with BucketNum = 0 for blank blocks)
%% 3. Number of Columns (0)
%% 4. Number of Rows (0)
-spec encode_blank_data_block() -> iolist().
encode_blank_data_block() ->
    [
        %% 1. Temp Table Name (Empty)
        clickhouse_erl_types_primitive:encode_string(""),

        %% 2. Block Info (blank blocks use BucketNum = 0, not -1)
        encode_blank_data_block_info(),

        %% 3. Number of Columns (0)
        clickhouse_erl_types_primitive:encode_varint(0),

        %% 4. Number of Rows (0)
        clickhouse_erl_types_primitive:encode_varint(0)
    ].

%% @doc Encode a data block into an iolist.
%%
%% Encodes the block structure, metadata, and column data.
%% Returns {ok, iolist()}.
-spec encode_data_block(data_block(), non_neg_integer()) ->
    {ok, iolist()} | {error, term()}.
encode_data_block(Block, ProtocolVersion) ->
    #{
        columns := NumColumns,
        rows := NumRows,
        column_data := Columns
    } = Block,

    %% Header parts
    Header = [
        %% 1. Temp Table Name (Empty)
        clickhouse_erl_types_primitive:encode_string(""),

        %% 2. Block Info
        encode_block_info(),

        %% 3. Number of Columns
        clickhouse_erl_types_primitive:encode_varint(NumColumns),

        %% 4. Number of Rows
        clickhouse_erl_types_primitive:encode_varint(NumRows)
    ],

    %% 5. Columns Metadata and Data
    case encode_columns(Columns, ProtocolVersion, []) of
        {ok, EncodedColumns} ->
            {ok, [Header, EncodedColumns]};
        Error ->
            Error
    end.

encode_columns([], _ProtocolVersion, Acc) ->
    {ok, lists:reverse(Acc)};
encode_columns([Column | Rest], ProtocolVersion, Acc) ->
    #{
        name := Name,
        type := Type,
        data := Data
    } = Column,

    %% Encode Name
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),

    %% Encode Type
    TypeBin = clickhouse_erl_types_primitive:encode_string(Type),

    %% Encode Custom Serialization (if >= 54454)
    %% DBMS_MIN_REVISION_WITH_CUSTOM_SERIALIZATION = 54454
    CustomSer =
        case ProtocolVersion >= 54454 of
            % HasCustom = false
            true -> <<0>>;
            false -> <<>>
        end,

    %% Encode State (for types that require it, like JSON)
    State = encode_column_state(Type),

    %% Encode Data
    case encode_column_data(Type, Data) of
        {ok, EncodedData} ->
            ColumnBin = [NameBin, TypeBin, CustomSer, State, EncodedData],
            encode_columns(Rest, ProtocolVersion, [ColumnBin | Acc]);
        {error, Reason} ->
            {error, {type_mismatch, Name, Type, Reason}}
    end.

encode_column_data(Type, Data) ->
    case Type of
        <<"UInt8">> ->
            clickhouse_erl_types_column:encode_uint8_column(Data);
        <<"UInt16">> ->
            clickhouse_erl_types_column:encode_uint16_column(Data);
        <<"UInt32">> ->
            clickhouse_erl_types_column:encode_uint32_column(Data);
        <<"UInt64">> ->
            clickhouse_erl_types_column:encode_uint64_column(Data);
        <<"Int8">> ->
            clickhouse_erl_types_column:encode_int8_column(Data);
        <<"Int16">> ->
            clickhouse_erl_types_column:encode_int16_column(Data);
        <<"Int32">> ->
            clickhouse_erl_types_column:encode_int32_column(Data);
        <<"Int64">> ->
            clickhouse_erl_types_column:encode_int64_column(Data);
        <<"Int128">> ->
            clickhouse_erl_types_column:encode_int128_column(Data);
        <<"UInt128">> ->
            clickhouse_erl_types_column:encode_uint128_column(Data);
        <<"Int256">> ->
            clickhouse_erl_types_column:encode_int256_column(Data);
        <<"UInt256">> ->
            clickhouse_erl_types_column:encode_uint256_column(Data);
        <<"Float32">> ->
            clickhouse_erl_types_column:encode_float32_column(Data);
        <<"Float64">> ->
            clickhouse_erl_types_column:encode_float64_column(Data);
        <<"String">> ->
            clickhouse_erl_types_column:encode_string_column(Data);
        % Bool handles true/false
        <<"Bool">> ->
            clickhouse_erl_types_column:encode_bool_column(Data);
        <<"Date">> ->
            clickhouse_erl_types_column:encode_date_column(Data);
        <<"Date32">> ->
            clickhouse_erl_types_column:encode_date32_column(Data);
        <<"DateTime">> ->
            clickhouse_erl_types_column:encode_datetime_column(Data);
        <<"DateTime(", _/binary>> ->
            clickhouse_erl_types_column:encode_datetime_column(Data);
        <<"DateTime64(", Rest/binary>> ->
            % Extract precision from type string like "DateTime64(3)"
            case binary:split(Rest, <<")">>) of
                [PrecisionBin, _] ->
                    try binary_to_integer(PrecisionBin) of
                        Precision ->
                            clickhouse_erl_types_column:encode_datetime64_column(Data, Precision)
                    catch
                        % default to milliseconds
                        _:_ -> clickhouse_erl_types_column:encode_datetime64_column(Data, 3)
                    end;
                _ ->
                    % default to milliseconds
                    clickhouse_erl_types_column:encode_datetime64_column(Data, 3)
            end;
        % default to milliseconds
        <<"DateTime64">> ->
            clickhouse_erl_types_column:encode_datetime64_column(Data, 3);
        <<"Time">> ->
            clickhouse_erl_types_column:encode_time_column(Data);
        <<"Time64">> ->
            clickhouse_erl_types_column:encode_time64_column(Data);
        <<"UUID">> ->
            clickhouse_erl_types_column:encode_uuid_column(Data);
        <<"IPv4">> ->
            clickhouse_erl_types_column:encode_ipv4_column(Data);
        <<"IPv6">> ->
            clickhouse_erl_types_column:encode_ipv6_column(Data);
        <<"Nothing">> ->
            clickhouse_erl_types_column:encode_nothing_column(Data);
        <<"Point">> ->
            clickhouse_erl_types_column:encode_point_column(Data);
        <<"JSON">> ->
            clickhouse_erl_types_column:encode_json_column(Data);
        <<"Decimal32(", _/binary>> = DecimalType ->
            case clickhouse_erl_types_decimal:parse_decimal_type(DecimalType) of
                {ok, {decimal32, _Precision, Scale}} ->
                    clickhouse_erl_types_column:encode_decimal32_column(Data, Scale);
                {error, Reason} ->
                    {error, Reason}
            end;
        <<"Decimal64(", _/binary>> = DecimalType ->
            case clickhouse_erl_types_decimal:parse_decimal_type(DecimalType) of
                {ok, {decimal64, _Precision, Scale}} ->
                    clickhouse_erl_types_column:encode_decimal64_column(Data, Scale);
                {error, Reason} ->
                    {error, Reason}
            end;
        <<"Decimal128(", _/binary>> = DecimalType ->
            case clickhouse_erl_types_decimal:parse_decimal_type(DecimalType) of
                {ok, {decimal128, _Precision, Scale}} ->
                    clickhouse_erl_types_column:encode_decimal128_column(Data, Scale);
                {error, Reason} ->
                    {error, Reason}
            end;
        <<"Decimal256(", _/binary>> = DecimalType ->
            case clickhouse_erl_types_decimal:parse_decimal_type(DecimalType) of
                {ok, {decimal256, _Precision, Scale}} ->
                    clickhouse_erl_types_column:encode_decimal256_column(Data, Scale);
                {error, Reason} ->
                    {error, Reason}
            end;
        <<"Enum8(", _/binary>> = EnumType ->
            case clickhouse_erl_types_enum:parse_enum_type(EnumType) of
                {ok, {enum8, Mappings}} ->
                    clickhouse_erl_types_column:encode_enum8_column(Data, Mappings);
                {error, Reason} ->
                    {error, Reason}
            end;
        <<"Enum16(", _/binary>> = EnumType ->
            case clickhouse_erl_types_enum:parse_enum_type(EnumType) of
                {ok, {enum16, Mappings}} ->
                    clickhouse_erl_types_column:encode_enum16_column(Data, Mappings);
                {error, Reason} ->
                    {error, Reason}
            end;
        <<"IntervalSecond">> ->
            clickhouse_erl_types_column:encode_interval_column(Data, second);
        <<"IntervalMinute">> ->
            clickhouse_erl_types_column:encode_interval_column(Data, minute);
        <<"IntervalHour">> ->
            clickhouse_erl_types_column:encode_interval_column(Data, hour);
        <<"IntervalDay">> ->
            clickhouse_erl_types_column:encode_interval_column(Data, day);
        <<"IntervalWeek">> ->
            clickhouse_erl_types_column:encode_interval_column(Data, week);
        <<"IntervalMonth">> ->
            clickhouse_erl_types_column:encode_interval_column(Data, month);
        <<"IntervalQuarter">> ->
            clickhouse_erl_types_column:encode_interval_column(Data, quarter);
        <<"IntervalYear">> ->
            clickhouse_erl_types_column:encode_interval_column(Data, year);
        <<"Tuple(", _/binary>> = TupleType ->
            % Parse tuple type and encode
            ElementTypes = clickhouse_erl_types_tuple:parse_tuple_type(TupleType),
            clickhouse_erl_types_tuple:encode_tuple_column(Data, ElementTypes);
        <<"Array(", _/binary>> = ArrayType ->
            % Parse array type and encode
            ElementType = clickhouse_erl_types_array:parse_array_type(ArrayType),
            clickhouse_erl_types_array:encode_array_column(Data, ElementType);
        <<"Map(", _/binary>> = MapType ->
            % Parse map type and encode
            {KeyType, ValueType} = clickhouse_erl_types_map:parse_map_type(MapType),
            clickhouse_erl_types_map:encode_map_column(Data, KeyType, ValueType);
        <<"Nullable(", _/binary>> = NullableType ->
            % Parse nullable type and encode
            InnerType = clickhouse_erl_types_nullable:parse_nullable_type(NullableType),
            clickhouse_erl_types_nullable:encode_nullable_column(Data, InnerType);
        <<"LowCardinality(", _/binary>> = LowCardinalityType ->
            % Parse low cardinality type and encode
            InnerType = clickhouse_erl_types_low_cardinality:parse_low_cardinality_type(
                LowCardinalityType
            ),
            % Encode state (version number)
            StateEncoded = clickhouse_erl_types_integer:encode_int64(1),
            % Encode column data
            case
                clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(
                    Data, InnerType
                )
            of
                {ok, ColumnEncoded} ->
                    {ok, iolist_to_binary([StateEncoded, ColumnEncoded])};
                Error ->
                    Error
            end;
        _ ->
            {error, {unknown_type, Type}}
    end.

%% @doc Encode column state for types that require it (like JSON)
%% JSON type requires a uint64 version number (1) before the column data
-spec encode_column_state(binary()) -> binary().
encode_column_state(<<"JSON">>) ->
    %% JSON serialization version = 1
    <<1:64/little-unsigned-integer>>;
encode_column_state(_Type) ->
    %% Most types don't require state
    <<>>.

%% @doc Decode column state for types that require it (like JSON)
%% JSON type requires reading and validating a uint64 version number
-spec decode_column_state(binary(), binary()) -> {ok, binary()} | {error, term()}.
decode_column_state(<<"JSON">>, <<Version:64/little-unsigned-integer, Rest/binary>>) ->
    case Version of
        1 ->
            %% String serialization (simple format)
            {ok, Rest};
        0 ->
            %% Object serialization (complex columnar format)
            %% TODO: Implement proper Object deserialization
            %% For now, return error with helpful message
            {error,
                {json_object_serialization_not_supported,
                    "ClickHouse is using Object serialization for JSON. "
                    "Enable 'output_format_native_write_json_as_string' setting "
                    "or implement Object serialization support."}};
        _ ->
            {error, {invalid_json_serialization_version, Version}}
    end;
decode_column_state(<<"JSON">>, _Binary) ->
    {error, {truncated_data, json_state}};
decode_column_state(_Type, Binary) ->
    %% Most types don't require state
    {ok, Binary}.
