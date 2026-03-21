-module(clickhouse_erl_parser_pong_integration_tests).
-include_lib("eunit/include/eunit.hrl").
-include("clickhouse_erl_protocol.hrl").

%% @doc Test that parser correctly handles PONG packet
parse_pong_packet_test() ->
    Version = ?PROTOCOL_VERSION,
    State = clickhouse_erl_parser:init(Version),

    %% PONG packet is just type byte 4
    Data = <<?SERVER_PONG:8>>,

    {ok, Events, _NewState} = clickhouse_erl_parser:parse(Data, State),

    %% Should get start and end events with no data events, followed by need_more
    ?assertEqual([{start, server_pong}, {'end', server_pong}, need_more], Events).

%% @doc Test that parser correctly handles PONG packet with remainder
parse_pong_with_remainder_test() ->
    Version = ?PROTOCOL_VERSION,
    State = clickhouse_erl_parser:init(Version),

    %% PONG packet followed by another packet type
    Data = <<?SERVER_PONG:8, ?SERVER_END_OF_STREAM:8>>,

    {ok, Events, _State1} = clickhouse_erl_parser:parse(Data, State),

    %% Should get both PONG and END_OF_STREAM events in one parse call
    ?assertEqual(
        [
            {start, server_pong},
            {'end', server_pong},
            {start, server_end_of_stream},
            {'end', server_end_of_stream},
            need_more
        ],
        Events
    ).

%% @doc Test that parser correctly handles incomplete PONG packet (just need_more)
parse_incomplete_pong_test() ->
    Version = ?PROTOCOL_VERSION,
    State = clickhouse_erl_parser:init(Version),

    %% Empty data - need more
    Data = <<>>,

    {ok, Events, _NewState} = clickhouse_erl_parser:parse(Data, State),

    %% Should get need_more
    ?assertEqual([need_more], Events).
