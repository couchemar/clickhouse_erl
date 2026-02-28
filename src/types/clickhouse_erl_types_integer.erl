%% @doc ClickHouse integer and boolean types encoding and decoding functions.
%%
%% This module provides functions for encoding and decoding integer types:
%% - Unsigned integers (UInt8/16/32/64)
%% - Signed integers (Int8/16/32/64)
%% - Boolean values (Bool)
-module(clickhouse_erl_types_integer).

-include_lib("kernel/include/logger.hrl").

%% Public API
-export([
    % Unsigned integers
    encode_uint8/1,
    decode_uint8/1,
    encode_uint16/1,
    decode_uint16/1,
    encode_uint32/1,
    decode_uint32/1,
    encode_uint64_internal/1,
    % Signed integers
    encode_int8/1,
    decode_int8/1,
    encode_int16/1,
    decode_int16/1,
    encode_int32/1,
    decode_int32/1,
    encode_int64/1,
    decode_int64/1,
    % Boolean
    encode_bool/1,
    decode_bool/1,
    check_bool/1
]).

%%%===================================================================
%%% Unsigned Integer Encoding/Decoding
%%%===================================================================

%% @doc Encode an unsigned 8-bit integer (UInt8).
%%
%% Returns a single byte binary or error tuple.
-spec encode_uint8(non_neg_integer()) -> binary() | {error, term()}.
encode_uint8(N) when is_integer(N), N >= 0, N =< 255 ->
    <<N:8>>;
encode_uint8(N) ->
    {error, {value_out_of_range, #{value => N, min => 0, max => 255, type => uint8}}}.

%% @doc Decode an unsigned 8-bit integer (UInt8).
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
-spec decode_uint8(binary()) -> {ok, non_neg_integer(), binary()} | {error, term()}.
decode_uint8(<<>>) ->
    {error, {truncated_data, #{expected_bytes => 1, actual_bytes => 0, type => uint8}}};
decode_uint8(<<Byte:8, Rest/binary>>) ->
    {ok, Byte, Rest}.

%% @doc Encode an unsigned 16-bit integer (UInt16) in little-endian format.
%%
%% Returns a 2-byte binary or error tuple.
-spec encode_uint16(non_neg_integer()) -> binary() | {error, term()}.
encode_uint16(N) when is_integer(N), N >= 0, N =< 65535 ->
    <<N:16/little-unsigned-integer>>;
encode_uint16(N) ->
    {error, {value_out_of_range, #{value => N, min => 0, max => 65535, type => uint16}}}.

%% @doc Decode an unsigned 16-bit integer (UInt16) from little-endian format.
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
-spec decode_uint16(binary()) -> {ok, non_neg_integer(), binary()} | {error, term()}.
decode_uint16(Binary) when byte_size(Binary) < 2 ->
    {error,
        {truncated_data, #{
            expected_bytes => 2, actual_bytes => byte_size(Binary), type => uint16
        }}};
decode_uint16(<<Value:16/little-unsigned-integer, Rest/binary>>) ->
    {ok, Value, Rest}.

%% @doc Encode an unsigned 32-bit integer (UInt32) in little-endian format.
%%
%% Returns a 4-byte binary or error tuple.
-spec encode_uint32(non_neg_integer()) -> binary() | {error, term()}.
encode_uint32(N) when is_integer(N), N >= 0, N =< 4294967295 ->
    <<N:32/little-unsigned-integer>>;
encode_uint32(N) ->
    {error, {value_out_of_range, #{value => N, min => 0, max => 4294967295, type => uint32}}}.

%% @doc Decode an unsigned 32-bit integer (UInt32) from little-endian format.
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
-spec decode_uint32(binary()) -> {ok, non_neg_integer(), binary()} | {error, term()}.
decode_uint32(Binary) when byte_size(Binary) < 4 ->
    {error,
        {truncated_data, #{
            expected_bytes => 4, actual_bytes => byte_size(Binary), type => uint32
        }}};
decode_uint32(<<Value:32/little-unsigned-integer, Rest/binary>>) ->
    {ok, Value, Rest}.

%% @doc Encode an unsigned 64-bit integer (UInt64) in little-endian format.
%%
%% This is an internal function used by column encoders.
%% Returns an 8-byte binary or error tuple.
-spec encode_uint64_internal(non_neg_integer()) -> binary() | {error, term()}.
encode_uint64_internal(N) when is_integer(N), N >= 0, N =< 18446744073709551615 ->
    <<N:64/little-unsigned-integer>>;
encode_uint64_internal(N) ->
    {error, {value_out_of_range, #{value => N, type => uint64}}}.

%%%===================================================================
%%% Signed Integer Encoding/Decoding
%%%===================================================================

%% @doc Encode a signed 8-bit integer (Int8).
%%
%% Returns a single byte binary or error tuple.
-spec encode_int8(integer()) -> binary() | {error, term()}.
encode_int8(N) when is_integer(N), N >= -128, N =< 127 ->
    <<N:8/signed-integer>>;
encode_int8(N) ->
    {error, {value_out_of_range, #{value => N, min => -128, max => 127, type => int8}}}.

%% @doc Decode a signed 8-bit integer (Int8).
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
-spec decode_int8(binary()) -> {ok, integer(), binary()} | {error, term()}.
decode_int8(<<>>) ->
    {error, {truncated_data, #{expected_bytes => 1, actual_bytes => 0, type => int8}}};
decode_int8(<<Value:8/signed-integer, Rest/binary>>) ->
    {ok, Value, Rest}.

%% @doc Encode a signed 16-bit integer (Int16) in little-endian format.
%%
%% Returns a 2-byte binary or error tuple.
-spec encode_int16(integer()) -> binary() | {error, term()}.
encode_int16(N) when is_integer(N), N >= -32768, N =< 32767 ->
    <<N:16/little-signed-integer>>;
encode_int16(N) ->
    {error, {value_out_of_range, #{value => N, min => -32768, max => 32767, type => int16}}}.

%% @doc Decode a signed 16-bit integer (Int16) from little-endian format.
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
-spec decode_int16(binary()) -> {ok, integer(), binary()} | {error, term()}.
decode_int16(Binary) when byte_size(Binary) < 2 ->
    {error,
        {truncated_data, #{expected_bytes => 2, actual_bytes => byte_size(Binary), type => int16}}};
decode_int16(<<Value:16/little-signed-integer, Rest/binary>>) ->
    {ok, Value, Rest}.

%% @doc Encode a signed 32-bit integer (Int32) in little-endian format.
%%
%% Returns a 4-byte binary or error tuple.
-spec encode_int32(integer()) -> binary() | {error, term()}.
encode_int32(N) when is_integer(N), N >= -2147483648, N =< 2147483647 ->
    <<N:32/little-signed-integer>>;
encode_int32(N) ->
    {error,
        {value_out_of_range, #{value => N, min => -2147483648, max => 2147483647, type => int32}}}.

%% @doc Decode a signed 32-bit integer (Int32) from little-endian format.
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
-spec decode_int32(binary()) -> {ok, integer(), binary()} | {error, term()}.
decode_int32(Binary) when byte_size(Binary) < 4 ->
    {error,
        {truncated_data, #{expected_bytes => 4, actual_bytes => byte_size(Binary), type => int32}}};
decode_int32(<<Value:32/little-signed-integer, Rest/binary>>) ->
    {ok, Value, Rest}.

%% @doc Encode a signed 64-bit integer (Int64) in little-endian format.
%%
%% Returns an 8-byte binary or error tuple.
-spec encode_int64(integer()) -> binary() | {error, term()}.
encode_int64(N) when is_integer(N), N >= -9223372036854775808, N =< 9223372036854775807 ->
    <<N:64/little-signed-integer>>;
encode_int64(N) ->
    {error,
        {value_out_of_range, #{
            value => N, min => -9223372036854775808, max => 9223372036854775807, type => int64
        }}}.

%% @doc Decode a signed 64-bit integer (Int64) from little-endian format.
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
-spec decode_int64(binary()) -> {ok, integer(), binary()} | {error, term()}.
decode_int64(Binary) when byte_size(Binary) < 8 ->
    {error,
        {truncated_data, #{expected_bytes => 8, actual_bytes => byte_size(Binary), type => int64}}};
decode_int64(<<Value:64/little-signed-integer, Rest/binary>>) ->
    {ok, Value, Rest}.

%%%===================================================================
%%% Boolean Encoding/Decoding
%%%===================================================================

%% @doc Encode a boolean (Bool).
%%
%% Returns a single byte binary (1 for true, 0 for false) or error tuple.
-spec encode_bool(boolean()) -> binary() | {error, term()}.
encode_bool(true) ->
    <<1>>;
encode_bool(false) ->
    <<0>>;
encode_bool(Val) ->
    {error, {invalid_value, #{value => Val, expected_type => boolean, type => bool}}}.

%% @doc Decode a boolean (Bool).
%%
%% Returns {ok, Boolean, Rest} on success or {error, Reason} on failure.
-spec decode_bool(binary()) -> {ok, boolean(), binary()} | {error, term()}.
decode_bool(Binary) ->
    maybe
        {ok, Bool0, Rest} ?= decode_uint8(Binary),
        {ok, Bool} ?= check_bool(Bool0),
        {ok, Bool, Rest}
    else
        {error, {truncated_data, _}} ->
            {error,
                {truncated_data, #{
                    expected_bytes => 1, actual_bytes => byte_size(Binary), type => bool
                }}};
        Error ->
            Error
    end.

%% @doc Check if an integer value is a valid boolean (0 or 1).
%%
%% Returns {ok, Boolean} or {error, Reason}.
-spec check_bool(non_neg_integer()) -> {ok, boolean()} | {error, term()}.
check_bool(Bool) ->
    case Bool of
        0 -> {ok, false};
        1 -> {ok, true};
        _ -> {error, {invalid_bool_value, #{value => Bool, expected_values => [0, 1]}}}
    end.
