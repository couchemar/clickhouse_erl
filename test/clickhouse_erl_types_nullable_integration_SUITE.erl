-module(clickhouse_erl_types_nullable_integration_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([
    simple_nullable_roundtrip/1,
    nullable_string_roundtrip/1,
    all_null_values/1,
    all_non_null_values/1,
    multiple_nullable_columns/1
]).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [
        simple_nullable_roundtrip,
        nullable_string_roundtrip,
        all_null_values,
        all_non_null_values,
        multiple_nullable_columns
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Test simple nullable round trip with ClickHouse
simple_nullable_roundtrip(Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_nullable_simple">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_nullable_simple (\n"
            "            id UInt32,\n"
            "            value Nullable(Int64)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4]},
        #{
            name => <<"value">>,
            type => <<"Nullable(Int64)">>,
            data => [{value, 10}, {null}, {value, 30}, {null}]
        }
    ],
    InsertSQL = <<"INSERT INTO test_nullable_simple VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_nullable_simple ORDER BY id">>
    ),

    #{data := #{rows := [[1, 10], [2, null], [3, 30], [4, null]]}} = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_nullable_simple">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test nullable strings
nullable_string_roundtrip(Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_nullable_string">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_nullable_string (\n"
            "            id UInt32,\n"
            "            name Nullable(String)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"name">>,
            type => <<"Nullable(String)">>,
            data => [{value, <<"Alice">>}, {null}, {value, <<"Bob">>}]
        }
    ],
    InsertSQL = <<"INSERT INTO test_nullable_string VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, name FROM test_nullable_string ORDER BY id">>
    ),

    #{data := #{rows := [[1, <<"Alice">>], [2, null], [3, <<"Bob">>]]}} = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_nullable_string">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test all null values
all_null_values(Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_nullable_all_null">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_nullable_all_null (\n"
            "            id UInt32,\n"
            "            value Nullable(Int64)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"value">>,
            type => <<"Nullable(Int64)">>,
            data => [{null}, {null}, {null}]
        }
    ],
    InsertSQL = <<"INSERT INTO test_nullable_all_null VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_nullable_all_null ORDER BY id">>
    ),

    #{data := #{rows := [[1, null], [2, null], [3, null]]}} = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_nullable_all_null">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test all non-null values
all_non_null_values(Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_nullable_all_non_null">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_nullable_all_non_null (\n"
            "            id UInt32,\n"
            "            value Nullable(Int64)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"value">>,
            type => <<"Nullable(Int64)">>,
            data => [{value, 10}, {value, 20}, {value, 30}]
        }
    ],
    InsertSQL = <<"INSERT INTO test_nullable_all_non_null VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_nullable_all_non_null ORDER BY id">>
    ),

    #{data := #{rows := [[1, 10], [2, 20], [3, 30]]}} = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_nullable_all_non_null">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test multiple nullable columns
multiple_nullable_columns(Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_nullable_multiple">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_nullable_multiple (\n"
            "            id UInt32,\n"
            "            value1 Nullable(Int64),\n"
            "            value2 Nullable(String),\n"
            "            value3 Nullable(Float64)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"value1">>,
            type => <<"Nullable(Int64)">>,
            data => [{value, 100}, {null}]
        },
        #{
            name => <<"value2">>,
            type => <<"Nullable(String)">>,
            data => [{null}, {value, <<"test">>}]
        },
        #{
            name => <<"value3">>,
            type => <<"Nullable(Float64)">>,
            data => [{value, 1.5}, {value, 2.5}]
        }
    ],
    InsertSQL = <<"INSERT INTO test_nullable_multiple VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value1, value2, value3 FROM test_nullable_multiple ORDER BY id">>
    ),

    #{
        data := #{
            rows := [
                [1, 100, null, 1.5],
                [2, null, <<"test">>, 2.5]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_nullable_multiple">>),
    test_helpers:disconnect(Conn),
    ok.
