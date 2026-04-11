-module(clickhouse_erl_cancel_query_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([cancel_query_no_active_query/1, cancel_query_active_query/1, cancel_query_with_id/1]).

suite() ->
    [{timetrap, {seconds, 30}}].

all() ->
    [cancel_query_no_active_query, cancel_query_active_query, cancel_query_with_id].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Test cancel_query/1 with no active query
cancel_query_no_active_query(_Config) ->
    {ok, Conn} = test_helpers:connect(),
    Result = clickhouse_erl:cancel_query(Conn),
    {error, no_active_query} = Result,
    test_helpers:disconnect(Conn),
    ok.

%% Test cancel_query/1 with active query
cancel_query_active_query(_Config) ->
    {ok, Conn} = test_helpers:connect(),
    Parent = self(),
    spawn_link(fun() ->
        SQL = <<"SELECT sleep(3)">>,
        Result = clickhouse_erl:query(Conn, SQL),
        Parent ! {query_result, Result}
    end),
    timer:sleep(100),
    ok = clickhouse_erl:cancel_query(Conn),
    receive
        {query_result, {error, {query_cancelled, _QueryId}}} ->
            ok;
        {query_result, Other} ->
            ct:fail("Expected cancelled error, got: ~p", [Other])
    after 5000 ->
        ct:fail("Query did not complete within timeout")
    end,
    test_helpers:disconnect(Conn),
    ok.

%% Test that cancel_query/2 still works (backward compatibility)
cancel_query_with_id(_Config) ->
    {ok, Conn} = test_helpers:connect(),
    QueryId = <<"test_cancel_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    Parent = self(),
    spawn_link(fun() ->
        SQL = <<"SELECT sleep(3)">>,
        Result = clickhouse_erl:query(Conn, SQL, #{query_id => QueryId}),
        Parent ! {query_result, Result}
    end),
    timer:sleep(100),
    ok = clickhouse_erl:cancel_query(Conn, QueryId),
    receive
        {query_result, {error, {query_cancelled, QueryId}}} ->
            ok;
        {query_result, Other} ->
            ct:fail("Expected cancelled error, got: ~p", [Other])
    after 5000 ->
        ct:fail("Query did not complete within timeout")
    end,
    test_helpers:disconnect(Conn),
    ok.
