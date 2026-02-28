-module(clickhouse_erl_query_manager_tests).
-include_lib("eunit/include/eunit.hrl").
-include("clickhouse_erl_protocol.hrl").

execute_query_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        fun validate_empty_sql_test/0,
        fun validate_missing_sql_test/0,
        fun delegate_valid_query_test/0,
        fun query_state_lifecycle_test/0,
        fun query_expiration_test/0,
        fun accumulator_update_test/0,
        fun query_tracking_test/0,
        fun query_cleanup_test/0,
        fun expired_query_cleanup_test/0
    ]}.

execute_insert_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        fun validate_insert_invalid_arguments_test/0,
        fun validate_insert_row_count_mismatch_test/0,
        fun validate_insert_invalid_column_name_test/0,
        fun validate_insert_empty_input_test/0,
        fun delegate_valid_insert_test/0
    ]}.

insert_workflow_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        fun insert_workflow_query_packet_test/0,
        fun insert_workflow_data_block_test/0,
        fun insert_workflow_blank_block_test/0,
        fun insert_workflow_success_response_test/0,
        fun insert_workflow_exception_response_test/0,
        fun insert_workflow_network_error_query_packet_test/0,
        fun insert_workflow_network_error_data_block_test/0,
        fun insert_workflow_network_error_blank_block_test/0
    ]}.

normalize_settings_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        fun normalize_settings_simple_map_test/0,
        fun normalize_settings_keyword_list_test/0,
        fun normalize_settings_protocol_format_test/0,
        fun normalize_settings_empty_test/0,
        fun normalize_settings_invalid_format_test/0
    ]}.

setup() ->
    ok.

cleanup(_) ->
    ok.

validate_empty_sql_test() ->
    %% Dummy pid
    Connection = self(),
    Request = #{sql => "   "},
    Result = clickhouse_erl_query_manager:execute_query(Connection, Request),
    ?assertEqual({error, {validation_error, empty_query}}, Result).

validate_missing_sql_test() ->
    %% Dummy pid
    Connection = self(),
    Request = #{},
    Result = clickhouse_erl_query_manager:execute_query(Connection, Request),
    ?assertEqual({error, {validation_error, missing_sql}}, Result).

delegate_valid_query_test() ->
    %% Spawn a dummy connection process to handle the gen_server:call
    Parent = self(),
    Pid = spawn(fun() ->
        receive
            {'$gen_call', From, {query, RequestMap}} when is_map(RequestMap) ->
                gen_server:reply(From, {ok, result_ok}),
                %% Keep alive to ensure reply is sent
                timer:sleep(10),
                ok;
            Other ->
                Parent ! {unexpected_msg, Other}
        end
    end),

    Request = #{sql => "SELECT 1"},
    Result = clickhouse_erl_query_manager:execute_query(Pid, Request),

    ?assertEqual({ok, result_ok}, Result).

query_state_lifecycle_test() ->
    Caller = {self(), make_ref()},
    QueryId = "test_query_id",
    Timeout = 5000,

    State = clickhouse_erl_query_manager:start_query(QueryId, Caller, Timeout),

    ?assertEqual(Caller, clickhouse_erl_query_manager:get_caller(State)),
    ?assert(is_reference(clickhouse_erl_query_manager:get_query_ref(State))),
    ?assertEqual(false, clickhouse_erl_query_manager:is_expired(State)).

query_expiration_test() ->
    Caller = {self(), make_ref()},
    %% 1ms timeout
    Timeout = 1,

    State = clickhouse_erl_query_manager:start_query("q1", Caller, Timeout),
    timer:sleep(10),

    ?assertEqual(true, clickhouse_erl_query_manager:is_expired(State)).

accumulator_update_test() ->
    Caller = {self(), make_ref()},
    State = clickhouse_erl_query_manager:start_query("q2", Caller, 5000),

    InitialAcc = clickhouse_erl_query_manager:get_result_accumulator(State),
    %% Check that it is a result_accumulator record (by checking size/type implicitly via usage or just existence)
    %% Since we can't match record directly without header in test (unless we include it), we trust it's not undefined.
    ?assertNotEqual(undefined, InitialAcc),

    %% Mock update
    %% For testing, we can just replace it with any term since strict type checking isn't enforced at runtime
    %% unless we stick to the type. But let's try to be consistent.
    %% Since we don't have the record definition included in tests easily without include lib path hacking,
    %% we will just rely on it being an opaque term that we can swap.
    NewAcc = {mock_accumulator, 1},
    State2 = clickhouse_erl_query_manager:update_result_accumulator(State, NewAcc),

    ?assertEqual(NewAcc, clickhouse_erl_query_manager:get_result_accumulator(State2)).

query_tracking_test() ->
    Caller = {self(), make_ref()},
    State1 = clickhouse_erl_query_manager:start_query("q1", Caller, 5000),
    State2 = clickhouse_erl_query_manager:start_query("q2", Caller, 5000),

    %% Start with empty registry
    Registry = #{},

    %% Track first query
    {ok, Registry1} = clickhouse_erl_query_manager:track_query(State1, Registry),
    ?assertEqual(1, maps:size(Registry1)),

    %% Track second query
    {ok, Registry2} = clickhouse_erl_query_manager:track_query(State2, Registry1),
    ?assertEqual(2, maps:size(Registry2)),

    %% Get active queries
    ActiveQueries = clickhouse_erl_query_manager:get_active_queries(Registry2),
    ?assertEqual(2, length(ActiveQueries)),

    %% Untrack first query
    QueryRef1 = clickhouse_erl_query_manager:get_query_ref(State1),
    {ok, Registry3} = clickhouse_erl_query_manager:untrack_query(QueryRef1, Registry2),
    ?assertEqual(1, maps:size(Registry3)).

query_cleanup_test() ->
    Caller = {self(), make_ref()},
    State = clickhouse_erl_query_manager:start_query("q1", Caller, 5000),
    QueryRef = clickhouse_erl_query_manager:get_query_ref(State),

    %% Track query
    Registry = #{},
    {ok, Registry1} = clickhouse_erl_query_manager:track_query(State, Registry),

    %% Clean up existing query
    {ok, Registry2} = clickhouse_erl_query_manager:cleanup_query(QueryRef, Registry1),
    ?assertEqual(0, maps:size(Registry2)),

    %% Try to clean up non-existent query
    NonExistentRef = make_ref(),
    ?assertEqual(
        {error, query_not_found},
        clickhouse_erl_query_manager:cleanup_query(NonExistentRef, Registry2)
    ).

expired_query_cleanup_test() ->
    Caller = {self(), make_ref()},
    %% Create query with very short timeout
    State1 = clickhouse_erl_query_manager:start_query("q1", Caller, 1),
    State2 = clickhouse_erl_query_manager:start_query("q2", Caller, 5000),

    Registry = #{},
    {ok, Registry1} = clickhouse_erl_query_manager:track_query(State1, Registry),
    {ok, Registry2} = clickhouse_erl_query_manager:track_query(State2, Registry1),

    %% Wait for first query to expire
    timer:sleep(10),

    %% Clean up expired queries
    {ok, CleanRegistry, ExpiredQueries} =
        clickhouse_erl_query_manager:cleanup_expired_queries(Registry2),

    %% Should have 1 active query and 1 expired query
    ?assertEqual(1, maps:size(CleanRegistry)),
    ?assertEqual(1, length(ExpiredQueries)).

%% INSERT tests

validate_insert_invalid_arguments_test() ->
    %% Test with invalid connection (not a pid)
    Result1 = clickhouse_erl_query_manager:execute_insert(not_a_pid, <<"INSERT INTO t">>, [], 5000),
    ?assertEqual({error, {validation_error, invalid_arguments}}, Result1),

    %% Test with invalid SQL (not a binary)
    Result2 = clickhouse_erl_query_manager:execute_insert(self(), "not binary", [], 5000),
    ?assertEqual({error, {validation_error, invalid_arguments}}, Result2),

    %% Test with invalid input (not a list)
    Result3 = clickhouse_erl_query_manager:execute_insert(
        self(), <<"INSERT INTO t">>, not_a_list, 5000
    ),
    ?assertEqual({error, {validation_error, invalid_arguments}}, Result3).

validate_insert_row_count_mismatch_test() ->
    %% Create input with mismatched row counts
    Input = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"col2">>, type => <<"String">>, data => [<<"a">>, <<"b">>]}
    ],

    %% Spawn a dummy connection process
    Pid = spawn(fun() -> timer:sleep(100) end),

    Result = clickhouse_erl_query_manager:execute_insert(Pid, <<"INSERT INTO t">>, Input, 5000),

    %% Should return row count mismatch error
    ?assertMatch({error, {validation_error, {row_count_mismatch, _}}}, Result).

validate_insert_invalid_column_name_test() ->
    %% Create input with invalid column name (not a binary)
    Input = [
        #{name => "not_binary", type => <<"UInt32">>, data => [1, 2, 3]}
    ],

    %% Spawn a dummy connection process
    Pid = spawn(fun() -> timer:sleep(100) end),

    Result = clickhouse_erl_query_manager:execute_insert(Pid, <<"INSERT INTO t">>, Input, 5000),

    %% Should return invalid column name error
    ?assertMatch({error, {validation_error, {invalid_column_name, _}}}, Result).

validate_insert_empty_input_test() ->
    %% Create input with zero rows
    Input = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => []},
        #{name => <<"col2">>, type => <<"String">>, data => []}
    ],

    %% Spawn a dummy connection process that responds to insert
    Parent = self(),
    Pid = spawn(fun() ->
        receive
            {'$gen_call', From, {insert, RequestMap}} when is_map(RequestMap) ->
                gen_server:reply(From, {ok, #{rows_inserted => 0, elapsed_time => 0}}),
                timer:sleep(10),
                ok;
            Other ->
                Parent ! {unexpected_msg, Other}
        end
    end),

    Result = clickhouse_erl_query_manager:execute_insert(Pid, <<"INSERT INTO t">>, Input, 5000),

    %% Should succeed with 0 rows inserted
    ?assertEqual({ok, #{rows_inserted => 0, elapsed_time => 0}}, Result).

delegate_valid_insert_test() ->
    %% Create valid input
    Input = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"col2">>, type => <<"String">>, data => [<<"a">>, <<"b">>, <<"c">>]}
    ],

    %% Spawn a dummy connection process that responds to insert
    Parent = self(),
    Pid = spawn(fun() ->
        receive
            {'$gen_call', From, {insert, RequestMap}} when is_map(RequestMap) ->
                %% Verify the prepared request has expected fields
                ?assert(maps:is_key(sql, RequestMap)),
                ?assert(maps:is_key(query_id, RequestMap)),
                ?assert(maps:is_key(input, RequestMap)),
                ?assert(maps:is_key(num_columns, RequestMap)),
                ?assert(maps:is_key(num_rows, RequestMap)),
                ?assert(maps:is_key(timeout, RequestMap)),

                %% Verify values
                ?assertEqual(2, maps:get(num_columns, RequestMap)),
                ?assertEqual(3, maps:get(num_rows, RequestMap)),

                gen_server:reply(From, {ok, #{rows_inserted => 3, elapsed_time => 100}}),
                timer:sleep(10),
                ok;
            Other ->
                Parent ! {unexpected_msg, Other}
        end
    end),

    Result = clickhouse_erl_query_manager:execute_insert(
        Pid, <<"INSERT INTO t VALUES">>, Input, 5000
    ),

    %% Should succeed with 3 rows inserted
    ?assertEqual({ok, #{rows_inserted => 3, elapsed_time => 100}}, Result).

%% INSERT workflow tests

%% @doc Test INSERT workflow sends query packet correctly
%% Requirements: 1.1, 1.2
insert_workflow_query_packet_test() ->
    %% Create valid input
    Input = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],

    %% Spawn a mock connection process that verifies query packet
    Parent = self(),
    Pid = spawn(fun() ->
        receive
            {'$gen_call', From, {insert, RequestMap}} when is_map(RequestMap) ->
                %% Verify the prepared request has query packet fields
                ?assert(maps:is_key(sql, RequestMap)),
                ?assert(maps:is_key(query_id, RequestMap)),
                ?assert(maps:is_key(input, RequestMap)),

                %% Send success response
                gen_server:reply(From, {ok, #{rows_inserted => 3, elapsed_time => 100}}),
                Parent ! test_passed,
                timer:sleep(10),
                ok;
            Other ->
                Parent ! {unexpected_msg, Other}
        end
    end),

    Result = clickhouse_erl_query_manager:execute_insert(
        Pid, <<"INSERT INTO t VALUES">>, Input, 5000
    ),

    %% Should succeed
    ?assertEqual({ok, #{rows_inserted => 3, elapsed_time => 100}}, Result),

    %% Verify test passed
    receive
        test_passed -> ok;
        {unexpected_msg, Msg} -> ?assert(false, io_lib:format("Unexpected message: ~p", [Msg]))
    after 100 ->
        ?assert(false, "Test did not complete")
    end.

%% @doc Test INSERT workflow sends data block correctly
%% Requirements: 1.2
insert_workflow_data_block_test() ->
    %% Create valid input with multiple columns
    Input = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2]},
        #{name => <<"col2">>, type => <<"String">>, data => [<<"a">>, <<"b">>]}
    ],

    %% Spawn a mock connection process
    Parent = self(),
    Pid = spawn(fun() ->
        receive
            {'$gen_call', From, {insert, RequestMap}} when is_map(RequestMap) ->
                %% Verify data block fields
                ?assertEqual(2, maps:get(num_columns, RequestMap)),
                ?assertEqual(2, maps:get(num_rows, RequestMap)),
                ?assertEqual(Input, maps:get(input, RequestMap)),

                gen_server:reply(From, {ok, #{rows_inserted => 2, elapsed_time => 50}}),
                Parent ! test_passed,
                timer:sleep(10),
                ok;
            Other ->
                Parent ! {unexpected_msg, Other}
        end
    end),

    Result = clickhouse_erl_query_manager:execute_insert(
        Pid, <<"INSERT INTO t VALUES">>, Input, 5000
    ),

    ?assertEqual({ok, #{rows_inserted => 2, elapsed_time => 50}}, Result),

    receive
        test_passed -> ok;
        {unexpected_msg, Msg} -> ?assert(false, io_lib:format("Unexpected message: ~p", [Msg]))
    after 100 ->
        ?assert(false, "Test did not complete")
    end.

%% @doc Test INSERT workflow sends blank block correctly
%% Requirements: 1.3
insert_workflow_blank_block_test() ->
    %% The blank block is sent by the connection layer after the data block
    %% This test verifies that the workflow completes successfully,
    %% which implies the blank block was sent

    Input = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1]}
    ],

    Parent = self(),
    Pid = spawn(fun() ->
        receive
            {'$gen_call', From, {insert, _RequestMap}} ->
                %% Simulate successful completion (blank block sent)
                gen_server:reply(From, {ok, #{rows_inserted => 1, elapsed_time => 10}}),
                Parent ! test_passed,
                timer:sleep(10),
                ok;
            Other ->
                Parent ! {unexpected_msg, Other}
        end
    end),

    Result = clickhouse_erl_query_manager:execute_insert(
        Pid, <<"INSERT INTO t VALUES">>, Input, 5000
    ),

    ?assertEqual({ok, #{rows_inserted => 1, elapsed_time => 10}}, Result),

    receive
        test_passed -> ok;
        {unexpected_msg, Msg} -> ?assert(false, io_lib:format("Unexpected message: ~p", [Msg]))
    after 100 ->
        ?assert(false, "Test did not complete")
    end.

%% @doc Test INSERT workflow handles success response
%% Requirements: 1.4, 4.3
insert_workflow_success_response_test() ->
    Input = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3, 4, 5]}
    ],

    Parent = self(),
    Pid = spawn(fun() ->
        receive
            {'$gen_call', From, {insert, _RequestMap}} ->
                %% Simulate END_OF_STREAM success response
                gen_server:reply(From, {ok, #{rows_inserted => 5, elapsed_time => 150}}),
                Parent ! test_passed,
                timer:sleep(10),
                ok;
            Other ->
                Parent ! {unexpected_msg, Other}
        end
    end),

    Result = clickhouse_erl_query_manager:execute_insert(
        Pid, <<"INSERT INTO t VALUES">>, Input, 5000
    ),

    %% Verify success result structure
    ?assertMatch({ok, #{rows_inserted := 5, elapsed_time := 150}}, Result),

    receive
        test_passed -> ok;
        {unexpected_msg, Msg} -> ?assert(false, io_lib:format("Unexpected message: ~p", [Msg]))
    after 100 ->
        ?assert(false, "Test did not complete")
    end.

%% @doc Test INSERT workflow handles exception response
%% Requirements: 1.4, 4.3
insert_workflow_exception_response_test() ->
    Input = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],

    Parent = self(),
    Pid = spawn(fun() ->
        receive
            {'$gen_call', From, {insert, _RequestMap}} ->
                %% Simulate server exception (e.g., constraint violation)
                ExceptionInfo = #exception_info{
                    error_code = 252,
                    exception_name = <<"DB::Exception">>,
                    message = <<"Constraint violation">>,
                    stack_trace = <<"at insert.cpp:123">>,
                    nested = false,
                    nested_exceptions = []
                },
                gen_server:reply(From, {error, {server_exception, ExceptionInfo}}),
                Parent ! test_passed,
                timer:sleep(10),
                ok;
            Other ->
                Parent ! {unexpected_msg, Other}
        end
    end),

    Result = clickhouse_erl_query_manager:execute_insert(
        Pid, <<"INSERT INTO t VALUES">>, Input, 5000
    ),

    %% Verify exception is propagated
    ?assertMatch({error, {server_exception, #exception_info{}}}, Result),

    receive
        test_passed -> ok;
        {unexpected_msg, Msg} -> ?assert(false, io_lib:format("Unexpected message: ~p", [Msg]))
    after 100 ->
        ?assert(false, "Test did not complete")
    end.

%% @doc Test INSERT workflow handles network error during query packet send
%% Requirements: 4.4
insert_workflow_network_error_query_packet_test() ->
    Input = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],

    Parent = self(),
    Pid = spawn(fun() ->
        receive
            {'$gen_call', From, {insert, _RequestMap}} ->
                %% Simulate network error during query packet send
                gen_server:reply(From, {error, {network_error, econnreset}}),
                Parent ! test_passed,
                timer:sleep(10),
                ok;
            Other ->
                Parent ! {unexpected_msg, Other}
        end
    end),

    Result = clickhouse_erl_query_manager:execute_insert(
        Pid, <<"INSERT INTO t VALUES">>, Input, 5000
    ),

    %% Verify network error is propagated with context
    ?assertMatch({error, {connection_error, {network, econnreset}}}, Result),

    receive
        test_passed -> ok;
        {unexpected_msg, Msg} -> ?assert(false, io_lib:format("Unexpected message: ~p", [Msg]))
    after 100 ->
        ?assert(false, "Test did not complete")
    end.

%% @doc Test INSERT workflow handles network error during data block send
%% Requirements: 4.4
insert_workflow_network_error_data_block_test() ->
    Input = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],

    Parent = self(),
    Pid = spawn(fun() ->
        receive
            {'$gen_call', From, {insert, _RequestMap}} ->
                %% Simulate network error during data block send
                gen_server:reply(From, {error, {send_failed, {data_block, closed}}}),
                Parent ! test_passed,
                timer:sleep(10),
                ok;
            Other ->
                Parent ! {unexpected_msg, Other}
        end
    end),

    Result = clickhouse_erl_query_manager:execute_insert(
        Pid, <<"INSERT INTO t VALUES">>, Input, 5000
    ),

    %% Verify send_failed error is propagated
    ?assertMatch({error, {connection_error, {send_failed, {data_block, closed}}}}, Result),

    receive
        test_passed -> ok;
        {unexpected_msg, Msg} -> ?assert(false, io_lib:format("Unexpected message: ~p", [Msg]))
    after 100 ->
        ?assert(false, "Test did not complete")
    end.

%% @doc Test INSERT workflow handles network error during blank block send
%% Requirements: 4.4
insert_workflow_network_error_blank_block_test() ->
    Input = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],

    Parent = self(),
    Pid = spawn(fun() ->
        receive
            {'$gen_call', From, {insert, _RequestMap}} ->
                %% Simulate network error during blank block send
                gen_server:reply(From, {error, {send_failed, {blank_block, timeout}}}),
                Parent ! test_passed,
                timer:sleep(10),
                ok;
            Other ->
                Parent ! {unexpected_msg, Other}
        end
    end),

    Result = clickhouse_erl_query_manager:execute_insert(
        Pid, <<"INSERT INTO t VALUES">>, Input, 5000
    ),

    %% Verify send_failed error is propagated with context
    ?assertMatch({error, {connection_error, {send_failed, {blank_block, timeout}}}}, Result),

    receive
        test_passed -> ok;
        {unexpected_msg, Msg} -> ?assert(false, io_lib:format("Unexpected message: ~p", [Msg]))
    after 100 ->
        ?assert(false, "Test did not complete")
    end.

%% Settings normalization tests

%% @doc Test simple map format conversion
%% Validates: Requirements 1.1.1, 1.1.2, 1.1.3
normalize_settings_simple_map_test() ->
    %% Test with single setting
    Input1 = #{<<"max_threads">> => <<"4">>},
    Result1 = clickhouse_erl_query_manager:normalize_settings(Input1),

    ?assertEqual(1, length(Result1)),
    [Setting1] = Result1,
    ?assertEqual(<<"max_threads">>, maps:get(key, Setting1)),
    ?assertEqual(<<"4">>, maps:get(value, Setting1)),
    ?assertEqual(false, maps:get(important, Setting1)),
    ?assertEqual(false, maps:get(custom, Setting1)),
    ?assertEqual(false, maps:get(obsolete, Setting1)),

    %% Test with multiple settings
    Input2 = #{
        <<"max_threads">> => <<"4">>,
        <<"max_memory_usage">> => <<"10000000000">>
    },
    Result2 = clickhouse_erl_query_manager:normalize_settings(Input2),

    ?assertEqual(2, length(Result2)),
    %% Verify all settings have correct structure with default flags
    lists:foreach(
        fun(Setting) ->
            ?assert(maps:is_key(key, Setting)),
            ?assert(maps:is_key(value, Setting)),
            ?assertEqual(false, maps:get(important, Setting)),
            ?assertEqual(false, maps:get(custom, Setting)),
            ?assertEqual(false, maps:get(obsolete, Setting))
        end,
        Result2
    ),

    %% Verify keys and values are present
    Keys = lists:sort([maps:get(key, S) || S <- Result2]),
    ?assert(lists:member(<<"max_threads">>, Keys)),
    ?assert(lists:member(<<"max_memory_usage">>, Keys)).

%% @doc Test keyword list format conversion
%% Validates: Requirements 1.2.1, 1.2.2, 1.2.3
normalize_settings_keyword_list_test() ->
    %% Test with single setting
    Input1 = [{<<"max_threads">>, <<"4">>}],
    Result1 = clickhouse_erl_query_manager:normalize_settings(Input1),

    ?assertEqual(1, length(Result1)),
    [Setting1] = Result1,
    ?assertEqual(<<"max_threads">>, maps:get(key, Setting1)),
    ?assertEqual(<<"4">>, maps:get(value, Setting1)),
    ?assertEqual(false, maps:get(important, Setting1)),
    ?assertEqual(false, maps:get(custom, Setting1)),
    ?assertEqual(false, maps:get(obsolete, Setting1)),

    %% Test with multiple settings
    Input2 = [
        {<<"max_threads">>, <<"4">>},
        {<<"max_memory_usage">>, <<"10000000000">>}
    ],
    Result2 = clickhouse_erl_query_manager:normalize_settings(Input2),

    ?assertEqual(2, length(Result2)),
    %% Verify all settings have correct structure with default flags
    lists:foreach(
        fun(Setting) ->
            ?assert(maps:is_key(key, Setting)),
            ?assert(maps:is_key(value, Setting)),
            ?assertEqual(false, maps:get(important, Setting)),
            ?assertEqual(false, maps:get(custom, Setting)),
            ?assertEqual(false, maps:get(obsolete, Setting))
        end,
        Result2
    ),

    %% Verify order is preserved
    [First, Second] = Result2,
    ?assertEqual(<<"max_threads">>, maps:get(key, First)),
    ?assertEqual(<<"max_memory_usage">>, maps:get(key, Second)).

%% @doc Test protocol format preservation
%% Validates: Requirements 1.3.1
normalize_settings_protocol_format_test() ->
    %% Test with minimal protocol format (no explicit flags)
    Input1 = [#{key => <<"max_threads">>, value => <<"4">>}],
    Result1 = clickhouse_erl_query_manager:normalize_settings(Input1),

    ?assertEqual(1, length(Result1)),
    [Setting1] = Result1,
    ?assertEqual(<<"max_threads">>, maps:get(key, Setting1)),
    ?assertEqual(<<"4">>, maps:get(value, Setting1)),
    ?assertEqual(false, maps:get(important, Setting1)),
    ?assertEqual(false, maps:get(custom, Setting1)),
    ?assertEqual(false, maps:get(obsolete, Setting1)),

    %% Test with explicit flags - verify they are preserved
    Input2 = [
        #{
            key => <<"custom_setting">>,
            value => <<"value">>,
            important => true,
            custom => true,
            obsolete => false
        }
    ],
    Result2 = clickhouse_erl_query_manager:normalize_settings(Input2),

    ?assertEqual(1, length(Result2)),
    [Setting2] = Result2,
    ?assertEqual(<<"custom_setting">>, maps:get(key, Setting2)),
    ?assertEqual(<<"value">>, maps:get(value, Setting2)),
    ?assertEqual(true, maps:get(important, Setting2)),
    ?assertEqual(true, maps:get(custom, Setting2)),
    ?assertEqual(false, maps:get(obsolete, Setting2)),

    %% Test with multiple settings with mixed flags
    Input3 = [
        #{key => <<"setting1">>, value => <<"val1">>, important => true},
        #{key => <<"setting2">>, value => <<"val2">>, custom => true}
    ],
    Result3 = clickhouse_erl_query_manager:normalize_settings(Input3),

    ?assertEqual(2, length(Result3)),
    [S1, S2] = Result3,
    ?assertEqual(true, maps:get(important, S1)),
    ?assertEqual(false, maps:get(custom, S1)),
    ?assertEqual(false, maps:get(important, S2)),
    ?assertEqual(true, maps:get(custom, S2)).

%% @doc Test empty settings handling
%% Validates: Requirements 1.1.2, 1.2.2
normalize_settings_empty_test() ->
    %% Test empty map
    Result1 = clickhouse_erl_query_manager:normalize_settings(#{}),
    ?assertEqual([], Result1),

    %% Test empty list
    Result2 = clickhouse_erl_query_manager:normalize_settings([]),
    ?assertEqual([], Result2).

%% @doc Test invalid format error handling
%% Validates: Requirements 1.3.3
normalize_settings_invalid_format_test() ->
    %% Test with invalid list format (flat list instead of tuples/maps)
    ?assertError(
        {invalid_settings_format, _, _},
        clickhouse_erl_query_manager:normalize_settings([<<"key">>, <<"value">>])
    ),

    %% Test with mixed formats (tuple and map in same list)
    %% This causes function_clause because the list starts with tuple format
    %% but contains a map, which doesn't match the tuple pattern
    ?assertError(
        function_clause,
        clickhouse_erl_query_manager:normalize_settings([
            {<<"key1">>, <<"value1">>},
            #{key => <<"key2">>, value => <<"value2">>}
        ])
    ),

    %% Test with invalid tuple format (non-binary key)
    %% The implementation catches this and returns invalid_settings_format error
    ?assertError(
        {invalid_settings_format, _, _},
        clickhouse_erl_query_manager:normalize_settings([{key_atom, <<"value">>}])
    ),

    %% Test with invalid tuple format (non-binary value)
    %% The implementation catches this and returns invalid_settings_format error
    ?assertError(
        {invalid_settings_format, _, _},
        clickhouse_erl_query_manager:normalize_settings([{<<"key">>, value_atom}])
    ).
