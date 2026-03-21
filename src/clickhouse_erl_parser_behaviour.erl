%% @doc Behaviour for event-driven packet parsers.
%%
%% Each parser module handles a specific ClickHouse server packet type.
%% The parser emits events as it processes binary data, enabling streaming
%% without buffering entire packets.
-module(clickhouse_erl_parser_behaviour).

-type parser_state() :: map().
-type event() :: {start, atom()} | {'end', atom()} | {data, atom(), term()} | need_more.
-type parse_result() ::
    {done, [event()], Rest :: binary()}
    | {more, [event()], Rest :: binary(), parser_state()}
    | {error, term()}.

-export_type([parser_state/0, event/0, parse_result/0]).

-callback init(ParentState :: map()) -> parser_state().
-callback parse(Data :: binary(), State :: parser_state()) -> parse_result().
