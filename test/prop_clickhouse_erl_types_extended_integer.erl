%% @doc Property-based tests for extended integer type encoding and decoding
-module(prop_clickhouse_erl_types_extended_integer).

-include_lib("proper/include/proper.hrl").

-export([
    prop_int128_encode_decode_roundtrip/0,
    prop_uint128_encode_decode_roundtrip/0,
    prop_int256_encode_decode_roundtrip/0,
    prop_uint256_encode_decode_roundtrip/0,
    prop_int128_byte_structure/0,
    prop_uint128_byte_structure/0,
    prop_int256_byte_structure/0,
    prop_uint256_byte_structure/0,
    prop_int128_representation_choice/0,
    prop_uint128_representation_choice/0,
    prop_int128_range_validation/0,
    prop_uint128_range_validation/0
]).

%%%===================================================================
%%% Generators
%%%===================================================================

%% Generator for valid Int128 values
%% Int128 range: -2^127 to 2^127-1
int128_gen() ->
    Min = -170141183460469231731687303715884105728,
    Max = 170141183460469231731687303715884105727,
    ?LET(N, range(Min, Max), N).

%% Generator for valid UInt128 values
%% UInt128 range: 0 to 2^128-1
uint128_gen() ->
    Max = 340282366920938463463374607431768211455,
    ?LET(N, range(0, Max), N).

%% Generator for valid Int256 values
%% Int256 range: -2^255 to 2^255-1
int256_gen() ->
    Min = -57896044618658097711785492504343953926634992332820282019728792003956564819968,
    Max = 57896044618658097711785492504343953926634992332820282019728792003956564819967,
    ?LET(N, range(Min, Max), N).

%% Generator for valid UInt256 values
%% UInt256 range: 0 to 2^256-1
uint256_gen() ->
    Max = 115792089237316195423570985008687907853269984665640564039457584007913129639935,
    ?LET(N, range(0, Max), N).

%% Generator for out-of-range Int128 values
%% Values below -2^127 or above 2^127-1
int128_out_of_range_gen() ->
    Min = -170141183460469231731687303715884105728,
    Max = 170141183460469231731687303715884105727,
    oneof([
        % Values below minimum
        ?LET(N, range(Min - 1000000, Min - 1), N),
        % Values above maximum
        ?LET(N, range(Max + 1, Max + 1000000), N)
    ]).

%% Generator for out-of-range UInt128 values
%% Values below 0 or above 2^128-1
uint128_out_of_range_gen() ->
    Max = 340282366920938463463374607431768211455,
    oneof([
        % Negative values
        ?LET(N, range(-1000000, -1), N),
        % Values above maximum
        ?LET(N, range(Max + 1, Max + 1000000), N)
    ]).

%%%===================================================================
%%% Property 1: Int128/UInt128 encode-decode roundtrip
%%% Feature: extended-types-support
%%% Validates: Requirements 1.1, 1.2, 1.5, 1.6
%%%===================================================================

%% @doc Property: For any valid Int128 value, encoding then decoding should
%% produce an equivalent value.
prop_int128_encode_decode_roundtrip() ->
    ?FORALL(
        Value,
        int128_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_extended_integer:encode_int128(Value),
            {ok, Decoded, <<>>} = clickhouse_erl_types_extended_integer:decode_int128(Encoded),
            Value =:= Decoded
        end
    ).

%% @doc Property: For any valid UInt128 value, encoding then decoding should
%% produce an equivalent value.
prop_uint128_encode_decode_roundtrip() ->
    ?FORALL(
        Value,
        uint128_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_extended_integer:encode_uint128(Value),
            {ok, Decoded, <<>>} = clickhouse_erl_types_extended_integer:decode_uint128(Encoded),
            Value =:= Decoded
        end
    ).

%%%===================================================================
%%% Property 2: Int256/UInt256 encode-decode roundtrip
%%% Feature: extended-types-support
%%% Validates: Requirements 1.3, 1.4, 1.7, 1.8
%%%===================================================================

%% @doc Property: For any valid Int256 value, encoding then decoding should
%% produce an equivalent value.
prop_int256_encode_decode_roundtrip() ->
    ?FORALL(
        Value,
        int256_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_extended_integer:encode_int256(Value),
            {ok, Decoded, <<>>} = clickhouse_erl_types_extended_integer:decode_int256(Encoded),
            Value =:= Decoded
        end
    ).

%% @doc Property: For any valid UInt256 value, encoding then decoding should
%% produce an equivalent value.
prop_uint256_encode_decode_roundtrip() ->
    ?FORALL(
        Value,
        uint256_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_extended_integer:encode_uint256(Value),
            {ok, Decoded, <<>>} = clickhouse_erl_types_extended_integer:decode_uint256(Encoded),
            Value =:= Decoded
        end
    ).

%%%===================================================================
%%% Property 3: Extended integer byte structure
%%% Feature: extended-types-support
%%% Validates: Requirements 1.9, 1.10
%%%===================================================================

%% @doc Property: For any Int128 value, the encoded binary should be exactly
%% 16 bytes in little-endian format (low 64 bits first, high 64 bits second).
prop_int128_byte_structure() ->
    ?FORALL(
        Value,
        int128_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_extended_integer:encode_int128(Value),

            % Check byte length is exactly 16 bytes
            ByteLength = byte_size(Encoded),

            % Extract low and high 64-bit parts in little-endian order
            case Encoded of
                <<Low:64/little-signed, High:64/little-signed>> ->
                    % Reconstruct the value from parts using same logic as decode
                    Reconstructed = (High bsl 64) bor (Low band 16#FFFFFFFFFFFFFFFF),

                    % Verify byte length and value reconstruction
                    (ByteLength =:= 16) andalso (Reconstructed =:= Value);
                _ ->
                    false
            end
        end
    ).

%% @doc Property: For any UInt128 value, the encoded binary should be exactly
%% 16 bytes in little-endian format (low 64 bits first, high 64 bits second).
prop_uint128_byte_structure() ->
    ?FORALL(
        Value,
        uint128_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_extended_integer:encode_uint128(Value),

            % Check byte length is exactly 16 bytes
            ByteLength = byte_size(Encoded),

            % Extract low and high 64-bit parts in little-endian order
            case Encoded of
                <<Low:64/little-unsigned, High:64/little-unsigned>> ->
                    % Reconstruct the value from parts using same logic as decode
                    Reconstructed = (High bsl 64) bor Low,

                    % Verify byte length and value reconstruction
                    (ByteLength =:= 16) andalso (Reconstructed =:= Value);
                _ ->
                    false
            end
        end
    ).

%% @doc Property: For any Int256 value, the encoded binary should be exactly
%% 32 bytes in little-endian format (four 64-bit segments).
prop_int256_byte_structure() ->
    ?FORALL(
        Value,
        int256_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_extended_integer:encode_int256(Value),

            % Check byte length is exactly 32 bytes
            ByteLength = byte_size(Encoded),

            % Extract four 64-bit parts in little-endian order
            case Encoded of
                <<P0:64/little-signed, P1:64/little-signed, P2:64/little-signed,
                    P3:64/little-signed>> ->
                    % Reconstruct the value from parts using same logic as decode
                    Reconstructed =
                        (P3 bsl 192) bor
                            ((P2 band 16#FFFFFFFFFFFFFFFF) bsl 128) bor
                            ((P1 band 16#FFFFFFFFFFFFFFFF) bsl 64) bor
                            (P0 band 16#FFFFFFFFFFFFFFFF),

                    % Verify byte length and value reconstruction
                    (ByteLength =:= 32) andalso (Reconstructed =:= Value);
                _ ->
                    false
            end
        end
    ).

%% @doc Property: For any UInt256 value, the encoded binary should be exactly
%% 32 bytes in little-endian format (four 64-bit segments).
prop_uint256_byte_structure() ->
    ?FORALL(
        Value,
        uint256_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_extended_integer:encode_uint256(Value),

            % Check byte length is exactly 32 bytes
            ByteLength = byte_size(Encoded),

            % Extract four 64-bit parts in little-endian order
            case Encoded of
                <<P0:64/little-unsigned, P1:64/little-unsigned, P2:64/little-unsigned,
                    P3:64/little-unsigned>> ->
                    % Reconstruct the value from parts using same logic as decode
                    Reconstructed =
                        (P3 bsl 192) bor
                            (P2 bsl 128) bor
                            (P1 bsl 64) bor
                            P0,

                    % Verify byte length and value reconstruction
                    (ByteLength =:= 32) andalso (Reconstructed =:= Value);
                _ ->
                    false
            end
        end
    ).

%%%===================================================================
%%% Property 4: Extended integer representation choice
%%% Feature: extended-types-support
%%% Validates: Requirements 1.11, 1.12
%%%===================================================================

%% @doc Property: For any valid Int128 value, decoding should return a plain
%% Erlang integer (not a tuple representation). Encoding should accept plain
%% Erlang integers.
prop_int128_representation_choice() ->
    ?FORALL(
        Value,
        int128_gen(),
        begin
            % Test encoding accepts plain integer (Requirement 1.12)
            EncodeResult = clickhouse_erl_types_extended_integer:encode_int128(Value),
            EncodingAcceptsPlainInt =
                case EncodeResult of
                    {ok, _} -> true;
                    _ -> false
                end,

            % Test decoding returns plain integer (Requirement 1.11)
            case EncodeResult of
                {ok, Encoded} ->
                    {ok, Decoded, <<>>} = clickhouse_erl_types_extended_integer:decode_int128(
                        Encoded
                    ),

                    % Verify decoded value is a plain integer (not a tuple)
                    DecodingReturnsPlainInt = is_integer(Decoded) andalso not is_tuple(Decoded),

                    % Verify the value is correct
                    ValueCorrect = (Decoded =:= Value),

                    EncodingAcceptsPlainInt andalso DecodingReturnsPlainInt andalso ValueCorrect;
                _ ->
                    false
            end
        end
    ).

%% @doc Property: For any valid UInt128 value, decoding should return a plain
%% Erlang integer (not a tuple representation). Encoding should accept plain
%% Erlang integers.
prop_uint128_representation_choice() ->
    ?FORALL(
        Value,
        uint128_gen(),
        begin
            % Test encoding accepts plain integer (Requirement 1.12)
            EncodeResult = clickhouse_erl_types_extended_integer:encode_uint128(Value),
            EncodingAcceptsPlainInt =
                case EncodeResult of
                    {ok, _} -> true;
                    _ -> false
                end,

            % Test decoding returns plain integer (Requirement 1.11)
            case EncodeResult of
                {ok, Encoded} ->
                    {ok, Decoded, <<>>} = clickhouse_erl_types_extended_integer:decode_uint128(
                        Encoded
                    ),

                    % Verify decoded value is a plain integer (not a tuple)
                    DecodingReturnsPlainInt = is_integer(Decoded) andalso not is_tuple(Decoded),

                    % Verify the value is correct
                    ValueCorrect = (Decoded =:= Value),

                    EncodingAcceptsPlainInt andalso DecodingReturnsPlainInt andalso ValueCorrect;
                _ ->
                    false
            end
        end
    ).

%%%===================================================================
%%% Property 5: Extended integer range validation
%%% Feature: extended-types-support
%%% Validates: Requirements 1.14
%%%===================================================================

%% @doc Property: For any value outside the valid Int128 range, encoding should
%% return an error tuple with range information. This property tests three aspects:
%% 1. Values within range are accepted
%% 2. Values outside range return proper error tuples
%% 3. Non-integer values return proper error tuples
prop_int128_range_validation() ->
    Min = -170141183460469231731687303715884105728,
    Max = 170141183460469231731687303715884105727,

    ?FORALL(
        {TestType, Value},
        oneof([
            {valid, int128_gen()},
            {out_of_range, int128_out_of_range_gen()},
            {non_integer, oneof([1.5, <<"binary">>, atom, {tuple}])}
        ]),
        begin
            Result = clickhouse_erl_types_extended_integer:encode_int128(Value),
            case TestType of
                valid ->
                    % Values within range should succeed
                    case Result of
                        {ok, _} -> true;
                        _ -> false
                    end;
                out_of_range ->
                    % Values outside range should return error with proper structure
                    case Result of
                        {error, {value_out_of_range, ErrorMap}} ->
                            maps:is_key(value, ErrorMap) andalso
                                maps:is_key(min, ErrorMap) andalso
                                maps:is_key(max, ErrorMap) andalso
                                maps:is_key(type, ErrorMap) andalso
                                maps:get(min, ErrorMap) =:= Min andalso
                                maps:get(max, ErrorMap) =:= Max andalso
                                maps:get(type, ErrorMap) =:= int128 andalso
                                maps:get(value, ErrorMap) =:= Value;
                        _ ->
                            false
                    end;
                non_integer ->
                    % Non-integer values should return invalid_value error
                    case Result of
                        {error, {invalid_value, ErrorMap}} ->
                            maps:is_key(value, ErrorMap) andalso
                                maps:is_key(expected_type, ErrorMap) andalso
                                maps:is_key(type, ErrorMap) andalso
                                maps:get(expected_type, ErrorMap) =:= integer andalso
                                maps:get(type, ErrorMap) =:= int128;
                        _ ->
                            false
                    end
            end
        end
    ).

%% @doc Property: For any value outside the valid UInt128 range, encoding should
%% return an error tuple with range information. This property tests three aspects:
%% 1. Values within range are accepted
%% 2. Values outside range return proper error tuples
%% 3. Non-integer values return proper error tuples
prop_uint128_range_validation() ->
    Min = 0,
    Max = 340282366920938463463374607431768211455,

    ?FORALL(
        {TestType, Value},
        oneof([
            {valid, uint128_gen()},
            {out_of_range, uint128_out_of_range_gen()},
            {non_integer, oneof([1.5, <<"binary">>, atom, {tuple}])}
        ]),
        begin
            Result = clickhouse_erl_types_extended_integer:encode_uint128(Value),
            case TestType of
                valid ->
                    % Values within range should succeed
                    case Result of
                        {ok, _} -> true;
                        _ -> false
                    end;
                out_of_range ->
                    % Values outside range should return error with proper structure
                    case Result of
                        {error, {value_out_of_range, ErrorMap}} ->
                            maps:is_key(value, ErrorMap) andalso
                                maps:is_key(min, ErrorMap) andalso
                                maps:is_key(max, ErrorMap) andalso
                                maps:is_key(type, ErrorMap) andalso
                                maps:get(min, ErrorMap) =:= Min andalso
                                maps:get(max, ErrorMap) =:= Max andalso
                                maps:get(type, ErrorMap) =:= uint128 andalso
                                maps:get(value, ErrorMap) =:= Value;
                        {error, {invalid_value, ErrorMap}} ->
                            % Negative values should return invalid_value error
                            maps:is_key(value, ErrorMap) andalso
                                maps:is_key(expected_type, ErrorMap) andalso
                                maps:is_key(type, ErrorMap) andalso
                                maps:get(expected_type, ErrorMap) =:= non_neg_integer andalso
                                maps:get(type, ErrorMap) =:= uint128;
                        _ ->
                            false
                    end;
                non_integer ->
                    % Non-integer values should return invalid_value error
                    case Result of
                        {error, {invalid_value, ErrorMap}} ->
                            maps:is_key(value, ErrorMap) andalso
                                maps:is_key(expected_type, ErrorMap) andalso
                                maps:is_key(type, ErrorMap) andalso
                                maps:get(expected_type, ErrorMap) =:= non_neg_integer andalso
                                maps:get(type, ErrorMap) =:= uint128;
                        _ ->
                            false
                    end
            end
        end
    ).
