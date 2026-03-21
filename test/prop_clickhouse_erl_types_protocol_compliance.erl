%% @doc Property-based protocol compliance tests for ClickHouse type encoding/decoding.
%%
%% This module validates that our encoding matches the ClickHouse binary protocol
%% specifications using property-based testing with PropEr.
%%
%% **Validates: Requirements 8.1, 8.2, 8.3**
-module(prop_clickhouse_erl_types_protocol_compliance).

-include_lib("proper/include/proper.hrl").

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

-export([
    prop_protocol_compliance/0,
    prop_little_endian_encoding/0,
    prop_ieee754_compliance/0,
    prop_bool_protocol_compliance/0,
    prop_binary_size_compliance/0
]).

%%%===================================================================
%%% Generators
%%%===================================================================

%% Generator for valid DateTime64 values (milliseconds since epoch)
datetime64_gen() ->
    ?LET(N, range(0, 1000000000000), N).

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

%%%===================================================================
%%% Property 1: Protocol Compliance
%%% Feature: extended-types-support
%%% Validates: Requirements 8.1, 8.2, 8.3
%%%===================================================================

%% @doc Property: Encoded binaries match expected protocol format
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

%%%===================================================================
%%% Property 2: Little-Endian Encoding
%%% Feature: extended-types-support
%%% Validates: Requirements 8.1, 8.2
%%%===================================================================

%% @doc Property: Multi-byte integers use little-endian encoding
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

%%%===================================================================
%%% Property 3: IEEE 754 Compliance
%%% Feature: extended-types-support
%%% Validates: Requirements 8.1, 8.2, 2.5
%%%===================================================================

%% @doc Property: Floating-point types use IEEE 754 encoding
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

%%%===================================================================
%%% Property 4: Boolean Protocol Compliance
%%% Feature: extended-types-support
%%% Validates: Requirements 8.1, 8.2, 4.1, 4.3
%%%===================================================================

%% @doc Property: Boolean values encode as UInt8 (0 or 1)
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

%%%===================================================================
%%% Property 5: Binary Size Compliance
%%% Feature: extended-types-support
%%% Validates: Requirements 8.1, 8.2
%%%===================================================================

%% @doc Property: All types encode to expected binary sizes
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
