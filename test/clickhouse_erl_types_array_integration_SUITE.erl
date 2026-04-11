-module(clickhouse_erl_types_array_integration_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([
    simple_array_roundtrip/1,
    array_string_roundtrip/1,
    nested_array_roundtrip/1,
    array_of_tuples_roundtrip/1,
    empty_array_roundtrip/1
]).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [
        simple_array_roundtrip,
        array_string_roundtrip,
        nested_array_roundtrip,
        array_of_tuples_roundtrip,
        empty_array_roundtrip
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Test simple array round trip with ClickHouse
simple_array_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_array_simple">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_array_simple (\n"
            "            id UInt32,\n"
            "            numbers Array(Int64)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"numbers">>,
            type => <<"Array(Int64)">>,
            data => [[1, 2, 3], [4, 5], [6]]
        }
    ],
    InsertSQL = <<"INSERT INTO test_array_simple VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, numbers FROM test_array_simple ORDER BY id">>
    ),

    #{data := #{rows := [[1, [1, 2, 3]], [2, [4, 5]], [3, [6]]]}} = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_array_simple">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test array of strings
array_string_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_array_string">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_array_string (\n"
            "            id UInt32,\n"
            "            tags Array(String)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"tags">>,
            type => <<"Array(String)">>,
            data => [
                [<<"tag1">>, <<"tag2">>],
                [<<"tag3">>],
                []
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_array_string VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, tags FROM test_array_string ORDER BY id">>
    ),

    #{data := #{rows := [[1, [<<"tag1">>, <<"tag2">>]], [2, [<<"tag3">>]], [3, []]]}} = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_array_string">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test nested arrays
nested_array_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_array_nested">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_array_nested (\n"
            "            id UInt32,\n"
            "            matrix Array(Array(Int64))\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"matrix">>,
            type => <<"Array(Array(Int64))">>,
            data => [
                [[1, 2], [3, 4]],
                [[5, 6, 7]]
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_array_nested VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, matrix FROM test_array_nested ORDER BY id">>
    ),

    #{data := #{rows := [[1, [[1, 2], [3, 4]]], [2, [[5, 6, 7]]]]}} = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_array_nested">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test array of tuples
array_of_tuples_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_array_of_tuples">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_array_of_tuples (\n"
            "            id UInt32,\n"
            "            points Array(Tuple(UInt8, UInt8))\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"points">>,
            type => <<"Array(Tuple(UInt8, UInt8))">>,
            data => [
                [{10, 20}, {30, 40}],
                [{50, 60}]
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_array_of_tuples VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, points FROM test_array_of_tuples ORDER BY id">>
    ),

    #{data := #{rows := [[1, [{10, 20}, {30, 40}]], [2, [{50, 60}]]]}} = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_array_of_tuples">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test empty arrays
empty_array_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_array_empty">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_array_empty (\n"
            "            id UInt32,\n"
            "            data Array(Int64)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"data">>,
            type => <<"Array(Int64)">>,
            data => [[], [], []]
        }
    ],
    InsertSQL = <<"INSERT INTO test_array_empty VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_array_empty ORDER BY id">>
    ),

    #{data := #{rows := [[1, []], [2, []], [3, []]]}} = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_array_empty">>),
    test_helpers:disconnect(Conn),
    ok.
