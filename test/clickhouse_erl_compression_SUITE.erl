%% @doc Common Test suite for compression support
%%
%% Tests compression functionality against a real ClickHouse server.
%% Validates LZ4, ZSTD, and disabled compression modes.
%%
%% Feature: compression-support
-module(clickhouse_erl_compression_SUITE).

-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).

%% Test cases - LZ4 Compression (Task 10.1, 10.3)
-export([
    select_small_result_lz4/1,
    select_large_result_lz4/1,
    select_multiple_queries_lz4/1,
    insert_with_lz4/1
]).

%% Test cases - ZSTD Compression (Task 10.2, 10.3)
-export([
    select_small_result_zstd/1,
    select_large_result_zstd/1,
    select_multiple_queries_zstd/1,
    insert_with_zstd/1
]).

%% Test cases - Compression Disabled (Task 10.4)
-export([
    compression_disabled_backward_compatibility/1
]).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

%% @doc Returns suite configuration
suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [
        {group, lz4_compression},
        {group, zstd_compression},
        {group, compression_disabled}
    ].

groups() ->
    [
        {lz4_compression, [sequence], [
            select_small_result_lz4,
            select_large_result_lz4,
            select_multiple_queries_lz4,
            insert_with_lz4
        ]},
        {zstd_compression, [sequence], [
            select_small_result_zstd,
            select_large_result_zstd,
            select_multiple_queries_zstd,
            insert_with_zstd
        ]},
        {compression_disabled, [sequence], [
            compression_disabled_backward_compatibility
        ]}
    ].

%% @doc Initialize test suite - start application
init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

%% @doc Cleanup test suite
end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% @doc Initialize test group - create connection with appropriate compression
init_per_group(lz4_compression, Config) ->
    ct:pal("Initializing LZ4 compression group, creating connection"),
    case connect_with_compression(lz4) of
        {ok, Conn} ->
            ct:pal("LZ4 connection created: ~p", [Conn]),
            [{connection, Conn} | Config];
        {error, Reason} ->
            ct:pal("LZ4 connection failed: ~p", [Reason]),
            ct:fail({connection_failed, Reason})
    end;
init_per_group(zstd_compression, Config) ->
    ct:pal("Initializing ZSTD compression group, creating connection"),
    case connect_with_compression(zstd) of
        {ok, Conn} ->
            ct:pal("ZSTD connection created: ~p", [Conn]),
            [{connection, Conn} | Config];
        {error, Reason} ->
            ct:pal("ZSTD connection failed: ~p", [Reason]),
            ct:fail({connection_failed, Reason})
    end;
init_per_group(compression_disabled, Config) ->
    ct:pal("Initializing compression disabled group, creating connection without compression"),
    case connect_without_compression() of
        {ok, Conn} ->
            ct:pal("Connection without compression created: ~p", [Conn]),
            [{connection, Conn} | Config];
        {error, Reason} ->
            ct:pal("Connection without compression failed: ~p", [Reason]),
            ct:fail({connection_failed, Reason})
    end.

%% @doc Cleanup test group - disconnect
end_per_group(_Group, Config) ->
    Conn = ?config(connection, Config),
    test_helpers:disconnect(Conn),
    ok.

%%%===================================================================
%%% Test Cases: LZ4 Compression (Task 10.1)
%%% Requirements: 1.1, 6.2
%%%===================================================================

select_small_result_lz4(Config) ->
    Conn = ?config(connection, Config),

    %% Execute simple SELECT query with LZ4 compression
    ct:pal("Starting select_small_result_lz4"),
    SQL = <<"SELECT number FROM system.numbers LIMIT 100">>,
    Options = #{timeout => 30000},
    ct:pal("Executing query: ~p with options: ~p", [SQL, Options]),
    {ok, QueryResult} = clickhouse_erl:query(Conn, SQL, Options),
    ct:pal("Query result received"),

    %% Verify data is correct (Requirement 1.1, 6.2)
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    100 = length(Rows),

    %% Verify first and last values
    [0] = lists:nth(1, Rows),
    [99] = lists:nth(100, Rows).

select_large_result_lz4(Config) ->
    Conn = ?config(connection, Config),

    %% Execute SELECT query with larger result set
    SQL = <<"SELECT number, toString(number) as str FROM system.numbers LIMIT 10000">>,
    Options = #{timeout => 30000},
    {ok, QueryResult} = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify query succeeds (Requirement 1.1, 6.2)
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    10000 = length(Rows),

    %% Verify first row
    [FirstNum, FirstStr] = lists:nth(1, Rows),
    0 = FirstNum,
    <<"0">> = FirstStr,

    %% Verify last row
    [LastNum, LastStr] = lists:nth(10000, Rows),
    9999 = LastNum,
    <<"9999">> = LastStr.

select_multiple_queries_lz4(Config) ->
    Conn = ?config(connection, Config),

    %% Execute multiple queries on same connection with LZ4
    SQL1 = <<"SELECT number FROM system.numbers LIMIT 50">>,
    Options = #{timeout => 30000},
    {ok, QueryResult1} = clickhouse_erl:query(Conn, SQL1, Options),
    Data1 = maps:get(data, QueryResult1),
    Rows1 = maps:get(rows, Data1),
    50 = length(Rows1),
    [0] = lists:nth(1, Rows1),
    [49] = lists:nth(50, Rows1),

    %% Second query
    SQL2 = <<"SELECT number FROM system.numbers LIMIT 25">>,
    {ok, QueryResult2} = clickhouse_erl:query(Conn, SQL2, Options),
    Data2 = maps:get(data, QueryResult2),
    Rows2 = maps:get(rows, Data2),
    25 = length(Rows2),
    [0] = lists:nth(1, Rows2),
    [24] = lists:nth(25, Rows2).

insert_with_lz4(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table
    Table = <<"test_insert_lz4_compression">>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn,
        <<"CREATE TABLE ", Table/binary, " (id UInt32, value String) ENGINE = Memory">>
    ),

    %% Execute INSERT with LZ4 compression (Requirement 1.1, 6.1)
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4, 5]},
        #{
            name => <<"value">>,
            type => <<"String">>,
            data => [<<"a">>, <<"b">>, <<"c">>, <<"d">>, <<"e">>]
        }
    ],
    SQL = <<"INSERT INTO ", Table/binary, " (id, value) VALUES">>,
    {ok, InsertResult} = clickhouse_erl:insert(Conn, SQL, Input),

    %% Verify INSERT succeeded
    5 = maps:get(rows_inserted, InsertResult),

    %% Verify data written correctly
    {ok, QueryResult} = clickhouse_erl:query(
        Conn,
        <<"SELECT id, value FROM ", Table/binary, " ORDER BY id">>
    ),
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    [[1, <<"a">>], [2, <<"b">>], [3, <<"c">>], [4, <<"d">>], [5, <<"e">>]] = Rows,

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: ZSTD Compression (Task 10.2)
%%% Requirements: 1.2, 6.2
%%%===================================================================

select_small_result_zstd(Config) ->
    Conn = ?config(connection, Config),

    %% Execute simple SELECT query with ZSTD compression
    ct:pal("Starting select_small_result_zstd"),
    SQL = <<"SELECT number FROM system.numbers LIMIT 100">>,
    Options = #{timeout => 30000},
    ct:pal("Executing query: ~p with options: ~p", [SQL, Options]),
    {ok, QueryResult} = clickhouse_erl:query(Conn, SQL, Options),
    ct:pal("Query result received"),

    %% Verify data is correct (Requirement 1.2, 6.2)
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    100 = length(Rows),

    %% Verify first and last values
    [0] = lists:nth(1, Rows),
    [99] = lists:nth(100, Rows).

select_large_result_zstd(Config) ->
    Conn = ?config(connection, Config),

    %% Execute SELECT query with larger result set
    SQL = <<"SELECT number, toString(number) as str FROM system.numbers LIMIT 10000">>,
    Options = #{timeout => 30000},
    {ok, QueryResult} = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify query succeeds (Requirement 1.2, 6.2)
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    10000 = length(Rows),

    %% Verify first row
    [FirstNum, FirstStr] = lists:nth(1, Rows),
    0 = FirstNum,
    <<"0">> = FirstStr,

    %% Verify last row
    [LastNum, LastStr] = lists:nth(10000, Rows),
    9999 = LastNum,
    <<"9999">> = LastStr.

select_multiple_queries_zstd(Config) ->
    Conn = ?config(connection, Config),

    %% Execute multiple queries on same connection with ZSTD
    SQL1 = <<"SELECT number FROM system.numbers LIMIT 50">>,
    Options = #{timeout => 30000},
    {ok, QueryResult1} = clickhouse_erl:query(Conn, SQL1, Options),
    Data1 = maps:get(data, QueryResult1),
    Rows1 = maps:get(rows, Data1),
    50 = length(Rows1),
    [0] = lists:nth(1, Rows1),
    [49] = lists:nth(50, Rows1),

    %% Second query
    SQL2 = <<"SELECT number FROM system.numbers LIMIT 25">>,
    {ok, QueryResult2} = clickhouse_erl:query(Conn, SQL2, Options),
    Data2 = maps:get(data, QueryResult2),
    Rows2 = maps:get(rows, Data2),
    25 = length(Rows2),
    [0] = lists:nth(1, Rows2),
    [24] = lists:nth(25, Rows2).

insert_with_zstd(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table
    Table = <<"test_insert_zstd_compression">>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn,
        <<"CREATE TABLE ", Table/binary, " (id UInt32, value String) ENGINE = Memory">>
    ),

    %% Execute INSERT with ZSTD compression (Requirement 1.2, 6.1)
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4, 5]},
        #{
            name => <<"value">>,
            type => <<"String">>,
            data => [<<"a">>, <<"b">>, <<"c">>, <<"d">>, <<"e">>]
        }
    ],
    SQL = <<"INSERT INTO ", Table/binary, " (id, value) VALUES">>,
    {ok, InsertResult} = clickhouse_erl:insert(Conn, SQL, Input),

    %% Verify INSERT succeeded
    5 = maps:get(rows_inserted, InsertResult),

    %% Verify data written correctly
    {ok, QueryResult} = clickhouse_erl:query(
        Conn,
        <<"SELECT id, value FROM ", Table/binary, " ORDER BY id">>
    ),
    Data = maps:get(data, QueryResult),
    Rows = maps:get(rows, Data),
    [[1, <<"a">>], [2, <<"b">>], [3, <<"c">>], [4, <<"d">>], [5, <<"e">>]] = Rows,

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: Compression Disabled (Task 10.4)
%%% Requirements: 9.1, 9.2
%%%===================================================================

compression_disabled_backward_compatibility(Config) ->
    Conn = ?config(connection, Config),

    %% Execute SELECT query without compression (Requirement 9.1, 9.2)
    ct:pal("Testing backward compatibility with compression disabled"),
    SQL1 = <<"SELECT number FROM system.numbers LIMIT 100">>,
    Options = #{timeout => 30000},
    {ok, QueryResult1} = clickhouse_erl:query(Conn, SQL1, Options),

    %% Verify data is correct
    Data1 = maps:get(data, QueryResult1),
    Rows1 = maps:get(rows, Data1),
    100 = length(Rows1),
    [0] = lists:nth(1, Rows1),
    [99] = lists:nth(100, Rows1),

    %% Execute INSERT without compression
    Table = <<"test_insert_no_compression">>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn,
        <<"CREATE TABLE ", Table/binary, " (id UInt32, value String) ENGINE = Memory">>
    ),

    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"value">>, type => <<"String">>, data => [<<"a">>, <<"b">>, <<"c">>]}
    ],
    SQL2 = <<"INSERT INTO ", Table/binary, " (id, value) VALUES">>,
    {ok, InsertResult} = clickhouse_erl:insert(Conn, SQL2, Input),

    %% Verify INSERT succeeded
    3 = maps:get(rows_inserted, InsertResult),

    %% Verify data written correctly
    {ok, QueryResult2} = clickhouse_erl:query(
        Conn,
        <<"SELECT id, value FROM ", Table/binary, " ORDER BY id">>
    ),
    Data2 = maps:get(data, QueryResult2),
    Rows2 = maps:get(rows, Data2),
    [[1, <<"a">>], [2, <<"b">>], [3, <<"c">>]] = Rows2,

    %% Execute multiple queries to verify connection stability
    SQL3 = <<"SELECT number FROM system.numbers LIMIT 50">>,
    {ok, QueryResult3} = clickhouse_erl:query(Conn, SQL3, Options),
    Data3 = maps:get(data, QueryResult3),
    Rows3 = maps:get(rows, Data3),
    50 = length(Rows3),
    [0] = lists:nth(1, Rows3),
    [49] = lists:nth(50, Rows3),

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Connect to ClickHouse with specified compression method
-spec connect_with_compression(lz4 | zstd) -> {ok, pid()} | {error, term()}.
connect_with_compression(Method) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database(),
        compression => Method
    },
    clickhouse_erl:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ).

%% @doc Connect to ClickHouse without compression (backward compatibility)
-spec connect_without_compression() -> {ok, pid()} | {error, term()}.
connect_without_compression() ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    clickhouse_erl:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ).

%% @doc Execute a query and return ok or error
-spec execute(pid(), binary()) -> ok | {error, term()}.
execute(Conn, SQL) ->
    case clickhouse_erl:query(Conn, SQL) of
        {ok, _} -> ok;
        {error, Reason} -> {error, Reason}
    end.
