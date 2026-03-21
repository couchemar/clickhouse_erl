-module(clickhouse_erl_connection_streaming_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([
    validate_on_data_callback_correct_arity/1,
    validate_on_data_callback_incorrect_arity_1/1,
    validate_on_data_callback_incorrect_arity_3/1,
    validate_on_progress_callback_correct_arity/1,
    validate_on_progress_callback_incorrect_arity/1,
    validate_on_profile_callback_correct_arity/1,
    validate_on_profile_callback_incorrect_arity/1,
    validate_on_profile_events_callback_correct_arity/1,
    validate_on_profile_events_callback_incorrect_arity/1,
    validate_callback_not_a_function/1,
    validate_callback_undefined/1,
    validate_prepared_request_with_valid_on_data/1,
    validate_prepared_request_with_invalid_on_data/1,
    validate_prepared_request_with_valid_optional_callbacks/1,
    validate_prepared_request_with_invalid_on_progress/1,
    validate_prepared_request_without_callbacks/1,
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
    [
        validate_on_data_callback_correct_arity,
        validate_on_data_callback_incorrect_arity_1,
        validate_on_data_callback_incorrect_arity_3,
        validate_on_progress_callback_correct_arity,
        validate_on_progress_callback_incorrect_arity,
        validate_on_profile_callback_correct_arity,
        validate_on_profile_callback_incorrect_arity,
        validate_on_profile_events_callback_correct_arity,
        validate_on_profile_events_callback_incorrect_arity,
        validate_callback_not_a_function,
        validate_callback_undefined,
        validate_prepared_request_with_valid_on_data,
        validate_prepared_request_with_invalid_on_data,
        validate_prepared_request_with_valid_optional_callbacks,
        validate_prepared_request_with_invalid_on_progress,
        validate_prepared_request_without_callbacks,
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

%% Callback arity validation tests
validate_on_data_callback_correct_arity(_Config) ->
    Callback = fun(_DataBlock, _Acc) -> {ok, []} end,
    ok = clickhouse_erl_connection:validate_callback(on_data, Callback).

validate_on_data_callback_incorrect_arity_1(_Config) ->
    Callback = fun(_DataBlock) -> {ok, []} end,
    {error, {invalid_callback_arity, 2, 1}} = clickhouse_erl_connection:validate_callback(
        on_data, Callback
    ).

validate_on_data_callback_incorrect_arity_3(_Config) ->
    Callback = fun(_DataBlock, _Acc, _Extra) -> {ok, []} end,
    {error, {invalid_callback_arity, 2, 3}} = clickhouse_erl_connection:validate_callback(
        on_data, Callback
    ).

validate_on_progress_callback_correct_arity(_Config) ->
    Callback = fun(_ProgressInfo) -> ok end,
    ok = clickhouse_erl_connection:validate_callback(on_progress, Callback).

validate_on_progress_callback_incorrect_arity(_Config) ->
    Callback = fun(_ProgressInfo, _Extra) -> ok end,
    {error, {invalid_callback_arity, 1, 2}} = clickhouse_erl_connection:validate_callback(
        on_progress, Callback
    ).

validate_on_profile_callback_correct_arity(_Config) ->
    Callback = fun(_ProfileInfo) -> ok end,
    ok = clickhouse_erl_connection:validate_callback(on_profile, Callback).

validate_on_profile_callback_incorrect_arity(_Config) ->
    Callback = fun() -> ok end,
    {error, {invalid_callback_arity, 1, 0}} = clickhouse_erl_connection:validate_callback(
        on_profile, Callback
    ).

validate_on_profile_events_callback_correct_arity(_Config) ->
    Callback = fun(_ProfileEvents) -> ok end,
    ok = clickhouse_erl_connection:validate_callback(on_profile_events, Callback).

validate_on_profile_events_callback_incorrect_arity(_Config) ->
    Callback = fun(_ProfileEvents, _Extra) -> ok end,
    {error, {invalid_callback_arity, 1, 2}} = clickhouse_erl_connection:validate_callback(
        on_profile_events, Callback
    ).

validate_callback_not_a_function(_Config) ->
    NotAFunction = "not a function",
    {error, {invalid_callback_type, NotAFunction}} = clickhouse_erl_connection:validate_callback(
        on_data, NotAFunction
    ).

validate_callback_undefined(_Config) ->
    ok = clickhouse_erl_connection:validate_callback(on_data, undefined).

%% PreparedRequest validation tests
validate_prepared_request_with_valid_on_data(_Config) ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_data => fun(_DataBlock, _Acc) -> {ok, []} end,
        initial_accumulator => []
    },
    ok = clickhouse_erl_connection:validate_prepared_request(PreparedRequest).

validate_prepared_request_with_invalid_on_data(_Config) ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_data => fun(_DataBlock) -> {ok, []} end
    },
    {error, {invalid_callback_arity, 2, 1}} = clickhouse_erl_connection:validate_prepared_request(
        PreparedRequest
    ).

validate_prepared_request_with_valid_optional_callbacks(_Config) ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_progress => fun(_ProgressInfo) -> ok end,
        on_profile => fun(_ProfileInfo) -> ok end,
        on_profile_events => fun(_ProfileEvents) -> ok end
    },
    ok = clickhouse_erl_connection:validate_prepared_request(PreparedRequest).

validate_prepared_request_with_invalid_on_progress(_Config) ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>,
        on_progress => fun(_ProgressInfo, _Extra) -> ok end
    },
    {error, {invalid_callback_arity, 1, 2}} = clickhouse_erl_connection:validate_prepared_request(
        PreparedRequest
    ).

validate_prepared_request_without_callbacks(_Config) ->
    PreparedRequest = #{
        sql => <<"SELECT 1">>,
        query_id => <<"test-query">>
    },
    ok = clickhouse_erl_connection:validate_prepared_request(PreparedRequest).

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
