-module(clickhouse_erl_connection_streaming_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Callback Arity Validation Tests
%%%===================================================================

%% Test that on_data callback with correct arity (2) is accepted
validate_on_data_callback_correct_arity_test() ->
    Callback = fun(_DataBlock, _Acc) -> {ok, []} end,
    ?assertEqual(ok, clickhouse_erl_connection:validate_callback(on_data, Callback)).

%% Test that on_data callback with incorrect arity (1) is rejected
validate_on_data_callback_incorrect_arity_1_test() ->
    Callback = fun(_DataBlock) -> {ok, []} end,
    ?assertEqual(
        {error, {invalid_callback_arity, 2, 1}},
        clickhouse_erl_connection:validate_callback(on_data, Callback)
    ).

%% Test that on_data callback with incorrect arity (3) is rejected
validate_on_data_callback_incorrect_arity_3_test() ->
    Callback = fun(_DataBlock, _Acc, _Extra) -> {ok, []} end,
    ?assertEqual(
        {error, {invalid_callback_arity, 2, 3}},
        clickhouse_erl_connection:validate_callback(on_data, Callback)
    ).

%% Test that on_progress callback with correct arity (1) is accepted
validate_on_progress_callback_correct_arity_test() ->
    Callback = fun(_ProgressInfo) -> ok end,
    ?assertEqual(ok, clickhouse_erl_connection:validate_callback(on_progress, Callback)).

%% Test that on_progress callback with incorrect arity (2) is rejected
validate_on_progress_callback_incorrect_arity_test() ->
    Callback = fun(_ProgressInfo, _Extra) -> ok end,
    ?assertEqual(
        {error, {invalid_callback_arity, 1, 2}},
        clickhouse_erl_connection:validate_callback(on_progress, Callback)
    ).

%% Test that on_profile callback with correct arity (1) is accepted
validate_on_profile_callback_correct_arity_test() ->
    Callback = fun(_ProfileInfo) -> ok end,
    ?assertEqual(ok, clickhouse_erl_connection:validate_callback(on_profile, Callback)).

%% Test that on_profile callback with incorrect arity (0) is rejected
validate_on_profile_callback_incorrect_arity_test() ->
    Callback = fun() -> ok end,
    ?assertEqual(
        {error, {invalid_callback_arity, 1, 0}},
        clickhouse_erl_connection:validate_callback(on_profile, Callback)
    ).

%% Test that on_profile_events callback with correct arity (1) is accepted
validate_on_profile_events_callback_correct_arity_test() ->
    Callback = fun(_ProfileEvents) -> ok end,
    ?assertEqual(ok, clickhouse_erl_connection:validate_callback(on_profile_events, Callback)).

%% Test that on_profile_events callback with incorrect arity (2) is rejected
validate_on_profile_events_callback_incorrect_arity_test() ->
    Callback = fun(_ProfileEvents, _Extra) -> ok end,
    ?assertEqual(
        {error, {invalid_callback_arity, 1, 2}},
        clickhouse_erl_connection:validate_callback(on_profile_events, Callback)
    ).

%% Test that non-function value is rejected
validate_callback_not_a_function_test() ->
    NotAFunction = "not a function",
    ?assertEqual(
        {error, {invalid_callback_type, NotAFunction}},
        clickhouse_erl_connection:validate_callback(on_data, NotAFunction)
    ).

%% Test that undefined callback is accepted (optional callback)
validate_callback_undefined_test() ->
    ?assertEqual(ok, clickhouse_erl_connection:validate_callback(on_data, undefined)).

%%%===================================================================
%%% PreparedRequest Validation Tests
%%%===================================================================

%% Test that PreparedRequest with valid on_data callback is accepted
validate_prepared_request_with_valid_on_data_test() ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_data => fun(_DataBlock, _Acc) -> {ok, []} end,
        initial_accumulator => []
    },
    ?assertEqual(ok, clickhouse_erl_connection:validate_prepared_request(PreparedRequest)).

%% Test that PreparedRequest with invalid on_data callback is rejected
validate_prepared_request_with_invalid_on_data_test() ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_data => fun(_DataBlock) -> {ok, []} end
    },
    ?assertEqual(
        {error, {invalid_callback_arity, 2, 1}},
        clickhouse_erl_connection:validate_prepared_request(PreparedRequest)
    ).

%% Test that PreparedRequest with valid optional callbacks is accepted
validate_prepared_request_with_valid_optional_callbacks_test() ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_progress => fun(_ProgressInfo) -> ok end,
        on_profile => fun(_ProfileInfo) -> ok end,
        on_profile_events => fun(_ProfileEvents) -> ok end
    },
    ?assertEqual(ok, clickhouse_erl_connection:validate_prepared_request(PreparedRequest)).

%% Test that PreparedRequest with invalid on_progress callback is rejected
validate_prepared_request_with_invalid_on_progress_test() ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_progress => fun(_ProgressInfo, _Extra) -> ok end
    },
    ?assertEqual(
        {error, {invalid_callback_arity, 1, 2}},
        clickhouse_erl_connection:validate_prepared_request(PreparedRequest)
    ).

%% Test that PreparedRequest without callbacks is accepted
validate_prepared_request_without_callbacks_test() ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>
    },
    ?assertEqual(ok, clickhouse_erl_connection:validate_prepared_request(PreparedRequest)).

%%%===================================================================
%%% Integration Tests with Connection
%%%===================================================================

%% Test that query with invalid callback is rejected before execution
query_with_invalid_callback_rejected_test() ->
    %% Start a connection using test_helpers
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

    %% Try to execute query with invalid on_data callback (arity 1 instead of 2)
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-invalid-callback">>,
        on_data => fun(_DataBlock) -> {ok, []} end
    },

    %% Should fail with invalid_callback_arity error
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    ?assertMatch({error, {invalid_callback_arity, 2, 1}}, Result),

    %% Clean up
    clickhouse_erl_connection:disconnect(Conn).

%% Test that query with valid callback is accepted
query_with_valid_callback_accepted_test() ->
    %% Start a connection using test_helpers
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

    %% Execute query with valid on_data callback (arity 2)
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-valid-callback">>,
        on_data => fun(_DataBlock, Acc) -> {ok, [_DataBlock | Acc]} end,
        initial_accumulator => []
    },

    %% Should succeed (callback validation passes, query executes)
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    ?assertMatch({ok, _}, Result),

    %% Clean up
    clickhouse_erl_connection:disconnect(Conn).

%% Test that query without callbacks still works (backward compatibility)
query_without_callbacks_works_test() ->
    %% Start a connection using test_helpers
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

    %% Execute query without any callbacks
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-no-callbacks">>
    },

    %% Should succeed
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    ?assertMatch({ok, _}, Result),

    %% Clean up
    clickhouse_erl_connection:disconnect(Conn).

%%%===================================================================
%%% Initial Accumulator Tests
%%%===================================================================

%% Test that missing initial_accumulator defaults to undefined
%% Requirements: 2.2
default_undefined_accumulator_test() ->
    %% Start a connection using test_helpers
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

    %% Track accumulator values received by callback
    TestPid = self(),

    %% Execute query with on_data callback but NO initial_accumulator
    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 3">>,
        query_id => <<"test-default-accumulator">>,
        on_data => fun(DataBlock, Acc) ->
            %% Send accumulator value to test process
            TestPid ! {accumulator, Acc},
            %% Accumulate data blocks
            {ok, [DataBlock | Acc]}
        end
        %% Note: initial_accumulator is NOT provided
    },

    %% Execute query
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    ?assertMatch({ok, _}, Result),

    %% Verify that first callback received undefined as accumulator
    receive
        {accumulator, FirstAcc} ->
            ?assertEqual(undefined, FirstAcc)
    after 1000 ->
        ?assert(false, "Did not receive accumulator value from callback")
    end,

    %% Clean up
    clickhouse_erl_connection:disconnect(Conn).

%%%===================================================================
%%% Empty Result Edge Case Tests
%%%===================================================================

%% Test that query with no data blocks returns appropriate empty result in batch mode
%% Requirements: 9.3
empty_result_batch_mode_test() ->
    %% Start a connection using test_helpers
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

    %% Execute a query that returns no data (CREATE TABLE IF NOT EXISTS)
    PreparedRequest = #{
        sql => <<"CREATE TABLE IF NOT EXISTS test_empty_result (id UInt32) ENGINE = Memory">>,
        query_id => <<"test-empty-batch">>
    },

    %% Execute query without callbacks (batch mode)
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),

    %% Should succeed with data key containing empty columns and rows
    ?assertMatch({ok, #{data := #{columns := [], rows := []}}}, Result),

    %% Verify statistics are present
    {ok, ResultMap} = Result,
    ?assert(maps:is_key(statistics, ResultMap)),

    %% Clean up - drop the table
    DropRequest = #{
        sql => <<"DROP TABLE IF EXISTS test_empty_result">>,
        query_id => <<"test-empty-batch-cleanup">>
    },
    clickhouse_erl_connection:query(Conn, DropRequest),
    clickhouse_erl_connection:disconnect(Conn).

%% Test that query with no data blocks returns initial accumulator in streaming mode
%% Requirements: 9.3
empty_result_streaming_mode_test() ->
    %% Start a connection using test_helpers
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

    %% Track callback invocations
    TestPid = self(),
    CallbackInvoked = make_ref(),

    %% Execute a query that returns no data with streaming callback
    PreparedRequest = #{
        sql => <<"CREATE TABLE IF NOT EXISTS test_empty_streaming (id UInt32) ENGINE = Memory">>,
        query_id => <<"test-empty-streaming">>,
        on_data => fun(DataBlock, Acc) ->
            %% This callback should NOT be invoked for queries with no data
            TestPid ! {callback_invoked, CallbackInvoked, DataBlock},
            {ok, [DataBlock | Acc]}
        end,
        initial_accumulator => []
    },

    %% Execute query
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),

    %% Should succeed with data key containing initial accumulator unchanged
    ?assertMatch({ok, #{data := []}}, Result),

    %% Verify statistics are present
    {ok, ResultMap} = Result,
    ?assert(maps:is_key(statistics, ResultMap)),

    %% Verify callback was NOT invoked (no DATA packets for DDL queries)
    receive
        {callback_invoked, CallbackInvoked, _} ->
            ?assert(false, "Callback should not be invoked for queries with no data blocks")
    after 100 ->
        %% Expected - callback should not be invoked
        ok
    end,

    %% Clean up - drop the table
    DropRequest = #{
        sql => <<"DROP TABLE IF EXISTS test_empty_streaming">>,
        query_id => <<"test-empty-streaming-cleanup">>
    },
    clickhouse_erl_connection:query(Conn, DropRequest),
    clickhouse_erl_connection:disconnect(Conn).

%% Test that INSERT query with callback returns initial accumulator
%% Requirements: 9.3
empty_result_insert_with_callback_test() ->
    %% Start a connection using test_helpers
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

    %% Create a test table
    CreateRequest = #{
        sql =>
            <<"CREATE TABLE IF NOT EXISTS test_insert_callback (id UInt32, value String) ENGINE = Memory">>,
        query_id => <<"test-insert-callback-create">>
    },
    {ok, _} = clickhouse_erl_connection:query(Conn, CreateRequest),

    %% Track callback invocations
    TestPid = self(),
    CallbackInvoked = make_ref(),

    %% Execute INSERT with callback
    PreparedRequest = #{
        sql => <<"INSERT INTO test_insert_callback VALUES (1, 'test')">>,
        query_id => <<"test-insert-callback">>,
        on_data => fun(DataBlock, Acc) ->
            %% This callback should NOT be invoked for INSERT queries
            TestPid ! {callback_invoked, CallbackInvoked, DataBlock},
            {ok, [DataBlock | Acc]}
        end,
        initial_accumulator => my_custom_accumulator
    },

    %% Execute query
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),

    %% When using query/2 with INSERT and callback, it's treated as streaming SELECT
    %% The accumulator is returned unchanged since no DATA packets arrive
    ?assertMatch({ok, #{data := my_custom_accumulator}}, Result),

    %% Verify callback was NOT invoked (INSERT doesn't send DATA packets)
    receive
        {callback_invoked, CallbackInvoked, _} ->
            ?assert(false, "Callback should not be invoked for INSERT queries")
    after 100 ->
        %% Expected - callback should not be invoked
        ok
    end,

    %% Clean up - drop the table
    DropRequest = #{
        sql => <<"DROP TABLE IF EXISTS test_insert_callback">>,
        query_id => <<"test-insert-callback-cleanup">>
    },
    clickhouse_erl_connection:query(Conn, DropRequest),
    clickhouse_erl_connection:disconnect(Conn).
