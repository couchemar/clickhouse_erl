%% @doc UUID type encoding and decoding for ClickHouse UUID type.
%%
%% This module handles encoding and decoding of UUID (Universally Unique Identifier) values
%% using RFC 4122 format with support for multiple input formats.
%%
%% Type Representations:
%% - Input: Binary string (with/without hyphens) or 16-byte binary
%% - Output: Binary string in canonical hyphenated format (8-4-4-4-12)
%%
%% Encoding Format:
%% - 16 bytes, RFC 4122 network byte order
%%
%% External Dependencies:
%% - Uses `uuid` library (uuid_erl package) for parsing and formatting
%%
%% Usage Examples:
%%
%% ```
%% % Encode UUID from hyphenated string
%% {ok, Binary} = encode_uuid(<<"550e8400-e29b-41d4-a716-446655440000">>).
%% % Binary = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
%%
%% % Encode UUID from non-hyphenated string
%% {ok, Binary2} = encode_uuid(<<"550e8400e29b41d4a716446655440000">>).
%% % Binary2 = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
%%
%% % Encode UUID from 16-byte binary
%% {ok, Binary3} = encode_uuid(<<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>).
%%
%% % Decode UUID (returns canonical hyphenated format)
%% {ok, <<"550e8400-e29b-41d4-a716-446655440000">>, Rest} = decode_uuid(Binary).
%%
%% % Parse UUID string to binary
%% {ok, Binary4} = parse_uuid(<<"550e8400-e29b-41d4-a716-446655440000">>).
%%
%% % Format UUID binary to string
%% <<"550e8400-e29b-41d4-a716-446655440000">> = format_uuid(Binary).
%%
%% % Validate UUID format
%% true = validate_uuid_format(<<"550e8400-e29b-41d4-a716-446655440000">>).
%% false = validate_uuid_format(<<"invalid-uuid">>).
%%
%% % Invalid UUID format error
%% {error, {invalid_uuid_format, _}} = encode_uuid(<<"not-a-uuid">>).
%%
%% % Invalid UUID length error
%% {error, {invalid_uuid_format, _}} = encode_uuid(<<"550e8400-e29b-41d4">>).
%% '''
%%
%% Error Cases:
%% - {invalid_uuid_format, Value} - Invalid UUID string format or length
%% - {uuid_parse_error, Reason} - UUID library parsing error
%% - {truncated_data, Details} - Binary too short for decoding (expected 16 bytes)
-module(clickhouse_erl_types_uuid).

%% API exports
-export([
    encode_uuid/1,
    decode_uuid/1,
    encode_uuid_column/1,
    decode_uuid_column/2
]).

%% Helper function exports
-export([
    parse_uuid/1,
    format_uuid/1,
    validate_uuid_format/1
]).

-include_lib("kernel/include/logger.hrl").

%% Type definitions
-export_type([
    uuid_value/0,
    uuid_binary/0,
    uuid_string/0
]).

% 16-byte binary
-type uuid_binary() :: <<_:128>>.
% String representation (with or without hyphens)
-type uuid_string() :: binary().
-type uuid_value() :: uuid_string() | uuid_binary().

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Encode a UUID value to 16-byte binary format.
%%
%% Accepts:
%% - Binary string with hyphens: <<"550e8400-e29b-41d4-a716-446655440000">>
%% - Binary string without hyphens: <<"550e8400e29b41d4a716446655440000">>
%% - 16-byte binary: <<85, 14, 132, 0, ...>>
%%
%% Returns {ok, Binary} where Binary is 16 bytes in RFC 4122 network byte order,
%% or {error, Reason} if the UUID is invalid.
%%
%% Requirements: 5.2, 5.3, 5.5, 5.6, 5.7, 5.8
-spec encode_uuid(uuid_value()) -> {ok, binary()} | {error, term()}.
encode_uuid(UUID) when is_binary(UUID) ->
    case byte_size(UUID) of
        16 ->
            % Already a 16-byte binary, validate and return
            case validate_uuid_binary(UUID) of
                ok -> {ok, UUID};
                {error, Reason} -> {error, Reason}
            end;
        _ ->
            % String representation, parse it
            parse_uuid(UUID)
    end;
encode_uuid(UUID) ->
    {error, {invalid_uuid_type, UUID}}.

%% @doc Decode a 16-byte UUID binary to canonical hyphenated string format.
%%
%% Parses 16 bytes from the input binary and returns the UUID as a canonical
%% hyphenated string (8-4-4-4-12 format) along with the remaining binary.
%%
%% Returns {ok, UUIDString, Rest} where UUIDString is in canonical format,
%% or {error, Reason} if the binary is too short or invalid.
%%
%% Requirements: 5.1, 5.3, 5.4, 5.8
-spec decode_uuid(binary()) -> {ok, binary(), binary()} | {error, term()}.
decode_uuid(<<UUID:16/binary, Rest/binary>>) ->
    case format_uuid(UUID) of
        {ok, Formatted} -> {ok, Formatted, Rest};
        {error, Reason} -> {error, Reason}
    end;
decode_uuid(Binary) when is_binary(Binary) ->
    {error,
        {truncated_data, #{
            expected_bytes => 16,
            actual_bytes => byte_size(Binary),
            type => uuid
        }}};
decode_uuid(Data) ->
    {error, {invalid_data_type, #{value => Data, type => uuid}}}.

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Parse a UUID string to 16-byte binary format using uuid library.
%%
%% Accepts UUID strings with or without hyphens and validates the format.
%% Uses the uuid library for parsing.
%%
%% Requirements: 5.5, 5.7
-spec parse_uuid(binary()) -> {ok, binary()} | {error, term()}.
parse_uuid(UUIDString) when is_binary(UUIDString) ->
    % Validate format first
    case validate_uuid_format(UUIDString) of
        ok ->
            % Use uuid library to parse
            try
                % uuid:string_to_uuid/1 expects a string (list), returns binary directly
                UUIDList = binary_to_list(UUIDString),
                UUIDBinary = uuid:string_to_uuid(UUIDList),
                case UUIDBinary of
                    <<_:128>> = Binary ->
                        {ok, Binary};
                    _ ->
                        {error,
                            {invalid_uuid_binary, #{
                                value => UUIDBinary,
                                reason => unexpected_format
                            }}}
                end
            catch
                error:Reason ->
                    {error,
                        {uuid_parse_error, #{
                            value => UUIDString,
                            reason => Reason
                        }}}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Format a 16-byte UUID binary to canonical hyphenated string using uuid library.
%%
%% Uses the uuid library to format the binary as a canonical UUID string
%% in 8-4-4-4-12 format with lowercase hex digits.
%%
%% Requirements: 5.4
-spec format_uuid(binary()) -> {ok, binary()} | {error, term()}.
format_uuid(<<_:128>> = UUIDBinary) ->
    try
        % uuid:uuid_to_string/1 expects binary, returns list directly
        UUIDList = uuid:uuid_to_string(UUIDBinary),
        % Convert to binary and ensure lowercase
        UUIDString = list_to_binary(string:lowercase(UUIDList)),
        {ok, UUIDString}
    catch
        error:Reason ->
            {error,
                {uuid_format_error, #{
                    value => UUIDBinary,
                    reason => Reason
                }}}
    end;
format_uuid(Binary) ->
    {error,
        {invalid_uuid_binary, #{
            value => Binary,
            expected_size => 16,
            actual_size => byte_size(Binary)
        }}}.

%% @doc Validate UUID string format (8-4-4-4-12 hex digits with optional hyphens).
%%
%% Checks that the UUID string matches the expected format:
%% - With hyphens: 36 characters (8-4-4-4-12 pattern)
%% - Without hyphens: 32 hex characters
%%
%% Requirements: 5.7
-spec validate_uuid_format(binary()) -> ok | {error, term()}.
validate_uuid_format(UUIDString) when is_binary(UUIDString) ->
    Size = byte_size(UUIDString),
    case Size of
        36 ->
            % Expected format with hyphens: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
            validate_hyphenated_format(UUIDString);
        32 ->
            % Expected format without hyphens: 32 hex characters
            validate_hex_string(UUIDString);
        _ ->
            {error,
                {invalid_uuid_format, #{
                    value => UUIDString,
                    reason => invalid_length,
                    expected => [32, 36],
                    actual => Size
                }}}
    end.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @doc Validate hyphenated UUID format (8-4-4-4-12).
-spec validate_hyphenated_format(binary()) -> ok | {error, term()}.
validate_hyphenated_format(<<
    A:8/binary, $-, B:4/binary, $-, C:4/binary, $-, D:4/binary, $-, E:12/binary
>>) ->
    % Check that all segments are valid hex
    case validate_hex_string(<<A/binary, B/binary, C/binary, D/binary, E/binary>>) of
        ok -> ok;
        {error, _} = Error -> Error
    end;
validate_hyphenated_format(UUIDString) ->
    {error,
        {invalid_uuid_format, #{
            value => UUIDString,
            reason => invalid_hyphen_positions,
            expected_format => <<"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx">>
        }}}.

%% @doc Validate that a binary contains only hexadecimal characters.
-spec validate_hex_string(binary()) -> ok | {error, term()}.
validate_hex_string(Binary) ->
    case is_hex_string(Binary) of
        true ->
            ok;
        false ->
            {error,
                {invalid_uuid_format, #{
                    value => Binary,
                    reason => non_hex_characters
                }}}
    end.

%% @doc Check if a binary contains only hexadecimal characters (0-9, a-f, A-F).
-spec is_hex_string(binary()) -> boolean().
is_hex_string(<<>>) ->
    true;
is_hex_string(<<C, Rest/binary>>) when
    (C >= $0 andalso C =< $9) orelse
        (C >= $a andalso C =< $f) orelse
        (C >= $A andalso C =< $F)
->
    is_hex_string(Rest);
is_hex_string(_) ->
    false.

%% @doc Validate that a 16-byte binary is a valid UUID.
-spec validate_uuid_binary(binary()) -> ok | {error, term()}.
validate_uuid_binary(<<_:128>>) ->
    % All 16-byte binaries are valid UUIDs
    ok;
validate_uuid_binary(Binary) ->
    {error,
        {invalid_uuid_binary, #{
            expected_size => 16,
            actual_size => byte_size(Binary)
        }}}.

%%%===================================================================
%%% Column Encoding/Decoding
%%%===================================================================

%% @doc Encode a column of UUID values.
-spec encode_uuid_column([uuid_value()]) -> {ok, iolist()} | {error, term()}.
encode_uuid_column(Values) ->
    encode_column_loop(Values, fun encode_uuid/1, []).

%% @doc Decode a column of UUID values.
-spec decode_uuid_column(binary(), non_neg_integer()) ->
    {ok, [uuid_value()], binary()} | {error, term()}.
decode_uuid_column(Binary, NumRows) ->
    decode_column_loop(Binary, NumRows, fun decode_uuid/1, []).

%%%===================================================================
%%% Internal Helper Functions
%%%===================================================================

%% @doc Helper to encode a column of values using an encoder function.
-spec encode_column_loop([term()], fun((term()) -> {ok, binary()} | {error, term()}), iolist()) ->
    {ok, iolist()} | {error, term()}.
encode_column_loop([], _EncodeFun, Acc) ->
    {ok, lists:reverse(Acc)};
encode_column_loop([Value | Rest], EncodeFun, Acc) ->
    case EncodeFun(Value) of
        {ok, Encoded} ->
            encode_column_loop(Rest, EncodeFun, [Encoded | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Helper to decode a column of values using a decoder function.
-spec decode_column_loop(
    binary(),
    non_neg_integer(),
    fun((binary()) -> {ok, term(), binary()} | {error, term()}),
    [term()]
) ->
    {ok, [term()], binary()} | {error, term()}.
decode_column_loop(Binary, 0, _DecodeFun, Acc) ->
    {ok, lists:reverse(Acc), Binary};
decode_column_loop(Binary, N, DecodeFun, Acc) ->
    case DecodeFun(Binary) of
        {ok, Value, Rest} ->
            decode_column_loop(Rest, N - 1, DecodeFun, [Value | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.
