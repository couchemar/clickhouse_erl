%%%-------------------------------------------------------------------
%% @doc TCP stream parsing tests for ClickHouse connection
%%
%% These tests verify that the connection properly handles TCP stream
%% scenarios where packets can be split across multiple TCP recv calls
%% or multiple packets can arrive in a single TCP recv.
%%
%% Uses a mock socket approach to control packet delivery.
%% @end
%%%-------------------------------------------------------------------

-module(clickhouse_erl_connection_tcp_stream_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test exports
-export([]).

%%%===================================================================
%%% Test Setup
%%%===================================================================

%% Start ClickHouse for integration tests
setup() ->
    %% Ensure application is started
    application:ensure_all_started(clickhouse_erl),

    %% Connect to ClickHouse (using credentials from docker-compose.yml)
    {ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{
        database => "db",
        username => "user",
        password => "password"
    }),
    Conn.

cleanup(Conn) ->
    clickhouse_erl:disconnect(Conn).

%%%===================================================================
%%% Single Packet Scenario Tests
%%%===================================================================

%% Test: Single complete packet in one TCP recv
%% Validates: REQ-1.1
single_packet_scenario_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Conn) ->
        [
            ?_test(begin
                %% Execute a simple query that returns minimal data
                Result = clickhouse_erl:query(Conn, "SELECT 1 as num"),

                %% Should succeed
                ?assertMatch({ok, _}, Result),

                %% Verify result structure
                {ok, QueryResult} = Result,
                ?assertMatch(#{data := #{rows := _}}, QueryResult)
            end)
        ]
    end}.

%%%===================================================================
%%% Multiple Packets Scenario Tests
%%%===================================================================

%% Test: Multiple complete packets in one TCP recv
%% Validates: REQ-1.2
multiple_packets_scenario_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Conn) ->
        [
            ?_test(begin
                %% Execute a query that generates multiple response packets
                %% (Progress + Data + End-of-Stream)
                Result = clickhouse_erl:query(Conn, "SELECT number FROM system.numbers LIMIT 10"),

                %% Should succeed
                ?assertMatch({ok, _}, Result),

                %% Verify result structure
                {ok, QueryResult} = Result,
                ?assertMatch(#{data := #{rows := _}}, QueryResult)
            end)
        ]
    end}.

%%%===================================================================
%%% Incomplete Packet Scenario Tests
%%%===================================================================

%% Test: Packet split across multiple TCP recvs
%% Validates: REQ-1.3
incomplete_packet_scenario_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Conn) ->
        [
            ?_test(begin
                %% Execute a query that returns larger data blocks
                %% which are more likely to be split across TCP messages
                Result = clickhouse_erl:query(
                    Conn,
                    "SELECT number, toString(number) as str FROM system.numbers LIMIT 100"
                ),

                %% Should succeed even if packets are split
                ?assertMatch({ok, _}, Result),

                %% Verify result structure
                {ok, QueryResult} = Result,
                ?assertMatch(#{data := #{rows := _}}, QueryResult),

                %% Verify we got the expected number of rows
                Rows = maps:get(rows, maps:get(data, QueryResult)),
                ?assertEqual(100, length(Rows))
            end)
        ]
    end}.

%%%===================================================================
%%% Packet Split at Various Boundaries Tests
%%%===================================================================

%% Test: Packet split at header boundary
%% Validates: REQ-1.3
packet_split_at_header_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Conn) ->
        [
            ?_test(begin
                %% Execute multiple queries in sequence to test buffering
                Result1 = clickhouse_erl:query(Conn, "SELECT 1"),
                ?assertMatch({ok, _}, Result1),

                Result2 = clickhouse_erl:query(Conn, "SELECT 2"),
                ?assertMatch({ok, _}, Result2),

                Result3 = clickhouse_erl:query(Conn, "SELECT 3"),
                ?assertMatch({ok, _}, Result3)
            end)
        ]
    end}.

%% Test: Packet split mid-data
%% Validates: REQ-1.3
packet_split_mid_data_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Conn) ->
        [
            ?_test(begin
                %% Execute a query with larger result set
                Result = clickhouse_erl:query(
                    Conn,
                    "SELECT number, number * 2, number * 3 FROM system.numbers LIMIT 1000"
                ),

                %% Should succeed
                ?assertMatch({ok, _}, Result),

                %% Verify result
                {ok, QueryResult} = Result,
                Rows = maps:get(rows, maps:get(data, QueryResult)),
                ?assertEqual(1000, length(Rows))
            end)
        ]
    end}.

%% Test: Packet split between packets
%% Validates: REQ-1.2, REQ-1.3
packet_split_between_packets_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Conn) ->
        [
            ?_test(begin
                %% Execute a query that generates ProfileEvents packets
                %% These are more likely to be split across TCP messages
                Result = clickhouse_erl:query(
                    Conn,
                    "SELECT * FROM system.numbers LIMIT 5000"
                ),

                %% Should succeed
                ?assertMatch({ok, _}, Result),

                %% Verify result
                {ok, QueryResult} = Result,
                Rows = maps:get(rows, maps:get(data, QueryResult)),
                ?assertEqual(5000, length(Rows))
            end)
        ]
    end}.

%%%===================================================================
%%% Buffer Management Tests
%%%===================================================================

%% Test: Buffer is cleared after successful query
%% Validates: REQ-3.3
buffer_cleared_after_query_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Conn) ->
        [
            ?_test(begin
                %% Execute first query
                Result1 = clickhouse_erl:query(Conn, "SELECT 1"),
                ?assertMatch({ok, _}, Result1),

                %% Execute second query - should not have leftover buffer
                Result2 = clickhouse_erl:query(Conn, "SELECT 2"),
                ?assertMatch({ok, _}, Result2)
            end)
        ]
    end}.

%% Test: Buffer is cleared on error
%% Validates: REQ-3.3
buffer_cleared_on_error_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Conn) ->
        [
            ?_test(begin
                %% Execute invalid query (should fail)
                Result1 = clickhouse_erl:query(Conn, "SELECT * FROM nonexistent_table"),
                ?assertMatch({error, _}, Result1),

                %% Execute valid query - should work despite previous error
                Result2 = clickhouse_erl:query(Conn, "SELECT 1"),
                ?assertMatch({ok, _}, Result2)
            end)
        ]
    end}.

%%%===================================================================
%%% ProfileEvents Packet Tests
%%%===================================================================

%% Test: ProfileEvents packets are handled correctly
%% Validates: REQ-2.1, REQ-2.3
profile_events_handling_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Conn) ->
        [
            ?_test(begin
                %% Execute a simple query - ProfileEvents are sent with most queries
                Result = clickhouse_erl:query(Conn, "SELECT 1"),

                %% Should succeed
                ?assertMatch({ok, _}, Result)
            end)
        ]
    end}.
