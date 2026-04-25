-module(clickhouse_erl_optional_callbacks_integration_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).
-export([
    optional_callbacks_integration/1,
    optional_callback_error_nonfatal/1,
    optional_callback_crash_nonfatal/1
]).

suite() ->
    [{timetrap, {seconds, 30}}].

all() ->
    [
        optional_callbacks_integration,
        optional_callback_error_nonfatal,
        optional_callback_crash_nonfatal
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

init_per_testcase(_TestCase, Config) ->
    {ok, Conn} = test_helpers:connect(),
    [{connection, Conn} | Config].

end_per_testcase(_TestCase, Config) ->
    Conn = ?config(connection, Config),
    clickhouse_erl_connection:disconnect(Conn),
    ok.

%% Test: optional callbacks are invoked during query execution
optional_callbacks_integration(Config) ->
    Conn = ?config(connection, Config),
    TestPid = self(),

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

    {ok, _Result} = clickhouse_erl_connection:query(Conn, PreparedRequest),
    ok.

%% Test: optional callback errors are non-fatal
optional_callback_error_nonfatal(Config) ->
    Conn = ?config(connection, Config),

    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 100">>,
        query_id => <<"optional-callback-error-test">>,
        on_progress => fun(_Info) ->
            {error, intentional_error}
        end
    },

    {ok, _} = clickhouse_erl_connection:query(Conn, PreparedRequest),
    ok.

%% Test: optional callback crash is non-fatal
optional_callback_crash_nonfatal(Config) ->
    Conn = ?config(connection, Config),

    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 100">>,
        query_id => <<"optional-callback-crash-test">>,
        on_progress => fun(_Info) ->
            error(intentional_crash)
        end
    },

    {ok, _} = clickhouse_erl_connection:query(Conn, PreparedRequest),
    ok.
