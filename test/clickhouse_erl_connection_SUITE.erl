%% @doc Common Test suite for connection property tests
%%
%% Tests connection properties against real ClickHouse server.
%% Feature: connection-management, Properties: Query handling, error detection
%% Validates: Requirements 2.1, 2.2, 4.1, 5.1, 8.1
-module(clickhouse_erl_connection_SUITE).

-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).

%% Test cases
-export([
    prop_query_execution/1,
    prop_error_detection/1,
    prop_timeout_handling/1,
    prop_concurrent_query_rejection/1
]).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

%% @doc Returns list of test cases and groups
all() ->
    [
        {group, property_tests}
    ].

%% @doc Defines test groups
groups() ->
    [
        {property_tests, [], [
            prop_query_execution,
            prop_error_detection,
            prop_timeout_handling,
            prop_concurrent_query_rejection
        ]}
    ].

%% @doc Suite-level configuration
suite() ->
    [
        {timetrap, {minutes, 5}}
    ].

%% @doc Setup for entire suite
init_per_suite(Config) ->
    %% Initialize ct_property_test (compiles property_test/*.erl files)
    Config1 = ct_property_test:init_per_suite(Config),

    %% Setup test helpers and establish connection
    test_helpers:setup(),
    case test_helpers:connect() of
        {ok, Conn} ->
            ct:pal("Suite connection established: ~p", [Conn]),
            [{connection, Conn} | Config1];
        {error, Reason} ->
            {skip, {connection_failed, Reason}}
    end.

%% @doc Cleanup for entire suite
end_per_suite(Config) ->
    Conn = ?config(connection, Config),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup(),
    ok.

%% @doc Setup for test group
init_per_group(GroupName, Config) ->
    ct:pal("Starting group: ~p", [GroupName]),
    Config.

%% @doc Cleanup for test group
end_per_group(GroupName, Config) ->
    ct:pal("Finished group: ~p", [GroupName]),
    Config.

%%%===================================================================
%%% Property Test Cases
%%%===================================================================

%% @doc Property test: Query execution completeness
%% Tests that queries are properly executed and return valid results
prop_query_execution(Config) ->
    Conn = ?config(connection, Config),

    ct:pal("Running query execution property test with 50 iterations"),

    true = ct_property_test:quickcheck(
        ct_prop_connection:prop_query_execution(Conn),
        [{numtests, 50} | Config]
    ).

%% @doc Property test: Error detection
%% Tests that invalid queries return appropriate errors
prop_error_detection(Config) ->
    Conn = ?config(connection, Config),

    ct:pal("Running error detection property test with 50 iterations"),

    true = ct_property_test:quickcheck(
        ct_prop_connection:prop_error_detection(Conn),
        [{numtests, 50} | Config]
    ).

%% @doc Property test: Timeout handling
%% Tests that long-running queries can be cancelled with timeout
prop_timeout_handling(Config) ->
    Conn = ?config(connection, Config),

    ct:pal("Running timeout handling property test with 20 iterations"),

    true = ct_property_test:quickcheck(
        ct_prop_connection:prop_timeout_handling(Conn),
        [{numtests, 20} | Config]
    ).

%% @doc Property test: Concurrent query rejection
%% Tests that attempting concurrent queries returns appropriate rejection
prop_concurrent_query_rejection(Config) ->
    Conn = ?config(connection, Config),

    ct:pal("Running concurrent query rejection property test with 20 iterations"),

    true = ct_property_test:quickcheck(
        ct_prop_connection:prop_concurrent_query_rejection(Conn),
        [{numtests, 20} | Config]
    ).
