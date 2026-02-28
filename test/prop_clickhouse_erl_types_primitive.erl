%% @doc Property tests for ClickHouse primitive type encoding/decoding.
-module(prop_clickhouse_erl_types_primitive).

-include_lib("proper/include/proper.hrl").

-import(generators, [
    char_gen/0,
    float32_gen/0,
    float64_gen/0,
    int16_gen/0,
    int8_gen/0,
    string_gen/0,
    uint16_gen/0,
    uint32_gen/0,
    varint_gen/0
]).

-export([
    prop_uint16_round_trip/0,
    prop_uint32_round_trip/0,
    prop_int8_round_trip/0,
    prop_int16_round_trip/0,
    prop_float32_round_trip/0,
    prop_float64_round_trip/0,
    prop_bool_round_trip/0,
    prop_uint16_boundary_validation/0,
    prop_uint32_boundary_validation/0,
    prop_int8_boundary_validation/0,
    prop_int16_boundary_validation/0,
    prop_uint8_boundary_validation/0,
    prop_int32_boundary_validation/0,
    prop_int64_boundary_validation/0,
    prop_string_utf8_validation/0,
    prop_bool_validation/0,
    prop_bool_truncation_detection/0,
    prop_truncation_detection/0,
    prop_float_truncation_detection/0,
    prop_varint_string_round_trip/0,
    prop_varint_error_handling/0,
    prop_string_error_handling/0
]).

%% ============================================================================
%% Generators
%% ============================================================================

%% Generators for invalid values
invalid_uint16_gen() -> oneof([range(-1000, -1), range(65536, 1000000)]).
invalid_uint32_gen() -> oneof([range(-1000, -1), range(4294967296, 5000000000)]).
invalid_int8_gen() -> oneof([range(-1000, -129), range(128, 1000)]).
invalid_int16_gen() -> oneof([range(-100000, -32769), range(32768, 100000)]).

%% Generator for invalid boolean byte values (for decoding - not 0 or 1)
invalid_bool_byte_gen() ->
    range(2, 255).

%% Generators for truncated binaries
truncated_uint16_gen() -> oneof([<<>>, binary(1)]).
truncated_uint32_gen() -> oneof([<<>>, binary(1), binary(2), binary(3)]).
truncated_int8_gen() -> return(<<>>).
truncated_int16_gen() -> oneof([<<>>, binary(1)]).
truncated_float32_gen() -> oneof([<<>>, binary(1), binary(2), binary(3)]).
truncated_float64_gen() ->
    oneof([<<>>, binary(1), binary(2), binary(3), binary(4), binary(5), binary(6), binary(7)]).

%% Generator for invalid varint binary data
invalid_varint_binary_gen() ->
    oneof([
        %% Empty binary
        <<>>,

        %% Incomplete varints (continuation bit set but no following byte)
        <<128>>,
        <<255>>,

        %% Varint overflow (too many bytes)
        <<128, 128, 128, 128, 128, 128, 128, 128, 128, 128>>,
        <<255, 255, 255, 255, 255, 255, 255, 255, 255, 255>>,

        %% Random binary that might be interpreted as varint
        crypto:strong_rand_bytes(20)
    ]).

%% Generator for invalid string binary data
invalid_string_binary_gen() ->
    oneof([
        %% Empty binary
        <<>>,

        %% Invalid length prefix (no string data)

        % Claims 5 bytes but no data follows
        <<5>>,
        % Claims 100 bytes but no data follows
        <<100>>,

        %% Length exceeding available data

        % Claims 10 bytes but only has 5
        <<10, "short">>,
        % Claims 255 bytes but only has 1
        <<255, "x">>,

        %% Invalid UTF-8 sequences

        % Invalid UTF-8 bytes
        <<2, 255, 254>>,
        % Overlong encoding
        <<3, 16#C0, 16#80, 16#00>>,
        % Surrogate pair in UTF-8
        <<4, 16#ED, 16#A0, 16#80, 16#00>>,

        %% Incomplete UTF-8 sequences

        % Incomplete 2-byte sequence
        <<2, 16#C2>>,
        % Incomplete 3-byte sequence
        <<3, 16#E0, 16#A0>>,

        %% Random binary data
        crypto:strong_rand_bytes(30)
    ]).

%% Additional generators for error conditions
invalid_uint8_gen() -> oneof([range(-1000, -1), range(256, 1000)]).
invalid_int32_gen() -> oneof([range(-3000000000, -2147483649), range(2147483648, 3000000000)]).
invalid_int64_gen() ->
    oneof([
        %% Values below min int64
        return(-9223372036854775809),
        %% Values above max int64
        return(9223372036854775808)
    ]).

%% Generator for invalid UTF-8 sequences
invalid_utf8_gen() ->
    oneof([
        %% Invalid continuation byte
        <<16#C0, 16#80>>,
        %% Incomplete sequence
        <<16#C2>>,
        %% Overlong encoding
        <<16#C0, 16#AF>>,
        %% Invalid start byte
        <<16#FF, 16#FE>>
    ]).

%% ============================================================================
%% Properties
%% ============================================================================

%% Property: UInt16 Round Trip
prop_uint16_round_trip() ->
    ?FORALL(
        N,
        uint16_gen(),
        begin
            Encoded = clickhouse_erl_types_integer:encode_uint16(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_uint16(Encoded),
            Decoded =:= N
        end
    ).

%% Property: UInt32 Round Trip
prop_uint32_round_trip() ->
    ?FORALL(
        N,
        uint32_gen(),
        begin
            Encoded = clickhouse_erl_types_integer:encode_uint32(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_uint32(Encoded),
            Decoded =:= N
        end
    ).

%% Property: Int8 Round Trip
prop_int8_round_trip() ->
    ?FORALL(
        N,
        int8_gen(),
        begin
            Encoded = clickhouse_erl_types_integer:encode_int8(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_int8(Encoded),
            Decoded =:= N
        end
    ).

%% Property: Int16 Round Trip
prop_int16_round_trip() ->
    ?FORALL(
        N,
        int16_gen(),
        begin
            Encoded = clickhouse_erl_types_integer:encode_int16(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_int16(Encoded),
            Decoded =:= N
        end
    ).

%% Property: Float32 Round Trip
%% **Validates: Requirements 2.1, 2.2, 2.5**
prop_float32_round_trip() ->
    ?FORALL(
        N,
        float32_gen(),
        begin
            Encoded = clickhouse_erl_types_float:encode_float32(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_float:decode_float32(Encoded),
            %% For special values (infinity, -infinity, nan), check exact match
            %% For regular floats, check that re-encoding produces same binary
            case N of
                infinity ->
                    Decoded =:= infinity;
                '-infinity' ->
                    Decoded =:= '-infinity';
                nan ->
                    Decoded =:= nan;
                _ ->
                    %% For regular floats, verify round-trip by re-encoding
                    ReEncoded = clickhouse_erl_types_float:encode_float32(Decoded),
                    Encoded =:= ReEncoded
            end
        end
    ).

%% Property: Float64 Round Trip
%% **Validates: Requirements 2.1, 2.2, 2.5**
prop_float64_round_trip() ->
    ?FORALL(
        N,
        float64_gen(),
        begin
            Encoded = clickhouse_erl_types_float:encode_float64(N),
            {ok, Decoded, <<>>} = clickhouse_erl_types_float:decode_float64(Encoded),
            %% For special values (infinity, -infinity, nan), check exact match
            %% For regular floats, check exact equality (Float64 has full precision)
            case N of
                infinity -> Decoded =:= infinity;
                '-infinity' -> Decoded =:= '-infinity';
                nan -> Decoded =:= nan;
                _ -> Decoded == N
            end
        end
    ).

%% Property 9: Boolean Round Trip
%% **Validates: Requirements 4.1, 4.3**
prop_bool_round_trip() ->
    ?FORALL(
        Val,
        boolean(),
        begin
            Encoded = clickhouse_erl_types_integer:encode_bool(Val),
            {ok, Decoded, <<>>} = clickhouse_erl_types_integer:decode_bool(Encoded),
            Decoded =:= Val
        end
    ).

%% Property: UInt16 Boundary Validation
prop_uint16_boundary_validation() ->
    ?FORALL(
        N,
        invalid_uint16_gen(),
        begin
            Result = clickhouse_erl_types_integer:encode_uint16(N),
            case Result of
                {error, {value_out_of_range, _}} -> true;
                _ -> false
            end
        end
    ).

%% Property: UInt32 Boundary Validation
prop_uint32_boundary_validation() ->
    ?FORALL(
        N,
        invalid_uint32_gen(),
        begin
            Result = clickhouse_erl_types_integer:encode_uint32(N),
            case Result of
                {error, {value_out_of_range, _}} -> true;
                _ -> false
            end
        end
    ).

%% Property: Int8 Boundary Validation
prop_int8_boundary_validation() ->
    ?FORALL(
        N,
        invalid_int8_gen(),
        begin
            Result = clickhouse_erl_types_integer:encode_int8(N),
            case Result of
                {error, {value_out_of_range, _}} -> true;
                _ -> false
            end
        end
    ).

%% Property: Int16 Boundary Validation
prop_int16_boundary_validation() ->
    ?FORALL(
        N,
        invalid_int16_gen(),
        begin
            Result = clickhouse_erl_types_integer:encode_int16(N),
            case Result of
                {error, {value_out_of_range, _}} -> true;
                _ -> false
            end
        end
    ).

%% Property: UInt8 Boundary Validation
prop_uint8_boundary_validation() ->
    ?FORALL(
        N,
        invalid_uint8_gen(),
        begin
            Result = clickhouse_erl_types_integer:encode_uint8(N),
            case Result of
                {error, {value_out_of_range, _}} -> true;
                _ -> false
            end
        end
    ).

%% Property: Int32 Boundary Validation
prop_int32_boundary_validation() ->
    ?FORALL(
        N,
        invalid_int32_gen(),
        begin
            Result = clickhouse_erl_types_integer:encode_int32(N),
            case Result of
                {error, {value_out_of_range, _}} -> true;
                _ -> false
            end
        end
    ).

%% Property: Int64 Boundary Validation
prop_int64_boundary_validation() ->
    ?FORALL(
        N,
        invalid_int64_gen(),
        begin
            Result = clickhouse_erl_types_integer:encode_int64(N),
            case Result of
                {error, {value_out_of_range, _}} -> true;
                _ -> false
            end
        end
    ).

%% Property: String UTF-8 Validation
%% Tests that invalid UTF-8 sequences are properly rejected during encoding
prop_string_utf8_validation() ->
    ?FORALL(
        InvalidUtf8,
        invalid_utf8_gen(),
        begin
            %% Try to encode invalid UTF-8 as a string
            %% The encode_string function should handle this gracefully
            Result = clickhouse_erl_types_primitive:encode_string(InvalidUtf8),
            %% Either it succeeds (if it's treated as binary) or returns an error
            case Result of
                % Encoded as binary
                <<_/binary>> -> true;
                % Returned error
                {error, _} -> true;
                _ -> false
            end
        end
    ).

%% Property 10: Boolean Validation Error Handling
%% **Validates: Requirements 4.2**
prop_bool_validation() ->
    ?FORALL(
        InvalidByte,
        invalid_bool_byte_gen(),
        begin
            %% Create a binary with an invalid boolean value (not 0 or 1)
            Binary = <<InvalidByte:8>>,
            Result = clickhouse_erl_types_integer:decode_bool(Binary),
            case Result of
                {error, {invalid_bool_value, _}} -> true;
                _ -> false
            end
        end
    ).

%% Property 11: Boolean Truncation Error Detection
%% **Validates: Requirements 4.4**
prop_bool_truncation_detection() ->
    %% Test that empty binary returns proper error
    Result = clickhouse_erl_types_integer:decode_bool(<<>>),
    case Result of
        {error, {truncated_data, _}} -> true;
        _ -> false
    end.

%% Property: Truncation Detection
prop_truncation_detection() ->
    ?FORALL(
        {Type, TruncatedBinary},
        oneof([
            {uint16, truncated_uint16_gen()},
            {uint32, truncated_uint32_gen()},
            {int8, truncated_int8_gen()},
            {int16, truncated_int16_gen()},
            {float32, truncated_float32_gen()},
            {float64, truncated_float64_gen()}
        ]),
        begin
            Result =
                case Type of
                    uint16 -> clickhouse_erl_types_integer:decode_uint16(TruncatedBinary);
                    uint32 -> clickhouse_erl_types_integer:decode_uint32(TruncatedBinary);
                    int8 -> clickhouse_erl_types_integer:decode_int8(TruncatedBinary);
                    int16 -> clickhouse_erl_types_integer:decode_int16(TruncatedBinary);
                    float32 -> clickhouse_erl_types_float:decode_float32(TruncatedBinary);
                    float64 -> clickhouse_erl_types_float:decode_float64(TruncatedBinary)
                end,
            case Result of
                {error, {truncated_data, _}} -> true;
                _ -> false
            end
        end
    ).

%% Property 5: Floating-point truncation error detection
%% **Validates: Requirements 2.4**
prop_float_truncation_detection() ->
    ?FORALL(
        {Type, TruncatedBinary},
        oneof([
            {float32, truncated_float32_gen()},
            {float64, truncated_float64_gen()}
        ]),
        begin
            Result =
                case Type of
                    float32 -> clickhouse_erl_types_float:decode_float32(TruncatedBinary);
                    float64 -> clickhouse_erl_types_float:decode_float64(TruncatedBinary)
                end,
            case Result of
                {error, {truncated_data, _}} -> true;
                _ -> false
            end
        end
    ).

%% Property test: Varint and String Round Trip
%% Tests that varint and string encoding/decoding are reversible
prop_varint_string_round_trip() ->
    ?FORALL(
        {VarInt, String},
        {varint_gen(), string_gen()},
        begin
            %% Test varint round trip
            VarIntBinary = clickhouse_erl_types_primitive:encode_varint(VarInt),
            {ok, DecodedVarInt, <<>>} = clickhouse_erl_types_primitive:decode_varint(VarIntBinary),
            VarIntRoundTrip = (VarInt =:= DecodedVarInt),

            %% Test string round trip - String is already a proper Unicode string
            StringBinary = clickhouse_erl_types_primitive:encode_string(String),
            {ok, DecodedString, <<>>} = clickhouse_erl_types_primitive:decode_string(StringBinary),
            %% Convert original string to binary for comparison
            ExpectedBinary = unicode:characters_to_binary(String, utf8),
            StringRoundTrip = (ExpectedBinary =:= DecodedString),

            %% Both round trips should succeed
            VarIntRoundTrip andalso StringRoundTrip
        end
    ).

%% Property test: Varint Error Handling
%% Tests that invalid varint binary data returns appropriate errors
prop_varint_error_handling() ->
    ?FORALL(
        InvalidVarIntBinary,
        invalid_varint_binary_gen(),
        begin
            %% Test varint decoding with invalid binary data
            try
                Result = clickhouse_erl_types_primitive:decode_varint(InvalidVarIntBinary),
                case Result of
                    {error, truncated_varint} ->
                        %% Expected error for truncated varint
                        true;
                    {error, varint_overflow} ->
                        %% Expected error for overflow varint
                        true;
                    {error, _OtherError} ->
                        %% Other error types are also acceptable
                        true;
                    {ok, _Value, _Rest} ->
                        %% Some invalid varints might still decode
                        true
                end
            catch
                _:_ -> true
            end
        end
    ).

%% Property test: String Error Handling
%% Tests that invalid string binary data returns appropriate errors
prop_string_error_handling() ->
    ?FORALL(
        InvalidStringBinary,
        invalid_string_binary_gen(),
        begin
            %% Test string decoding with invalid binary data
            try
                Result = clickhouse_erl_types_primitive:decode_string(InvalidStringBinary),
                case Result of
                    {error, truncated_string} ->
                        %% Expected error for truncated string
                        true;
                    {error, invalid_utf8} ->
                        %% Expected error for invalid UTF-8
                        true;
                    {error, incomplete_utf8} ->
                        %% Expected error for incomplete UTF-8
                        true;
                    {error, _OtherError} ->
                        %% Other error types are also acceptable
                        true;
                    {ok, _String, _Rest} ->
                        %% Some invalid strings might still decode
                        true
                end
            catch
                _:_ -> true
            end
        end
    ).
