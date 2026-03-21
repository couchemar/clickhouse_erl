-module(clickhouse_erl_types_map_integration_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([
    map_string_int64_roundtrip/1, map_with_array_values_roundtrip/1, map_with_empty_maps_roundtrip/1
]).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [map_string_int64_roundtrip, map_with_array_values_roundtrip, map_with_empty_maps_roundtrip].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Test simple map round trip with ClickHouse
map_string_int64_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_map_simple">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<"CREATE TABLE test_map_simple (id UInt32, data Map(String, Int64)) ENGINE = Memory">>
    ),

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

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_map_simple ORDER BY id">>
    ),

    #{
        data := #{
            rows := [
                [1, #{<<"key1">> := 100, <<"key2">> := 200}],
                [2, #{<<"key3">> := 300}],
                [3, #{<<"key4">> := 400, <<"key5">> := 500, <<"key6">> := 600}]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_map_simple">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test map with array values
map_with_array_values_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_map_array_values">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<"CREATE TABLE test_map_array_values (id UInt32, data Map(String, Array(Int64))) ENGINE = Memory">>
    ),

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

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_map_array_values ORDER BY id">>
    ),

    #{
        data := #{
            rows := [
                [1, #{<<"key1">> := [1, 2, 3], <<"key2">> := [4, 5]}],
                [2, #{<<"key3">> := [], <<"key4">> := [6, 7, 8, 9]}]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_map_array_values">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test empty maps
map_with_empty_maps_roundtrip(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_map_empty">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<"CREATE TABLE test_map_empty (id UInt32, data Map(String, UInt32)) ENGINE = Memory">>
    ),

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

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, data FROM test_map_empty ORDER BY id">>
    ),

    #{
        data := #{
            rows := [
                [1, #{<<"key1">> := 100}],
                [2, #{}],
                [3, #{<<"key2">> := 200}]
            ]
        }
    } = Result,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_map_empty">>),
    test_helpers:disconnect(Conn),
    ok.
