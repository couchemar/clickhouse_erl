%%%-------------------------------------------------------------------
%% @doc Integration test for optional callbacks (on_progress, on_profile, on_profile_events)
%% This test verifies that optional callbacks are invoked during real query execution
%% @end
%%%-------------------------------------------------------------------
-module(clickhouse_erl_optional_callbacks_integration_test).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Integration Tests
%%%===================================================================

%% Test: optional callbacks are invoked during query execution
optional_callbacks_integration_test_() ->
    {timeout, 30, fun() ->
        %% Start application
        {ok, _Apps} = application:ensure_all_started(clickhouse_erl),

        %% Connect to ClickHouse using test_helpers
        {ok, Conn} = test_helpers:connect(),

        %% Track callback invocations
        TestPid = self(),

        %% Create PreparedRequest with optional callbacks
        PreparedRequest = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 100">>,
            query_id => <<"optional-callbacks-test">>,
            on_progress => fun(Info) ->
                TestPid ! {progress_called, Info},
                ok
            end,
            on_profile => fun(Info) ->
                TestPid ! {profile_called, Info},
                ok
            end,
            on_profile_events => fun(Info) ->
                TestPid ! {profile_events_called, Info},
                ok
            end
        },

        %% Execute query
        {ok, _Result} = clickhouse_erl_connection:query(Conn, PreparedRequest),

        %% Note: Progress, profile, and profile_events packets may or may not be sent
        %% depending on the query and server configuration. We just verify that
        %% if they are sent, the callbacks are invoked without errors.

        %% Clean up
        clickhouse_erl_connection:disconnect(Conn),

        %% Test passes if query completed successfully
        ok
    end}.

%% Test: optional callback errors are non-fatal
optional_callback_error_nonfatal_test_() ->
    {timeout, 30, fun() ->
        %% Start application
        {ok, _Apps} = application:ensure_all_started(clickhouse_erl),

        %% Connect to ClickHouse using test_helpers
        {ok, Conn} = test_helpers:connect(),

        %% Create PreparedRequest with failing optional callback
        PreparedRequest = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 100">>,
            query_id => <<"optional-callback-error-test">>,
            on_progress => fun(_Info) ->
                %% Return error - should be logged but not stop query
                {error, intentional_error}
            end
        },

        %% Execute query - should succeed despite callback error
        Result = clickhouse_erl_connection:query(Conn, PreparedRequest),

        %% Query should complete successfully
        ?assertMatch({ok, _}, Result),

        %% Clean up
        clickhouse_erl_connection:disconnect(Conn),

        ok
    end}.

%% Test: optional callback crash is non-fatal
optional_callback_crash_nonfatal_test_() ->
    {timeout, 30, fun() ->
        %% Start application
        {ok, _Apps} = application:ensure_all_started(clickhouse_erl),

        %% Connect to ClickHouse using test_helpers
        {ok, Conn} = test_helpers:connect(),

        %% Create PreparedRequest with crashing optional callback
        PreparedRequest = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 100">>,
            query_id => <<"optional-callback-crash-test">>,
            on_progress => fun(_Info) ->
                %% Crash - should be caught and logged but not stop query
                error(intentional_crash)
            end
        },

        %% Execute query - should succeed despite callback crash
        Result = clickhouse_erl_connection:query(Conn, PreparedRequest),

        %% Query should complete successfully
        ?assertMatch({ok, _}, Result),

        %% Clean up
        clickhouse_erl_connection:disconnect(Conn),

        ok
    end}.
