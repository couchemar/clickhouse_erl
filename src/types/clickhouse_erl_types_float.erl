%% @doc ClickHouse floating point types encoding and decoding functions.
%%
%% This module provides functions for encoding and decoding floating point types:
%% - Float32 (32-bit IEEE 754)
%% - Float64 (64-bit IEEE 754)
-module(clickhouse_erl_types_float).

-include_lib("kernel/include/logger.hrl").

%% Public API
-export([
    encode_float32/1,
    decode_float32/1,
    encode_float64/1,
    decode_float64/1
]).

%%%===================================================================
%%% Floating Point Encoding/Decoding
%%%===================================================================

%% @doc Encode a 32-bit floating point number (Float32) in little-endian format.
%%
%% Returns a 4-byte binary or error tuple.
%% Handles 'infinity', '-infinity', and 'nan' atoms.
-spec encode_float32(float() | integer() | infinity | '-infinity' | nan) ->
    binary() | {error, term()}.
encode_float32(infinity) ->
    <<0, 0, 128, 127>>;
encode_float32('-infinity') ->
    <<0, 0, 128, 255>>;
encode_float32(nan) ->
    <<0, 0, 192, 127>>;
encode_float32(N) when is_float(N); is_integer(N) ->
    <<N:32/little-float>>;
encode_float32(N) ->
    {error,
        {invalid_value, #{
            value => N,
            expected_type => 'float32 | integer | infinity | -infinity | nan',
            type => float32
        }}}.

%% @doc Decode a 32-bit floating point number (Float32) from little-endian format.
%%
%% Returns {ok, Float, Rest} on success or {error, Reason} on failure.
-spec decode_float32(binary()) -> {ok, float() | atom(), binary()} | {error, term()}.
decode_float32(Binary) when byte_size(Binary) < 4 ->
    {error,
        {truncated_data, #{
            expected_bytes => 4, actual_bytes => byte_size(Binary), type => float32
        }}};
decode_float32(<<Int:32/little-unsigned-integer, Rest/binary>>) ->
    case Int of
        16#7F800000 ->
            {ok, infinity, Rest};
        16#FF800000 ->
            {ok, '-infinity', Rest};
        _ when (Int band 16#7F800000) =:= 16#7F800000, (Int band 16#007FFFFF) /= 0 ->
            {ok, nan, Rest};
        _ ->
            <<Float:32/little-float>> = <<Int:32/little-unsigned-integer>>,
            {ok, Float, Rest}
    end.

%% @doc Encode a 64-bit floating point number (Float64) in little-endian format.
%%
%% Returns an 8-byte binary or error tuple.
%% Handles 'infinity', '-infinity', and 'nan' atoms.
-spec encode_float64(float() | integer() | infinity | '-infinity' | nan) ->
    binary() | {error, term()}.
encode_float64(infinity) ->
    <<0, 0, 0, 0, 0, 0, 240, 127>>;
encode_float64('-infinity') ->
    <<0, 0, 0, 0, 0, 0, 240, 255>>;
encode_float64(nan) ->
    <<0, 0, 0, 0, 0, 0, 248, 127>>;
encode_float64(N) when is_float(N); is_integer(N) ->
    <<N:64/little-float>>;
encode_float64(N) ->
    {error,
        {invalid_value, #{
            value => N,
            expected_type => 'float64 | integer | infinity | -infinity | nan',
            type => float64
        }}}.

%% @doc Decode a 64-bit floating point number (Float64) from little-endian format.
%%
%% Returns {ok, Float, Rest} on success or {error, Reason} on failure.
-spec decode_float64(binary()) -> {ok, float() | atom(), binary()} | {error, term()}.
decode_float64(Binary) when byte_size(Binary) < 8 ->
    {error,
        {truncated_data, #{
            expected_bytes => 8, actual_bytes => byte_size(Binary), type => float64
        }}};
decode_float64(<<Int:64/little-unsigned-integer, Rest/binary>>) ->
    case Int of
        16#7FF0000000000000 ->
            {ok, infinity, Rest};
        16#FFF0000000000000 ->
            {ok, '-infinity', Rest};
        _ when
            (Int band 16#7FF0000000000000) =:= 16#7FF0000000000000,
            (Int band 16#000FFFFFFFFFFFFF) /= 0
        ->
            {ok, nan, Rest};
        _ ->
            <<Float:64/little-float>> = <<Int:64/little-unsigned-integer>>,
            {ok, Float, Rest}
    end.
