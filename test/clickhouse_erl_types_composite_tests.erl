-module(clickhouse_erl_types_composite_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Offset Tests
%%%===================================================================

encode_decode_offsets_test() ->
    Offsets = [0, 10, 25, 100, 1000],
    Encoded = clickhouse_erl_types_composite:encode_offsets(Offsets),
    ExpectedSize = 5 * 8,
    ?assertEqual(ExpectedSize, byte_size(Encoded)),
    {ok, Decoded, Rest} = clickhouse_erl_types_composite:decode_offsets(Encoded, 5),
    ?assertEqual(Offsets, Decoded),
    ?assertEqual(<<>>, Rest).

decode_offsets_truncated_test() ->
    Binary = <<1:64/little-unsigned-integer>>,
    %% Try to decode 2 offsets (needs 16 bytes), but only have 8
    Result = clickhouse_erl_types_composite:decode_offsets(Binary, 2),
    ?assertMatch({error, {truncated_data, _}}, Result).

%%%===================================================================
%%% Type Parameter Parsing Tests
%%%===================================================================

parse_params_simple_test() ->
    Input = "String, Int64",
    Expected = [<<"String">>, <<"Int64">>],
    ?assertEqual(Expected, clickhouse_erl_types_composite:parse_type_params(Input)).

parse_params_nested_test() ->
    Input = "Array(String), Map(String, Int64)",
    Expected = [<<"Array(String)">>, <<"Map(String, Int64)">>],
    ?assertEqual(Expected, clickhouse_erl_types_composite:parse_type_params(Input)).

parse_params_deeply_nested_test() ->
    Input = "Tuple(A, Tuple(B, C)), Array(D)",
    Expected = [<<"Tuple(A, Tuple(B, C))">>, <<"Array(D)">>],
    ?assertEqual(Expected, clickhouse_erl_types_composite:parse_type_params(Input)).

parse_params_whitespace_test() ->
    Input = "  String  ,  Int64  ",
    Expected = [<<"String">>, <<"Int64">>],
    ?assertEqual(Expected, clickhouse_erl_types_composite:parse_type_params(Input)).

%%%===================================================================
%%% Column Type Parsing Tests
%%%===================================================================

parse_primitive_test() ->
    ?assertEqual(uint8, clickhouse_erl_types_composite:parse_column_type("UInt8")),
    ?assertEqual(string, clickhouse_erl_types_composite:parse_column_type("String")),
    ?assertEqual(datetime64, clickhouse_erl_types_composite:parse_column_type("DateTime64(3)")).

parse_array_test() ->
    ?assertEqual(
        {array, uint8},
        clickhouse_erl_types_composite:parse_column_type("Array(UInt8)")
    ),
    ?assertEqual(
        {array, {array, string}},
        clickhouse_erl_types_composite:parse_column_type("Array(Array(String))")
    ).

parse_tuple_test() ->
    ?assertEqual(
        {tuple, [uint8, string]},
        clickhouse_erl_types_composite:parse_column_type("Tuple(UInt8, String)")
    ).

parse_map_test() ->
    ?assertEqual(
        {map, string, uint32},
        clickhouse_erl_types_composite:parse_column_type("Map(String, UInt32)")
    ).

parse_nullable_test() ->
    ?assertEqual(
        {nullable, string},
        clickhouse_erl_types_composite:parse_column_type("Nullable(String)")
    ).

parse_low_cardinality_test() ->
    ?assertEqual(
        {low_cardinality, string},
        clickhouse_erl_types_composite:parse_column_type("LowCardinality(String)")
    ).

parse_complex_nested_test() ->
    Input = "Map(String, Array(Nullable(UInt64)))",
    Expected = {map, string, {array, {nullable, uint64}}},
    ?assertEqual(Expected, clickhouse_erl_types_composite:parse_column_type(Input)).
