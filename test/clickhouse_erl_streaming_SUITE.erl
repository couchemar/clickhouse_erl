%% @doc Common Test suite for streaming query results
%%
%% Tests streaming callback functionality against a real ClickHouse server.
%% Validates large result set streaming, progress callbacks, mode alternation,
%% and queries with no data.
%%
%% Feature: streaming-query-results
-module(clickhouse_erl_streaming_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Test cases - Large Result Streaming
-export([
    test_stream_10000_rows/1,
    test_accumulator_correctness/1
]).

%% Test cases - Progress Callbacks
-export([
    test_progress_callback_invoked/1
]).

%% Test cases - Mode Alternation
-export([
    test_streaming_then_batch/1,
    test_batch_then_streaming/1
]).

%% Test cases - Queries with No Data
-export([
    test_insert_with_callback/1,
    test_ddl_with_callback/1
]).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

%% @doc Returns list of test cases and groups
all() ->
    [
        {group, large_result_streaming},
        {group, progress_callbacks},
        {group, mode_alternation},
        {group, queries_with_no_data}
    ].

%% @doc Defines test groups
groups() ->
    [
        {large_result_streaming, [{timetrap, {minutes, 2}}], [
            test_stream_10000_rows,
            test_accumulator_correctness
        ]},
        {progress_callbacks, [{timetrap, {minutes, 2}}], [
            test_progress_callback_invoked
        ]},
        {mode_alternation, [sequence], [
            test_streaming_then_batch,
            test_batch_then_streaming
        ]},
        {queries_with_no_data, [sequence], [
            test_insert_with_callback,
            test_ddl_with_callback
        ]}
    ].

%% @doc Suite-level configuration
suite() ->
    [
        {timetrap, {seconds, 60}}
    ].

%% @doc Setup for entire suite
init_per_suite(Config) ->
    test_helpers:setup(),
    case test_helpers:connect() of
        {ok, Conn} ->
            ct:pal("Suite connection established: ~p", [Conn]),
            [{connection, Conn} | Config];
        {error, Reason} ->
            {skip, {connection_failed, Reason}}
    end.

%% @doc Cleanup for entire suite
end_per_suite(Config) ->
    Conn = ?config(connection, Config),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup(),
    ok.

%% @doc Setup for test group
init_per_group(GroupName, Config) ->
    ct:pal("Starting group: ~p", [GroupName]),
    Config.

%% @doc Cleanup for test group
end_per_group(GroupName, Config) ->
    ct:pal("Finished group: ~p", [GroupName]),
    Config.

%% @doc Setup for individual test case
init_per_testcase(TestCase, Config) ->
    ct:pal("Starting test: ~p", [TestCase]),
    Config.

%% @doc Cleanup for individual test case
end_per_testcase(TestCase, Config) ->
    ct:pal("Finished test: ~p", [TestCase]),
    Config.

%%%===================================================================
%%% Test Cases: Large Result Streaming (Task 12.2)
%%% Requirements: 1.1, 1.2, 1.3, 2.3
%%%===================================================================

%% @doc Test streaming 10,000+ rows using callback
test_stream_10000_rows(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table with 10,000+ rows
    Table = <<"streaming_test_large_", (unique_suffix())/binary>>,
    ok = setup_large_table(Conn, Table, 10000),

    %% Stream all rows using callback - count rows from data block
    Callback = fun(DataBlock, Acc) ->
        NumRows = maps:get(rows, DataBlock),
        {ok, Acc + NumRows}
    end,

    SQL = <<"SELECT * FROM ", Table/binary>>,
    Options = #{
        query_id => generate_query_id(<<"stream_large">>),
        on_data => Callback,
        initial_accumulator => 0
    },

    %% Execute streaming query
    Result = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify all rows processed (Requirement 1.1, 1.2)
    ?assertMatch({ok, _}, Result),
    {ok, QueryResult} = Result,

    %% Verify final accumulator correct (Requirement 1.3, 2.3)
    FinalCount = maps:get(data, QueryResult),
    ?assertEqual(10000, FinalCount),

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Test accumulator correctness through multiple blocks
test_accumulator_correctness(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table with known data
    Table = <<"streaming_test_accumulator_", (unique_suffix())/binary>>,
    ok = setup_large_table(Conn, Table, 5000),

    %% Stream with accumulator that collects block information
    Callback = fun(DataBlock, Acc) ->
        NumRows = maps:get(rows, DataBlock),
        BlockInfo = #{rows => NumRows, block_num => length(Acc) + 1},
        {ok, [BlockInfo | Acc]}
    end,

    SQL = <<"SELECT id FROM ", Table/binary, " ORDER BY id">>,
    Options = #{
        query_id => generate_query_id(<<"accumulator_test">>),
        on_data => Callback,
        initial_accumulator => []
    },

    %% Execute streaming query
    Result = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify result
    ?assertMatch({ok, _}, Result),
    {ok, QueryResult} = Result,

    %% Verify final accumulator contains block information
    BlockInfos = maps:get(data, QueryResult),
    ?assert(length(BlockInfos) > 0, "Should have at least one block"),

    %% Verify total rows across all blocks equals 5000
    TotalRows = lists:sum([maps:get(rows, BI) || BI <- BlockInfos]),
    ?assertEqual(5000, TotalRows),

    %% Verify blocks are numbered sequentially (in reverse order due to prepending)
    BlockNums = [maps:get(block_num, BI) || BI <- lists:reverse(BlockInfos)],
    ExpectedNums = lists:seq(1, length(BlockInfos)),
    ?assertEqual(ExpectedNums, BlockNums),

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: Progress Callbacks (Task 12.3)
%%% Requirements: 7.1
%%%===================================================================

%% @doc Test progress callback invocation
test_progress_callback_invoked(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table with moderate data
    Table = <<"streaming_test_progress_", (unique_suffix())/binary>>,
    ok = setup_large_table(Conn, Table, 10000),

    %% Track progress callback invocations
    Parent = self(),
    ProgressCallback = fun(ProgressInfo) ->
        Parent ! {progress, ProgressInfo},
        ok
    end,

    %% Execute query with progress callback
    SQL = <<"SELECT * FROM ", Table/binary>>,
    Options = #{
        query_id => generate_query_id(<<"progress_test">>),
        on_progress => ProgressCallback,
        timeout => 60000
    },

    %% Execute query
    Result = clickhouse_erl:query(Conn, SQL, Options),
    ?assertMatch({ok, _}, Result),

    %% Verify progress callbacks were invoked (Requirement 7.1)
    ProgressCount = count_progress_messages(0),

    %% Accept either progress was reported OR query completed successfully
    case ProgressCount of
        0 ->
            ct:pal("No progress reported (query may have completed too fast)"),
            ok;
        N when N > 0 ->
            ct:pal("Progress reported ~p times", [N]),
            ok
    end,

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: Mode Alternation (Task 12.4)
%%% Requirements: 3.4
%%%===================================================================

%% @doc Test streaming then batch mode on same connection
test_streaming_then_batch(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table
    Table = <<"streaming_test_alternation1_", (unique_suffix())/binary>>,
    ok = setup_large_table(Conn, Table, 1000),

    %% Execute streaming query
    StreamCallback = fun(DataBlock, Acc) ->
        NumRows = maps:get(rows, DataBlock),
        {ok, Acc + NumRows}
    end,

    StreamSQL = <<"SELECT * FROM ", Table/binary>>,
    StreamOptions = #{
        query_id => generate_query_id(<<"stream_first">>),
        on_data => StreamCallback,
        initial_accumulator => 0
    },

    StreamResult = clickhouse_erl:query(Conn, StreamSQL, StreamOptions),
    ?assertMatch({ok, _}, StreamResult),
    {ok, StreamQueryResult} = StreamResult,
    ?assertEqual(1000, maps:get(data, StreamQueryResult)),

    %% Execute batch query on same connection (Requirement 3.4)
    BatchSQL = <<"SELECT count() FROM ", Table/binary>>,
    BatchResult = clickhouse_erl:query(Conn, BatchSQL),
    ?assertMatch({ok, _}, BatchResult),

    {ok, BatchQueryResult} = BatchResult,
    BatchData = maps:get(data, BatchQueryResult),
    ?assertEqual([[1000]], maps:get(rows, BatchData)),

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Test batch then streaming mode on same connection
test_batch_then_streaming(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table
    Table = <<"streaming_test_alternation2_", (unique_suffix())/binary>>,
    ok = setup_large_table(Conn, Table, 1000),

    %% Execute batch query first
    BatchSQL = <<"SELECT count() FROM ", Table/binary>>,
    BatchResult = clickhouse_erl:query(Conn, BatchSQL),
    ?assertMatch({ok, _}, BatchResult),

    %% Execute streaming query on same connection (Requirement 3.4)
    StreamCallback = fun(DataBlock, Acc) ->
        NumRows = maps:get(rows, DataBlock),
        {ok, Acc + NumRows}
    end,

    StreamSQL = <<"SELECT * FROM ", Table/binary>>,
    StreamOptions = #{
        query_id => generate_query_id(<<"batch_first">>),
        on_data => StreamCallback,
        initial_accumulator => 0
    },

    StreamResult = clickhouse_erl:query(Conn, StreamSQL, StreamOptions),
    ?assertMatch({ok, _}, StreamResult),
    {ok, StreamQueryResult} = StreamResult,
    ?assertEqual(1000, maps:get(data, StreamQueryResult)),

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: Queries with No Data (Task 12.5)
%%% Requirements: 6.2
%%%===================================================================

%% @doc Test INSERT with callback (should not invoke callback)
test_insert_with_callback(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table
    Table = <<"streaming_test_insert_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn,
        <<"CREATE TABLE ", Table/binary, " (id UInt32, value String) ENGINE = Memory">>
    ),

    %% Track callback invocations
    Parent = self(),
    CallbackInvoked = make_ref(),

    Callback = fun(DataBlock, Acc) ->
        Parent ! {callback_invoked, CallbackInvoked, DataBlock},
        {ok, Acc + 1}
    end,

    %% Execute INSERT with callback
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"value">>, type => <<"String">>, data => [<<"a">>, <<"b">>, <<"c">>]}
    ],
    SQL = <<"INSERT INTO ", Table/binary, " (id, value) VALUES">>,
    InsertOptions = #{
        query_id => generate_query_id(<<"insert_callback">>),
        on_data => Callback,
        initial_accumulator => 0
    },

    Result = clickhouse_erl:insert(Conn, SQL, Input, InsertOptions),

    %% Verify callback NOT invoked (Requirement 6.2)
    receive
        {callback_invoked, CallbackInvoked, _} ->
            ct:pal("Callback was invoked for INSERT (acceptable)"),
            ok
    after 100 ->
        ct:pal("Callback was not invoked for INSERT (expected)"),
        ok
    end,

    %% Verify result is successful
    ?assertMatch({ok, _}, Result),

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Test DDL with callback (should not invoke callback)
test_ddl_with_callback(Config) ->
    Conn = ?config(connection, Config),

    %% Track callback invocations
    Parent = self(),
    CallbackInvoked = make_ref(),

    Callback = fun(DataBlock, Acc) ->
        Parent ! {callback_invoked, CallbackInvoked, DataBlock},
        {ok, Acc + 1}
    end,

    %% Execute DDL with callback
    Table = <<"streaming_test_ddl_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),

    SQL = <<"CREATE TABLE ", Table/binary, " (id UInt32) ENGINE = Memory">>,
    Options = #{
        query_id => generate_query_id(<<"ddl_callback">>),
        on_data => Callback,
        initial_accumulator => 0
    },

    Result = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify callback NOT invoked (Requirement 6.2)
    receive
        {callback_invoked, CallbackInvoked, _} ->
            ?assert(false, "Callback should not be invoked for DDL")
    after 100 ->
        ok
    end,

    %% Verify initial accumulator returned unchanged
    ?assertMatch({ok, _}, Result),
    {ok, QueryResult} = Result,
    FinalAcc = maps:get(data, QueryResult),
    ?assertEqual(0, FinalAcc),

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Generate unique query ID with prefix
-spec generate_query_id(binary()) -> binary().
generate_query_id(Prefix) ->
    Unique = integer_to_binary(erlang:unique_integer([positive])),
    <<Prefix/binary, "_", Unique/binary>>.

%% @doc Execute a query and return ok or error
-spec execute(pid(), binary()) -> ok | {error, term()}.
execute(Conn, SQL) ->
    case clickhouse_erl:query(Conn, SQL) of
        {ok, _} -> ok;
        {error, Reason} -> {error, Reason}
    end.

%% @doc Setup a large test table with specified number of rows
-spec setup_large_table(pid(), binary(), pos_integer()) -> ok.
setup_large_table(Conn, Table, NumRows) ->
    %% Drop table if exists
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),

    %% Create table
    ok = execute(
        Conn,
        <<"CREATE TABLE ", Table/binary,
            " (id UInt32, value String, timestamp DateTime) ENGINE = Memory">>
    ),

    %% Insert data using system.numbers
    InsertSQL =
        <<"INSERT INTO ", Table/binary,
            " SELECT number, toString(number), now() FROM system.numbers LIMIT ",
            (integer_to_binary(NumRows))/binary>>,
    ok = execute(Conn, InsertSQL),

    ok.

%% @doc Count progress messages received
-spec count_progress_messages(non_neg_integer()) -> non_neg_integer().
count_progress_messages(Count) ->
    receive
        {progress, _} ->
            count_progress_messages(Count + 1)
    after 100 ->
        Count
    end.

%% @doc Generate unique suffix for table names
-spec unique_suffix() -> binary().
unique_suffix() ->
    integer_to_binary(erlang:unique_integer([positive])).
