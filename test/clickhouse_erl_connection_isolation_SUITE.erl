-module(clickhouse_erl_connection_isolation_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([
    concurrent_queries_with_blocking_callback/1,
    multiple_concurrent_queries/1,
    callback_crash_isolation/1,
    callback_error_isolation/1
]).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [
        concurrent_queries_with_blocking_callback,
        multiple_concurrent_queries,
        callback_crash_isolation,
        callback_error_isolation
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Test that blocking callback in one connection doesn't affect another connection
concurrent_queries_with_blocking_callback(_Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn1} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),
    {ok, Conn2} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    BlockingCallback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ('end', Acc) ->
            {ok, Acc};
        ({data, _Event}, Acc) ->
            timer:sleep(500),
            {ok, Acc + 1}
    end,

    NormalCallback = fun
        (block_end, Acc) -> {ok, Acc};
        ('end', Acc) -> {ok, Acc};
        ({data, _Event}, Acc) -> {ok, Acc + 1}
    end,

    Parent = self(),
    Pid1 = spawn_link(fun() ->
        PreparedRequest1 = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 3">>,
            query_id => <<"test-blocking-query">>,
            on_data => BlockingCallback,
            initial_accumulator => 0
        },
        Result1 = clickhouse_erl_connection:query(Conn1, PreparedRequest1),
        Parent ! {conn1_result, Result1}
    end),

    timer:sleep(50),

    Pid2 = spawn_link(fun() ->
        PreparedRequest2 = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 3">>,
            query_id => <<"test-normal-query">>,
            on_data => NormalCallback,
            initial_accumulator => 0
        },
        Result2 = clickhouse_erl_connection:query(Conn2, PreparedRequest2),
        Parent ! {conn2_result, Result2}
    end),

    receive
        {conn2_result, Result2} ->
            {ok, #{data := _}} = Result2
    after 3000 ->
        ct:fail("Conn2 timeout")
    end,

    receive
        {conn1_result, Result1} ->
            {ok, #{data := _}} = Result1
    after 3000 ->
        ct:fail("Conn1 timeout")
    end,

    unlink(Pid1),
    unlink(Pid2),

    clickhouse_erl_connection:disconnect(Conn1),
    clickhouse_erl_connection:disconnect(Conn2),
    ok.

%% Test that multiple connections can execute queries concurrently
multiple_concurrent_queries(_Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn1} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),
    {ok, Conn2} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),
    {ok, Conn3} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    CountCallback = fun
        (block_end, Acc) -> {ok, Acc};
        ('end', Acc) -> {ok, Acc};
        ({data, _}, Acc) -> {ok, Acc + 1}
    end,

    Parent = self(),

    Pid1 = spawn_link(fun() ->
        PreparedRequest = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
            query_id => <<"test-conn1">>,
            on_data => CountCallback,
            initial_accumulator => 0
        },
        Result = clickhouse_erl_connection:query(Conn1, PreparedRequest),
        Parent ! {result, conn1, Result}
    end),

    Pid2 = spawn_link(fun() ->
        PreparedRequest = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
            query_id => <<"test-conn2">>,
            on_data => CountCallback,
            initial_accumulator => 0
        },
        Result = clickhouse_erl_connection:query(Conn2, PreparedRequest),
        Parent ! {result, conn2, Result}
    end),

    Pid3 = spawn_link(fun() ->
        PreparedRequest = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
            query_id => <<"test-conn3">>,
            on_data => CountCallback,
            initial_accumulator => 0
        },
        Result = clickhouse_erl_connection:query(Conn3, PreparedRequest),
        Parent ! {result, conn3, Result}
    end),

    Results = collect_results(3, []),

    3 = length(Results),

    lists:foreach(
        fun({_ConnId, Result}) ->
            {ok, #{data := 10}} = Result
        end,
        Results
    ),

    unlink(Pid1),
    unlink(Pid2),
    unlink(Pid3),

    clickhouse_erl_connection:disconnect(Conn1),
    clickhouse_erl_connection:disconnect(Conn2),
    clickhouse_erl_connection:disconnect(Conn3),
    ok.

%% Test that callback crash in one connection doesn't affect another connection
callback_crash_isolation(_Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn1} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),
    {ok, Conn2} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    CrashingCallback = fun(_Event, _Acc) ->
        error(intentional_crash)
    end,

    NormalCallback = fun
        (block_end, Acc) -> {ok, Acc};
        ('end', Acc) -> {ok, Acc};
        ({data, _}, Acc) -> {ok, Acc + 1}
    end,

    Parent = self(),

    Pid1 = spawn_link(fun() ->
        PreparedRequest1 = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
            query_id => <<"test-crash-query">>,
            on_data => CrashingCallback,
            initial_accumulator => 0
        },
        Result1 = clickhouse_erl_connection:query(Conn1, PreparedRequest1),
        Parent ! {conn1_result, Result1}
    end),

    timer:sleep(100),

    Pid2 = spawn_link(fun() ->
        PreparedRequest2 = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
            query_id => <<"test-normal-query">>,
            on_data => NormalCallback,
            initial_accumulator => 0
        },
        Result2 = clickhouse_erl_connection:query(Conn2, PreparedRequest2),
        Parent ! {conn2_result, Result2}
    end),

    Result1 =
        receive
            {conn1_result, R1} -> R1
        after 5000 -> timeout
        end,

    Result2 =
        receive
            {conn2_result, R2} -> R2
        after 5000 -> timeout
        end,

    {error, {callback_failed, {callback_crashed, _}}} = Result1,
    {ok, #{data := _}} = Result2,

    unlink(Pid1),
    unlink(Pid2),

    clickhouse_erl_connection:disconnect(Conn1),
    clickhouse_erl_connection:disconnect(Conn2),
    ok.

%% Test that callback error in one connection doesn't affect another connection
callback_error_isolation(_Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn1} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),
    {ok, Conn2} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    ErrorCallback = fun(_Event, _Acc) ->
        {error, user_stop}
    end,

    NormalCallback = fun
        (block_end, Acc) -> {ok, Acc};
        ('end', Acc) -> {ok, Acc};
        ({data, _}, Acc) -> {ok, Acc + 1}
    end,

    Parent = self(),

    Pid1 = spawn_link(fun() ->
        PreparedRequest1 = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
            query_id => <<"test-error-query">>,
            on_data => ErrorCallback,
            initial_accumulator => 0
        },
        Result1 = clickhouse_erl_connection:query(Conn1, PreparedRequest1),
        Parent ! {conn1_result, Result1}
    end),

    timer:sleep(100),

    Pid2 = spawn_link(fun() ->
        PreparedRequest2 = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
            query_id => <<"test-normal-query">>,
            on_data => NormalCallback,
            initial_accumulator => 0
        },
        Result2 = clickhouse_erl_connection:query(Conn2, PreparedRequest2),
        Parent ! {conn2_result, Result2}
    end),

    Result1 =
        receive
            {conn1_result, R1} -> R1
        after 5000 -> timeout
        end,

    Result2 =
        receive
            {conn2_result, R2} -> R2
        after 5000 -> timeout
        end,

    {error, {callback_failed, user_stop}} = Result1,
    {ok, #{data := _}} = Result2,

    unlink(Pid1),
    unlink(Pid2),

    clickhouse_erl_connection:disconnect(Conn1),
    clickhouse_erl_connection:disconnect(Conn2),
    ok.

collect_results(0, Acc) ->
    Acc;
collect_results(N, Acc) ->
    receive
        {result, ConnId, Result} ->
            collect_results(N - 1, [{ConnId, Result} | Acc])
    after 10000 ->
        Acc
    end.
