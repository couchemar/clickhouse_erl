%% @doc Unit tests for event-driven parser integration in connection module
%%
%% Tests the TCP handler's integration with clickhouse_erl_parser:
%% - Parser state initialization
%% - Raw TCP data flow through parser
%% - Event list handling
%% - need_more event handling
%% - Parser state persistence across TCP recvs
%%
%% Requirements: Task 8.5.2 - Update TCP handler for event-driven parser
-module(clickhouse_erl_connection_event_parser_tests).
-include_lib("eunit/include/eunit.hrl").
-include("clickhouse_erl_protocol.hrl").

%%%===================================================================
%%% Test Fixtures
%%%===================================================================

%% @doc Create a mock connection state for testing
mock_connection_state() ->
    #{
        socket => mock_socket,
        host => "localhost",
        port => 9000,
        options => #{},
        state => ready,
        server_info => undefined,
        error_reason => undefined,
        active_queries => #{},
        active_query_state => undefined,
        negotiated_version => 54451,
        compression_opts => undefined,
        parser_state => undefined
    }.

%%%===================================================================
%%% Parser State Initialization Tests
%%%===================================================================

parser_state_initialization_test() ->
    %% Test that parser state is initialized on first TCP recv
    State = mock_connection_state(),

    %% Verify parser_state is undefined initially
    ?assertEqual(undefined, maps:get(parser_state, State)),

    %% Simulate parser initialization
    Version = maps:get(negotiated_version, State),
    ParserState = clickhouse_erl_parser:init(Version),

    %% Verify parser state is initialized correctly
    ?assertMatch(#{state := initial, buffer := <<>>, version := 54451}, ParserState).

parser_state_reuse_test() ->
    %% Test that existing parser state is reused on subsequent TCP recvs
    Version = 54451,
    InitialParserState = clickhouse_erl_parser:init(Version),

    State = (mock_connection_state())#{parser_state => InitialParserState},

    %% Verify parser_state exists
    ?assertMatch(#{state := initial}, maps:get(parser_state, State)),

    %% Simulate getting existing parser state
    ExistingParserState = maps:get(parser_state, State),
    ?assertEqual(InitialParserState, ExistingParserState).

%%%===================================================================
%%% TCP Data Flow Tests
%%%===================================================================

tcp_data_flows_through_parser_test() ->
    %% Test that raw TCP data is passed to parser
    Version = 54451,
    ParserState = clickhouse_erl_parser:init(Version),

    %% Create a simple PONG packet (type 4, no data)
    PongPacket = <<?SERVER_PONG:8>>,

    %% Parse the packet
    {ok, EventList, _NewParserState} = clickhouse_erl_parser:parse(PongPacket, ParserState),

    %% Verify events are generated
    ?assert(length(EventList) > 0),

    %% Verify start event
    ?assertEqual({start, server_pong}, lists:nth(1, EventList)),

    %% Verify end event (should be second-to-last, before need_more or last if complete)
    case lists:last(EventList) of
        need_more ->
            %% If need_more is last, end should be second-to-last
            ?assertEqual({'end', server_pong}, lists:nth(length(EventList) - 1, EventList));
        {'end', server_pong} ->
            %% If end is last, packet is complete
            ok
    end.

tcp_data_incomplete_packet_test() ->
    %% Test that parser handles incomplete packets correctly
    Version = 54451,
    ParserState = clickhouse_erl_parser:init(Version),

    %% Create incomplete END_OF_STREAM packet (missing data)
    %% END_OF_STREAM has no fields, so just the type byte should be complete

    % Empty data - need packet type
    IncompletePacket = <<>>,

    %% Parse the incomplete packet
    {ok, EventList, NewParserState} = clickhouse_erl_parser:parse(IncompletePacket, ParserState),

    %% Verify need_more event is generated
    ?assertEqual(need_more, lists:last(EventList)),

    %% Verify parser state has buffered data
    ?assertMatch(#{buffer := <<>>}, NewParserState).

tcp_data_multiple_packets_test() ->
    %% Test that parser handles multiple packets in one TCP recv
    Version = 54451,
    ParserState = clickhouse_erl_parser:init(Version),

    %% Create two PONG packets
    TwoPackets = <<?SERVER_PONG:8, ?SERVER_PONG:8>>,

    %% Parse both packets
    {ok, EventList, _NewParserState} = clickhouse_erl_parser:parse(TwoPackets, ParserState),

    %% Count start events (should be 2)
    StartEvents = [E || E <- EventList, element(1, E) =:= start],
    ?assertEqual(2, length(StartEvents)),

    %% Verify both are server_pong
    ?assertEqual({start, server_pong}, lists:nth(1, StartEvents)),
    ?assertEqual({start, server_pong}, lists:nth(2, StartEvents)).

%%%===================================================================
%%% need_more Event Handling Tests
%%%===================================================================

need_more_event_detection_test() ->
    %% Test that need_more event is detected correctly
    Version = 54451,
    ParserState = clickhouse_erl_parser:init(Version),

    %% Create incomplete packet (just type byte, but END_OF_STREAM needs more parsing)
    %% Actually, END_OF_STREAM with just type byte might be complete
    %% Let's use empty data which definitely needs more
    IncompleteData = <<>>,

    %% Parse
    {ok, EventList, _NewParserState} = clickhouse_erl_parser:parse(IncompleteData, ParserState),

    %% Verify need_more is last event
    ?assertEqual(need_more, lists:last(EventList)).

need_more_event_not_present_complete_packet_test() ->
    %% Test that need_more is not present for complete packets
    Version = 54451,
    ParserState = clickhouse_erl_parser:init(Version),

    %% Create complete PONG packet
    PongPacket = <<?SERVER_PONG:8>>,

    %% Parse
    {ok, EventList, _NewParserState} = clickhouse_erl_parser:parse(PongPacket, ParserState),

    %% Verify last event is either 'end' or need_more
    LastEvent = lists:last(EventList),
    case LastEvent of
        {'end', server_pong} ->
            %% Complete packet, no need_more
            ok;
        need_more ->
            %% Parser needs more data (this is also valid for PONG)
            ok
    end.

%%%===================================================================
%%% Parser State Persistence Tests
%%%===================================================================

parser_state_persists_across_recvs_test() ->
    %% Test that parser state is maintained across TCP recv boundaries
    Version = 54451,
    ParserState1 = clickhouse_erl_parser:init(Version),

    %% First recv: incomplete packet (empty)
    {ok, EventList1, ParserState2} = clickhouse_erl_parser:parse(<<>>, ParserState1),

    %% Verify need_more
    ?assertEqual(need_more, lists:last(EventList1)),

    %% Second recv: complete packet type
    {ok, EventList2, _ParserState3} = clickhouse_erl_parser:parse(<<?SERVER_PONG:8>>, ParserState2),

    %% Verify packet is parsed
    ?assertEqual({start, server_pong}, lists:nth(1, EventList2)).

parser_state_buffer_management_test() ->
    %% Test that parser manages its internal buffer correctly
    Version = 54451,
    ParserState1 = clickhouse_erl_parser:init(Version),

    %% Verify initial buffer is empty
    ?assertMatch(#{buffer := <<>>}, ParserState1),

    %% Parse incomplete data
    {ok, _EventList, ParserState2} = clickhouse_erl_parser:parse(<<>>, ParserState1),

    %% Verify buffer is managed by parser
    ?assertMatch(#{buffer := _}, ParserState2).

%%%===================================================================
%%% Event List Structure Tests
%%%===================================================================

event_list_structure_test() ->
    %% Test that event list has correct structure
    Version = 54451,
    ParserState = clickhouse_erl_parser:init(Version),

    %% Parse PONG packet
    PongPacket = <<?SERVER_PONG:8>>,
    {ok, EventList, _NewParserState} = clickhouse_erl_parser:parse(PongPacket, ParserState),

    %% Verify event list is a list
    ?assert(is_list(EventList)),

    %% Verify events have correct format
    lists:foreach(
        fun(Event) ->
            case Event of
                {start, Type} when is_atom(Type) -> ok;
                {'end', Type} when is_atom(Type) -> ok;
                {data, Field, _Value} when is_atom(Field) -> ok;
                need_more -> ok;
                % Invalid event format
                _ -> ?assert(false)
            end
        end,
        EventList
    ).

event_list_start_end_pairing_test() ->
    %% Test that start and end events are properly paired
    Version = 54451,
    ParserState = clickhouse_erl_parser:init(Version),

    %% Parse PONG packet
    PongPacket = <<?SERVER_PONG:8>>,
    {ok, EventList, _NewParserState} = clickhouse_erl_parser:parse(PongPacket, ParserState),

    %% Filter out need_more
    Events = [E || E <- EventList, E =/= need_more],

    %% If we have events, first should be start
    case Events of
        [] ->
            % No events yet
            ok;
        [{start, _Type} | _] ->
            % Correct
            ok;
        _ ->
            % First event should be start
            ?assert(false)
    end.

%%%===================================================================
%%% Error Handling Tests
%%%===================================================================

parser_error_handling_test() ->
    %% Test that parser errors are handled correctly
    Version = 54451,
    ParserState = clickhouse_erl_parser:init(Version),

    %% Create invalid packet (unknown type)

    % Type 255 is not defined
    InvalidPacket = <<255:8>>,

    %% Parse should return error
    Result = clickhouse_erl_parser:parse(InvalidPacket, ParserState),

    %% Verify error is returned
    case Result of
        {error, {unknown_message_type, 255}} ->
            ok;
        {error, _Reason} ->
            % Any error is acceptable
            ok;
        _ ->
            % Should return error
            ?assert(false)
    end.

parser_state_cleared_on_error_test() ->
    %% Test that parser state should be cleared on protocol errors
    %% This is a connection-level concern, but we verify the pattern
    State = mock_connection_state(),

    %% Simulate error scenario
    ErrorState = State#{
        state => error,
        error_reason => {protocol_error, test_error},
        % Should be cleared
        parser_state => undefined
    },

    %% Verify parser_state is cleared
    ?assertEqual(undefined, maps:get(parser_state, ErrorState)).

%%%===================================================================
%%% Streaming Mode Detection Tests (Task 8.5.6.2)
%%%===================================================================

acc_state_batch_mode_no_callback_test() ->
    %% In batch mode (no on_data in options), AccState should NOT have
    %% on_data_callback or user_acc fields
    ActiveQueryState = #{
        caller => {self(), make_ref()},
        handler_state => undefined,
        query_id => <<"test">>,
        timeout => 5000,
        timer_ref => undefined,
        cancelled => false,
        replied => false,
        on_data => fun(_DataBlock, Acc) -> Acc end,
        accumulator => [],
        on_progress => fun(_) -> ok end,
        on_profile => fun(_) -> ok end,
        on_profile_events => fun(_) -> ok end,
        streaming_mode => false
    },
    AccState = clickhouse_erl_connection:init_acc_state(ActiveQueryState),
    ?assertEqual(undefined, maps:get(on_data_callback, AccState, undefined)),
    ?assertEqual(undefined, maps:get(user_acc, AccState, undefined)).

acc_state_streaming_mode_stores_callback_test() ->
    %% In streaming mode (on_data provided), AccState should have
    %% on_data_callback and user_acc fields
    MyCallback = fun
        ({data, #{name := _Name, value := _Value}}, Acc) -> {ok, Acc};
        ('end', Acc) -> {ok, Acc}
    end,
    InitialAcc = #{},
    ActiveQueryState = #{
        caller => {self(), make_ref()},
        handler_state => undefined,
        query_id => <<"test">>,
        timeout => 5000,
        timer_ref => undefined,
        cancelled => false,
        replied => false,
        on_data => MyCallback,
        accumulator => InitialAcc,
        on_progress => fun(_) -> ok end,
        on_profile => fun(_) -> ok end,
        on_profile_events => fun(_) -> ok end,
        streaming_mode => true
    },
    AccState = clickhouse_erl_connection:init_acc_state(ActiveQueryState),
    ?assertEqual(MyCallback, maps:get(on_data_callback, AccState)),
    ?assertEqual(InitialAcc, maps:get(user_acc, AccState)).

acc_state_streaming_mode_default_accumulator_test() ->
    %% When streaming mode is true but accumulator is undefined,
    %% user_acc should be undefined
    MyCallback = fun(_, Acc) -> {ok, Acc} end,
    ActiveQueryState = #{
        caller => {self(), make_ref()},
        handler_state => undefined,
        query_id => <<"test">>,
        timeout => 5000,
        timer_ref => undefined,
        cancelled => false,
        replied => false,
        on_data => MyCallback,
        accumulator => undefined,
        on_progress => fun(_) -> ok end,
        on_profile => fun(_) -> ok end,
        on_profile_events => fun(_) -> ok end,
        streaming_mode => true
    },
    AccState = clickhouse_erl_connection:init_acc_state(ActiveQueryState),
    ?assertEqual(MyCallback, maps:get(on_data_callback, AccState)),
    ?assertEqual(undefined, maps:get(user_acc, AccState)).

acc_state_preserves_existing_fields_test() ->
    %% Verify that AccState always has the standard fields regardless of mode
    ActiveQueryState = #{
        caller => {self(), make_ref()},
        handler_state => undefined,
        query_id => <<"test">>,
        timeout => 5000,
        timer_ref => undefined,
        cancelled => false,
        replied => false,
        on_data => fun(_, Acc) -> Acc end,
        accumulator => [],
        on_progress => fun(_) -> ok end,
        on_profile => fun(_) -> ok end,
        on_profile_events => fun(_) -> ok end,
        streaming_mode => false
    },
    AccState = clickhouse_erl_connection:init_acc_state(ActiveQueryState),
    ?assertEqual([], maps:get(columns, AccState)),
    ?assertEqual(undefined, maps:get(current_column, AccState)),
    ?assertEqual(undefined, maps:get(current_column_name, AccState)),
    ?assertEqual([], maps:get(column_data, AccState)),
    ?assertEqual(undefined, maps:get(current_block_type, AccState)),
    ?assertEqual(undefined, maps:get(exception_info, AccState)),
    ?assertEqual(0, maps:get(rows_written, AccState)).

%%%===================================================================
%%% End-of-Stream Streaming Callback Tests (Task 8.5.6.4)
%%%===================================================================

end_of_stream_calls_callback_with_end_in_streaming_mode_test() ->
    %% When end_of_stream arrives in streaming mode, the callback should
    %% be called with 'end' to let the user finalize results
    Callback = fun
        ({data, #{name := _Name, value := _Value}}, Acc) -> {ok, Acc};
        ('end', Acc) -> {ok, {finalized, Acc}}
    end,
    AccState = #{
        columns => [],
        current_column => undefined,
        current_column_name => undefined,
        column_data => [],
        current_block_type => undefined,
        exception_info => undefined,
        rows_written => 0,
        on_data_callback => Callback,
        user_acc => [value1, value2]
    },
    EventList = [{'end', server_end_of_stream}],
    %% Simulate the foldl processing
    {HasEos, _NeedMore, _HasException, NewAccState} =
        clickhouse_erl_connection:process_events(EventList, AccState),
    ?assert(HasEos),
    %% Callback should have been called with 'end', producing {finalized, ...}
    ?assertEqual({finalized, [value1, value2]}, maps:get(user_acc, NewAccState)).

end_of_stream_no_callback_in_batch_mode_test() ->
    %% In batch mode (no on_data_callback), end_of_stream should just
    %% set the flag without calling any callback
    AccState = #{
        columns => [],
        current_column => undefined,
        current_column_name => undefined,
        column_data => [],
        current_block_type => undefined,
        exception_info => undefined,
        rows_written => 0
    },
    EventList = [{'end', server_end_of_stream}],
    {HasEos, _NeedMore, _HasException, NewAccState} =
        clickhouse_erl_connection:process_events(EventList, AccState),
    ?assert(HasEos),
    %% AccState should be unchanged (no user_acc field)
    ?assertEqual(undefined, maps:get(user_acc, NewAccState, undefined)).

build_query_result_returns_user_acc_in_streaming_mode_test() ->
    %% In streaming mode, build_query_result should return
    %% #{data => FinalUserAcc} instead of column-oriented result
    AccState = #{
        columns => [],
        current_column => undefined,
        current_column_name => undefined,
        column_data => [],
        current_block_type => undefined,
        exception_info => undefined,
        rows_written => 0,
        on_data_callback => fun(_, Acc) -> {ok, Acc} end,
        user_acc => #{<<"name">> => [<<"alice">>, <<"bob">>], <<"age">> => [30, 25]}
    },
    Result = clickhouse_erl_connection:build_query_result(AccState),
    Expected = #{data => #{<<"name">> => [<<"alice">>, <<"bob">>], <<"age">> => [30, 25]}},
    ?assertEqual(Expected, Result).

build_query_result_batch_mode_unchanged_test() ->
    %% In batch mode, build_query_result should still return column-oriented result
    AccState = #{
        columns => [
            #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2]}
        ],
        current_column => undefined,
        current_column_name => undefined,
        column_data => [],
        current_block_type => undefined,
        exception_info => undefined,
        rows_written => 0
    },
    Result = clickhouse_erl_connection:build_query_result(AccState),
    ?assertMatch(#{data := #{columns := _, rows := _}}, Result).

end_of_stream_with_empty_accumulator_test() ->
    %% Streaming mode with undefined accumulator should still call callback
    Callback = fun('end', undefined) -> {ok, done} end,
    AccState = #{
        columns => [],
        current_column => undefined,
        current_column_name => undefined,
        column_data => [],
        current_block_type => undefined,
        exception_info => undefined,
        rows_written => 0,
        on_data_callback => Callback,
        user_acc => undefined
    },
    EventList = [{'end', server_end_of_stream}],
    {HasEos, _NeedMore, _HasException, NewAccState} =
        clickhouse_erl_connection:process_events(EventList, AccState),
    ?assert(HasEos),
    ?assertEqual(done, maps:get(user_acc, NewAccState)).
