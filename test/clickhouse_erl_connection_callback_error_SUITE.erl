-module(clickhouse_erl_connection_callback_error_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([
    callback_returns_error/1,
    callback_crashes/1,
    callback_returns_invalid_value/1,
    callback_error_clears_query_state/1,
    callback_error_cancels_timer/1
]).

suite() ->
    [{timetrap, {seconds, 30}}].

all() ->
    [
        callback_returns_error,
        callback_crashes,
        callback_returns_invalid_value,
        callback_error_clears_query_state,
        callback_error_cancels_timer
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Test that callback returning {error, Reason} is properly handled
callback_returns_error(_Config) ->
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

    Callback = fun(_DataBlock, _Acc) ->
        {error, user_requested_stop}
    end,

    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
        query_id => <<"test-callback-error">>,
        on_data => Callback,
        initial_accumulator => []
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    {error, {callback_failed, user_requested_stop}} = Result,

    PreparedRequest2 = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-after-error">>
    },
    Result2 = clickhouse_erl_connection:query(Conn, PreparedRequest2),
    {ok, _} = Result2,

    clickhouse_erl_connection:disconnect(Conn),
    ok.

%% Test that callback crash is properly handled
callback_crashes(_Config) ->
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

    Callback = fun(_DataBlock, _Acc) ->
        error(intentional_crash)
    end,

    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
        query_id => <<"test-callback-crash">>,
        on_data => Callback,
        initial_accumulator => []
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    {error, {callback_failed, {callback_crashed, {error, intentional_crash, _}}}} = Result,

    PreparedRequest2 = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-after-crash">>
    },
    Result2 = clickhouse_erl_connection:query(Conn, PreparedRequest2),
    {ok, _} = Result2,

    clickhouse_erl_connection:disconnect(Conn),
    ok.

%% Test that callback returning invalid value is properly handled
callback_returns_invalid_value(_Config) ->
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

    Callback = fun(_DataBlock, _Acc) ->
        invalid_return_value
    end,

    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
        query_id => <<"test-callback-invalid">>,
        on_data => Callback,
        initial_accumulator => []
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    {error, {callback_failed, {invalid_callback_return, invalid_return_value}}} = Result,

    PreparedRequest2 = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-after-invalid">>
    },
    Result2 = clickhouse_erl_connection:query(Conn, PreparedRequest2),
    {ok, _} = Result2,

    clickhouse_erl_connection:disconnect(Conn),
    ok.

%% Test that callback error clears active query state
callback_error_clears_query_state(_Config) ->
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

    Callback = fun(_DataBlock, _Acc) ->
        {error, stop_processing}
    end,

    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
        query_id => <<"test-state-cleanup">>,
        on_data => Callback,
        initial_accumulator => []
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    {error, {callback_failed, stop_processing}} = Result,

    PreparedRequest2 = #{
        sql => <<"SELECT 2">>,
        query_id => <<"test-immediate-after">>
    },
    Result2 = clickhouse_erl_connection:query(Conn, PreparedRequest2),
    {ok, _} = Result2,

    clickhouse_erl_connection:disconnect(Conn),
    ok.

%% Test that timeout timer is cancelled on callback error
callback_error_cancels_timer(_Config) ->
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

    Callback = fun(_DataBlock, _Acc) ->
        {error, early_stop}
    end,

    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
        query_id => <<"test-timer-cancel">>,
        on_data => Callback,
        initial_accumulator => [],
        timeout => 30000
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    {error, {callback_failed, early_stop}} = Result,

    receive
        {query_timeout, _} ->
            ct:fail("Timeout message arrived when it should have been cancelled")
    after 100 ->
        ok
    end,

    clickhouse_erl_connection:disconnect(Conn),
    ok.
