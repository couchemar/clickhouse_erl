%% @doc Parser for SERVER_EXCEPTION (2) packets.
%%
%% The EXCEPTION packet contains error information from the server.
%% It includes an error code, exception name, message, and optional stack trace.
%%
%% Emitted events:
%% - `{data, error_code, Code}` - 32-bit signed integer error code
%% - `{data, exception_name, Name}` - String name of the exception
%% - `{data, message, Message}` - String error message
%% - `{data, stack_trace, Trace}` - String stack trace (if available)
%% - `{data, nested, HasNested}` - Boolean indicating if nested exceptions follow
%%
%% The parser processes fields sequentially:
%% 1. error_code (4 bytes, little-endian signed integer)
%% 2. exception_name (varint-prefixed UTF-8 string)
%% 3. message (varint-prefixed UTF-8 string)
%% 4. stack_trace (varint-prefixed UTF-8 string)
%% 5. nested (1 byte: 0 = no nested, non-zero = nested exceptions follow)
%%
%% If nested exceptions are present (nested = true), the parser resets to
%% error_code stage to parse the next exception in the chain.
-module(clickhouse_erl_parser_server_exception).
-behaviour(clickhouse_erl_parser_behaviour).

-export([parse/2, init/1]).

-type parser_state() :: #{
    stage := error_code | name | message | stack_trace | nested
}.

-type parse_result() ::
    {done, list(), binary()}
    | {more, list(), binary(), parser_state()}
    | {error, term()}.

%% @doc Initialize parser state for EXCEPTION packet.
%% EXCEPTION packets have no version-dependent fields, so state is minimal.
-spec init(map()) -> parser_state().
init(_State) ->
    #{stage => error_code}.

%% @doc Parse EXCEPTION packet payload.
%% Processes fields sequentially: error_code, name, message, stack_trace, nested.
%% Returns {done, Events, Rest} when complete, or {more, Events, Data, State} if incomplete.
-spec parse(binary(), parser_state()) -> parse_result().
parse(Data, State) ->
    do_parse(Data, State, []).

do_parse(Data, #{stage := error_code} = State, Acc) ->
    case Data of
        <<Code:32/signed-little, Rest/binary>> ->
            do_parse(Rest, State#{stage => name}, [{data, error_code, Code} | Acc]);
        _ ->
            {more, lists:reverse(Acc), Data, State}
    end;
do_parse(Data, #{stage := name} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, Name, Rest} ->
            do_parse(Rest, State#{stage => message}, [{data, exception_name, Name} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := message} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, Msg, Rest} ->
            do_parse(Rest, State#{stage => stack_trace}, [{data, message, Msg} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := stack_trace} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, Trace, Rest} ->
            do_parse(Rest, State#{stage => nested}, [{data, stack_trace, Trace} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := nested} = State, Acc) ->
    case Data of
        <<0:8, Rest/binary>> ->
            {done, lists:reverse([{data, nested, false} | Acc]), Rest};
        <<_:8, Rest/binary>> ->
            %% More nested exceptions follow.
            %% We emit a true marker and reset to error_code stage.
            do_parse(Rest, State#{stage => error_code}, [{data, nested, true} | Acc]);
        <<>> ->
            {more, lists:reverse(Acc), Data, State}
    end.
