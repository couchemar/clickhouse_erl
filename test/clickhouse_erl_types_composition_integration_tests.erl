%% @doc Integration tests for composite type composition with ClickHouse.
%%
%% Tests deeply nested composite types against a real ClickHouse server.
-module(clickhouse_erl_types_composition_integration_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Integration Tests
%%%===================================================================

%% @doc Test Array(Nullable(String)) round trip
array_nullable_string_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table
    {ok, _} = clickhouse_erl:query(
        Conn, <<"DROP TABLE IF EXISTS test_array_nullable_string">>
    ),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_array_nullable_string (\n"
            "            id UInt32,\n"
            "            data Array(Nullable(String))\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    % Insert data
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"data">>,
            type => <<"Array(Nullable(String))">>,
            data => [
                [{value, <<"hello">>}, {null}, {value, <<"world">>}],
                [{value, <<"foo">>}]
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_array_nullable_string VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_array_nullable_string ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{
            data := #{
                rows := [
                    [1, [{value, <<"hello">>}, {null}, {value, <<"world">>}]],
                    [2, [{value, <<"foo">>}]]
                ]
            }
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_array_nullable_string">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test Tuple(Array(String), Map(String, Int64)) round trip
tuple_array_map_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_tuple_array_map">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_tuple_array_map (\n"
            "            id UInt32,\n"
            "            data Tuple(Array(String), Map(String, Int64))\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    % Insert data
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"data">>,
            type => <<"Tuple(Array(String), Map(String, Int64))">>,
            data => [
                {[<<"a">>, <<"b">>], #{<<"x">> => 1, <<"y">> => 2}},
                {[], #{}}
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_tuple_array_map VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_tuple_array_map ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{
            data := #{
                rows := [
                    [1, {[<<"a">>, <<"b">>], #{<<"x">> := 1, <<"y">> := 2}}],
                    [2, {[], #{}}]
                ]
            }
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_tuple_array_map">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test Array(Tuple(String, Int64)) round trip
array_tuple_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_array_tuple">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_array_tuple (\n"
            "            id UInt32,\n"
            "            data Array(Tuple(String, Int64))\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    % Insert data
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"data">>,
            type => <<"Array(Tuple(String, Int64))">>,
            data => [
                [{<<"alice">>, 25}, {<<"bob">>, 30}],
                [{<<"charlie">>, 35}]
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_array_tuple VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_array_tuple ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{
            data := #{
                rows := [
                    [1, [{<<"alice">>, 25}, {<<"bob">>, 30}]],
                    [2, [{<<"charlie">>, 35}]]
                ]
            }
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_array_tuple">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test Map(String, Array(Int64)) round trip
map_string_array_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_map_string_array">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_map_string_array (\n"
            "            id UInt32,\n"
            "            data Map(String, Array(Int64))\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    % Insert data
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"data">>,
            type => <<"Map(String, Array(Int64))">>,
            data => [
                #{<<"key1">> => [1, 2, 3], <<"key2">> => [4, 5]},
                #{<<"key3">> => []}
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_map_string_array VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_map_string_array ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{
            data := #{
                rows := [
                    [1, #{<<"key1">> := [1, 2, 3], <<"key2">> := [4, 5]}],
                    [2, #{<<"key3">> := []}]
                ]
            }
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_map_string_array">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test deeply nested structure (4 levels)
%% Array(Array(Array(Nullable(Int64))))
deeply_nested_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table with 4-level nesting
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_deeply_nested">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_deeply_nested (\n"
            "            id UInt32,\n"
            "            data Array(Array(Array(Nullable(Int64))))\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    % Insert data with 4 levels of nesting
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"data">>,
            type => <<"Array(Array(Array(Nullable(Int64))))">>,
            data => [
                % Row 1: Array of arrays of arrays of nullable int64
                [
                    [[{value, 1}, {null}, {value, 2}]],
                    [[{value, 3}]]
                ],
                % Row 2: Simpler structure
                [
                    [[{value, 4}, {value, 5}, {value, 6}]]
                ]
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_deeply_nested VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_deeply_nested ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{
            data := #{
                rows := [
                    [
                        1,
                        [
                            [[{value, 1}, {null}, {value, 2}]],
                            [[{value, 3}]]
                        ]
                    ],
                    [2, [[[{value, 4}, {value, 5}, {value, 6}]]]]
                ]
            }
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_deeply_nested">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().
