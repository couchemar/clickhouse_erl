%% @doc Unit tests for type compatibility validation.
-module(clickhouse_erl_types_composite_validation_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Primitive Type Validation Tests
%%%===================================================================

validate_uint8_test() ->
    ?assertEqual(ok, clickhouse_erl_types_composite:validate_type_compatibility(uint8, 0)),
    ?assertEqual(ok, clickhouse_erl_types_composite:validate_type_compatibility(uint8, 255)),
    ?assertMatch(
        {error, {type_mismatch, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(uint8, 256)
    ),
    ?assertMatch(
        {error, {type_mismatch, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(uint8, -1)
    ).

validate_int64_test() ->
    ?assertEqual(ok, clickhouse_erl_types_composite:validate_type_compatibility(int64, 0)),
    ?assertEqual(ok, clickhouse_erl_types_composite:validate_type_compatibility(int64, -100)),
    ?assertEqual(ok, clickhouse_erl_types_composite:validate_type_compatibility(int64, 100)),
    ?assertMatch(
        {error, {type_mismatch, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(int64, <<"not an int">>)
    ).

validate_string_test() ->
    ?assertEqual(ok, clickhouse_erl_types_composite:validate_type_compatibility(string, <<>>)),
    ?assertEqual(
        ok, clickhouse_erl_types_composite:validate_type_compatibility(string, <<"hello">>)
    ),
    ?assertMatch(
        {error, {type_mismatch, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(string, "not a binary")
    ).

%%%===================================================================
%%% Array Type Validation Tests
%%%===================================================================

validate_array_int64_test() ->
    ?assertEqual(
        ok,
        clickhouse_erl_types_composite:validate_type_compatibility({array, int64}, [1, 2, 3])
    ),
    ?assertEqual(
        ok, clickhouse_erl_types_composite:validate_type_compatibility({array, int64}, [])
    ),
    ?assertMatch(
        {error, {array_element_error, 1, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(
            {array, int64}, [1, <<"bad">>, 3]
        )
    ).

validate_array_string_test() ->
    ?assertEqual(
        ok,
        clickhouse_erl_types_composite:validate_type_compatibility(
            {array, string}, [<<"a">>, <<"b">>]
        )
    ),
    ?assertMatch(
        {error, {array_element_error, 0, _}},
        clickhouse_erl_types_composite:validate_type_compatibility({array, string}, ["not binary"])
    ).

%%%===================================================================
%%% Tuple Type Validation Tests
%%%===================================================================

validate_tuple_test() ->
    ?assertEqual(
        ok,
        clickhouse_erl_types_composite:validate_type_compatibility(
            {tuple, [string, int64]}, {<<"hello">>, 42}
        )
    ),
    ?assertMatch(
        {error, {tuple_size_mismatch, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(
            {tuple, [string, int64]}, {<<"hello">>}
        )
    ),
    ?assertMatch(
        {error, {tuple_element_error, 1, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(
            {tuple, [string, int64]}, {<<"hello">>, <<"bad">>}
        )
    ).

%%%===================================================================
%%% Map Type Validation Tests
%%%===================================================================

validate_map_test() ->
    ?assertEqual(
        ok,
        clickhouse_erl_types_composite:validate_type_compatibility(
            {map, string, int64}, #{<<"key">> => 42}
        )
    ),
    ?assertEqual(
        ok,
        clickhouse_erl_types_composite:validate_type_compatibility({map, string, int64}, #{})
    ),
    ?assertMatch(
        {error, {map_value_error, _, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(
            {map, string, int64}, #{<<"key">> => <<"bad">>}
        )
    ).

%%%===================================================================
%%% Nullable Type Validation Tests
%%%===================================================================

validate_nullable_test() ->
    ?assertEqual(
        ok, clickhouse_erl_types_composite:validate_type_compatibility({nullable, int64}, {null})
    ),
    ?assertEqual(
        ok,
        clickhouse_erl_types_composite:validate_type_compatibility({nullable, int64}, {value, 42})
    ),
    ?assertMatch(
        {error, {type_mismatch, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(
            {nullable, int64}, {value, <<"bad">>}
        )
    ),
    ?assertMatch(
        {error, {type_mismatch, _}},
        clickhouse_erl_types_composite:validate_type_compatibility({nullable, int64}, 42)
    ).

%%%===================================================================
%%% Nested Type Validation Tests
%%%===================================================================

validate_array_nullable_string_test() ->
    ?assertEqual(
        ok,
        clickhouse_erl_types_composite:validate_type_compatibility(
            {array, {nullable, string}}, [{value, <<"a">>}, {null}, {value, <<"b">>}]
        )
    ),
    ?assertMatch(
        {error, {array_element_error, 1, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(
            {array, {nullable, string}}, [{value, <<"a">>}, <<"bad">>, {value, <<"b">>}]
        )
    ).

validate_nullable_array_int64_test() ->
    ?assertEqual(
        ok,
        clickhouse_erl_types_composite:validate_type_compatibility(
            {nullable, {array, int64}}, {value, [1, 2, 3]}
        )
    ),
    ?assertEqual(
        ok,
        clickhouse_erl_types_composite:validate_type_compatibility({nullable, {array, int64}}, {
            null
        })
    ),
    ?assertMatch(
        {error, {array_element_error, 1, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(
            {nullable, {array, int64}}, {value, [1, <<"bad">>, 3]}
        )
    ).

validate_map_string_array_test() ->
    ?assertEqual(
        ok,
        clickhouse_erl_types_composite:validate_type_compatibility(
            {map, string, {array, int64}}, #{<<"key">> => [1, 2, 3]}
        )
    ),
    ?assertMatch(
        {error, {map_value_error, _, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(
            {map, string, {array, int64}}, #{<<"key">> => [1, <<"bad">>, 3]}
        )
    ).

validate_deeply_nested_test() ->
    %% Array(Nullable(Array(Int64)))
    Type = {array, {nullable, {array, int64}}},
    ValidData = [{value, [1, 2]}, {null}, {value, [3]}],
    ?assertEqual(ok, clickhouse_erl_types_composite:validate_type_compatibility(Type, ValidData)),

    InvalidData = [{value, [1, 2]}, {null}, {value, [<<"bad">>]}],
    ?assertMatch(
        {error, {array_element_error, 2, _}},
        clickhouse_erl_types_composite:validate_type_compatibility(Type, InvalidData)
    ).
