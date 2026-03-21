-module(clickhouse_erl_types_tuple_integration_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([simple_tuple_roundtrip/1, nested_tuple_roundtrip/1]).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [simple_tuple_roundtrip, nested_tuple_roundtrip].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Test simple tuple round trip with ClickHouse
simple_tuple_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

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

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, coords FROM test_tuple_simple ORDER BY id">>
    ),

    #{data := #{rows := [[1, {10, 1000}], [2, {20, 2000}], [3, {30, 3000}]]}} = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_tuple_simple">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test nested tuple round trip
nested_tuple_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

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

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_tuple_nested ORDER BY id">>
    ),

    #{data := #{rows := [[1, {{10, 20}, 1000}], [2, {{30, 40}, 2000}]]}} = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_tuple_nested">>),
    test_helpers:disconnect(Conn),
    ok.
