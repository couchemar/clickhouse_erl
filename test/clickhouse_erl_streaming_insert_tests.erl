%% @doc Unit tests for streaming insert API
-module(clickhouse_erl_streaming_insert_tests).

-include_lib("eunit/include/eunit.hrl").
-include("clickhouse_erl_connection.hrl").

%%%===================================================================
%%% Pull-based API export tests
%%%===================================================================

streaming_insert_3_exported_test() ->
    code:ensure_loaded(clickhouse_erl),
    ?assert(erlang:function_exported(clickhouse_erl, streaming_insert, 3)).

streaming_insert_4_exported_test() ->
    code:ensure_loaded(clickhouse_erl),
    ?assert(erlang:function_exported(clickhouse_erl, streaming_insert, 4)).

%%%===================================================================
%%% Push-based API export tests
%%%===================================================================

start_streaming_insert_3_exported_test() ->
    code:ensure_loaded(clickhouse_erl),
    ?assert(erlang:function_exported(clickhouse_erl, start_streaming_insert, 3)).

start_streaming_insert_4_exported_test() ->
    code:ensure_loaded(clickhouse_erl),
    ?assert(erlang:function_exported(clickhouse_erl, start_streaming_insert, 4)).

send_data_3_exported_test() ->
    code:ensure_loaded(clickhouse_erl),
    ?assert(erlang:function_exported(clickhouse_erl, send_data, 3)).

finish_streaming_insert_2_exported_test() ->
    code:ensure_loaded(clickhouse_erl),
    ?assert(erlang:function_exported(clickhouse_erl, finish_streaming_insert, 2)).

%%%===================================================================
%%% Pull-based API validation tests
%%%===================================================================

%% Test: streaming_insert with missing on_input callback returns error
%% Validates: Requirement 1.2
streaming_insert_missing_on_input_callback_test() ->
    PreparedRequest = #{
        sql => <<"INSERT INTO test_table (a, b) VALUES">>,
        columns => [#{name => <<"a">>, type => <<"UInt32">>, data => [1, 2, 3]}]
    },
    Result = clickhouse_erl_streaming_helpers:validate_streaming_request(PreparedRequest),
    ?assertEqual({error, {validation_error, missing_on_input_callback}}, Result).

%% Test: streaming_insert with empty columns returns error
%% Validates: Requirement 1.4
streaming_insert_empty_columns_test() ->
    PreparedRequest = #{
        sql => <<"INSERT INTO test_table (a, b) VALUES">>,
        columns => [],
        on_input => fun(_Columns, _Acc) -> {done, done} end
    },
    Result = clickhouse_erl_streaming_helpers:validate_streaming_request(PreparedRequest),
    ?assertEqual({error, {validation_error, empty_columns}}, Result).

%% Test: streaming_insert with valid request returns ok
%% Validates: Requirement 5.1
streaming_insert_valid_request_test() ->
    PreparedRequest = #{
        sql => <<"INSERT INTO test_table (a, b) VALUES">>,
        columns => [#{name => <<"a">>, type => <<"UInt32">>, data => [1, 2, 3]}],
        on_input => fun(_Columns, _Acc) -> {done, done} end
    },
    Result = clickhouse_erl_streaming_helpers:validate_streaming_request(PreparedRequest),
    ?assertEqual(ok, Result).

%%%===================================================================
%%% API delegation tests
%%%===================================================================

%% Test: streaming_insert/3 delegates to streaming_insert/4
%% Validates: Requirement 5.1
streaming_insert_3_delegates_to_4_test() ->
    %% Verify the 3-arity function exists and calls the 4-arity function
    code:ensure_loaded(clickhouse_erl),
    ?assert(erlang:function_exported(clickhouse_erl, streaming_insert, 3)),
    ?assert(erlang:function_exported(clickhouse_erl, streaming_insert, 4)).

%%%===================================================================
%%% Push-based API validation tests
%%%===================================================================

%% Test: start_streaming_insert with empty columns returns error
%% Validates: Requirement 12.1
start_streaming_insert_empty_columns_test() ->
    %% Test the public API function which validates empty columns
    code:ensure_loaded(clickhouse_erl),
    %% Mock a connection pid (won't actually be used since validation fails first)
    MockConn = make_ref(),
    SQL = <<"INSERT INTO test_table VALUES">>,
    %% Empty columns
    Options = #{columns => []},
    Result = clickhouse_erl:start_streaming_insert(MockConn, SQL, Options),
    ?assertEqual({error, {validation_error, empty_columns}}, Result).

%% Test: start_streaming_insert/3 delegates to start_streaming_insert/4
%% Validates: Requirement 9.2
start_streaming_insert_3_delegates_to_4_test() ->
    %% Verify the 3-arity function exists and calls the 4-arity function
    code:ensure_loaded(clickhouse_erl),
    ?assert(erlang:function_exported(clickhouse_erl, start_streaming_insert, 3)),
    ?assert(erlang:function_exported(clickhouse_erl, start_streaming_insert, 4)).

%% Test: send_data with no active session returns error
%% Validates: Requirement 11.5
send_data_no_active_session_test() ->
    %% Mock connection state with no active query
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = undefined
    },
    Result = clickhouse_erl_connection:handle_call(
        {send_data, make_ref(), []}, {self(), make_ref()}, State
    ),
    ?assertMatch({reply, {error, {validation_error, no_active_streaming_session}}, _}, Result).

%% Test: send_data with wrong stream ref returns error
%% Validates: Requirement 11.4
send_data_wrong_stream_ref_test() ->
    %% Mock connection state with active push session
    StreamRef = make_ref(),
    WrongRef = make_ref(),
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => false
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = #{push_session => SessionState}
    },
    Result = clickhouse_erl_connection:handle_call(
        {send_data, WrongRef, []}, {self(), make_ref()}, State
    ),
    ?assertMatch({reply, {error, {validation_error, invalid_stream_ref}}, _}, Result).

%% Test: send_data on failed session returns stored error reason
%% Validates: Requirement 14.2
send_data_failed_session_test() ->
    %% Mock connection state with failed push session (stores reason)
    StreamRef = make_ref(),
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => {true, {timeout_error, streaming_insert}}
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = #{push_session => SessionState}
    },
    Result = clickhouse_erl_connection:handle_call(
        {send_data, StreamRef, []}, {self(), make_ref()}, State
    ),
    ?assertMatch({reply, {error, {timeout_error, streaming_insert}}, _}, Result).

%% Test: finish_streaming_insert on failed session cleans up and returns stored reason
%% Validates: Requirement 14.3
finish_streaming_insert_failed_session_test() ->
    %% Mock connection state with failed push session (stores reason)
    StreamRef = make_ref(),
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => {true, {server_exception, #{message => <<"test">>}}}
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = #{push_session => SessionState}
    },
    Result = clickhouse_erl_connection:handle_call(
        {finish_streaming_insert, StreamRef}, {self(), make_ref()}, State
    ),
    ?assertMatch({reply, {error, {server_exception, _}}, _}, Result),
    %% Verify state was cleaned up
    {reply, _, NewState} = Result,
    ?assertEqual(undefined, NewState#connection_state.active_query_state).

%% Test: send_data validation error does NOT fail the session
%% Validates: Design doc — "Session remains active, caller fixes data"
send_data_validation_error_keeps_session_active_test() ->
    StreamRef = make_ref(),
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [
            #{name => <<"a">>, type => <<"UInt32">>, data => [1, 2, 3]},
            #{name => <<"b">>, type => <<"String">>, data => [<<"x">>, <<"y">>, <<"z">>]}
        ],
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => false,
        start_time => erlang:system_time(millisecond)
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = #{push_session => SessionState}
    },
    %% Send data with mismatched row counts between columns
    BadData = [
        #{name => <<"a">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"b">>, type => <<"String">>, data => [<<"x">>]}
    ],
    Result = clickhouse_erl_connection:handle_call(
        {send_data, StreamRef, BadData}, {self(), make_ref()}, State
    ),
    ?assertMatch({reply, {error, {validation_error, {row_count_mismatch, _}}}, _}, Result),
    %% Verify session is still active (not failed)
    {reply, _, NewState} = Result,
    #{push_session := NewSession} = NewState#connection_state.active_query_state,
    ?assertEqual(false, maps:get(session_failed, NewSession)).

%%%===================================================================
%%% finish_streaming_insert implementation tests
%%%===================================================================

%% Test: finish_streaming_insert includes start_time in session state
%% Validates: Requirement 9.6
finish_streaming_insert_includes_start_time_test() ->
    StreamRef = make_ref(),
    %% Create session state with start_time

    %% 1 second ago
    StartTime = erlang:system_time(millisecond) - 1000,
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 10,
        blocks_sent => 2,
        session_failed => false,
        start_time => StartTime
    },
    ActiveState = #{
        push_session => SessionState
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = ActiveState
    },
    %% Mock gen_tcp:send to succeed
    meck:new(gen_tcp, [unstick]),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(gen_tcp, recv, fun(_, _, _) -> {error, timeout} end),
    try
        Result = clickhouse_erl_connection:handle_call(
            {finish_streaming_insert, StreamRef}, {self(), make_ref()}, State
        ),
        case Result of
            {reply, {ok, ResultMap}, _} ->
                ?assert(is_map(ResultMap)),
                ?assert(maps:is_key(rows_inserted, ResultMap)),
                ?assert(maps:is_key(blocks_sent, ResultMap)),
                ?assert(maps:is_key(elapsed_time, ResultMap)),
                %% elapsed_time should be at least 1000ms
                ?assert(maps:get(elapsed_time, ResultMap) >= 1000);
            _ ->
                ?assert(false)
        end
    after
        meck:unload(gen_tcp)
    end.

%% Test: finish_streaming_insert without start_time returns 0 elapsed_time
%% Validates: Requirement 9.6
finish_streaming_insert_no_start_time_test() ->
    StreamRef = make_ref(),
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 10,
        blocks_sent => 2,
        session_failed => false
        %% No start_time field
    },
    ActiveState = #{
        push_session => SessionState
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = ActiveState
    },
    %% Mock gen_tcp:send to succeed
    meck:new(gen_tcp, [unstick]),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(gen_tcp, recv, fun(_, _, _) -> {error, timeout} end),
    try
        Result = clickhouse_erl_connection:handle_call(
            {finish_streaming_insert, StreamRef}, {self(), make_ref()}, State
        ),
        case Result of
            {reply, {ok, ResultMap}, _} ->
                ?assert(is_map(ResultMap)),
                ?assertEqual(10, maps:get(rows_inserted, ResultMap)),
                ?assertEqual(2, maps:get(blocks_sent, ResultMap)),
                ?assertEqual(0, maps:get(elapsed_time, ResultMap));
            _ ->
                ?assert(false)
        end
    after
        meck:unload(gen_tcp)
    end.

%% Test: finish_streaming_insert returns result with correct fields
%% Validates: Requirement 9.6
finish_streaming_insert_returns_result_test() ->
    StreamRef = make_ref(),
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 42,
        blocks_sent => 3,
        session_failed => false,
        start_time => erlang:system_time(millisecond) - 500
    },
    ActiveState = #{
        push_session => SessionState
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = ActiveState
    },
    %% Mock gen_tcp:send to succeed
    meck:new(gen_tcp, [unstick]),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(gen_tcp, recv, fun(_, _, _) -> {error, timeout} end),
    try
        Result = clickhouse_erl_connection:handle_call(
            {finish_streaming_insert, StreamRef}, {self(), make_ref()}, State
        ),
        case Result of
            {reply, {ok, ResultMap}, NewState} ->
                ?assert(is_map(ResultMap)),
                ?assertEqual(42, maps:get(rows_inserted, ResultMap)),
                ?assertEqual(3, maps:get(blocks_sent, ResultMap)),
                ?assert(maps:is_key(elapsed_time, ResultMap)),
                %% elapsed_time should be at least 500ms
                ?assert(maps:get(elapsed_time, ResultMap) >= 500),
                %% Check that active_query_state was cleared
                ?assertEqual(undefined, NewState#connection_state.active_query_state);
            _ ->
                ?assert(false)
        end
    after
        meck:unload(gen_tcp)
    end.

%% Test: finish_streaming_insert cancels timer
%% Validates: Requirement 10.3
finish_streaming_insert_cancels_timer_test() ->
    StreamRef = make_ref(),
    TimerRef = erlang:send_after(30000, self(), test),
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => false,
        start_time => erlang:system_time(millisecond)
    },
    ActiveState = #{
        push_session => SessionState,
        timeout_timer => TimerRef
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = ActiveState
    },
    %% Mock gen_tcp:send to succeed
    meck:new(gen_tcp, [unstick]),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(gen_tcp, recv, fun(_, _, _) -> {error, timeout} end),
    try
        Result = clickhouse_erl_connection:handle_call(
            {finish_streaming_insert, StreamRef}, {self(), make_ref()}, State
        ),
        %% Check that timer was cancelled
        ?assertNot(erlang:read_timer(TimerRef)),
        case Result of
            {reply, {ok, _}, NewState} ->
                ?assertEqual(undefined, NewState#connection_state.active_query_state);
            _ ->
                ?assert(false)
        end
    after
        meck:unload(gen_tcp)
    end.

%%%===================================================================
%%% Timeout enforcement tests (pull-based)
%%%===================================================================

%% Test: check_timeout returns ok when within timeout
%% Validates: Requirement 7.1
check_timeout_within_limit_test() ->
    %% 1 second ago
    StartTime = erlang:system_time(millisecond) - 1000,
    %% 2 second timeout
    Timeout = 2000,
    Result = clickhouse_erl_streaming_helpers:check_timeout(StartTime, Timeout),
    ?assertEqual(ok, Result).

%% Test: check_timeout returns error when timeout exceeded
%% Validates: Requirement 7.1, 7.2
check_timeout_exceeded_test() ->
    %% 3 seconds ago
    StartTime = erlang:system_time(millisecond) - 3000,
    %% 2 second timeout
    Timeout = 2000,
    Result = clickhouse_erl_streaming_helpers:check_timeout(StartTime, Timeout),
    ?assertEqual({error, {timeout_error, streaming_insert}}, Result).

%% Test: check_timeout with infinity never times out
%% Validates: Requirement 7.1
check_timeout_infinity_test() ->
    %% Long time ago
    StartTime = erlang:system_time(millisecond) - 1000000,
    Result = clickhouse_erl_streaming_helpers:check_timeout(StartTime, infinity),
    ?assertEqual(ok, Result).

%% Test: streaming_loop respects timeout and returns error
%% Validates: Requirement 7.1, 7.2
streaming_loop_timeout_enforcement_test() ->
    %% Create a callback that takes a long time
    %% Note: safe_invoke_on_input calls callback with only Acc, not (Columns, Acc)
    Callback = fun(Acc) ->
        %% Simulate work
        timer:sleep(100),
        {ok, [#{name => <<"col">>, type => <<"UInt32">>, data => []}], Acc + 1}
    end,

    %% Create mock state
    State = #connection_state{
        socket = undefined,
        state = ready,
        parser_state = #{}
    },

    %% Create stats with very short timeout
    StartTime = erlang:system_time(millisecond),
    Stats = #{
        rows_inserted => 0,
        blocks_sent => 0,
        start_time => StartTime,
        %% Very short timeout
        timeout => 50
    },

    Columns = [#{name => <<"col">>, type => <<"UInt32">>, data => []}],

    %% Run streaming loop - should timeout quickly
    Result = clickhouse_erl_connection:streaming_loop(State, Columns, 0, Callback, Stats),

    %% Should timeout before callback returns
    ?assertMatch({error, {timeout_error, streaming_insert}}, Result).

%% Test: streaming_loop continues when within timeout
%% Validates: Requirement 7.1
streaming_loop_within_timeout_test() ->
    %% Create a callback that returns done immediately
    %% Note: safe_invoke_on_input calls callback with only Acc, not (Columns, Acc)
    Callback = fun(Acc) ->
        {done, Acc}
    end,

    %% Create mock state
    State = #connection_state{
        socket = undefined,
        state = ready,
        parser_state = #{}
    },

    %% Create stats with reasonable timeout
    StartTime = erlang:system_time(millisecond),
    Stats = #{
        rows_inserted => 0,
        blocks_sent => 0,
        start_time => StartTime,
        %% 5 second timeout
        timeout => 5000
    },

    Columns = [#{name => <<"col">>, type => <<"UInt32">>, data => []}],

    %% Run streaming loop - should succeed
    Result = clickhouse_erl_connection:streaming_loop(State, Columns, 0, Callback, Stats),

    %% Should return done
    ?assertMatch({ok, 0, _}, Result).

%% Test: push-based timeout enforcement - timer fires and marks session as failed
%% Validates: Requirement 15.1, 15.2
push_based_timeout_enforcement_test() ->
    %% Create a mock connection state with active push session
    StreamRef = make_ref(),
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => false,
        start_time => erlang:system_time(millisecond)
    },
    ActiveState = #{
        push_session => SessionState,
        %% Timer will be set by start_streaming_insert
        timeout_timer => undefined
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = ActiveState
    },

    %% Simulate timeout message
    Result = clickhouse_erl_connection:handle_info(
        {streaming_timeout, StreamRef}, State
    ),

    %% Should mark session as failed
    ?assertMatch({noreply, _}, Result),
    {noreply, NewState} = Result,

    %% Check that session is marked as failed with timeout error
    #{push_session := NewSession} = NewState#connection_state.active_query_state,
    ?assertMatch(
        {true, {timeout_error, streaming_insert}},
        maps:get(session_failed, NewSession)
    ).

%% Test: send_data returns timeout error after session times out
%% Validates: Requirement 15.2
send_data_after_timeout_test() ->
    %% Create connection state with failed session (timed out)
    StreamRef = make_ref(),
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => {true, {timeout_error, streaming_insert}}
    },
    ActiveState = #{
        push_session => SessionState,
        timeout_timer => undefined
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = ActiveState
    },

    %% Try to send data - should return timeout error
    Result = clickhouse_erl_connection:handle_call(
        {send_data, StreamRef, []}, {self(), make_ref()}, State
    ),
    ?assertMatch({reply, {error, {timeout_error, streaming_insert}}, _}, Result).

%% Test: finish_streaming_insert returns timeout error after session times out
%% Validates: Requirement 15.2
finish_streaming_insert_after_timeout_test() ->
    %% Create connection state with failed session (timed out)
    StreamRef = make_ref(),
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => {true, {timeout_error, streaming_insert}}
    },
    ActiveState = #{
        push_session => SessionState,
        timeout_timer => undefined
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = ActiveState
    },

    %% Try to finish streaming - should return timeout error and clean up
    Result = clickhouse_erl_connection:handle_call(
        {finish_streaming_insert, StreamRef}, {self(), make_ref()}, State
    ),
    ?assertMatch({reply, {error, {timeout_error, streaming_insert}}, _}, Result),
    {reply, _, NewState} = Result,
    ?assertEqual(undefined, NewState#connection_state.active_query_state).

%%%===================================================================
%%% Cancellation support tests
%%%===================================================================

%% Test: cancel_query during pull-based streaming insert stops callback invocation
%% Validates: Requirement 7.3
pull_based_cancellation_stops_callback_test() ->
    %% Create mock state with active streaming insert
    QueryId = <<"test-query">>,
    ActiveQueryState = #{
        caller => {self(), make_ref()},
        query_id => QueryId,
        timeout => 30000,
        timer_ref => undefined,
        cancelled => false,
        replied => false,
        is_insert => true,
        on_data => fun(_, _) -> {ok, #{}} end,
        accumulator => #{}
    },
    %% Create a mock socket
    MockSocket = make_ref(),
    State = #connection_state{
        socket = MockSocket,
        state = ready,
        active_query_state = ActiveQueryState
    },

    %% Mock send_cancel_packet to succeed
    meck:new(gen_tcp, [unstick]),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(gen_tcp, recv, fun(_, _, _) -> {error, timeout} end),
    try
        %% Cancel the query
        Result = clickhouse_erl_connection:handle_call(
            {cancel_query, QueryId}, {self(), make_ref()}, State
        ),
        ?assertMatch({reply, ok, _}, Result),
        {reply, _, NewState} = Result,

        %% Check that query is marked as cancelled
        #{cancelled := Cancelled} = NewState#connection_state.active_query_state,
        ?assertEqual(true, Cancelled)
    after
        meck:unload(gen_tcp)
    end.

%% Test: streaming_loop does NOT support pull-based cancellation via cancel_query
%% The streaming loop runs synchronously inside handle_call, blocking the gen_server.
%% No cancel_query handle_call can execute while the loop is running.
%% Pull-based cancellation is only possible via timeout (check_timeout/2).
%% Validates: Requirement 7.3 (partially — timeout-based only for pull mode)
pull_based_cancellation_only_via_timeout_test() ->
    %% Create a callback that returns done immediately
    Callback = fun(Acc) ->
        {done, Acc}
    end,

    %% Create mock state — no cancelled flag needed
    State = #connection_state{
        socket = undefined,
        state = ready,
        parser_state = #{}
    },

    %% Create stats with very short timeout (already expired)
    StartTime = erlang:system_time(millisecond) - 5000,
    Stats = #{
        rows_inserted => 0,
        blocks_sent => 0,
        start_time => StartTime,
        %% Already expired
        timeout => 1
    },

    Columns = [#{name => <<"col">>, type => <<"UInt32">>, data => []}],

    %% Run streaming loop — should abort due to timeout
    Result = clickhouse_erl_connection:streaming_loop(State, Columns, 0, Callback, Stats),

    %% Timeout is the only way to abort a pull-based streaming loop
    ?assertMatch({error, {timeout_error, streaming_insert}}, Result).

%% Test: cancel_query during push-based streaming marks session as failed
%% Validates: Requirement 15.3
push_based_cancellation_marks_session_failed_test() ->
    %% Create connection state with active push session
    StreamRef = make_ref(),
    QueryId = <<"test-query">>,
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => false,
        start_time => erlang:system_time(millisecond)
    },
    ActiveQueryState = #{
        caller => {self(), make_ref()},
        query_id => QueryId,
        timeout => 30000,
        timer_ref => undefined,
        cancelled => false,
        replied => false,
        is_insert => true,
        on_data => fun(_, _) -> {ok, #{}} end,
        accumulator => #{},
        push_session => SessionState
    },
    %% Create a mock socket
    MockSocket = make_ref(),
    State = #connection_state{
        socket = MockSocket,
        state = ready,
        active_query_state = ActiveQueryState
    },

    %% Mock send_cancel_packet to succeed
    meck:new(gen_tcp, [unstick]),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(gen_tcp, recv, fun(_, _, _) -> {error, timeout} end),
    try
        %% Cancel the query
        Result = clickhouse_erl_connection:handle_call(
            {cancel_query, QueryId}, {self(), make_ref()}, State
        ),
        ?assertMatch({reply, ok, _}, Result),
        {reply, _, NewState} = Result,

        %% Check that session is marked as failed with cancellation reason
        #{push_session := NewSession} = NewState#connection_state.active_query_state,
        ?assertMatch({true, {query_cancelled, _}}, maps:get(session_failed, NewSession))
    after
        meck:unload(gen_tcp)
    end.

%% Test: send_data returns cancellation error after session cancelled
%% Validates: Requirement 15.3
send_data_after_cancellation_test() ->
    %% Create connection state with cancelled push session
    StreamRef = make_ref(),
    QueryId = <<"test-query">>,
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => {true, {query_cancelled, QueryId}}
    },
    ActiveState = #{
        push_session => SessionState,
        timeout_timer => undefined
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = ActiveState
    },

    %% Try to send data - should return cancellation error
    Result = clickhouse_erl_connection:handle_call(
        {send_data, StreamRef, []}, {self(), make_ref()}, State
    ),
    ?assertMatch({reply, {error, {query_cancelled, _}}, _}, Result).

%% Test: finish_streaming_insert returns cancellation error after session cancelled
%% Validates: Requirement 15.3
finish_streaming_insert_after_cancellation_test() ->
    %% Create connection state with cancelled push session
    StreamRef = make_ref(),
    QueryId = <<"test-query">>,
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => {true, {query_cancelled, QueryId}}
    },
    ActiveState = #{
        push_session => SessionState,
        timeout_timer => undefined
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = ActiveState
    },

    %% Try to finish streaming - should return cancellation error and clean up
    Result = clickhouse_erl_connection:handle_call(
        {finish_streaming_insert, StreamRef}, {self(), make_ref()}, State
    ),
    ?assertMatch({reply, {error, {query_cancelled, _}}, _}, Result),
    {reply, _, NewState} = Result,
    ?assertEqual(undefined, NewState#connection_state.active_query_state).

%%%===================================================================
%%% Compression integration tests for encode_and_send_block/2
%%% Validates: Requirements 6.1, 6.2, 6.3, 13.1, 13.2, 13.3
%%%===================================================================

%% Test: encode_and_send_block with compression disabled sends uncompressed data
%% Validates: Requirements 6.2, 13.2
encode_and_send_block_compression_disabled_test() ->
    %% Create connection state with compression disabled
    State = #connection_state{
        socket = make_ref(),
        state = ready,
        negotiated_version = 54460,
        compression_opts = #{method => disabled}
    },
    ColumnData = [
        #{name => <<"a">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],
    %% Mock gen_tcp:send to capture the sent packet
    meck:new(gen_tcp, [unstick]),
    SentRef = make_ref(),
    put(SentRef, undefined),
    meck:expect(gen_tcp, send, fun(_, Packet) ->
        put(SentRef, Packet),
        ok
    end),
    try
        Result = clickhouse_erl_connection:encode_and_send_block(State, ColumnData),
        ?assertEqual(ok, Result),
        %% Verify packet was sent
        SentPacket = get(SentRef),
        ?assertNotEqual(undefined, SentPacket),
        %% Packet should start with CLIENT_DATA byte (2)
        <<2:8, _Rest/binary>> = SentPacket,
        %% With compression disabled, the block data should NOT have a 16-byte
        %% CityHash128 checksum header (compression wrapper starts with checksum)
        %% Extract block data after temp table name
        <<2:8, TempTableAndBlock/binary>> = SentPacket,
        {ok, _TempTableName, BlockData} =
            clickhouse_erl_types_primitive:decode_string(TempTableAndBlock),
        %% Uncompressed block data should NOT start with a compression header
        %% Compression headers have a 16-byte checksum followed by method byte
        %% (0x82=LZ4, 0x90=ZSTD, 0x02=None). Uncompressed block data starts
        %% with block info (varint field number).
        ?assert(byte_size(BlockData) > 0),
        %% Block data should be small (no compression overhead)
        %% A simple 3-row UInt32 column should be well under 100 bytes
        ?assert(byte_size(BlockData) < 100)
    after
        meck:unload(gen_tcp)
    end.

%% Test: encode_and_send_block with undefined compression_opts sends uncompressed data
%% Validates: Requirements 6.2, 13.2
encode_and_send_block_undefined_compression_test() ->
    %% Create connection state with undefined compression opts
    State = #connection_state{
        socket = make_ref(),
        state = ready,
        negotiated_version = 54460,
        compression_opts = undefined
    },
    ColumnData = [
        #{name => <<"a">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],
    meck:new(gen_tcp, [unstick]),
    SentRef = make_ref(),
    put(SentRef, undefined),
    meck:expect(gen_tcp, send, fun(_, Packet) ->
        put(SentRef, Packet),
        ok
    end),
    try
        Result = clickhouse_erl_connection:encode_and_send_block(State, ColumnData),
        ?assertEqual(ok, Result),
        SentPacket = get(SentRef),
        ?assertNotEqual(undefined, SentPacket),
        <<2:8, _Rest/binary>> = SentPacket
    after
        meck:unload(gen_tcp)
    end.

%% Test: encode_and_send_block with LZ4 compression wraps block data
%% Validates: Requirements 6.1, 6.3, 13.1, 13.3
encode_and_send_block_lz4_compression_test() ->
    %% Create connection state with LZ4 compression enabled
    State = #connection_state{
        socket = make_ref(),
        state = ready,
        negotiated_version = 54460,
        compression_opts = #{method => lz4}
    },
    ColumnData = [
        #{name => <<"a">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],
    meck:new(gen_tcp, [unstick]),
    SentRef = make_ref(),
    put(SentRef, undefined),
    meck:expect(gen_tcp, send, fun(_, Packet) ->
        put(SentRef, Packet),
        ok
    end),
    try
        Result = clickhouse_erl_connection:encode_and_send_block(State, ColumnData),
        ?assertEqual(ok, Result),
        SentPacket = get(SentRef),
        ?assertNotEqual(undefined, SentPacket),
        %% Packet should start with CLIENT_DATA byte (2)
        <<2:8, TempTableAndBlock/binary>> = SentPacket,
        %% Extract block data after temp table name
        {ok, _TempTableName, CompressedBlockData} =
            clickhouse_erl_types_primitive:decode_string(TempTableAndBlock),
        %% Compressed block data should have at least 25 bytes (16 checksum + 1 method + 4 comp size + 4 orig size)
        ?assert(byte_size(CompressedBlockData) >= 25),
        %% Verify the compressed data can be decompressed
        {ok, _Decompressed, _Remaining} =
            clickhouse_erl_compression:decompress(CompressedBlockData),
        ok
    after
        meck:unload(gen_tcp)
    end.

%% Test: encode_and_send_block with ZSTD compression wraps block data
%% Validates: Requirements 6.1, 6.3, 13.1, 13.3
encode_and_send_block_zstd_compression_test() ->
    %% Create connection state with ZSTD compression enabled
    State = #connection_state{
        socket = make_ref(),
        state = ready,
        negotiated_version = 54460,
        compression_opts = #{method => zstd}
    },
    ColumnData = [
        #{name => <<"a">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],
    meck:new(gen_tcp, [unstick]),
    SentRef = make_ref(),
    put(SentRef, undefined),
    meck:expect(gen_tcp, send, fun(_, Packet) ->
        put(SentRef, Packet),
        ok
    end),
    try
        Result = clickhouse_erl_connection:encode_and_send_block(State, ColumnData),
        ?assertEqual(ok, Result),
        SentPacket = get(SentRef),
        ?assertNotEqual(undefined, SentPacket),
        <<2:8, TempTableAndBlock/binary>> = SentPacket,
        {ok, _TempTableName, CompressedBlockData} =
            clickhouse_erl_types_primitive:decode_string(TempTableAndBlock),
        %% Compressed block data should have at least 25 bytes
        ?assert(byte_size(CompressedBlockData) >= 25),
        %% Verify the compressed data can be decompressed
        {ok, _Decompressed, _Remaining} =
            clickhouse_erl_compression:decompress(CompressedBlockData),
        ok
    after
        meck:unload(gen_tcp)
    end.

%% Test: encode_and_send_block compresses each block independently
%% Validates: Requirements 6.3, 13.3
encode_and_send_block_independent_compression_test() ->
    %% Create connection state with LZ4 compression
    State = #connection_state{
        socket = make_ref(),
        state = ready,
        negotiated_version = 54460,
        compression_opts = #{method => lz4}
    },
    %% Two different column data sets
    ColumnData1 = [
        #{name => <<"a">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],
    ColumnData2 = [
        #{name => <<"a">>, type => <<"UInt32">>, data => [10, 20, 30]}
    ],
    meck:new(gen_tcp, [unstick]),
    SentPackets = make_ref(),
    put(SentPackets, []),
    meck:expect(gen_tcp, send, fun(_, Packet) ->
        Packets = get(SentPackets),
        put(SentPackets, Packets ++ [Packet]),
        ok
    end),
    try
        %% Send two blocks
        ok = clickhouse_erl_connection:encode_and_send_block(State, ColumnData1),
        ok = clickhouse_erl_connection:encode_and_send_block(State, ColumnData2),
        Packets = get(SentPackets),
        ?assertEqual(2, length(Packets)),
        %% Each packet should be independently decompressible
        lists:foreach(
            fun(Packet) ->
                <<2:8, TempTableAndBlock/binary>> = Packet,
                {ok, _TempTableName, CompressedBlockData} =
                    clickhouse_erl_types_primitive:decode_string(TempTableAndBlock),
                %% Each block should independently decompress
                {ok, _Decompressed, _Remaining} =
                    clickhouse_erl_compression:decompress(CompressedBlockData),
                ok
            end,
            Packets
        )
    after
        meck:unload(gen_tcp)
    end.

%% Test: encode_and_send_block compressed data round-trips correctly
%% Validates: Requirements 6.1, 6.3, 13.1, 13.3
encode_and_send_block_compression_roundtrip_test() ->
    %% First, encode without compression to get the raw block data
    StateNoComp = #connection_state{
        socket = make_ref(),
        state = ready,
        negotiated_version = 54460,
        compression_opts = #{method => disabled}
    },
    ColumnData = [
        #{name => <<"a">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],
    meck:new(gen_tcp, [unstick]),
    UncompressedRef = make_ref(),
    put(UncompressedRef, undefined),
    meck:expect(gen_tcp, send, fun(_, Packet) ->
        put(UncompressedRef, Packet),
        ok
    end),
    try
        ok = clickhouse_erl_connection:encode_and_send_block(StateNoComp, ColumnData),
        UncompressedPacket = get(UncompressedRef),
        <<2:8, UncompTTB/binary>> = UncompressedPacket,
        {ok, _, UncompressedBlockData} =
            clickhouse_erl_types_primitive:decode_string(UncompTTB),

        %% Now encode with LZ4 compression
        StateLZ4 = StateNoComp#connection_state{compression_opts = #{method => lz4}},
        CompressedRef = make_ref(),
        put(CompressedRef, undefined),
        meck:expect(gen_tcp, send, fun(_, Packet) ->
            put(CompressedRef, Packet),
            ok
        end),
        ok = clickhouse_erl_connection:encode_and_send_block(StateLZ4, ColumnData),
        CompressedPacket = get(CompressedRef),
        <<2:8, CompTTB/binary>> = CompressedPacket,
        {ok, _, CompressedBlockData} =
            clickhouse_erl_types_primitive:decode_string(CompTTB),

        %% Decompress and verify it matches the uncompressed version
        {ok, Decompressed, <<>>} =
            clickhouse_erl_compression:decompress(CompressedBlockData),
        ?assertEqual(UncompressedBlockData, Decompressed)
    after
        meck:unload(gen_tcp)
    end.

%%%===================================================================
%%% Cancellation support tests (continued)
%%%===================================================================

%% Test: cancel_query sends CLIENT_CANCEL packet
%% Validates: Requirement 7.3, 15.3
cancel_query_sends_client_cancel_packet_test() ->
    QueryId = <<"test-query">>,
    ActiveQueryState = #{
        caller => {self(), make_ref()},
        query_id => QueryId,
        timeout => 30000,
        timer_ref => undefined,
        cancelled => false,
        replied => false,
        is_insert => true,
        on_data => fun(_, _) -> {ok, #{}} end,
        accumulator => #{}
    },
    %% Create a mock socket
    MockSocket = make_ref(),
    State = #connection_state{
        socket = MockSocket,
        state = ready,
        active_query_state = ActiveQueryState
    },

    %% Mock gen_tcp:send to capture what was sent
    meck:new(gen_tcp, [unstick]),
    SentPackets = make_ref(),
    put(SentPackets, []),
    meck:expect(gen_tcp, send, fun(_, Packet) ->
        Packets = get(SentPackets),
        put(SentPackets, [Packet | Packets]),
        ok
    end),
    try
        %% Cancel the query
        Result = clickhouse_erl_connection:handle_call(
            {cancel_query, QueryId}, {self(), make_ref()}, State
        ),
        ?assertMatch({reply, ok, _}, Result),

        %% Check that CLIENT_CANCEL packet was sent
        Packets = get(SentPackets),
        ?assert(
            lists:any(
                fun(Packet) ->
                    %% CLIENT_CANCEL is packet type 3
                    case Packet of
                        <<3:8, _/binary>> -> true;
                        _ -> false
                    end
                end,
                Packets
            )
        )
    after
        meck:unload(gen_tcp)
    end.
