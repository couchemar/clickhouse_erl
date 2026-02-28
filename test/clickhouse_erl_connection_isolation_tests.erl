-module(clickhouse_erl_connection_isolation_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Connection Isolation Tests
%%% Tests for task 11.1: Verify callback isolation between connections
%%% Validates Requirements 10.2, 10.3
%%%===================================================================

%% @doc Test that blocking callback in one connection doesn't affect another connection
%% This test verifies that concurrent queries on different connections are properly isolated
concurrent_queries_with_blocking_callback_test() ->
    %% Start two separate connections
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

    %% Create a blocking callback that sleeps for 500ms
    BlockingCallback = fun(DataBlock, Acc) ->
        timer:sleep(500),
        {ok, [DataBlock | Acc]}
    end,

    %% Create a normal callback that doesn't block
    NormalCallback = fun(DataBlock, Acc) ->
        {ok, [DataBlock | Acc]}
    end,

    %% Start query on Conn1 with blocking callback in a separate process
    Parent = self(),
    Pid1 = spawn_link(fun() ->
        PreparedRequest1 = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 3">>,
            query_id => <<"test-blocking-query">>,
            on_data => BlockingCallback,
            initial_accumulator => []
        },
        Result1 = clickhouse_erl_connection:query(Conn1, PreparedRequest1),
        Parent ! {conn1_result, Result1}
    end),

    %% Wait a bit to ensure Conn1 query has started
    timer:sleep(50),

    %% Start query on Conn2 with normal callback (should complete quickly)
    Pid2 = spawn_link(fun() ->
        PreparedRequest2 = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 3">>,
            query_id => <<"test-normal-query">>,
            on_data => NormalCallback,
            initial_accumulator => []
        },
        Result2 = clickhouse_erl_connection:query(Conn2, PreparedRequest2),
        Parent ! {conn2_result, Result2}
    end),

    %% Conn2 should complete before Conn1 (since Conn1 is blocking)
    receive
        {conn2_result, Result2} ->
            ?assertMatch({ok, #{data := _}}, Result2)
    after 3000 ->
        ?assert(false)
    end,

    %% Conn1 should complete after Conn2
    receive
        {conn1_result, Result1} ->
            ?assertMatch({ok, #{data := _}}, Result1)
    after 3000 ->
        ?assert(false)
    end,

    %% Clean up processes
    unlink(Pid1),
    unlink(Pid2),

    %% Clean up connections
    clickhouse_erl_connection:disconnect(Conn1),
    clickhouse_erl_connection:disconnect(Conn2).

%% @doc Test that multiple connections can execute queries concurrently
%% without interfering with each other
multiple_concurrent_queries_test() ->
    %% Start three separate connections
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

    %% Create callbacks that track which connection they're running on
    CreateCallback = fun(ConnId) ->
        fun(DataBlock, Acc) ->
            %% Add connection ID to each data block
            BlockWithId = DataBlock#{conn_id => ConnId},
            {ok, [BlockWithId | Acc]}
        end
    end,

    Callback1 = CreateCallback(conn1),
    Callback2 = CreateCallback(conn2),
    Callback3 = CreateCallback(conn3),

    %% Execute queries concurrently on all three connections
    Parent = self(),

    Pid1 = spawn_link(fun() ->
        PreparedRequest = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
            query_id => <<"test-conn1">>,
            on_data => Callback1,
            initial_accumulator => []
        },
        Result = clickhouse_erl_connection:query(Conn1, PreparedRequest),
        Parent ! {result, conn1, Result}
    end),

    Pid2 = spawn_link(fun() ->
        PreparedRequest = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
            query_id => <<"test-conn2">>,
            on_data => Callback2,
            initial_accumulator => []
        },
        Result = clickhouse_erl_connection:query(Conn2, PreparedRequest),
        Parent ! {result, conn2, Result}
    end),

    Pid3 = spawn_link(fun() ->
        PreparedRequest = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
            query_id => <<"test-conn3">>,
            on_data => Callback3,
            initial_accumulator => []
        },
        Result = clickhouse_erl_connection:query(Conn3, PreparedRequest),
        Parent ! {result, conn3, Result}
    end),

    %% Collect all results
    Results = collect_results(3, []),

    %% Verify all queries completed successfully
    ?assertEqual(3, length(Results)),

    %% Verify each connection got its own results
    lists:foreach(
        fun({ConnId, Result}) ->
            ?assertMatch({ok, #{data := _}}, Result),
            {ok, #{data := Data}} = Result,
            %% Verify all data blocks have the correct connection ID
            ?assert(
                lists:all(
                    fun(Block) ->
                        maps:get(conn_id, Block, undefined) =:= ConnId
                    end,
                    Data
                )
            )
        end,
        Results
    ),

    %% Clean up processes
    unlink(Pid1),
    unlink(Pid2),
    unlink(Pid3),

    %% Clean up connections
    clickhouse_erl_connection:disconnect(Conn1),
    clickhouse_erl_connection:disconnect(Conn2),
    clickhouse_erl_connection:disconnect(Conn3).

%% @doc Test that callback crash in one connection doesn't affect another connection
callback_crash_isolation_test() ->
    %% Start two separate connections
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

    %% Create a crashing callback for Conn1
    CrashingCallback = fun(_DataBlock, _Acc) ->
        error(intentional_crash)
    end,

    %% Create a normal callback for Conn2
    NormalCallback = fun(DataBlock, Acc) ->
        {ok, [DataBlock | Acc]}
    end,

    %% Execute queries concurrently
    Parent = self(),

    Pid1 = spawn_link(fun() ->
        PreparedRequest1 = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
            query_id => <<"test-crash-query">>,
            on_data => CrashingCallback,
            initial_accumulator => []
        },
        Result1 = clickhouse_erl_connection:query(Conn1, PreparedRequest1),
        Parent ! {conn1_result, Result1}
    end),

    %% Wait a bit to ensure Conn1 query has started
    timer:sleep(100),

    Pid2 = spawn_link(fun() ->
        PreparedRequest2 = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
            query_id => <<"test-normal-query">>,
            on_data => NormalCallback,
            initial_accumulator => []
        },
        Result2 = clickhouse_erl_connection:query(Conn2, PreparedRequest2),
        Parent ! {conn2_result, Result2}
    end),

    %% Collect results
    Result1 =
        receive
            {conn1_result, R1} -> R1
        after 5000 ->
            timeout
        end,

    Result2 =
        receive
            {conn2_result, R2} -> R2
        after 5000 ->
            timeout
        end,

    %% Verify Conn1 got callback crash error
    ?assertMatch({error, {callback_failed, {callback_crashed, _}}}, Result1),

    %% Verify Conn2 completed successfully despite Conn1 crash
    ?assertMatch({ok, #{data := _}}, Result2),

    %% Clean up processes
    unlink(Pid1),
    unlink(Pid2),

    %% Clean up connections
    clickhouse_erl_connection:disconnect(Conn1),
    clickhouse_erl_connection:disconnect(Conn2).

%% @doc Test that callback error in one connection doesn't affect another connection
callback_error_isolation_test() ->
    %% Start two separate connections
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

    %% Create an error-returning callback for Conn1
    ErrorCallback = fun(_DataBlock, _Acc) ->
        {error, user_stop}
    end,

    %% Create a normal callback for Conn2
    NormalCallback = fun(DataBlock, Acc) ->
        {ok, [DataBlock | Acc]}
    end,

    %% Execute queries concurrently
    Parent = self(),

    Pid1 = spawn_link(fun() ->
        PreparedRequest1 = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
            query_id => <<"test-error-query">>,
            on_data => ErrorCallback,
            initial_accumulator => []
        },
        Result1 = clickhouse_erl_connection:query(Conn1, PreparedRequest1),
        Parent ! {conn1_result, Result1}
    end),

    %% Wait a bit to ensure Conn1 query has started
    timer:sleep(100),

    Pid2 = spawn_link(fun() ->
        PreparedRequest2 = #{
            sql => <<"SELECT number FROM system.numbers LIMIT 5">>,
            query_id => <<"test-normal-query">>,
            on_data => NormalCallback,
            initial_accumulator => []
        },
        Result2 = clickhouse_erl_connection:query(Conn2, PreparedRequest2),
        Parent ! {conn2_result, Result2}
    end),

    %% Collect results
    Result1 =
        receive
            {conn1_result, R1} -> R1
        after 5000 ->
            timeout
        end,

    Result2 =
        receive
            {conn2_result, R2} -> R2
        after 5000 ->
            timeout
        end,

    %% Verify Conn1 got callback error
    ?assertMatch({error, {callback_failed, user_stop}}, Result1),

    %% Verify Conn2 completed successfully despite Conn1 error
    ?assertMatch({ok, #{data := _}}, Result2),

    %% Clean up processes
    unlink(Pid1),
    unlink(Pid2),

    %% Clean up connections
    clickhouse_erl_connection:disconnect(Conn1),
    clickhouse_erl_connection:disconnect(Conn2).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Collect results from multiple concurrent queries
collect_results(0, Acc) ->
    Acc;
collect_results(N, Acc) ->
    receive
        {result, ConnId, Result} ->
            collect_results(N - 1, [{ConnId, Result} | Acc])
    after 10000 ->
        Acc
    end.
