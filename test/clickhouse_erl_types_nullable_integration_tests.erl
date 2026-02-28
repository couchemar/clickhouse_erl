%% @doc Integration tests for ClickHouse Nullable type support
%%
%% This module contains integration tests that verify nullable encoding/decoding
%% with a real ClickHouse server instance.
-module(clickhouse_erl_types_nullable_integration_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Integration Tests
%%%===================================================================

%% @doc Test simple nullable round trip with ClickHouse
simple_nullable_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table with nullable column
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

    % Insert data with mixed null and non-null values
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

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_nullable_simple ORDER BY id">>
    ),

    % Verify results - the result format is rows-based
    ?assertMatch(
        #{data := #{rows := [[1, {value, 10}], [2, {null}], [3, {value, 30}], [4, {null}]]}},
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_nullable_simple">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test nullable strings
nullable_string_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table with nullable string
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

    % Insert data
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

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, name FROM test_nullable_string ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{data := #{rows := [[1, {value, <<"Alice">>}], [2, {null}], [3, {value, <<"Bob">>}]]}},
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_nullable_string">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test all null values
all_null_values_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table
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

    % Insert data with all null values
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

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_nullable_all_null ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{data := #{rows := [[1, {null}], [2, {null}], [3, {null}]]}},
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_nullable_all_null">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test all non-null values
all_non_null_values_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table
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

    % Insert data with all non-null values
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

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_nullable_all_non_null ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{data := #{rows := [[1, {value, 10}], [2, {value, 20}], [3, {value, 30}]]}},
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_nullable_all_non_null">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test multiple nullable columns
multiple_nullable_columns_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table with multiple nullable columns
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

    % Insert data
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

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value1, value2, value3 FROM test_nullable_multiple ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{
            data := #{
                rows := [
                    [1, {value, 100}, {null}, {value, 1.5}],
                    [2, {null}, {value, <<"test">>}, {value, 2.5}]
                ]
            }
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_nullable_multiple">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().
