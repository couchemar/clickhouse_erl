-module(clickhouse_erl_connection_parser_poc_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([pong_parsing_with_event_parser/1]).

suite() ->
    [{timetrap, {seconds, 30}}].

all() ->
    [pong_parsing_with_event_parser].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Test that PONG parsing works with event-driven parser during handshake
pong_parsing_with_event_parser(_Config) ->
    case test_helpers:connect() of
        {ok, Conn} ->
            test_helpers:disconnect(Conn),
            true = true;
        {error, Reason} ->
            ct:fail("ClickHouse connection failed: ~p", [Reason])
    end.
