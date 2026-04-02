-module(clickhouse_erl_connection_streaming_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([
    % Integration tests that require ClickHouse connection
    query_with_invalid_callback_rejected/1,
    query_with_valid_callback_accepted/1,
    query_without_callbacks_works/1,
    default_undefined_accumulator/1,
    empty_result_batch_mode/1,
    empty_result_streaming_mode/1,
    empty_result_insert_with_callback/1
]).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    % Only integration tests that require ClickHouse connection
    % Unit tests for callback validation are in clickhouse_erl_connection_callback_tests
    [
        query_with_invalid_callback_rejected,
        query_with_valid_callback_accepted,
        query_without_callbacks_works,
        default_undefined_accumulator,
        empty_result_batch_mode,
        empty_result_streaming_mode,
        empty_result_insert_with_callback
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Integration tests with connection
query_with_invalid_callback_rejected(_Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-invalid-callback">>,
        on_data => fun(_DataBlock) -> {ok, []} end
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    {error, {invalid_callback_arity, 2, 1}} = Result,

    clickhouse_erl_connection:disconnect(Conn),
    ok.

query_with_valid_callback_accepted(_Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-valid-callback">>,
        on_data => fun(_DataBlock, Acc) -> {ok, [_DataBlock | Acc]} end,
        initial_accumulator => []
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    {ok, _} = Result,

    clickhouse_erl_connection:disconnect(Conn),
    ok.

query_without_callbacks_works(_Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-no-callbacks">>
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    {ok, _} = Result,

    clickhouse_erl_connection:disconnect(Conn),
    ok.

%% Initial accumulator tests
default_undefined_accumulator(_Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    TestPid = self(),

    PreparedRequest = #{
        sql => <<"SELECT number FROM system.numbers LIMIT 3">>,
        query_id => <<"test-default-accumulator">>,
        on_data => fun(DataBlock, Acc) ->
            TestPid ! {accumulator, Acc},
            {ok, [DataBlock | Acc]}
        end
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    {ok, _} = Result,

    receive
        {accumulator, FirstAcc} ->
            undefined = FirstAcc
    after 1000 ->
        ct:fail("Did not receive accumulator value from callback")
    end,

    clickhouse_erl_connection:disconnect(Conn),
    ok.

%% Empty result edge case tests
empty_result_batch_mode(_Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    PreparedRequest = #{
        sql => <<"CREATE TABLE IF NOT EXISTS test_empty_result (id UInt32) ENGINE = Memory">>,
        query_id => <<"test-empty-batch">>
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    {ok, #{data := #{columns := [], rows := []}}} = Result,

    DropRequest = #{
        sql => <<"DROP TABLE IF EXISTS test_empty_result">>,
        query_id => <<"test-empty-batch-cleanup">>
    },
    clickhouse_erl_connection:query(Conn, DropRequest),
    clickhouse_erl_connection:disconnect(Conn),
    ok.

empty_result_streaming_mode(_Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    TestPid = self(),
    CallbackInvoked = make_ref(),

    PreparedRequest = #{
        sql => <<"CREATE TABLE IF NOT EXISTS test_empty_streaming (id UInt32) ENGINE = Memory">>,
        query_id => <<"test-empty-streaming">>,
        on_data => fun
            ('end', Acc) ->
                {ok, Acc};
            (DataBlock, Acc) ->
                TestPid ! {callback_invoked, CallbackInvoked, DataBlock},
                {ok, [DataBlock | Acc]}
        end,
        initial_accumulator => []
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    {ok, #{data := []}} = Result,

    receive
        {callback_invoked, CallbackInvoked, _} ->
            ct:fail("Callback should not be invoked for queries with no data blocks")
    after 100 ->
        ok
    end,

    DropRequest = #{
        sql => <<"DROP TABLE IF EXISTS test_empty_streaming">>,
        query_id => <<"test-empty-streaming-cleanup">>
    },
    clickhouse_erl_connection:query(Conn, DropRequest),
    clickhouse_erl_connection:disconnect(Conn),
    ok.

empty_result_insert_with_callback(_Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Conn} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),

    CreateRequest = #{
        sql =>
            <<"CREATE TABLE IF NOT EXISTS test_insert_callback (id UInt32, value String) ENGINE = Memory">>,
        query_id => <<"test-insert-callback-create">>
    },
    {ok, _} = clickhouse_erl_connection:query(Conn, CreateRequest),

    TestPid = self(),
    CallbackInvoked = make_ref(),

    PreparedRequest = #{
        sql => <<"INSERT INTO test_insert_callback VALUES (1, 'test')">>,
        query_id => <<"test-insert-callback">>,
        on_data => fun
            ('end', Acc) ->
                {ok, Acc};
            (DataBlock, Acc) ->
                TestPid ! {callback_invoked, CallbackInvoked, DataBlock},
                {ok, [DataBlock | Acc]}
        end,
        initial_accumulator => my_custom_accumulator
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),
    {ok, #{data := my_custom_accumulator}} = Result,

    receive
        {callback_invoked, CallbackInvoked, _} ->
            ct:fail("Callback should not be invoked for INSERT queries")
    after 100 ->
        ok
    end,

    DropRequest = #{
        sql => <<"DROP TABLE IF EXISTS test_insert_callback">>,
        query_id => <<"test-insert-callback-cleanup">>
    },
    clickhouse_erl_connection:query(Conn, DropRequest),
    clickhouse_erl_connection:disconnect(Conn),
    ok.
