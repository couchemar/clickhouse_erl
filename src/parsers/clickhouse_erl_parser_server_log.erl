%% @doc Parser for SERVER_LOG (10) packets.
%%
%% The LOG packet contains server log entries in block format, similar to DATA packets.
%% The block contains columns: event_time, event_time_microseconds, host_name,
%% query_id, thread_id, priority, source, text.
%%
%% Emitted events:
%% - Block-related events from clickhouse_erl_parser_block
%%
%% Packet format:
%% - temp_table_name (string) - Usually empty for LOG packets
%% - block data - Standard block format with log columns
%%
%% This parser delegates to the block parser since LOG packets use block structure.
-module(clickhouse_erl_parser_server_log).
-behaviour(clickhouse_erl_parser_behaviour).

-export([parse/2, init/1]).

%% @doc Initialize parser state for LOG packet.
%% LOG packets use block structure, so we delegate to block parser.
-spec init(map()) -> map().
init(State) ->
    clickhouse_erl_parser_block:init(State).

%% @doc Parse LOG packet payload.
%% Delegates to block parser since LOG uses block structure.
-spec parse(binary(), map()) ->
    {done, list(), binary()} | {more, list(), binary(), map()} | {error, term()}.
parse(Data, State) ->
    clickhouse_erl_parser_block:parse(Data, State).
