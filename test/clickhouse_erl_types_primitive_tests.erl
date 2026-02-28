%% @doc Tests for ClickHouse primitive type encoding/decoding functions.
%%
%% This module contains tests for the clickhouse_erl_types_primitive module.
-module(clickhouse_erl_types_primitive_tests).

-include_lib("eunit/include/eunit.hrl").

%% ============================================================================
%% Varint Tests
%% ============================================================================

%% Test zero varint encoding/decoding
zero_varint_test() ->
    ZeroVarInt = 0,
    EncodedBinary = clickhouse_erl_types_primitive:encode_varint(ZeroVarInt),
    ?assert(is_binary(EncodedBinary)),
    {ok, DecodedVarInt, <<>>} = clickhouse_erl_types_primitive:decode_varint(EncodedBinary),
    ?assertEqual(ZeroVarInt, DecodedVarInt).

%% Test maximum safe varint encoding/decoding
max_varint_test() ->
    MaxVarInt = 16#7FFFFFFFFFFFFFFF,
    EncodedBinary = clickhouse_erl_types_primitive:encode_varint(MaxVarInt),
    ?assert(is_binary(EncodedBinary)),
    {ok, DecodedVarInt, <<>>} = clickhouse_erl_types_primitive:decode_varint(EncodedBinary),
    ?assertEqual(MaxVarInt, DecodedVarInt).

%% Test varint with remaining data
varint_with_remaining_data_test() ->
    VarInt = 42,
    RemainingData = <<"extra_data">>,
    EncodedVarInt = clickhouse_erl_types_primitive:encode_varint(VarInt),
    BinaryWithExtra = <<EncodedVarInt/binary, RemainingData/binary>>,
    {ok, DecodedVarInt, Rest} = clickhouse_erl_types_primitive:decode_varint(BinaryWithExtra),
    ?assertEqual(VarInt, DecodedVarInt),
    ?assertEqual(RemainingData, Rest).

%% Test truncated varint
truncated_varint_test() ->
    %% Incomplete varint (continuation bit set but no following byte)
    TruncatedVarInt = <<128>>,
    Result = clickhouse_erl_types_primitive:decode_varint(TruncatedVarInt),
    ?assertMatch({error, _}, Result).

%% Test empty binary for varint
empty_binary_varint_test() ->
    Result = clickhouse_erl_types_primitive:decode_varint(<<>>),
    ?assertMatch({error, _}, Result).

%% ============================================================================
%% UInt8 Tests
%% ============================================================================

%% Test UInt8 encoding
encode_uint8_test() ->
    ?assertEqual(<<0>>, clickhouse_erl_types_integer:encode_uint8(0)),
    ?assertEqual(<<1>>, clickhouse_erl_types_integer:encode_uint8(1)),
    ?assertEqual(<<127>>, clickhouse_erl_types_integer:encode_uint8(127)),
    ?assertEqual(<<128>>, clickhouse_erl_types_integer:encode_uint8(128)),
    ?assertEqual(<<255>>, clickhouse_erl_types_integer:encode_uint8(255)).

%% Test UInt8 decoding
decode_uint8_test() ->
    ?assertEqual({ok, 0, <<>>}, clickhouse_erl_types_integer:decode_uint8(<<0>>)),
    ?assertEqual({ok, 1, <<>>}, clickhouse_erl_types_integer:decode_uint8(<<1>>)),
    ?assertEqual({ok, 127, <<>>}, clickhouse_erl_types_integer:decode_uint8(<<127>>)),
    ?assertEqual({ok, 128, <<>>}, clickhouse_erl_types_integer:decode_uint8(<<128>>)),
    ?assertEqual({ok, 255, <<>>}, clickhouse_erl_types_integer:decode_uint8(<<255>>)).

%% Test UInt8 round trip
uint8_round_trip_test() ->
    lists:foreach(
        fun(N) ->
            Encoded = clickhouse_erl_types_integer:encode_uint8(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_uint8(Encoded),
            ?assertEqual(N, Decoded)
        end,
        lists:seq(0, 255)
    ).

%% Test UInt8 with remaining data
uint8_with_remaining_data_test() ->
    Binary = <<42, "extra_data">>,
    {ok, Value, Rest} = clickhouse_erl_types_integer:decode_uint8(Binary),
    ?assertEqual(42, Value),
    ?assertEqual(<<"extra_data">>, Rest).

%% Test UInt8 decode empty binary
decode_uint8_empty_test() ->
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_uint8(<<>>)).

%% Test UInt8 encode negative value
encode_uint8_negative_test() ->
    ?assertMatch({error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint8(-1)),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint8(-128)
    ).

%% Test UInt8 encode value too large
encode_uint8_too_large_test() ->
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint8(256)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint8(1000)
    ).

%% ============================================================================
%% UInt16 Tests
%% ============================================================================

%% Test UInt16 encoding
encode_uint16_test() ->
    ?assertEqual(<<0, 0>>, clickhouse_erl_types_integer:encode_uint16(0)),
    ?assertEqual(<<1, 0>>, clickhouse_erl_types_integer:encode_uint16(1)),
    ?assertEqual(<<255, 0>>, clickhouse_erl_types_integer:encode_uint16(255)),
    ?assertEqual(<<0, 1>>, clickhouse_erl_types_integer:encode_uint16(256)),
    ?assertEqual(<<255, 255>>, clickhouse_erl_types_integer:encode_uint16(65535)).

%% Test UInt16 decoding
decode_uint16_test() ->
    ?assertEqual({ok, 0, <<>>}, clickhouse_erl_types_integer:decode_uint16(<<0, 0>>)),
    ?assertEqual({ok, 1, <<>>}, clickhouse_erl_types_integer:decode_uint16(<<1, 0>>)),
    ?assertEqual({ok, 255, <<>>}, clickhouse_erl_types_integer:decode_uint16(<<255, 0>>)),
    ?assertEqual({ok, 256, <<>>}, clickhouse_erl_types_integer:decode_uint16(<<0, 1>>)),
    ?assertEqual({ok, 65535, <<>>}, clickhouse_erl_types_integer:decode_uint16(<<255, 255>>)).

%% Test UInt16 round trip
uint16_round_trip_test() ->
    TestValues = [0, 1, 255, 256, 32767, 32768, 65535],
    lists:foreach(
        fun(N) ->
            Encoded = clickhouse_erl_types_integer:encode_uint16(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_uint16(Encoded),
            ?assertEqual(N, Decoded)
        end,
        TestValues
    ).

%% Test UInt16 validation
encode_uint16_validation_test() ->
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint16(-1)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint16(65536)
    ).

%% Test UInt16 validation for truncated binary
decode_uint16_truncated_test() ->
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_uint16(<<1>>)).

%% ============================================================================
%% UInt32 Tests
%% ============================================================================

%% Test UInt32 encoding
encode_uint32_test() ->
    ?assertEqual(<<0, 0, 0, 0>>, clickhouse_erl_types_integer:encode_uint32(0)),
    ?assertEqual(<<1, 0, 0, 0>>, clickhouse_erl_types_integer:encode_uint32(1)),
    ?assertEqual(<<255, 255, 255, 255>>, clickhouse_erl_types_integer:encode_uint32(4294967295)).

%% Test UInt32 decoding
decode_uint32_test() ->
    ?assertEqual({ok, 0, <<>>}, clickhouse_erl_types_integer:decode_uint32(<<0, 0, 0, 0>>)),
    ?assertEqual({ok, 1, <<>>}, clickhouse_erl_types_integer:decode_uint32(<<1, 0, 0, 0>>)),
    ?assertEqual(
        {ok, 4294967295, <<>>}, clickhouse_erl_types_integer:decode_uint32(<<255, 255, 255, 255>>)
    ).

%% Test UInt32 round trip
uint32_round_trip_test() ->
    %% Debugging specific failing value
    ?assertEqual(<<192, 137, 12, 94>>, clickhouse_erl_types_integer:encode_uint32(1577880000)),

    TestValues = [0, 1, 65535, 65536, 4294967295],
    lists:foreach(
        fun(N) ->
            Encoded = clickhouse_erl_types_integer:encode_uint32(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_uint32(Encoded),
            ?assertEqual(N, Decoded)
        end,
        TestValues
    ).

%% Test UInt32 validation
encode_uint32_validation_test() ->
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint32(-1)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint32(4294967296)
    ).

%% Test UInt32 truncated validation
decode_uint32_truncated_test() ->
    ?assertMatch(
        {error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_uint32(<<1, 2, 3>>)
    ).

%% ============================================================================
%% Int8 Tests
%% ============================================================================

%% Test Int8 encoding
encode_int8_test() ->
    ?assertEqual(<<0>>, clickhouse_erl_types_integer:encode_int8(0)),
    ?assertEqual(<<1>>, clickhouse_erl_types_integer:encode_int8(1)),
    ?assertEqual(<<127>>, clickhouse_erl_types_integer:encode_int8(127)),
    ?assertEqual(<<128>>, clickhouse_erl_types_integer:encode_int8(-128)),
    ?assertEqual(<<255>>, clickhouse_erl_types_integer:encode_int8(-1)).

%% Test Int8 decoding
decode_int8_test() ->
    ?assertEqual({ok, 0, <<>>}, clickhouse_erl_types_integer:decode_int8(<<0>>)),
    ?assertEqual({ok, 1, <<>>}, clickhouse_erl_types_integer:decode_int8(<<1>>)),
    ?assertEqual({ok, 127, <<>>}, clickhouse_erl_types_integer:decode_int8(<<127>>)),
    ?assertEqual({ok, -128, <<>>}, clickhouse_erl_types_integer:decode_int8(<<128>>)),
    ?assertEqual({ok, -1, <<>>}, clickhouse_erl_types_integer:decode_int8(<<255>>)).

%% Test Int8 round trip
int8_round_trip_test() ->
    lists:foreach(
        fun(N) ->
            Encoded = clickhouse_erl_types_integer:encode_int8(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_int8(Encoded),
            ?assertEqual(N, Decoded)
        end,
        lists:seq(-128, 127)
    ).

%% Test Int8 validation
encode_int8_validation_test() ->
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int8(-129)
    ),
    ?assertMatch({error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int8(128)).

%% Test Int8 truncated validation
decode_int8_truncated_test() ->
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_int8(<<>>)).

%% ============================================================================
%% Int16 Tests
%% ============================================================================

%% Test Int16 encoding
encode_int16_test() ->
    ?assertEqual(<<0, 0>>, clickhouse_erl_types_integer:encode_int16(0)),
    ?assertEqual(<<1, 0>>, clickhouse_erl_types_integer:encode_int16(1)),
    ?assertEqual(<<255, 127>>, clickhouse_erl_types_integer:encode_int16(32767)),
    ?assertEqual(<<0, 128>>, clickhouse_erl_types_integer:encode_int16(-32768)),
    ?assertEqual(<<255, 255>>, clickhouse_erl_types_integer:encode_int16(-1)).

%% Test Int16 decoding
decode_int16_test() ->
    ?assertEqual({ok, 0, <<>>}, clickhouse_erl_types_integer:decode_int16(<<0, 0>>)),
    ?assertEqual({ok, 1, <<>>}, clickhouse_erl_types_integer:decode_int16(<<1, 0>>)),
    ?assertEqual({ok, 32767, <<>>}, clickhouse_erl_types_integer:decode_int16(<<255, 127>>)),
    ?assertEqual({ok, -32768, <<>>}, clickhouse_erl_types_integer:decode_int16(<<0, 128>>)),
    ?assertEqual({ok, -1, <<>>}, clickhouse_erl_types_integer:decode_int16(<<255, 255>>)).

%% Test Int16 round trip
int16_round_trip_test() ->
    TestValues = [0, 1, -1, 127, -128, 32767, -32768],
    lists:foreach(
        fun(N) ->
            Encoded = clickhouse_erl_types_integer:encode_int16(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_int16(Encoded),
            ?assertEqual(N, Decoded)
        end,
        TestValues
    ).

%% Test Int16 validation
encode_int16_validation_test() ->
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int16(-32769)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int16(32768)
    ).

%% Test Int16 truncated validation
decode_int16_truncated_test() ->
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_int16(<<1>>)).

%% ============================================================================
%% Int32 Tests
%% ============================================================================

%% Test Int32 encoding
encode_int32_test() ->
    ?assertEqual(<<0, 0, 0, 0>>, clickhouse_erl_types_integer:encode_int32(0)),
    ?assertEqual(<<1, 0, 0, 0>>, clickhouse_erl_types_integer:encode_int32(1)),
    ?assertEqual(<<255, 255, 255, 255>>, clickhouse_erl_types_integer:encode_int32(-1)),
    ?assertEqual(<<255, 127, 0, 0>>, clickhouse_erl_types_integer:encode_int32(32767)),
    ?assertEqual(
        <<1, 128, 255, 255>>, clickhouse_erl_types_integer:encode_int32(-32767)
    ).

%% Test Int32 decoding
decode_int32_test() ->
    ?assertEqual({ok, 0, <<>>}, clickhouse_erl_types_integer:decode_int32(<<0, 0, 0, 0>>)),
    ?assertEqual({ok, 1, <<>>}, clickhouse_erl_types_integer:decode_int32(<<1, 0, 0, 0>>)),
    ?assertEqual(
        {ok, -1, <<>>},
        clickhouse_erl_types_integer:decode_int32(<<255, 255, 255, 255>>)
    ),
    ?assertEqual(
        {ok, 32767, <<>>}, clickhouse_erl_types_integer:decode_int32(<<255, 127, 0, 0>>)
    ),
    ?assertEqual(
        {ok, -32767, <<>>},
        clickhouse_erl_types_integer:decode_int32(<<1, 128, 255, 255>>)
    ).

%% Test Int32 round trip
int32_round_trip_test() ->
    TestValues = [
        0,
        1,
        -1,
        127,
        -128,
        255,
        -256,
        32767,
        -32767,
        65535,
        -65536,
        2147483647,
        -2147483648
    ],
    lists:foreach(
        fun(N) ->
            Encoded = clickhouse_erl_types_integer:encode_int32(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_int32(Encoded),
            ?assertEqual(N, Decoded)
        end,
        TestValues
    ).

%% Test Int32 with remaining data
int32_with_remaining_data_test() ->
    Binary = <<42, 0, 0, 0, "extra_data">>,
    {ok, Value, Rest} = clickhouse_erl_types_integer:decode_int32(Binary),
    ?assertEqual(42, Value),
    ?assertEqual(<<"extra_data">>, Rest).

%% Test Int32 decode truncated binary
decode_int32_truncated_test() ->
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_int32(<<>>)),
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_int32(<<1>>)),
    ?assertMatch(
        {error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_int32(<<1, 2, 3>>)
    ).

%% Test Int32 encode value too large
encode_int32_too_large_test() ->
    TooBig = 2147483648,
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int32(TooBig)
    ).

%% Test Int32 encode value too small
encode_int32_too_small_test() ->
    TooSmall = -2147483649,
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int32(TooSmall)
    ).

%% ============================================================================
%% Int64 Tests
%% ============================================================================

%% Test Int64 encoding
encode_int64_test() ->
    ?assertEqual(<<0, 0, 0, 0, 0, 0, 0, 0>>, clickhouse_erl_types_integer:encode_int64(0)),
    ?assertEqual(<<1, 0, 0, 0, 0, 0, 0, 0>>, clickhouse_erl_types_integer:encode_int64(1)),
    ?assertEqual(
        <<255, 255, 255, 255, 255, 255, 255, 255>>, clickhouse_erl_types_integer:encode_int64(-1)
    ),
    ?assertEqual(
        <<255, 127, 0, 0, 0, 0, 0, 0>>, clickhouse_erl_types_integer:encode_int64(32767)
    ),
    ?assertEqual(
        <<1, 128, 255, 255, 255, 255, 255, 255>>,
        clickhouse_erl_types_integer:encode_int64(-32767)
    ).

%% Test Int64 decoding
decode_int64_test() ->
    ?assertEqual(
        {ok, 0, <<>>}, clickhouse_erl_types_integer:decode_int64(<<0, 0, 0, 0, 0, 0, 0, 0>>)
    ),
    ?assertEqual(
        {ok, 1, <<>>}, clickhouse_erl_types_integer:decode_int64(<<1, 0, 0, 0, 0, 0, 0, 0>>)
    ),
    ?assertEqual(
        {ok, -1, <<>>},
        clickhouse_erl_types_integer:decode_int64(<<255, 255, 255, 255, 255, 255, 255, 255>>)
    ),
    ?assertEqual(
        {ok, 32767, <<>>},
        clickhouse_erl_types_integer:decode_int64(<<255, 127, 0, 0, 0, 0, 0, 0>>)
    ),
    ?assertEqual(
        {ok, -32767, <<>>},
        clickhouse_erl_types_integer:decode_int64(<<1, 128, 255, 255, 255, 255, 255, 255>>)
    ).

%% Test Int64 round trip
int64_round_trip_test() ->
    TestValues = [
        0,
        1,
        -1,
        127,
        -128,
        255,
        -256,
        32767,
        -32767,
        65535,
        -65536,
        % 32-bit limits
        2147483647,
        -2147483648,
        % max int64
        9223372036854775807,
        % min int64
        -9223372036854775808
    ],
    lists:foreach(
        fun(N) ->
            Encoded = clickhouse_erl_types_integer:encode_int64(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_int64(Encoded),
            ?assertEqual(N, Decoded)
        end,
        TestValues
    ).

%% Test Int64 with remaining data
int64_with_remaining_data_test() ->
    Binary = <<42, 0, 0, 0, 0, 0, 0, 0, "extra_data">>,
    {ok, Value, Rest} = clickhouse_erl_types_integer:decode_int64(Binary),
    ?assertEqual(42, Value),
    ?assertEqual(<<"extra_data">>, Rest).

%% Test Int64 decode truncated binary
decode_int64_truncated_test() ->
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_int64(<<>>)),
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_int64(<<1>>)),
    ?assertMatch(
        {error, {truncated_data, _}},
        clickhouse_erl_types_integer:decode_int64(<<1, 2, 3, 4, 5, 6, 7>>)
    ).

%% Test Int64 encode value too large
encode_int64_too_large_test() ->
    % max + 1
    TooBig = 9223372036854775808,
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int64(TooBig)
    ).

%% Test Int64 encode value too small
encode_int64_too_small_test() ->
    % min - 1
    TooSmall = -9223372036854775809,
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int64(TooSmall)
    ).

%% ============================================================================
%% Float32 Tests
%% ============================================================================

%% Test Float32 encoding
encode_float32_test() ->
    ?assertEqual(<<0, 0, 0, 0>>, clickhouse_erl_types_float:encode_float32(0.0)),
    ?assertEqual(<<0, 0, 128, 63>>, clickhouse_erl_types_float:encode_float32(1.0)),
    ?assertEqual(<<0, 0, 0, 192>>, clickhouse_erl_types_float:encode_float32(-2.0)).

%% Test Float32 decoding
decode_float32_test() ->
    ?assertEqual({ok, 0.0, <<>>}, clickhouse_erl_types_float:decode_float32(<<0, 0, 0, 0>>)),
    ?assertEqual({ok, 1.0, <<>>}, clickhouse_erl_types_float:decode_float32(<<0, 0, 128, 63>>)),
    ?assertEqual({ok, -2.0, <<>>}, clickhouse_erl_types_float:decode_float32(<<0, 0, 0, 192>>)).

%% Test Float32 special values
float32_special_values_test() ->
    %% Infinity
    ?assertEqual(<<0, 0, 128, 127>>, clickhouse_erl_types_float:encode_float32(infinity)),
    ?assertEqual(
        {ok, infinity, <<>>}, clickhouse_erl_types_float:decode_float32(<<0, 0, 128, 127>>)
    ),

    %% -Infinity
    ?assertEqual(<<0, 0, 128, 255>>, clickhouse_erl_types_float:encode_float32('-infinity')),
    ?assertEqual(
        {ok, '-infinity', <<>>}, clickhouse_erl_types_float:decode_float32(<<0, 0, 128, 255>>)
    ),

    %% NaN
    ?assertEqual(<<0, 0, 192, 127>>, clickhouse_erl_types_float:encode_float32(nan)),
    ?assertEqual(
        {ok, nan, <<>>}, clickhouse_erl_types_float:decode_float32(<<0, 0, 192, 127>>)
    ).

%% Test Float32 truncated
decode_float32_truncated_test() ->
    ?assertMatch(
        {error, {truncated_data, _}}, clickhouse_erl_types_float:decode_float32(<<0, 0, 0>>)
    ).

%% ============================================================================
%% Float64 Tests
%% ============================================================================

%% Test Float64 encoding
encode_float64_test() ->
    ?assertEqual(<<0, 0, 0, 0, 0, 0, 0, 0>>, clickhouse_erl_types_float:encode_float64(0.0)),
    ?assertEqual(<<0, 0, 0, 0, 0, 0, 240, 63>>, clickhouse_erl_types_float:encode_float64(1.0)),
    ?assertEqual(<<0, 0, 0, 0, 0, 0, 0, 192>>, clickhouse_erl_types_float:encode_float64(-2.0)).

%% Test Float64 decoding
decode_float64_test() ->
    ?assertEqual(
        {ok, 0.0, <<>>}, clickhouse_erl_types_float:decode_float64(<<0, 0, 0, 0, 0, 0, 0, 0>>)
    ),
    ?assertEqual(
        {ok, 1.0, <<>>},
        clickhouse_erl_types_float:decode_float64(<<0, 0, 0, 0, 0, 0, 240, 63>>)
    ),
    ?assertEqual(
        {ok, -2.0, <<>>},
        clickhouse_erl_types_float:decode_float64(<<0, 0, 0, 0, 0, 0, 0, 192>>)
    ).

%% Test Float64 special values
float64_special_values_test() ->
    %% Infinity
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 240, 127>>, clickhouse_erl_types_float:encode_float64(infinity)
    ),
    ?assertEqual(
        {ok, infinity, <<>>},
        clickhouse_erl_types_float:decode_float64(<<0, 0, 0, 0, 0, 0, 240, 127>>)
    ),

    %% -Infinity
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 240, 255>>, clickhouse_erl_types_float:encode_float64('-infinity')
    ),
    ?assertEqual(
        {ok, '-infinity', <<>>},
        clickhouse_erl_types_float:decode_float64(<<0, 0, 0, 0, 0, 0, 240, 255>>)
    ),

    %% NaN
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 248, 127>>, clickhouse_erl_types_float:encode_float64(nan)
    ),
    ?assertEqual(
        {ok, nan, <<>>},
        clickhouse_erl_types_float:decode_float64(<<0, 0, 0, 0, 0, 0, 248, 127>>)
    ).

%% Test Float64 truncated
decode_float64_truncated_test() ->
    ?assertMatch(
        {error, {truncated_data, _}},
        clickhouse_erl_types_float:decode_float64(<<0, 0, 0, 0, 0, 0, 0>>)
    ).

%% ============================================================================
%% Boolean Tests
%% ============================================================================

%% Test Bool encoding
encode_bool_test() ->
    ?assertEqual(<<1>>, clickhouse_erl_types_integer:encode_bool(true)),
    ?assertEqual(<<0>>, clickhouse_erl_types_integer:encode_bool(false)).

%% Test Bool validtion
encode_bool_validation_test() ->
    ?assertMatch(
        {error, {invalid_value, _}}, clickhouse_erl_types_integer:encode_bool(not_a_bool)
    ),
    ?assertMatch({error, {invalid_value, _}}, clickhouse_erl_types_integer:encode_bool(1)).

%% Test Bool decoding
decode_bool_test() ->
    ?assertEqual({ok, true, <<>>}, clickhouse_erl_types_integer:decode_bool(<<1>>)),
    ?assertEqual({ok, false, <<>>}, clickhouse_erl_types_integer:decode_bool(<<0>>)),
    %% Error for non-0/1 values
    ?assertMatch(
        {error, {invalid_bool_value, _}}, clickhouse_erl_types_integer:decode_bool(<<2>>)
    ).

%% ============================================================================
%% String Tests
%% ============================================================================

%% Test empty string encoding/decoding
empty_string_test() ->
    EmptyString = "",
    EncodedBinary = clickhouse_erl_types_primitive:encode_string(EmptyString),
    ?assert(is_binary(EncodedBinary)),
    {ok, DecodedString, <<>>} = clickhouse_erl_types_primitive:decode_string(EncodedBinary),
    ?assertEqual(<<>>, DecodedString).

%% Test Unicode string encoding/decoding
unicode_string_test() ->
    UnicodeString = "тест-клиент数据库",
    EncodedBinary = clickhouse_erl_types_primitive:encode_string(UnicodeString),
    ?assert(is_binary(EncodedBinary)),
    {ok, DecodedString, <<>>} = clickhouse_erl_types_primitive:decode_string(EncodedBinary),
    ?assertEqual(unicode:characters_to_binary(UnicodeString, utf8), DecodedString).

%% Test long string encoding/decoding
long_string_test() ->
    LongString = lists:duplicate(1000, $a),
    EncodedBinary = clickhouse_erl_types_primitive:encode_string(LongString),
    ?assert(is_binary(EncodedBinary)),
    {ok, DecodedString, <<>>} = clickhouse_erl_types_primitive:decode_string(EncodedBinary),
    ?assertEqual(list_to_binary(LongString), DecodedString).

%% Test special characters in string
special_characters_test() ->
    SpecialString = "test@domain.com!#$%^&*()_+-=[]{}|;':" ++ [34] ++ ",./<>?",
    EncodedBinary = clickhouse_erl_types_primitive:encode_string(SpecialString),
    ?assert(is_binary(EncodedBinary)),
    {ok, DecodedString, <<>>} = clickhouse_erl_types_primitive:decode_string(EncodedBinary),
    ?assertEqual(list_to_binary(SpecialString), DecodedString).

%% Test string with remaining data
string_with_remaining_data_test() ->
    String = "test_string",
    RemainingData = <<"extra_data">>,
    EncodedString = clickhouse_erl_types_primitive:encode_string(String),
    BinaryWithExtra = <<EncodedString/binary, RemainingData/binary>>,
    {ok, DecodedString, Rest} = clickhouse_erl_types_primitive:decode_string(BinaryWithExtra),
    ?assertEqual(list_to_binary(String), DecodedString),
    ?assertEqual(RemainingData, Rest).

%% Test truncated string
truncated_string_test() ->
    %% String claims 10 bytes but only has 5
    TruncatedString = <<10, "short">>,
    Result = clickhouse_erl_types_primitive:decode_string(TruncatedString),
    ?assertMatch({error, _}, Result).

%% Test invalid UTF-8
invalid_utf8_test() ->
    %% Invalid UTF-8 bytes
    InvalidUtf8 = <<3, 255, 254, 253>>,
    Result = clickhouse_erl_types_primitive:decode_string(InvalidUtf8),
    ?assertMatch({error, _}, Result).

%% Test empty binary for string
empty_binary_string_test() ->
    Result = clickhouse_erl_types_primitive:decode_string(<<>>),
    ?assertMatch({error, _}, Result).

%% Test string limit enforcement
string_limit_test() ->
    String = "12345",
    Binary = clickhouse_erl_types_primitive:encode_string(String),

    %% Should succeed when limit is sufficient
    {ok, Decoded, <<>>} = clickhouse_erl_types_primitive:decode_string(Binary, 5),
    ?assertEqual(list_to_binary(String), Decoded),

    %% Should fail when limit is exceeded
    Result = clickhouse_erl_types_primitive:decode_string(Binary, 4),
    ?assertMatch({error, {string_too_long, #{length := 5, max_length := 4}}}, Result).

%% Test huge string length safety
%% This test ensures that we don't allocate memory when the declared length is huge
huge_string_length_test() ->
    %% Claim 1GB string but provide no data
    HugeLength = 1024 * 1024 * 1024,
    Binary = <<(clickhouse_erl_types_primitive:encode_varint(HugeLength))/binary>>,

    %% With strict limit - should fail fast with string_too_long
    ResultStrict = clickhouse_erl_types_primitive:decode_string(Binary, 1024),
    ?assertMatch(
        {error, {string_too_long, #{length := HugeLength, max_length := 1024}}}, ResultStrict
    ),

    %% With sufficient limit - should fail with truncated_data (not memory allocation error)
    %% Note: We use a limit larger than HugeLength to simulate "allowed" size,
    %% ensuring the failure is due to missing data, not memory exhaustion.
    %% Since we can't easily test "no memory allocation" directly in eunit without crashing,
    %% we rely on the implementation logic: check byte_size(Rest) >= Length BEFORE allocation.
    ResultLoose = clickhouse_erl_types_primitive:decode_string(Binary, HugeLength + 1),
    ?assertMatch({error, {truncated_data, _}}, ResultLoose).

%% Test String validation
encode_string_validation_test() ->
    ?assertMatch({error, {invalid_value, _}}, clickhouse_erl_types_primitive:encode_string(123)).
