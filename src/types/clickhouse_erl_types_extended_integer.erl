%% @doc ClickHouse extended integer types encoding and decoding functions.
%%
%% This module provides functions for encoding and decoding extended integer types:
%% - Int128/UInt128 (16 bytes, little-endian)
%% - Int256/UInt256 (32 bytes, little-endian)
%%
%% Type Representations:
%% - All values are represented as plain Erlang integers
%% - Erlang supports arbitrary precision natively
%% - No tuple representation needed
%%
%% Encoding Format:
%% - Int128/UInt128: 16 bytes, little-endian (low 64 bits, high 64 bits)
%% - Int256/UInt256: 32 bytes, little-endian (four 64-bit segments)
%%
%% Range Limits:
%% - Int128: -170141183460469231731687303715884105728 to 170141183460469231731687303715884105727
%% - UInt128: 0 to 340282366920938463463374607431768211455
%% - Int256: -2^255 to 2^255-1
%% - UInt256: 0 to 2^256-1
%%
%% Usage Examples:
%%
%% ```
%% % Encode Int128
%% {ok, Binary} = encode_int128(170141183460469231731687303715884105727).
%% % Binary = <<255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,127>>
%%
%% % Decode Int128
%% {ok, Value, Rest} = decode_int128(Binary).
%% % Value = 170141183460469231731687303715884105727
%%
%% % Encode UInt256
%% {ok, Binary2} = encode_uint256(115792089237316195423570985008687907853269984665640564039457584007913129639935).
%%
%% % Range validation error
%% {error, {value_out_of_range, _}} = encode_int128(170141183460469231731687303715884105728).
%% '''
%%
%% Error Cases:
%% - {value_out_of_range, Details} - Value exceeds type range
%% - {invalid_value, Details} - Non-integer value provided
%% - {truncated_data, Details} - Binary too short for decoding
-module(clickhouse_erl_types_extended_integer).

-include_lib("kernel/include/logger.hrl").

%% Public API
-export([
    % Int128
    encode_int128/1,
    decode_int128/1,
    % UInt128
    encode_uint128/1,
    decode_uint128/1,
    % Int256
    encode_int256/1,
    decode_int256/1,
    % UInt256
    encode_uint256/1,
    decode_uint256/1,
    % Column encoding/decoding
    encode_int128_column/1,
    decode_int128_column/2,
    encode_uint128_column/1,
    decode_uint128_column/2,
    encode_int256_column/1,
    decode_int256_column/2,
    encode_uint256_column/1,
    decode_uint256_column/2
]).

%%%===================================================================
%%% Int128 Encoding/Decoding
%%%===================================================================

%% @doc Encode a signed 128-bit integer (Int128) in little-endian format.
%%
%% Accepts a plain Erlang integer and encodes it as 16 bytes.
%% Returns {ok, Binary} or {error, Reason} tuple.
-spec encode_int128(integer()) -> {ok, binary()} | {error, term()}.
encode_int128(N) when is_integer(N) ->
    % Int128 range: -2^127 to 2^127-1
    Min = -170141183460469231731687303715884105728,
    Max = 170141183460469231731687303715884105727,
    case N >= Min andalso N =< Max of
        true ->
            % Split into low and high 64-bit parts
            Low = N band 16#FFFFFFFFFFFFFFFF,
            High = N bsr 64,
            {ok, <<Low:64/little-signed-integer, High:64/little-signed-integer>>};
        false ->
            {error, {value_out_of_range, #{value => N, min => Min, max => Max, type => int128}}}
    end;
encode_int128(Val) ->
    {error, {invalid_value, #{value => Val, expected_type => integer, type => int128}}}.

%% @doc Decode a signed 128-bit integer (Int128) from little-endian format.
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
%% Always returns a plain Erlang integer.
-spec decode_int128(binary()) -> {ok, integer(), binary()} | {error, term()}.
decode_int128(Binary) when byte_size(Binary) < 16 ->
    {error,
        {truncated_data, #{
            expected_bytes => 16, actual_bytes => byte_size(Binary), type => int128
        }}};
decode_int128(<<Low:64/little-signed-integer, High:64/little-signed-integer, Rest/binary>>) ->
    % Reconstruct the 128-bit value
    % Need to handle sign extension properly
    Value = (High bsl 64) bor (Low band 16#FFFFFFFFFFFFFFFF),
    {ok, Value, Rest}.

%%%===================================================================
%%% UInt128 Encoding/Decoding
%%%===================================================================

%% @doc Encode an unsigned 128-bit integer (UInt128) in little-endian format.
%%
%% Accepts a plain Erlang integer and encodes it as 16 bytes.
%% Returns {ok, Binary} or {error, Reason} tuple.
-spec encode_uint128(non_neg_integer()) -> {ok, binary()} | {error, term()}.
encode_uint128(N) when is_integer(N), N >= 0 ->
    % UInt128 range: 0 to 2^128-1
    Max = 340282366920938463463374607431768211455,
    case N =< Max of
        true ->
            % Split into low and high 64-bit parts
            Low = N band 16#FFFFFFFFFFFFFFFF,
            High = N bsr 64,
            {ok, <<Low:64/little-unsigned-integer, High:64/little-unsigned-integer>>};
        false ->
            {error, {value_out_of_range, #{value => N, min => 0, max => Max, type => uint128}}}
    end;
encode_uint128(Val) ->
    {error, {invalid_value, #{value => Val, expected_type => non_neg_integer, type => uint128}}}.

%% @doc Decode an unsigned 128-bit integer (UInt128) from little-endian format.
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
%% Always returns a plain Erlang integer.
-spec decode_uint128(binary()) -> {ok, non_neg_integer(), binary()} | {error, term()}.
decode_uint128(Binary) when byte_size(Binary) < 16 ->
    {error,
        {truncated_data, #{
            expected_bytes => 16, actual_bytes => byte_size(Binary), type => uint128
        }}};
decode_uint128(<<Low:64/little-unsigned-integer, High:64/little-unsigned-integer, Rest/binary>>) ->
    % Reconstruct the 128-bit value
    Value = (High bsl 64) bor Low,
    {ok, Value, Rest}.

%%%===================================================================
%%% Int256 Encoding/Decoding
%%%===================================================================

%% @doc Encode a signed 256-bit integer (Int256) in little-endian format.
%%
%% Accepts a plain Erlang integer and encodes it as 32 bytes.
%% Returns {ok, Binary} or {error, Reason} tuple.
-spec encode_int256(integer()) -> {ok, binary()} | {error, term()}.
encode_int256(N) when is_integer(N) ->
    % Int256 range: -2^255 to 2^255-1
    Min = -57896044618658097711785492504343953926634992332820282019728792003956564819968,
    Max = 57896044618658097711785492504343953926634992332820282019728792003956564819967,
    case N >= Min andalso N =< Max of
        true ->
            % Split into four 64-bit parts
            P0 = N band 16#FFFFFFFFFFFFFFFF,
            P1 = (N bsr 64) band 16#FFFFFFFFFFFFFFFF,
            P2 = (N bsr 128) band 16#FFFFFFFFFFFFFFFF,
            P3 = N bsr 192,
            {ok,
                <<P0:64/little-signed-integer, P1:64/little-signed-integer,
                    P2:64/little-signed-integer, P3:64/little-signed-integer>>};
        false ->
            {error, {value_out_of_range, #{value => N, min => Min, max => Max, type => int256}}}
    end;
encode_int256(Val) ->
    {error, {invalid_value, #{value => Val, expected_type => integer, type => int256}}}.

%% @doc Decode a signed 256-bit integer (Int256) from little-endian format.
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
%% Always returns a plain Erlang integer.
-spec decode_int256(binary()) -> {ok, integer(), binary()} | {error, term()}.
decode_int256(Binary) when byte_size(Binary) < 32 ->
    {error,
        {truncated_data, #{
            expected_bytes => 32, actual_bytes => byte_size(Binary), type => int256
        }}};
decode_int256(
    <<P0:64/little-signed-integer, P1:64/little-signed-integer, P2:64/little-signed-integer,
        P3:64/little-signed-integer, Rest/binary>>
) ->
    % Reconstruct the 256-bit value
    Value =
        (P3 bsl 192) bor
            ((P2 band 16#FFFFFFFFFFFFFFFF) bsl 128) bor
            ((P1 band 16#FFFFFFFFFFFFFFFF) bsl 64) bor
            (P0 band 16#FFFFFFFFFFFFFFFF),
    {ok, Value, Rest}.

%%%===================================================================
%%% UInt256 Encoding/Decoding
%%%===================================================================

%% @doc Encode an unsigned 256-bit integer (UInt256) in little-endian format.
%%
%% Accepts a plain Erlang integer and encodes it as 32 bytes.
%% Returns {ok, Binary} or {error, Reason} tuple.
-spec encode_uint256(non_neg_integer()) -> {ok, binary()} | {error, term()}.
encode_uint256(N) when is_integer(N), N >= 0 ->
    % UInt256 range: 0 to 2^256-1
    Max = 115792089237316195423570985008687907853269984665640564039457584007913129639935,
    case N =< Max of
        true ->
            % Split into four 64-bit parts
            P0 = N band 16#FFFFFFFFFFFFFFFF,
            P1 = (N bsr 64) band 16#FFFFFFFFFFFFFFFF,
            P2 = (N bsr 128) band 16#FFFFFFFFFFFFFFFF,
            P3 = N bsr 192,
            {ok,
                <<P0:64/little-unsigned-integer, P1:64/little-unsigned-integer,
                    P2:64/little-unsigned-integer, P3:64/little-unsigned-integer>>};
        false ->
            {error, {value_out_of_range, #{value => N, min => 0, max => Max, type => uint256}}}
    end;
encode_uint256(Val) ->
    {error, {invalid_value, #{value => Val, expected_type => non_neg_integer, type => uint256}}}.

%% @doc Decode an unsigned 256-bit integer (UInt256) from little-endian format.
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
%% Always returns a plain Erlang integer.
-spec decode_uint256(binary()) -> {ok, non_neg_integer(), binary()} | {error, term()}.
decode_uint256(Binary) when byte_size(Binary) < 32 ->
    {error,
        {truncated_data, #{
            expected_bytes => 32, actual_bytes => byte_size(Binary), type => uint256
        }}};
decode_uint256(
    <<P0:64/little-unsigned-integer, P1:64/little-unsigned-integer, P2:64/little-unsigned-integer,
        P3:64/little-unsigned-integer, Rest/binary>>
) ->
    % Reconstruct the 256-bit value
    Value =
        (P3 bsl 192) bor
            (P2 bsl 128) bor
            (P1 bsl 64) bor
            P0,
    {ok, Value, Rest}.

%%%===================================================================
%%% Column Encoding/Decoding
%%%===================================================================

%% @doc Encode a column of Int128 values.
-spec encode_int128_column([integer()]) -> {ok, iolist()} | {error, term()}.
encode_int128_column(Values) ->
    encode_column_loop(Values, fun encode_int128/1, []).

%% @doc Decode a column of Int128 values.
-spec decode_int128_column(binary(), non_neg_integer()) ->
    {ok, [integer()], binary()} | {error, term()}.
decode_int128_column(Binary, NumRows) ->
    decode_column_loop(Binary, NumRows, fun decode_int128/1, []).

%% @doc Encode a column of UInt128 values.
-spec encode_uint128_column([non_neg_integer()]) -> {ok, iolist()} | {error, term()}.
encode_uint128_column(Values) ->
    encode_column_loop(Values, fun encode_uint128/1, []).

%% @doc Decode a column of UInt128 values.
-spec decode_uint128_column(binary(), non_neg_integer()) ->
    {ok, [non_neg_integer()], binary()} | {error, term()}.
decode_uint128_column(Binary, NumRows) ->
    decode_column_loop(Binary, NumRows, fun decode_uint128/1, []).

%% @doc Encode a column of Int256 values.
-spec encode_int256_column([integer()]) -> {ok, iolist()} | {error, term()}.
encode_int256_column(Values) ->
    encode_column_loop(Values, fun encode_int256/1, []).

%% @doc Decode a column of Int256 values.
-spec decode_int256_column(binary(), non_neg_integer()) ->
    {ok, [integer()], binary()} | {error, term()}.
decode_int256_column(Binary, NumRows) ->
    decode_column_loop(Binary, NumRows, fun decode_int256/1, []).

%% @doc Encode a column of UInt256 values.
-spec encode_uint256_column([non_neg_integer()]) -> {ok, iolist()} | {error, term()}.
encode_uint256_column(Values) ->
    encode_column_loop(Values, fun encode_uint256/1, []).

%% @doc Decode a column of UInt256 values.
-spec decode_uint256_column(binary(), non_neg_integer()) ->
    {ok, [non_neg_integer()], binary()} | {error, term()}.
decode_uint256_column(Binary, NumRows) ->
    decode_column_loop(Binary, NumRows, fun decode_uint256/1, []).

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
