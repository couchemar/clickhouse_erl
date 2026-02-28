%% @doc Integration tests for ClickHouse LowCardinality type support
%%
%% This module contains integration tests that verify low cardinality encoding/decoding
%% with a real ClickHouse server instance.
-module(clickhouse_erl_types_low_cardinality_integration_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Integration Tests
%%%===================================================================

%% @doc Test simple low cardinality string round trip with ClickHouse
simple_low_cardinality_string_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table with low cardinality column
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

    % Insert data with repeated values (low cardinality)
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

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, category FROM test_low_cardinality_simple ORDER BY id">>
    ),

    % Verify results - values should be returned transparently
    ?assertMatch(
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
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_low_cardinality_simple">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test low cardinality with many unique values
high_cardinality_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table
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

    % Insert data with many unique values
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

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_low_cardinality_high ORDER BY id LIMIT 5">>
    ),

    % Verify first 5 results
    ?assertMatch(
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
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_low_cardinality_high">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test low cardinality with all identical values
all_identical_values_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table
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

    % Insert data with all identical values
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

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_low_cardinality_identical ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
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
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_low_cardinality_identical">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test low cardinality with empty strings
empty_strings_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table
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

    % Insert data with empty strings
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

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_low_cardinality_empty ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{
            data := #{
                rows := [
                    [1, <<"">>],
                    [2, <<"test">>],
                    [3, <<"">>]
                ]
            }
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_low_cardinality_empty">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test multiple low cardinality columns
multiple_low_cardinality_columns_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table with multiple low cardinality columns
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

    % Insert data
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

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, category, status FROM test_low_cardinality_multiple ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{
            data := #{
                rows := [
                    [1, <<"A">>, <<"active">>],
                    [2, <<"B">>, <<"active">>],
                    [3, <<"A">>, <<"inactive">>],
                    [4, <<"B">>, <<"active">>]
                ]
            }
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_low_cardinality_multiple">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().
