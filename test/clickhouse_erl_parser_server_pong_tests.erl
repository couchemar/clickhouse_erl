-module(clickhouse_erl_parser_server_pong_tests).
-include_lib("eunit/include/eunit.hrl").

%% @doc Test that PONG parser initializes correctly
init_test() ->
    State = clickhouse_erl_parser_server_pong:init(#{}),
    ?assertEqual(#{}, State).

%% @doc Test that PONG parser returns done immediately with no events
parse_empty_payload_test() ->
    State = #{},
    Data = <<>>,
    Result = clickhouse_erl_parser_server_pong:parse(Data, State),
    ?assertEqual({done, [], <<>>}, Result).

%% @doc Test that PONG parser returns done with remainder data
parse_with_remainder_test() ->
    State = #{},
    Data = <<1, 2, 3, 4>>,
    Result = clickhouse_erl_parser_server_pong:parse(Data, State),
    ?assertEqual({done, [], <<1, 2, 3, 4>>}, Result).
