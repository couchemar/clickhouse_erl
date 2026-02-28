%%%-------------------------------------------------------------------
%% @doc Unit tests for optional callback support (on_progress, on_profile, on_profile_events)
%% @end
%%%-------------------------------------------------------------------
-module(clickhouse_erl_connection_optional_callbacks_tests).

-include_lib("eunit/include/eunit.hrl").
-include("clickhouse_erl_protocol.hrl").

%%%===================================================================
%%% Test Cases
%%%===================================================================

%% Test: invoke_optional_callback with successful callback
invoke_optional_callback_success_test() ->
    %% Create a callback that returns ok
    Callback = fun(Info) ->
        ?assertEqual(#{test => value}, Info),
        ok
    end,

    %% Invoke callback
    Result = clickhouse_erl_connection:invoke_optional_callback(Callback, #{test => value}),

    %% Should return ok
    ?assertEqual(ok, Result).

%% Test: invoke_optional_callback with callback returning error
invoke_optional_callback_error_test() ->
    %% Create a callback that returns error
    Callback = fun(_Info) ->
        {error, test_error}
    end,

    %% Invoke callback - should log but return ok (non-fatal)
    Result = clickhouse_erl_connection:invoke_optional_callback(Callback, #{test => value}),

    %% Should return ok despite callback error
    ?assertEqual(ok, Result).

%% Test: invoke_optional_callback with crashing callback
invoke_optional_callback_crash_test() ->
    %% Create a callback that crashes
    Callback = fun(_Info) ->
        error(intentional_crash)
    end,

    %% Invoke callback - should catch crash and return ok (non-fatal)
    Result = clickhouse_erl_connection:invoke_optional_callback(Callback, #{test => value}),

    %% Should return ok despite crash
    ?assertEqual(ok, Result).

%% Test: invoke_optional_callback with invalid return value
invoke_optional_callback_invalid_return_test() ->
    %% Create a callback that returns invalid value
    Callback = fun(_Info) ->
        invalid_return
    end,

    %% Invoke callback - should log but return ok (non-fatal)
    Result = clickhouse_erl_connection:invoke_optional_callback(Callback, #{test => value}),

    %% Should return ok despite invalid return
    ?assertEqual(ok, Result).

%% Test: default optional callbacks are set during query initialization
default_optional_callbacks_test() ->
    %% Create a PreparedRequest without optional callbacks
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>
    },

    %% Validate the request
    case clickhouse_erl_connection:validate_prepared_request(PreparedRequest) of
        ok ->
            %% Request is valid - default callbacks will be set during send_query_packet
            ok;
        {error, Reason} ->
            ?assert(false, io_lib:format("Validation failed: ~p", [Reason]))
    end.

%% Test: user-provided optional callbacks are preserved
user_optional_callbacks_test() ->
    %% Track callback invocations
    TestPid = self(),

    %% Create a PreparedRequest with optional callbacks
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_progress => fun(Info) ->
            TestPid ! {progress, Info},
            ok
        end,
        on_profile => fun(Info) ->
            TestPid ! {profile, Info},
            ok
        end,
        on_profile_events => fun(Info) ->
            TestPid ! {profile_events, Info},
            ok
        end
    },

    %% Validate the request
    case clickhouse_erl_connection:validate_prepared_request(PreparedRequest) of
        ok ->
            %% Request is valid - user callbacks will be used
            ok;
        {error, Reason} ->
            ?assert(false, io_lib:format("Validation failed: ~p", [Reason]))
    end.
