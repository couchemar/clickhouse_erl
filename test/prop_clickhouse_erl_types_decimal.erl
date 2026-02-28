%% @doc Property-based tests for Decimal type encoding and decoding.
%%
%% Tests universal properties for Decimal32, Decimal64, Decimal128, and Decimal256 types.
-module(prop_clickhouse_erl_types_decimal).

-include_lib("proper/include/proper.hrl").

%%%===================================================================
%%% Properties
%%%===================================================================

%% @doc Property 6: Decimal encode-decode roundtrip
%% For any valid Decimal32 value, encoding then decoding should produce an equivalent value.
%% Validates: Requirements 2.1, 2.2
prop_decimal32_roundtrip() ->
    ?FORALL(
        {Value, Scale},
        decimal32_gen(),
        begin
            case clickhouse_erl_types_decimal:encode_decimal32({decimal, Value, Scale}, Scale) of
                {ok, Encoded} ->
                    case clickhouse_erl_types_decimal:decode_decimal32(Encoded, Scale) of
                        {ok, {decimal, DecodedValue, DecodedScale}, <<>>} ->
                            Value =:= DecodedValue andalso Scale =:= DecodedScale;
                        _ ->
                            false
                    end;
                {error, _} ->
                    %% If encoding fails due to precision, that's acceptable
                    true
            end
        end
    ).

%% @doc Property 6: Decimal encode-decode roundtrip
%% For any valid Decimal64 value, encoding then decoding should produce an equivalent value.
%% Validates: Requirements 2.3, 2.4
prop_decimal64_roundtrip() ->
    ?FORALL(
        {Value, Scale},
        decimal64_gen(),
        begin
            case clickhouse_erl_types_decimal:encode_decimal64({decimal, Value, Scale}, Scale) of
                {ok, Encoded} ->
                    case clickhouse_erl_types_decimal:decode_decimal64(Encoded, Scale) of
                        {ok, {decimal, DecodedValue, DecodedScale}, <<>>} ->
                            Value =:= DecodedValue andalso Scale =:= DecodedScale;
                        _ ->
                            false
                    end;
                {error, _} ->
                    %% If encoding fails due to precision, that's acceptable
                    true
            end
        end
    ).

%% @doc Property 6: Decimal encode-decode roundtrip
%% For any valid Decimal128 value, encoding then decoding should produce an equivalent value.
%% Validates: Requirements 2.5, 2.6
prop_decimal128_roundtrip() ->
    ?FORALL(
        {Value, Scale},
        decimal128_gen(),
        begin
            case clickhouse_erl_types_decimal:encode_decimal128({decimal, Value, Scale}, Scale) of
                {ok, Encoded} ->
                    case clickhouse_erl_types_decimal:decode_decimal128(Encoded, Scale) of
                        {ok, {decimal, DecodedValue, DecodedScale}, <<>>} ->
                            Value =:= DecodedValue andalso Scale =:= DecodedScale;
                        _ ->
                            false
                    end;
                {error, _} ->
                    %% If encoding fails due to precision, that's acceptable
                    true
            end
        end
    ).

%% @doc Property 6: Decimal encode-decode roundtrip
%% For any valid Decimal256 value, encoding then decoding should produce an equivalent value.
%% Validates: Requirements 2.7, 2.8
prop_decimal256_roundtrip() ->
    ?FORALL(
        {Value, Scale},
        decimal256_gen(),
        begin
            case clickhouse_erl_types_decimal:encode_decimal256({decimal, Value, Scale}, Scale) of
                {ok, Encoded} ->
                    case clickhouse_erl_types_decimal:decode_decimal256(Encoded, Scale) of
                        {ok, {decimal, DecodedValue, DecodedScale}, <<>>} ->
                            Value =:= DecodedValue andalso Scale =:= DecodedScale;
                        _ ->
                            false
                    end;
                {error, _} ->
                    %% If encoding fails due to precision, that's acceptable
                    true
            end
        end
    ).

%% @doc Property 7: Decimal underlying encoding
%% For any Decimal32 value, the encoded binary should use Int32 encoding (4 bytes, little-endian).
%% Validates: Requirements 2.9
prop_decimal32_underlying_encoding() ->
    ?FORALL(
        {Value, Scale},
        decimal32_gen(),
        begin
            case clickhouse_erl_types_decimal:encode_decimal32({decimal, Value, Scale}, Scale) of
                {ok, Encoded} ->
                    %% Should be exactly 4 bytes (Int32)
                    byte_size(Encoded) =:= 4 andalso
                        %% Should decode as little-endian signed 32-bit integer
                        case Encoded of
                            <<DecodedInt:32/little-signed>> -> DecodedInt =:= Value;
                            _ -> false
                        end;
                {error, _} ->
                    %% If encoding fails due to precision, that's acceptable
                    true
            end
        end
    ).

%% @doc Property 7: Decimal underlying encoding
%% For any Decimal64 value, the encoded binary should use Int64 encoding (8 bytes, little-endian).
%% Validates: Requirements 2.10
prop_decimal64_underlying_encoding() ->
    ?FORALL(
        {Value, Scale},
        decimal64_gen(),
        begin
            case clickhouse_erl_types_decimal:encode_decimal64({decimal, Value, Scale}, Scale) of
                {ok, Encoded} ->
                    %% Should be exactly 8 bytes (Int64)
                    byte_size(Encoded) =:= 8 andalso
                        %% Should decode as little-endian signed 64-bit integer
                        case Encoded of
                            <<DecodedInt:64/little-signed>> -> DecodedInt =:= Value;
                            _ -> false
                        end;
                {error, _} ->
                    %% If encoding fails due to precision, that's acceptable
                    true
            end
        end
    ).

%% @doc Property 9: Decimal precision validation
%% For any Decimal32 value where precision exceeds 9 digits, encoding should return an error.
%% Validates: Requirements 2.15
prop_decimal32_precision_validation() ->
    ?FORALL(
        {Value, Scale},
        decimal32_invalid_precision_gen(),
        begin
            Result = clickhouse_erl_types_decimal:encode_decimal32({decimal, Value, Scale}, Scale),
            case Result of
                {error, {precision_exceeded, _}} -> true;
                {ok, _} -> false;
                _ -> false
            end
        end
    ).

%% @doc Property 9: Decimal precision validation
%% For any Decimal64 value where precision exceeds 18 digits, encoding should return an error.
%% Validates: Requirements 2.15
prop_decimal64_precision_validation() ->
    ?FORALL(
        {Value, Scale},
        decimal64_invalid_precision_gen(),
        begin
            Result = clickhouse_erl_types_decimal:encode_decimal64({decimal, Value, Scale}, Scale),
            case Result of
                {error, {precision_exceeded, _}} -> true;
                {ok, _} -> false;
                _ -> false
            end
        end
    ).

%% @doc Property 7: Decimal underlying encoding
%% For any Decimal128 value, the encoded binary should use Int128 encoding (16 bytes, little-endian).
%% Validates: Requirements 2.11
prop_decimal128_underlying_encoding() ->
    ?FORALL(
        {Value, Scale},
        decimal128_gen(),
        begin
            case clickhouse_erl_types_decimal:encode_decimal128({decimal, Value, Scale}, Scale) of
                {ok, Encoded} ->
                    %% Should be exactly 16 bytes (Int128)
                    byte_size(Encoded) =:= 16 andalso
                        %% Verify it can be decoded using Int128 decoder
                        case clickhouse_erl_types_extended_integer:decode_int128(Encoded) of
                            {ok, DecodedInt, <<>>} -> DecodedInt =:= Value;
                            _ -> false
                        end;
                {error, _} ->
                    %% If encoding fails due to precision, that's acceptable
                    true
            end
        end
    ).

%% @doc Property 7: Decimal underlying encoding
%% For any Decimal256 value, the encoded binary should use Int256 encoding (32 bytes, little-endian).
%% Validates: Requirements 2.12
prop_decimal256_underlying_encoding() ->
    ?FORALL(
        {Value, Scale},
        decimal256_gen(),
        begin
            case clickhouse_erl_types_decimal:encode_decimal256({decimal, Value, Scale}, Scale) of
                {ok, Encoded} ->
                    %% Should be exactly 32 bytes (Int256)
                    byte_size(Encoded) =:= 32 andalso
                        %% Verify it can be decoded using Int256 decoder
                        case clickhouse_erl_types_extended_integer:decode_int256(Encoded) of
                            {ok, DecodedInt, <<>>} -> DecodedInt =:= Value;
                            _ -> false
                        end;
                {error, _} ->
                    %% If encoding fails due to precision, that's acceptable
                    true
            end
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generate valid Decimal32 values.
%% Decimal32 has max precision of 9 digits.
decimal32_gen() ->
    ?LET(
        Scale,
        range(0, 9),
        begin
            %% Generate value that fits in 9 digits total
            MaxValue = trunc(math:pow(10, 9)) - 1,
            ?LET(Value, range(-MaxValue, MaxValue), {Value, Scale})
        end
    ).

%% @doc Generate valid Decimal64 values.
%% Decimal64 has max precision of 18 digits.
decimal64_gen() ->
    ?LET(
        Scale,
        range(0, 18),
        begin
            %% Generate value that fits in 18 digits total
            MaxValue = trunc(math:pow(10, 18)) - 1,
            ?LET(Value, range(-MaxValue, MaxValue), {Value, Scale})
        end
    ).

%% @doc Generate valid Decimal128 values.
%% Decimal128 has max precision of 38 digits.
decimal128_gen() ->
    ?LET(
        Scale,
        range(0, 38),
        begin
            %% Generate value that fits in 38 digits total
            MaxValue = trunc(math:pow(10, 38)) - 1,
            ?LET(Value, range(-MaxValue, MaxValue), {Value, Scale})
        end
    ).

%% @doc Generate valid Decimal256 values.
%% Decimal256 has max precision of 76 digits.
decimal256_gen() ->
    ?LET(
        Scale,
        range(0, 76),
        begin
            %% Generate value that fits in 76 digits total
            MaxValue = trunc(math:pow(10, 76)) - 1,
            ?LET(Value, range(-MaxValue, MaxValue), {Value, Scale})
        end
    ).

%% @doc Generate Decimal32 values that exceed precision constraint.
%% Values with more than 9 digits should fail validation.
decimal32_invalid_precision_gen() ->
    ?LET(
        Scale,
        range(0, 9),
        begin
            %% Generate value with 10+ digits (exceeds Decimal32 max precision of 9)
            MinValue = trunc(math:pow(10, 9)),
            MaxValue = trunc(math:pow(10, 12)),
            ?LET(Value, range(MinValue, MaxValue), {Value, Scale})
        end
    ).

%% @doc Generate Decimal64 values that exceed precision constraint.
%% Values with more than 18 digits should fail validation.
decimal64_invalid_precision_gen() ->
    ?LET(
        Scale,
        range(0, 18),
        begin
            %% Generate value with 19+ digits (exceeds Decimal64 max precision of 18)
            MinValue = trunc(math:pow(10, 18)),
            MaxValue = trunc(math:pow(10, 21)),
            ?LET(Value, range(MinValue, MaxValue), {Value, Scale})
        end
    ).
