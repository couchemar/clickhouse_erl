%% @doc ClickHouse temporal types encoding and decoding functions.
%%
%% This module provides functions for encoding and decoding ClickHouse temporal types
%% including Date, Date32, DateTime, and DateTime64.
-module(clickhouse_erl_types_temporal).

%% Date types
-export([encode_date/1, decode_date/1]).
-export([encode_date32/1, decode_date32/1]).

%% DateTime types
-export([encode_datetime/1, decode_datetime/1]).
-export([encode_datetime64/2, decode_datetime64/2]).

%%%===================================================================
%%% API - Date Types
%%%===================================================================

%% @doc Encode a date (Date) as UInt16 days since 1970-01-01.
%%
%% Input: {Year, Month, Day} tuple
%% Returns a 2-byte binary or error tuple.
-spec encode_date(calendar:date()) -> binary() | {error, term()}.
encode_date({Y, M, D}) ->
    case calendar:valid_date(Y, M, D) of
        true ->
            Days = calendar:date_to_gregorian_days(Y, M, D) - 719528,
            clickhouse_erl_types_integer:encode_uint16(Days);
        false ->
            {error, {invalid_date, #{value => {Y, M, D}, reason => invalid_date_components}}}
    end;
encode_date(Val) ->
    {error, {invalid_value, #{value => Val, expected_type => '{Year, Month, Day}', type => date}}}.

%% @doc Decode a date (Date) from UInt16 days since 1970-01-01.
%%
%% Returns {ok, {Year, Month, Day}, Rest} on success or {error, Reason} on failure.
-spec decode_date(binary()) -> {ok, calendar:date(), binary()} | {error, term()}.
decode_date(Binary) ->
    case clickhouse_erl_types_integer:decode_uint16(Binary) of
        {ok, Days, Rest} ->
            Date = calendar:gregorian_days_to_date(Days + 719528),
            {ok, Date, Rest};
        {error, {truncated_data, _}} ->
            {error,
                {truncated_data, #{
                    expected_bytes => 2, actual_bytes => byte_size(Binary), type => date
                }}}
    end.

%% @doc Encode a date (Date32) as Int32 days since 1970-01-01.
%%
%% Input: {Year, Month, Day} tuple
%% Returns a 4-byte binary or error tuple.
-spec encode_date32(calendar:date()) -> binary() | {error, term()}.
encode_date32({Y, M, D}) ->
    case calendar:valid_date(Y, M, D) of
        true ->
            Days = calendar:date_to_gregorian_days(Y, M, D) - 719528,
            clickhouse_erl_types_integer:encode_int32(Days);
        false ->
            {error, {invalid_date, #{value => {Y, M, D}, reason => invalid_date_components}}}
    end;
encode_date32(Val) ->
    {error,
        {invalid_value, #{value => Val, expected_type => '{Year, Month, Day}', type => date32}}}.

%% @doc Decode a date (Date32) from Int32 days since 1970-01-01.
%%
%% Returns {ok, {Year, Month, Day}, Rest} on success or {error, Reason} on failure.
-spec decode_date32(binary()) -> {ok, calendar:date(), binary()} | {error, term()}.
decode_date32(Binary) ->
    case clickhouse_erl_types_integer:decode_int32(Binary) of
        {ok, Days, Rest} ->
            Date = calendar:gregorian_days_to_date(Days + 719528),
            {ok, Date, Rest};
        {error, {truncated_data, _}} ->
            {error,
                {truncated_data, #{
                    expected_bytes => 4, actual_bytes => byte_size(Binary), type => date32
                }}}
    end.

%%%===================================================================
%%% API - DateTime Types
%%%===================================================================

%% @doc Encode a datetime (DateTime) as UInt32 seconds since 1970-01-01 00:00:00 UTC.
%%
%% Input: {{Year, Month, Day}, {Hour, Minute, Second}} tuple
%% Returns a 4-byte binary or error tuple.
-spec encode_datetime(calendar:datetime()) -> binary() | {error, term()}.
encode_datetime({{Y, M, D}, {H, Min, S}}) ->
    case calendar:valid_date(Y, M, D) of
        true when H >= 0, H < 24, Min >= 0, Min < 60, S >= 0, S < 60 ->
            Gregorian = calendar:datetime_to_gregorian_seconds({{Y, M, D}, {H, Min, S}}),
            Seconds = Gregorian - 62167219200,
            clickhouse_erl_types_integer:encode_uint32(Seconds);
        _ ->
            {error,
                {invalid_datetime, #{
                    value => {{Y, M, D}, {H, Min, S}}, reason => invalid_datetime_components
                }}}
    end;
encode_datetime(Val) ->
    {error,
        {invalid_value, #{
            value => Val,
            expected_type => '{{Year, Month, Day}, {Hour, Minute, Second}}',
            type => datetime
        }}}.

%% @doc Decode a datetime (DateTime) from UInt32 seconds since 1970-01-01 00:00:00 UTC.
%%
%% Returns {ok, {{Year, Month, Day}, {Hour, Minute, Second}}, Rest} on success
%% or {error, Reason} on failure.
-spec decode_datetime(binary()) -> {ok, calendar:datetime(), binary()} | {error, term()}.
decode_datetime(Binary) ->
    case clickhouse_erl_types_integer:decode_uint32(Binary) of
        {ok, Seconds, Rest} ->
            DateTime = calendar:gregorian_seconds_to_datetime(Seconds + 62167219200),
            {ok, DateTime, Rest};
        {error, {truncated_data, _}} ->
            {error,
                {truncated_data, #{
                    expected_bytes => 4, actual_bytes => byte_size(Binary), type => datetime
                }}}
    end.

%% @doc Encode a datetime64 (DateTime64) as Int64 ticks.
%%
%% Input can be either:
%% - An integer representing ticks (milliseconds, microseconds, etc. based on precision)
%% - A datetime tuple {{Year, Month, Day}, {Hour, Minute, Second}} which will be converted
%%
%% Precision determines the scale:
%% - 0: seconds
%% - 3: milliseconds
%% - 6: microseconds
%% - 9: nanoseconds
%%
%% Returns an 8-byte binary or error tuple.
-spec encode_datetime64(calendar:datetime() | integer(), non_neg_integer()) ->
    binary() | {error, term()}.
encode_datetime64({{Y, M, D}, {H, Min, S}} = DateTime, Precision) when is_integer(Precision) ->
    case calendar:valid_date(Y, M, D) of
        true when H >= 0, H < 24, Min >= 0, Min < 60, S >= 0, S < 60 ->
            Gregorian = calendar:datetime_to_gregorian_seconds(DateTime),
            Seconds = Gregorian - 62167219200,
            % Convert to ticks based on precision
            Ticks =
                case Precision of
                    0 -> Seconds;
                    % milliseconds
                    3 -> Seconds * 1000;
                    % microseconds
                    6 -> Seconds * 1000000;
                    % nanoseconds
                    9 -> Seconds * 1000000000
                end,
            clickhouse_erl_types_integer:encode_int64(Ticks);
        _ ->
            {error,
                {invalid_datetime, #{
                    value => DateTime, reason => invalid_datetime_components
                }}}
    end;
encode_datetime64(Value, _Precision) when is_integer(Value) ->
    clickhouse_erl_types_integer:encode_int64(Value);
encode_datetime64(Val, _Precision) ->
    {error,
        {invalid_value, #{
            value => Val,
            expected_type => 'integer or {{Year, Month, Day}, {Hour, Minute, Second}}',
            type => datetime64
        }}}.

%% @doc Decode a datetime64 (DateTime64) from Int64 ticks.
%%
%% Returns {ok, Integer, Rest} on success or {error, Reason} on failure.
-spec decode_datetime64(binary(), non_neg_integer()) -> {ok, integer(), binary()} | {error, term()}.
decode_datetime64(Binary, _Precision) ->
    case clickhouse_erl_types_integer:decode_int64(Binary) of
        {ok, Val, Rest} ->
            {ok, Val, Rest};
        {error, {truncated_data, _}} ->
            {error,
                {truncated_data, #{
                    expected_bytes => 8, actual_bytes => byte_size(Binary), type => datetime64
                }}}
    end.
