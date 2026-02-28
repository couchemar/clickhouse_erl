%% @doc Integration tests for ClickHouse Tuple type support
%%
%% This module contains integration tests that verify tuple encoding/decoding
%% with a real ClickHouse server instance.
-module(clickhouse_erl_types_tuple_integration_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Integration Tests
%%%===================================================================

%% @doc Test simple tuple round trip with ClickHouse
simple_tuple_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table with tuple column
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_tuple_simple">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_tuple_simple (\n"
            "            id UInt32,\n"
            "            coords Tuple(UInt8, UInt16)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    % Insert data
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"coords">>,
            type => <<"Tuple(UInt8, UInt16)">>,
            data => [{10, 1000}, {20, 2000}, {30, 3000}]
        }
    ],
    InsertSQL = <<"INSERT INTO test_tuple_simple VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, coords FROM test_tuple_simple ORDER BY id">>
    ),

    % Verify results - the result format is rows-based
    ?assertMatch(#{data := #{rows := [[1, {10, 1000}], [2, {20, 2000}], [3, {30, 3000}]]}}, Result),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_tuple_simple">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test nested tuple round trip
nested_tuple_roundtrip_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table with nested tuple
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_tuple_nested">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_tuple_nested (\n"
            "            id UInt32,\n"
            "            data Tuple(Tuple(UInt8, UInt8), UInt16)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    % Insert data
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"data">>,
            type => <<"Tuple(Tuple(UInt8, UInt8), UInt16)">>,
            data => [{{10, 20}, 1000}, {{30, 40}, 2000}]
        }
    ],
    InsertSQL = <<"INSERT INTO test_tuple_nested VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query back
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_tuple_nested ORDER BY id">>
    ),

    % Verify results - the result format is rows-based
    ?assertMatch(#{data := #{rows := [[1, {{10, 20}, 1000}], [2, {{30, 40}, 2000}]]}}, Result),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_tuple_nested">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test empty tuple - DISABLED: ClickHouse may not support empty tuples in all versions
%% empty_tuple_test() ->
%%     setup_clickhouse(),
%%     
%%     Options = #{
%%         username => ?TEST_USERNAME,
%%         password => ?TEST_PASSWORD,
%%         database => ?TEST_DATABASE
%%     },
%%     
%%     {ok, Conn} = clickhouse_erl:connect(?CLICKHOUSE_HOST, ?CLICKHOUSE_PORT, Options),
%%     
%%     % Create table with empty tuple
%%     {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_tuple_empty">>),
%%     {ok, _} = clickhouse_erl:query(Conn, <<"
%%         CREATE TABLE test_tuple_empty (
%%             id UInt32,
%%             empty Tuple()
%%         ) ENGINE = Memory
%%     ">>),
%%     
%%     % Insert data
%%     InsertData = [
%%         #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
%%         #{name => <<"empty">>, type => <<"Tuple()">>, data => [{}, {}]}
%%     ],
%%     InsertSQL = <<"INSERT INTO test_tuple_empty VALUES">>,
%%     {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),
%%     
%%     % Query back
%%     {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, empty FROM test_tuple_empty ORDER BY id">>),
%%     
%%     % Verify results - the result format is rows-based
%%     ?assertMatch(#{rows := [[1, {}], [2, {}]]}, Result),
%%     
%%     % Cleanup
%%     {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_tuple_empty">>),
%%     clickhouse_erl:disconnect(Conn),
%%     cleanup_clickhouse().
