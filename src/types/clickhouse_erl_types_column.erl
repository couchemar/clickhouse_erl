%% @doc ClickHouse column-oriented data encoding.
%%
%% This module provides functions for encoding columns of data for bulk operations.
-module(clickhouse_erl_types_column).

%% Column encoders
-export([
    encode_bool_column/1,
    encode_uint8_column/1,
    encode_uint16_column/1,
    encode_uint32_column/1,
    encode_uint64_column/1,
    encode_int8_column/1,
    encode_int16_column/1,
    encode_int32_column/1,
    encode_int64_column/1,
    encode_float32_column/1,
    encode_float64_column/1,
    encode_string_column/1,
    encode_date_column/1,
    encode_date32_column/1,
    encode_datetime_column/1,
    encode_datetime64_column/2,
    % Extended integer encoders
    encode_int128_column/1,
    encode_uint128_column/1,
    encode_int256_column/1,
    encode_uint256_column/1,
    % Decimal encoders
    encode_decimal32_column/2,
    encode_decimal64_column/2,
    encode_decimal128_column/2,
    encode_decimal256_column/2,
    % Enum encoders
    encode_enum8_column/2,
    encode_enum16_column/2,
    % Network type encoders
    encode_ipv4_column/1,
    encode_ipv6_column/1,
    % UUID encoder
    encode_uuid_column/1,
    % Time encoders
    encode_time_column/1,
    encode_time64_column/1,
    % Special type encoders
    encode_nothing_column/1,
    encode_point_column/1,
    encode_interval_column/2,
    encode_json_column/1,
    % Composite type encoders
    encode_tuple_column/2,
    encode_array_column/2,
    encode_map_column/3,
    encode_nullable_column/2,
    encode_low_cardinality_column/2,
    % Generic dispatcher
    encode_column/2
]).

-ignore_xref([
    encode_tuple_column/2,
    encode_array_column/2,
    encode_map_column/3,
    encode_nullable_column/2,
    encode_low_cardinality_column/2
]).

-include_lib("kernel/include/logger.hrl").

%%%===================================================================
%%% Column Encoders
%%%===================================================================

%% @doc Encode a column of Bool values.
%% Converts boolean atoms to UInt8 (true -> 1, false -> 0).
-spec encode_bool_column([boolean()]) -> {ok, iolist()} | {error, term()}.
encode_bool_column(Values) ->
    %% Convert booleans to integers (true -> 1, false -> 0)
    case convert_bools_to_ints(Values, []) of
        {ok, IntValues} ->
            encode_column_internal(IntValues, fun clickhouse_erl_types_integer:encode_uint8/1);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Encode a column of UInt8 values.
-spec encode_uint8_column([non_neg_integer()]) -> {ok, iolist()} | {error, term()}.
encode_uint8_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_integer:encode_uint8/1).

%% @doc Encode a column of UInt16 values.
-spec encode_uint16_column([non_neg_integer()]) -> {ok, iolist()} | {error, term()}.
encode_uint16_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_integer:encode_uint16/1).

%% @doc Encode a column of UInt32 values.
-spec encode_uint32_column([non_neg_integer()]) -> {ok, iolist()} | {error, term()}.
encode_uint32_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_integer:encode_uint32/1).

%% @doc Encode a column of UInt64 values.
-spec encode_uint64_column([non_neg_integer()]) -> {ok, iolist()} | {error, term()}.
encode_uint64_column(Values) ->
    encode_column_internal(Values, fun encode_uint64_internal/1).

%% @doc Encode a column of Int8 values.
-spec encode_int8_column([integer()]) -> {ok, iolist()} | {error, term()}.
encode_int8_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_integer:encode_int8/1).

%% @doc Encode a column of Int16 values.
-spec encode_int16_column([integer()]) -> {ok, iolist()} | {error, term()}.
encode_int16_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_integer:encode_int16/1).

%% @doc Encode a column of Int32 values.
-spec encode_int32_column([integer()]) -> {ok, iolist()} | {error, term()}.
encode_int32_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_integer:encode_int32/1).

%% @doc Encode a column of Int64 values.
-spec encode_int64_column([integer()]) -> {ok, iolist()} | {error, term()}.
encode_int64_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_integer:encode_int64/1).

%% @doc Encode a column of Float32 values.
-spec encode_float32_column([float() | integer() | atom()]) -> {ok, iolist()} | {error, term()}.
encode_float32_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_float:encode_float32/1).

%% @doc Encode a column of Float64 values.
-spec encode_float64_column([float() | integer() | atom()]) -> {ok, iolist()} | {error, term()}.
encode_float64_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_float:encode_float64/1).

%% @doc Encode a column of String values.
-spec encode_string_column([string() | binary()]) -> {ok, iolist()} | {error, term()}.
encode_string_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_primitive:encode_string/1).

%% @doc Encode a column of Date values.
-spec encode_date_column([calendar:date()]) -> {ok, iolist()} | {error, term()}.
encode_date_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_temporal:encode_date/1).

%% @doc Encode a column of Date32 values.
-spec encode_date32_column([calendar:date()]) -> {ok, iolist()} | {error, term()}.
encode_date32_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_temporal:encode_date32/1).

%% @doc Encode a column of DateTime values.
-spec encode_datetime_column([calendar:datetime()]) -> {ok, iolist()} | {error, term()}.
encode_datetime_column(Values) ->
    encode_column_internal(Values, fun clickhouse_erl_types_temporal:encode_datetime/1).

%% @doc Encode a column of DateTime64 values.
%% Values can be integers representing ticks or datetime tuples.
%% Precision determines the scale (0=seconds, 3=milliseconds, 6=microseconds, 9=nanoseconds).
-spec encode_datetime64_column([calendar:datetime() | integer()], non_neg_integer()) ->
    {ok, iolist()} | {error, term()}.
encode_datetime64_column(Values, Precision) ->
    encode_column_internal(Values, fun(V) ->
        clickhouse_erl_types_temporal:encode_datetime64(V, Precision)
    end).

%%%===================================================================
%%% Extended Integer Encoders
%%%===================================================================

%% @doc Encode a column of Int128 values.
-spec encode_int128_column([integer()]) -> {ok, iolist()} | {error, term()}.
encode_int128_column(Values) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_extended_integer:encode_int128(V) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%% @doc Encode a column of UInt128 values.
-spec encode_uint128_column([non_neg_integer()]) -> {ok, iolist()} | {error, term()}.
encode_uint128_column(Values) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_extended_integer:encode_uint128(V) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%% @doc Encode a column of Int256 values.
-spec encode_int256_column([integer()]) -> {ok, iolist()} | {error, term()}.
encode_int256_column(Values) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_extended_integer:encode_int256(V) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%% @doc Encode a column of UInt256 values.
-spec encode_uint256_column([non_neg_integer()]) -> {ok, iolist()} | {error, term()}.
encode_uint256_column(Values) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_extended_integer:encode_uint256(V) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%%%===================================================================
%%% Decimal Encoders
%%%===================================================================

%% @doc Encode a column of Decimal32 values.
%% Values should be {decimal, Value, Scale} tuples.
-spec encode_decimal32_column([{decimal, integer(), non_neg_integer()}], non_neg_integer()) ->
    {ok, iolist()} | {error, term()}.
encode_decimal32_column(Values, Scale) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_decimal:encode_decimal32(V, Scale) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%% @doc Encode a column of Decimal64 values.
%% Values should be {decimal, Value, Scale} tuples.
-spec encode_decimal64_column([{decimal, integer(), non_neg_integer()}], non_neg_integer()) ->
    {ok, iolist()} | {error, term()}.
encode_decimal64_column(Values, Scale) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_decimal:encode_decimal64(V, Scale) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%% @doc Encode a column of Decimal128 values.
%% Values should be {decimal, Value, Scale} tuples.
-spec encode_decimal128_column([{decimal, integer(), non_neg_integer()}], non_neg_integer()) ->
    {ok, iolist()} | {error, term()}.
encode_decimal128_column(Values, Scale) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_decimal:encode_decimal128(V, Scale) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%% @doc Encode a column of Decimal256 values.
%% Values should be {decimal, Value, Scale} tuples.
-spec encode_decimal256_column([{decimal, integer(), non_neg_integer()}], non_neg_integer()) ->
    {ok, iolist()} | {error, term()}.
encode_decimal256_column(Values, Scale) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_decimal:encode_decimal256(V, Scale) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%%%===================================================================
%%% Enum Encoders
%%%===================================================================

%% @doc Encode a column of Enum8 values.
%% Values can be atoms, binaries, or integers.
-spec encode_enum8_column([atom() | binary() | integer()], map()) ->
    {ok, iolist()} | {error, term()}.
encode_enum8_column(Values, Mappings) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_enum:encode_enum8(V, Mappings) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%% @doc Encode a column of Enum16 values.
%% Values can be atoms, binaries, or integers.
-spec encode_enum16_column([atom() | binary() | integer()], map()) ->
    {ok, iolist()} | {error, term()}.
encode_enum16_column(Values, Mappings) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_enum:encode_enum16(V, Mappings) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%%%===================================================================
%%% Network Type Encoders
%%%===================================================================

%% @doc Encode a column of IPv4 values.
%% Values can be tuples {A, B, C, D}, binary strings, or integers.
-spec encode_ipv4_column([tuple() | binary() | non_neg_integer()]) ->
    {ok, iolist()} | {error, term()}.
encode_ipv4_column(Values) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_network:encode_ipv4(V) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%% @doc Encode a column of IPv6 values.
%% Values can be tuples or binary strings.
-spec encode_ipv6_column([tuple() | binary()]) -> {ok, iolist()} | {error, term()}.
encode_ipv6_column(Values) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_network:encode_ipv6(V) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%%%===================================================================
%%% UUID Encoder
%%%===================================================================

%% @doc Encode a column of UUID values.
%% Values can be binary strings (with or without hyphens) or 16-byte binaries.
-spec encode_uuid_column([binary()]) -> {ok, iolist()} | {error, term()}.
encode_uuid_column(Values) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_uuid:encode_uuid(V) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%%%===================================================================
%%% Time Encoders
%%%===================================================================

%% @doc Encode a column of Time values.
%% Values can be {Hour, Minute, Second} tuples or integers (seconds since midnight).
-spec encode_time_column([tuple() | non_neg_integer()]) -> {ok, iolist()} | {error, term()}.
encode_time_column(Values) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_time:encode_time(V) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%% @doc Encode a column of Time64 values.
%% Values can be {Hour, Minute, Second, Nanosecond} tuples or integers (nanoseconds since midnight).
-spec encode_time64_column([tuple() | non_neg_integer()]) -> {ok, iolist()} | {error, term()}.
encode_time64_column(Values) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_time:encode_time64(V) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%%%===================================================================
%%% Special Type Encoders
%%%===================================================================

%% @doc Encode a column of Nothing values.
%% Accepts any values (all ignored) and encodes as zero bytes.
-spec encode_nothing_column([term()]) -> {ok, iolist()} | {error, term()}.
encode_nothing_column(Values) ->
    encode_column_internal(Values, fun(V) ->
        {ok, Bin} = clickhouse_erl_types_special:encode_nothing(V),
        Bin
    end).

%% @doc Encode a column of Point values.
%% Values should be {X, Y} tuples where X and Y are floats.
-spec encode_point_column([{float(), float()}]) -> {ok, iolist()} | {error, term()}.
encode_point_column(Values) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_special:encode_point(V) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%% @doc Encode a column of Interval values.
%% Values should be {interval, Scale, Value} tuples or integers.
-spec encode_interval_column([{interval, atom(), integer()} | integer()], atom()) ->
    {ok, iolist()} | {error, term()}.
encode_interval_column(Values, Scale) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_special:encode_interval(V, Scale) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%% @doc Encode a column of JSON values.
%% Values can be binary strings, maps, or lists.
-spec encode_json_column([binary() | map() | list()]) -> {ok, iolist()} | {error, term()}.
encode_json_column(Values) ->
    encode_column_internal(Values, fun(V) ->
        case clickhouse_erl_types_special:encode_json(V) of
            {ok, Bin} -> Bin;
            {error, Reason} -> {error, Reason}
        end
    end).

%%%===================================================================
%%% Composite Type Encoders
%%%===================================================================

%% @doc Encode a column of Tuple values.
%% Each value should be an Erlang tuple matching the element types.
-spec encode_tuple_column([tuple()], [term()]) -> {ok, iolist()} | {error, term()}.
encode_tuple_column(Values, ElementTypes) ->
    clickhouse_erl_types_tuple:encode_tuple_column(Values, ElementTypes).

%% @doc Encode a column of Array values.
%% Each value should be an Erlang list of elements matching the element type.
-spec encode_array_column([list()], term()) -> {ok, iolist()} | {error, term()}.
encode_array_column(Values, ElementType) ->
    clickhouse_erl_types_array:encode_array_column(Values, ElementType).

%% @doc Encode a column of Map values.
%% Each value should be an Erlang map with keys and values matching the specified types.
-spec encode_map_column([map()], term(), term()) -> {ok, iolist()} | {error, term()}.
encode_map_column(Values, KeyType, ValueType) ->
    clickhouse_erl_types_map:encode_map_column(Values, KeyType, ValueType).

%% @doc Encode a column of Nullable values.
%% Each value should be {null} or {value, ActualValue}.
-spec encode_nullable_column([{null} | {value, term()}], term()) ->
    {ok, iolist()} | {error, term()}.
encode_nullable_column(Values, InnerType) ->
    clickhouse_erl_types_nullable:encode_nullable_column(Values, InnerType).

%% @doc Encode a column of LowCardinality values.
%% Values are encoded with dictionary compression for high-cardinality columns.
-spec encode_low_cardinality_column([term()], term()) -> {ok, iolist()} | {error, term()}.
encode_low_cardinality_column(Values, InnerType) ->
    clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(Values, InnerType).

%% @doc Generic column encoding dispatch
-spec encode_column(term(), [term()]) -> {ok, iolist()} | {error, term()}.
encode_column(uint8, Values) ->
    encode_uint8_column(Values);
encode_column(uint16, Values) ->
    encode_uint16_column(Values);
encode_column(uint32, Values) ->
    encode_uint32_column(Values);
encode_column(uint64, Values) ->
    encode_uint64_column(Values);
encode_column(int8, Values) ->
    encode_int8_column(Values);
encode_column(int16, Values) ->
    encode_int16_column(Values);
encode_column(int32, Values) ->
    encode_int32_column(Values);
encode_column(int64, Values) ->
    encode_int64_column(Values);
encode_column(int128, Values) ->
    encode_int128_column(Values);
encode_column(uint128, Values) ->
    encode_uint128_column(Values);
encode_column(int256, Values) ->
    encode_int256_column(Values);
encode_column(uint256, Values) ->
    encode_uint256_column(Values);
encode_column(float32, Values) ->
    encode_float32_column(Values);
encode_column(float64, Values) ->
    encode_float64_column(Values);
encode_column(bool, Values) ->
    encode_bool_column(Values);
encode_column(string, Values) ->
    encode_string_column(Values);
encode_column(date, Values) ->
    encode_date_column(Values);
encode_column(date32, Values) ->
    encode_date32_column(Values);
encode_column(datetime, Values) ->
    encode_datetime_column(Values);
encode_column({datetime64, Precision}, Values) ->
    encode_datetime64_column(Values, Precision);
encode_column({decimal32, _Precision, Scale}, Values) ->
    encode_decimal32_column(Values, Scale);
encode_column({decimal64, _Precision, Scale}, Values) ->
    encode_decimal64_column(Values, Scale);
encode_column({decimal128, _Precision, Scale}, Values) ->
    encode_decimal128_column(Values, Scale);
encode_column({decimal256, _Precision, Scale}, Values) ->
    encode_decimal256_column(Values, Scale);
encode_column({enum8, Mappings}, Values) ->
    encode_enum8_column(Values, Mappings);
encode_column({enum16, Mappings}, Values) ->
    encode_enum16_column(Values, Mappings);
encode_column(ipv4, Values) ->
    encode_ipv4_column(Values);
encode_column(ipv6, Values) ->
    encode_ipv6_column(Values);
encode_column(uuid, Values) ->
    encode_uuid_column(Values);
encode_column(time, Values) ->
    encode_time_column(Values);
encode_column(time64, Values) ->
    encode_time64_column(Values);
encode_column(nothing, Values) ->
    encode_nothing_column(Values);
encode_column(point, Values) ->
    encode_point_column(Values);
encode_column({interval, Scale}, Values) ->
    encode_interval_column(Values, Scale);
encode_column(json, Values) ->
    encode_json_column(Values);
encode_column({tuple, ElementTypes}, Values) ->
    clickhouse_erl_types_tuple:encode_tuple_column(Values, ElementTypes);
encode_column({array, ElementType}, Values) ->
    clickhouse_erl_types_array:encode_array_column(Values, ElementType);
encode_column({map, KeyType, ValueType}, Values) ->
    clickhouse_erl_types_map:encode_map_column(Values, KeyType, ValueType);
encode_column({nullable, InnerType}, Values) ->
    clickhouse_erl_types_nullable:encode_nullable_column(Values, InnerType);
encode_column({low_cardinality, InnerType}, Values) ->
    clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(Values, InnerType);
encode_column(Type, _Values) ->
    {error, {unsupported_type, Type}}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @doc Internal helper to map encoder over values
-spec encode_column_internal([term()], fun((term()) -> binary() | {error, term()})) ->
    {ok, iolist()} | {error, term()}.
encode_column_internal(Values, Encoder) ->
    encode_column_internal(Values, Encoder, []).

%% @doc Internal helper with accumulator
-spec encode_column_internal([term()], fun((term()) -> binary() | {error, term()}), [binary()]) ->
    {ok, iolist()} | {error, term()}.
encode_column_internal([], _Encoder, Acc) ->
    {ok, lists:reverse(Acc)};
encode_column_internal([V | Rest], Encoder, Acc) ->
    case Encoder(V) of
        Bin when is_binary(Bin) ->
            encode_column_internal(Rest, Encoder, [Bin | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Convert boolean values to integers for Bool column encoding
-spec convert_bools_to_ints([boolean()], [0 | 1]) -> {ok, [0 | 1]} | {error, term()}.
convert_bools_to_ints([], Acc) ->
    {ok, lists:reverse(Acc)};
convert_bools_to_ints([true | Rest], Acc) ->
    convert_bools_to_ints(Rest, [1 | Acc]);
convert_bools_to_ints([false | Rest], Acc) ->
    convert_bools_to_ints(Rest, [0 | Acc]);
convert_bools_to_ints([Val | _], _Acc) ->
    {error, {invalid_value, #{value => Val, expected_type => boolean, type => bool}}}.

%% @doc Internal UInt64 encoder for column encoding
-spec encode_uint64_internal(non_neg_integer()) -> binary() | {error, term()}.
encode_uint64_internal(N) when is_integer(N), N >= 0, N =< 18446744073709551615 ->
    <<N:64/little-unsigned-integer>>;
encode_uint64_internal(N) ->
    {error, {value_out_of_range, #{value => N, type => uint64}}}.
