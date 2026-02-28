%% @doc Tests for ClickHouse temporal type encoding/decoding functions.
%%
%% This module contains tests specifically for the clickhouse_erl_types_temporal module,
%% covering Date, Date32, DateTime, and DateTime64 types.
-module(clickhouse_erl_types_temporal_tests).

-include_lib("eunit/include/eunit.hrl").

%% ============================================================================
%% Date Tests
%% ============================================================================

%% Test Date encoding
encode_date_test() ->
    %% 1970-01-01 -> 0 days
    ?assertEqual(<<0, 0>>, clickhouse_erl_types_temporal:encode_date({1970, 1, 1})),
    %% 1970-01-02 -> 1 day
    ?assertEqual(<<1, 0>>, clickhouse_erl_types_temporal:encode_date({1970, 1, 2})),
    %% 2020-01-01 -> 18262 days -> 0x4756 -> <<86, 71>>
    ?assertEqual(<<86, 71>>, clickhouse_erl_types_temporal:encode_date({2020, 1, 1})),
    %% 2149-06-06 -> 65535 days -> Max UInt16
    ?assertEqual(<<255, 255>>, clickhouse_erl_types_temporal:encode_date({2149, 6, 6})).

%% Test Date decoding
decode_date_test() ->
    ?assertEqual({ok, {1970, 1, 1}, <<>>}, clickhouse_erl_types_temporal:decode_date(<<0, 0>>)),
    ?assertEqual({ok, {1970, 1, 2}, <<>>}, clickhouse_erl_types_temporal:decode_date(<<1, 0>>)),
    ?assertEqual({ok, {2020, 1, 1}, <<>>}, clickhouse_erl_types_temporal:decode_date(<<86, 71>>)),
    ?assertEqual(
        {ok, {2149, 6, 6}, <<>>}, clickhouse_erl_types_temporal:decode_date(<<255, 255>>)
    ).

%% Test Date validation
encode_date_validation_test() ->
    %% Too early (before 1970)
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_temporal:encode_date({1969, 12, 31})
    ),
    %% Too late (overflow UInt16)
    ?assertMatch(
        {error, {value_out_of_range, _}}, clickhouse_erl_types_temporal:encode_date({2150, 1, 1})
    ),
    %% Invalid Date
    ?assertMatch(
        {error, {invalid_date, _}}, clickhouse_erl_types_temporal:encode_date({2023, 2, 30})
    ),
    %% Bad structure
    ?assertMatch(
        {error, {invalid_value, _}}, clickhouse_erl_types_temporal:encode_date(not_a_date)
    ).

%% ============================================================================
%% Date32 Tests
%% ============================================================================

%% Test Date32 encoding
encode_date32_test() ->
    %% 1970-01-01 -> 0 days
    ?assertEqual(<<0, 0, 0, 0>>, clickhouse_erl_types_temporal:encode_date32({1970, 1, 1})),
    %% 1970-01-02 -> 1 day
    ?assertEqual(<<1, 0, 0, 0>>, clickhouse_erl_types_temporal:encode_date32({1970, 1, 2})),
    %% 2020-01-01 -> 18262 days
    ?assertEqual(<<86, 71, 0, 0>>, clickhouse_erl_types_temporal:encode_date32({2020, 1, 1})).

%% Test Date32 decoding
decode_date32_test() ->
    ?assertEqual(
        {ok, {1970, 1, 1}, <<>>}, clickhouse_erl_types_temporal:decode_date32(<<0, 0, 0, 0>>)
    ),
    ?assertEqual(
        {ok, {1970, 1, 2}, <<>>}, clickhouse_erl_types_temporal:decode_date32(<<1, 0, 0, 0>>)
    ),
    ?assertEqual(
        {ok, {2020, 1, 1}, <<>>}, clickhouse_erl_types_temporal:decode_date32(<<86, 71, 0, 0>>)
    ).

%% Test Date32 validation
encode_date32_validation_test() ->
    %% Invalid Date
    ?assertMatch(
        {error, {invalid_date, _}}, clickhouse_erl_types_temporal:encode_date32({2023, 2, 30})
    ),
    %% Bad structure
    ?assertMatch(
        {error, {invalid_value, _}}, clickhouse_erl_types_temporal:encode_date32(not_a_date)
    ).

%% ============================================================================
%% DateTime Tests
%% ============================================================================

%% Test DateTime encoding
encode_datetime_test() ->
    %% 1970-01-01 00:00:00
    ?assertEqual(
        <<0, 0, 0, 0>>, clickhouse_erl_types_temporal:encode_datetime({{1970, 1, 1}, {0, 0, 0}})
    ),
    %% 2020-01-01 12:00:00 -> 1577880000 -> 0x5E0C89C0 -> <<192, 137, 12, 94>>
    ?assertEqual(
        <<192, 137, 12, 94>>,
        clickhouse_erl_types_temporal:encode_datetime({{2020, 1, 1}, {12, 0, 0}})
    ).

%% Test DateTime decoding
decode_datetime_test() ->
    ?assertEqual(
        {ok, {{1970, 1, 1}, {0, 0, 0}}, <<>>},
        clickhouse_erl_types_temporal:decode_datetime(<<0, 0, 0, 0>>)
    ),
    ?assertEqual(
        {ok, {{2020, 1, 1}, {12, 0, 0}}, <<>>},
        clickhouse_erl_types_temporal:decode_datetime(<<192, 137, 12, 94>>)
    ).

%% Test DateTime validation
encode_datetime_validation_test() ->
    %% Too early
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_temporal:encode_datetime({{1969, 12, 31}, {23, 59, 59}})
    ),
    %% Too late
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_temporal:encode_datetime({{2107, 1, 1}, {0, 0, 0}})
    ),
    %% Invalid Time
    ?assertMatch(
        {error, {invalid_datetime, _}},
        clickhouse_erl_types_temporal:encode_datetime({{2020, 1, 1}, {25, 0, 0}})
    ),
    %% Bad structure
    ?assertMatch(
        {error, {invalid_value, _}},
        clickhouse_erl_types_temporal:encode_datetime(not_a_datetime)
    ).

%% ============================================================================
%% DateTime64 Tests
%% ============================================================================

%% Test DateTime64 encoding
encode_datetime64_test() ->
    %% Just wraps Int64
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 0, 0>>, clickhouse_erl_types_temporal:encode_datetime64(0, 3)
    ),
    ?assertEqual(
        <<1, 0, 0, 0, 0, 0, 0, 0>>, clickhouse_erl_types_temporal:encode_datetime64(1, 3)
    ).

%% Test DateTime64 decoding
decode_datetime64_test() ->
    ?assertEqual(
        {ok, 0, <<>>},
        clickhouse_erl_types_temporal:decode_datetime64(<<0, 0, 0, 0, 0, 0, 0, 0>>, 3)
    ),
    ?assertEqual(
        {ok, 1, <<>>},
        clickhouse_erl_types_temporal:decode_datetime64(<<1, 0, 0, 0, 0, 0, 0, 0>>, 3)
    ).
