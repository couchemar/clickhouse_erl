%% @doc Time and Time64 type encoding/decoding for ClickHouse.
%%
%% This module handles Time (seconds since midnight) and Time64 (nanoseconds since midnight)
%% types for representing time-of-day values without date components.
%%
%% Type Representations:
%% - Time: {Hour, Minute, Second} tuple or integer (seconds since midnight)
%% - Time64: {Hour, Minute, Second, Nanosecond} tuple or integer (nanoseconds since midnight)
%%
%% Encoding Format:
%% - Time: Int32 encoding (4 bytes, little-endian)
%% - Time64: Int64 encoding (8 bytes, little-endian)
%%
%% Range Limits:
%% - Time: 0-86399 seconds (00:00:00 to 23:59:59)
%% - Time64: 0-86399999999999 nanoseconds
%%
%% Usage Examples:
%%
%% ```
%% % Encode Time from tuple
%% {ok, Binary} = encode_time({14, 30, 45}).
%% % Binary = <<173, 204, 0, 0>> (52245 seconds in little-endian)
%%
%% % Encode Time from integer (seconds since midnight)
%% {ok, Binary2} = encode_time(52245).
%% % Binary2 = <<173, 204, 0, 0>>
%%
%% % Decode Time
%% {ok, {14, 30, 45}, Rest} = decode_time(Binary).
%%
%% % Encode Time64 from tuple with nanoseconds
%% {ok, Binary3} = encode_time64({14, 30, 45, 123456789}).
%% % Binary3 = <<21, 205, 91, 7, 225, 11, 0, 0>>
%%
%% % Encode Time64 from integer (nanoseconds since midnight)
%% {ok, Binary4} = encode_time64(52245123456789).
%%
%% % Decode Time64
%% {ok, {14, 30, 45, 123456789}, Rest} = decode_time64(Binary3).
%%
%% % Convert between formats
%% 52245 = time_to_seconds({14, 30, 45}).
%% {14, 30, 45} = seconds_to_time(52245).
%% 52245123456789 = time64_to_nanoseconds({14, 30, 45, 123456789}).
%% {14, 30, 45, 123456789} = nanoseconds_to_time64(52245123456789).
%%
%% % Out-of-range error
%% {error, {invalid_time_range, _}} = encode_time({25, 0, 0}).
%% {error, {invalid_time_range, _}} = encode_time(86400).
%% '''
%%
%% Error Cases:
%% - {invalid_time_range, Details} - Time value outside valid range
%% - {invalid_time_value, Value} - Invalid time format or type
%% - {truncated_data, Details} - Binary too short for decoding
-module(clickhouse_erl_types_time).

%% API exports
-export([
    encode_time/1,
    decode_time/1,
    encode_time64/1,
    decode_time64/1,
    seconds_to_time/1,
    nanoseconds_to_time64/1,
    decode_time_column/2,
    decode_time64_column/2
]).

-ignore_xref([
    seconds_to_time/1,
    nanoseconds_to_time64/1
]).

%% Includes
-include_lib("kernel/include/logger.hrl").

%% Type definitions
-export_type([time_value/0, time64_value/0]).

-type time_value() :: {Hour :: 0..23, Minute :: 0..59, Second :: 0..59} | non_neg_integer().
-type time64_value() ::
    {Hour :: 0..23, Minute :: 0..59, Second :: 0..59, Nanosecond :: 0..999999999}
    | non_neg_integer().

%% Constants

% 23:59:59 in seconds
-define(MAX_TIME_SECONDS, 86399).
% 23:59:59.999999999 in nanoseconds
-define(MAX_TIME64_NANOSECONDS, 86399999999999).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Encode a Time value (seconds since midnight).
%% Accepts either a tuple {Hour, Minute, Second} or an integer (seconds since midnight).
%% Returns 4 bytes (Int32, little-endian).
-spec encode_time(time_value()) -> {ok, binary()} | {error, term()}.
encode_time({Hour, Minute, Second}) when is_integer(Hour), is_integer(Minute), is_integer(Second) ->
    case validate_time_tuple(Hour, Minute, Second) of
        ok ->
            Seconds = Hour * 3600 + Minute * 60 + Second,
            {ok, <<Seconds:32/little-signed>>};
        Error ->
            Error
    end;
encode_time(Seconds) when is_integer(Seconds) ->
    case validate_time_seconds(Seconds) of
        ok ->
            {ok, <<Seconds:32/little-signed>>};
        Error ->
            Error
    end;
encode_time(Value) ->
    {error, {invalid_time_value, #{value => Value, expected => "tuple {H, M, S} or integer"}}}.

%% @doc Decode a Time value from binary.
%% Parses 4 bytes (Int32, little-endian) and returns a tuple {Hour, Minute, Second}.
-spec decode_time(binary()) -> {ok, time_value(), binary()} | {error, term()}.
decode_time(<<Seconds:32/little-signed, Rest/binary>>) ->
    case validate_time_seconds(Seconds) of
        ok ->
            Time = seconds_to_time(Seconds),
            {ok, Time, Rest};
        Error ->
            Error
    end;
decode_time(Binary) when byte_size(Binary) < 4 ->
    {error,
        {truncated_data, #{
            expected_bytes => 4,
            actual_bytes => byte_size(Binary),
            type => time
        }}};
decode_time(_) ->
    {error, {invalid_time_binary, #{type => time}}}.

%% @doc Encode a Time64 value (nanoseconds since midnight).
%% Accepts either a tuple {Hour, Minute, Second, Nanosecond} or an integer
%% (nanoseconds since midnight). Returns 8 bytes (Int64, little-endian).
-spec encode_time64(time64_value()) -> {ok, binary()} | {error, term()}.
encode_time64({Hour, Minute, Second, Nanosecond}) when
    is_integer(Hour),
    is_integer(Minute),
    is_integer(Second),
    is_integer(Nanosecond)
->
    case validate_time64_tuple(Hour, Minute, Second, Nanosecond) of
        ok ->
            Nanoseconds = time64_to_nanoseconds({Hour, Minute, Second, Nanosecond}),
            {ok, <<Nanoseconds:64/little-signed>>};
        Error ->
            Error
    end;
encode_time64(Nanoseconds) when is_integer(Nanoseconds) ->
    case validate_time64_nanoseconds(Nanoseconds) of
        ok ->
            {ok, <<Nanoseconds:64/little-signed>>};
        Error ->
            Error
    end;
encode_time64(Value) ->
    {error, {invalid_time64_value, #{value => Value, expected => "tuple {H, M, S, N} or integer"}}}.

%% @doc Decode a Time64 value from binary.
%% Parses 8 bytes (Int64, little-endian) and returns a tuple {Hour, Minute, Second, Nanosecond}.
-spec decode_time64(binary()) -> {ok, time64_value(), binary()} | {error, term()}.
decode_time64(<<Nanoseconds:64/little-signed, Rest/binary>>) ->
    case validate_time64_nanoseconds(Nanoseconds) of
        ok ->
            Time64 = nanoseconds_to_time64(Nanoseconds),
            {ok, Time64, Rest};
        Error ->
            Error
    end;
decode_time64(Binary) when byte_size(Binary) < 8 ->
    {error,
        {truncated_data, #{
            expected_bytes => 8,
            actual_bytes => byte_size(Binary),
            type => time64
        }}};
decode_time64(_) ->
    {error, {invalid_time64_binary, #{type => time64}}}.

%% @doc Convert seconds since midnight to time tuple.
-spec seconds_to_time(non_neg_integer()) -> {0..23, 0..59, 0..59}.
seconds_to_time(Seconds) ->
    Hour = Seconds div 3600,
    Remainder = Seconds rem 3600,
    Minute = Remainder div 60,
    Second = Remainder rem 60,
    {Hour, Minute, Second}.

%% @doc Convert time64 tuple to nanoseconds since midnight.
-spec time64_to_nanoseconds(time64_value()) -> non_neg_integer().
time64_to_nanoseconds({Hour, Minute, Second, Nanosecond}) ->
    (Hour * 3600 + Minute * 60 + Second) * 1000000000 + Nanosecond;
time64_to_nanoseconds(Nanoseconds) when is_integer(Nanoseconds) ->
    Nanoseconds.

%% @doc Convert nanoseconds since midnight to time64 tuple.
-spec nanoseconds_to_time64(non_neg_integer()) -> {0..23, 0..59, 0..59, 0..999999999}.
nanoseconds_to_time64(Nanoseconds) ->
    TotalSeconds = Nanoseconds div 1000000000,
    Nanosecond = Nanoseconds rem 1000000000,
    Hour = TotalSeconds div 3600,
    Remainder = TotalSeconds rem 3600,
    Minute = Remainder div 60,
    Second = Remainder rem 60,
    {Hour, Minute, Second, Nanosecond}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Validate time tuple components.
-spec validate_time_tuple(integer(), integer(), integer()) -> ok | {error, term()}.
validate_time_tuple(Hour, Minute, Second) ->
    case
        {
            Hour >= 0 andalso Hour =< 23,
            Minute >= 0 andalso Minute =< 59,
            Second >= 0 andalso Second =< 59
        }
    of
        {true, true, true} ->
            ok;
        {false, _, _} ->
            {error, {invalid_hour, #{value => Hour, min => 0, max => 23, type => time}}};
        {_, false, _} ->
            {error, {invalid_minute, #{value => Minute, min => 0, max => 59, type => time}}};
        {_, _, false} ->
            {error, {invalid_second, #{value => Second, min => 0, max => 59, type => time}}}
    end.

%% @doc Validate time seconds value.
-spec validate_time_seconds(integer()) -> ok | {error, term()}.
validate_time_seconds(Seconds) when Seconds >= 0 andalso Seconds =< ?MAX_TIME_SECONDS ->
    ok;
validate_time_seconds(Seconds) ->
    {error,
        {value_out_of_range, #{
            value => Seconds,
            min => 0,
            max => ?MAX_TIME_SECONDS,
            type => time
        }}}.

%% @doc Validate time64 tuple components.
-spec validate_time64_tuple(integer(), integer(), integer(), integer()) -> ok | {error, term()}.
validate_time64_tuple(Hour, Minute, Second, Nanosecond) ->
    case
        {
            Hour >= 0 andalso Hour =< 23,
            Minute >= 0 andalso Minute =< 59,
            Second >= 0 andalso Second =< 59,
            Nanosecond >= 0 andalso Nanosecond =< 999999999
        }
    of
        {true, true, true, true} ->
            ok;
        {false, _, _, _} ->
            {error, {invalid_hour, #{value => Hour, min => 0, max => 23, type => time64}}};
        {_, false, _, _} ->
            {error, {invalid_minute, #{value => Minute, min => 0, max => 59, type => time64}}};
        {_, _, false, _} ->
            {error, {invalid_second, #{value => Second, min => 0, max => 59, type => time64}}};
        {_, _, _, false} ->
            {error,
                {invalid_nanosecond, #{
                    value => Nanosecond, min => 0, max => 999999999, type => time64
                }}}
    end.

%% @doc Validate time64 nanoseconds value.
-spec validate_time64_nanoseconds(integer()) -> ok | {error, term()}.
validate_time64_nanoseconds(Nanoseconds) when
    Nanoseconds >= 0 andalso Nanoseconds =< ?MAX_TIME64_NANOSECONDS
->
    ok;
validate_time64_nanoseconds(Nanoseconds) ->
    {error,
        {value_out_of_range, #{
            value => Nanoseconds,
            min => 0,
            max => ?MAX_TIME64_NANOSECONDS,
            type => time64
        }}}.

%%%===================================================================
%%% Column Encoding/Decoding
%%%===================================================================

%% @doc Decode a column of Time values.
-spec decode_time_column(binary(), non_neg_integer()) ->
    {ok, [time_value()], binary()} | {error, term()}.
decode_time_column(Binary, NumRows) ->
    decode_column_loop(Binary, NumRows, fun decode_time/1, []).

%% @doc Decode a column of Time64 values.
-spec decode_time64_column(binary(), non_neg_integer()) ->
    {ok, [time64_value()], binary()} | {error, term()}.
decode_time64_column(Binary, NumRows) ->
    decode_column_loop(Binary, NumRows, fun decode_time64/1, []).

%%%===================================================================
%%% Internal Helper Functions
%%%===================================================================

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
