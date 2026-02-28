%% @doc Common Test suite for extended types integration testing
%%
%% Tests Int128/256, UInt128/256, Decimal, Enum, IPv4/IPv6, UUID, Time/Time64,
%% and special types (Nothing, Point, Interval, JSON) against real ClickHouse.
%%
%% Feature: extended-types-support
-module(clickhouse_erl_extended_types_SUITE).

-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).

%% Test cases - Extended Integers (Task 27.1)
-export([
    int128_roundtrip/1,
    uint128_roundtrip/1,
    int256_roundtrip/1,
    uint256_roundtrip/1,
    mixed_extended_integers/1
]).

%% Test cases - Decimals (Task 27.2)
-export([
    decimal32_roundtrip/1,
    decimal64_roundtrip/1,
    decimal128_roundtrip/1,
    decimal256_roundtrip/1,
    mixed_decimal_precisions/1
]).

%% Test cases - Enums (Task 27.3)
-export([
    enum8_roundtrip/1,
    enum16_roundtrip/1,
    enum_negative_values/1
]).

%% Test cases - Network Types (Task 27.4)
-export([
    ipv4_roundtrip/1,
    ipv6_roundtrip/1,
    mixed_network_types/1
]).

%% Test cases - UUID (Task 27.5)
-export([
    uuid_roundtrip/1,
    uuid_various_formats/1
]).

%% Test cases - Time Types (Task 27.6)
-export([
    time_roundtrip/1
]).

%% Test cases - Special Types (Task 27.7)
-export([
    point_roundtrip/1,
    interval_roundtrip/1,
    json_roundtrip/1
]).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

suite() ->
    [{timetrap, {seconds, 30}}].

all() ->
    [
        {group, extended_integers},
        {group, decimals},
        {group, enums},
        {group, network_types},
        {group, uuid},
        {group, time_types},
        {group, special_types}
    ].

groups() ->
    [
        {extended_integers, [sequence], [
            int128_roundtrip,
            uint128_roundtrip,
            int256_roundtrip,
            uint256_roundtrip,
            mixed_extended_integers
        ]},
        {decimals, [sequence], [
            decimal32_roundtrip,
            decimal64_roundtrip,
            decimal128_roundtrip,
            decimal256_roundtrip,
            mixed_decimal_precisions
        ]},
        {enums, [sequence], [
            enum8_roundtrip,
            enum16_roundtrip,
            enum_negative_values
        ]},
        {network_types, [sequence], [
            ipv4_roundtrip,
            ipv6_roundtrip,
            mixed_network_types
        ]},
        {uuid, [sequence], [
            uuid_roundtrip,
            uuid_various_formats
        ]},
        {time_types, [sequence], [
            time_roundtrip
        ]},
        {special_types, [sequence], [
            point_roundtrip,
            interval_roundtrip,
            json_roundtrip
        ]}
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

init_per_group(_Group, Config) ->
    ct:pal("Initializing group ~p, creating connection", [_Group]),
    case test_helpers:connect() of
        {ok, Conn} ->
            ct:pal("Connection created: ~p", [Conn]),
            [{connection, Conn} | Config];
        {error, Reason} ->
            ct:pal("Connection failed: ~p", [Reason]),
            ct:fail({connection_failed, Reason})
    end.

end_per_group(_Group, Config) ->
    Conn = ?config(connection, Config),
    test_helpers:disconnect(Conn),
    ok.

%%%===================================================================
%%% Test Cases: Extended Integers (Task 27.1)
%%% Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8
%%%===================================================================

int128_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    %% Create table with Int128 column
    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_int128">>),
    ok = execute(Conn, <<"CREATE TABLE test_int128 (id UInt32, value Int128) ENGINE = Memory">>),

    %% Insert data with various Int128 values
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4]},
        #{
            name => <<"value">>,
            type => <<"Int128">>,
            data => [
                0,
                42,
                -42,
                % Max Int128
                170141183460469231731687303715884105727
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_int128 VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    %% Query back
    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, value FROM test_int128 ORDER BY id">>),

    %% Verify results
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    [[1, 0], [2, 42], [3, -42], [4, 170141183460469231731687303715884105727]] = Rows,

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE test_int128">>).

uint128_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_uint128">>),
    ok = execute(Conn, <<"CREATE TABLE test_uint128 (id UInt32, value UInt128) ENGINE = Memory">>),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"value">>,
            type => <<"UInt128">>,
            data => [
                0,
                42,
                % Max UInt128
                340282366920938463463374607431768211455
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_uint128 VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, value FROM test_uint128 ORDER BY id">>),
    Data = maps:get(data, Result),
    [[1, 0], [2, 42], [3, 340282366920938463463374607431768211455]] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_uint128">>).

int256_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_int256">>),
    ok = execute(Conn, <<"CREATE TABLE test_int256 (id UInt32, value Int256) ENGINE = Memory">>),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"value">>,
            type => <<"Int256">>,
            data => [
                0,
                123456789012345678901234567890,
                -123456789012345678901234567890
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_int256 VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, value FROM test_int256 ORDER BY id">>),
    Data = maps:get(data, Result),
    [[1, 0], [2, 123456789012345678901234567890], [3, -123456789012345678901234567890]] = maps:get(
        rows, Data
    ),

    ok = execute(Conn, <<"DROP TABLE test_int256">>).

uint256_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_uint256">>),
    ok = execute(Conn, <<"CREATE TABLE test_uint256 (id UInt32, value UInt256) ENGINE = Memory">>),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"value">>,
            type => <<"UInt256">>,
            data => [
                0,
                123456789012345678901234567890123456789012345678901234567890
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_uint256 VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, value FROM test_uint256 ORDER BY id">>),
    Data = maps:get(data, Result),
    [[1, 0], [2, 123456789012345678901234567890123456789012345678901234567890]] = maps:get(
        rows, Data
    ),

    ok = execute(Conn, <<"DROP TABLE test_uint256">>).

mixed_extended_integers(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_mixed_extended">>),
    ok = execute(
        Conn,
        <<"CREATE TABLE test_mixed_extended (id UInt32, i128 Int128, u128 UInt128, i256 Int256, u256 UInt256) ENGINE = Memory">>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1]},
        #{name => <<"i128">>, type => <<"Int128">>, data => [-100]},
        #{name => <<"u128">>, type => <<"UInt128">>, data => [200]},
        #{name => <<"i256">>, type => <<"Int256">>, data => [-300]},
        #{name => <<"u256">>, type => <<"UInt256">>, data => [400]}
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_mixed_extended VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, i128, u128, i256, u256 FROM test_mixed_extended">>
    ),
    Data = maps:get(data, Result),
    [[1, -100, 200, -300, 400]] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_mixed_extended">>).

%%%===================================================================
%%% Test Cases: Decimals (Task 27.2)
%%% Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8
%%%===================================================================

decimal32_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_decimal32">>),
    ok = execute(
        Conn, <<"CREATE TABLE test_decimal32 (id UInt32, value Decimal32(4)) ENGINE = Memory">>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"value">>,
            type => <<"Decimal32(4)">>,
            data => [
                {decimal, 0, 4},
                {decimal, 123450, 4},
                {decimal, -999990, 4}
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_decimal32 VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_decimal32 ORDER BY id">>
    ),
    Data = maps:get(data, Result),
    [[1, {decimal, 0, 4}], [2, {decimal, 123450, 4}], [3, {decimal, -999990, 4}]] = maps:get(
        rows, Data
    ),

    ok = execute(Conn, <<"DROP TABLE test_decimal32">>).

decimal64_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_decimal64">>),
    ok = execute(
        Conn, <<"CREATE TABLE test_decimal64 (id UInt32, value Decimal64(9)) ENGINE = Memory">>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"value">>,
            type => <<"Decimal64(9)">>,
            data => [
                {decimal, 123456789000000000, 9},
                {decimal, -987654321000000000, 9}
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_decimal64 VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_decimal64 ORDER BY id">>
    ),
    Data = maps:get(data, Result),
    [[1, {decimal, 123456789000000000, 9}], [2, {decimal, -987654321000000000, 9}]] = maps:get(
        rows, Data
    ),

    ok = execute(Conn, <<"DROP TABLE test_decimal64">>).

decimal128_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_decimal128">>),
    ok = execute(
        Conn, <<"CREATE TABLE test_decimal128 (id UInt32, value Decimal128(18)) ENGINE = Memory">>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"value">>,
            type => <<"Decimal128(18)">>,
            data => [
                {decimal, 123456789012345678000000000000000000, 18},
                {decimal, -987654321098765432000000000000000000, 18}
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_decimal128 VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_decimal128 ORDER BY id">>
    ),
    Data = maps:get(data, Result),
    [
        [1, {decimal, 123456789012345678000000000000000000, 18}],
        [2, {decimal, -987654321098765432000000000000000000, 18}]
    ] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_decimal128">>).

decimal256_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_decimal256">>),
    ok = execute(
        Conn, <<"CREATE TABLE test_decimal256 (id UInt32, value Decimal256(38)) ENGINE = Memory">>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1]},
        #{
            name => <<"value">>,
            type => <<"Decimal256(38)">>,
            data => [
                {decimal, 12345678901234567890123456789012345678, 38}
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_decimal256 VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_decimal256 ORDER BY id">>
    ),
    Data = maps:get(data, Result),
    [[1, {decimal, 12345678901234567890123456789012345678, 38}]] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_decimal256">>).

mixed_decimal_precisions(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_mixed_decimals">>),
    ok = execute(
        Conn,
        <<"CREATE TABLE test_mixed_decimals (id UInt32, d32 Decimal32(2), d64 Decimal64(4), d128 Decimal128(6)) ENGINE = Memory">>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1]},
        #{name => <<"d32">>, type => <<"Decimal32(2)">>, data => [{decimal, 12345, 2}]},
        #{name => <<"d64">>, type => <<"Decimal64(4)">>, data => [{decimal, 123456789, 4}]},
        #{name => <<"d128">>, type => <<"Decimal128(6)">>, data => [{decimal, 123456789012, 6}]}
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_mixed_decimals VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, d32, d64, d128 FROM test_mixed_decimals">>
    ),
    Data = maps:get(data, Result),
    [[1, {decimal, 12345, 2}, {decimal, 123456789, 4}, {decimal, 123456789012, 6}]] = maps:get(
        rows, Data
    ),

    ok = execute(Conn, <<"DROP TABLE test_mixed_decimals">>).

%%%===================================================================
%%% Test Cases: Enums (Task 27.3)
%%% Requirements: 3.1, 3.2, 3.3, 3.4
%%%===================================================================

enum8_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_enum8">>),
    ok = execute(
        Conn,
        <<"CREATE TABLE test_enum8 (id UInt32, status Enum8('active' = 1, 'inactive' = 0, 'pending' = 2)) ENGINE = Memory">>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"status">>,
            type => <<"Enum8('active' = 1, 'inactive' = 0, 'pending' = 2)">>,
            data => [active, inactive, pending]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_enum8 VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, status FROM test_enum8 ORDER BY id">>),
    Data = maps:get(data, Result),
    [[1, active], [2, inactive], [3, pending]] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_enum8">>).

enum16_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_enum16">>),
    ok = execute(
        Conn,
        <<"CREATE TABLE test_enum16 (id UInt32, priority Enum16('low' = 1, 'medium' = 100, 'high' = 1000)) ENGINE = Memory">>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"priority">>,
            type => <<"Enum16('low' = 1, 'medium' = 100, 'high' = 1000)">>,
            data => [low, medium, high]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_enum16 VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, priority FROM test_enum16 ORDER BY id">>
    ),
    Data = maps:get(data, Result),
    [[1, low], [2, medium], [3, high]] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_enum16">>).

enum_negative_values(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_enum_negative">>),
    ok = execute(
        Conn,
        <<"CREATE TABLE test_enum_negative (id UInt32, value Enum8('negative' = -1, 'zero' = 0, 'positive' = 1)) ENGINE = Memory">>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"value">>,
            type => <<"Enum8('negative' = -1, 'zero' = 0, 'positive' = 1)">>,
            data => [negative, zero, positive]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_enum_negative VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_enum_negative ORDER BY id">>
    ),
    Data = maps:get(data, Result),
    [[1, negative], [2, zero], [3, positive]] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_enum_negative">>).

%%%===================================================================
%%% Test Cases: Network Types (Task 27.4)
%%% Requirements: 4.1, 4.2, 4.3, 4.4
%%%===================================================================

ipv4_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_ipv4">>),
    ok = execute(Conn, <<"CREATE TABLE test_ipv4 (id UInt32, addr IPv4) ENGINE = Memory">>),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"addr">>,
            type => <<"IPv4">>,
            data => [
                {192, 168, 1, 1},
                {10, 0, 0, 1},
                {127, 0, 0, 1}
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_ipv4 VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, addr FROM test_ipv4 ORDER BY id">>),
    Data = maps:get(data, Result),
    [[1, {192, 168, 1, 1}], [2, {10, 0, 0, 1}], [3, {127, 0, 0, 1}]] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_ipv4">>).

ipv6_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_ipv6">>),
    ok = execute(Conn, <<"CREATE TABLE test_ipv6 (id UInt32, addr IPv6) ENGINE = Memory">>),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"addr">>,
            type => <<"IPv6">>,
            data => [
                {8193, 3512, 0, 0, 0, 0, 0, 1},
                {0, 0, 0, 0, 0, 0, 0, 1}
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_ipv6 VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, addr FROM test_ipv6 ORDER BY id">>),
    Data = maps:get(data, Result),
    [[1, {8193, 3512, 0, 0, 0, 0, 0, 1}], [2, {0, 0, 0, 0, 0, 0, 0, 1}]] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_ipv6">>).

mixed_network_types(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_mixed_network">>),
    ok = execute(
        Conn,
        <<"CREATE TABLE test_mixed_network (id UInt32, ipv4 IPv4, ipv6 IPv6) ENGINE = Memory">>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1]},
        #{name => <<"ipv4">>, type => <<"IPv4">>, data => [{192, 168, 1, 1}]},
        #{name => <<"ipv6">>, type => <<"IPv6">>, data => [{8193, 3512, 0, 0, 0, 0, 0, 1}]}
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_mixed_network VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, ipv4, ipv6 FROM test_mixed_network">>),
    Data = maps:get(data, Result),
    [[1, {192, 168, 1, 1}, {8193, 3512, 0, 0, 0, 0, 0, 1}]] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_mixed_network">>).

%%%===================================================================
%%% Test Cases: UUID (Task 27.5)
%%% Requirements: 5.1, 5.2
%%%===================================================================

uuid_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_uuid">>),
    ok = execute(Conn, <<"CREATE TABLE test_uuid (id UInt32, value UUID) ENGINE = Memory">>),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"value">>,
            type => <<"UUID">>,
            data => [
                <<"550e8400-e29b-41d4-a716-446655440000">>,
                <<"123e4567-e89b-12d3-a456-426614174000">>
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_uuid VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, value FROM test_uuid ORDER BY id">>),
    Data = maps:get(data, Result),
    [
        [1, <<"550e8400-e29b-41d4-a716-446655440000">>],
        [2, <<"123e4567-e89b-12d3-a456-426614174000">>]
    ] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_uuid">>).

uuid_various_formats(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_uuid_formats">>),
    ok = execute(
        Conn, <<"CREATE TABLE test_uuid_formats (id UInt32, value UUID) ENGINE = Memory">>
    ),

    %% Test with hyphenated format
    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1]},
        #{
            name => <<"value">>,
            type => <<"UUID">>,
            data => [<<"550e8400-e29b-41d4-a716-446655440000">>]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_uuid_formats VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, value FROM test_uuid_formats">>),
    Data = maps:get(data, Result),
    [[1, <<"550e8400-e29b-41d4-a716-446655440000">>]] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_uuid_formats">>).

%%%===================================================================
%%% Test Cases: Time Types (Task 27.6)
%%% Requirements: 6.1, 6.2, 6.3, 6.4
%%%===================================================================

time_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_time">>),
    ok = execute(Conn, <<"CREATE TABLE test_time (id UInt32, value Time) ENGINE = Memory">>),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"value">>,
            type => <<"Time">>,
            data => [
                {0, 0, 0},
                {12, 30, 45},
                {23, 59, 59}
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_time VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, value FROM test_time ORDER BY id">>),
    Data = maps:get(data, Result),
    [[1, {0, 0, 0}], [2, {12, 30, 45}], [3, {23, 59, 59}]] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_time">>).

%%%===================================================================
%%% Test Cases: Special Types (Task 27.7)
%%% Requirements: 8.1, 8.2, 9.1, 9.2, 10.1, 10.2
%%% Note: Nothing type cannot be used in tables per ClickHouse limitation
%%% Note: Time64 type not yet supported in type parsing
%%%===================================================================

point_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_point">>),
    ok = execute(Conn, <<"CREATE TABLE test_point (id UInt32, value Point) ENGINE = Memory">>),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"value">>,
            type => <<"Point">>,
            data => [
                {0.0, 0.0},
                {1.5, 2.5},
                {-10.5, 20.75}
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_point VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, value FROM test_point ORDER BY id">>),
    Data = maps:get(data, Result),
    [[1, {+0.0, +0.0}], [2, {1.5, 2.5}], [3, {-10.5, 20.75}]] = maps:get(rows, Data),

    ok = execute(Conn, <<"DROP TABLE test_point">>).

interval_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_interval">>),
    ok = execute(
        Conn, <<"CREATE TABLE test_interval (id UInt32, value IntervalSecond) ENGINE = Memory">>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"value">>,
            type => <<"IntervalSecond">>,
            data => [
                {interval, second, 0},
                {interval, second, 3600},
                {interval, second, 86400}
            ]
        }
    ],
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_interval VALUES">>, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT id, value FROM test_interval ORDER BY id">>
    ),
    Data = maps:get(data, Result),
    [[1, {interval, second, 0}], [2, {interval, second, 3600}], [3, {interval, second, 86400}]] = maps:get(
        rows, Data
    ),

    ok = execute(Conn, <<"DROP TABLE test_interval">>).

json_roundtrip(Config) ->
    Conn = ?config(connection, Config),

    ok = execute(Conn, <<"DROP TABLE IF EXISTS test_json">>),
    ok = execute(Conn, <<"CREATE TABLE test_json (id UInt32, value JSON) ENGINE = Memory">>),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"value">>,
            type => <<"JSON">>,
            data => [
                <<"{\"key\":\"value\"}">>,
                <<"{\"number\":42,\"array\":[1,2,3]}">>
            ]
        }
    ],
    %% Use settings to enable string serialization for JSON
    {ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO test_json VALUES">>, InsertData, #{
        settings => [#{key => <<"output_format_native_write_json_as_string">>, value => <<"1">>}]
    }),

    %% Query also needs the setting to return JSON as string
    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT id, value FROM test_json ORDER BY id">>, #{
        settings => [#{key => <<"output_format_native_write_json_as_string">>, value => <<"1">>}]
    }),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    %% Verify we got 2 rows
    2 = length(Rows),

    %% Verify row 1
    [1, Json1] = lists:nth(1, Rows),
    true = is_binary(Json1),
    %% JSON keys may be reordered, so just check it's valid JSON with expected content
    Parsed1 = json:decode(Json1),
    <<"value">> = maps:get(<<"key">>, Parsed1),

    %% Verify row 2
    [2, Json2] = lists:nth(2, Rows),
    true = is_binary(Json2),
    Parsed2 = json:decode(Json2),
    42 = maps:get(<<"number">>, Parsed2),
    [1, 2, 3] = maps:get(<<"array">>, Parsed2),

    ok = execute(Conn, <<"DROP TABLE test_json">>).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Execute a query and return ok or error
-spec execute(pid(), binary()) -> ok | {error, term()}.
execute(Conn, SQL) ->
    case clickhouse_erl:query(Conn, SQL) of
        {ok, _} -> ok;
        {error, Reason} -> {error, Reason}
    end.
