%% @doc Unit tests for clickhouse_erl_parser_server_end_of_stream module.
%%
%% Tests end_of_stream packet parsing with synthetic data (no live ClickHouse connection).
-module(clickhouse_erl_parser_server_end_of_stream_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Unit Tests
%%%===================================================================

parse_empty_packet_test() ->
    %% END_OF_STREAM has no payload
    State = clickhouse_erl_parser_server_end_of_stream:init(#{}),
    Result = clickhouse_erl_parser_server_end_of_stream:parse(<<>>, State),

    ?assertMatch({done, [], <<>>}, Result).

parse_with_remainder_test() ->
    %% END_OF_STREAM should pass through all data as remainder
    Remainder = <<"next_packet_data">>,

    State = clickhouse_erl_parser_server_end_of_stream:init(#{}),
    Result = clickhouse_erl_parser_server_end_of_stream:parse(Remainder, State),

    ?assertMatch({done, [], <<"next_packet_data">>}, Result).

parse_no_events_test() ->
    %% END_OF_STREAM should never emit events
    State = clickhouse_erl_parser_server_end_of_stream:init(#{}),
    Result = clickhouse_erl_parser_server_end_of_stream:parse(<<"any_data">>, State),

    {done, Events, _} = Result,
    ?assertEqual([], Events).

parse_multiple_calls_test() ->
    %% Multiple calls should all return done immediately
    State = clickhouse_erl_parser_server_end_of_stream:init(#{}),

    Result1 = clickhouse_erl_parser_server_end_of_stream:parse(<<1, 2, 3>>, State),
    ?assertMatch({done, [], <<1, 2, 3>>}, Result1),

    Result2 = clickhouse_erl_parser_server_end_of_stream:parse(<<4, 5, 6>>, State),
    ?assertMatch({done, [], <<4, 5, 6>>}, Result2).

init_returns_empty_state_test() ->
    %% init should return empty map
    State = clickhouse_erl_parser_server_end_of_stream:init(#{}),
    ?assertEqual(#{}, State).

init_ignores_input_test() ->
    %% init should ignore any input state
    State1 = clickhouse_erl_parser_server_end_of_stream:init(#{foo => bar}),
    ?assertEqual(#{}, State1),

    State2 = clickhouse_erl_parser_server_end_of_stream:init(#{version => 54460}),
    ?assertEqual(#{}, State2).
