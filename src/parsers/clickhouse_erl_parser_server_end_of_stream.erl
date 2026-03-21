%% @doc Parser for SERVER_END_OF_STREAM (5) packets.
%%
%% The END_OF_STREAM packet marks the end of query results.
%% It has no payload - just the packet type byte.
%% This parser immediately returns done with no events.
%%
%% Emitted events: None (empty list)
%%
%% This packet is used to signal that all DATA, TOTALS, and EXTREMES packets
%% have been sent and no more result data will follow.
-module(clickhouse_erl_parser_server_end_of_stream).
-behaviour(clickhouse_erl_parser_behaviour).

-export([parse/2, init/1]).

-type parser_state() :: #{}.

-type parse_result() ::
    {done, list(), binary()}.

%% @doc Initialize parser state for END_OF_STREAM packet.
%% END_OF_STREAM packets have no payload, so state is empty.
-spec init(map()) -> parser_state().
init(_State) ->
    #{}.

%% @doc Parse END_OF_STREAM packet payload (which is empty).
%% Returns immediately with done status and passes through all data.
-spec parse(binary(), parser_state()) -> parse_result().
parse(Data, _State) ->
    {done, [], Data}.
