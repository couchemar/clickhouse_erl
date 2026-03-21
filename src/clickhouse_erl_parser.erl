%% @doc A streaming, lazy parser for ClickHouse protocol messages.
%%
%% This parser processes raw binary streams incrementally and emits a list of
%% parsing events. This approach avoids buffering large unparsed chunks memory
%% and allows consumers to process data as soon as it arrives.
%%
%% The parser maintains an internal state and buffer. It delegates payload
%% parsing to specific message parsers (e.g. `clickhouse_erl_parser_server_hello`)
%% which act as state machines yielding atomic parse events.
%%
%% Emitted events are in the format:
%% - `{start, PacketType}` : Marks the beginning of a message.
%% - `{data, FieldName, Value}` : An individual parsed field of the message.
%% - `{'end', PacketType}` : Marks the successful completion of a message.
%% - `need_more` : Indicates that the parser needs more bytes to continue
%%   (always the last element in incomplete streams).
-module(clickhouse_erl_parser).
-include("clickhouse_erl_protocol.hrl").

-export([parse/2, init/1, init/2]).

%% Parser module callbacks - allows dynamic dispatch to parser implementations
-callback init(ParentState :: map()) -> map().
-callback parse(Data :: binary(), State :: map()) ->
    {done, [term()], binary()}
    | {more, [term()], binary(), map()}
    | {error, term()}.

%% @doc Initializes the parser state without compression options.
%%
%% `Version` - the protocol version negotiated with the server.
-spec init(non_neg_integer()) -> map().
init(Version) ->
    init(Version, undefined).

%% @doc Initializes the parser state with compression options.
%%
%% `Version` - the protocol version negotiated with the server.
%% `CompressionOpts` - compression options map or `undefined` if compression is disabled.
-spec init(non_neg_integer(), map() | undefined) -> map().
init(Version, CompressionOpts) ->
    #{
        state => initial,
        buffer => <<>>,
        version => Version,
        compression_opts => CompressionOpts
    }.

%% @doc Parses an incoming chunk of binary data and returns a list of events.
%%
%% Merges the newly arrived `Data` with any leftover `buffer` from previous
%% calls, and processes as much as possible, delegating to the current active
%% packet parser.
parse(Data, #{buffer := Buffer} = State) ->
    NewBuffer = <<Buffer/binary, Data/binary>>,
    do_parse(NewBuffer, State#{buffer => <<>>}, []).

do_parse(<<>>, #{state := initial} = State, Acc) ->
    {ok, lists:reverse([need_more | Acc]), State};
do_parse(<<MsgByte:8, Rest/binary>>, #{state := initial} = State, Acc) ->
    case get_message_type(MsgByte) of
        unknown ->
            {error, {unknown_message_type, MsgByte}};
        Type ->
            ParserModule = get_parser(Type),
            case ParserModule of
                {ok, Module} ->
                    ParserState = Module:init(State#{packet_type => Type}),
                    NewState = State#{
                        state => parsing,
                        type => Type,
                        parser => Module,
                        parser_state => ParserState
                    },
                    do_parse(Rest, NewState, [{start, Type} | Acc]);
                {error, Error} ->
                    {error, Error}
            end
    end;
do_parse(
    Buffer,
    #{state := parsing, type := Type, parser := ParserModule, parser_state := ParserState} = State,
    Acc
) ->
    case ParserModule:parse(Buffer, ParserState) of
        {done, Events, Rest} ->
            NewState = State#{
                state => initial, type => undefined, parser => undefined, parser_state => undefined
            },
            do_parse(Rest, NewState, [{'end', Type} | lists:reverse(Events) ++ Acc]);
        {more, Events, UnparsedRest, NewParserState} ->
            NewState = State#{parser_state => NewParserState, buffer => UnparsedRest},
            {ok, lists:reverse([need_more | lists:reverse(Events) ++ Acc]), NewState};
        {error, Reason} ->
            {error, Reason}
    end.

get_message_type(MsgByte) ->
    case MsgByte of
        ?SERVER_HELLO -> server_hello;
        ?SERVER_DATA -> server_data;
        ?SERVER_EXCEPTION -> server_exception;
        ?SERVER_PROGRESS -> server_progress;
        ?SERVER_PONG -> server_pong;
        ?SERVER_END_OF_STREAM -> server_end_of_stream;
        ?SERVER_PROFILE -> server_profile;
        ?SERVER_TOTALS -> server_totals;
        ?SERVER_EXTREMES -> server_extremes;
        ?SERVER_TABLES_STATUS -> server_tables_status;
        ?SERVER_LOG -> server_log;
        ?SERVER_TABLE_COLUMNS -> server_table_columns;
        ?SERVER_PART_UUIDS -> server_part_uuids;
        ?SERVER_READ_TASK_REQUEST -> server_read_task_request;
        ?SERVER_PROFILE_EVENTS -> server_profile_events;
        _ -> unknown
    end.

get_parser(Type) ->
    case Type of
        server_hello -> {ok, clickhouse_erl_parser_server_hello};
        server_exception -> {ok, clickhouse_erl_parser_server_exception};
        server_pong -> {ok, clickhouse_erl_parser_server_pong};
        server_end_of_stream -> {ok, clickhouse_erl_parser_server_end_of_stream};
        server_progress -> {ok, clickhouse_erl_parser_server_progress};
        server_profile -> {ok, clickhouse_erl_parser_server_profile};
        server_data -> {ok, clickhouse_erl_parser_block};
        server_totals -> {ok, clickhouse_erl_parser_block};
        server_extremes -> {ok, clickhouse_erl_parser_block};
        server_log -> {ok, clickhouse_erl_parser_server_log};
        server_table_columns -> {ok, clickhouse_erl_parser_server_table_columns};
        server_part_uuids -> {ok, clickhouse_erl_parser_server_part_uuids};
        server_read_task_request -> {ok, clickhouse_erl_parser_server_read_task_request};
        server_profile_events -> {ok, clickhouse_erl_parser_block};
        unknown -> {error, unknown_message_type};
        _Other -> {error, {unsupported_message_type, Type}}
    end.
