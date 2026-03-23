%% @doc Decimal type encoding and decoding for ClickHouse.
%%
%% Supports Decimal32, Decimal64, Decimal128, and Decimal256 types.
%% Decimals are stored as scaled integers with a specified precision and scale.
%%
%% Type Representations:
%% - Decimal values: {decimal, Value :: integer(), Scale :: non_neg_integer()}
%%   where Value is the scaled integer (e.g., 12345 for 123.45 with scale 2)
%% - Decimal types: {decimal32, Precision, Scale} | {decimal64, Precision, Scale}
%%                  {decimal128, Precision, Scale} | {decimal256, Precision, Scale}
%%
%% Encoding Format:
%% - Decimal32: Int32 encoding (4 bytes, little-endian)
%% - Decimal64: Int64 encoding (8 bytes, little-endian)
%% - Decimal128: Int128 encoding (16 bytes, little-endian)
%% - Decimal256: Int256 encoding (32 bytes, little-endian)
%%
%% Precision Limits:
%% - Decimal32: Up to 9 digits
%% - Decimal64: Up to 18 digits
%% - Decimal128: Up to 38 digits
%% - Decimal256: Up to 76 digits
%%
%% Usage Examples:
%%
%% ```
%% % Encode Decimal64 with scale 4 (123.4567)
%% {ok, Binary} = encode_decimal64({decimal, 1234567, 4}, 4).
%%
%% % Decode Decimal64
%% {ok, {decimal, 1234567, 4}, Rest} = decode_decimal64(Binary, 4).
%%
%% % Convert float to decimal
%% {ok, Binary2} = encode_decimal32(99.995, 4).
%% % Internally converts to {decimal, 999950, 4}
%%
%% % Parse decimal type string
%% {ok, {decimal64, 18, 4}} = parse_decimal_type(<<"Decimal64(18, 4)">>).
%%
%% % Precision validation error
%% {error, {precision_exceeded, _}} = encode_decimal32({decimal, 1234567890, 2}, 2).
%% '''
%%
%% Error Cases:
%% - {precision_exceeded, Details} - Value exceeds type precision
%% - {invalid_decimal_value, Value} - Invalid value type
%% - {truncated_data, Details} - Binary too short for decoding
%% - {invalid_decimal_type, Type} - Invalid type string format
-module(clickhouse_erl_types_decimal).

%% API exports
-export([
    encode_decimal32/2,
    decode_decimal32/2,
    encode_decimal64/2,
    decode_decimal64/2,
    encode_decimal128/2,
    decode_decimal128/2,
    encode_decimal256/2,
    decode_decimal256/2,
    parse_decimal_type/1,
    % Column decoding
    decode_decimal32_column/3,
    decode_decimal64_column/3,
    decode_decimal128_column/3,
    decode_decimal256_column/3
]).

%% Includes
-include_lib("kernel/include/logger.hrl").

%% Type definitions and exports
-export_type([
    decimal_value/0,
    decimal_type/0,
    decimal32_type/0,
    decimal64_type/0,
    decimal128_type/0,
    decimal256_type/0
]).

-type decimal_value() :: {decimal, Value :: integer(), Scale :: non_neg_integer()}.
-type decimal32_type() :: {decimal32, Precision :: 1..9, Scale :: non_neg_integer()}.
-type decimal64_type() :: {decimal64, Precision :: 1..18, Scale :: non_neg_integer()}.
-type decimal128_type() :: {decimal128, Precision :: 1..38, Scale :: non_neg_integer()}.
-type decimal256_type() :: {decimal256, Precision :: 1..76, Scale :: non_neg_integer()}.
-type decimal_type() :: decimal32_type() | decimal64_type() | decimal128_type() | decimal256_type().

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Encode a Decimal32 value.
%% Accepts {decimal, Value, Scale} tuple or plain integer/float.
%% Returns 4-byte little-endian binary.
%% Validates precision constraints (max 9 digits).
-spec encode_decimal32(decimal_value() | integer() | float(), non_neg_integer()) ->
    {ok, binary()} | {error, term()}.
encode_decimal32({decimal, Value, _Scale}, TypeScale) when is_integer(Value) ->
    case validate_precision(Value, TypeScale, 9) of
        ok -> encode_int32(Value);
        {error, Reason} -> {error, Reason}
    end;
encode_decimal32(Value, TypeScale) when is_integer(Value) ->
    ScaledValue = Value * round(math:pow(10, TypeScale)),
    case validate_precision(ScaledValue, TypeScale, 9) of
        ok -> encode_int32(ScaledValue);
        {error, Reason} -> {error, Reason}
    end;
encode_decimal32(Value, Scale) when is_float(Value) ->
    ScaledValue = round(Value * math:pow(10, Scale)),
    case validate_precision(ScaledValue, Scale, 9) of
        ok -> encode_int32(ScaledValue);
        {error, Reason} -> {error, Reason}
    end;
encode_decimal32(Value, _Scale) ->
    {error, {invalid_decimal_value, Value}}.

%% @doc Decode a Decimal32 value.
%% Parses 4-byte little-endian binary and returns {decimal, Value, Scale} tuple.
-spec decode_decimal32(binary(), non_neg_integer()) ->
    {ok, decimal_value(), binary()} | {error, term()}.
decode_decimal32(<<Value:32/little-signed, Rest/binary>>, Scale) ->
    {ok, {decimal, Value, Scale}, Rest};
decode_decimal32(Binary, _Scale) when byte_size(Binary) < 4 ->
    {error,
        {truncated_data, #{
            expected_bytes => 4, actual_bytes => byte_size(Binary), type => decimal32
        }}};
decode_decimal32(_Binary, _Scale) ->
    {error, {invalid_format, #{type => decimal32}}}.

%% @doc Encode a Decimal64 value.
%% Accepts {decimal, Value, Scale} tuple or plain integer/float.
%% Returns 8-byte little-endian binary.
%% Validates precision constraints (max 18 digits).
-spec encode_decimal64(decimal_value() | integer() | float(), non_neg_integer()) ->
    {ok, binary()} | {error, term()}.
encode_decimal64({decimal, Value, _Scale}, TypeScale) when is_integer(Value) ->
    case validate_precision(Value, TypeScale, 18) of
        ok -> encode_int64(Value);
        {error, Reason} -> {error, Reason}
    end;
encode_decimal64(Value, TypeScale) when is_integer(Value) ->
    ScaledValue = Value * round(math:pow(10, TypeScale)),
    case validate_precision(ScaledValue, TypeScale, 18) of
        ok -> encode_int64(ScaledValue);
        {error, Reason} -> {error, Reason}
    end;
encode_decimal64(Value, Scale) when is_float(Value) ->
    ScaledValue = round(Value * math:pow(10, Scale)),
    case validate_precision(ScaledValue, Scale, 18) of
        ok -> encode_int64(ScaledValue);
        {error, Reason} -> {error, Reason}
    end;
encode_decimal64(Value, _Scale) ->
    {error, {invalid_decimal_value, Value}}.

%% @doc Decode a Decimal64 value.
%% Parses 8-byte little-endian binary and returns {decimal, Value, Scale} tuple.
-spec decode_decimal64(binary(), non_neg_integer()) ->
    {ok, decimal_value(), binary()} | {error, term()}.
decode_decimal64(<<Value:64/little-signed, Rest/binary>>, Scale) ->
    {ok, {decimal, Value, Scale}, Rest};
decode_decimal64(Binary, _Scale) when byte_size(Binary) < 8 ->
    {error,
        {truncated_data, #{
            expected_bytes => 8, actual_bytes => byte_size(Binary), type => decimal64
        }}};
decode_decimal64(_Binary, _Scale) ->
    {error, {invalid_format, #{type => decimal64}}}.

%% @doc Encode a Decimal128 value.
%% Accepts {decimal, Value, Scale} tuple or plain integer/float.
%% Returns 16-byte little-endian binary using Int128 encoding.
%% Validates precision constraints (max 38 digits).
-spec encode_decimal128(decimal_value() | integer() | float(), non_neg_integer()) ->
    {ok, binary()} | {error, term()}.
encode_decimal128({decimal, Value, _Scale}, TypeScale) when is_integer(Value) ->
    case validate_precision(Value, TypeScale, 38) of
        ok -> clickhouse_erl_types_extended_integer:encode_int128(Value);
        {error, Reason} -> {error, Reason}
    end;
encode_decimal128(Value, TypeScale) when is_integer(Value) ->
    ScaledValue = Value * round(math:pow(10, TypeScale)),
    case validate_precision(ScaledValue, TypeScale, 38) of
        ok -> clickhouse_erl_types_extended_integer:encode_int128(ScaledValue);
        {error, Reason} -> {error, Reason}
    end;
encode_decimal128(Value, Scale) when is_float(Value) ->
    ScaledValue = round(Value * math:pow(10, Scale)),
    case validate_precision(ScaledValue, Scale, 38) of
        ok -> clickhouse_erl_types_extended_integer:encode_int128(ScaledValue);
        {error, Reason} -> {error, Reason}
    end;
encode_decimal128(Value, _Scale) ->
    {error, {invalid_decimal_value, Value}}.

%% @doc Decode a Decimal128 value.
%% Parses 16-byte little-endian binary and returns {decimal, Value, Scale} tuple.
-spec decode_decimal128(binary(), non_neg_integer()) ->
    {ok, decimal_value(), binary()} | {error, term()}.
decode_decimal128(Binary, Scale) when byte_size(Binary) >= 16 ->
    case clickhouse_erl_types_extended_integer:decode_int128(Binary) of
        {ok, Value, Rest} ->
            {ok, {decimal, Value, Scale}, Rest};
        {error, Reason} ->
            {error, Reason}
    end;
decode_decimal128(Binary, _Scale) ->
    {error,
        {truncated_data, #{
            expected_bytes => 16, actual_bytes => byte_size(Binary), type => decimal128
        }}}.

%% @doc Encode a Decimal256 value.
%% Accepts {decimal, Value, Scale} tuple or plain integer/float.
%% Returns 32-byte little-endian binary using Int256 encoding.
%% Validates precision constraints (max 76 digits).
-spec encode_decimal256(decimal_value() | integer() | float(), non_neg_integer()) ->
    {ok, binary()} | {error, term()}.
encode_decimal256({decimal, Value, _Scale}, TypeScale) when is_integer(Value) ->
    case validate_precision(Value, TypeScale, 76) of
        ok -> clickhouse_erl_types_extended_integer:encode_int256(Value);
        {error, Reason} -> {error, Reason}
    end;
encode_decimal256(Value, TypeScale) when is_integer(Value) ->
    ScaledValue = Value * round(math:pow(10, TypeScale)),
    case validate_precision(ScaledValue, TypeScale, 76) of
        ok -> clickhouse_erl_types_extended_integer:encode_int256(ScaledValue);
        {error, Reason} -> {error, Reason}
    end;
encode_decimal256(Value, Scale) when is_float(Value) ->
    ScaledValue = round(Value * math:pow(10, Scale)),
    case validate_precision(ScaledValue, Scale, 76) of
        ok -> clickhouse_erl_types_extended_integer:encode_int256(ScaledValue);
        {error, Reason} -> {error, Reason}
    end;
encode_decimal256(Value, _Scale) ->
    {error, {invalid_decimal_value, Value}}.

%% @doc Decode a Decimal256 value.
%% Parses 32-byte little-endian binary and returns {decimal, Value, Scale} tuple.
-spec decode_decimal256(binary(), non_neg_integer()) ->
    {ok, decimal_value(), binary()} | {error, term()}.
decode_decimal256(Binary, Scale) when byte_size(Binary) >= 32 ->
    case clickhouse_erl_types_extended_integer:decode_int256(Binary) of
        {ok, Value, Rest} ->
            {ok, {decimal, Value, Scale}, Rest};
        {error, Reason} ->
            {error, Reason}
    end;
decode_decimal256(Binary, _Scale) ->
    {error,
        {truncated_data, #{
            expected_bytes => 32, actual_bytes => byte_size(Binary), type => decimal256
        }}}.

%% @doc Parse a decimal type string to extract precision and scale.
%% Examples:
%%   "Decimal32(9, 2)" -> {ok, {decimal32, 9, 2}}
%%   "Decimal32(2)" -> {ok, {decimal32, 9, 2}}
%%   "Decimal(9, 2)" -> {ok, {decimal32, 9, 2}}  (ClickHouse canonical format)
%%   "Decimal64(18, 4)" -> {ok, {decimal64, 18, 4}}
%%   "Decimal128(38, 10)" -> {ok, {decimal128, 38, 10}}
%%   "Decimal256(76, 20)" -> {ok, {decimal256, 76, 20}}
-spec parse_decimal_type(binary() | string()) ->
    {ok, decimal_type()} | {error, term()}.
parse_decimal_type(TypeStr) when is_list(TypeStr) ->
    parse_decimal_type(list_to_binary(TypeStr));
parse_decimal_type(<<"Decimal32(", Rest/binary>>) ->
    parse_decimal_params(Rest, decimal32, 9);
parse_decimal_type(<<"Decimal64(", Rest/binary>>) ->
    parse_decimal_params(Rest, decimal64, 18);
parse_decimal_type(<<"Decimal128(", Rest/binary>>) ->
    parse_decimal_params(Rest, decimal128, 38);
parse_decimal_type(<<"Decimal256(", Rest/binary>>) ->
    parse_decimal_params(Rest, decimal256, 76);
%% Generic Decimal(P, S) format - ClickHouse canonical representation
parse_decimal_type(<<"Decimal(", Rest/binary>>) ->
    parse_generic_decimal_params(Rest);
parse_decimal_type(TypeStr) ->
    {error, {invalid_decimal_type, TypeStr}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Validate that a decimal value fits within the precision constraint.
%% Precision is the total number of significant digits.
-spec validate_precision(integer(), non_neg_integer(), pos_integer()) ->
    ok | {error, term()}.
validate_precision(Value, _Scale, MaxPrecision) ->
    %% Count the number of digits in the absolute value
    AbsValue = abs(Value),
    Digits = count_digits(AbsValue),
    case Digits =< MaxPrecision of
        true ->
            ok;
        false ->
            {error,
                {precision_exceeded, #{
                    value => Value, digits => Digits, max_precision => MaxPrecision
                }}}
    end.

%% @doc Count the number of digits in a non-negative integer.
-spec count_digits(non_neg_integer()) -> pos_integer().
count_digits(0) ->
    1;
count_digits(N) when N > 0 ->
    trunc(math:log10(N)) + 1.

%% @doc Encode a 32-bit signed integer in little-endian format.
-spec encode_int32(integer()) -> {ok, binary()} | {error, term()}.
encode_int32(Value) when Value >= -2147483648, Value =< 2147483647 ->
    {ok, <<Value:32/little-signed>>};
encode_int32(Value) ->
    {error,
        {value_out_of_range, #{
            value => Value, min => -2147483648, max => 2147483647, type => int32
        }}}.

%% @doc Encode a 64-bit signed integer in little-endian format.
-spec encode_int64(integer()) -> {ok, binary()} | {error, term()}.
encode_int64(Value) when Value >= -9223372036854775808, Value =< 9223372036854775807 ->
    {ok, <<Value:64/little-signed>>};
encode_int64(Value) ->
    {error,
        {value_out_of_range, #{
            value => Value, min => -9223372036854775808, max => 9223372036854775807, type => int64
        }}}.

%% @doc Parse decimal type parameters (precision and scale).
%% ClickHouse Decimal types can be specified as:
%%   - Decimal32(S) - scale only, precision defaults to max for type
%%   - Decimal32(P, S) - explicit precision and scale
-spec parse_decimal_params(binary(), atom(), pos_integer()) ->
    {ok, decimal_type()} | {error, term()}.
parse_decimal_params(Rest, TypeAtom, MaxPrecision) ->
    %% Remove closing parenthesis first
    case binary:split(Rest, <<")">>) of
        [ParamsStr, _] ->
            %% Split by comma to check if we have precision and scale or just scale
            case binary:split(ParamsStr, <<",">>) of
                [ScaleBin] ->
                    %% Only scale provided, use max precision
                    try
                        Scale = binary_to_integer(string:trim(ScaleBin)),
                        {ok, {TypeAtom, MaxPrecision, Scale}}
                    catch
                        _:_ ->
                            {error, {invalid_decimal_params, Rest}}
                    end;
                [PrecisionBin, ScaleBin] ->
                    %% Both precision and scale provided
                    try
                        Precision = binary_to_integer(string:trim(PrecisionBin)),
                        Scale = binary_to_integer(string:trim(ScaleBin)),
                        case Precision >= 1 andalso Precision =< MaxPrecision of
                            true ->
                                {ok, {TypeAtom, Precision, Scale}};
                            false ->
                                {error,
                                    {invalid_precision, #{
                                        precision => Precision,
                                        max => MaxPrecision,
                                        type => TypeAtom
                                    }}}
                        end
                    catch
                        _:_ ->
                            {error, {invalid_decimal_params, Rest}}
                    end;
                _ ->
                    {error, {invalid_decimal_format, Rest}}
            end;
        _ ->
            {error, {invalid_decimal_format, Rest}}
    end.

%% @doc Parse generic Decimal(P, S) format and determine the appropriate type.
%% ClickHouse uses this canonical format in responses.
%% Type is determined by precision:
%%   - P <= 9: Decimal32
%%   - P <= 18: Decimal64
%%   - P <= 38: Decimal128
%%   - P <= 76: Decimal256
-spec parse_generic_decimal_params(binary()) ->
    {ok, decimal_type()} | {error, term()}.
parse_generic_decimal_params(Rest) ->
    case binary:split(Rest, <<")">>) of
        [ParamsStr, _] ->
            case binary:split(ParamsStr, <<",">>) of
                [PrecisionBin, ScaleBin] ->
                    try
                        Precision = binary_to_integer(string:trim(PrecisionBin)),
                        Scale = binary_to_integer(string:trim(ScaleBin)),
                        %% Determine type based on precision
                        TypeAtom =
                            case Precision of
                                P when P =< 9 -> decimal32;
                                P when P =< 18 -> decimal64;
                                P when P =< 38 -> decimal128;
                                P when P =< 76 -> decimal256;
                                _ -> invalid
                            end,
                        case TypeAtom of
                            invalid ->
                                {error,
                                    {precision_too_large, #{precision => Precision, max => 76}}};
                            _ ->
                                {ok, {TypeAtom, Precision, Scale}}
                        end
                    catch
                        _:_ ->
                            {error, {invalid_decimal_params, Rest}}
                    end;
                _ ->
                    {error, {invalid_decimal_format, Rest}}
            end;
        _ ->
            {error, {invalid_decimal_format, Rest}}
    end.

%%%===================================================================
%%% Column Encoding/Decoding
%%%===================================================================

%% @doc Decode a column of Decimal32 values.
-spec decode_decimal32_column(binary(), non_neg_integer(), non_neg_integer()) ->
    {ok, [decimal_value()], binary()} | {error, term()}.
decode_decimal32_column(Binary, Scale, NumRows) ->
    decode_decimal_column_loop(Binary, Scale, NumRows, fun decode_decimal32/2, []).

%% @doc Decode a column of Decimal64 values.
-spec decode_decimal64_column(binary(), non_neg_integer(), non_neg_integer()) ->
    {ok, [decimal_value()], binary()} | {error, term()}.
decode_decimal64_column(Binary, Scale, NumRows) ->
    decode_decimal_column_loop(Binary, Scale, NumRows, fun decode_decimal64/2, []).

%% @doc Decode a column of Decimal128 values.
-spec decode_decimal128_column(binary(), non_neg_integer(), non_neg_integer()) ->
    {ok, [decimal_value()], binary()} | {error, term()}.
decode_decimal128_column(Binary, Scale, NumRows) ->
    decode_decimal_column_loop(Binary, Scale, NumRows, fun decode_decimal128/2, []).

%% @doc Decode a column of Decimal256 values.
-spec decode_decimal256_column(binary(), non_neg_integer(), non_neg_integer()) ->
    {ok, [decimal_value()], binary()} | {error, term()}.
decode_decimal256_column(Binary, Scale, NumRows) ->
    decode_decimal_column_loop(Binary, Scale, NumRows, fun decode_decimal256/2, []).

%%%===================================================================
%%% Internal Helper Functions
%%%===================================================================

%% @doc Helper to decode a column of decimal values.
-spec decode_decimal_column_loop(
    binary(),
    non_neg_integer(),
    non_neg_integer(),
    fun((binary(), non_neg_integer()) -> {ok, decimal_value(), binary()} | {error, term()}),
    [decimal_value()]
) ->
    {ok, [decimal_value()], binary()} | {error, term()}.
decode_decimal_column_loop(Binary, _Scale, 0, _DecodeFun, Acc) ->
    {ok, lists:reverse(Acc), Binary};
decode_decimal_column_loop(Binary, Scale, N, DecodeFun, Acc) ->
    case DecodeFun(Binary, Scale) of
        {ok, Value, Rest} ->
            decode_decimal_column_loop(Rest, Scale, N - 1, DecodeFun, [Value | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.
