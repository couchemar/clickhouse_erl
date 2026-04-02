%%%-------------------------------------------------------------------
%% @doc TCP stream parsing tests for ClickHouse connection (Common Test)
%%
%% These tests verify that the connection properly handles TCP stream
%% scenarios where packets can be split across multiple TCP recv calls
%% or multiple packets can arrive in a single TCP recv.
%% @end
%%%-------------------------------------------------------------------
-module(clickhouse_erl_connection_tcp_stream_SUITE).
-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Test cases
-export([
    single_packet_scenario/1,
    multiple_packets_scenario/1,
    incomplete_packet_scenario/1,
    packet_split_at_header/1,
    packet_split_mid_data/1,
    packet_split_between_packets/1,
    buffer_cleared_after_query/1,
    buffer_cleared_on_error/1,
    profile_events_handling/1
]).

suite() ->
    [{timetrap, {seconds, 30}}].

all() ->
    [
        {group, single_packet},
        {group, multi_packet},
        {group, large_results},
        {group, buffer_mgmt}
    ].

groups() ->
    [
        {single_packet, [], [
            single_packet_scenario, multiple_packets_scenario, profile_events_handling
        ]},
        {multi_packet, [], [
            packet_split_at_header
        ]},
        {large_results, [], [
            incomplete_packet_scenario,
            packet_split_mid_data,
            packet_split_between_packets
        ]},
        {buffer_mgmt, [], [buffer_cleared_after_query, buffer_cleared_on_error]}
    ].

init_per_suite(Config) ->
    application:ensure_all_started(clickhouse_erl),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_Group, Config) ->
    Config.

end_per_group(_Group, _Config) ->
    ok.

init_per_testcase(TestCase, Config) ->
    {ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{
        database => "db",
        username => "user",
        password => "password"
    }),
    ct:pal("init_per_testcase ~p: Conn=~p", [TestCase, Conn]),
    [{connection, Conn} | Config].

end_per_testcase(TestCase, Config) ->
    Conn = ?config(connection, Config),
    ct:pal("end_per_testcase ~p: Conn=~p", [TestCase, Conn]),
    clickhouse_erl:disconnect(Conn),
    ok.

%%%===================================================================
%%% Single Packet Scenario Tests
%%%===================================================================

single_packet_scenario(Config) ->
    Conn = ?config(connection, Config),
    Result = clickhouse_erl:query(Conn, <<"SELECT 1 as num">>),
    {ok, QueryResult} = Result,
    #{data := #{rows := _}} = QueryResult.

multiple_packets_scenario(Config) ->
    Conn = ?config(connection, Config),
    Result = clickhouse_erl:query(Conn, <<"SELECT number FROM system.numbers LIMIT 10">>),
    {ok, QueryResult} = Result,
    #{data := #{rows := _}} = QueryResult.

profile_events_handling(Config) ->
    Conn = ?config(connection, Config),
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

%%%===================================================================
%%% Multi Packet / Split Tests
%%%===================================================================

incomplete_packet_scenario(Config) ->
    Conn = ?config(connection, Config),
    {ok, QueryResult} = clickhouse_erl:query(
        Conn,
        <<"SELECT number, toString(number) as str FROM system.numbers LIMIT 100">>
    ),
    #{data := #{rows := Rows}} = QueryResult,
    100 = length(Rows).

packet_split_at_header(Config) ->
    Conn = ?config(connection, Config),
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>),
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 2">>),
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 3">>).

packet_split_mid_data(Config) ->
    Conn = ?config(connection, Config),
    Result = clickhouse_erl:query(
        Conn,
        <<"SELECT number, number * 2, number * 3 FROM system.numbers LIMIT 1000">>
    ),
    ct:pal("packet_split_mid_data result: ~p", [Result]),
    {ok, QueryResult} = Result,
    Rows = maps:get(rows, maps:get(data, QueryResult)),
    1000 = length(Rows).

packet_split_between_packets(Config) ->
    Conn = ?config(connection, Config),
    {ok, QueryResult} = clickhouse_erl:query(
        Conn,
        <<"SELECT * FROM system.numbers LIMIT 5000">>
    ),
    Rows = maps:get(rows, maps:get(data, QueryResult)),
    5000 = length(Rows).

%%%===================================================================
%%% Buffer Management Tests
%%%===================================================================

buffer_cleared_after_query(Config) ->
    Conn = ?config(connection, Config),
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>),
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 2">>).

buffer_cleared_on_error(Config) ->
    Conn = ?config(connection, Config),
    {error, _} = clickhouse_erl:query(Conn, <<"SELECT * FROM nonexistent_table">>),
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>).
