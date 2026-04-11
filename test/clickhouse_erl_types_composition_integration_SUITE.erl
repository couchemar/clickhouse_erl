-module(clickhouse_erl_types_composition_integration_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([
    array_nullable_string_roundtrip/1,
    tuple_array_map_roundtrip/1,
    array_tuple_roundtrip/1,
    map_string_array_roundtrip/1,
    deeply_nested_roundtrip/1
]).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [
        array_nullable_string_roundtrip,
        tuple_array_map_roundtrip,
        array_tuple_roundtrip,
        map_string_array_roundtrip,
        deeply_nested_roundtrip
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Test Array(Nullable(String)) round trip
array_nullable_string_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_array_nullable_string">>),
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

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_array_nullable_string ORDER BY id">>
    ),

    #{
        data := #{
            rows := [
                [1, [{value, <<"hello">>}, {null}, {value, <<"world">>}]],
                [2, [{value, <<"foo">>}]]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_array_nullable_string">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test Tuple(Array(String), Map(String, Int64)) round trip
tuple_array_map_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

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

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_tuple_array_map ORDER BY id">>
    ),

    #{
        data := #{
            rows := [
                [1, {[<<"a">>, <<"b">>], #{<<"x">> := 1, <<"y">> := 2}}],
                [2, {[], #{}}]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_tuple_array_map">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test Array(Tuple(String, Int64)) round trip
array_tuple_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

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

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_array_tuple ORDER BY id">>
    ),

    #{
        data := #{
            rows := [
                [1, [{<<"alice">>, 25}, {<<"bob">>, 30}]],
                [2, [{<<"charlie">>, 35}]]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_array_tuple">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test Map(String, Array(Int64)) round trip
map_string_array_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

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

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_map_string_array ORDER BY id">>
    ),

    #{
        data := #{
            rows := [
                [1, #{<<"key1">> := [1, 2, 3], <<"key2">> := [4, 5]}],
                [2, #{<<"key3">> := []}]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_map_string_array">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test deeply nested structure (4 levels)
deeply_nested_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

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

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"data">>,
            type => <<"Array(Array(Array(Nullable(Int64))))">>,
            data => [
                [
                    [[{value, 1}, {null}, {value, 2}]],
                    [[{value, 3}]]
                ],
                [
                    [[{value, 4}, {value, 5}, {value, 6}]]
                ]
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_deeply_nested VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_deeply_nested ORDER BY id">>
    ),

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
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_deeply_nested">>),
    test_helpers:disconnect(Conn),
    ok.
