-module(clickhouse_erl_connection_state_cleanup_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Tests for connection state cleanup between queries
%%% Requirements: 3.4
%%%===================================================================

%% Setup and cleanup for all tests
setup() ->
    test_helpers:setup().

cleanup(_) ->
    test_helpers:cleanup().

%% @doc Test that active_query_state is cleared after a successful query
%% This verifies that the connection is ready for the next query
active_query_state_cleared_after_query_test_() ->
    {setup, fun setup/0, fun cleanup/1,
        ?_test(begin
            %% Start ClickHouse connection with proper credentials
            {ok, Conn} = test_helpers:connect(),

            %% Execute first query
            PreparedRequest1 = #{
                sql => <<"SELECT 1">>,
                query_id => <<"query-1">>
            },
            {ok, _Result1} = clickhouse_erl_connection:query(Conn, PreparedRequest1),

            %% Verify active_query_state is cleared
            {ok, ConnInfo} = clickhouse_erl_connection:get_connection_info(Conn),
            ?assertEqual(undefined, maps:get(active_query_state, ConnInfo)),

            %% Execute second query to verify connection is ready
            PreparedRequest2 = #{
                sql => <<"SELECT 2">>,
                query_id => <<"query-2">>
            },
            {ok, _Result2} = clickhouse_erl_connection:query(Conn, PreparedRequest2),

            %% Verify active_query_state is cleared again
            {ok, ConnInfo2} = clickhouse_erl_connection:get_connection_info(Conn),
            ?assertEqual(undefined, maps:get(active_query_state, ConnInfo2)),

            %% Cleanup
            ok = test_helpers:disconnect(Conn),
            ok
        end)}.

%% @doc Test that streaming query state doesn't leak to batch query
%% This verifies that callbacks and accumulators are properly isolated
streaming_to_batch_no_state_leak_test_() ->
    {setup, fun setup/0, fun cleanup/1,
        ?_test(begin
            %% Start ClickHouse connection with proper credentials
            {ok, Conn} = test_helpers:connect(),

            %% Execute streaming query with callback
            StreamingCallback = fun(DataBlock, Acc) ->
                Rows = maps:get(rows, DataBlock, 0),
                {ok, Acc + Rows}
            end,

            PreparedRequest1 = #{
                sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
                query_id => <<"streaming-query">>,
                on_data => StreamingCallback,
                initial_accumulator => 0
            },
            {ok, StreamingResult} = clickhouse_erl_connection:query(Conn, PreparedRequest1),

            %% Verify streaming result format
            ?assert(maps:is_key(data, StreamingResult)),
            ?assertEqual(5, maps:get(data, StreamingResult)),

            %% Verify active_query_state is cleared
            {ok, ConnInfo1} = clickhouse_erl_connection:get_connection_info(Conn),
            ?assertEqual(undefined, maps:get(active_query_state, ConnInfo1)),

            %% Execute batch query (no callback)
            PreparedRequest2 = #{
                sql => <<"SELECT number FROM system.numbers LIMIT 3">>,
                query_id => <<"batch-query">>
            },
            {ok, BatchResult} = clickhouse_erl_connection:query(Conn, PreparedRequest2),

            %% Verify batch result format (should have columns and rows, not accumulator)
            ?assert(maps:is_key(data, BatchResult)),
            BatchData = maps:get(data, BatchResult),
            ?assert(maps:is_key(columns, BatchData)),
            ?assert(maps:is_key(rows, BatchData)),
            % Should not be the streaming accumulator
            ?assertNot(is_integer(BatchData)),

            %% Verify active_query_state is cleared
            {ok, ConnInfo2} = clickhouse_erl_connection:get_connection_info(Conn),
            ?assertEqual(undefined, maps:get(active_query_state, ConnInfo2)),

            %% Cleanup
            ok = test_helpers:disconnect(Conn),
            ok
        end)}.

%% @doc Test that batch query state doesn't leak to streaming query
%% This verifies the reverse direction of state isolation
batch_to_streaming_no_state_leak_test_() ->
    {setup, fun setup/0, fun cleanup/1,
        ?_test(begin
            %% Start ClickHouse connection with proper credentials
            {ok, Conn} = test_helpers:connect(),

            %% Execute batch query first
            PreparedRequest1 = #{
                sql => <<"SELECT number FROM system.numbers LIMIT 3">>,
                query_id => <<"batch-query-first">>
            },
            {ok, BatchResult} = clickhouse_erl_connection:query(Conn, PreparedRequest1),

            %% Verify batch result format
            ?assert(maps:is_key(data, BatchResult)),
            BatchData = maps:get(data, BatchResult),
            ?assert(maps:is_key(columns, BatchData)),
            ?assert(maps:is_key(rows, BatchData)),

            %% Verify active_query_state is cleared
            {ok, ConnInfo1} = clickhouse_erl_connection:get_connection_info(Conn),
            ?assertEqual(undefined, maps:get(active_query_state, ConnInfo1)),

            %% Execute streaming query with callback
            StreamingCallback = fun(DataBlock, Acc) ->
                Rows = maps:get(rows, DataBlock, 0),
                {ok, Acc + Rows}
            end,

            PreparedRequest2 = #{
                sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
                query_id => <<"streaming-query-second">>,
                on_data => StreamingCallback,
                initial_accumulator => 0
            },
            {ok, StreamingResult} = clickhouse_erl_connection:query(Conn, PreparedRequest2),

            %% Verify streaming result format
            ?assert(maps:is_key(data, StreamingResult)),
            ?assertEqual(5, maps:get(data, StreamingResult)),

            %% Verify active_query_state is cleared
            {ok, ConnInfo2} = clickhouse_erl_connection:get_connection_info(Conn),
            ?assertEqual(undefined, maps:get(active_query_state, ConnInfo2)),

            %% Cleanup
            ok = test_helpers:disconnect(Conn),
            ok
        end)}.

%% @doc Test multiple alternations between streaming and batch modes
%% This verifies that the connection can handle repeated mode switches
multiple_mode_alternations_test_() ->
    {setup, fun setup/0, fun cleanup/1,
        ?_test(begin
            %% Start ClickHouse connection with proper credentials
            {ok, Conn} = test_helpers:connect(),

            %% Define streaming callback
            StreamingCallback = fun(DataBlock, Acc) ->
                Rows = maps:get(rows, DataBlock, 0),
                {ok, Acc + Rows}
            end,

            %% Perform multiple alternations
            lists:foreach(
                fun(N) ->
                    %% Streaming query
                    StreamingRequest = #{
                        sql => <<"SELECT number FROM system.numbers LIMIT 2">>,
                        query_id => list_to_binary("streaming-" ++ integer_to_list(N)),
                        on_data => StreamingCallback,
                        initial_accumulator => 0
                    },
                    {ok, StreamingResult} = clickhouse_erl_connection:query(Conn, StreamingRequest),
                    ?assert(maps:is_key(data, StreamingResult)),
                    ?assertEqual(2, maps:get(data, StreamingResult)),

                    %% Verify state cleared
                    {ok, ConnInfo1} = clickhouse_erl_connection:get_connection_info(Conn),
                    ?assertEqual(undefined, maps:get(active_query_state, ConnInfo1)),

                    %% Batch query
                    BatchRequest = #{
                        sql => <<"SELECT number FROM system.numbers LIMIT 2">>,
                        query_id => list_to_binary("batch-" ++ integer_to_list(N))
                    },
                    {ok, BatchResult} = clickhouse_erl_connection:query(Conn, BatchRequest),
                    ?assert(maps:is_key(data, BatchResult)),
                    BatchData = maps:get(data, BatchResult),
                    ?assert(maps:is_key(columns, BatchData)),
                    ?assert(maps:is_key(rows, BatchData)),

                    %% Verify state cleared
                    {ok, ConnInfo2} = clickhouse_erl_connection:get_connection_info(Conn),
                    ?assertEqual(undefined, maps:get(active_query_state, ConnInfo2))
                end,
                lists:seq(1, 3)
            ),

            %% Cleanup
            ok = test_helpers:disconnect(Conn),
            ok
        end)}.

%% @doc Test that different callbacks don't leak between streaming queries
%% This verifies that callback state is properly isolated
different_callbacks_no_leak_test_() ->
    {setup, fun setup/0, fun cleanup/1,
        ?_test(begin
            %% Start ClickHouse connection with proper credentials
            {ok, Conn} = test_helpers:connect(),

            %% First streaming query with sum callback
            SumCallback = fun(DataBlock, Acc) ->
                Rows = maps:get(rows, DataBlock, 0),
                {ok, Acc + Rows}
            end,

            PreparedRequest1 = #{
                sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
                query_id => <<"sum-query">>,
                on_data => SumCallback,
                initial_accumulator => 0
            },
            {ok, Result1} = clickhouse_erl_connection:query(Conn, PreparedRequest1),
            ?assertEqual(5, maps:get(data, Result1)),

            %% Verify state cleared
            {ok, ConnInfo1} = clickhouse_erl_connection:get_connection_info(Conn),
            ?assertEqual(undefined, maps:get(active_query_state, ConnInfo1)),

            %% Second streaming query with list callback
            ListCallback = fun(DataBlock, Acc) ->
                Rows = maps:get(rows, DataBlock, 0),
                {ok, [Rows | Acc]}
            end,

            PreparedRequest2 = #{
                sql => <<"SELECT number FROM system.numbers LIMIT 3">>,
                query_id => <<"list-query">>,
                on_data => ListCallback,
                initial_accumulator => []
            },
            {ok, Result2} = clickhouse_erl_connection:query(Conn, PreparedRequest2),

            %% Verify result is a list (not a sum)
            ResultData = maps:get(data, Result2),
            ?assert(is_list(ResultData)),
            % Verify we got 3 rows total, regardless of chunking
            ?assertEqual(3, lists:sum(ResultData)),

            %% Verify state cleared
            {ok, ConnInfo2} = clickhouse_erl_connection:get_connection_info(Conn),
            ?assertEqual(undefined, maps:get(active_query_state, ConnInfo2)),

            %% Cleanup
            ok = test_helpers:disconnect(Conn),
            ok
        end)}.

%% @doc Test that optional callbacks don't leak between queries
%% This verifies that progress/profile callbacks are properly isolated
optional_callbacks_no_leak_test_() ->
    {setup, fun setup/0, fun cleanup/1,
        ?_test(begin
            %% Start ClickHouse connection with proper credentials
            {ok, Conn} = test_helpers:connect(),

            %% First query with progress callback
            ProgressCalled = erlang:make_ref(),
            ProgressCallback = fun(_ProgressInfo) ->
                self() ! {progress_called, ProgressCalled},
                ok
            end,

            PreparedRequest1 = #{
                sql => <<"SELECT sleep(0.1) FROM system.numbers LIMIT 1">>,
                query_id => <<"query-with-progress">>,
                on_progress => ProgressCallback
            },
            {ok, _Result1} = clickhouse_erl_connection:query(Conn, PreparedRequest1),

            %% Verify state cleared
            {ok, ConnInfo1} = clickhouse_erl_connection:get_connection_info(Conn),
            ?assertEqual(undefined, maps:get(active_query_state, ConnInfo1)),

            %% Second query without progress callback
            PreparedRequest2 = #{
                sql => <<"SELECT sleep(0.1) FROM system.numbers LIMIT 1">>,
                query_id => <<"query-without-progress">>
            },
            {ok, _Result2} = clickhouse_erl_connection:query(Conn, PreparedRequest2),

            %% Verify state cleared
            {ok, ConnInfo2} = clickhouse_erl_connection:get_connection_info(Conn),
            ?assertEqual(undefined, maps:get(active_query_state, ConnInfo2)),

            %% Cleanup
            ok = test_helpers:disconnect(Conn),
            ok
        end)}.
