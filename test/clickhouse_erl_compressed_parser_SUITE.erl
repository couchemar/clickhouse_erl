%% @doc Common Test suite for compressed queries via event-driven parser
%%
%% Tests that the event-driven parser correctly handles compression for
%% compressible packet types (DATA, TOTALS, EXTREMES) while skipping
%% decompression for non-compressible types (PROFILE_EVENTS).
%%
%% Feature: streamable-packet-parsing (Task 8.5.8.5)
-module(clickhouse_erl_compressed_parser_SUITE).

-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).

%% LZ4 test cases
-export([
    lz4_select_small/1,
    lz4_select_large_multiblock/1,
    lz4_select_multiple_sequential/1,
    lz4_results_match_uncompressed/1,
    lz4_totals/1,
    lz4_extremes/1
]).

%% ZSTD test cases
-export([
    zstd_select_small/1,
    zstd_select_large_multiblock/1,
    zstd_select_multiple_sequential/1,
    zstd_results_match_uncompressed/1,
    zstd_totals/1,
    zstd_extremes/1
]).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [
        {group, lz4},
        {group, zstd}
    ].

groups() ->
    [
        {lz4, [sequence], [
            lz4_select_small,
            lz4_select_large_multiblock,
            lz4_select_multiple_sequential,
            lz4_results_match_uncompressed,
            lz4_totals,
            lz4_extremes
        ]},
        {zstd, [sequence], [
            zstd_select_small,
            zstd_select_large_multiblock,
            zstd_select_multiple_sequential,
            zstd_results_match_uncompressed,
            zstd_totals,
            zstd_extremes
        ]}
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    %% Create an uncompressed connection for result comparison
    {ok, RefConn} = test_helpers:connect(),
    [{ref_connection, RefConn} | Config].

end_per_suite(Config) ->
    RefConn = ?config(ref_connection, Config),
    test_helpers:disconnect(RefConn),
    test_helpers:cleanup(),
    ok.

init_per_group(lz4, Config) ->
    {ok, Conn} = connect_compressed(lz4),
    [{connection, Conn} | Config];
init_per_group(zstd, Config) ->
    {ok, Conn} = connect_compressed(zstd),
    [{connection, Conn} | Config].

end_per_group(_Group, Config) ->
    Conn = ?config(connection, Config),
    test_helpers:disconnect(Conn),
    ok.

%%%===================================================================
%%% LZ4 Test Cases
%%%===================================================================

lz4_select_small(Config) ->
    select_small(?config(connection, Config)).

lz4_select_large_multiblock(Config) ->
    select_large_multiblock(?config(connection, Config)).

lz4_select_multiple_sequential(Config) ->
    select_multiple_sequential(?config(connection, Config)).

lz4_results_match_uncompressed(Config) ->
    results_match_uncompressed(
        ?config(connection, Config),
        ?config(ref_connection, Config)
    ).

lz4_totals(Config) ->
    totals_with_compression(?config(connection, Config)).

lz4_extremes(Config) ->
    extremes_with_compression(?config(connection, Config)).

%%%===================================================================
%%% ZSTD Test Cases
%%%===================================================================

zstd_select_small(Config) ->
    select_small(?config(connection, Config)).

zstd_select_large_multiblock(Config) ->
    select_large_multiblock(?config(connection, Config)).

zstd_select_multiple_sequential(Config) ->
    select_multiple_sequential(?config(connection, Config)).

zstd_results_match_uncompressed(Config) ->
    results_match_uncompressed(
        ?config(connection, Config),
        ?config(ref_connection, Config)
    ).

zstd_totals(Config) ->
    totals_with_compression(?config(connection, Config)).

zstd_extremes(Config) ->
    extremes_with_compression(?config(connection, Config)).

%%%===================================================================
%%% Shared Test Implementations
%%%===================================================================

%% @doc Small SELECT through compressed parser path
select_small(Conn) ->
    SQL = <<"SELECT number FROM system.numbers LIMIT 100">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    100 = length(Rows),
    [0] = hd(Rows),
    [99] = lists:last(Rows).

%% @doc Large result set generating multiple compressed DATA packets
select_large_multiblock(Conn) ->
    SQL = <<"SELECT number, toString(number) as str FROM system.numbers LIMIT 100000">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{timeout => 30000}),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    100000 = length(Rows),
    [0, <<"0">>] = hd(Rows),
    [99999, <<"99999">>] = lists:last(Rows).

%% @doc Multiple sequential queries on same compressed connection
select_multiple_sequential(Conn) ->
    lists:foreach(
        fun(N) ->
            Limit = integer_to_binary(N * 100),
            SQL = <<"SELECT number FROM system.numbers LIMIT ", Limit/binary>>,
            {ok, Result} = clickhouse_erl:query(Conn, SQL),
            Data = maps:get(data, Result),
            Rows = maps:get(rows, Data),
            Expected = N * 100,
            Expected = length(Rows)
        end,
        lists:seq(1, 5)
    ).

%% @doc Verify compressed results are identical to uncompressed results
results_match_uncompressed(CompConn, RefConn) ->
    SQL = <<"SELECT number, toString(number) as str FROM system.numbers LIMIT 10000">>,
    {ok, CompResult} = clickhouse_erl:query(CompConn, SQL),
    {ok, RefResult} = clickhouse_erl:query(RefConn, SQL),
    CompRows = maps:get(rows, maps:get(data, CompResult)),
    RefRows = maps:get(rows, maps:get(data, RefResult)),
    RefRows = CompRows.

%% @doc TOTALS packet with compression (compressible per protocol)
totals_with_compression(Conn) ->
    SQL = <<
        "SELECT number % 5 as g, count() as cnt "
        "FROM (SELECT number FROM system.numbers LIMIT 100) "
        "GROUP BY g WITH TOTALS ORDER BY g"
    >>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    5 = length(Rows),
    %% Each group should have 20 rows (100 / 5)
    lists:foreach(
        fun([_G, Cnt]) -> 20 = Cnt end,
        Rows
    ).

%% @doc EXTREMES packet with compression (compressible per protocol)
extremes_with_compression(Conn) ->
    SQL = <<"SELECT number FROM system.numbers LIMIT 100">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        settings => #{<<"extremes">> => <<"1">>}
    }),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    100 = length(Rows),
    [0] = hd(Rows),
    [99] = lists:last(Rows).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Connect with specified compression method
-spec connect_compressed(lz4 | zstd) -> {ok, pid()} | {error, term()}.
connect_compressed(Method) ->
    clickhouse_erl:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        #{
            username => test_helpers:test_username(),
            password => test_helpers:test_password(),
            database => test_helpers:test_database(),
            compression => Method
        }
    ).
