-module(clickhouse_erl_types_array_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Type Parsing Tests
%%%===================================================================

parse_simple_array_type_test() ->
    ?assertEqual(uint8, clickhouse_erl_types_array:parse_array_type(<<"Array(UInt8)">>)),
    ?assertEqual(string, clickhouse_erl_types_array:parse_array_type(<<"Array(String)">>)),
    ?assertEqual(int64, clickhouse_erl_types_array:parse_array_type(<<"Array(Int64)">>)).

parse_nested_array_type_test() ->
    ?assertEqual(
        {array, int64},
        clickhouse_erl_types_array:parse_array_type(<<"Array(Array(Int64))">>)
    ),
    ?assertEqual(
        {array, string},
        clickhouse_erl_types_array:parse_array_type(<<"Array(Array(String))">>)
    ).

parse_array_of_tuple_type_test() ->
    ?assertEqual(
        {tuple, [string, int64]},
        clickhouse_erl_types_array:parse_array_type(<<"Array(Tuple(String, Int64))">>)
    ).

%%%===================================================================
%%% Encoding Tests
%%%===================================================================

encode_empty_arrays_test() ->
    %% Empty list of arrays
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column([], int64),
    ?assert(is_binary(Encoded)).

encode_single_element_arrays_test() ->
    %% Arrays with single elements
    Arrays = [[1], [2], [3]],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, int64),
    ?assert(is_binary(Encoded)),
    %% Should have 3 offsets (3*8=24 bytes) + 3 int64 values (3*8=24 bytes) = 48 bytes
    ?assertEqual(48, byte_size(Encoded)).

encode_variable_length_arrays_test() ->
    %% Arrays of different lengths
    Arrays = [[1, 2, 3], [4, 5], [6]],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, int64),
    ?assert(is_binary(Encoded)),
    %% Should have 3 offsets (24 bytes) + 6 int64 values (48 bytes) = 72 bytes
    ?assertEqual(72, byte_size(Encoded)).

encode_string_arrays_test() ->
    %% Arrays of strings
    Arrays = [[<<"hello">>, <<"world">>], [<<"foo">>], []],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, string),
    ?assert(is_binary(Encoded)).

encode_nested_arrays_test() ->
    %% Nested arrays: Array(Array(Int64))
    Arrays = [[[1, 2], [3]], [[4, 5, 6]], []],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, {array, int64}),
    ?assert(is_binary(Encoded)).

%%%===================================================================
%%% Decoding Tests
%%%===================================================================

decode_empty_arrays_test() ->
    %% Encode then decode empty arrays
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column([], int64),
    {ok, Decoded, _Rest} = clickhouse_erl_types_array:decode_array_column(Encoded, int64, 0),
    ?assertEqual([], Decoded).

decode_single_element_arrays_test() ->
    %% Encode then decode single-element arrays
    Arrays = [[1], [2], [3]],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, int64),
    {ok, Decoded, _Rest} = clickhouse_erl_types_array:decode_array_column(Encoded, int64, 3),
    ?assertEqual(Arrays, Decoded).

decode_variable_length_arrays_test() ->
    %% Encode then decode variable-length arrays
    Arrays = [[1, 2, 3], [4, 5], [6]],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, int64),
    {ok, Decoded, _Rest} = clickhouse_erl_types_array:decode_array_column(Encoded, int64, 3),
    ?assertEqual(Arrays, Decoded).

decode_string_arrays_test() ->
    %% Encode then decode string arrays
    Arrays = [[<<"hello">>, <<"world">>], [<<"foo">>], []],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, string),
    {ok, Decoded, _Rest} = clickhouse_erl_types_array:decode_array_column(Encoded, string, 3),
    ?assertEqual(Arrays, Decoded).

decode_nested_arrays_test() ->
    %% Encode then decode nested arrays
    Arrays = [[[1, 2], [3]], [[4, 5, 6]], []],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, {array, int64}),
    {ok, Decoded, _Rest} = clickhouse_erl_types_array:decode_array_column(
        Encoded, {array, int64}, 3
    ),
    ?assertEqual(Arrays, Decoded).

decode_arrays_of_tuples_test() ->
    %% Encode then decode arrays of tuples
    Arrays = [[{<<"a">>, 1}, {<<"b">>, 2}], [{<<"c">>, 3}], []],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(
        Arrays, {tuple, [string, int64]}
    ),
    {ok, Decoded, _Rest} = clickhouse_erl_types_array:decode_array_column(
        Encoded, {tuple, [string, int64]}, 3
    ),
    ?assertEqual(Arrays, Decoded).

%%%===================================================================
%%% Round Trip Tests
%%%===================================================================

roundtrip_uint8_arrays_test() ->
    Arrays = [[1, 2, 3], [4, 5], [], [6, 7, 8, 9]],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, uint8),
    {ok, Decoded, <<>>} = clickhouse_erl_types_array:decode_array_column(Encoded, uint8, 4),
    ?assertEqual(Arrays, Decoded).

roundtrip_float64_arrays_test() ->
    Arrays = [[1.5, 2.5], [3.5], []],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, float64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_array:decode_array_column(Encoded, float64, 3),
    ?assertEqual(Arrays, Decoded).

roundtrip_deeply_nested_arrays_test() ->
    %% Array(Array(Array(Int64)))
    Arrays = [[[[1, 2], [3]], [[4]]], [[[5, 6, 7]]]],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(
        Arrays, {array, {array, int64}}
    ),
    {ok, Decoded, <<>>} = clickhouse_erl_types_array:decode_array_column(
        Encoded, {array, {array, int64}}, 2
    ),
    ?assertEqual(Arrays, Decoded).

%%%===================================================================
%%% Edge Cases
%%%===================================================================

encode_all_empty_arrays_test() ->
    %% All arrays are empty
    Arrays = [[], [], []],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, int64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_array:decode_array_column(Encoded, int64, 3),
    ?assertEqual(Arrays, Decoded).

encode_single_large_array_test() ->
    %% Single array with many elements
    LargeArray = lists:seq(1, 1000),
    Arrays = [LargeArray],
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, int64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_array:decode_array_column(Encoded, int64, 1),
    ?assertEqual(Arrays, Decoded).
