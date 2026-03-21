%% @doc Parser for SERVER_PART_UUIDS (12) packets.
%%
%% The PART_UUIDS packet contains a list of unique part IDs.
%% It includes a count followed by an array of UUID strings.
%%
%% Emitted events:
%% - `{data, count, Count}` - Varint number of UUIDs
%% - `{data, uuid, UUID}` - String UUID (emitted Count times)
%%
%% Packet format:
%% 1. count (varint)
%% 2. uuids (array of strings, Count elements)
-module(clickhouse_erl_parser_server_part_uuids).
-behaviour(clickhouse_erl_parser_behaviour).

-export([parse/2, init/1]).

-type parser_state() :: #{
    stage := count | uuids,
    version := non_neg_integer(),
    count => non_neg_integer(),
    parsed => non_neg_integer()
}.

-type parse_result() ::
    {done, list(), binary()}
    | {more, list(), binary(), parser_state()}
    | {error, term()}.

%% @doc Initialize parser state for PART_UUIDS packet.
-spec init(map()) -> parser_state().
init(#{version := Version}) ->
    #{stage => count, version => Version}.

%% @doc Parse PART_UUIDS packet payload.
-spec parse(binary(), parser_state()) -> parse_result().
parse(Data, State) ->
    do_parse(Data, State, []).

do_parse(Data, #{stage := count} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, Count, Rest} ->
            NewState = State#{
                stage => uuids,
                count => Count,
                parsed => 0
            },
            do_parse(Rest, NewState, [{data, count, Count} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := uuids, count := Count, parsed := Parsed} = State, Acc) when
    Parsed < Count
->
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, UUID, Rest} ->
            NewState = State#{parsed => Parsed + 1},
            do_parse(Rest, NewState, [{data, uuid, UUID} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := uuids, count := Count, parsed := Count} = _State, Acc) ->
    %% All UUIDs parsed
    {done, lists:reverse(Acc), Data}.
