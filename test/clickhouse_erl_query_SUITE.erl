%% @doc Common Test suite for query lifecycle management
%%
%% Tests query execution, timeout, cancellation, and concurrent connections
%% against a real ClickHouse server.
%%
%% Feature: query-lifecycle-management
-module(clickhouse_erl_query_SUITE).

-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Test cases - Query Execution and Completion (Task 8.1)
-export([
    simple_select_query/1,
    connection_available_after_query/1,
    multiple_sequential_queries/1
]).

%% Test cases - Query Timeout (Task 8.2)
-export([
    query_timeout_triggers_cancellation/1,
    connection_recovers_after_timeout/1
]).

%% Test cases - Query Cancellation (Task 8.3)
-export([
    cancel_mid_execution/1,
    connection_waits_for_eof_after_cancel/1
]).

%% Test cases - Concurrent Connections (Task 8.4)
-export([
    multiple_connections_concurrent_queries/1,
    no_cross_connection_interference/1
]).

%% Test cases - INSERT Query Lifecycle (Task 8.5)
-export([
    insert_query_execution/1,
    connection_available_after_insert/1
]).

%% Test cases - Settings API Simplification (Task 6)
-export([
    query_with_settings_simple_map/1,
    query_with_settings_keyword_list/1,
    query_with_settings_protocol_format/1,
    query_with_multiple_settings_simple_map/1,
    query_with_multiple_settings_keyword_list/1,
    query_with_multiple_settings_protocol_format/1
]).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

%% @doc Returns list of test cases and groups
suite() ->
    [{timetrap, {seconds, 30}}].

all() ->
    [
        {group, query_execution},
        {group, query_timeout},
        {group, query_cancellation},
        {group, concurrent_connections},
        {group, insert_lifecycle},
        {group, settings_api}
    ].

groups() ->
    [
        {query_execution, [sequence], [
            simple_select_query,
            connection_available_after_query,
            multiple_sequential_queries
        ]},
        {query_timeout, [sequence], [
            query_timeout_triggers_cancellation,
            connection_recovers_after_timeout
        ]},
        {query_cancellation, [sequence], [
            cancel_mid_execution,
            connection_waits_for_eof_after_cancel
        ]},
        {concurrent_connections, [sequence], [
            multiple_connections_concurrent_queries,
            no_cross_connection_interference
        ]},
        {insert_lifecycle, [sequence], [
            insert_query_execution,
            connection_available_after_insert
        ]},
        {settings_api, [sequence], [
            query_with_settings_simple_map,
            query_with_settings_keyword_list,
            query_with_settings_protocol_format,
            query_with_multiple_settings_simple_map,
            query_with_multiple_settings_keyword_list,
            query_with_multiple_settings_protocol_format
        ]}
    ].

%% @doc Initialize test suite - start application
init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

%% @doc Cleanup test suite
end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% @doc Initialize test group - create shared connection for sequential tests
init_per_group(Group, Config) when
    Group =:= query_execution;
    Group =:= query_timeout;
    Group =:= query_cancellation;
    Group =:= insert_lifecycle;
    Group =:= settings_api
->
    ct:pal("Initializing group ~p, creating connection", [Group]),
    case test_helpers:connect() of
        {ok, Conn} ->
            ct:pal("Connection created: ~p", [Conn]),
            [{connection, Conn} | Config];
        {error, Reason} ->
            ct:pal("Connection failed: ~p", [Reason]),
            ct:fail({connection_failed, Reason})
    end;
init_per_group(Group, Config) ->
    ct:pal("Initializing group ~p (no connection needed)", [Group]),
    Config.

%% @doc Cleanup test group - disconnect shared connection
end_per_group(Group, Config) when
    Group =:= query_execution;
    Group =:= query_timeout;
    Group =:= query_cancellation;
    Group =:= insert_lifecycle;
    Group =:= settings_api
->
    Conn = ?config(connection, Config),
    test_helpers:disconnect(Conn),
    ok;
end_per_group(_Group, _Config) ->
    ok.

%% @doc Initialize test case
init_per_testcase(TestCase, Config) when TestCase =:= multiple_connections_concurrent_queries ->
    %% Create 3 connections for concurrent query test
    ct:pal("Creating 3 connections for concurrent query test"),
    Connections = lists:map(
        fun(Idx) ->
            case test_helpers:connect() of
                {ok, Conn} ->
                    ct:pal("Connection ~p created: ~p", [Idx, Conn]),
                    Conn;
                {error, Reason} ->
                    ct:fail({connection_failed, Idx, Reason})
            end
        end,
        lists:seq(1, 3)
    ),
    ct:pal("All 3 connections created: ~p", [Connections]),
    [{concurrent_connections, Connections} | Config];
init_per_testcase(TestCase, Config) when TestCase =:= no_cross_connection_interference ->
    %% Create 2 connections for interference test
    {ok, Conn1} = test_helpers:connect(),
    {ok, Conn2} = test_helpers:connect(),
    [{conn1, Conn1}, {conn2, Conn2} | Config];
init_per_testcase(_TestCase, Config) ->
    Config.

%% @doc Cleanup test case
end_per_testcase(TestCase, Config) when TestCase =:= multiple_connections_concurrent_queries ->
    Connections = ?config(concurrent_connections, Config),
    lists:foreach(
        fun(Conn) -> test_helpers:disconnect(Conn) end,
        Connections
    ),
    ok;
end_per_testcase(TestCase, Config) when TestCase =:= no_cross_connection_interference ->
    Conn1 = ?config(conn1, Config),
    Conn2 = ?config(conn2, Config),
    test_helpers:disconnect(Conn1),
    test_helpers:disconnect(Conn2),
    ok;
end_per_testcase(_TestCase, _Config) ->
    ok.

%%%===================================================================
%%% Test Cases: Query Execution and Completion (Task 8.1)
%%% Requirements: 1.1, 2.1, 2.2, 2.3, 5.2
%%%===================================================================

simple_select_query(Config) ->
    Conn = ?config(connection, Config),

    %% Execute SELECT query against real ClickHouse
    SQL = <<"SELECT 1 as num">>,
    {ok, QueryResult} = clickhouse_erl:query(Conn, SQL),

    %% Verify data structure
    Data = maps:get(data, QueryResult),

    %% Verify columns metadata
    Columns = maps:get(columns, Data),
    [#{name := <<"num">>, type := <<"UInt8">>}] = Columns,

    %% Verify row data
    Rows = maps:get(rows, Data),
    [[1]] = Rows.

connection_available_after_query(Config) ->
    Conn = ?config(connection, Config),

    %% Execute first query
    SQL1 = <<"SELECT 42">>,
    {ok, _} = clickhouse_erl:query(Conn, SQL1),

    %% Immediately execute second query (no delay)
    %% Validates: Connection available for next query (Requirement 5.2)
    SQL2 = <<"SELECT 'hello'">>,
    {ok, QueryResult2} = clickhouse_erl:query(Conn, SQL2),

    Data2 = maps:get(data, QueryResult2),
    Rows2 = maps:get(rows, Data2),
    [[<<"hello">>]] = Rows2.

multiple_sequential_queries(Config) ->
    Conn = ?config(connection, Config),

    %% Execute multiple queries in sequence
    %% Validates: Query state cleanup and connection reusability
    Queries = [
        <<"SELECT 1">>,
        <<"SELECT 2">>,
        <<"SELECT 3">>,
        <<"SELECT 4">>,
        <<"SELECT 5">>
    ],

    Results = [clickhouse_erl:query(Conn, SQL) || SQL <- Queries],

    %% All queries should succeed
    lists:foreach(
        fun({ok, _}) -> ok end,
        Results
    ),

    %% Verify last result
    {ok, LastResult} = lists:last(Results),
    LastData = maps:get(data, LastResult),
    LastRows = maps:get(rows, LastData),
    [[5]] = LastRows.

%%%===================================================================
%%% Test Cases: Query Timeout (Task 8.2)
%%% Requirements: 3.3, 3.4, 4.1, 5.3
%%%===================================================================

query_timeout_triggers_cancellation(Config) ->
    Conn = ?config(connection, Config),

    %% Execute long-running query with short timeout
    SQL = <<"SELECT sleep(3)">>,
    Options = #{timeout => 500},

    StartTime = erlang:system_time(millisecond),
    Result = clickhouse_erl:query(Conn, SQL, Options),
    EndTime = erlang:system_time(millisecond),

    %% Verify timeout error received (Requirement 3.4)
    {error, {timeout_error, query_execution}} = Result,

    %% Verify timeout occurred around 500ms (not 3000ms)
    ElapsedMs = EndTime - StartTime,
    true = ElapsedMs >= 500,
    true = ElapsedMs < 2000,

    %% Wait for server to send EOF (server will continue executing sleep(3))
    timer:sleep(3500).

connection_recovers_after_timeout(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query that will timeout
    SQL = <<"SELECT sleep(2)">>,
    Options = #{timeout => 300},
    {error, {timeout_error, query_execution}} = clickhouse_erl:query(Conn, SQL, Options),

    %% Wait for ClickHouse to send EOF after cancellation
    %% (Requirement 5.3: Connection waits for EOF before accepting new queries)
    timer:sleep(3000),

    %% Verify connection accepts new queries (Requirement 5.3)
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

%%%===================================================================
%%% Test Cases: Query Cancellation (Task 8.3)
%%% Requirements: 4.1, 4.2, 4.3, 5.3
%%%===================================================================

cancel_mid_execution(Config) ->
    Conn = ?config(connection, Config),

    %% Execute long-running query
    SQL = <<"SELECT sleep(3)">>,
    QueryId = generate_query_id(<<"cancel_test">>),

    Parent = self(),
    spawn_link(fun() ->
        Result = clickhouse_erl:query(Conn, SQL, #{query_id => QueryId}),
        Parent ! {query_result, Result}
    end),

    %% Wait for query to start executing
    timer:sleep(500),

    %% Cancel mid-execution (Requirement 4.1)
    ok = clickhouse_erl:cancel_query(Conn, QueryId),

    %% Verify cancellation error received (Requirement 4.3)
    receive
        {query_result, {error, {query_cancelled, QueryId}}} ->
            ok
    after 3000 ->
        ct:fail("Timeout waiting for cancellation result")
    end,

    %% Wait for server EOF before test completes
    timer:sleep(3500).

connection_waits_for_eof_after_cancel(Config) ->
    Conn = ?config(connection, Config),

    %% Execute long-running query
    SQL = <<"SELECT sleep(3)">>,
    QueryId = generate_query_id(<<"eof_wait_test">>),

    Parent = self(),
    spawn_link(fun() ->
        Result = clickhouse_erl:query(Conn, SQL, #{query_id => QueryId}),
        Parent ! {query_result, Result}
    end),

    %% Wait for query to start
    timer:sleep(500),

    %% Cancel the query
    ok = clickhouse_erl:cancel_query(Conn, QueryId),

    %% Wait for cancellation to complete
    receive
        {query_result, _} -> ok
    after 4000 ->
        ct:fail("Timeout waiting for cancellation")
    end,

    %% Wait for server EOF (Requirement 5.3)
    timer:sleep(3500),

    %% Verify connection accepts new queries after EOF
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

%%%===================================================================
%%% Test Cases: Concurrent Connections (Task 8.4)
%%% Requirements: 5.1, 5.4
%%%===================================================================

multiple_connections_concurrent_queries(Config) ->
    Connections = ?config(concurrent_connections, Config),
    NumConnections = length(Connections),
    ct:pal("Starting concurrent queries test with ~p connections: ~p", [NumConnections, Connections]),

    %% Execute queries concurrently across connections
    Parent = self(),
    lists:foreach(
        fun({Idx, Conn}) ->
            ct:pal("Spawning query process ~p for connection ~p", [Idx, Conn]),
            spawn_link(fun() ->
                SQL = list_to_binary("SELECT " ++ integer_to_list(Idx * 10)),
                ct:pal("Process ~p executing query: ~s", [Idx, SQL]),
                Result = clickhouse_erl:query(Conn, SQL),
                ct:pal("Process ~p got result: ~p", [Idx, Result]),
                Parent ! {query_done, Idx, Result}
            end)
        end,
        lists:zip(lists:seq(1, NumConnections), Connections)
    ),

    ct:pal("All query processes spawned, waiting for results"),

    %% Collect all results (order doesn't matter - queries complete concurrently)
    Results = collect_query_results(NumConnections, 5000, []),

    ct:pal("All results collected: ~p", [Results]),

    %% Verify all queries succeeded
    lists:foreach(
        fun({ok, _}) -> ok end,
        Results
    ),

    %% Verify each connection handled one query at a time
    NumConnections = length(Results).

no_cross_connection_interference(Config) ->
    Conn1 = ?config(conn1, Config),
    Conn2 = ?config(conn2, Config),

    %% Start long-running query on Conn1
    Parent = self(),
    QueryId1 = generate_query_id(<<"conn1_query">>),

    spawn_link(fun() ->
        Result = clickhouse_erl:query(
            Conn1,
            <<"SELECT sleep(2)">>,
            #{query_id => QueryId1}
        ),
        Parent ! {conn1_result, Result}
    end),

    %% Wait for query to start
    timer:sleep(300),

    %% Execute quick query on Conn2 (should not be blocked by Conn1)
    {ok, QueryResult2} = clickhouse_erl:query(Conn2, <<"SELECT 42">>),

    %% Verify Conn2 result is correct
    Data2 = maps:get(data, QueryResult2),
    Rows2 = maps:get(rows, Data2),
    [[42]] = Rows2,

    %% Wait for Conn1 query to complete
    receive
        {conn1_result, {ok, _}} -> ok
    after 3000 ->
        ct:fail("Timeout waiting for Conn1 query")
    end,

    %% Verify both connections still work
    {ok, _} = clickhouse_erl:query(Conn1, <<"SELECT 1">>),
    {ok, _} = clickhouse_erl:query(Conn2, <<"SELECT 2">>).

%%%===================================================================
%%% Test Cases: INSERT Query Lifecycle (Task 8.5)
%%% Requirements: 1.1, 2.1, 2.2, 2.3, 5.2
%%%===================================================================

insert_query_execution(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table
    Table = <<"test_insert_lifecycle">>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn,
        <<"CREATE TABLE ", Table/binary, " (id UInt32, value String) ENGINE = Memory">>
    ),

    %% Execute INSERT query against real ClickHouse
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"value">>, type => <<"String">>, data => [<<"a">>, <<"b">>, <<"c">>]}
    ],
    SQL = <<"INSERT INTO ", Table/binary, " (id, value) VALUES">>,
    {ok, InsertResult} = clickhouse_erl:insert(Conn, SQL, Input),

    %% Verify INSERT succeeded
    3 = maps:get(rows_inserted, InsertResult),

    %% Verify data written correctly
    {ok, QueryResult} = clickhouse_erl:query(
        Conn,
        <<"SELECT id, value FROM ", Table/binary, " ORDER BY id">>
    ),
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    [[1, <<"a">>], [2, <<"b">>], [3, <<"c">>]] = Rows,

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

connection_available_after_insert(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table
    Table = <<"test_insert_availability">>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (id UInt32) ENGINE = Memory">>),

    %% Execute INSERT query
    Input = [#{name => <<"id">>, type => <<"UInt32">>, data => [42]}],
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, SQL, Input),

    %% Immediately execute another query (Requirement 5.2)
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>),

    %% Execute another INSERT immediately
    Input2 = [#{name => <<"id">>, type => <<"UInt32">>, data => [99]}],
    {ok, _} = clickhouse_erl:insert(Conn, SQL, Input2),

    %% Verify both inserts succeeded
    {ok, QueryResult} = clickhouse_erl:query(
        Conn,
        <<"SELECT count() FROM ", Table/binary>>
    ),
    Data = maps:get(data, QueryResult),
    [[2]] = maps:get(rows, Data),

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Collect query results in any order (concurrent queries may complete out of order)
-spec collect_query_results(non_neg_integer(), timeout(), list()) -> list().
collect_query_results(0, _Timeout, Acc) ->
    lists:reverse(Acc);
collect_query_results(Remaining, Timeout, Acc) ->
    receive
        {query_done, Idx, Result} ->
            ct:pal("Received result from query ~p: ~p", [Idx, Result]),
            collect_query_results(Remaining - 1, Timeout, [Result | Acc])
    after Timeout ->
        ct:pal("TIMEOUT waiting for ~p remaining queries", [Remaining]),
        ct:fail({timeout_waiting_for_queries, Remaining})
    end.

%% @doc Generate unique query ID with prefix
-spec generate_query_id(binary()) -> binary().
generate_query_id(Prefix) ->
    Unique = integer_to_binary(erlang:unique_integer([positive])),
    <<Prefix/binary, "_", Unique/binary>>.

%% @doc Execute a query and return ok or error
-spec execute(pid(), binary()) -> ok | {error, term()}.
execute(Conn, SQL) ->
    case clickhouse_erl:query(Conn, SQL) of
        {ok, _} -> ok;
        {error, Reason} -> {error, Reason}
    end.

%%%===================================================================
%%% Test Cases: Settings API Simplification (Task 6)
%%% Requirements: 1.1.1, 1.1.2, 1.2.1, 1.2.2, 1.3.1, 1.4.1
%%%===================================================================

query_with_settings_simple_map(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query with simple map settings format
    SQL = <<"SELECT 1">>,
    Options = #{settings => #{<<"max_threads">> => <<"2">>}},

    %% Verify query succeeds with simple map format (Requirement 1.1.1, 1.1.2)
    {ok, QueryResult} = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify result structure
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    [[1]] = Rows.

query_with_settings_keyword_list(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query with keyword list settings format
    SQL = <<"SELECT 1">>,
    Options = #{settings => [{<<"max_threads">>, <<"2">>}]},

    %% Verify query succeeds with keyword list format (Requirement 1.2.1, 1.2.2)
    {ok, QueryResult} = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify result structure
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    [[1]] = Rows.

query_with_settings_protocol_format(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query with protocol format settings (backward compatibility)
    SQL = <<"SELECT 1">>,
    Options = #{
        settings => [
            #{
                key => <<"max_threads">>,
                value => <<"2">>,
                important => false,
                custom => false,
                obsolete => false
            }
        ]
    },

    %% Verify query succeeds with protocol format (Requirement 1.3.1, 1.4.1)
    {ok, QueryResult} = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify result structure
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    [[1]] = Rows.

query_with_multiple_settings_simple_map(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query with multiple settings in simple map format
    SQL = <<"SELECT 1">>,
    Options = #{
        settings => #{
            <<"max_threads">> => <<"2">>,
            <<"max_block_size">> => <<"10000">>
        }
    },

    %% Verify query succeeds with multiple settings (Requirement 1.1.1)
    {ok, QueryResult} = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify result structure
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    [[1]] = Rows.

query_with_multiple_settings_keyword_list(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query with multiple settings in keyword list format
    SQL = <<"SELECT 1">>,
    Options = #{
        settings => [
            {<<"max_threads">>, <<"2">>},
            {<<"max_block_size">>, <<"10000">>}
        ]
    },

    %% Verify query succeeds with multiple settings (Requirement 1.2.1)
    {ok, QueryResult} = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify result structure
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    [[1]] = Rows.

query_with_multiple_settings_protocol_format(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query with multiple settings in protocol format
    SQL = <<"SELECT 1">>,
    Options = #{
        settings => [
            #{
                key => <<"max_threads">>,
                value => <<"2">>,
                important => false,
                custom => false,
                obsolete => false
            },
            #{
                key => <<"max_block_size">>,
                value => <<"10000">>,
                important => false,
                custom => false,
                obsolete => false
            }
        ]
    },

    %% Verify query succeeds with multiple settings (Requirement 1.3.1)
    {ok, QueryResult} = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify result structure
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    [[1]] = Rows.
