-module(clickhouse_erl_connection_state_cleanup_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([
    active_query_state_cleared_after_query/1,
    streaming_to_batch_no_state_leak/1,
    batch_to_streaming_no_state_leak/1,
    multiple_mode_alternations/1,
    different_callbacks_no_leak/1,
    optional_callbacks_no_leak/1
]).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [
        active_query_state_cleared_after_query,
        streaming_to_batch_no_state_leak,
        batch_to_streaming_no_state_leak,
        multiple_mode_alternations,
        different_callbacks_no_leak,
        optional_callbacks_no_leak
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Test that active_query_state is cleared after a successful query
active_query_state_cleared_after_query(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    PreparedRequest1 = #{
        sql => <<"SELECT 1">>,
        query_id => <<"query-1">>
    },
    {ok, _Result1} = clickhouse_erl_connection:query(Conn, PreparedRequest1),

    {ok, ConnInfo} = clickhouse_erl_connection:get_connection_info(Conn),
    undefined = maps:get(active_query_state, ConnInfo),

    PreparedRequest2 = #{
        sql => <<"SELECT 2">>,
        query_id => <<"query-2">>
    },
    {ok, _Result2} = clickhouse_erl_connection:query(Conn, PreparedRequest2),

    {ok, ConnInfo2} = clickhouse_erl_connection:get_connection_info(Conn),
    undefined = maps:get(active_query_state, ConnInfo2),

    test_helpers:disconnect(Conn),
    ok.

%% Test that streaming query state doesn't leak to batch query
streaming_to_batch_no_state_leak(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    StreamingCallback = fun
        ('end', Acc) -> {ok, Acc};
        ({data, _}, Acc) -> {ok, Acc + 1}
    end,

    PreparedRequest1 = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
        query_id => <<"streaming-query">>,
        on_data => StreamingCallback,
        initial_accumulator => 0
    },
    {ok, StreamingResult} = clickhouse_erl_connection:query(Conn, PreparedRequest1),

    true = maps:is_key(data, StreamingResult),
    5 = maps:get(data, StreamingResult),

    {ok, ConnInfo1} = clickhouse_erl_connection:get_connection_info(Conn),
    undefined = maps:get(active_query_state, ConnInfo1),

    PreparedRequest2 = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 3">>,
        query_id => <<"batch-query">>
    },
    {ok, BatchResult} = clickhouse_erl_connection:query(Conn, PreparedRequest2),

    true = maps:is_key(data, BatchResult),
    BatchData = maps:get(data, BatchResult),
    true = maps:is_key(columns, BatchData),
    true = maps:is_key(rows, BatchData),
    false = is_integer(BatchData),

    {ok, ConnInfo2} = clickhouse_erl_connection:get_connection_info(Conn),
    undefined = maps:get(active_query_state, ConnInfo2),

    test_helpers:disconnect(Conn),
    ok.

%% Test that batch query state doesn't leak to streaming query
batch_to_streaming_no_state_leak(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    PreparedRequest1 = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 3">>,
        query_id => <<"batch-query-first">>
    },
    {ok, BatchResult} = clickhouse_erl_connection:query(Conn, PreparedRequest1),

    true = maps:is_key(data, BatchResult),
    BatchData = maps:get(data, BatchResult),
    true = maps:is_key(columns, BatchData),
    true = maps:is_key(rows, BatchData),

    {ok, ConnInfo1} = clickhouse_erl_connection:get_connection_info(Conn),
    undefined = maps:get(active_query_state, ConnInfo1),

    StreamingCallback = fun
        ('end', Acc) -> {ok, Acc};
        ({data, _}, Acc) -> {ok, Acc + 1}
    end,

    PreparedRequest2 = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
        query_id => <<"streaming-query-second">>,
        on_data => StreamingCallback,
        initial_accumulator => 0
    },
    {ok, StreamingResult} = clickhouse_erl_connection:query(Conn, PreparedRequest2),

    true = maps:is_key(data, StreamingResult),
    5 = maps:get(data, StreamingResult),

    {ok, ConnInfo2} = clickhouse_erl_connection:get_connection_info(Conn),
    undefined = maps:get(active_query_state, ConnInfo2),

    test_helpers:disconnect(Conn),
    ok.

%% Test multiple alternations between streaming and batch modes
multiple_mode_alternations(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    StreamingCallback = fun
        ('end', Acc) -> {ok, Acc};
        ({data, _}, Acc) -> {ok, Acc + 1}
    end,

    lists:foreach(
        fun(N) ->
            StreamingRequest = #{
                sql => <<"SELECT number FROM system.numbers LIMIT 2">>,
                query_id => list_to_binary("streaming-" ++ integer_to_list(N)),
                on_data => StreamingCallback,
                initial_accumulator => 0
            },
            {ok, StreamingResult} = clickhouse_erl_connection:query(Conn, StreamingRequest),
            true = maps:is_key(data, StreamingResult),
            2 = maps:get(data, StreamingResult),

            {ok, ConnInfo1} = clickhouse_erl_connection:get_connection_info(Conn),
            undefined = maps:get(active_query_state, ConnInfo1),

            BatchRequest = #{
                sql => <<"SELECT number FROM system.numbers LIMIT 2">>,
                query_id => list_to_binary("batch-" ++ integer_to_list(N))
            },
            {ok, BatchResult} = clickhouse_erl_connection:query(Conn, BatchRequest),
            true = maps:is_key(data, BatchResult),
            BatchData = maps:get(data, BatchResult),
            true = maps:is_key(columns, BatchData),
            true = maps:is_key(rows, BatchData),

            {ok, ConnInfo2} = clickhouse_erl_connection:get_connection_info(Conn),
            undefined = maps:get(active_query_state, ConnInfo2)
        end,
        lists:seq(1, 3)
    ),

    test_helpers:disconnect(Conn),
    ok.

%% Test that different callbacks don't leak between streaming queries
different_callbacks_no_leak(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    CountCallback = fun
        ('end', Acc) -> {ok, Acc};
        ({data, _}, Acc) -> {ok, Acc + 1}
    end,

    PreparedRequest1 = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
        query_id => <<"sum-query">>,
        on_data => CountCallback,
        initial_accumulator => 0
    },
    {ok, Result1} = clickhouse_erl_connection:query(Conn, PreparedRequest1),
    5 = maps:get(data, Result1),

    {ok, ConnInfo1} = clickhouse_erl_connection:get_connection_info(Conn),
    undefined = maps:get(active_query_state, ConnInfo1),

    ListCallback = fun
        ('end', Acc) -> {ok, Acc};
        ({data, #{value := V}}, Acc) -> {ok, [V | Acc]}
    end,

    PreparedRequest2 = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 3">>,
        query_id => <<"list-query">>,
        on_data => ListCallback,
        initial_accumulator => []
    },
    {ok, Result2} = clickhouse_erl_connection:query(Conn, PreparedRequest2),

    ResultData = maps:get(data, Result2),
    true = is_list(ResultData),
    3 = length(ResultData),

    {ok, ConnInfo2} = clickhouse_erl_connection:get_connection_info(Conn),
    undefined = maps:get(active_query_state, ConnInfo2),

    test_helpers:disconnect(Conn),
    ok.

%% Test that optional callbacks don't leak between queries
optional_callbacks_no_leak(_Config) ->
    {ok, Conn} = test_helpers:connect(),

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

    {ok, ConnInfo1} = clickhouse_erl_connection:get_connection_info(Conn),
    undefined = maps:get(active_query_state, ConnInfo1),

    PreparedRequest2 = #{
        sql => <<"SELECT sleep(0.1) FROM system.numbers LIMIT 1">>,
        query_id => <<"query-without-progress">>
    },
    {ok, _Result2} = clickhouse_erl_connection:query(Conn, PreparedRequest2),

    {ok, ConnInfo2} = clickhouse_erl_connection:get_connection_info(Conn),
    undefined = maps:get(active_query_state, ConnInfo2),

    test_helpers:disconnect(Conn),
    ok.
