%% @doc ClickHouse primitive protocol types encoding and decoding functions.
%%
%% This module provides functions for encoding and decoding protocol-level primitives:
%% - Variable-length integers (varint)
%% - Strings (UTF-8 with varint length prefix)
%% - Utility functions
%%
%% For integer types, see clickhouse_erl_types_integer.
%% For floating point types, see clickhouse_erl_types_float.
-module(clickhouse_erl_types_primitive).

-include_lib("kernel/include/logger.hrl").

%% Public API
-export([
    % Varint
    encode_varint/1,
    decode_varint/1,
    % String
    encode_string/1,
    decode_string/1,
    decode_string/2,
    % Utilities
    to_binary/1
]).

%%%===================================================================
%%% Varint Encoding/Decoding
%%%===================================================================

%% @doc Encode an unsigned variable-length integer (UVarInt).
%%
%% Uses the same encoding as Go's binary.PutUvarint function.
%% Each byte encodes 7 bits of data and 1 continuation bit.
-spec encode_varint(non_neg_integer()) -> binary().
encode_varint(N) when N < 128 ->
    <<N>>;
encode_varint(N) ->
    <<(N band 127 bor 128), (encode_varint(N bsr 7))/binary>>.

%% @doc Decode an unsigned variable-length integer (UVarInt).
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
-spec decode_varint(binary()) -> {ok, non_neg_integer(), binary()} | {error, term()}.
decode_varint(Binary) ->
    decode_varint(Binary, 0, 0).

%% Internal helper for varint decoding
-spec decode_varint(binary(), non_neg_integer(), non_neg_integer()) ->
    {ok, non_neg_integer(), binary()} | {error, term()}.
decode_varint(<<>>, _Acc, _Shift) ->
    {error, {truncated_data, #{type => varint, reason => incomplete_varint}}};
decode_varint(<<Byte, Rest/binary>>, Acc, Shift) when Shift < 64 ->
    Value = Byte band 127,
    NewAcc = Acc bor (Value bsl Shift),
    case Byte band 128 of
        0 -> {ok, NewAcc, Rest};
        _ -> decode_varint(Rest, NewAcc, Shift + 7)
    end;
decode_varint(_, _Acc, _Shift) ->
    {error, {varint_overflow, #{reason => varint_too_large}}}.

%%%===================================================================
%%% String Encoding/Decoding
%%%===================================================================

%% @doc Encode a string using ClickHouse protocol format.
%%
%% Format: UVarInt length + UTF-8 bytes
%% Returns a binary or error tuple.
-spec encode_string(string() | binary()) -> binary() | {error, term()}.
encode_string(String) ->
    try
        Utf8Bytes = to_binary(String),
        Length = byte_size(Utf8Bytes),
        LengthBinary = encode_varint(Length),
        <<LengthBinary/binary, Utf8Bytes/binary>>
    catch
        _:_ ->
            {error,
                {invalid_value, #{
                    value => String, expected_type => 'string | binary', type => string
                }}}
    end.

%% @doc Decode a string from ClickHouse protocol format.
%%
%% Returns {ok, String, Rest} on success or {error, Reason} on failure.
-spec decode_string(binary()) -> {ok, binary(), binary()} | {error, term()}.
decode_string(Binary) ->
    %% Use a very large default limit (1GB) for backward compatibility
    decode_string(Binary, 1073741824).

%% @doc Decode a string from ClickHouse protocol format with a maximum length limit.
%%
%% Returns {ok, String, Rest} on success.
%% Returns {error, {string_too_long, Length, MaxLength}} if the string exceeds the limit.
%% Returns {error, Reason} on other failures.
-spec decode_string(binary(), non_neg_integer()) -> {ok, binary(), binary()} | {error, term()}.
decode_string(Binary, MaxLength) ->
    maybe
        {ok, Length, Rest} ?= decode_varint(Binary),
        ok ?= check_string_length(Length, MaxLength),
        {ok, {StringBytes, Remaining}} ?= extract_string_bytes(Rest, Length),
        {ok, ValidString} ?= validate_string_encoding(StringBytes),
        {ok, ValidString, Remaining}
    end.

-spec check_string_length(non_neg_integer(), non_neg_integer()) -> ok | {error, term()}.
check_string_length(Length, MaxLength) ->
    case Length > MaxLength of
        true -> {error, {string_too_long, #{length => Length, max_length => MaxLength}}};
        false -> ok
    end.

-spec extract_string_bytes(binary(), non_neg_integer()) ->
    {ok, {binary(), binary()}} | {error, term()}.
extract_string_bytes(Rest, Length) ->
    case byte_size(Rest) >= Length of
        true ->
            <<StringBytes:Length/binary, Remaining/binary>> = Rest,
            {ok, {StringBytes, Remaining}};
        false ->
            {error,
                {truncated_data, #{
                    expected_bytes => Length,
                    actual_bytes => byte_size(Rest),
                    type => string
                }}}
    end.

-spec validate_string_encoding(binary()) -> {ok, binary()} | {error, term()}.
validate_string_encoding(StringBytes) ->
    case unicode:characters_to_binary(StringBytes, utf8) of
        {error, _, _} ->
            {error,
                {invalid_encoding, #{
                    encoding => utf8, reason => invalid_utf8
                }}};
        {incomplete, _, _} ->
            {error,
                {invalid_encoding, #{
                    encoding => utf8, reason => incomplete_utf8
                }}};
        ValidString ->
            {ok, ValidString}
    end.

%%%===================================================================
%%% Utility Functions
%%%===================================================================

%% @doc Convert a string or binary to a binary.
-spec to_binary(string() | binary()) -> binary().
to_binary(B) when is_binary(B) -> B;
to_binary(L) when is_list(L) -> unicode:characters_to_binary(L);
to_binary(A) when is_atom(A) -> atom_to_binary(A).
