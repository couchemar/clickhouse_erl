%% @doc Integration tests for ClickHouse Map type support
%%
%% This module contains integration tests that verify map encoding/decoding
%% with a real ClickHouse server instance.
-module(clickhouse_erl_types_map_integration_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Integration Tests
%%%===================================================================

%% @doc Test simple map round trip with ClickHouse
map_string_int64_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table with map column
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_map_simple">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<"CREATE TABLE test_map_simple (id UInt32, data Map(String, Int64)) ENGINE = Memory">>
    ),

    % Insert data
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"data">>,
            type => <<"Map(String, Int64)">>,
            data => [
                #{<<"key1">> => 100, <<"key2">> => 200},
                #{<<"key3">> => 300},
                #{<<"key4">> => 400, <<"key5">> => 500, <<"key6">> => 600}
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_map_simple VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_map_simple ORDER BY id">>
    ),

    % Verify results - the result format is rows-based
    ?assertMatch(
        #{
            data := #{
                rows := [
                    [1, #{<<"key1">> := 100, <<"key2">> := 200}],
                    [2, #{<<"key3">> := 300}],
                    [3, #{<<"key4">> := 400, <<"key5">> := 500, <<"key6">> := 600}]
                ]
            }
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_map_simple">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test map with array values
map_with_array_values_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table with map of arrays
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_map_array_values">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<"CREATE TABLE test_map_array_values (id UInt32, data Map(String, Array(Int64))) ENGINE = Memory">>
    ),

    % Insert data
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"data">>,
            type => <<"Map(String, Array(Int64))">>,
            data => [
                #{<<"key1">> => [1, 2, 3], <<"key2">> => [4, 5]},
                #{<<"key3">> => [], <<"key4">> => [6, 7, 8, 9]}
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_map_array_values VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_map_array_values ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{
            data := #{
                rows := [
                    [1, #{<<"key1">> := [1, 2, 3], <<"key2">> := [4, 5]}],
                    [2, #{<<"key3">> := [], <<"key4">> := [6, 7, 8, 9]}]
                ]
            }
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_map_array_values">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test empty maps
map_with_empty_maps_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_map_empty">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<"CREATE TABLE test_map_empty (id UInt32, data Map(String, UInt32)) ENGINE = Memory">>
    ),

    % Insert data with empty maps
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"data">>,
            type => <<"Map(String, UInt32)">>,
            data => [
                #{<<"key1">> => 100},
                #{},
                #{<<"key2">> => 200}
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_map_empty VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_map_empty ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(
        #{
            data := #{
                rows := [
                    [1, #{<<"key1">> := 100}],
                    [2, #{}],
                    [3, #{<<"key2">> := 200}]
                ]
            }
        },
        Result
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_map_empty">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().
