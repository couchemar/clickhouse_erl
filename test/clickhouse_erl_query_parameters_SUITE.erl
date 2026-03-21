%% @doc Common Test suite for query parameters feature
%%
%% Tests query parameters against a real ClickHouse server.
%% Feature: query-parameters
-module(clickhouse_erl_query_parameters_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("clickhouse_erl_protocol.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).

%% Test cases - Parameter Substitution
-export([
    test_single_parameter_select/1,
    test_multiple_parameters_select/1,
    test_missing_parameter_error/1,
    test_parameter_order_independence/1
]).

%% Test cases - Backward Compatibility
-export([
    test_backward_compatibility_select/1
]).

%% Test cases - INSERT with Parameters
-export([
    test_insert_with_parameters/1,
    test_insert_without_parameters/1
]).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

%% @doc Returns list of test cases and groups
all() ->
    [
        {group, parameter_substitution},
        {group, backward_compatibility},
        {group, insert_with_parameters}
    ].

%% @doc Defines test groups
groups() ->
    [
        {parameter_substitution, [], [
            test_single_parameter_select,
            test_multiple_parameters_select,
            test_missing_parameter_error,
            test_parameter_order_independence
        ]},
        {backward_compatibility, [], [
            test_backward_compatibility_select
        ]},
        {insert_with_parameters, [sequence], [
            test_insert_with_parameters,
            test_insert_without_parameters
        ]}
    ].

%% @doc Suite-level configuration
suite() ->
    [
        {timetrap, {seconds, 30}}
    ].

%% @doc Setup for entire suite
init_per_suite(Config) ->
    test_helpers:setup(),
    case test_helpers:connect() of
        {ok, Conn} ->
            ct:pal("Suite connection established: ~p", [Conn]),
            [{connection, Conn} | Config];
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
%%% Test Cases: Parameter Substitution (Feature: query-parameters)
%%% Requirements: 4.5, 5.1-5.5
%%%===================================================================

%% @doc Test 9.1: Successful single parameter substitution (SELECT)
%% Property 9: Successful Parameter Substitution
%% Validates: Requirements 4.5
test_single_parameter_select(Config) ->
    Conn = ?config(connection, Config),
    Query = <<"SELECT {value:UInt64}">>,
    Parameters = [{<<"value">>, <<"42">>}],

    Result = clickhouse_erl:query(Conn, Query, #{parameters => Parameters}),

    ?assertMatch({ok, _}, Result),
    {ok, ResultMap} = Result,
    ?assertMatch(#{data := #{rows := [[42]]}}, ResultMap).

%% @doc Test 9.2: Successful multiple parameters (SELECT)
%% Property 7: Multiple Parameters Support
%% Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5
test_multiple_parameters_select(Config) ->
    Conn = ?config(connection, Config),
    Query = <<"SELECT {a:UInt64}, {b:String}">>,
    Parameters = [{<<"a">>, <<"1">>}, {<<"b">>, <<"test">>}],

    Result = clickhouse_erl:query(Conn, Query, #{parameters => Parameters}),

    ?assertMatch({ok, _}, Result),
    {ok, ResultMap} = Result,
    ?assertMatch(#{data := #{rows := [[1, <<"test">>]]}}, ResultMap).

%% @doc Test 9.3: Missing parameter error (SELECT)
%% Property 8: Server Error Preservation
%% Validates: Requirements 4.1, 4.3, 4.4
test_missing_parameter_error(Config) ->
    Conn = ?config(connection, Config),
    Query = <<"SELECT {missing:UInt64}">>,
    Parameters = [],

    Result = clickhouse_erl:query(Conn, Query, #{parameters => Parameters}),

    ?assertMatch({error, {server_exception, #{code := _, message := _}}}, Result),
    {error, {server_exception, ExceptionInfo}} = Result,

    %% Verify the error message mentions the missing parameter
    Message = maps:get(message, ExceptionInfo),
    ?assert(
        string:find(Message, <<"missing">>) =/= nomatch orelse
            string:find(Message, <<"Substitution">>) =/= nomatch
    ).

%% @doc Test 9.4: Parameter order independence (SELECT)
%% Validates: Requirements 5.5
test_parameter_order_independence(Config) ->
    Conn = ?config(connection, Config),
    Query = <<"SELECT {b:String}, {a:UInt64}">>,
    %% Parameters in different order than placeholders
    Parameters = [{<<"a">>, <<"1">>}, {<<"b">>, <<"test">>}],

    Result = clickhouse_erl:query(Conn, Query, #{parameters => Parameters}),

    ?assertMatch({ok, _}, Result),
    {ok, ResultMap} = Result,
    %% Result order matches query order (b, a)
    ?assertMatch(#{data := #{rows := [[<<"test">>, 1]]}}, ResultMap).

%%%===================================================================
%%% Test Cases: Backward Compatibility
%%% Requirements: 6.1, 6.3
%%%===================================================================

%% @doc Test 9.5: Backward compatibility (SELECT)
%% Validates: Requirements 6.1, 6.3
test_backward_compatibility_select(Config) ->
    Conn = ?config(connection, Config),
    Query = <<"SELECT 1">>,

    %% Query without parameters option
    Result = clickhouse_erl:query(Conn, Query),

    ?assertMatch({ok, _}, Result),
    {ok, ResultMap} = Result,
    ?assertMatch(#{data := #{rows := [[1]]}}, ResultMap).

%%%===================================================================
%%% Test Cases: INSERT with Parameters
%%% Requirements: 1.6, 6.6, 8.1-8.7
%%%===================================================================

%% @doc Test 9.6: INSERT with parameters
%% Property 10: INSERT Parameter Support
%% Validates: Requirements 1.6, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6
test_insert_with_parameters(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table
    CreateTable =
        <<"CREATE TABLE IF NOT EXISTS param_test (id UInt32, name String) ENGINE = Memory">>,
    {ok, _} = clickhouse_erl:query(Conn, CreateTable),

    %% Clean table
    {ok, _} = clickhouse_erl:query(Conn, <<"TRUNCATE TABLE param_test">>),

    %% INSERT with parameters
    InsertQuery = <<"INSERT INTO param_test (id, name) VALUES ({id:UInt32}, {name:String})">>,
    Parameters = [{<<"id">>, <<"123">>}, {<<"name">>, <<"test">>}],

    InsertResult = clickhouse_erl:query(Conn, InsertQuery, #{parameters => Parameters}),

    ?assertMatch({ok, _}, InsertResult),

    %% Verify data was inserted
    SelectQuery = <<"SELECT * FROM param_test WHERE id = 123">>,
    {ok, SelectResult} = clickhouse_erl:query(Conn, SelectQuery),
    ?assertMatch(#{data := #{rows := [[123, <<"test">>]]}}, SelectResult),

    %% Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE param_test">>).

%% @doc Test 9.7: INSERT without parameters (backward compatibility)
%% Validates: Requirements 6.6, 8.7
test_insert_without_parameters(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table
    CreateTable =
        <<"CREATE TABLE IF NOT EXISTS param_test_compat (id UInt32, name String) ENGINE = Memory">>,
    {ok, _} = clickhouse_erl:query(Conn, CreateTable),

    %% Clean table
    {ok, _} = clickhouse_erl:query(Conn, <<"TRUNCATE TABLE param_test_compat">>),

    %% INSERT without parameters using standard format
    InsertQuery = <<"INSERT INTO param_test_compat (id, name) VALUES">>,
    Columns = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [456]},
        #{name => <<"name">>, type => <<"String">>, data => [<<"compat_test">>]}
    ],

    InsertResult = clickhouse_erl:insert(Conn, InsertQuery, Columns),

    ?assertMatch({ok, _}, InsertResult),

    %% Verify data was inserted
    SelectQuery = <<"SELECT * FROM param_test_compat WHERE id = 456">>,
    {ok, SelectResult} = clickhouse_erl:query(Conn, SelectQuery),
    ?assertMatch(#{data := #{rows := [[456, <<"compat_test">>]]}}, SelectResult),

    %% Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE param_test_compat">>).
