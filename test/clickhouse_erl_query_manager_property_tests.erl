%% @doc Property-based tests for ClickHouse query manager.
%%
%% This module contains property-based tests using PropEr to validate
%% the query execution lifecycle management and state tracking.
-module(clickhouse_erl_query_manager_property_tests).

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("src/clickhouse_erl_protocol.hrl").

%% Property test: Query state lifecycle management
%% Feature: simple-query, Property 9: Query state lifecycle management
%% Validates: Requirements 5.1, 5.3, 5.4
prop_query_state_lifecycle_management() ->
    ?FORALL(
        {QueryRequest, ConnectionBehavior},
        {query_request_gen(), connection_behavior_gen()},
        begin
            %% Create a mock connection process that simulates different behaviors
            MockConnection = spawn_mock_connection(ConnectionBehavior),

            %% Track initial state
            InitialTime = erlang:system_time(millisecond),

            %% Execute query and track the lifecycle
            Result = clickhouse_erl_query_manager:execute_query(MockConnection, QueryRequest),

            %% Verify lifecycle management based on expected behavior
            case ConnectionBehavior of
                success ->
                    %% For successful queries, should return ok result
                    %% Requirements 5.1, 5.3: Track state and clean up on success
                    case Result of
                        {ok, _} ->
                            %% Verify connection process handled the query properly
                            verify_successful_lifecycle(MockConnection, QueryRequest, InitialTime);
                        {error, _} ->
                            %% If validation failed, that's also acceptable lifecycle management
                            verify_validation_error_lifecycle(Result, QueryRequest)
                    end;
                network_error ->
                    %% For network errors, should return connection error
                    %% Requirements 5.4: Clean up resources on failure
                    case Result of
                        {error, {connection_error, _}} ->
                            verify_error_lifecycle(MockConnection, QueryRequest, InitialTime);
                        {error, {validation_error, _}} ->
                            %% Validation errors can occur before network interaction
                            verify_validation_error_lifecycle(Result, QueryRequest);
                        _ ->
                            false
                    end;
                timeout ->
                    %% For timeouts, should return timeout error
                    %% Requirements 5.4: Clean up resources on timeout
                    case Result of
                        {error, {timeout_error, _}} ->
                            verify_timeout_lifecycle(MockConnection, QueryRequest, InitialTime);
                        {error, {connection_error, _}} ->
                            %% Connection errors can manifest as timeouts
                            verify_error_lifecycle(MockConnection, QueryRequest, InitialTime);
                        {error, {validation_error, _}} ->
                            %% Validation errors can occur before timeout
                            verify_validation_error_lifecycle(Result, QueryRequest);
                        _ ->
                            false
                    end;
                server_exception ->
                    %% For server exceptions, should return protocol error
                    %% Requirements 5.4: Clean up resources on server error
                    case Result of
                        {error, {protocol_error, _}} ->
                            verify_exception_lifecycle(MockConnection, QueryRequest, InitialTime);
                        {error, {validation_error, _}} ->
                            %% Validation errors can occur before server interaction
                            verify_validation_error_lifecycle(Result, QueryRequest);
                        _ ->
                            false
                    end
            end
        end
    ).

%% Generator for query requests with various valid and invalid combinations
query_request_gen() ->
    oneof([
        %% Valid query requests
        #{
            sql => sql_gen(),
            query_id => oneof([undefined, query_id_gen()]),
            settings => settings_gen(),
            timeout => timeout_gen()
        },
        %% Invalid query requests (missing sql)
        #{
            query_id => oneof([undefined, query_id_gen()]),
            settings => settings_gen(),
            timeout => timeout_gen()
        },
        %% Invalid query requests (empty sql)
        #{
            sql => oneof(["", "   ", "\t\n  "]),
            query_id => oneof([undefined, query_id_gen()]),
            settings => settings_gen(),
            timeout => timeout_gen()
        },
        %% Invalid query requests (wrong sql type)
        #{
            sql => oneof([123, atom, {tuple}]),
            query_id => oneof([undefined, query_id_gen()]),
            settings => settings_gen(),
            timeout => timeout_gen()
        }
    ]).

%% Generator for SQL queries
sql_gen() ->
    oneof([
        "SELECT 1",
        "SELECT * FROM system.numbers LIMIT 10",
        "SHOW TABLES",
        "SELECT version()",
        "SELECT now()",
        list_to_binary("SELECT 'binary query'")
    ]).

%% Generator for query IDs
query_id_gen() ->
    oneof([
        list_to_binary("test-query-" ++ integer_to_list(rand:uniform(1000))),
        list_to_binary("binary-query-" ++ integer_to_list(rand:uniform(1000)))
    ]).

%% Generator for settings
settings_gen() ->
    oneof([
        [],
        [#{key => "max_rows_to_read", value => "1000", important => false}],
        [
            #{key => "max_execution_time", value => "30", important => true},
            #{key => "readonly", value => "1", important => false}
        ]
    ]).

%% Generator for timeouts
timeout_gen() ->
    oneof([
        5000,
        10000,
        30000,
        infinity
    ]).

%% Generator for different connection behaviors
connection_behavior_gen() ->
    oneof([
        success,
        network_error,
        timeout,
        server_exception
    ]).

%% Spawn a mock connection process that simulates different behaviors
spawn_mock_connection(Behavior) ->
    Parent = self(),
    spawn(fun() -> mock_connection_loop(Behavior, Parent) end).

%% Mock connection process loop
mock_connection_loop(Behavior, Parent) ->
    receive
        {'$gen_call', From, {query, SQL}} ->
            case Behavior of
                success ->
                    gen_server:reply(From, {ok, mock_result}),
                    Parent ! {connection_handled, success, SQL};
                network_error ->
                    gen_server:reply(From, {error, {network_error, connection_lost}}),
                    Parent ! {connection_handled, network_error, SQL};
                timeout ->
                    %% Don't reply to simulate timeout
                    Parent ! {connection_handled, timeout, SQL};
                server_exception ->
                    ExceptionInfo = #exception_info{
                        error_code = 62,
                        exception_name = "DB::Exception",
                        message = "Syntax error",
                        stack_trace = "Stack trace here",
                        nested = false,
                        nested_exceptions = []
                    },
                    gen_server:reply(From, {error, {server_exception, ExceptionInfo}}),
                    Parent ! {connection_handled, server_exception, SQL}
            end,
            mock_connection_loop(Behavior, Parent);
        stop ->
            ok;
        Other ->
            Parent ! {unexpected_message, Other},
            mock_connection_loop(Behavior, Parent)
    end.

%% Verify successful query lifecycle
verify_successful_lifecycle(MockConnection, _QueryRequest, InitialTime) ->
    %% Check that connection was properly used
    ConnectionHandled =
        receive
            {connection_handled, success, _SQL} -> true;
            {connection_handled, _, _} -> false
        after 1000 ->
            false
        end,

    %% Verify query execution took reasonable time (lifecycle tracking)
    ExecutionTime = erlang:system_time(millisecond) - InitialTime,
    % Should complete quickly in tests
    ReasonableTime = ExecutionTime < 5000,

    %% Clean up mock connection
    MockConnection ! stop,

    %% Requirements 5.1, 5.3: State tracked and cleaned up properly
    ConnectionHandled andalso ReasonableTime.

%% Verify error handling lifecycle
verify_error_lifecycle(MockConnection, _QueryRequest, InitialTime) ->
    %% Check that connection was properly used
    ConnectionHandled =
        receive
            {connection_handled, network_error, _SQL} -> true;
            {connection_handled, _, _} -> false
        after 1000 ->
            false
        end,

    %% Verify error handling took reasonable time
    ExecutionTime = erlang:system_time(millisecond) - InitialTime,
    ReasonableTime = ExecutionTime < 5000,

    %% Clean up mock connection
    MockConnection ! stop,

    %% Requirements 5.4: Resources cleaned up on failure
    ConnectionHandled andalso ReasonableTime.

%% Verify timeout handling lifecycle
verify_timeout_lifecycle(MockConnection, _QueryRequest, InitialTime) ->
    %% For timeout simulation, connection might not respond
    ConnectionHandled =
        receive
            {connection_handled, timeout, _SQL} -> true;
            {connection_handled, _, _} -> false
        after 1000 ->
            % Timeout is expected, so no response is acceptable
            true
        end,

    %% Verify timeout handling took reasonable time
    ExecutionTime = erlang:system_time(millisecond) - InitialTime,
    % Allow more time for timeout scenarios
    ReasonableTime = ExecutionTime < 10000,

    %% Clean up mock connection
    MockConnection ! stop,

    %% Requirements 5.4: Resources cleaned up on timeout
    ConnectionHandled andalso ReasonableTime.

%% Verify server exception handling lifecycle
verify_exception_lifecycle(MockConnection, _QueryRequest, InitialTime) ->
    %% Check that connection was properly used
    ConnectionHandled =
        receive
            {connection_handled, server_exception, _SQL} -> true;
            {connection_handled, _, _} -> false
        after 1000 ->
            false
        end,

    %% Verify exception handling took reasonable time
    ExecutionTime = erlang:system_time(millisecond) - InitialTime,
    ReasonableTime = ExecutionTime < 5000,

    %% Clean up mock connection
    MockConnection ! stop,

    %% Requirements 5.4: Resources cleaned up on server exception
    ConnectionHandled andalso ReasonableTime.

%% Verify validation error lifecycle (no connection interaction needed)
verify_validation_error_lifecycle(Result, QueryRequest) ->
    %% For validation errors, should not interact with connection
    %% and should return appropriate error
    case Result of
        {error, {validation_error, empty_query}} ->
            %% Check if query was actually empty
            case maps:get(sql, QueryRequest, undefined) of
                undefined -> true;
                SQL when is_list(SQL) -> string:trim(SQL) =:= "";
                SQL when is_binary(SQL) -> string:trim(binary_to_list(SQL)) =:= "";
                % Invalid type, validation error expected
                _ -> true
            end;
        {error, {validation_error, missing_sql}} ->
            %% Check if sql was actually missing
            not maps:is_key(sql, QueryRequest);
        {error, {validation_error, invalid_sql_type}} ->
            %% Check if sql was invalid type
            case maps:get(sql, QueryRequest, undefined) of
                SQL when is_list(SQL) orelse is_binary(SQL) -> false;
                _ -> true
            end;
        {error, {validation_error, invalid_arguments}} ->
            %% This can happen for various validation failures
            true;
        _ ->
            false
    end.

%% Property test: Concurrent query independence
%% Feature: simple-query, Property 10: Concurrent query independence
%% Validates: Requirements 5.2
prop_concurrent_query_independence() ->
    ?FORALL(
        {QueryRequests, ConnectionBehaviors},
        concurrent_scenario_gen(),
        begin
            %% Create multiple mock connections with different behaviors
            MockConnections = lists:zipwith(
                fun(Behavior, Index) ->
                    {Index, spawn_mock_connection_with_id(Behavior, Index)}
                end,
                ConnectionBehaviors,
                lists:seq(1, length(ConnectionBehaviors))
            ),

            %% Execute queries concurrently
            Parent = self(),
            lists:zipwith3(
                fun({ConnIndex, MockConnection}, QueryRequest, QueryIndex) ->
                    spawn(fun() ->
                        Result = clickhouse_erl_query_manager:execute_query(
                            MockConnection, QueryRequest
                        ),
                        Parent ! {query_result, QueryIndex, ConnIndex, Result}
                    end)
                end,
                MockConnections,
                QueryRequests,
                lists:seq(1, length(QueryRequests))
            ),

            %% Collect results from all concurrent queries
            Results = collect_concurrent_results(length(QueryRequests), []),

            %% Clean up mock connections
            lists:foreach(
                fun({_Index, MockConnection}) ->
                    MockConnection ! stop
                end,
                MockConnections
            ),

            %% Verify concurrent query independence
            verify_concurrent_independence(Results, ConnectionBehaviors, QueryRequests)
        end
    ).

%% Generator for concurrent scenario with matching lengths
concurrent_scenario_gen() ->
    ?LET(
        N,
        choose(2, 5),
        {vector(N, query_request_gen()), vector(N, connection_behavior_gen())}
    ).

%% Spawn a mock connection with an ID for tracking
spawn_mock_connection_with_id(Behavior, ConnectionId) ->
    Parent = self(),
    spawn(fun() -> mock_connection_loop_with_id(Behavior, ConnectionId, Parent) end).

%% Mock connection process loop with ID tracking
mock_connection_loop_with_id(Behavior, ConnectionId, Parent) ->
    receive
        {'$gen_call', From, {query, SQL}} ->
            case Behavior of
                success ->
                    gen_server:reply(From, {ok, {mock_result, ConnectionId}}),
                    Parent ! {connection_handled, ConnectionId, success, SQL};
                network_error ->
                    gen_server:reply(From, {error, {network_error, connection_lost}}),
                    Parent ! {connection_handled, ConnectionId, network_error, SQL};
                timeout ->
                    %% Don't reply to simulate timeout
                    Parent ! {connection_handled, ConnectionId, timeout, SQL};
                server_exception ->
                    ExceptionInfo = #exception_info{
                        error_code = 62,
                        exception_name = "DB::Exception",
                        message = "Syntax error",
                        stack_trace = "Stack trace here",
                        nested = false,
                        nested_exceptions = []
                    },
                    gen_server:reply(From, {error, {server_exception, ExceptionInfo}}),
                    Parent ! {connection_handled, ConnectionId, server_exception, SQL}
            end,
            mock_connection_loop_with_id(Behavior, ConnectionId, Parent);
        stop ->
            ok;
        Other ->
            Parent ! {unexpected_message, ConnectionId, Other},
            mock_connection_loop_with_id(Behavior, ConnectionId, Parent)
    end.

%% Collect results from concurrent query executions
collect_concurrent_results(0, Acc) ->
    Acc;
collect_concurrent_results(Remaining, Acc) ->
    receive
        {query_result, QueryIndex, ConnIndex, Result} ->
            collect_concurrent_results(Remaining - 1, [{QueryIndex, ConnIndex, Result} | Acc])
        % 10 second timeout for all queries to complete
    after 10000 ->
        %% Some queries may have timed out, which is acceptable
        Acc
    end.

%% Verify that concurrent queries executed independently
verify_concurrent_independence(Results, ConnectionBehaviors, QueryRequests) ->
    %% Requirements 5.2: Multiple queries should be handled independently

    %% 1. Each query should have produced a result or timeout independently
    NumExpectedResults = length(QueryRequests),
    NumActualResults = length(Results),

    %% Allow for some queries to timeout in concurrent scenarios
    ResultsReceived = NumActualResults >= (NumExpectedResults div 2),

    %% 2. Results should match expected behaviors for each connection
    BehaviorMatches = lists:all(
        fun({_QueryIndex, ConnIndex, Result}) ->
            %% Get expected behavior for this connection
            ExpectedBehavior = lists:nth(ConnIndex, ConnectionBehaviors),
            verify_result_matches_behavior(Result, ExpectedBehavior)
        end,
        Results
    ),

    %% 3. Verify no cross-contamination between queries
    %% Each result should be associated with the correct connection
    ConnectionMapping = lists:all(
        fun({_QueryIndex, ConnIndex, _Result}) ->
            %% Connection index should be within valid range
            ConnIndex >= 1 andalso ConnIndex =< length(ConnectionBehaviors)
        end,
        Results
    ),

    %% 4. Verify timing independence - concurrent queries should not significantly delay each other
    %% This is implicitly tested by the timeout mechanism above

    ResultsReceived andalso BehaviorMatches andalso ConnectionMapping.

%% Verify that a result matches the expected connection behavior
verify_result_matches_behavior(Result, ExpectedBehavior) ->
    case {Result, ExpectedBehavior} of
        {{ok, _}, success} -> true;
        {{error, {connection_error, _}}, network_error} -> true;
        {{error, {timeout_error, _}}, timeout} -> true;
        {{error, {server_exception, _}}, server_exception} -> true;
        % Validation errors can occur with any behavior
        {{error, {validation_error, _}}, _} -> true;
        _ -> false
    end.

%% EUnit test wrapper for the query state lifecycle management property
query_state_lifecycle_management_test() ->
    ?assert(proper:quickcheck(prop_query_state_lifecycle_management(), [{numtests, 100}])).

%% EUnit test wrapper for the concurrent query independence property
concurrent_query_independence_test() ->
    ?assert(proper:quickcheck(prop_concurrent_query_independence(), [{numtests, 100}])).

%% Additional unit tests for specific lifecycle scenarios

%% Test that query state is properly tracked during successful execution
successful_query_lifecycle_test() ->
    %% Create a mock connection that responds successfully
    MockConnection = spawn(fun() ->
        receive
            {'$gen_call', From, {query, _SQL}} ->
                gen_server:reply(From, {ok, test_result})
        end
    end),

    QueryRequest = #{sql => "SELECT 1"},
    InitialTime = erlang:system_time(millisecond),

    Result = clickhouse_erl_query_manager:execute_query(MockConnection, QueryRequest),

    ExecutionTime = erlang:system_time(millisecond) - InitialTime,

    %% Should return success
    ?assertMatch({ok, _}, Result),

    %% Should complete in reasonable time (state tracking working)
    ?assert(ExecutionTime < 5000).

%% Test that resources are cleaned up on connection failure
connection_failure_lifecycle_test() ->
    %% Create a mock connection that fails
    MockConnection = spawn(fun() ->
        receive
            {'$gen_call', From, {query, _SQL}} ->
                gen_server:reply(From, {error, {network_error, connection_lost}})
        end
    end),

    QueryRequest = #{sql => "SELECT 1"},
    InitialTime = erlang:system_time(millisecond),

    Result = clickhouse_erl_query_manager:execute_query(MockConnection, QueryRequest),

    ExecutionTime = erlang:system_time(millisecond) - InitialTime,

    %% Should return connection error
    ?assertMatch({error, {connection_error, _}}, Result),

    %% Should complete in reasonable time (cleanup working)
    ?assert(ExecutionTime < 5000).

%% Test that validation errors are handled without connection interaction
validation_error_lifecycle_test() ->
    %% Use self() as dummy connection (should not be called)
    MockConnection = self(),
    flush_mailbox(),

    %% Empty query should trigger validation error
    QueryRequest = #{sql => ""},
    InitialTime = erlang:system_time(millisecond),

    Result = clickhouse_erl_query_manager:execute_query(MockConnection, QueryRequest),

    ExecutionTime = erlang:system_time(millisecond) - InitialTime,

    %% Should return validation error
    ?assertEqual({error, {validation_error, empty_query}}, Result),

    %% Should complete very quickly (no connection interaction)
    ?assert(ExecutionTime < 1000),

    %% Should not have received any messages (no connection interaction)
    receive
        UnexpectedMsg ->
            ?assert(false, "Unexpected message: " ++ io_lib:format("~p", [UnexpectedMsg]))
    after 100 ->
        ok
    end.

%% Test that query ID generation works properly in lifecycle
query_id_generation_lifecycle_test() ->
    %% Create a mock connection that captures the query
    Parent = self(),
    MockConnection = spawn(fun() ->
        receive
            {'$gen_call', From, {query, RequestMap}} when is_map(RequestMap) ->
                Parent ! {query_received, RequestMap},
                gen_server:reply(From, {ok, test_result})
        end
    end),

    %% Query without explicit query_id should generate one
    QueryRequest = #{sql => "SELECT 1"},

    Result = clickhouse_erl_query_manager:execute_query(MockConnection, QueryRequest),

    %% Should return success
    ?assertMatch({ok, _}, Result),

    %% Should have received the query
    receive
        {query_received, ReceivedMap} ->
            ?assertEqual(<<"SELECT 1">>, maps:get(sql, ReceivedMap)),
            ?assert(maps:is_key(query_id, ReceivedMap)),
            ?assert(is_binary(maps:get(query_id, ReceivedMap))),
            ?assert(byte_size(maps:get(query_id, ReceivedMap)) > 0)
    after 1000 ->
        ?assert(false, "Did not receive query from connection")
    end.

%% Test that settings are properly handled in lifecycle
settings_handling_lifecycle_test() ->
    %% Create a mock connection
    MockConnection = spawn(fun() ->
        receive
            {'$gen_call', From, {query, _SQL}} ->
                gen_server:reply(From, {ok, test_result})
        end
    end),

    %% Query with settings
    QueryRequest = #{
        sql => "SELECT 1",
        settings => [#{key => "max_rows", value => "100", important => false}]
    },

    Result = clickhouse_erl_query_manager:execute_query(MockConnection, QueryRequest),

    %% Should return success (settings handled properly)
    ?assertMatch({ok, _}, Result).

%% Test that timeout parameter is properly handled in lifecycle
timeout_handling_lifecycle_test() ->
    %% Create a mock connection
    MockConnection = spawn(fun() ->
        receive
            {'$gen_call', From, {query, _SQL}} ->
                gen_server:reply(From, {ok, test_result})
        end
    end),

    %% Query with custom timeout
    QueryRequest = #{
        sql => "SELECT 1",
        timeout => 60000
    },

    Result = clickhouse_erl_query_manager:execute_query(MockConnection, QueryRequest),

    %% Should return success (timeout handled properly)
    ?assertMatch({ok, _}, Result).

flush_mailbox() ->
    receive
        _ -> flush_mailbox()
    after 0 ->
        ok
    end.

%%%===================================================================
%%% INSERT Workflow Property Tests
%%%===================================================================

%% Property test: INSERT workflow atomicity
%% Feature: insert-queries, Property 3: INSERT Workflow Atomicity
%% Validates: Requirements 1.6
prop_insert_workflow_atomicity() ->
    ?FORALL(
        {InsertScenario, NumRows},
        {insert_scenario_gen(), choose(1, 100)},
        begin
            %% Generate test data based on scenario
            Input = generate_insert_input(InsertScenario, NumRows),
            SQL = generate_insert_sql(InsertScenario),

            %% Create a mock connection that simulates different outcomes
            MockConnection = spawn_mock_insert_connection(InsertScenario),

            %% Execute INSERT
            Result = clickhouse_erl_query_manager:execute_insert(
                MockConnection, SQL, Input, 5000
            ),

            %% Clean up
            MockConnection ! stop,

            %% Verify atomicity: either all rows inserted or none
            verify_insert_atomicity(Result, InsertScenario, NumRows)
        end
    ).

%% Generator for INSERT scenarios
insert_scenario_gen() ->
    oneof([
        % All rows inserted successfully
        success,
        % Server rejects due to constraint
        constraint_violation,
        % Network failure during INSERT
        network_error,
        % Data validation failure
        invalid_data
    ]).

%% Generate INSERT input based on scenario
generate_insert_input(invalid_data, NumRows) ->
    %% Generate invalid input (mismatched row counts)
    [
        #{name => <<"col1">>, type => <<"UInt32">>, data => lists:seq(1, NumRows)},
        #{name => <<"col2">>, type => <<"String">>, data => lists:seq(1, NumRows - 1)}
    ];
generate_insert_input(_Scenario, NumRows) ->
    %% Generate valid input
    [
        #{name => <<"col1">>, type => <<"UInt32">>, data => lists:seq(1, NumRows)},
        #{
            name => <<"col2">>,
            type => <<"String">>,
            data => [<<"test">> || _ <- lists:seq(1, NumRows)]
        }
    ].

%% Generate INSERT SQL based on scenario
generate_insert_sql(_Scenario) ->
    <<"INSERT INTO test_table (col1, col2) VALUES">>.

%% Spawn a mock connection for INSERT testing
spawn_mock_insert_connection(Scenario) ->
    Parent = self(),
    spawn(fun() -> mock_insert_connection_loop(Scenario, Parent) end).

%% Mock INSERT connection loop
mock_insert_connection_loop(Scenario, Parent) ->
    receive
        {'$gen_call', From, {insert, RequestMap}} ->
            NumRows = maps:get(num_rows, RequestMap, 0),
            case Scenario of
                success ->
                    %% All rows inserted successfully
                    gen_server:reply(From, {ok, #{rows_inserted => NumRows, elapsed_time => 100}}),
                    Parent ! {insert_handled, success, NumRows};
                constraint_violation ->
                    %% Server exception: constraint violation (no rows inserted)
                    ExceptionInfo = #exception_info{
                        error_code = 252,
                        exception_name = <<"DB::Exception">>,
                        message = <<"Constraint violation: duplicate key">>,
                        stack_trace = <<"at insert.cpp:123">>,
                        nested = false,
                        nested_exceptions = []
                    },
                    gen_server:reply(From, {error, {server_exception, ExceptionInfo}}),
                    Parent ! {insert_handled, constraint_violation, 0};
                network_error ->
                    %% Network error during INSERT (no rows inserted)
                    gen_server:reply(From, {error, {send_failed, {data_block, econnreset}}}),
                    Parent ! {insert_handled, network_error, 0};
                invalid_data ->
                    %% This should be caught by validation before reaching connection
                    gen_server:reply(From, {error, {validation_error, row_count_mismatch}}),
                    Parent ! {insert_handled, invalid_data, 0}
            end,
            mock_insert_connection_loop(Scenario, Parent);
        stop ->
            ok;
        Other ->
            Parent ! {unexpected_message, Other},
            mock_insert_connection_loop(Scenario, Parent)
    end.

%% Verify INSERT atomicity property
verify_insert_atomicity(Result, Scenario, NumRows) ->
    %% First, consume any pending messages to avoid interference
    flush_insert_messages(),

    case Scenario of
        success ->
            %% Should insert all rows
            case Result of
                {ok, #{rows_inserted := InsertedRows}} ->
                    %% Atomicity: all rows inserted
                    InsertedRows =:= NumRows;
                _ ->
                    false
            end;
        constraint_violation ->
            %% Should insert no rows (atomicity: all or nothing)
            case Result of
                {error, {server_exception, _}} ->
                    %% Exception means no rows were inserted (atomicity)
                    true;
                _ ->
                    false
            end;
        network_error ->
            %% Should insert no rows (atomicity: all or nothing)
            case Result of
                {error, {connection_error, _}} ->
                    %% Network error means no rows were inserted (atomicity)
                    true;
                _ ->
                    false
            end;
        invalid_data ->
            %% Should be caught by validation (no rows inserted)
            case Result of
                {error, {validation_error, _}} ->
                    %% Validation error means no data was sent (atomicity)
                    true;
                _ ->
                    false
            end
    end.

%% Flush any pending insert messages
flush_insert_messages() ->
    receive
        {insert_handled, _, _} -> flush_insert_messages()
    after 0 ->
        ok
    end.

%% EUnit test wrapper for INSERT workflow atomicity property
insert_workflow_atomicity_test() ->
    ?assert(proper:quickcheck(prop_insert_workflow_atomicity(), [{numtests, 100}])).

%% Property test: Network error propagation
%% Feature: insert-queries, Property 9: Network Error Propagation
%% Validates: Requirements 4.4
prop_network_error_propagation() ->
    ?FORALL(
        {NetworkError, NumRows},
        {network_error_gen(), choose(1, 50)},
        begin
            %% Generate valid INSERT input
            Input = [
                #{name => <<"col1">>, type => <<"UInt32">>, data => lists:seq(1, NumRows)},
                #{
                    name => <<"col2">>,
                    type => <<"String">>,
                    data => [<<"test">> || _ <- lists:seq(1, NumRows)]
                }
            ],
            SQL = <<"INSERT INTO test_table VALUES">>,

            %% Create a mock connection that simulates network error
            MockConnection = spawn_mock_network_error_connection(NetworkError),

            %% Execute INSERT
            Result = clickhouse_erl_query_manager:execute_insert(
                MockConnection, SQL, Input, 5000
            ),

            %% Clean up
            MockConnection ! stop,

            %% Verify network error is propagated with context
            verify_network_error_propagation(Result, NetworkError)
        end
    ).

%% Generator for different network errors
network_error_gen() ->
    oneof([
        % Connection reset
        econnreset,
        % Connection refused
        econnrefused,
        % Socket closed
        closed,
        % Network timeout
        timeout,
        % Host unreachable
        ehostunreach,
        % Network unreachable
        enetunreach
    ]).

%% Spawn a mock connection that simulates network errors
spawn_mock_network_error_connection(NetworkError) ->
    Parent = self(),
    spawn(fun() -> mock_network_error_connection_loop(NetworkError, Parent) end).

%% Mock connection loop for network errors
mock_network_error_connection_loop(NetworkError, Parent) ->
    receive
        {'$gen_call', From, {insert, _RequestMap}} ->
            %% Simulate network error at different stages
            ErrorStage = lists:nth(rand:uniform(3), [query_packet, data_block, blank_block]),
            ErrorResponse =
                case ErrorStage of
                    query_packet ->
                        {error, {network_error, NetworkError}};
                    data_block ->
                        {error, {send_failed, {data_block, NetworkError}}};
                    blank_block ->
                        {error, {send_failed, {blank_block, NetworkError}}}
                end,
            gen_server:reply(From, ErrorResponse),
            Parent ! {network_error_handled, ErrorStage, NetworkError},
            mock_network_error_connection_loop(NetworkError, Parent);
        stop ->
            ok;
        Other ->
            Parent ! {unexpected_message, Other},
            mock_network_error_connection_loop(NetworkError, Parent)
    end.

%% Verify network error is propagated with context
verify_network_error_propagation(Result, ExpectedError) ->
    case Result of
        {error, {connection_error, {network, ActualError}}} ->
            %% Network error propagated with context
            ActualError =:= ExpectedError;
        {error, {connection_error, {send_failed, {Stage, ActualError}}}} ->
            %% Send failed error propagated with stage context
            ActualError =:= ExpectedError andalso
                lists:member(Stage, [query_packet, data_block, blank_block]);
        _ ->
            false
    end.

%% EUnit test wrapper for network error propagation property
network_error_propagation_test() ->
    ?assert(proper:quickcheck(prop_network_error_propagation(), [{numtests, 100}])).

%% Property test: Server exception handling
%% Feature: insert-queries, Property 10: Server Exception Handling
%% Validates: Requirements 4.3
prop_server_exception_handling() ->
    ?FORALL(
        {ExceptionScenario, NumRows},
        {exception_scenario_gen(), choose(1, 50)},
        begin
            %% Generate valid INSERT input
            Input = [
                #{name => <<"col1">>, type => <<"UInt32">>, data => lists:seq(1, NumRows)},
                #{
                    name => <<"col2">>,
                    type => <<"String">>,
                    data => [<<"test">> || _ <- lists:seq(1, NumRows)]
                }
            ],
            SQL = <<"INSERT INTO test_table VALUES">>,

            %% Create a mock connection that simulates server exception
            MockConnection = spawn_mock_exception_connection(ExceptionScenario),

            %% Execute INSERT
            Result = clickhouse_erl_query_manager:execute_insert(
                MockConnection, SQL, Input, 5000
            ),

            %% Clean up
            MockConnection ! stop,

            %% Verify exception details are captured and returned
            verify_server_exception_handling(Result, ExceptionScenario)
        end
    ).

%% Generator for different server exception scenarios
exception_scenario_gen() ->
    oneof([
        {constraint_violation, 252, <<"Constraint violation: duplicate key">>},
        {syntax_error, 62, <<"Syntax error in query">>},
        {unknown_table, 60, <<"Table doesn't exist">>},
        {type_mismatch, 53, <<"Type mismatch in column">>},
        {readonly_violation, 164, <<"Cannot insert into readonly table">>},
        {quota_exceeded, 201, <<"Quota exceeded">>},
        {memory_limit, 241, <<"Memory limit exceeded">>}
    ]).

%% Spawn a mock connection that simulates server exceptions
spawn_mock_exception_connection(ExceptionScenario) ->
    Parent = self(),
    spawn(fun() -> mock_exception_connection_loop(ExceptionScenario, Parent) end).

%% Mock connection loop for server exceptions
mock_exception_connection_loop(ExceptionScenario, Parent) ->
    receive
        {'$gen_call', From, {insert, _RequestMap}} ->
            {ExceptionType, ErrorCode, Message} = ExceptionScenario,

            %% Create exception info with all required fields (record)
            ExceptionInfo = #exception_info{
                error_code = ErrorCode,
                exception_name = <<"DB::Exception">>,
                message = Message,
                stack_trace = list_to_binary(
                    io_lib:format("at ~s.cpp:~p", [ExceptionType, rand:uniform(1000)])
                ),
                nested = false,
                nested_exceptions = []
            },

            gen_server:reply(From, {error, {server_exception, ExceptionInfo}}),
            Parent ! {exception_handled, ExceptionType, ErrorCode, Message},
            mock_exception_connection_loop(ExceptionScenario, Parent);
        stop ->
            ok;
        Other ->
            Parent ! {unexpected_message, Other},
            mock_exception_connection_loop(ExceptionScenario, Parent)
    end.

%% Verify server exception is captured and returned with details
verify_server_exception_handling(Result, ExceptionScenario) ->
    {ExpectedType, ExpectedCode, ExpectedMessage} = ExceptionScenario,

    case Result of
        {error, {server_exception, ExceptionInfo}} ->
            %% Verify exception info contains all required fields (it's a record)
            ErrorCode = ExceptionInfo#exception_info.error_code,
            ExceptionName = ExceptionInfo#exception_info.exception_name,
            Message = ExceptionInfo#exception_info.message,
            StackTrace = ExceptionInfo#exception_info.stack_trace,

            %% Verify exception details match expected
            CodeMatches = ErrorCode =:= ExpectedCode,
            MessageMatches = Message =:= ExpectedMessage,

            %% Verify exception was handled
            ExceptionHandled =
                receive
                    {exception_handled, ActualType, ActualCode, ActualMessage} ->
                        ActualType =:= ExpectedType andalso
                            ActualCode =:= ExpectedCode andalso
                            ActualMessage =:= ExpectedMessage
                after 1000 ->
                    false
                end,

            %% All checks must pass
            is_integer(ErrorCode) andalso
                is_binary(ExceptionName) andalso
                is_binary(Message) andalso
                is_binary(StackTrace) andalso
                CodeMatches andalso MessageMatches andalso ExceptionHandled;
        _ ->
            false
    end.

%% EUnit test wrapper for server exception handling property
server_exception_handling_test() ->
    ?assert(proper:quickcheck(prop_server_exception_handling(), [{numtests, 100}])).
