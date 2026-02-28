%% @doc Protocol compliance tests for ClickHouse type encoding/decoding.
%%
%% This module validates that our encoding matches the ClickHouse binary protocol
%% specifications by comparing against known reference values from ch-go and
%% ClickHouse documentation.
%%
%% **Validates: Requirements 8.1, 8.2, 8.3**
-module(clickhouse_erl_types_protocol_compliance_tests).

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

-import(generators, [
    date_gen/0,
    datetime_gen/0,
    float32_gen/0,
    float64_gen/0,
    int16_gen/0,
    int8_gen/0,
    uint16_gen/0,
    uint32_gen/0
]).

%% ============================================================================
%% Integer Type Protocol Compliance Tests
%% ============================================================================

%% Test UInt16 encoding matches protocol specification
%% Protocol: 16-bit unsigned integer, little-endian
uint16_protocol_compliance_test() ->
    %% Test value: 0
    ?assertEqual(<<0, 0>>, clickhouse_erl_types_integer:encode_uint16(0)),

    %% Test value: 1
    ?assertEqual(<<1, 0>>, clickhouse_erl_types_integer:encode_uint16(1)),

    %% Test value: 256 (0x0100)
    ?assertEqual(<<0, 1>>, clickhouse_erl_types_integer:encode_uint16(256)),

    %% Test value: 65535 (max UInt16)
    ?assertEqual(<<255, 255>>, clickhouse_erl_types_integer:encode_uint16(65535)),

    %% Test value: 12345 (0x3039)
    ?assertEqual(<<57, 48>>, clickhouse_erl_types_integer:encode_uint16(12345)).

%% Test UInt32 encoding matches protocol specification
%% Protocol: 32-bit unsigned integer, little-endian
uint32_protocol_compliance_test() ->
    %% Test value: 0
    ?assertEqual(<<0, 0, 0, 0>>, clickhouse_erl_types_integer:encode_uint32(0)),

    %% Test value: 1
    ?assertEqual(<<1, 0, 0, 0>>, clickhouse_erl_types_integer:encode_uint32(1)),

    %% Test value: 256 (0x00000100)
    ?assertEqual(<<0, 1, 0, 0>>, clickhouse_erl_types_integer:encode_uint32(256)),

    %% Test value: 65536 (0x00010000)
    ?assertEqual(<<0, 0, 1, 0>>, clickhouse_erl_types_integer:encode_uint32(65536)),

    %% Test value: 4294967295 (max UInt32)
    ?assertEqual(<<255, 255, 255, 255>>, clickhouse_erl_types_integer:encode_uint32(4294967295)),

    %% Test value: 123456789 (0x075BCD15)
    ?assertEqual(<<21, 205, 91, 7>>, clickhouse_erl_types_integer:encode_uint32(123456789)).

%% Test Int8 encoding matches protocol specification
%% Protocol: 8-bit signed integer, two's complement
int8_protocol_compliance_test() ->
    %% Test value: 0
    ?assertEqual(<<0>>, clickhouse_erl_types_integer:encode_int8(0)),

    %% Test value: 1
    ?assertEqual(<<1>>, clickhouse_erl_types_integer:encode_int8(1)),

    %% Test value: -1
    ?assertEqual(<<255>>, clickhouse_erl_types_integer:encode_int8(-1)),

    %% Test value: 127 (max Int8)
    ?assertEqual(<<127>>, clickhouse_erl_types_integer:encode_int8(127)),

    %% Test value: -128 (min Int8)
    ?assertEqual(<<128>>, clickhouse_erl_types_integer:encode_int8(-128)),

    %% Test value: 42
    ?assertEqual(<<42>>, clickhouse_erl_types_integer:encode_int8(42)),

    %% Test value: -42
    ?assertEqual(<<214>>, clickhouse_erl_types_integer:encode_int8(-42)).

%% Test Int16 encoding matches protocol specification
%% Protocol: 16-bit signed integer, little-endian, two's complement
int16_protocol_compliance_test() ->
    %% Test value: 0
    ?assertEqual(<<0, 0>>, clickhouse_erl_types_integer:encode_int16(0)),

    %% Test value: 1
    ?assertEqual(<<1, 0>>, clickhouse_erl_types_integer:encode_int16(1)),

    %% Test value: -1
    ?assertEqual(<<255, 255>>, clickhouse_erl_types_integer:encode_int16(-1)),

    %% Test value: 32767 (max Int16)
    ?assertEqual(<<255, 127>>, clickhouse_erl_types_integer:encode_int16(32767)),

    %% Test value: -32768 (min Int16)
    ?assertEqual(<<0, 128>>, clickhouse_erl_types_integer:encode_int16(-32768)),

    %% Test value: 12345
    ?assertEqual(<<57, 48>>, clickhouse_erl_types_integer:encode_int16(12345)),

    %% Test value: -12345
    ?assertEqual(<<199, 207>>, clickhouse_erl_types_integer:encode_int16(-12345)).

%% Test Int32 encoding matches protocol specification
%% Protocol: 32-bit signed integer, little-endian, two's complement
int32_protocol_compliance_test() ->
    %% Test value: 0
    ?assertEqual(<<0, 0, 0, 0>>, clickhouse_erl_types_integer:encode_int32(0)),

    %% Test value: 1
    ?assertEqual(<<1, 0, 0, 0>>, clickhouse_erl_types_integer:encode_int32(1)),

    %% Test value: -1
    ?assertEqual(<<255, 255, 255, 255>>, clickhouse_erl_types_integer:encode_int32(-1)),

    %% Test value: 2147483647 (max Int32)
    ?assertEqual(<<255, 255, 255, 127>>, clickhouse_erl_types_integer:encode_int32(2147483647)),

    %% Test value: -2147483648 (min Int32)
    ?assertEqual(<<0, 0, 0, 128>>, clickhouse_erl_types_integer:encode_int32(-2147483648)),

    %% Test value: 123456789
    ?assertEqual(<<21, 205, 91, 7>>, clickhouse_erl_types_integer:encode_int32(123456789)),

    %% Test value: -123456789
    ?assertEqual(<<235, 50, 164, 248>>, clickhouse_erl_types_integer:encode_int32(-123456789)).

%% Test Int64 encoding matches protocol specification
%% Protocol: 64-bit signed integer, little-endian, two's complement
int64_protocol_compliance_test() ->
    %% Test value: 0
    ?assertEqual(<<0, 0, 0, 0, 0, 0, 0, 0>>, clickhouse_erl_types_integer:encode_int64(0)),

    %% Test value: 1
    ?assertEqual(<<1, 0, 0, 0, 0, 0, 0, 0>>, clickhouse_erl_types_integer:encode_int64(1)),

    %% Test value: -1
    ?assertEqual(
        <<255, 255, 255, 255, 255, 255, 255, 255>>,
        clickhouse_erl_types_integer:encode_int64(-1)
    ),

    %% Test value: 9223372036854775807 (max Int64)
    ?assertEqual(
        <<255, 255, 255, 255, 255, 255, 255, 127>>,
        clickhouse_erl_types_integer:encode_int64(9223372036854775807)
    ),

    %% Test value: -9223372036854775808 (min Int64)
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 0, 128>>,
        clickhouse_erl_types_integer:encode_int64(-9223372036854775808)
    ),

    %% Test value: 1234567890123456789
    ?assertEqual(
        <<21, 129, 233, 125, 244, 16, 34, 17>>,
        clickhouse_erl_types_integer:encode_int64(1234567890123456789)
    ).

%% ============================================================================
%% Floating-Point Type Protocol Compliance Tests
%% ============================================================================

%% Test Float32 encoding matches IEEE 754 specification
%% Protocol: 32-bit IEEE 754 single precision, little-endian
float32_protocol_compliance_test() ->
    %% Test value: 0.0
    ?assertEqual(<<0, 0, 0, 0>>, clickhouse_erl_types_float:encode_float32(0.0)),

    %% Test value: 1.0
    ?assertEqual(<<0, 0, 128, 63>>, clickhouse_erl_types_float:encode_float32(1.0)),

    %% Test value: -1.0
    ?assertEqual(<<0, 0, 128, 191>>, clickhouse_erl_types_float:encode_float32(-1.0)),

    %% Test value: 3.14159265 (approximation of pi)
    Encoded314 = clickhouse_erl_types_float:encode_float32(3.14159265),
    ?assertEqual(4, byte_size(Encoded314)),
    {ok, Decoded314, <<>>} = clickhouse_erl_types_float:decode_float32(Encoded314),
    ?assert(abs(Decoded314 - 3.14159265) < 0.0001),

    %% Test special values
    %% Infinity: 0x7F800000
    ?assertEqual(<<0, 0, 128, 127>>, clickhouse_erl_types_float:encode_float32(infinity)),

    %% -Infinity: 0xFF800000
    ?assertEqual(<<0, 0, 128, 255>>, clickhouse_erl_types_float:encode_float32('-infinity')),

    %% NaN: 0x7FC00000 (one of many possible NaN representations)
    ?assertEqual(<<0, 0, 192, 127>>, clickhouse_erl_types_float:encode_float32(nan)).

%% Test Float64 encoding matches IEEE 754 specification
%% Protocol: 64-bit IEEE 754 double precision, little-endian
float64_protocol_compliance_test() ->
    %% Test value: 0.0
    ?assertEqual(<<0, 0, 0, 0, 0, 0, 0, 0>>, clickhouse_erl_types_float:encode_float64(0.0)),

    %% Test value: 1.0
    ?assertEqual(<<0, 0, 0, 0, 0, 0, 240, 63>>, clickhouse_erl_types_float:encode_float64(1.0)),

    %% Test value: -1.0
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 240, 191>>, clickhouse_erl_types_float:encode_float64(-1.0)
    ),

    %% Test value: 3.141592653589793 (pi)
    EncodedPi = clickhouse_erl_types_float:encode_float64(3.141592653589793),
    ?assertEqual(8, byte_size(EncodedPi)),
    {ok, DecodedPi, <<>>} = clickhouse_erl_types_float:decode_float64(EncodedPi),
    ?assert(abs(DecodedPi - 3.141592653589793) < 0.000000000001),

    %% Test special values
    %% Infinity: 0x7FF0000000000000
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 240, 127>>, clickhouse_erl_types_float:encode_float64(infinity)
    ),

    %% -Infinity: 0xFFF0000000000000
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 240, 255>>, clickhouse_erl_types_float:encode_float64('-infinity')
    ),

    %% NaN: 0x7FF8000000000000 (one of many possible NaN representations)
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 248, 127>>, clickhouse_erl_types_float:encode_float64(nan)
    ).

%% ============================================================================
%% Temporal Type Protocol Compliance Tests
%% ============================================================================

%% Test Date encoding matches protocol specification
%% Protocol: UInt16 days since 1970-01-01 (Unix epoch)
date_protocol_compliance_test() ->
    %% Test value: 1970-01-01 (epoch) = 0 days
    ?assertEqual(<<0, 0>>, clickhouse_erl_types_temporal:encode_date({1970, 1, 1})),

    %% Test value: 1970-01-02 = 1 day
    ?assertEqual(<<1, 0>>, clickhouse_erl_types_temporal:encode_date({1970, 1, 2})),

    %% Test value: 2000-01-01 = 10957 days (0x2ACD)
    ?assertEqual(<<205, 42>>, clickhouse_erl_types_temporal:encode_date({2000, 1, 1})),

    %% Test value: 2024-01-01 = 19723 days (0x4D0B)
    ?assertEqual(<<11, 77>>, clickhouse_erl_types_temporal:encode_date({2024, 1, 1})),

    %% Verify round-trip for known date
    {ok, Decoded, <<>>} = clickhouse_erl_types_temporal:decode_date(<<205, 42>>),
    ?assertEqual({2000, 1, 1}, Decoded).

%% Test DateTime encoding matches protocol specification
%% Protocol: UInt32 seconds since 1970-01-01 00:00:00 UTC (Unix timestamp)
datetime_protocol_compliance_test() ->
    %% Test value: 1970-01-01 00:00:00 = 0 seconds
    ?assertEqual(
        <<0, 0, 0, 0>>,
        clickhouse_erl_types_temporal:encode_datetime({{1970, 1, 1}, {0, 0, 0}})
    ),

    %% Test value: 1970-01-01 00:00:01 = 1 second
    ?assertEqual(
        <<1, 0, 0, 0>>,
        clickhouse_erl_types_temporal:encode_datetime({{1970, 1, 1}, {0, 0, 1}})
    ),

    %% Test value: 2000-01-01 00:00:00 = 946684800 seconds (0x386D4380)
    ?assertEqual(
        <<128, 67, 109, 56>>,
        clickhouse_erl_types_temporal:encode_datetime({{2000, 1, 1}, {0, 0, 0}})
    ),

    %% Test value: 2024-01-01 00:00:00 = 1704067200 seconds (0x6592E080)
    ?assertEqual(
        <<128, 0, 146, 101>>,
        clickhouse_erl_types_temporal:encode_datetime({{2024, 1, 1}, {0, 0, 0}})
    ),

    %% Verify round-trip for known datetime
    {ok, Decoded, <<>>} = clickhouse_erl_types_temporal:decode_datetime(<<128, 67, 109, 56>>),
    ?assertEqual({{2000, 1, 1}, {0, 0, 0}}, Decoded).

%% Test DateTime64 encoding matches protocol specification
%% Protocol: Int64 ticks with configurable precision
datetime64_protocol_compliance_test() ->
    %% DateTime64 encodes as Int64 with precision determining the scale
    %% Precision 0 = seconds, 3 = milliseconds, 6 = microseconds, 9 = nanoseconds

    %% Test value: 0 (epoch) with precision 3 (milliseconds)
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 0, 0>>,
        clickhouse_erl_types_temporal:encode_datetime64(0, 3)
    ),

    %% Test value: 1000 milliseconds (1 second) with precision 3
    ?assertEqual(
        <<232, 3, 0, 0, 0, 0, 0, 0>>,
        clickhouse_erl_types_temporal:encode_datetime64(1000, 3)
    ),

    %% Test value: 1704067200000 milliseconds (2024-01-01 00:00:00) with precision 3
    %% 1704067200000 = 0x18C51F3C200
    ?assertEqual(
        <<0, 244, 81, 194, 140, 1, 0, 0>>,
        clickhouse_erl_types_temporal:encode_datetime64(1704067200000, 3)
    ),

    %% Verify round-trip
    {ok, Decoded, <<>>} = clickhouse_erl_types_temporal:decode_datetime64(
        <<232, 3, 0, 0, 0, 0, 0, 0>>, 3
    ),
    ?assertEqual(1000, Decoded).

%% ============================================================================
%% Boolean Type Protocol Compliance Tests
%% ============================================================================

%% Test Bool encoding matches protocol specification
%% Protocol: UInt8 where 0 = false, 1 = true
bool_protocol_compliance_test() ->
    %% Test value: false = 0
    ?assertEqual(<<0>>, clickhouse_erl_types_integer:encode_bool(false)),

    %% Test value: true = 1
    ?assertEqual(<<1>>, clickhouse_erl_types_integer:encode_bool(true)),

    %% Verify decoding
    {ok, false, <<>>} = clickhouse_erl_types_integer:decode_bool(<<0>>),
    {ok, true, <<>>} = clickhouse_erl_types_integer:decode_bool(<<1>>).

%% ============================================================================
%% Cross-Reference Tests with ch-go
%% ============================================================================

%% Test that our encoding matches ch-go for a variety of values
%% This test documents the expected binary format based on ch-go implementation
cross_reference_integer_types_test() ->
    %% UInt16: ch-go uses binary.LittleEndian.PutUint16
    ?assertEqual(<<0, 0>>, clickhouse_erl_types_integer:encode_uint16(0)),
    ?assertEqual(<<255, 255>>, clickhouse_erl_types_integer:encode_uint16(65535)),

    %% UInt32: ch-go uses binary.LittleEndian.PutUint32
    ?assertEqual(<<0, 0, 0, 0>>, clickhouse_erl_types_integer:encode_uint32(0)),
    ?assertEqual(<<255, 255, 255, 255>>, clickhouse_erl_types_integer:encode_uint32(4294967295)),

    %% Int8: ch-go uses direct byte assignment with two's complement
    ?assertEqual(<<0>>, clickhouse_erl_types_integer:encode_int8(0)),
    ?assertEqual(<<127>>, clickhouse_erl_types_integer:encode_int8(127)),
    ?assertEqual(<<128>>, clickhouse_erl_types_integer:encode_int8(-128)),

    %% Int16: ch-go uses binary.LittleEndian.PutUint16 with cast
    ?assertEqual(<<0, 0>>, clickhouse_erl_types_integer:encode_int16(0)),
    ?assertEqual(<<255, 127>>, clickhouse_erl_types_integer:encode_int16(32767)),
    ?assertEqual(<<0, 128>>, clickhouse_erl_types_integer:encode_int16(-32768)).

%% Test that our floating-point encoding matches IEEE 754 standard used by ch-go
cross_reference_float_types_test() ->
    %% Float32: ch-go uses math.Float32bits + binary.LittleEndian.PutUint32
    ?assertEqual(<<0, 0, 0, 0>>, clickhouse_erl_types_float:encode_float32(0.0)),
    ?assertEqual(<<0, 0, 128, 63>>, clickhouse_erl_types_float:encode_float32(1.0)),
    ?assertEqual(<<0, 0, 128, 127>>, clickhouse_erl_types_float:encode_float32(infinity)),

    %% Float64: ch-go uses math.Float64bits + binary.LittleEndian.PutUint64
    ?assertEqual(<<0, 0, 0, 0, 0, 0, 0, 0>>, clickhouse_erl_types_float:encode_float64(0.0)),
    ?assertEqual(<<0, 0, 0, 0, 0, 0, 240, 63>>, clickhouse_erl_types_float:encode_float64(1.0)),
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 240, 127>>, clickhouse_erl_types_float:encode_float64(infinity)
    ).

%% Test that our temporal encoding matches ch-go
cross_reference_temporal_types_test() ->
    %% Date: ch-go uses binary.LittleEndian.PutUint16 with days since Unix epoch
    ?assertEqual(<<0, 0>>, clickhouse_erl_types_temporal:encode_date({1970, 1, 1})),
    ?assertEqual(<<1, 0>>, clickhouse_erl_types_temporal:encode_date({1970, 1, 2})),

    %% DateTime: ch-go uses binary.LittleEndian.PutUint32 with Unix timestamp
    ?assertEqual(
        <<0, 0, 0, 0>>,
        clickhouse_erl_types_temporal:encode_datetime({{1970, 1, 1}, {0, 0, 0}})
    ),
    ?assertEqual(
        <<1, 0, 0, 0>>,
        clickhouse_erl_types_temporal:encode_datetime({{1970, 1, 1}, {0, 0, 1}})
    ),

    %% DateTime64: ch-go uses binary.LittleEndian.PutUint64 with Int64 ticks
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 0, 0>>,
        clickhouse_erl_types_temporal:encode_datetime64(0, 3)
    ),
    ?assertEqual(
        <<1, 0, 0, 0, 0, 0, 0, 0>>,
        clickhouse_erl_types_temporal:encode_datetime64(1, 3)
    ).

%% ============================================================================
%% Version-Aware Type Handling Tests
%% ============================================================================

%% Test that basic types work across all ClickHouse versions
%% All basic types (integers, floats, dates, booleans) have been stable
%% since early ClickHouse versions and don't require version-specific handling
version_compatibility_test() ->
    %% All basic types should encode/decode consistently regardless of version
    %% This test documents that no version-specific logic is needed for basic types

    %% Integer types: stable since ClickHouse 1.0
    ?assertEqual(<<1, 0>>, clickhouse_erl_types_integer:encode_uint16(1)),
    ?assertEqual(<<1, 0, 0, 0>>, clickhouse_erl_types_integer:encode_uint32(1)),
    ?assertEqual(<<1>>, clickhouse_erl_types_integer:encode_int8(1)),
    ?assertEqual(<<1, 0>>, clickhouse_erl_types_integer:encode_int16(1)),

    %% Float types: stable since ClickHouse 1.0
    ?assertEqual(<<0, 0, 128, 63>>, clickhouse_erl_types_float:encode_float32(1.0)),
    ?assertEqual(<<0, 0, 0, 0, 0, 0, 240, 63>>, clickhouse_erl_types_float:encode_float64(1.0)),

    %% Date/DateTime types: stable since ClickHouse 1.0
    ?assertEqual(<<0, 0>>, clickhouse_erl_types_temporal:encode_date({1970, 1, 1})),
    ?assertEqual(
        <<0, 0, 0, 0>>,
        clickhouse_erl_types_temporal:encode_datetime({{1970, 1, 1}, {0, 0, 0}})
    ),

    %% DateTime64: introduced in ClickHouse 20.1, but encoding is straightforward Int64
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 0, 0>>,
        clickhouse_erl_types_temporal:encode_datetime64(0, 3)
    ),

    %% Bool: introduced in ClickHouse 21.12, but encoding is simple UInt8
    ?assertEqual(<<1>>, clickhouse_erl_types_integer:encode_bool(true)).

%% ============================================================================
%% Comprehensive Error Handling Tests
%% **Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5**
%% ============================================================================

%% Test that all error conditions return proper error tuples with descriptive atoms and context
comprehensive_error_handling_test() ->
    %% Test truncation errors
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_uint8(<<>>)),
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_uint16(<<1>>)),
    ?assertMatch(
        {error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_uint32(<<1, 2, 3>>)
    ),
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_int8(<<>>)),
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_int16(<<1>>)),
    ?assertMatch(
        {error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_int32(<<1, 2, 3>>)
    ),
    ?assertMatch(
        {error, {truncated_data, _}},
        clickhouse_erl_types_integer:decode_int64(<<1, 2, 3, 4, 5, 6, 7>>)
    ),
    ?assertMatch(
        {error, {truncated_data, _}}, clickhouse_erl_types_float:decode_float32(<<1, 2, 3>>)
    ),
    ?assertMatch(
        {error, {truncated_data, _}},
        clickhouse_erl_types_float:decode_float64(<<1, 2, 3, 4, 5, 6, 7>>)
    ),
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_temporal:decode_date(<<1>>)),
    ?assertMatch(
        {error, {truncated_data, _}}, clickhouse_erl_types_temporal:decode_datetime(<<1, 2, 3>>)
    ),
    ?assertMatch(
        {error, {truncated_data, _}},
        clickhouse_erl_types_temporal:decode_datetime64(<<1, 2, 3, 4, 5, 6, 7>>, 3)
    ),
    ?assertMatch({error, {truncated_data, _}}, clickhouse_erl_types_integer:decode_bool(<<>>)),
    ?assertMatch({error, _}, clickhouse_erl_types_primitive:decode_string(<<>>)),

    %% Test boundary errors
    ?assertMatch({error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint8(-1)),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint8(256)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint16(-1)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint16(65536)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint32(-1)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_uint32(4294967296)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int8(-129)
    ),
    ?assertMatch({error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int8(128)),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int16(-32769)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int16(32768)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int32(-2147483649)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_integer:encode_int32(2147483648)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_integer:encode_int64(-9223372036854775809)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_integer:encode_int64(9223372036854775808)
    ),

    %% Test invalid value errors
    ?assertMatch(
        {error, {invalid_bool_value, _}}, clickhouse_erl_types_integer:decode_bool(<<2>>)
    ),
    ?assertMatch(
        {error, {invalid_bool_value, _}}, clickhouse_erl_types_integer:decode_bool(<<255>>)
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_temporal:encode_date({1969, 12, 31})
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_temporal:encode_date({2150, 1, 1})
    ),
    ?assertMatch(
        {error, {invalid_date, _}}, clickhouse_erl_types_temporal:encode_date({2023, 2, 30})
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_temporal:encode_datetime({{1969, 12, 31}, {23, 59, 59}})
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_temporal:encode_datetime({{2107, 1, 1}, {0, 0, 0}})
    ),
    ?assertMatch(
        {error, {invalid_datetime, _}},
        clickhouse_erl_types_temporal:encode_datetime({{2020, 1, 1}, {25, 0, 0}})
    ),
    ?assertMatch(
        {error, {invalid_value, _}}, clickhouse_erl_types_float:encode_float32(not_a_number)
    ),
    ?assertMatch(
        {error, {invalid_value, _}}, clickhouse_erl_types_float:encode_float64(not_a_number)
    ),
    ?assertMatch(
        {error, {invalid_value, _}}, clickhouse_erl_types_integer:encode_bool(not_a_bool)
    ),
    ?assertMatch(
        {error, {invalid_value, _}}, clickhouse_erl_types_temporal:encode_date(not_a_date)
    ),
    ?assertMatch(
        {error, {invalid_value, _}}, clickhouse_erl_types_temporal:encode_datetime(not_a_datetime)
    ),

    %% Test invalid encoding errors
    InvalidUtf8 = <<2, 255, 254>>,
    ?assertMatch({error, _}, clickhouse_erl_types_primitive:decode_string(InvalidUtf8)).

%% ============================================================================
%% Property-Based Protocol Compliance Tests
%% ============================================================================

%% ============================================================================
%% Generators (shared across property tests)
%% ============================================================================

%% Generator for valid DateTime64 values (milliseconds since epoch)
datetime64_gen() ->
    ?LET(N, range(0, 1000000000000), N).

%% ============================================================================
%% Property: Protocol Compliance
%% **Validates: Requirements 8.1, 8.2, 8.3**
%% ============================================================================

%% Generator for protocol-compliant test cases
protocol_test_case_gen() ->
    oneof([
        %% Integer types with known encodings
        {uint16, 0, <<0, 0>>},
        {uint16, 1, <<1, 0>>},
        {uint16, 256, <<0, 1>>},
        {uint16, 65535, <<255, 255>>},
        {uint32, 0, <<0, 0, 0, 0>>},
        {uint32, 1, <<1, 0, 0, 0>>},
        {uint32, 256, <<0, 1, 0, 0>>},
        {uint32, 4294967295, <<255, 255, 255, 255>>},
        {int8, 0, <<0>>},
        {int8, 1, <<1>>},
        {int8, -1, <<255>>},
        {int8, 127, <<127>>},
        {int8, -128, <<128>>},
        {int16, 0, <<0, 0>>},
        {int16, 1, <<1, 0>>},
        {int16, -1, <<255, 255>>},
        {int16, 32767, <<255, 127>>},
        {int16, -32768, <<0, 128>>},
        {int32, 0, <<0, 0, 0, 0>>},
        {int32, 1, <<1, 0, 0, 0>>},
        {int32, -1, <<255, 255, 255, 255>>},
        {int32, 2147483647, <<255, 255, 255, 127>>},
        {int32, -2147483648, <<0, 0, 0, 128>>},
        {int64, 0, <<0, 0, 0, 0, 0, 0, 0, 0>>},
        {int64, 1, <<1, 0, 0, 0, 0, 0, 0, 0>>},
        {int64, -1, <<255, 255, 255, 255, 255, 255, 255, 255>>},
        {int64, 9223372036854775807, <<255, 255, 255, 255, 255, 255, 255, 127>>},
        {int64, -9223372036854775808, <<0, 0, 0, 0, 0, 0, 0, 128>>},
        %% Floating-point types with IEEE 754 encodings
        {float32, 0.0, <<0, 0, 0, 0>>},
        {float32, 1.0, <<0, 0, 128, 63>>},
        {float32, -1.0, <<0, 0, 128, 191>>},
        {float32, infinity, <<0, 0, 128, 127>>},
        {float32, '-infinity', <<0, 0, 128, 255>>},
        {float32, nan, <<0, 0, 192, 127>>},
        {float64, 0.0, <<0, 0, 0, 0, 0, 0, 0, 0>>},
        {float64, 1.0, <<0, 0, 0, 0, 0, 0, 240, 63>>},
        {float64, -1.0, <<0, 0, 0, 0, 0, 0, 240, 191>>},
        {float64, infinity, <<0, 0, 0, 0, 0, 0, 240, 127>>},
        {float64, '-infinity', <<0, 0, 0, 0, 0, 0, 240, 255>>},
        {float64, nan, <<0, 0, 0, 0, 0, 0, 248, 127>>},
        %% Temporal types with protocol-specific encodings
        {date, {1970, 1, 1}, <<0, 0>>},
        {date, {1970, 1, 2}, <<1, 0>>},
        {date, {2000, 1, 1}, <<205, 42>>},
        {datetime, {{1970, 1, 1}, {0, 0, 0}}, <<0, 0, 0, 0>>},
        {datetime, {{1970, 1, 1}, {0, 0, 1}}, <<1, 0, 0, 0>>},
        {datetime, {{2000, 1, 1}, {0, 0, 0}}, <<128, 67, 109, 56>>},
        {datetime64, {0, 3}, <<0, 0, 0, 0, 0, 0, 0, 0>>},
        {datetime64, {1000, 3}, <<232, 3, 0, 0, 0, 0, 0, 0>>},
        %% Boolean type
        {bool, false, <<0>>},
        {bool, true, <<1>>}
    ]).

%% Property: Encoded binaries match expected protocol format
prop_protocol_compliance() ->
    ?FORALL(
        {Type, Value, ExpectedBinary},
        protocol_test_case_gen(),
        begin
            EncodedBinary =
                case Type of
                    uint16 ->
                        clickhouse_erl_types_integer:encode_uint16(Value);
                    uint32 ->
                        clickhouse_erl_types_integer:encode_uint32(Value);
                    int8 ->
                        clickhouse_erl_types_integer:encode_int8(Value);
                    int16 ->
                        clickhouse_erl_types_integer:encode_int16(Value);
                    int32 ->
                        clickhouse_erl_types_integer:encode_int32(Value);
                    int64 ->
                        clickhouse_erl_types_integer:encode_int64(Value);
                    float32 ->
                        clickhouse_erl_types_float:encode_float32(Value);
                    float64 ->
                        clickhouse_erl_types_float:encode_float64(Value);
                    date ->
                        clickhouse_erl_types_temporal:encode_date(Value);
                    datetime ->
                        clickhouse_erl_types_temporal:encode_datetime(Value);
                    datetime64 ->
                        {Val, Precision} = Value,
                        clickhouse_erl_types_temporal:encode_datetime64(Val, Precision);
                    bool ->
                        clickhouse_erl_types_integer:encode_bool(Value)
                end,
            EncodedBinary =:= ExpectedBinary
        end
    ).

%% ============================================================================
%% Property: Little-Endian Encoding
%% **Validates: Requirements 8.1, 8.2**
%% ============================================================================

prop_little_endian_encoding() ->
    ?FORALL(
        {Type, Value},
        oneof([
            {uint16, uint16_gen()},
            {uint32, uint32_gen()},
            {int16, int16_gen()},
            {int32, range(-2147483648, 2147483647)},
            {int64, range(-9223372036854775808, 9223372036854775807)}
        ]),
        begin
            Encoded =
                case Type of
                    uint16 -> clickhouse_erl_types_integer:encode_uint16(Value);
                    uint32 -> clickhouse_erl_types_integer:encode_uint32(Value);
                    int16 -> clickhouse_erl_types_integer:encode_int16(Value);
                    int32 -> clickhouse_erl_types_integer:encode_int32(Value);
                    int64 -> clickhouse_erl_types_integer:encode_int64(Value)
                end,
            %% Verify little-endian by checking that least significant byte comes first
            %% For positive values, the first byte should be Value mod 256
            case Type of
                uint16 when Value >= 0 ->
                    <<FirstByte:8, _/binary>> = Encoded,
                    FirstByte =:= (Value rem 256);
                uint32 when Value >= 0 ->
                    <<FirstByte:8, _/binary>> = Encoded,
                    FirstByte =:= (Value rem 256);
                _ ->
                    %% For signed types and negative values, verify encoding/decoding works
                    DecodeResult =
                        case Type of
                            int16 -> clickhouse_erl_types_integer:decode_int16(Encoded);
                            int32 -> clickhouse_erl_types_integer:decode_int32(Encoded);
                            int64 -> clickhouse_erl_types_integer:decode_int64(Encoded);
                            _ -> {ok, Value, <<>>}
                        end,
                    case DecodeResult of
                        {ok, DecodedValue, <<>>} -> DecodedValue =:= Value;
                        _ -> false
                    end
            end
        end
    ).

%% ============================================================================
%% Property: IEEE 754 Compliance
%% **Validates: Requirements 8.1, 8.2, 2.5**
%% ============================================================================

prop_ieee754_compliance() ->
    ?FORALL(
        {Type, Value},
        oneof([
            {float32, float32_gen()},
            {float64, float64_gen()}
        ]),
        begin
            Encoded =
                case Type of
                    float32 -> clickhouse_erl_types_float:encode_float32(Value);
                    float64 -> clickhouse_erl_types_float:encode_float64(Value)
                end,
            %% Verify the encoding is the correct size
            ExpectedSize =
                case Type of
                    float32 -> 4;
                    float64 -> 8
                end,
            SizeCorrect = byte_size(Encoded) =:= ExpectedSize,
            %% Verify round-trip preserves special values exactly
            DecodeResult =
                case Type of
                    float32 -> clickhouse_erl_types_float:decode_float32(Encoded);
                    float64 -> clickhouse_erl_types_float:decode_float64(Encoded)
                end,
            RoundTripCorrect =
                case {Value, DecodeResult} of
                    {infinity, {ok, infinity, <<>>}} ->
                        true;
                    {'-infinity', {ok, '-infinity', <<>>}} ->
                        true;
                    {nan, {ok, nan, <<>>}} ->
                        true;
                    {_, {ok, DecodedValue, <<>>}} when is_float(DecodedValue) ->
                        %% For regular floats, verify re-encoding produces same binary
                        ReEncoded =
                            case Type of
                                float32 ->
                                    clickhouse_erl_types_float:encode_float32(DecodedValue);
                                float64 ->
                                    clickhouse_erl_types_float:encode_float64(DecodedValue)
                            end,
                        ReEncoded =:= Encoded;
                    _ ->
                        false
                end,
            SizeCorrect andalso RoundTripCorrect
        end
    ).

%% ============================================================================
%% Property: Boolean Protocol Compliance
%% **Validates: Requirements 8.1, 8.2, 4.1, 4.3**
%% ============================================================================

prop_bool_protocol_compliance() ->
    ?FORALL(
        Value,
        boolean(),
        begin
            Encoded = clickhouse_erl_types_integer:encode_bool(Value),
            %% Verify encoding matches protocol
            ExpectedBinary =
                case Value of
                    false -> <<0>>;
                    true -> <<1>>
                end,
            EncodingCorrect = Encoded =:= ExpectedBinary,
            %% Verify round-trip
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_bool(Encoded),
            RoundTripCorrect = Decoded =:= Value,
            EncodingCorrect andalso RoundTripCorrect
        end
    ).

%% ============================================================================
%% Property: Binary Size Compliance
%% **Validates: Requirements 8.1, 8.2**
%% ============================================================================

prop_binary_size_compliance() ->
    ?FORALL(
        {Type, Value},
        oneof([
            {uint8, range(0, 255)},
            {uint16, uint16_gen()},
            {uint32, uint32_gen()},
            {int8, int8_gen()},
            {int16, int16_gen()},
            {int32, range(-2147483648, 2147483647)},
            {int64, range(-9223372036854775808, 9223372036854775807)},
            {float32, float32_gen()},
            {float64, float64_gen()},
            {date, date_gen()},
            {datetime, datetime_gen()},
            {datetime64, datetime64_gen()},
            {bool, boolean()}
        ]),
        begin
            Encoded =
                case Type of
                    uint8 -> clickhouse_erl_types_integer:encode_uint8(Value);
                    uint16 -> clickhouse_erl_types_integer:encode_uint16(Value);
                    uint32 -> clickhouse_erl_types_integer:encode_uint32(Value);
                    int8 -> clickhouse_erl_types_integer:encode_int8(Value);
                    int16 -> clickhouse_erl_types_integer:encode_int16(Value);
                    int32 -> clickhouse_erl_types_integer:encode_int32(Value);
                    int64 -> clickhouse_erl_types_integer:encode_int64(Value);
                    float32 -> clickhouse_erl_types_float:encode_float32(Value);
                    float64 -> clickhouse_erl_types_float:encode_float64(Value);
                    date -> clickhouse_erl_types_temporal:encode_date(Value);
                    datetime -> clickhouse_erl_types_temporal:encode_datetime(Value);
                    datetime64 -> clickhouse_erl_types_temporal:encode_datetime64(Value, 3);
                    bool -> clickhouse_erl_types_integer:encode_bool(Value)
                end,
            %% Verify the encoded binary has the expected size
            ExpectedSize =
                case Type of
                    uint8 -> 1;
                    uint16 -> 2;
                    uint32 -> 4;
                    int8 -> 1;
                    int16 -> 2;
                    int32 -> 4;
                    int64 -> 8;
                    float32 -> 4;
                    float64 -> 8;
                    date -> 2;
                    datetime -> 4;
                    datetime64 -> 8;
                    bool -> 1
                end,
            byte_size(Encoded) =:= ExpectedSize
        end
    ).

%% ============================================================================
%% EUnit Wrappers for Property Tests
%% ============================================================================

protocol_compliance_property_test() ->
    ?assert(proper:quickcheck(prop_protocol_compliance(), [{numtests, 100}])).

little_endian_encoding_property_test() ->
    ?assert(proper:quickcheck(prop_little_endian_encoding(), [{numtests, 100}])).

ieee754_compliance_property_test() ->
    ?assert(proper:quickcheck(prop_ieee754_compliance(), [{numtests, 100}])).

bool_protocol_compliance_property_test() ->
    ?assert(proper:quickcheck(prop_bool_protocol_compliance(), [{numtests, 100}])).

binary_size_compliance_property_test() ->
    ?assert(proper:quickcheck(prop_binary_size_compliance(), [{numtests, 100}])).
