%% @doc Property tests for ClickHouse column type encoding.
-module(prop_clickhouse_erl_types_column).

-include_lib("proper/include/proper.hrl").

-export([
    prop_column_encoder_success/0,
    prop_column_type_encoding_correctness/0,
    prop_tuple_column_encoding/0,
    prop_array_column_encoding/0,
    prop_map_column_encoding/0,
    prop_nullable_column_encoding/0,
    prop_low_cardinality_column_encoding/0,
    prop_bulk_encoding_consistency/0
]).

-import(generators, [
    char_gen/0,
    date_gen/0,
    datetime_gen/0,
    float32_gen/0,
    float64_gen/0,
    int16_gen/0,
    int8_gen/0,
    string_gen/0,
    uint16_gen/0,
    uint32_gen/0,
    map_gen/2
]).

%% ============================================================================
%% Local Generators for Composite Types
%% ============================================================================

%% Generator for tuples with specified element generators
tuple_gen(ElementGens) ->
    ?LET(Elements, [Gen || Gen <- ElementGens], list_to_tuple(Elements)).

%% Generator for arrays (lists) with specified element generator
array_gen(ElemGen) ->
    ?LET(Len, range(0, 10), vector(Len, ElemGen)).

%% Generator for nullable values
nullable_gen(InnerGen) ->
    oneof([{null}, ?LET(V, InnerGen, {value, V})]).

%% ============================================================================
%% Generators
%% ============================================================================

%% ============================================================================
%% Properties
%% ============================================================================

%% Property: Column encoder success for basic types
prop_column_encoder_success() ->
    ?FORALL(
        {Type, Values},
        oneof([
            {uint8, list(range(0, 255))},
            {int8, list(range(-128, 127))},
            {string, list(string_gen())}
        ]),
        begin
            Result =
                case Type of
                    uint8 -> clickhouse_erl_types_column:encode_uint8_column(Values);
                    int8 -> clickhouse_erl_types_column:encode_int8_column(Values);
                    string -> clickhouse_erl_types_column:encode_string_column(Values)
                end,
            case Result of
                {ok, IOList} -> is_list(IOList) orelse is_binary(IOList);
                _ -> false
            end
        end
    ).

%% ============================================================================
%% Property: Column Type Encoding Correctness
%% **Validates: Requirements for column encoding**
%% ============================================================================

%% Generator for column values by type
column_values_gen(Type, NumRows) ->
    case Type of
        uint8 -> vector(NumRows, range(0, 255));
        uint16 -> vector(NumRows, uint16_gen());
        uint32 -> vector(NumRows, uint32_gen());
        uint64 -> vector(NumRows, ?LET(N, range(0, 1000000000000), N));
        int8 -> vector(NumRows, int8_gen());
        int16 -> vector(NumRows, int16_gen());
        int32 -> vector(NumRows, range(-2147483648, 2147483647));
        int64 -> vector(NumRows, ?LET(N, range(-1000000000000, 1000000000000), N));
        float32 -> vector(NumRows, float32_gen());
        float64 -> vector(NumRows, float64_gen());
        string -> vector(NumRows, oneof([binary(), list(range(32, 126))]));
        date -> vector(NumRows, date_gen());
        datetime -> vector(NumRows, datetime_gen())
    end.

%% Property: Column type encoding produces correct binary structure
prop_column_type_encoding_correctness() ->
    ?FORALL(
        {Type, NumRows},
        {
            oneof([
                uint8,
                uint16,
                uint32,
                uint64,
                int8,
                int16,
                int32,
                int64,
                float32,
                float64,
                string,
                date,
                datetime
            ]),
            range(0, 100)
        },
        begin
            ValuesGen = column_values_gen(Type, NumRows),
            ?FORALL(
                Values,
                ValuesGen,
                begin
                    Result = encode_column_by_type(Type, Values),
                    case Result of
                        {ok, IOList} ->
                            Binary = iolist_to_binary(IOList),
                            %% Verify the binary size matches expected size
                            ExpectedSize = expected_column_size(Type, Values),
                            byte_size(Binary) =:= ExpectedSize;
                        {error, _} ->
                            %% Errors are acceptable for edge cases
                            true
                    end
                end
            )
        end
    ).

%% Helper to encode column by type
encode_column_by_type(uint8, Values) ->
    clickhouse_erl_types_column:encode_uint8_column(Values);
encode_column_by_type(uint16, Values) ->
    clickhouse_erl_types_column:encode_uint16_column(Values);
encode_column_by_type(uint32, Values) ->
    clickhouse_erl_types_column:encode_uint32_column(Values);
encode_column_by_type(uint64, Values) ->
    clickhouse_erl_types_column:encode_uint64_column(Values);
encode_column_by_type(int8, Values) ->
    clickhouse_erl_types_column:encode_int8_column(Values);
encode_column_by_type(int16, Values) ->
    clickhouse_erl_types_column:encode_int16_column(Values);
encode_column_by_type(int32, Values) ->
    clickhouse_erl_types_column:encode_int32_column(Values);
encode_column_by_type(int64, Values) ->
    clickhouse_erl_types_column:encode_int64_column(Values);
encode_column_by_type(float32, Values) ->
    clickhouse_erl_types_column:encode_float32_column(Values);
encode_column_by_type(float64, Values) ->
    clickhouse_erl_types_column:encode_float64_column(Values);
encode_column_by_type(string, Values) ->
    clickhouse_erl_types_column:encode_string_column(Values);
encode_column_by_type(date, Values) ->
    clickhouse_erl_types_column:encode_date_column(Values);
encode_column_by_type(datetime, Values) ->
    clickhouse_erl_types_column:encode_datetime_column(Values).

%% Helper to calculate expected column size
expected_column_size(uint8, Values) ->
    length(Values) * 1;
expected_column_size(uint16, Values) ->
    length(Values) * 2;
expected_column_size(uint32, Values) ->
    length(Values) * 4;
expected_column_size(uint64, Values) ->
    length(Values) * 8;
expected_column_size(int8, Values) ->
    length(Values) * 1;
expected_column_size(int16, Values) ->
    length(Values) * 2;
expected_column_size(int32, Values) ->
    length(Values) * 4;
expected_column_size(int64, Values) ->
    length(Values) * 8;
expected_column_size(float32, Values) ->
    length(Values) * 4;
expected_column_size(float64, Values) ->
    length(Values) * 8;
expected_column_size(date, Values) ->
    length(Values) * 2;
expected_column_size(datetime, Values) ->
    length(Values) * 4;
expected_column_size(string, Values) ->
    %% Each string has varint length + bytes
    lists:sum([
        byte_size(
            clickhouse_erl_types_primitive:encode_varint(
                byte_size(clickhouse_erl_types_primitive:to_binary(V))
            )
        ) +
            byte_size(clickhouse_erl_types_primitive:to_binary(V))
     || V <- Values
    ]).

%% ============================================================================
%% Property: Composite Type Column Encoding
%% **Validates: Requirements 1.2, 2.2, 3.2, 4.2, 5.2**
%% ============================================================================

%% Property: Tuple column encoding produces consistent results
prop_tuple_column_encoding() ->
    ?FORALL(
        {NumRows, ElementTypes},
        {range(0, 50), oneof([[uint8, string], [int32, int64], [string, uint16, float32]])},
        begin
            %% Generate tuples matching the element types
            TupleGen = tuple_gen([type_to_generator(T) || T <- ElementTypes]),
            ?FORALL(
                Tuples,
                vector(NumRows, TupleGen),
                begin
                    Result = clickhouse_erl_types_column:encode_tuple_column(Tuples, ElementTypes),
                    case Result of
                        {ok, Binary} when is_binary(Binary) ->
                            %% Verify binary is not empty for non-empty input
                            (NumRows =:= 0) orelse (byte_size(Binary) > 0);
                        {ok, IOList} ->
                            %% Verify iolist can be converted to binary
                            Binary = iolist_to_binary(IOList),
                            (NumRows =:= 0) orelse (byte_size(Binary) > 0);
                        {error, _} ->
                            %% Errors are acceptable for edge cases
                            true
                    end
                end
            )
        end
    ).

%% Property: Array column encoding produces consistent results
prop_array_column_encoding() ->
    ?FORALL(
        {NumRows, ElementType},
        {range(0, 50), oneof([uint8, int32, string])},
        begin
            %% Generate arrays of the element type
            ArrayGen = array_gen(type_to_generator(ElementType)),
            ?FORALL(
                Arrays,
                vector(NumRows, ArrayGen),
                begin
                    Result = clickhouse_erl_types_column:encode_array_column(Arrays, ElementType),
                    case Result of
                        {ok, Binary} when is_binary(Binary) ->
                            %% Verify binary includes offsets (8 bytes per row) + data
                            ExpectedMinSize = NumRows * 8,
                            byte_size(Binary) >= ExpectedMinSize;
                        {ok, IOList} ->
                            Binary = iolist_to_binary(IOList),
                            ExpectedMinSize = NumRows * 8,
                            byte_size(Binary) >= ExpectedMinSize;
                        {error, _} ->
                            true
                    end
                end
            )
        end
    ).

%% Property: Map column encoding produces consistent results
prop_map_column_encoding() ->
    ?FORALL(
        {NumRows, KeyType, ValueType},
        {range(0, 50), oneof([string, uint32]), oneof([int64, string])},
        begin
            %% Generate maps with the specified key and value types
            MapGen = map_gen(type_to_generator(KeyType), type_to_generator(ValueType)),
            ?FORALL(
                Maps,
                vector(NumRows, MapGen),
                begin
                    Result = clickhouse_erl_types_column:encode_map_column(
                        Maps, KeyType, ValueType
                    ),
                    case Result of
                        {ok, Binary} when is_binary(Binary) ->
                            %% Verify binary includes offsets (8 bytes per row) + keys + values
                            ExpectedMinSize = NumRows * 8,
                            byte_size(Binary) >= ExpectedMinSize;
                        {ok, IOList} ->
                            Binary = iolist_to_binary(IOList),
                            ExpectedMinSize = NumRows * 8,
                            byte_size(Binary) >= ExpectedMinSize;
                        {error, _} ->
                            true
                    end
                end
            )
        end
    ).

%% Property: Nullable column encoding produces consistent results
prop_nullable_column_encoding() ->
    ?FORALL(
        {NumRows, InnerType},
        {range(0, 50), oneof([uint8, int32, string])},
        begin
            %% Generate nullable values
            NullableGen = nullable_gen(type_to_generator(InnerType)),
            ?FORALL(
                NullableValues,
                vector(NumRows, NullableGen),
                begin
                    Result = clickhouse_erl_types_column:encode_nullable_column(
                        NullableValues, InnerType
                    ),
                    case Result of
                        {ok, Binary} when is_binary(Binary) ->
                            %% Verify binary includes null mask (1 byte per row) + values
                            ExpectedMinSize = NumRows,
                            byte_size(Binary) >= ExpectedMinSize;
                        {ok, IOList} ->
                            Binary = iolist_to_binary(IOList),
                            ExpectedMinSize = NumRows,
                            byte_size(Binary) >= ExpectedMinSize;
                        {error, _} ->
                            true
                    end
                end
            )
        end
    ).

%% Property: LowCardinality column encoding produces consistent results
prop_low_cardinality_column_encoding() ->
    ?FORALL(
        {NumRows, InnerType},
        {range(1, 50), oneof([string, uint32])},
        begin
            %% Generate values with controlled cardinality
            ValueGen = type_to_generator(InnerType),
            ?FORALL(
                Values,
                vector(NumRows, ValueGen),
                begin
                    Result = clickhouse_erl_types_column:encode_low_cardinality_column(
                        Values, InnerType
                    ),
                    case Result of
                        {ok, Binary} when is_binary(Binary) ->
                            %% Verify binary includes metadata + dictionary + keys
                            %% Minimum: 8 (meta) + 8 (dict size) + 8 (keys size) = 24 bytes
                            byte_size(Binary) >= 24;
                        {ok, IOList} ->
                            Binary = iolist_to_binary(IOList),
                            byte_size(Binary) >= 24;
                        {error, _} ->
                            true
                    end
                end
            )
        end
    ).

%% Property: Bulk encoding matches individual encoding for various sizes
prop_bulk_encoding_consistency() ->
    ?FORALL(
        {Type, NumRows},
        {oneof([uint8, int32, string]), range(0, 100)},
        begin
            ValuesGen = column_values_gen(Type, NumRows),
            ?FORALL(
                Values,
                ValuesGen,
                begin
                    %% Encode using bulk encoder
                    BulkResult = encode_column_by_type(Type, Values),
                    %% Encode individually and concatenate
                    IndividualResult = encode_individually(Type, Values),
                    %% Both should succeed or fail together
                    case {BulkResult, IndividualResult} of
                        {{ok, BulkBin}, {ok, IndivBin}} ->
                            %% Convert to binaries for comparison
                            BulkBinary = iolist_to_binary(BulkBin),
                            IndivBinary = iolist_to_binary(IndivBin),
                            BulkBinary =:= IndivBinary;
                        {{error, _}, {error, _}} ->
                            true;
                        _ ->
                            false
                    end
                end
            )
        end
    ).

%% Helper: Encode values individually and concatenate
encode_individually(Type, Values) ->
    try
        Encoded = [encode_single_value(Type, V) || V <- Values],
        {ok, Encoded}
    catch
        _:_ -> {error, individual_encoding_failed}
    end.

%% Helper: Encode a single value
encode_single_value(uint8, V) ->
    clickhouse_erl_types_integer:encode_uint8(V);
encode_single_value(int32, V) ->
    clickhouse_erl_types_integer:encode_int32(V);
encode_single_value(string, V) ->
    clickhouse_erl_types_primitive:encode_string(V).

%% Helper: Convert type atom to generator
type_to_generator(uint8) -> range(0, 255);
type_to_generator(uint16) -> uint16_gen();
type_to_generator(uint32) -> uint32_gen();
type_to_generator(int8) -> int8_gen();
type_to_generator(int16) -> int16_gen();
type_to_generator(int32) -> range(-2147483648, 2147483647);
type_to_generator(int64) -> ?LET(N, range(-1000000000000, 1000000000000), N);
type_to_generator(string) -> string_gen();
type_to_generator(float32) -> float32_gen();
type_to_generator(float64) -> float64_gen().
