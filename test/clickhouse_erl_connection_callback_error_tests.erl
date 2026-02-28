-module(clickhouse_erl_connection_callback_error_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Callback Error Handling Tests
%%% Tests for task 4.1: Add callback error handling in parse_query_packet_data/4
%%%===================================================================

%% Test that callback returning {error, Reason} is properly handled
callback_returns_error_test() ->
    %% Start a connection
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    %% Create a callback that returns an error on first invocation
    Callback = fun(_DataBlock, _Acc) ->
        {error, user_requested_stop}
    end,

    %% Execute query with error-returning callback
    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
        query_id => <<"test-callback-error">>,
        on_data => Callback,
        initial_accumulator => []
    },

    %% Should return callback_failed error
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    ?assertMatch({error, {callback_failed, user_requested_stop}}, Result),

    %% Verify connection is still usable after callback error
    PreparedRequest2 = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-after-error">>
    },
    Result2 = clickhouse_erl_connection:query(Conn, PreparedRequest2),
    ?assertMatch({ok, _}, Result2),

    %% Clean up
    clickhouse_erl_connection:disconnect(Conn).

%% Test that callback crash is properly handled
callback_crashes_test() ->
    %% Start a connection
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    %% Create a callback that crashes
    Callback = fun(_DataBlock, _Acc) ->
        error(intentional_crash)
    end,

    %% Execute query with crashing callback
    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
        query_id => <<"test-callback-crash">>,
        on_data => Callback,
        initial_accumulator => []
    },

    %% Should return callback_failed with callback_crashed error
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    ?assertMatch({error, {callback_failed, {callback_crashed, _}}}, Result),

    %% Extract the crash details
    {error, {callback_failed, {callback_crashed, {Class, Reason, _Stacktrace}}}} = Result,
    ?assertEqual(error, Class),
    ?assertEqual(intentional_crash, Reason),

    %% Verify connection is still usable after callback crash
    PreparedRequest2 = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-after-crash">>
    },
    Result2 = clickhouse_erl_connection:query(Conn, PreparedRequest2),
    ?assertMatch({ok, _}, Result2),

    %% Clean up
    clickhouse_erl_connection:disconnect(Conn).

%% Test that callback returning invalid value is properly handled
callback_returns_invalid_value_test() ->
    %% Start a connection
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    %% Create a callback that returns invalid value (not {ok, _} or {error, _})
    Callback = fun(_DataBlock, _Acc) ->
        invalid_return_value
    end,

    %% Execute query with invalid-returning callback
    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
        query_id => <<"test-callback-invalid">>,
        on_data => Callback,
        initial_accumulator => []
    },

    %% Should return callback_failed with invalid_callback_return error
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    ?assertMatch(
        {error, {callback_failed, {invalid_callback_return, invalid_return_value}}},
        Result
    ),

    %% Verify connection is still usable after invalid callback return
    PreparedRequest2 = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-after-invalid">>
    },
    Result2 = clickhouse_erl_connection:query(Conn, PreparedRequest2),
    ?assertMatch({ok, _}, Result2),

    %% Clean up
    clickhouse_erl_connection:disconnect(Conn).

%% Test that callback error clears active query state
callback_error_clears_query_state_test() ->
    %% Start a connection
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    %% Create a callback that returns an error
    Callback = fun(_DataBlock, _Acc) ->
        {error, stop_processing}
    end,

    %% Execute query with error-returning callback
    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
        query_id => <<"test-state-cleanup">>,
        on_data => Callback,
        initial_accumulator => []
    },

    %% Should return callback_failed error
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    ?assertMatch({error, {callback_failed, stop_processing}}, Result),

    %% Immediately try another query - should succeed if state was cleared
    PreparedRequest2 = #{
        sql => <<"SELECT 2">>,
        query_id => <<"test-immediate-after">>
    },
    Result2 = clickhouse_erl_connection:query(Conn, PreparedRequest2),
    ?assertMatch({ok, _}, Result2),

    %% Clean up
    clickhouse_erl_connection:disconnect(Conn).

%% Test that timeout timer is cancelled on callback error
callback_error_cancels_timer_test() ->
    %% Start a connection
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    %% Create a callback that returns an error
    Callback = fun(_DataBlock, _Acc) ->
        {error, early_stop}
    end,

    %% Execute query with timeout and error-returning callback
    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
        query_id => <<"test-timer-cancel">>,
        on_data => Callback,
        initial_accumulator => [],
        timeout => 30000
    },

    %% Should return callback_failed error (not timeout)
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    ?assertMatch({error, {callback_failed, early_stop}}, Result),

    %% If timer wasn't cancelled, we might get a timeout message later
    %% Wait a bit to ensure no timeout message arrives
    receive
        {query_timeout, _} ->
            ?assert(false)
    after 100 ->
        ok
    end,

    %% Clean up
    clickhouse_erl_connection:disconnect(Conn).
