-module(clickhouse_erl_exception).

-include("clickhouse_erl_protocol.hrl").

-export([
    format/1,
    to_map/1,
    is_exception/1,
    get_code/1,
    get_name/1,
    get_message/1,
    get_stack_trace/1,
    flatten/1,
    compare/2,
    match_code/2,
    match_name/2,
    match_message/2,
    has_nested/1,
    count_nested/1,
    find_by_code/2,
    find_by_name/2,
    is_schema_error/1
]).

-ignore_xref([
    to_map/1,
    is_exception/1,
    get_code/1,
    get_name/1,
    get_message/1,
    get_stack_trace/1,
    flatten/1,
    compare/2,
    match_code/2,
    match_name/2,
    match_message/2,
    has_nested/1,
    count_nested/1,
    find_by_code/2,
    find_by_name/2,
    is_schema_error/1
]).

-export_type([exception_info/0]).

%% @doc Format an exception into a human-readable binary.
-spec format(exception_info() | map()) -> binary().
format(#{code := Code, name := Name, message := Message} = Info) ->
    %% Map-based exception info (from event-driven parser)
    StackTrace = maps:get(stack_trace, Info, <<>>),
    BaseStr = format_exception_base(Code, Name, Message),
    unicode:characters_to_binary([BaseStr, format_stack_trace_suffix(StackTrace)]);
format(Info) when is_map(Info) ->
    %% Map missing required fields — format what we have
    Message = maps:get(message, Info, <<"unknown error">>),
    StackTrace = maps:get(stack_trace, Info, <<>>),
    unicode:characters_to_binary(
        [<<"Exception: ">>, Message, format_stack_trace_suffix(StackTrace)]
    );
format(#exception_info{
    error_code = Code,
    exception_name = Name,
    message = Message,
    stack_trace = StackTrace,
    nested = Nested,
    nested_exceptions = NestedExceptions
}) ->
    BaseStr = format_exception_base(Code, Name, Message),

    NestedStr =
        case Nested of
            true ->
                CausedBy = <<"\nCaused by:\n">>,
                NestedItems = [format_nested(E, 1) || E <- NestedExceptions],
                unicode:characters_to_binary([CausedBy | NestedItems]);
            false ->
                <<>>
        end,

    StackTraceStr =
        case StackTrace of
            <<>> ->
                <<>>;
            _ ->
                STHeader = <<"\nStack trace:\n">>,
                <<STHeader/binary, StackTrace/binary>>
        end,

    unicode:characters_to_binary([BaseStr, NestedStr, StackTraceStr]).

format_nested(
    #exception_info{
        error_code = Code,
        exception_name = Name,
        message = Message,
        nested = Nested,
        nested_exceptions = NestedExceptions
    },
    Depth
) ->
    Indent = lists:duplicate(Depth * 2, " "),
    BaseStr = io_lib:format("~s~ts\n", [Indent, format_exception_base(Code, Name, Message)]),

    NestedStr =
        case Nested of
            true ->
                [format_nested(E, Depth + 1) || E <- NestedExceptions];
            false ->
                []
        end,
    case unicode:characters_to_binary([BaseStr, NestedStr]) of
        Binary when is_binary(Binary) -> Binary;
        _ -> <<"(formatting error)">>
    end.

%% @doc Helper function to get error description from error code.
-spec get_error_description(integer()) -> {atom(), string()}.
get_error_description(Code) ->
    clickhouse_erl_error_codes:get_error_code_description(Code).

%% @doc Format exception base string with code, name, and message.
-spec format_exception_base(integer(), binary(), binary()) -> iolist().
format_exception_base(Code, Name, Message) ->
    {ErrAtom, Desc} = get_error_description(Code),
    io_lib:format("~ts (~p) [~ts]: ~ts. ~ts", [
        Name, Code, atom_to_list(ErrAtom), Desc, Message
    ]).

%% @doc Format stack trace as a suffix string for exception formatting.
-spec format_stack_trace_suffix(binary()) -> binary().
format_stack_trace_suffix(<<>>) -> <<>>;
format_stack_trace_suffix(StackTrace) -> <<"\nStack trace:\n", StackTrace/binary>>.

%% @doc Convert exception record to a map.
-spec to_map(exception_info()) -> map().
to_map(#exception_info{
    error_code = Code,
    exception_name = Name,
    message = Message,
    stack_trace = StackTrace,
    nested = Nested,
    nested_exceptions = NestedExceptions
}) ->
    #{
        error_code => Code,
        exception_name => Name,
        message => Message,
        stack_trace => StackTrace,
        nested => Nested,
        nested_exceptions => [to_map(E) || E <- NestedExceptions]
    }.

%% @doc Check if a term is a valid exception record.
-spec is_exception(term()) -> boolean().
is_exception(#exception_info{}) -> true;
is_exception(_) -> false.

%% @doc Get the error code.
-spec get_code(exception_info()) -> integer().
get_code(#exception_info{error_code = Code}) -> Code.

%% @doc Get the exception name.
-spec get_name(exception_info()) -> binary().
get_name(#exception_info{exception_name = Name}) -> Name.

%% @doc Get the exception message.
-spec get_message(exception_info()) -> binary().
get_message(#exception_info{message = Message}) -> Message.

%% @doc Get the stack trace.
-spec get_stack_trace(exception_info()) -> binary().
get_stack_trace(#exception_info{stack_trace = StackTrace}) -> StackTrace.

%% @doc Flatten nested exceptions into a list.
%% Returns a list starting with the top-level exception, followed by all nested exceptions
%% in a depth-first traversal order.
-spec flatten(exception_info()) -> [exception_info()].
flatten(#exception_info{nested_exceptions = NestedExceptions} = Exception) ->
    [Exception | lists:flatmap(fun flatten/1, NestedExceptions)].

%% @doc Compare two exceptions for equality.
%% Returns true if both exceptions have the same error code, name, and message.
%% Does not compare stack traces or nested exceptions.
-spec compare(exception_info(), exception_info()) -> boolean().
compare(
    #exception_info{error_code = Code1, exception_name = Name1, message = Msg1},
    #exception_info{error_code = Code2, exception_name = Name2, message = Msg2}
) ->
    Code1 =:= Code2 andalso Name1 =:= Name2 andalso Msg1 =:= Msg2.

%% @doc Check if an exception matches a specific error code.
-spec match_code(exception_info(), integer()) -> boolean().
match_code(#exception_info{error_code = Code}, TargetCode) ->
    Code =:= TargetCode.

%% @doc Check if an exception matches a specific exception name (case-insensitive).
-spec match_name(exception_info(), string() | binary()) -> boolean().
match_name(#exception_info{exception_name = Name}, TargetName) ->
    BN = clickhouse_erl_types_primitive:to_binary(Name),
    BTN = clickhouse_erl_types_primitive:to_binary(TargetName),
    string:casefold(BN) =:= string:casefold(BTN).

%% @doc Check if an exception message contains a specific substring (case-insensitive).
-spec match_message(exception_info(), string() | binary()) -> boolean().
match_message(#exception_info{message = Message}, TargetSubstring) ->
    BM = clickhouse_erl_types_primitive:to_binary(Message),
    BTS = clickhouse_erl_types_primitive:to_binary(TargetSubstring),
    string:find(string:casefold(BM), string:casefold(BTS)) =/= nomatch.

%% @doc Check if an exception has nested exceptions.
-spec has_nested(exception_info()) -> boolean().
has_nested(#exception_info{nested = Nested, nested_exceptions = NestedExceptions}) ->
    Nested andalso length(NestedExceptions) > 0.

%% @doc Count the total number of nested exceptions (including deeply nested ones).
-spec count_nested(exception_info()) -> non_neg_integer().
count_nested(#exception_info{nested_exceptions = NestedExceptions}) ->
    lists:foldl(
        fun(NestedException, Acc) ->
            Acc + 1 + count_nested(NestedException)
        end,
        0,
        NestedExceptions
    ).

%% @doc Find the first exception in the chain (including nested) that matches the given error code.
%% Returns {ok, Exception} if found, or not_found if no match.
-spec find_by_code(exception_info(), integer()) -> {ok, exception_info()} | not_found.
find_by_code(Exception, TargetCode) ->
    AllExceptions = flatten(Exception),
    case lists:search(fun(E) -> match_code(E, TargetCode) end, AllExceptions) of
        {value, FoundException} -> {ok, FoundException};
        false -> not_found
    end.

%% @doc Find the first exception in the chain (including nested) that matches the given name.
%% Returns {ok, Exception} if found, or not_found if no match.
-spec find_by_name(exception_info(), binary() | string()) -> {ok, exception_info()} | not_found.
find_by_name(Exception, TargetName) ->
    AllExceptions = flatten(Exception),
    case lists:search(fun(E) -> match_name(E, TargetName) end, AllExceptions) of
        {value, FoundException} -> {ok, FoundException};
        false -> not_found
    end.

%% @doc Check if an exception is a schema-related error.
%% Returns true for well-known schema mismatch error codes:
%% 16: NO_SUCH_COLUMN_IN_TABLE
%% 47: UNKNOWN_IDENTIFIER
%% 51: EMPTY_LIST_OF_COLUMNS_QUERIED
%% 53: TYPE_MISMATCH
-spec is_schema_error(exception_info() | map()) -> boolean().
is_schema_error(#{code := Code}) ->
    is_schema_error_code(Code);
is_schema_error(#exception_info{error_code = Code}) ->
    is_schema_error_code(Code).

%% @doc Check if an error code is a schema-related error code.
-spec is_schema_error_code(integer()) -> boolean().
is_schema_error_code(Code) ->
    lists:member(Code, [16, 47, 51, 53, 60, 81]).
