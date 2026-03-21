%% @doc Parser for SERVER_PONG (4) packets.
%%
%% The PONG packet has no payload - it's just the packet type byte.
%% This parser immediately returns done with no events, passing through
%% any remaining data for the next packet.
-module(clickhouse_erl_parser_server_pong).
-behaviour(clickhouse_erl_parser_behaviour).

-export([parse/2, init/1]).

%% @doc Initialize parser state for PONG packet.
%% PONG packets have no state since they have no payload.
-spec init(map()) -> map().
init(_State) ->
    #{}.

%% @doc Parse PONG packet payload (which is empty).
%% Returns immediately with done status and passes through all data.
-spec parse(binary(), map()) -> {done, list(), binary()}.
parse(Data, _State) ->
    {done, [], Data}.
