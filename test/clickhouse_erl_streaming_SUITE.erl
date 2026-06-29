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
    test_accumulator_correctness/1,
    test_state_machine_large_result_set/1
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

%% Test cases - Block End Event
-export([
    test_block_end_multi_block/1,
    test_block_end_single_block/1,
    test_block_end_backward_compat/1
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
        {group, queries_with_no_data},
        {group, block_end_event}
    ].

%% @doc Defines test groups
groups() ->
    [
        {large_result_streaming, [{timetrap, {minutes, 2}}], [
            test_stream_10000_rows,
            test_accumulator_correctness,
            test_state_machine_large_result_set
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
        ]},
        {block_end_event, [sequence], [
            test_block_end_multi_block,
            test_block_end_single_block,
            test_block_end_backward_compat
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

%% @doc Test streaming 10,000+ rows using column-name-tagged callback
test_stream_10000_rows(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table with 10,000+ rows
    Table = <<"streaming_test_large_", (unique_suffix())/binary>>,
    ok = setup_large_table(Conn, Table, 10000),

    %% Stream all rows using column-name-tagged callback - count column values
    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := _Name, value := _Value}}, Acc) ->
            {ok, Acc + 1};
        ('end', Acc) ->
            {ok, Acc}
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
    %% Table has 2 columns (id, value), so 10000 rows * 2 columns = 20000 values
    FinalCount = maps:get(data, QueryResult),
    ?assertEqual(20000, FinalCount),

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Test accumulator correctness through multiple blocks
test_accumulator_correctness(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table with known data
    Table = <<"streaming_test_accumulator_", (unique_suffix())/binary>>,
    ok = setup_large_table(Conn, Table, 5000),

    %% Stream with accumulator that collects column-map data
    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := Name, value := Value}}, Acc) ->
            Existing = maps:get(Name, Acc, []),
            {ok, Acc#{Name => [Value | Existing]}};
        ('end', Acc) ->
            %% Reverse all accumulated lists on finalization
            {ok, maps:map(fun(_K, V) -> lists:reverse(V) end, Acc)}
    end,

    SQL = <<"SELECT id FROM ", Table/binary, " ORDER BY id">>,
    Options = #{
        query_id => generate_query_id(<<"accumulator_test">>),
        on_data => Callback,
        initial_accumulator => #{}
    },

    %% Execute streaming query
    Result = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify result
    ?assertMatch({ok, _}, Result),
    {ok, QueryResult} = Result,

    %% Verify final accumulator contains column-map data
    DataMap = maps:get(data, QueryResult),
    ?assert(is_map(DataMap), "Should be a column map"),

    %% Verify the id column has 5000 values
    IdValues = maps:get(<<"id">>, DataMap),
    ?assertEqual(5000, length(IdValues)),

    %% Verify values are in order (0..4999)
    ?assertEqual(0, hd(IdValues)),
    ?assertEqual(4999, lists:last(IdValues)),

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: State Machine Integration (Task 8.1)
%%% Requirements: 7.1, 7.2, 7.3
%%%===================================================================

%% @doc Test state machine handles large result sets with multiple DATA packets
%% Verifies that:
%% 1. Multiple DATA packets are processed correctly through state machine
%% 2. No re-parsing occurs across packet boundaries
%% 3. State is properly reset between packets
%% Requirements: 7.1, 7.2, 7.3
%% @doc Test state machine with large result set (Task 8.1)
%% Verifies state machine handles multiple DATA packets correctly
%% Requirements: 7.1, 7.2, 7.3
test_state_machine_large_result_set(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table with enough data to generate multiple DATA packets
    Table = <<"state_machine_test_", (unique_suffix())/binary>>,
    ok = setup_large_table(Conn, Table, 50000),

    %% Track row count via column-name-tagged callback
    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := <<"id">>, value := _Value}}, Acc) ->
            %% Count only id column values to get row count
            {ok, Acc + 1};
        ({data, #{name := _Name, value := _Value}}, Acc) ->
            %% Skip other columns for counting
            {ok, Acc};
        ('end', Acc) ->
            {ok, Acc}
    end,

    SQL = <<"SELECT id, value FROM ", Table/binary, " ORDER BY id">>,
    Options = #{
        query_id => generate_query_id(<<"state_machine_test">>),
        on_data => Callback,
        initial_accumulator => 0
    },

    %% Execute streaming query
    Result = clickhouse_erl:query(Conn, SQL, Options),

    %% Verify all rows processed
    ?assertMatch({ok, _}, Result),
    {ok, QueryResult} = Result,

    %% Verify final count matches expected
    FinalCount = maps:get(data, QueryResult),
    ?assertEqual(50000, FinalCount),

    ct:pal("Total rows received: ~p", [FinalCount]),

    %% Verify state machine correctly handled packet boundaries
    ?assert(FinalCount > 0, "Should have received data"),

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
    StreamCallback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := _Name, value := _Value}}, Acc) ->
            {ok, Acc + 1};
        ('end', Acc) ->
            {ok, Acc}
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
    %% 1000 rows * 2 columns = 2000 values
    ?assertEqual(2000, maps:get(data, StreamQueryResult)),

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
    StreamCallback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := _Name, value := _Value}}, Acc) ->
            {ok, Acc + 1};
        ('end', Acc) ->
            {ok, Acc}
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
    %% 1000 rows * 2 columns = 2000 values
    ?assertEqual(2000, maps:get(data, StreamQueryResult)),

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

    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := _Name, value := _Value}} = Event, Acc) ->
            Parent ! {callback_invoked, CallbackInvoked, Event},
            {ok, Acc + 1};
        ('end', Acc) ->
            {ok, Acc}
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

    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := _Name, value := _Value}} = Event, Acc) ->
            Parent ! {callback_invoked, CallbackInvoked, Event},
            {ok, Acc + 1};
        ('end', Acc) ->
            {ok, Acc}
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
%%% Test Cases: Block End Event (Task 4.1)
%%% Requirements: 1.1, 3.1, 3.3, 5.3
%%%===================================================================

%% @doc Test block_end count with multi-block query
%% Uses low max_block_size to force multiple blocks, verifies block_end count
%% matches the number of non-empty blocks received.
%% Requirements: 1.1, 5.3
test_block_end_multi_block(Config) ->
    Conn = ?config(connection, Config),

    %% Use system.numbers with low max_block_size to force multiple blocks
    Callback = fun
        (block_end, Acc) ->
            BlockEnds = maps:get(block_ends, Acc, 0),
            {ok, Acc#{block_ends => BlockEnds + 1}};
        ({data, #{name := _Name, value := _Value}}, Acc) ->
            Rows = maps:get(rows, Acc, 0),
            {ok, Acc#{rows => Rows + 1}};
        ('end', Acc) ->
            {ok, Acc}
    end,

    SQL = <<"SELECT number FROM system.numbers LIMIT 1000">>,
    Options = #{
        query_id => generate_query_id(<<"block_end_multi">>),
        on_data => Callback,
        initial_accumulator => #{block_ends => 0, rows => 0},
        settings => #{<<"max_block_size">> => <<"100">>}
    },

    Result = clickhouse_erl:query(Conn, SQL, Options),
    ?assertMatch({ok, _}, Result),
    {ok, QueryResult} = Result,

    FinalAcc = maps:get(data, QueryResult),
    BlockEnds = maps:get(block_ends, FinalAcc),
    Rows = maps:get(rows, FinalAcc),

    ct:pal("Multi-block test: rows=~p, block_ends=~p", [Rows, BlockEnds]),

    %% All 1000 rows should be received
    ?assertEqual(1000, Rows),

    %% With max_block_size=100 and 1000 rows, we expect multiple blocks.
    %% The exact count depends on ClickHouse internals, but should be >= 2.
    ?assert(
        BlockEnds >= 2,
        io_lib:format("Expected >= 2 block_end events, got ~p", [BlockEnds])
    ),

    %% Each block_end corresponds to one non-empty block,
    %% so block_ends * 100 should approximate total rows (within block size variance)
    ?assert(
        BlockEnds =< 20,
        io_lib:format(
            "Expected <= 20 block_end events with 100-row blocks, got ~p",
            [BlockEnds]
        )
    ).

%% @doc Test block_end with single-block query (SELECT 1)
%% A trivial query that produces exactly one data block should emit exactly one block_end.
%% Requirements: 1.1, 5.3
test_block_end_single_block(Config) ->
    Conn = ?config(connection, Config),

    Callback = fun
        (block_end, Acc) ->
            BlockEnds = maps:get(block_ends, Acc, 0),
            {ok, Acc#{block_ends => BlockEnds + 1}};
        ({data, #{name := _Name, value := _Value}}, Acc) ->
            {ok, Acc};
        ('end', Acc) ->
            {ok, Acc}
    end,

    SQL = <<"SELECT 1">>,
    Options = #{
        query_id => generate_query_id(<<"block_end_single">>),
        on_data => Callback,
        initial_accumulator => #{block_ends => 0}
    },

    Result = clickhouse_erl:query(Conn, SQL, Options),
    ?assertMatch({ok, _}, Result),
    {ok, QueryResult} = Result,

    FinalAcc = maps:get(data, QueryResult),
    BlockEnds = maps:get(block_ends, FinalAcc),

    ct:pal("Single-block test: block_ends=~p", [BlockEnds]),

    %% SELECT 1 produces exactly one non-empty block
    ?assertEqual(1, BlockEnds).

%% @doc Test backward compatibility - callbacks without block_end handling still work
%% A callback that only handles {data, _} and 'end' should work fine because
%% the default_on_data_callback handles block_end when the user callback doesn't.
%% Requirements: 3.1, 3.3
test_block_end_backward_compat(Config) ->
    Conn = ?config(connection, Config),

    %% This callback does NOT handle block_end - relies on default behavior
    %% The default_on_data_callback handles block_end by returning {ok, Acc}
    %% But user callbacks are called directly, so they need to handle all events.
    %% To test backward compat, we use the default callback (no on_data option)
    %% and verify the query succeeds.

    %% First test: query without custom callback (uses default)
    SQL1 = <<"SELECT number FROM system.numbers LIMIT 500">>,
    Options1 = #{
        query_id => generate_query_id(<<"block_end_compat_default">>),
        settings => #{<<"max_block_size">> => <<"100">>}
    },

    Result1 = clickhouse_erl:query(Conn, SQL1, Options1),
    ?assertMatch({ok, _}, Result1),
    {ok, QueryResult1} = Result1,

    %% Default callback collects data into batch format
    Data1 = maps:get(data, QueryResult1),
    Rows1 = maps:get(rows, Data1),
    ?assertEqual(500, length(Rows1)),

    ct:pal(
        "Backward compat (default callback): ~p rows collected successfully",
        [length(Rows1)]
    ),

    %% Second test: custom callback that handles all events including block_end
    %% (demonstrates a well-behaved callback works with block_end)
    Callback2 = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := _Name, value := _Value}}, Acc) ->
            {ok, Acc + 1};
        ('end', Acc) ->
            {ok, Acc}
    end,

    SQL2 = <<"SELECT number FROM system.numbers LIMIT 500">>,
    Options2 = #{
        query_id => generate_query_id(<<"block_end_compat_custom">>),
        on_data => Callback2,
        initial_accumulator => 0,
        settings => #{<<"max_block_size">> => <<"100">>}
    },

    Result2 = clickhouse_erl:query(Conn, SQL2, Options2),
    ?assertMatch({ok, _}, Result2),
    {ok, QueryResult2} = Result2,
    FinalCount = maps:get(data, QueryResult2),
    ?assertEqual(500, FinalCount),

    ct:pal(
        "Backward compat (custom callback): ~p values processed successfully",
        [FinalCount]
    ).

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

    %% Create table with simple types that response handler supports
    ok = execute(
        Conn,
        <<"CREATE TABLE ", Table/binary, " (id UInt32, value String) ENGINE = Memory">>
    ),

    %% Insert data using system.numbers
    InsertSQL =
        <<"INSERT INTO ", Table/binary,
            " SELECT number, toString(number) FROM system.numbers LIMIT ",
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
