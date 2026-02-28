-module(clickhouse_erl_types_map_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Type Parsing Tests
%%%===================================================================

parse_simple_map_type_test() ->
    ?assertEqual(
        {string, uint64},
        clickhouse_erl_types_map:parse_map_type(<<"Map(String, UInt64)">>)
    ),
    ?assertEqual(
        {string, int64},
        clickhouse_erl_types_map:parse_map_type(<<"Map(String, Int64)">>)
    ).

parse_map_with_complex_value_type_test() ->
    ?assertEqual(
        {string, {array, int64}},
        clickhouse_erl_types_map:parse_map_type(<<"Map(String, Array(Int64))">>)
    ),
    ?assertEqual(
        {int32, {tuple, [string, uint64]}},
        clickhouse_erl_types_map:parse_map_type(<<"Map(Int32, Tuple(String, UInt64))">>)
    ).

parse_map_invalid_key_type_test() ->
    %% Arrays as keys should fail
    ?assertError(
        {invalid_key_type, array},
        clickhouse_erl_types_map:parse_map_type(<<"Map(Array(String), Int64)">>)
    ),
    %% Maps as keys should fail
    ?assertError(
        {invalid_key_type, map},
        clickhouse_erl_types_map:parse_map_type(<<"Map(Map(String, Int64), String)">>)
    ).

%%%===================================================================
%%% Encoding Tests
%%%===================================================================

encode_empty_maps_test() ->
    %% Empty list of maps
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column([], string, int64),
    ?assert(is_binary(Encoded)).

encode_single_entry_maps_test() ->
    %% Maps with single entries
    Maps = [#{<<"a">> => 1}, #{<<"b">> => 2}, #{<<"c">> => 3}],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(Maps, string, int64),
    ?assert(is_binary(Encoded)),
    %% Should have 3 offsets (3*8=24 bytes) + 3 strings + 3 int64 values (3*8=24 bytes)
    ?assert(byte_size(Encoded) > 48).

encode_multi_entry_maps_test() ->
    %% Maps with multiple entries
    Maps = [
        #{<<"a">> => 1, <<"b">> => 2, <<"c">> => 3},
        #{<<"d">> => 4, <<"e">> => 5},
        #{<<"f">> => 6}
    ],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(Maps, string, int64),
    ?assert(is_binary(Encoded)).

encode_maps_with_complex_values_test() ->
    %% Maps with array values
    Maps = [
        #{<<"key1">> => [1, 2, 3]},
        #{<<"key2">> => [4, 5]},
        #{<<"key3">> => []}
    ],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(Maps, string, {array, int64}),
    ?assert(is_binary(Encoded)).

encode_empty_map_entries_test() ->
    %% Some maps are empty
    Maps = [#{<<"a">> => 1}, #{}, #{<<"b">> => 2}],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(Maps, string, int64),
    ?assert(is_binary(Encoded)).

%%%===================================================================
%%% Decoding Tests
%%%===================================================================

decode_empty_maps_test() ->
    %% Encode then decode empty maps
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column([], string, int64),
    {ok, Decoded, _Rest} = clickhouse_erl_types_map:decode_map_column(
        Encoded, string, int64, 0
    ),
    ?assertEqual([], Decoded).

decode_single_entry_maps_test() ->
    %% Encode then decode single-entry maps
    Maps = [#{<<"a">> => 1}, #{<<"b">> => 2}, #{<<"c">> => 3}],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(Maps, string, int64),
    {ok, Decoded, _Rest} = clickhouse_erl_types_map:decode_map_column(
        Encoded, string, int64, 3
    ),
    ?assertEqual(Maps, Decoded).

decode_multi_entry_maps_test() ->
    %% Encode then decode multi-entry maps
    Maps = [
        #{<<"a">> => 1, <<"b">> => 2, <<"c">> => 3},
        #{<<"d">> => 4, <<"e">> => 5},
        #{<<"f">> => 6}
    ],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(Maps, string, int64),
    {ok, Decoded, _Rest} = clickhouse_erl_types_map:decode_map_column(
        Encoded, string, int64, 3
    ),
    ?assertEqual(Maps, Decoded).

decode_maps_with_complex_values_test() ->
    %% Encode then decode maps with array values
    Maps = [
        #{<<"key1">> => [1, 2, 3]},
        #{<<"key2">> => [4, 5]},
        #{<<"key3">> => []}
    ],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(Maps, string, {array, int64}),
    {ok, Decoded, _Rest} = clickhouse_erl_types_map:decode_map_column(
        Encoded, string, {array, int64}, 3
    ),
    ?assertEqual(Maps, Decoded).

decode_empty_map_entries_test() ->
    %% Encode then decode with some empty maps
    Maps = [#{<<"a">> => 1}, #{}, #{<<"b">> => 2}],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(Maps, string, int64),
    {ok, Decoded, _Rest} = clickhouse_erl_types_map:decode_map_column(
        Encoded, string, int64, 3
    ),
    ?assertEqual(Maps, Decoded).

%%%===================================================================
%%% Round Trip Tests
%%%===================================================================

roundtrip_string_uint64_maps_test() ->
    Maps = [
        #{<<"a">> => 100, <<"b">> => 200},
        #{<<"c">> => 300},
        #{},
        #{<<"d">> => 400, <<"e">> => 500, <<"f">> => 600}
    ],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(Maps, string, uint64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_map:decode_map_column(
        Encoded, string, uint64, 4
    ),
    ?assertEqual(Maps, Decoded).

roundtrip_int32_float64_maps_test() ->
    Maps = [#{1 => 1.5, 2 => 2.5}, #{3 => 3.5}, #{}],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(Maps, int32, float64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_map:decode_map_column(
        Encoded, int32, float64, 3
    ),
    ?assertEqual(Maps, Decoded).

roundtrip_maps_with_tuple_values_test() ->
    Maps = [
        #{<<"key1">> => {<<"val1">>, 100}},
        #{<<"key2">> => {<<"val2">>, 200}, <<"key3">> => {<<"val3">>, 300}}
    ],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(
        Maps, string, {tuple, [string, int64]}
    ),
    {ok, Decoded, <<>>} = clickhouse_erl_types_map:decode_map_column(
        Encoded, string, {tuple, [string, int64]}, 2
    ),
    ?assertEqual(Maps, Decoded).

%%%===================================================================
%%% Edge Cases
%%%===================================================================

encode_all_empty_maps_test() ->
    %% All maps are empty
    Maps = [#{}, #{}, #{}],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(Maps, string, int64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_map:decode_map_column(
        Encoded, string, int64, 3
    ),
    ?assertEqual(Maps, Decoded).

encode_single_large_map_test() ->
    %% Single map with many entries
    LargeMap = maps:from_list([{integer_to_binary(I), I} || I <- lists:seq(1, 100)]),
    Maps = [LargeMap],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(Maps, string, int64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_map:decode_map_column(
        Encoded, string, int64, 1
    ),
    ?assertEqual(Maps, Decoded).

roundtrip_maps_with_nested_arrays_test() ->
    %% Maps with nested array values
    Maps = [
        #{<<"a">> => [[1, 2], [3]]},
        #{<<"b">> => [[4, 5, 6]], <<"c">> => [[]]}
    ],
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(
        Maps, string, {array, {array, int64}}
    ),
    {ok, Decoded, <<>>} = clickhouse_erl_types_map:decode_map_column(
        Encoded, string, {array, {array, int64}}, 2
    ),
    ?assertEqual(Maps, Decoded).
