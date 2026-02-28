-module(clickhouse_erl_protocol_exception_packet).
-include_lib("kernel/include/logger.hrl").
-include("clickhouse_erl_protocol.hrl").

-export([decode/1, validate_parse_limits/1, get_parse_stats/1]).
-export_type([exception_info/0, parse_state/0]).

%% Internal parse state for tracking limits during decoding
-record(parse_state, {
    total_bytes = 0 :: non_neg_integer(),
    nested_count = 0 :: non_neg_integer()
}).

-opaque parse_state() :: #parse_state{}.

%% Exception parsing limits are fetched from clickhouse_erl_config

%% @doc Decode an Exception packet (Type 2).
%%
%% Parses exception data according to ClickHouse protocol specification.
%% Extracts error_code, exception_name, message, stack_trace, and nested flag.
%% Supports recursive parsing of nested exceptions with depth limits.
%% Enforces memory and nesting limits to prevent DoS attacks.
-spec decode(binary()) -> {ok, exception_info(), binary()} | {error, term()}.
decode(Binary) ->
    ?LOG_DEBUG(#{message => "Starting exception packet decode", binary_size => byte_size(Binary)}),

    %% Initialize parse state for limit tracking
    ParseState = #parse_state{},

    %% Perform decode with limit enforcement
    case decode_internal(Binary, 0, ParseState) of
        {ok, ExceptionInfo, _FinalState, Rest} ->
            ?LOG_DEBUG(#{
                message => "Exception packet decode successful",
                exception_info => ExceptionInfo,
                remaining_bytes => byte_size(Rest)
            }),
            {ok, ExceptionInfo, Rest};
        {error, Reason, FailedState} ->
            ?LOG_DEBUG(#{
                message => "Exception packet decode failed",
                error => Reason,
                binary_size => byte_size(Binary),
                parse_state => FailedState
            }),
            {error, Reason}
    end.

%% @doc Internal function to decode exception packet with limit enforcement
%% and nesting depth tracking.
-spec decode_internal(binary(), non_neg_integer(), parse_state()) ->
    {ok, exception_info(), parse_state(), binary()}
    | {error, term(), parse_state()}.
decode_internal(Binary, Depth, ParseState) ->
    %% Check nesting depth limit to prevent infinite recursion
    MaxDepth = clickhouse_erl_config:get_max_exception_nesting_depth(),
    MaxNestedCount = clickhouse_erl_config:get_max_nested_exception_count(),

    maybe
        %% Validate depth limit
        true ?= Depth =< MaxDepth,
        %% Validate nested count limit
        true ?= ParseState#parse_state.nested_count =< MaxNestedCount,
        %% Parse error_code as 32-bit signed little-endian integer
        <<ErrorCode:32/signed-little, Rest1/binary>> ?= Binary,
        %% Parse exception_name with limit checking
        NameMaxSize = clickhouse_erl_config:get_max_exception_name_size(),
        {ok, ExceptionName, Rest2, State1} ?=
            decode_string_checked(Rest1, NameMaxSize, exception_name, ParseState),
        %% Parse message with limit checking
        MsgMaxSize = clickhouse_erl_config:get_max_exception_message_size(),
        {ok, Message, Rest3, State2} ?=
            decode_string_checked(Rest2, MsgMaxSize, message, State1),
        %% Parse stack_trace with limit checking
        TraceMaxSize = clickhouse_erl_config:get_max_stack_trace_size(),
        {ok, StackTrace, Rest4, State3} ?=
            decode_string_checked(Rest3, TraceMaxSize, stack_trace, State2),
        %% Parse nested flag as boolean (UInt8)
        <<NestedByte:8, Rest5/binary>> ?= Rest4,
        Nested =
            case NestedByte of
                0 -> false;
                _ -> true
            end,
        %% Update nested count
        NestedCount = State3#parse_state.nested_count,
        State4 = State3#parse_state{nested_count = NestedCount + 1},
        %% Parse nested exceptions
        {ok, NestedExceptions, FinalState, FinalRest} ?=
            parse_nested_exceptions(Rest5, Nested, Depth, State4),
        %% Create exception info record
        ExceptionInfo = #exception_info{
            error_code = ErrorCode,
            exception_name = ExceptionName,
            message = Message,
            stack_trace = StackTrace,
            nested = Nested,
            nested_exceptions = NestedExceptions
        },
        {ok, ExceptionInfo, FinalState, FinalRest}
    else
        false when Depth > MaxDepth ->
            {error, {too_many_nested_exceptions, Depth, MaxDepth}, ParseState};
        false when ParseState#parse_state.nested_count > MaxNestedCount ->
            {error,
                {too_many_nested_exceptions, ParseState#parse_state.nested_count, MaxNestedCount},
                ParseState};
        {error, Reason, FailedState} ->
            {error, Reason, FailedState};
        _ ->
            {error, {invalid_exception_format, "Insufficient data for error code"}, ParseState}
    end.

%% @doc Decode a string with limit checking and memory tracking.
%%
%% Enforces size limits to prevent memory exhaustion from malicious packets.
%% Returns {ok, String, Rest, UpdatedState} or {error, Reason, State}.
-spec decode_string_checked(binary(), non_neg_integer(), atom(), parse_state()) ->
    {ok, binary(), binary(), parse_state()} | {error, term(), parse_state()}.
decode_string_checked(Binary, MaxLength, FieldName, ParseState) ->
    case clickhouse_erl_types_primitive:decode_string(Binary, MaxLength) of
        {ok, String, Rest} ->
            %% Calculate memory usage for this string
            StringSize = byte_size(String),

            %% Check total memory limit
            NewTotalBytes = ParseState#parse_state.total_bytes + StringSize,
            MaxTotalSize = clickhouse_erl_config:get_max_total_exception_size(),
            case NewTotalBytes > MaxTotalSize of
                true ->
                    {error, {memory_limit_exceeded, NewTotalBytes, MaxTotalSize}, ParseState};
                false ->
                    %% Update parse state with new byte count
                    UpdatedState = ParseState#parse_state{
                        total_bytes = NewTotalBytes
                    },
                    {ok, String, Rest, UpdatedState}
            end;
        {error, {string_too_long, #{length := Length, max_length := MaxLength}}} ->
            {error, {exception_field_truncated, FieldName, Length, MaxLength}, ParseState};
        {error, Reason} ->
            {error,
                {exception_parsing_error,
                    clickhouse_erl_protocol_common:format_decode_error(Reason)},
                ParseState}
    end.

%% @doc Parse nested exceptions recursively when nested=true.
%%
%% Returns {ok, NestedExceptions, UpdatedState, RemainingBinary} where NestedExceptions is a list
%% of exception_info records in the order they appear in the packet.
%% Enforces limits to prevent DoS attacks.
-spec parse_nested_exceptions(
    binary(), boolean(), non_neg_integer(), parse_state()
) ->
    {ok, [exception_info()], parse_state(), binary()} | {error, term(), parse_state()}.
parse_nested_exceptions(Binary, false, _Depth, ParseState) ->
    %% No nested exceptions to parse
    {ok, [], ParseState, Binary};
parse_nested_exceptions(Binary, true, Depth, ParseState) ->
    %% Only try to parse nested exceptions if there's actually data remaining
    case byte_size(Binary) of
        0 ->
            %% No more data, no nested exceptions
            {ok, [], ParseState, Binary};
        _ ->
            %% Parse nested exception recursively with limit checking
            case decode_internal(Binary, Depth + 1, ParseState) of
                {ok, NestedException, UpdatedState, RemainingBinary} ->
                    %% Successfully parsed one nested exception
                    %% Return it as a list with the remaining binary
                    {ok, [NestedException], UpdatedState, RemainingBinary};
                {error, Reason, FailedState} ->
                    %% Failed to parse nested exception
                    {error, Reason, FailedState}
            end
    end.

%% @doc Validate parse limits for exception parsing.
%%
%% Performs comprehensive validation of resource usage to prevent
%% memory exhaustion and ensure safe parsing.
-spec validate_parse_limits(parse_state()) -> ok | {error, term()}.
validate_parse_limits(ParseState) ->
    %% Check total memory usage
    TotalBytes = ParseState#parse_state.total_bytes,
    MaxTotalSize = clickhouse_erl_config:get_max_total_exception_size(),
    case TotalBytes > MaxTotalSize of
        true ->
            {error, {memory_limit_exceeded, TotalBytes, MaxTotalSize}};
        false ->
            %% Check nested exception count
            NestedCount = ParseState#parse_state.nested_count,
            MaxNestedCount = clickhouse_erl_config:get_max_nested_exception_count(),
            case NestedCount > MaxNestedCount of
                true ->
                    {error, {too_many_nested_exceptions, NestedCount, MaxNestedCount}};
                false ->
                    ok
            end
    end.

%% @doc Get current parse statistics.
%%
%% Returns a map with current resource usage for monitoring and debugging.
-spec get_parse_stats(parse_state()) -> #{atom() => term()}.
get_parse_stats(ParseState) ->
    #{
        total_bytes => ParseState#parse_state.total_bytes,
        nested_count => ParseState#parse_state.nested_count,
        memory_limit => clickhouse_erl_config:get_max_total_exception_size(),
        nesting_limit => clickhouse_erl_config:get_max_exception_nesting_depth(),
        nested_count_limit => clickhouse_erl_config:get_max_nested_exception_count()
    }.
