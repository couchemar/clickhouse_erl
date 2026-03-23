%% @doc ClickHouse protocol encoding and decoding functions.
%%
%% This module provides functions for encoding and decoding ClickHouse protocol
%% messages according to the native protocol specification.
-module(clickhouse_erl_protocol).

%% Include protocol type definitions
-include("clickhouse_erl_protocol.hrl").

%% Public API
-export([
    encode_client_hello/1,
    decode_server_hello/1,
    decode_server_hello/2,
    decode_exception_packet/1,

    create_exception_info/5,
    create_exception_info/6,
    is_complete_exception/1,
    get_exception_summary/1,
    get_error_description/1,
    get_error_atom/1,
    get_error_code_description/1,
    get_enhanced_error_info/1,
    validate_exception_packet_format/1,
    validate_protocol_compliance/1,
    validate_integer_encoding/2,
    validate_string_encoding/1,
    detect_protocol_violations/1
]).

-ignore_xref([
    create_exception_info/5,
    create_exception_info/6,
    decode_exception_packet/1,
    decode_server_hello/1,
    decode_server_hello/2,
    detect_protocol_violations/1,
    get_enhanced_error_info/1,
    get_error_atom/1,
    get_error_code_description/1,
    get_error_description/1,
    get_exception_summary/1,
    is_complete_exception/1,
    validate_exception_packet_format/1,
    validate_integer_encoding/2,
    validate_protocol_compliance/1,
    validate_string_encoding/1
]).

%% Export types used in public API
-export_type([
    client_hello_info/0,
    server_hello_info/0,
    exception_info/0
]).

%% Protocol constants
-define(CLIENT_HELLO, 0).
-define(EXCEPTION_PACKET, 2).

%% Timeouts
-define(CONNECT_TIMEOUT, 5000).
-define(HANDSHAKE_TIMEOUT, 10000).

%% @doc Encode a Client Hello message.
%%
%% Encodes according to ClickHouse protocol specification.
-spec encode_client_hello(client_hello_info()) -> {ok, binary()} | {error, term()}.
encode_client_hello(ClientInfo) ->
    clickhouse_erl_protocol_client_hello:encode(ClientInfo).

%% @doc Decode a Server Hello message.
%%
%% Decodes according to ClickHouse protocol specification.
-spec decode_server_hello(binary()) -> {ok, server_hello_info(), binary()} | {error, term()}.
decode_server_hello(Binary) ->
    clickhouse_erl_protocol_server_hello:decode(Binary).

-spec decode_server_hello(binary(), integer()) ->
    {ok, server_hello_info(), binary()} | {error, term()}.
decode_server_hello(Binary, Version) ->
    clickhouse_erl_protocol_server_hello:decode(Binary, Version).

%% @doc Decode an Exception packet (Type 2).
%%
%% Parses exception data according to ClickHouse protocol specification.
%% Extracts error_code, exception_name, message, stack_trace, and nested flag.
%% Supports recursive parsing of nested exceptions with depth limits.
-spec decode_exception_packet(binary()) -> {ok, exception_info(), binary()} | {error, term()}.
decode_exception_packet(Binary) ->
    clickhouse_erl_protocol_exception_packet:decode(Binary).

%% @doc Get error description using the existing error codes module.
%%
%% Uses clickhouse_erl_error_codes:get_readable_error/1 for known error codes,
%% falls back to generic description for unknown codes.
-spec get_error_description(integer()) -> string().
get_error_description(ErrorCode) ->
    case clickhouse_erl_error_codes:get_error_code_description(ErrorCode) of
        {unknown_error_code, _} ->
            lists:flatten(io_lib:format("Unknown error code ~w", [ErrorCode]));
        {_, Description} ->
            Description
    end.

%% @doc Get error atom using the existing error codes module.
%%
%% Uses clickhouse_erl_error_codes:get_error/1 for known error codes,
%% falls back to generic atom for unknown codes.
-spec get_error_atom(integer()) -> atom().
get_error_atom(ErrorCode) ->
    clickhouse_erl_error_codes:get_error(ErrorCode).

%% @doc Get complete error code description using the existing error codes module.
%%
%% Uses clickhouse_erl_error_codes:get_error_code_description/1 for known error codes,
%% returns {atom(), description} tuple. Falls back to generic values for unknown codes.
-spec get_error_code_description(integer()) -> {atom(), string()}.
get_error_code_description(ErrorCode) ->
    case clickhouse_erl_error_codes:get_error_code_description(ErrorCode) of
        {unknown_error_code, _} ->
            {unknown_error_code,
                lists:flatten(io_lib:format("Unknown error code ~w", [ErrorCode]))};
        Result ->
            Result
    end.

%% @doc Get enhanced exception information with error code details.
%%
%% Returns a map containing the original error code, error atom, and description
%% from the existing error codes module. Preserves original error codes while
%% adding descriptions from the existing module.
-spec get_enhanced_error_info(integer()) ->
    #{
        error_code => integer(),
        error_atom => atom(),
        error_description => string()
    }.
get_enhanced_error_info(ErrorCode) ->
    {ErrorAtom, ErrorDescription} = get_error_code_description(ErrorCode),
    #{
        error_code => ErrorCode,
        error_atom => ErrorAtom,
        error_description => ErrorDescription
    }.

%% @doc Create a structured exception info record.
%%
%% Creates an exception_info record with all required fields.
%% This function ensures all parsed fields are included in the structure.
-spec create_exception_info(
    integer(), binary() | string(), binary() | string(), binary() | string(), boolean()
) -> exception_info().
create_exception_info(ErrorCode, ExceptionName, Message, StackTrace, Nested) ->
    create_exception_info(ErrorCode, ExceptionName, Message, StackTrace, Nested, []).

%% @doc Create a structured exception info record with nested exceptions.
%%
%% Creates an exception_info record with all required fields including nested exceptions.
%% This function ensures all parsed fields are included in the structure.
-spec create_exception_info(
    integer(), binary() | string(), binary() | string(), binary() | string(), boolean(), [
        exception_info()
    ]
) -> exception_info().
create_exception_info(ErrorCode, ExceptionName, Message, StackTrace, Nested, NestedExceptions) ->
    #exception_info{
        error_code = ErrorCode,
        exception_name = clickhouse_erl_types_primitive:to_binary(ExceptionName),
        message = clickhouse_erl_types_primitive:to_binary(Message),
        stack_trace = clickhouse_erl_types_primitive:to_binary(StackTrace),
        nested = Nested,
        nested_exceptions = NestedExceptions
    }.

%% @doc Check if an exception info record is complete.
%%
%% Validates that all required fields are present and non-empty.
%% Handles incomplete exception data by checking for missing or empty fields.
%% Supports both #exception_info{} records and map-based exception info.
-spec is_complete_exception(exception_info() | map()) -> boolean().
is_complete_exception(#{code := Code, name := Name, message := Message} = Info) ->
    %% Map-based exception info (from event-driven parser)
    StackTrace = maps:get(stack_trace, Info, <<>>),
    Nested = maps:get(nested, Info, false),
    is_integer(Code) andalso
        is_binary(Name) andalso byte_size(Name) > 0 andalso
        is_binary(Message) andalso byte_size(Message) > 0 andalso
        is_binary(StackTrace) andalso
        is_boolean(Nested);
is_complete_exception(Info) when is_map(Info) ->
    %% Map missing required fields (code, name, or message) — incomplete
    false;
is_complete_exception(ExceptionInfo) ->
    %% Record-based exception info (legacy)
    ErrorCode = ExceptionInfo#exception_info.error_code,
    ExceptionName = ExceptionInfo#exception_info.exception_name,
    Message = ExceptionInfo#exception_info.message,
    StackTrace = ExceptionInfo#exception_info.stack_trace,
    Nested = ExceptionInfo#exception_info.nested,
    NestedExceptions = ExceptionInfo#exception_info.nested_exceptions,

    %% Validate each field
    is_integer(ErrorCode) andalso
        is_binary(ExceptionName) andalso byte_size(ExceptionName) > 0 andalso
        is_binary(Message) andalso byte_size(Message) > 0 andalso
        % Stack trace can be empty
        is_binary(StackTrace) andalso
        is_boolean(Nested) andalso
        is_list(NestedExceptions) andalso
        %% If nested is true, there should be nested exceptions
        (not Nested orelse length(NestedExceptions) > 0) andalso
        %% All nested exceptions should also be complete
        lists:all(fun is_complete_exception/1, NestedExceptions).

%% @doc Get a brief summary of an exception.
%%
%% Returns a short string summarizing the exception for logging or display.
%% Useful for incomplete exception data where full formatting might fail.
-spec get_exception_summary(exception_info()) -> binary().
get_exception_summary(ExceptionInfo) when is_record(ExceptionInfo, exception_info) ->
    ErrorCode = ExceptionInfo#exception_info.error_code,
    ExceptionName = ExceptionInfo#exception_info.exception_name,
    Message = ExceptionInfo#exception_info.message,
    NestedExceptions = ExceptionInfo#exception_info.nested_exceptions,
    maybe
        true ?= is_integer(ErrorCode),
        true ?= is_binary(ExceptionName),
        true ?= is_binary(Message),
        true ?= is_list(NestedExceptions),
        NestedCount = length(NestedExceptions),
        %% Get enhanced error information safely - get_enhanced_error_info
        %% uses get_error_code_description which is already safe.
        ErrorInfo = get_enhanced_error_info(ErrorCode),
        ErrorDescription = maps:get(error_description, ErrorInfo),
        ErrorAtom = maps:get(error_atom, ErrorInfo),
        %% Create summary with nested count if applicable
        NestedSuffix =
            case NestedCount of
                0 -> <<>>;
                N -> unicode:characters_to_binary(io_lib:format(" (+~w nested)", [N]))
            end,
        %% Convert list descriptions to binary if needed
        BDescription = clickhouse_erl_types_primitive:to_binary(ErrorDescription),
        unicode:characters_to_binary(
            io_lib:format("~s: ~s (~s [~s])~s", [
                ExceptionName,
                Message,
                BDescription,
                ErrorAtom,
                NestedSuffix
            ])
        )
    else
        _ ->
            %% Fallback for incomplete or corrupted exception data
            <<"Incomplete exception data">>
    end;
get_exception_summary(_ExceptionInfo) ->
    <<"Incomplete exception data">>.

%% @doc Validate exception packet format for protocol compliance.
%%
%% Validates that an exception packet follows the exact ClickHouse protocol specification
%% for field order, encoding, and format. Returns ok or {error, Reason}.
-spec validate_exception_packet_format(binary()) -> ok | {error, term()}.
validate_exception_packet_format(Binary) when is_binary(Binary) ->
    maybe
        %% Validate minimum packet size
        %% (4 bytes for error code + at least 1 byte for each string length)
        true ?= byte_size(Binary) >= 7,
        %% Validate field order and encoding step by step
        {ok, Rest1} ?= validate_error_code_field(Binary),
        {ok, Rest2} ?= validate_exception_name_field(Rest1),
        {ok, Rest3} ?= validate_message_field(Rest2),
        {ok, Rest4} ?= validate_stack_trace_field(Rest3),
        ok ?= validate_nested_flag_field(Rest4),
        ok
    else
        false -> {error, {protocol_violation, "Exception packet too small"}};
        {error, Reason} -> {error, Reason}
    end;
validate_exception_packet_format(_Binary) ->
    {error, {protocol_violation, "Invalid input: expected binary"}}.

%% @doc Validate overall protocol compliance for exception handling.
%%
%% Performs comprehensive validation of protocol compliance including
%% field order, encoding standards, and format requirements.
-spec validate_protocol_compliance(binary()) -> ok | {error, term()}.
validate_protocol_compliance(Binary) ->
    %% First validate the packet format
    case validate_exception_packet_format(Binary) of
        ok ->
            %% Then validate encoding compliance
            case validate_encoding_compliance(Binary) of
                ok ->
                    %% Finally detect any protocol violations
                    detect_protocol_violations(Binary);
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Validate integer encoding compliance.
%%
%% Validates that integers are encoded according to ClickHouse protocol:
%% - 32-bit signed integers in little-endian format
%% - UInt8 values for boolean flags
-spec validate_integer_encoding(binary(), atom()) -> ok | {error, term()}.
validate_integer_encoding(Binary, error_code) ->
    case byte_size(Binary) >= 4 of
        true ->
            <<ErrorCode:32/signed-little, _Rest/binary>> = Binary,
            %% Validate that the error code is within reasonable bounds
            case ErrorCode >= -2147483648 andalso ErrorCode =< 2147483647 of
                true ->
                    ok;
                false ->
                    {error,
                        {invalid_integer_encoding, error_code,
                            "Error code out of 32-bit signed range"}}
            end;
        false ->
            {error, {invalid_integer_encoding, error_code, "Insufficient bytes for 32-bit integer"}}
    end;
validate_integer_encoding(Binary, nested_flag) ->
    case byte_size(Binary) >= 1 of
        true ->
            <<NestedByte:8, _Rest/binary>> = Binary,
            %% Validate that nested flag is 0 or 1 (boolean)
            case NestedByte =:= 0 orelse NestedByte =:= 1 of
                true ->
                    ok;
                false ->
                    {error,
                        {invalid_integer_encoding, nested_flag,
                            io_lib:format("Invalid boolean value: ~w (expected 0 or 1)", [
                                NestedByte
                            ])}}
            end;
        false ->
            {error, {invalid_integer_encoding, nested_flag, "Insufficient bytes for UInt8"}}
    end;
validate_integer_encoding(_Binary, Field) ->
    {error, {invalid_integer_encoding, Field, "Unknown integer field"}}.

%% @doc Validate string encoding compliance.
%%
%% Validates that strings are encoded according to ClickHouse protocol:
%% - UVarInt length prefix
%% - Valid UTF-8 encoding
%% - Proper length prefix matching actual string length
-spec validate_string_encoding(binary()) -> ok | {error, term()}.
validate_string_encoding(Binary) ->
    maybe
        {ok, Length, Rest} ?=
            wrap_varint_error(clickhouse_erl_types_primitive:decode_varint(Binary)),
        ok ?= check_sufficient_bytes(Rest, Length),
        StringBytes ?= extract_string_bytes(Rest, Length),
        ok ?= validate_utf8_encoding(StringBytes),
        ok ?= validate_string_length(StringBytes, Length),
        ok
    end.

-spec wrap_varint_error({ok, non_neg_integer(), binary()} | {error, term()}) ->
    {ok, non_neg_integer(), binary()} | {error, term()}.
wrap_varint_error({ok, Length, Rest}) ->
    {ok, Length, Rest};
wrap_varint_error({error, Reason}) ->
    {error,
        {invalid_string_encoding, string,
            io_lib:format("Invalid varint length prefix: ~p", [Reason])}}.

-spec check_sufficient_bytes(binary(), non_neg_integer()) -> ok | {error, term()}.
check_sufficient_bytes(Rest, Length) ->
    case byte_size(Rest) >= Length of
        true ->
            ok;
        false ->
            {error,
                {invalid_string_encoding, string, "Insufficient bytes for declared string length"}}
    end.

-spec extract_string_bytes(binary(), non_neg_integer()) -> binary().
extract_string_bytes(Rest, Length) ->
    <<StringBytes:Length/binary, _Remaining/binary>> = Rest,
    StringBytes.

-spec validate_utf8_encoding(binary()) -> ok | {error, term()}.
validate_utf8_encoding(StringBytes) ->
    case unicode:characters_to_list(StringBytes, utf8) of
        {error, _, _} ->
            {error, {invalid_string_encoding, string, "Invalid UTF-8 encoding"}};
        {incomplete, _, _} ->
            {error, {invalid_string_encoding, string, "Incomplete UTF-8 sequence"}};
        ValidString when is_list(ValidString) ->
            ok
    end.

-spec validate_string_length(binary(), non_neg_integer()) -> ok | {error, term()}.
validate_string_length(StringBytes, ExpectedLength) ->
    ActualLength = byte_size(StringBytes),
    case ActualLength =:= ExpectedLength of
        true ->
            ok;
        false ->
            {error,
                {invalid_string_encoding, string,
                    io_lib:format(
                        "Length mismatch: declared ~w, actual ~w",
                        [ExpectedLength, ActualLength]
                    )}}
    end.

%% @doc Detect protocol violations in exception packet.
%%
%% Performs comprehensive detection of protocol violations including:
%% - Field order violations
%% - Encoding standard violations
%% - Format requirement violations
-spec detect_protocol_violations(binary()) -> ok | {error, term()}.
detect_protocol_violations(Binary) ->
    try
        %% Check for common protocol violations
        Violations = [
            check_field_order_violation(Binary),
            check_encoding_violations(Binary),
            check_format_violations(Binary)
        ],

        %% Filter out 'ok' results and collect errors
        Errors = [Error || Error <- Violations, Error =/= ok],

        case Errors of
            [] ->
                ok;
            [FirstError | _] ->
                FirstError
        end
    catch
        error:CatchReason ->
            {error,
                {protocol_violation,
                    io_lib:format("Violation detection failed: ~p", [CatchReason])}}
    end.

%% Internal validation helper functions

%% @doc Validate error code field (first field in exception packet).
-spec validate_error_code_field(binary()) -> {ok, binary()} | {error, term()}.
validate_error_code_field(Binary) ->
    case validate_integer_encoding(Binary, error_code) of
        ok ->
            <<_ErrorCode:32/signed-little, Rest/binary>> = Binary,
            {ok, Rest};
        {error, Reason} ->
            {error, {invalid_field_order, error_code, Reason}}
    end.

%% @doc Validate exception name field (second field in exception packet).
-spec validate_exception_name_field(binary()) -> {ok, binary()} | {error, term()}.
validate_exception_name_field(Binary) ->
    case validate_string_encoding(Binary) of
        ok ->
            case clickhouse_erl_types_primitive:decode_string(Binary) of
                {ok, _ExceptionName, Rest} ->
                    {ok, Rest};
                {error, Reason} ->
                    {error, {invalid_field_order, exception_name, Reason}}
            end;
        {error, Reason} ->
            {error, {invalid_field_order, exception_name, Reason}}
    end.

%% @doc Validate message field (third field in exception packet).
-spec validate_message_field(binary()) -> {ok, binary()} | {error, term()}.
validate_message_field(Binary) ->
    case validate_string_encoding(Binary) of
        ok ->
            case clickhouse_erl_types_primitive:decode_string(Binary) of
                {ok, _Message, Rest} ->
                    {ok, Rest};
                {error, Reason} ->
                    {error, {invalid_field_order, message, Reason}}
            end;
        {error, Reason} ->
            {error, {invalid_field_order, message, Reason}}
    end.

%% @doc Validate stack trace field (fourth field in exception packet).
-spec validate_stack_trace_field(binary()) -> {ok, binary()} | {error, term()}.
validate_stack_trace_field(Binary) ->
    case validate_string_encoding(Binary) of
        ok ->
            case clickhouse_erl_types_primitive:decode_string(Binary) of
                {ok, _StackTrace, Rest} ->
                    {ok, Rest};
                {error, Reason} ->
                    {error, {invalid_field_order, stack_trace, Reason}}
            end;
        {error, Reason} ->
            {error, {invalid_field_order, stack_trace, Reason}}
    end.

%% @doc Validate nested flag field (fifth field in exception packet).
-spec validate_nested_flag_field(binary()) -> ok | {error, term()}.
validate_nested_flag_field(Binary) ->
    case validate_integer_encoding(Binary, nested_flag) of
        ok ->
            ok;
        {error, Reason} ->
            {error, {invalid_field_order, nested_flag, Reason}}
    end.

%% @doc Validate encoding compliance for the entire packet.
-spec validate_encoding_compliance(binary()) -> ok | {error, term()}.
validate_encoding_compliance(Binary) when is_binary(Binary) ->
    maybe
        %% Validate error code encoding (32-bit signed little-endian)
        ok ?= validate_integer_encoding(Binary, error_code),
        <<_ErrorCode:32/signed-little, Rest1/binary>> = Binary,
        %% Validate exception name string encoding
        ok ?= validate_string_encoding(Rest1),
        {ok, _ExceptionName, Rest2} ?= clickhouse_erl_types_primitive:decode_string(Rest1),
        %% Validate message string encoding
        ok ?= validate_string_encoding(Rest2),
        {ok, _Message, Rest3} ?= clickhouse_erl_types_primitive:decode_string(Rest2),
        %% Validate stack trace string encoding
        ok ?= validate_string_encoding(Rest3),
        {ok, _StackTrace, Rest4} ?= clickhouse_erl_types_primitive:decode_string(Rest3),
        %% Validate nested flag encoding (UInt8)
        ok ?= validate_integer_encoding(Rest4, nested_flag),
        ok
    else
        {error, Reason} -> {error, Reason}
    end.

%% @doc Check for field order violations.
-spec check_field_order_violation(binary()) -> ok | {error, term()}.
check_field_order_violation(Binary) when is_binary(Binary) ->
    %% The correct field order is: error_code, exception_name, message, stack_trace, nested_flag
    %% We validate this by attempting to parse each field in the expected order
    maybe
        {error_code, true} ?= {error_code, byte_size(Binary) >= 4},
        <<_ErrorCode:32/signed-little, Rest1/binary>> = Binary,
        {exception_name, {ok, _ExceptionName, Rest2}} ?=
            {exception_name, clickhouse_erl_types_primitive:decode_string(Rest1)},
        {message, {ok, _Message, Rest3}} ?=
            {message, clickhouse_erl_types_primitive:decode_string(Rest2)},
        {stack_trace, {ok, _StackTrace, Rest4}} ?=
            {stack_trace, clickhouse_erl_types_primitive:decode_string(Rest3)},
        {nested_flag, true} ?= {nested_flag, byte_size(Rest4) >= 1},
        ok
    else
        {error_code, false} ->
            {error, {protocol_violation, "Packet too small for error code field"}};
        {exception_name, _} ->
            {error, {protocol_violation, "Invalid exception_name field order or encoding"}};
        {message, _} ->
            {error, {protocol_violation, "Invalid message field order or encoding"}};
        {stack_trace, _} ->
            {error, {protocol_violation, "Invalid stack_trace field order or encoding"}};
        {nested_flag, false} ->
            {error, {protocol_violation, "Missing nested flag field"}};
        _ ->
            {error, {protocol_violation, "Field order check failed: unexpected error"}}
    end;
check_field_order_violation(_Binary) ->
    {error, {protocol_violation, "Invalid input: expected binary"}}.

%% @doc Check for encoding violations.
-spec check_encoding_violations(binary()) -> ok | {error, term()}.
check_encoding_violations(Binary) ->
    %% Check that all integers use correct byte order and size
    %% Check that all strings use proper UTF-8 encoding and varint length prefixes
    validate_encoding_compliance(Binary).

%% @doc Check for format violations.
-spec check_format_violations(binary()) -> ok | {error, term()}.
check_format_violations(Binary) when is_binary(Binary) ->
    maybe
        %% Check minimum packet size
        %% 4 bytes error code + 1 byte each for 3 empty strings + 1 byte nested flag
        true ?= byte_size(Binary) >= 7,
        %% Check that packet can be fully parsed without truncation
        {ok, _ExceptionInfo, _Rest} ?= clickhouse_erl_protocol_exception_packet:decode(Binary),
        ok
    else
        false ->
            {error, {protocol_violation, "Exception packet smaller than minimum required size"}};
        {error, {exception_parsing_error, Details}} ->
            format_violation_error(Details);
        {error, {invalid_exception_format, Details}} ->
            format_violation_error(Details);
        {error, Reason} ->
            {error,
                {protocol_violation,
                    lists:flatten(io_lib:format("Format violation: ~p", [Reason]))}}
    end.

%% @doc Format a protocol violation error with details.
-spec format_violation_error(term()) -> {error, {protocol_violation, string()}}.
format_violation_error(Details) ->
    {error, {protocol_violation, lists:flatten(io_lib:format("Format violation: ~s", [Details]))}}.
