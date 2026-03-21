%% @doc Parser for SERVER_PROGRESS (3) packets.
%%
%% The PROGRESS packet contains query execution progress information.
%% It includes rows/bytes processed and optional write statistics.
%%
%% Emitted events:
%% - `{data, rows, Rows}` - Varint number of rows processed
%% - `{data, bytes, Bytes}` - Varint number of bytes processed
%% - `{data, total_rows, TotalRows}` - Varint total rows to process
%% - `{data, wrote_rows, WroteRows}` - Varint rows written (version-dependent)
%% - `{data, wrote_bytes, WroteBytes}` - Varint bytes written (version-dependent)
%% - `{data, elapsed_ns, ElapsedNs}` - Varint elapsed time in nanoseconds (version-dependent)
%%
%% The parser processes fields sequentially:
%% 1. rows (varint)
%% 2. bytes (varint)
%% 3. total_rows (varint)
%% 4. wrote_rows (varint) - if client_write_info feature supported
%% 5. wrote_bytes (varint) - if client_write_info feature supported
%% 6. elapsed_ns (varint) - if server_query_time_in_progress feature supported
%%
%% Version-dependent fields are determined by checking feature support
%% via `clickhouse_erl_protocol_features:has_feature/2`.
-module(clickhouse_erl_parser_server_progress).
-behaviour(clickhouse_erl_parser_behaviour).

-export([parse/2, init/1]).

-type parser_state() :: #{
    stage := rows | bytes | total_rows | wrote_rows | wrote_bytes | elapsed_ns,
    version := non_neg_integer()
}.

-type parse_result() ::
    {done, list(), binary()}
    | {more, list(), binary(), parser_state()}
    | {error, term()}.

%% @doc Initialize parser state for PROGRESS packet.
%% Requires client version from state to determine which fields are present.
-spec init(map()) -> parser_state().
init(#{version := Version}) ->
    #{stage => rows, version => Version}.

%% @doc Parse PROGRESS packet payload.
%% Processes fields sequentially, checking version features for optional fields.
%% Returns {done, Events, Rest} when complete, or {more, Events, Data, State} if incomplete.
-spec parse(binary(), parser_state()) -> parse_result().
parse(Data, State) ->
    do_parse(Data, State, []).

do_parse(Data, #{stage := rows} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, Rows, Rest} ->
            do_parse(Rest, State#{stage => bytes}, [{data, rows, Rows} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := bytes} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, Bytes, Rest} ->
            do_parse(Rest, State#{stage => total_rows}, [{data, bytes, Bytes} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := total_rows} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, TotalRows, Rest} ->
            do_parse(Rest, State#{stage => wrote_rows}, [{data, total_rows, TotalRows} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := wrote_rows, version := ClientVersion} = State, Acc) ->
    case clickhouse_erl_protocol_features:has_feature(client_write_info, ClientVersion) of
        true ->
            case clickhouse_erl_types_primitive:decode_varint(Data) of
                {ok, WroteRows, Rest} ->
                    do_parse(Rest, State#{stage => wrote_bytes}, [
                        {data, wrote_rows, WroteRows} | Acc
                    ]);
                {error, {truncated_data, _}} ->
                    {more, lists:reverse(Acc), Data, State};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            do_parse(Data, State#{stage => wrote_bytes}, Acc)
    end;
do_parse(Data, #{stage := wrote_bytes, version := ClientVersion} = State, Acc) ->
    case clickhouse_erl_protocol_features:has_feature(client_write_info, ClientVersion) of
        true ->
            case clickhouse_erl_types_primitive:decode_varint(Data) of
                {ok, WroteBytes, Rest} ->
                    do_parse(Rest, State#{stage => elapsed_ns}, [
                        {data, wrote_bytes, WroteBytes} | Acc
                    ]);
                {error, {truncated_data, _}} ->
                    {more, lists:reverse(Acc), Data, State};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            do_parse(Data, State#{stage => elapsed_ns}, Acc)
    end;
do_parse(Data, #{stage := elapsed_ns, version := ClientVersion} = State, Acc) ->
    case
        clickhouse_erl_protocol_features:has_feature(server_query_time_in_progress, ClientVersion)
    of
        true ->
            case clickhouse_erl_types_primitive:decode_varint(Data) of
                {ok, ElapsedNs, Rest} ->
                    {done, lists:reverse([{data, elapsed_ns, ElapsedNs} | Acc]), Rest};
                {error, {truncated_data, _}} ->
                    {more, lists:reverse(Acc), Data, State};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            {done, lists:reverse(Acc), Data}
    end.
