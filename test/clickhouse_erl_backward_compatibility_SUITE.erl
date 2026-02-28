%% @doc Common Test suite for backward compatibility property tests
%%
%% Tests backward compatibility when using queries with and without parameters.
%% Feature: query-parameters, Property 3: Backward Compatibility
%% Validates: Requirements 1.2, 6.1, 6.4
-module(clickhouse_erl_backward_compatibility_SUITE).

-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).

%% Test cases
-export([
    prop_backward_compatibility/1
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
            prop_backward_compatibility
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

%% @doc Property test: Backward Compatibility
%% Feature: query-parameters, Property 3: Backward Compatibility
%% Validates: Requirements 1.2, 6.1, 6.4
%%
%% Tests that queries work identically with and without the parameters option.
prop_backward_compatibility(Config) ->
    Conn = ?config(connection, Config),

    ct:pal("Running backward compatibility property test with 50 iterations"),

    %% Use ct_property_test:quickcheck/2 to run the property
    %% The property module was compiled by init_per_suite
    ct_property_test:quickcheck(
        ct_prop_backward_compatibility:prop_backward_compatibility(Conn),
        Config
    ).
