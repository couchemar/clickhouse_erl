-module(clickhouse_erl_cancel_query_tests).
-include_lib("eunit/include/eunit.hrl").
-import(test_helpers, [setup/0, connect/0, disconnect/1]).

%% Test cancel_query/1 with no active query
cancel_query_no_active_query_test() ->
    setup(),
    {ok, Conn} = connect(),

    % Try to cancel when no query is active
    Result = clickhouse_erl:cancel_query(Conn),
    ?assertEqual({error, no_active_query}, Result),

    disconnect(Conn).

%% Test cancel_query/1 with active query
cancel_query_active_query_test() ->
    setup(),
    {ok, Conn} = connect(),

    % Start a long-running query in a separate process
    Parent = self(),
    spawn_link(fun() ->
        SQL = <<"SELECT sleep(3)">>,
        Result = clickhouse_erl:query(Conn, SQL),
        Parent ! {query_result, Result}
    end),

    % Give query time to start
    timer:sleep(100),

    % Cancel the active query (without knowing the query_id)
    ok = clickhouse_erl:cancel_query(Conn),

    % Wait for query result
    receive
        {query_result, {error, {query_cancelled, _QueryId}}} ->
            ok;
        {query_result, Other} ->
            ?assert(false, io_lib:format("Expected cancelled error, got: ~p", [Other]))
    after 5000 ->
        ?assert(false, "Query did not complete within timeout")
    end,

    disconnect(Conn).

%% Test that cancel_query/2 still works (backward compatibility)
cancel_query_with_id_test() ->
    setup(),
    {ok, Conn} = connect(),

    QueryId = <<"test_cancel_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,

    % Start a long-running query with explicit query_id
    Parent = self(),
    spawn_link(fun() ->
        SQL = <<"SELECT sleep(3)">>,
        Result = clickhouse_erl:query(Conn, SQL, #{query_id => QueryId}),
        Parent ! {query_result, Result}
    end),

    % Give query time to start
    timer:sleep(100),

    % Cancel using the explicit query_id
    ok = clickhouse_erl:cancel_query(Conn, QueryId),

    % Wait for query result
    receive
        {query_result, {error, {query_cancelled, QueryId}}} ->
            ok;
        {query_result, Other} ->
            ?assert(false, io_lib:format("Expected cancelled error, got: ~p", [Other]))
    after 5000 ->
        ?assert(false, "Query did not complete within timeout")
    end,

    disconnect(Conn).
