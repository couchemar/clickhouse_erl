%% @doc Parser for SERVER_PROFILE (6) packets.
%%
%% The PROFILE packet contains query profiling information (BlockStreamProfileInfo).
%% It includes statistics about rows, blocks, and bytes processed.
%%
%% Emitted events:
%% - `{data, rows, Rows}` - Varint number of rows processed
%% - `{data, blocks, Blocks}` - Varint number of blocks processed
%% - `{data, bytes, Bytes}` - Varint number of bytes processed
%% - `{data, applied_limit, AppliedLimit}` - Boolean (1 byte) whether limit was applied
%% - `{data, rows_before_limit, RowsBeforeLimit}` - Varint rows before limit
%% - `{data, calculated_rows_before_limit, Calculated}` - Boolean (1 byte) whether rows_before_limit was calculated
%%
%% Packet format (sequential fields):
%% 1. rows (varint)
%% 2. blocks (varint)
%% 3. bytes (varint)
%% 4. applied_limit (bool - 1 byte)
%% 5. rows_before_limit (varint)
%% 6. calculated_rows_before_limit (bool - 1 byte)
-module(clickhouse_erl_parser_server_profile).
-behaviour(clickhouse_erl_parser_behaviour).

-export([parse/2, init/1]).

-type parser_state() :: #{
    stage :=
        rows | blocks | bytes | applied_limit | rows_before_limit | calculated_rows_before_limit,
    version := non_neg_integer()
}.

-type parse_result() ::
    {done, list(), binary()}
    | {more, list(), binary(), parser_state()}
    | {error, term()}.

%% @doc Initialize parser state for PROFILE packet.
-spec init(map()) -> parser_state().
init(#{version := Version}) ->
    #{stage => rows, version => Version}.

%% @doc Parse PROFILE packet payload.
%% Processes fields sequentially.
-spec parse(binary(), parser_state()) -> parse_result().
parse(Data, State) ->
    do_parse(Data, State, []).

do_parse(Data, #{stage := rows} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, Rows, Rest} ->
            do_parse(Rest, State#{stage => blocks}, [{data, rows, Rows} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := blocks} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, Blocks, Rest} ->
            do_parse(Rest, State#{stage => bytes}, [{data, blocks, Blocks} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := bytes} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, Bytes, Rest} ->
            do_parse(Rest, State#{stage => applied_limit}, [{data, bytes, Bytes} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(<<AppliedLimit:8, Rest/binary>>, #{stage := applied_limit} = State, Acc) ->
    Bool =
        case AppliedLimit of
            0 -> false;
            _ -> true
        end,
    do_parse(Rest, State#{stage => rows_before_limit}, [{data, applied_limit, Bool} | Acc]);
do_parse(Data, #{stage := applied_limit} = State, Acc) when byte_size(Data) < 1 ->
    {more, lists:reverse(Acc), Data, State};
do_parse(Data, #{stage := rows_before_limit} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, RowsBeforeLimit, Rest} ->
            do_parse(
                Rest,
                State#{stage => calculated_rows_before_limit},
                [{data, rows_before_limit, RowsBeforeLimit} | Acc]
            );
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(<<Calculated:8, Rest/binary>>, #{stage := calculated_rows_before_limit} = _State, Acc) ->
    Bool =
        case Calculated of
            0 -> false;
            _ -> true
        end,
    {done, lists:reverse([{data, calculated_rows_before_limit, Bool} | Acc]), Rest};
do_parse(Data, #{stage := calculated_rows_before_limit} = State, Acc) when byte_size(Data) < 1 ->
    {more, lists:reverse(Acc), Data, State}.
