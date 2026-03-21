-module(clickhouse_erl_types_low_cardinality_integration_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([
    simple_low_cardinality_string_roundtrip/1,
    high_cardinality/1,
    all_identical_values/1,
    empty_strings/1,
    multiple_low_cardinality_columns/1
]).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [
        simple_low_cardinality_string_roundtrip,
        high_cardinality,
        all_identical_values,
        empty_strings,
        multiple_low_cardinality_columns
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Test simple low cardinality string round trip with ClickHouse
simple_low_cardinality_string_roundtrip(Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_low_cardinality_simple">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_low_cardinality_simple (\n"
            "            id UInt32,\n"
            "            category LowCardinality(String)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4, 5, 6]},
        #{
            name => <<"category">>,
            type => <<"LowCardinality(String)">>,
            data => [<<"A">>, <<"A">>, <<"B">>, <<"B">>, <<"B">>, <<"A">>]
        }
    ],
    InsertSQL = <<"INSERT INTO test_low_cardinality_simple VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, category FROM test_low_cardinality_simple ORDER BY id">>
    ),

    #{
        data := #{
            rows := [
                [1, <<"A">>],
                [2, <<"A">>],
                [3, <<"B">>],
                [4, <<"B">>],
                [5, <<"B">>],
                [6, <<"A">>]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_low_cardinality_simple">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test low cardinality with many unique values
high_cardinality(Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_low_cardinality_high">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_low_cardinality_high (\n"
            "            id UInt32,\n"
            "            value LowCardinality(String)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    Values = [list_to_binary("value" ++ integer_to_list(I)) || I <- lists:seq(1, 100)],
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => lists:seq(1, 100)},
        #{
            name => <<"value">>,
            type => <<"LowCardinality(String)">>,
            data => Values
        }
    ],
    InsertSQL = <<"INSERT INTO test_low_cardinality_high VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_low_cardinality_high ORDER BY id LIMIT 5">>
    ),

    #{
        data := #{
            rows := [
                [1, <<"value1">>],
                [2, <<"value2">>],
                [3, <<"value3">>],
                [4, <<"value4">>],
                [5, <<"value5">>]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_low_cardinality_high">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test low cardinality with all identical values
all_identical_values(Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_low_cardinality_identical">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_low_cardinality_identical (\n"
            "            id UInt32,\n"
            "            value LowCardinality(String)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4, 5]},
        #{
            name => <<"value">>,
            type => <<"LowCardinality(String)">>,
            data => [<<"same">>, <<"same">>, <<"same">>, <<"same">>, <<"same">>]
        }
    ],
    InsertSQL = <<"INSERT INTO test_low_cardinality_identical VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_low_cardinality_identical ORDER BY id">>
    ),

    #{
        data := #{
            rows := [
                [1, <<"same">>],
                [2, <<"same">>],
                [3, <<"same">>],
                [4, <<"same">>],
                [5, <<"same">>]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_low_cardinality_identical">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test low cardinality with empty strings
empty_strings(Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_low_cardinality_empty">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_low_cardinality_empty (\n"
            "            id UInt32,\n"
            "            value LowCardinality(String)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"value">>,
            type => <<"LowCardinality(String)">>,
            data => [<<"">>, <<"test">>, <<"">>]
        }
    ],
    InsertSQL = <<"INSERT INTO test_low_cardinality_empty VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_low_cardinality_empty ORDER BY id">>
    ),

    #{
        data := #{
            rows := [
                [1, <<"">>],
                [2, <<"test">>],
                [3, <<"">>]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_low_cardinality_empty">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test multiple low cardinality columns
multiple_low_cardinality_columns(Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_low_cardinality_multiple">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_low_cardinality_multiple (\n"
            "            id UInt32,\n"
            "            category LowCardinality(String),\n"
            "            status LowCardinality(String)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4]},
        #{
            name => <<"category">>,
            type => <<"LowCardinality(String)">>,
            data => [<<"A">>, <<"B">>, <<"A">>, <<"B">>]
        },
        #{
            name => <<"status">>,
            type => <<"LowCardinality(String)">>,
            data => [<<"active">>, <<"active">>, <<"inactive">>, <<"active">>]
        }
    ],
    InsertSQL = <<"INSERT INTO test_low_cardinality_multiple VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, category, status FROM test_low_cardinality_multiple ORDER BY id">>
    ),

    #{
        data := #{
            rows := [
                [1, <<"A">>, <<"active">>],
                [2, <<"B">>, <<"active">>],
                [3, <<"A">>, <<"inactive">>],
                [4, <<"B">>, <<"active">>]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_low_cardinality_multiple">>),
    test_helpers:disconnect(Conn),
    ok.
