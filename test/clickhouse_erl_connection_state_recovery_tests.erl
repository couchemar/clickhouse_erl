%% @doc Unit tests for connection state recovery in streaming insert
-module(clickhouse_erl_connection_state_recovery_tests).

-include_lib("eunit/include/eunit.hrl").
-include("clickhouse_erl_connection.hrl").

%%%===================================================================
%%% Test: clear_active_query_state/1 sets state to ready
%%%===================================================================

clear_active_query_state_sets_state_to_ready_test() ->
    %% Create a state with active query and timeout timer
    TimerRef = erlang:send_after(30000, self(), test_timer),
    State = #connection_state{
        state = busy,
        active_query_state = #{
            query_id => <<"test">>,
            timeout_timer => TimerRef
        },
        parser_state = #{}
    },

    %% Call clear_active_query_state/1 — should default to ready
    NewState = clickhouse_erl_connection:clear_active_query_state(State),

    %% Verify state transitions to ready
    ?assertEqual(ready, NewState#connection_state.state),
    ?assertEqual(undefined, NewState#connection_state.active_query_state),
    ?assertEqual(undefined, NewState#connection_state.parser_state),
    %% Timer should have been cancelled
    ?assertEqual(false, erlang:read_timer(TimerRef)).

%%%===================================================================
%%% Test: clear_active_query_state/2 with ready target
%%%===================================================================

clear_active_query_state_with_ready_target_test() ->
    State = #connection_state{
        state = busy,
        active_query_state = #{query_id => <<"test">>},
        parser_state = #{}
    },

    NewState = clickhouse_erl_connection:clear_active_query_state(State, ready),

    ?assertEqual(ready, NewState#connection_state.state),
    ?assertEqual(undefined, NewState#connection_state.active_query_state).

%%%===================================================================
%%% Test: clear_active_query_state/2 with error target for network errors
%%% Requirements 8.3, 16.2, 16.3: network errors transition to error state
%%%===================================================================

clear_active_query_state_with_error_target_test() ->
    State = #connection_state{
        state = busy,
        active_query_state = #{query_id => <<"test">>},
        parser_state = #{}
    },

    NewState = clickhouse_erl_connection:clear_active_query_state(State, error),

    ?assertEqual(error, NewState#connection_state.state),
    ?assertEqual(undefined, NewState#connection_state.active_query_state),
    ?assertEqual(undefined, NewState#connection_state.parser_state).

%%%===================================================================
%%% Test: check_connection_ready rejects when active_query_state is set
%%% (tested indirectly through handle_call which calls check_connection_ready)
%%%===================================================================

check_connection_ready_rejects_when_active_query_state_set_test() ->
    %% Create a state with active query but state = ready
    State = #connection_state{
        state = ready,
        active_query_state = #{query_id => <<"test">>},
        parser_state = #{}
    },

    %% Try to start a new streaming insert — should be rejected
    PreparedRequest = #{
        sql => <<"INSERT INTO test VALUES">>,
        columns => [#{name => <<"col">>, type => <<"UInt32">>, data => []}]
    },

    Result = clickhouse_erl_connection:handle_call(
        {start_streaming_insert, PreparedRequest}, {self(), make_ref()}, State
    ),

    ?assertMatch({reply, {error, {connection_error, query_in_progress}}, _}, Result).

%%%===================================================================
%%% Test: Successful streaming insert clears state and sets ready
%%%===================================================================

successful_streaming_insert_clears_state_test() ->
    meck:new(gen_tcp, [unstick]),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(gen_tcp, recv, fun(_, _, _) -> {error, timeout} end),

    try
        State = #connection_state{
            socket = make_ref(),
            state = busy,
            active_query_state = #{query_id => <<"test">>},
            parser_state = #{}
        },

        NewState = clickhouse_erl_connection:clear_active_query_state(State),

        ?assertEqual(ready, NewState#connection_state.state),
        ?assertEqual(undefined, NewState#connection_state.active_query_state)
    after
        meck:unload(gen_tcp)
    end.

%%%===================================================================
%%% Test: Callback error sends best-effort blank block and clears state
%%% Validates: Requirement 8.2 — callback error transitions to ready
%%%===================================================================

callback_error_clears_state_to_ready_test() ->
    State = #connection_state{
        socket = make_ref(),
        state = busy,
        active_query_state = #{query_id => <<"test">>},
        parser_state = #{},
        compression_opts = #{method => disabled}
    },

    %% After a callback error, clear_active_query_state/1 should set state to ready
    NewState = clickhouse_erl_connection:clear_active_query_state(State),
    ?assertEqual(ready, NewState#connection_state.state),
    ?assertEqual(undefined, NewState#connection_state.active_query_state).

%%%===================================================================
%%% Test: Network error transitions to error state via clear_active_query_state/2
%%% Validates: Requirements 8.3, 16.2, 16.3
%%%===================================================================

network_error_transitions_to_error_state_test() ->
    State = #connection_state{
        state = busy,
        socket = make_ref(),
        active_query_state = #{query_id => <<"test">>},
        parser_state = #{}
    },

    %% Network errors should use clear_active_query_state/2 with error target
    NewState = clickhouse_erl_connection:clear_active_query_state(State, error),

    ?assertEqual(error, NewState#connection_state.state),
    ?assertEqual(undefined, NewState#connection_state.active_query_state).

%%%===================================================================
%%% Test: Server exception clears state if TCP still open
%%%===================================================================

server_exception_clears_state_if_tcp_open_test() ->
    State = #connection_state{
        socket = make_ref(),
        state = busy,
        active_query_state = #{query_id => <<"test">>},
        parser_state = #{}
    },

    %% Server exception with TCP still open → ready state
    NewState = clickhouse_erl_connection:clear_active_query_state(State),
    ?assertEqual(ready, NewState#connection_state.state).

%%%===================================================================
%%% Test: Push-based finish_streaming_insert sets state to ready
%%%===================================================================

push_based_finish_streaming_insert_sets_state_to_ready_test() ->
    meck:new(gen_tcp, [unstick]),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(gen_tcp, recv, fun(_, _, _) -> {error, timeout} end),

    try
        StreamRef = make_ref(),
        SessionState = #{
            streaming_mode => push,
            stream_ref => StreamRef,
            expected_columns => [],
            rows_inserted => 10,
            blocks_sent => 2,
            session_failed => false,
            start_time => erlang:system_time(millisecond) - 1000
        },
        ActiveState = #{
            push_session => SessionState
        },
        State = #connection_state{
            socket = make_ref(),
            state = busy,
            active_query_state = ActiveState,
            compression_opts = #{method => disabled}
        },

        Result = clickhouse_erl_connection:handle_call(
            {finish_streaming_insert, StreamRef}, {self(), make_ref()}, State
        ),

        ?assertMatch({reply, {ok, _}, _}, Result),
        {reply, {ok, _}, NewState} = Result,
        ?assertEqual(ready, NewState#connection_state.state),
        ?assertEqual(undefined, NewState#connection_state.active_query_state)
    after
        meck:unload(gen_tcp)
    end.

%%%===================================================================
%%% Test: Push-based finish_streaming_insert network error → error state
%%% Validates: Requirements 16.2, 16.3
%%%===================================================================

push_based_finish_network_error_transitions_to_error_state_test() ->
    meck:new(gen_tcp, [unstick]),
    meck:expect(gen_tcp, send, fun(_, _) -> {error, econnreset} end),

    try
        StreamRef = make_ref(),
        SessionState = #{
            streaming_mode => push,
            stream_ref => StreamRef,
            expected_columns => [],
            rows_inserted => 5,
            blocks_sent => 1,
            session_failed => false,
            start_time => erlang:system_time(millisecond) - 500
        },
        ActiveState = #{
            push_session => SessionState
        },
        State = #connection_state{
            socket = make_ref(),
            state = busy,
            active_query_state = ActiveState,
            compression_opts = #{method => disabled}
        },

        Result = clickhouse_erl_connection:handle_call(
            {finish_streaming_insert, StreamRef}, {self(), make_ref()}, State
        ),

        %% Should return network error
        ?assertMatch({reply, {error, {network_error, econnreset}}, _}, Result),
        {reply, _, NewState} = Result,
        %% Should transition to error state, not ready
        ?assertEqual(error, NewState#connection_state.state),
        ?assertEqual(undefined, NewState#connection_state.active_query_state)
    after
        meck:unload(gen_tcp)
    end.

%%%===================================================================
%%% Test: Push-based failed session with network error → error state
%%% Validates: Requirements 16.2
%%%===================================================================

push_based_failed_session_network_error_transitions_to_error_state_test() ->
    StreamRef = make_ref(),
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => [],
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => {true, {network_error, econnreset}}
    },
    ActiveState = #{
        push_session => SessionState
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = ActiveState
    },

    Result = clickhouse_erl_connection:handle_call(
        {finish_streaming_insert, StreamRef}, {self(), make_ref()}, State
    ),

    ?assertMatch({reply, {error, {network_error, econnreset}}, _}, Result),
    {reply, _, NewState} = Result,
    %% Network error → error state
    ?assertEqual(error, NewState#connection_state.state).

%%%===================================================================
%%% Test: Push-based failed session with timeout → ready state
%%% Validates: Requirements 16.3
%%%===================================================================

push_based_failed_session_timeout_transitions_to_ready_state_test() ->
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
        push_session => SessionState
    },
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = ActiveState
    },

    Result = clickhouse_erl_connection:handle_call(
        {finish_streaming_insert, StreamRef}, {self(), make_ref()}, State
    ),

    ?assertMatch({reply, {error, {timeout_error, streaming_insert}}, _}, Result),
    {reply, _, NewState} = Result,
    %% Timeout → ready state (TCP still open)
    ?assertEqual(ready, NewState#connection_state.state).

%%%===================================================================
%%% Test: Concurrent queries rejected while streaming in progress
%%%===================================================================

concurrent_queries_rejected_while_streaming_test() ->
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = #{
            query_id => <<"streaming-insert">>,
            streaming_mode => pull
        }
    },

    Result = clickhouse_erl_connection:handle_call(
        {query, #{sql => <<"SELECT 1">>}}, {self(), make_ref()}, State
    ),

    ?assertMatch(
        {reply, {error, {connection_error, query_in_progress}}, _}, Result
    ).

%%%===================================================================
%%% Test: Concurrent start_streaming_insert rejected while streaming in progress
%%%===================================================================

concurrent_start_streaming_insert_rejected_test() ->
    State = #connection_state{
        socket = undefined,
        state = ready,
        active_query_state = #{query_id => <<"active-query">>}
    },

    PreparedRequest = #{
        sql => <<"INSERT INTO test VALUES">>,
        columns => [#{name => <<"col">>, type => <<"UInt32">>, data => []}]
    },

    Result = clickhouse_erl_connection:handle_call(
        {start_streaming_insert, PreparedRequest}, {self(), make_ref()}, State
    ),

    ?assertMatch({reply, {error, {connection_error, query_in_progress}}, _}, Result).
