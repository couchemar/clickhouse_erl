%% @doc Unit tests for callback validation in clickhouse_erl_connection.
%% These tests don't require a ClickHouse connection.
-module(clickhouse_erl_connection_callback_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Callback arity validation tests
%%%===================================================================

validate_on_data_callback_correct_arity_test() ->
    Callback = fun(_DataBlock, _Acc) -> {ok, []} end,
    ok = clickhouse_erl_connection:validate_callback(on_data, Callback).

validate_on_data_callback_incorrect_arity_1_test() ->
    Callback = fun(_DataBlock) -> {ok, []} end,
    {error, {invalid_callback_arity, 2, 1}} = clickhouse_erl_connection:validate_callback(
        on_data, Callback
    ).

validate_on_data_callback_incorrect_arity_3_test() ->
    Callback = fun(_DataBlock, _Acc, _Extra) -> {ok, []} end,
    {error, {invalid_callback_arity, 2, 3}} = clickhouse_erl_connection:validate_callback(
        on_data, Callback
    ).

validate_on_progress_callback_correct_arity_test() ->
    Callback = fun(_ProgressInfo) -> ok end,
    ok = clickhouse_erl_connection:validate_callback(on_progress, Callback).

validate_on_progress_callback_incorrect_arity_test() ->
    Callback = fun(_ProgressInfo, _Extra) -> ok end,
    {error, {invalid_callback_arity, 1, 2}} = clickhouse_erl_connection:validate_callback(
        on_progress, Callback
    ).

validate_on_profile_callback_correct_arity_test() ->
    Callback = fun(_ProfileInfo) -> ok end,
    ok = clickhouse_erl_connection:validate_callback(on_profile, Callback).

validate_on_profile_callback_incorrect_arity_test() ->
    Callback = fun() -> ok end,
    {error, {invalid_callback_arity, 1, 0}} = clickhouse_erl_connection:validate_callback(
        on_profile, Callback
    ).

validate_on_profile_events_callback_correct_arity_test() ->
    Callback = fun(_ProfileEvents) -> ok end,
    ok = clickhouse_erl_connection:validate_callback(on_profile_events, Callback).

validate_on_profile_events_callback_incorrect_arity_test() ->
    Callback = fun(_ProfileEvents, _Extra) -> ok end,
    {error, {invalid_callback_arity, 1, 2}} = clickhouse_erl_connection:validate_callback(
        on_profile_events, Callback
    ).

validate_callback_not_a_function_test() ->
    NotAFunction = "not a function",
    {error, {invalid_callback_type, NotAFunction}} = clickhouse_erl_connection:validate_callback(
        on_data, NotAFunction
    ).

validate_callback_undefined_test() ->
    %% undefined is now rejected - defaults are set before validation
    {error, {invalid_callback_type, undefined}} = clickhouse_erl_connection:validate_callback(
        on_data, undefined
    ).

%%%===================================================================
%%% PreparedRequest validation tests
%%%===================================================================

validate_prepared_request_with_valid_on_data_test() ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_data => fun(_DataBlock, _Acc) -> {ok, []} end,
        initial_accumulator => []
    },
    ok = clickhouse_erl_connection:validate_prepared_request(PreparedRequest).

validate_prepared_request_with_invalid_on_data_test() ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_data => fun(_DataBlock) -> {ok, []} end
    },
    {error, {invalid_callback_arity, 2, 1}} = clickhouse_erl_connection:validate_prepared_request(
        PreparedRequest
    ).

validate_prepared_request_with_valid_optional_callbacks_test() ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_progress => fun(_ProgressInfo) -> ok end,
        on_profile => fun(_ProfileInfo) -> ok end,
        on_profile_events => fun(_ProfileEvents) -> ok end
    },
    ok = clickhouse_erl_connection:validate_prepared_request(PreparedRequest).

validate_prepared_request_with_invalid_on_progress_test() ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_progress => fun(_ProgressInfo, _Extra) -> ok end
    },
    {error, {invalid_callback_arity, 1, 2}} = clickhouse_erl_connection:validate_prepared_request(
        PreparedRequest
    ).

validate_prepared_request_without_callbacks_test() ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>
    },
    ok = clickhouse_erl_connection:validate_prepared_request(PreparedRequest).
