%% @doc Parser for SERVER_TABLE_COLUMNS (11) packets.
%%
%% The TABLE_COLUMNS packet contains table column metadata for default values calculation.
%% It includes the external table name and column descriptions.
%%
%% Emitted events:
%% - `{data, external_table_name, TableName}` - String name of the external table
%% - `{data, column_description, Description}` - String with column metadata
%%
%% Packet format:
%% 1. external_table_name (string with varint length prefix)
%% 2. column_description (string with varint length prefix)
-module(clickhouse_erl_parser_server_table_columns).
-behaviour(clickhouse_erl_parser_behaviour).

-export([parse/2, init/1]).

-type parser_state() :: #{
    stage := external_table_name | column_description,
    version := non_neg_integer()
}.

-type parse_result() ::
    {done, list(), binary()}
    | {more, list(), binary(), parser_state()}
    | {error, term()}.

%% @doc Initialize parser state for TABLE_COLUMNS packet.
-spec init(map()) -> parser_state().
init(#{version := Version}) ->
    #{stage => external_table_name, version => Version}.

%% @doc Parse TABLE_COLUMNS packet payload.
-spec parse(binary(), parser_state()) -> parse_result().
parse(Data, State) ->
    do_parse(Data, State, []).

do_parse(Data, #{stage := external_table_name} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, TableName, Rest} ->
            do_parse(
                Rest,
                State#{stage => column_description},
                [{data, external_table_name, TableName} | Acc]
            );
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := column_description} = _State, Acc) ->
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, Description, Rest} ->
            {done, lists:reverse([{data, column_description, Description} | Acc]), Rest};
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, #{stage => column_description, version => 54451}};
        {error, Reason} ->
            {error, Reason}
    end.
