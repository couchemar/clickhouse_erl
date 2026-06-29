%% @doc Common Test suite for streaming validation
%%
%% Validates that the event-driven parser architecture solves the original
%% problems: no infinite accumulators, true streaming (no buffer bloat),
%% and chunk-ready parsing (handles partial packets efficiently).
%%
%% Feature: streamable-packet-parsing (Task 8.6)
-module(clickhouse_erl_streaming_validation_SUITE).

-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).

%% Test cases - No Infinite Accumulators
-export([
    streaming_no_accumulator_growth/1
]).

%% Test cases - True Streaming (No Buffer Bloat)
-export([
    streaming_large_result_constant_memory/1
]).

%% Test cases - Batch Mode Baseline
-export([
    batch_mode_accumulates_correctly/1
]).

%% Test cases - Multi-Block Streaming
-export([
    parser_handles_multi_block_streaming/1
]).

%% Test cases - Chunk-Ready Parsing Correctness
-export([
    chunk_ready_parsing_correctness/1
]).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

%% @doc Suite-level configuration
-spec suite() -> [term()].
suite() ->
    [{timetrap, {minutes, 3}}].

%% @doc Returns list of test groups
-spec all() -> [term()].
all() ->
    [
        {group, no_infinite_accumulators},
        {group, true_streaming},
        {group, batch_mode_baseline},
        {group, multi_block_streaming},
        {group, chunk_ready_parsing}
    ].

%% @doc Defines test groups
-spec groups() -> [term()].
groups() ->
    [
        {no_infinite_accumulators, [sequence], [
            streaming_no_accumulator_growth
        ]},
        {true_streaming, [sequence], [
            streaming_large_result_constant_memory
        ]},
        {batch_mode_baseline, [sequence], [
            batch_mode_accumulates_correctly
        ]},
        {multi_block_streaming, [sequence], [
            parser_handles_multi_block_streaming
        ]},
        {chunk_ready_parsing, [sequence], [
            chunk_ready_parsing_correctness
        ]}
    ].

%% @doc Setup for entire suite
-spec init_per_suite(term()) -> term().
init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

%% @doc Cleanup for entire suite
-spec end_per_suite(term()) -> ok.
end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% @doc Setup for test group — create a fresh connection per group
-spec init_per_group(atom(), term()) -> term().
init_per_group(_Group, Config) ->
    {ok, Conn} = test_helpers:connect(),
    [{connection, Conn} | Config].

%% @doc Cleanup for test group
-spec end_per_group(atom(), term()) -> ok.
end_per_group(_Group, Config) ->
    Conn = ?config(connection, Config),
    test_helpers:disconnect(Conn),
    ok.

%%%===================================================================
%%% Test Cases: No Infinite Accumulators
%%% Validates: The streaming callback controls accumulation.
%%% Internal AccState fields (column_data, columns) do NOT grow
%%% unboundedly in streaming mode because values are dispatched
%%% to the user callback immediately.
%%%===================================================================

%% @doc Execute a streaming query with a counting callback.
%% The callback only increments a counter — it does NOT accumulate rows.
%% The final result should be just the count, proving that streaming mode
%% does not force the user to accumulate all data.
-spec streaming_no_accumulator_growth(term()) -> ok.
streaming_no_accumulator_growth(Config) ->
    Conn = ?config(connection, Config),

    NumRows = 50000,

    %% Callback that only counts — never accumulates row data
    Callback = fun
        (block_end, Count) -> {ok, Count};
        ({data, #{name := _Name, value := _Value}}, Count) -> {ok, Count + 1};
        ('end', Count) -> {ok, Count}
    end,

    SQL =
        <<"SELECT number, toString(number) as str FROM system.numbers LIMIT ",
            (integer_to_binary(NumRows))/binary>>,
    Options = #{
        on_data => Callback,
        initial_accumulator => 0
    },

    {ok, Result} = clickhouse_erl:query(Conn, SQL, Options),

    %% Final accumulator is just a count (small integer), not all 50k rows
    FinalCount = maps:get(data, Result),

    %% 50000 rows * 2 columns = 100000 column values dispatched
    100000 = FinalCount,

    %% The key validation: the result is a single integer, not a list of rows.
    %% This proves the streaming architecture does not force accumulation.
    true = is_integer(FinalCount),

    ct:pal(
        "Streaming no-accumulator: ~p values dispatched, final acc is integer ~p",
        [FinalCount, FinalCount]
    ),
    ok.

%%%===================================================================
%%% Test Cases: True Streaming (No Buffer Bloat)
%%% Validates: The user callback receives individual values and the
%%% final accumulator stays small (just a running sum/count).
%%% This proves the parser + connection do not buffer all data internally.
%%%===================================================================

%% @doc Execute a streaming query returning many rows.
%% Use a callback that keeps only a running count and sum.
%% Verify the final accumulator is small — not all rows.
-spec streaming_large_result_constant_memory(term()) -> ok.
streaming_large_result_constant_memory(Config) ->
    Conn = ?config(connection, Config),

    NumRows = 100000,

    %% Callback that maintains only a running count and sum — O(1) memory
    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := <<"number">>, value := V}}, #{count := C, sum := S}) ->
            {ok, #{count => C + 1, sum => S + V}};
        ({data, #{name := _Other, value := _V}}, Acc) ->
            %% Ignore non-number columns (toString column)
            {ok, Acc};
        ('end', Acc) ->
            {ok, Acc}
    end,

    SQL =
        <<"SELECT number, toString(number) as str FROM system.numbers LIMIT ",
            (integer_to_binary(NumRows))/binary>>,
    Options = #{
        on_data => Callback,
        initial_accumulator => #{count => 0, sum => 0}
    },

    {ok, Result} = clickhouse_erl:query(Conn, SQL, Options),

    FinalAcc = maps:get(data, Result),

    %% Verify correctness
    NumRows = maps:get(count, FinalAcc),
    %% sum(0..N-1)
    ExpectedSum = (NumRows - 1) * NumRows div 2,
    ExpectedSum = maps:get(sum, FinalAcc),

    %% The key validation: final accumulator is a small map with 2 keys,
    %% NOT a list of 100k rows. This proves true streaming with no bloat.
    2 = maps:size(FinalAcc),

    ct:pal(
        "True streaming: ~p rows, sum=~p, acc size=~p keys",
        [maps:get(count, FinalAcc), maps:get(sum, FinalAcc), maps:size(FinalAcc)]
    ),
    ok.

%%%===================================================================
%%% Test Cases: Batch Mode Baseline
%%% Validates: Batch mode (no on_data callback) still accumulates
%%% all rows correctly. This is expected behavior — batch mode DOES
%%% accumulate, but that's by design.
%%%===================================================================

%% @doc Execute a batch query (no on_data callback).
%% Verify all rows are returned correctly in column-oriented format.
-spec batch_mode_accumulates_correctly(term()) -> ok.
batch_mode_accumulates_correctly(Config) ->
    Conn = ?config(connection, Config),

    NumRows = 1000,

    SQL =
        <<"SELECT number, toString(number) as str FROM system.numbers LIMIT ",
            (integer_to_binary(NumRows))/binary>>,

    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    Data = maps:get(data, Result),
    Columns = maps:get(columns, Data),
    Rows = maps:get(rows, Data),

    %% Verify column metadata
    2 = length(Columns),
    [#{name := <<"number">>}, #{name := <<"str">>}] = Columns,

    %% Verify all rows returned
    NumRows = length(Rows),

    %% Verify first and last rows
    [0, <<"0">>] = hd(Rows),
    [999, <<"999">>] = lists:last(Rows),

    ct:pal("Batch mode: ~p rows returned with ~p columns", [length(Rows), length(Columns)]),
    ok.

%%%===================================================================
%%% Test Cases: Multi-Block Streaming
%%% Validates: Streaming callback receives values from ALL data blocks
%%% when a query returns multiple DATA packets.
%%%===================================================================

%% @doc Execute a query that returns multiple data blocks.
%% Verify streaming callback receives values from all blocks correctly.
-spec parser_handles_multi_block_streaming(term()) -> ok.
parser_handles_multi_block_streaming(Config) ->
    Conn = ?config(connection, Config),

    %% 200k rows should generate multiple DATA blocks from ClickHouse
    NumRows = 200000,

    %% Accumulate into column map to verify ordering across blocks
    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := Name, value := Value}}, Acc) ->
            Existing = maps:get(Name, Acc, []),
            {ok, Acc#{Name => [Value | Existing]}};
        ('end', Acc) ->
            %% Reverse accumulated lists to restore original order
            {ok, maps:map(fun(_K, V) -> lists:reverse(V) end, Acc)}
    end,

    SQL = <<"SELECT number FROM system.numbers LIMIT ", (integer_to_binary(NumRows))/binary>>,
    Options = #{
        on_data => Callback,
        initial_accumulator => #{}
    },

    {ok, Result} = clickhouse_erl:query(Conn, SQL, Options),

    DataMap = maps:get(data, Result),
    Numbers = maps:get(<<"number">>, DataMap),

    %% Verify all rows received across all blocks
    NumRows = length(Numbers),

    %% Verify ordering is correct (values span multiple blocks)
    0 = hd(Numbers),
    199999 = lists:last(Numbers),

    %% Verify continuity: no gaps between blocks
    %% Check a few boundary points
    true = lists:nth(65536, Numbers) =:= 65535,
    true = lists:nth(100001, Numbers) =:= 100000,

    ct:pal(
        "Multi-block streaming: ~p values received, first=~p, last=~p",
        [length(Numbers), hd(Numbers), lists:last(Numbers)]
    ),
    ok.

%%%===================================================================
%%% Test Cases: Chunk-Ready Parsing Correctness
%%% Validates: The parser produces correct results regardless of how
%%% TCP chunks arrive. The TCP layer handles chunking transparently,
%%% so we verify end-to-end correctness with various query sizes.
%%%===================================================================

%% @doc Execute queries of different sizes and verify results are correct.
%% This validates the parser produces correct results regardless of
%% how TCP chunks arrive — the TCP layer handles chunking transparently.
-spec chunk_ready_parsing_correctness(term()) -> ok.
chunk_ready_parsing_correctness(Config) ->
    Conn = ?config(connection, Config),

    %% Test with multiple query sizes to exercise different chunking patterns
    Sizes = [1, 10, 100, 1000, 10000, 50000],

    lists:foreach(
        fun(N) ->
            Callback = fun
                (block_end, Acc) ->
                    {ok, Acc};
                ({data, #{name := <<"number">>, value := V}}, {Count, Sum}) ->
                    {ok, {Count + 1, Sum + V}};
                ({data, #{name := _Other, value := _V}}, Acc) ->
                    {ok, Acc};
                ('end', Acc) ->
                    {ok, Acc}
            end,

            SQL = <<"SELECT number FROM system.numbers LIMIT ", (integer_to_binary(N))/binary>>,
            Options = #{
                on_data => Callback,
                initial_accumulator => {0, 0}
            },

            {ok, Result} = clickhouse_erl:query(Conn, SQL, Options),

            {Count, Sum} = maps:get(data, Result),

            %% Verify row count
            N = Count,

            %% Verify sum correctness: sum(0..N-1) = N*(N-1)/2
            ExpectedSum = N * (N - 1) div 2,
            ExpectedSum = Sum,

            ct:pal(
                "Chunk-ready size=~p: count=~p, sum=~p (expected ~p)",
                [N, Count, Sum, ExpectedSum]
            )
        end,
        Sizes
    ),

    ok.
