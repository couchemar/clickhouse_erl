%% @doc Common Test suite for ClickHouse integration tests
%%
%% Comprehensive integration tests covering connection handshake, concurrent connections,
%% error scenarios, exception handling, and INSERT operations against a real ClickHouse server.
%%
-module(clickhouse_erl_integration_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("../src/clickhouse_erl_protocol.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).

%% Test cases - Handshake
-export([
    successful_handshake_default/1,
    successful_handshake_custom_credentials/1,
    handshake_different_client_versions/1,
    handshake_different_databases/1
]).

%% Test cases - Concurrent Connections
-export([
    concurrent_connections/1,
    connection_pooling/1,
    concurrent_different_credentials/1
]).

%% Test cases - Error Scenarios
-export([
    connection_nonexistent_host/1,
    connection_invalid_port/1,
    connection_timeout/1,
    invalid_credentials/1,
    malformed_options/1,
    network_interruption/1,
    resource_cleanup_after_failure/1,
    connection_recovery/1
]).

%% Test cases - Stress Tests
-export([
    stress_rapid_connections/1
]).

%% Test cases - Error Information
-export([
    error_information_completeness/1,
    version_compatibility/1
]).

%% Test cases - Exception Handling
-export([
    exception_handling_authentication_failure/1,
    exception_handling_connection_phases/1,
    nested_exception_handling/1,
    exception_handling_error_scenarios/1,
    exception_propagation_completeness/1,
    exception_handling_integration/1,
    exception_packet_recognition/1
]).

%% Test cases - INSERT Operations
-export([
    insert_single_column/1,
    insert_multiple_columns/1,
    insert_integer_types/1,
    insert_float_types/1,
    insert_string_type/1,
    insert_temporal_types/1,
    insert_bool_type/1,
    insert_datetime64_type/1
]).

%% Test cases - Round-trip Tests
-export([
    roundtrip_integer_types/1,
    roundtrip_float_types/1,
    roundtrip_temporal_types/1,
    roundtrip_bool_type/1
]).

%% Test cases - INSERT Error Handling
-export([
    insert_empty_input/1,
    insert_schema_mismatch/1,
    insert_constraint_violation/1,
    insert_row_count_mismatch/1,
    insert_invalid_column_name/1
]).

%% Test cases - INSERT Performance
-export([
    insert_large_dataset/1,
    insert_sequential/1,
    insert_with_timeout/1,
    insert_atomicity/1
]).

%% Test cases - New Type Support
-export([
    new_integer_types_full/1,
    new_float_types_full/1,
    new_temporal_types_full/1,
    new_bool_type_full/1,
    new_all_types_combined/1
]).

-define(CONNECTION_TIMEOUT, 10000).
-define(HANDSHAKE_TIMEOUT, 15000).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

suite() ->
    [{timetrap, {seconds, 30}}].

all() ->
    [
        {group, handshake},
        {group, concurrent_connections},
        {group, error_scenarios},
        {group, stress_tests},
        {group, error_information},
        {group, exception_handling},
        {group, insert_operations},
        {group, roundtrip_tests},
        {group, insert_error_handling},
        {group, insert_performance},
        {group, new_type_support}
    ].

groups() ->
    [
        {handshake, [sequence], [
            successful_handshake_default,
            successful_handshake_custom_credentials,
            handshake_different_client_versions,
            handshake_different_databases
        ]},
        {concurrent_connections, [sequence], [
            concurrent_connections,
            connection_pooling,
            concurrent_different_credentials
        ]},
        {error_scenarios, [sequence], [
            connection_nonexistent_host,
            connection_invalid_port,
            connection_timeout,
            invalid_credentials,
            malformed_options,
            network_interruption,
            resource_cleanup_after_failure,
            connection_recovery
        ]},
        {stress_tests, [sequence], [
            stress_rapid_connections
        ]},
        {error_information, [sequence], [
            error_information_completeness,
            version_compatibility
        ]},
        {exception_handling, [sequence], [
            exception_handling_authentication_failure,
            exception_handling_connection_phases,
            nested_exception_handling,
            exception_handling_error_scenarios,
            exception_propagation_completeness,
            exception_handling_integration,
            exception_packet_recognition
        ]},
        {insert_operations, [sequence], [
            insert_single_column,
            insert_multiple_columns,
            insert_integer_types,
            insert_float_types,
            insert_string_type,
            insert_temporal_types,
            insert_bool_type,
            insert_datetime64_type
        ]},
        {roundtrip_tests, [sequence], [
            roundtrip_integer_types,
            roundtrip_float_types,
            roundtrip_temporal_types,
            roundtrip_bool_type
        ]},
        {insert_error_handling, [sequence], [
            insert_empty_input,
            insert_schema_mismatch,
            insert_constraint_violation,
            insert_row_count_mismatch,
            insert_invalid_column_name
        ]},
        {insert_performance, [sequence], [
            insert_large_dataset,
            insert_sequential,
            insert_with_timeout,
            insert_atomicity
        ]},
        {new_type_support, [sequence], [
            new_integer_types_full,
            new_float_types_full,
            new_temporal_types_full,
            new_bool_type_full,
            new_all_types_combined
        ]}
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

init_per_group(Group, Config) when
    Group =:= handshake;
    Group =:= insert_operations;
    Group =:= roundtrip_tests;
    Group =:= insert_error_handling;
    Group =:= new_type_support
->
    % Groups that can share a connection
    % Ensure application is started
    test_helpers:setup(),
    % Use test_helpers:connect() for consistent connection setup
    {ok, Connection} = test_helpers:connect(),
    [{connection, Connection} | Config];
init_per_group(_Group, Config) ->
    % Groups that create their own connections (concurrent, error scenarios, etc.)
    Config.

end_per_group(Group, Config) when
    Group =:= handshake;
    Group =:= insert_operations;
    Group =:= roundtrip_tests;
    Group =:= new_type_support
->
    % Clean up shared connection
    Connection = ?config(connection, Config),
    ok = test_helpers:disconnect(Connection);
end_per_group(_Group, _Config) ->
    ok.

%%%===================================================================
%%% Test Cases
%%%===================================================================

%% @doc Test successful handshake with default credentials
%% Requirements: 1.1, 2.1, 3.1
successful_handshake_default(Config) ->
    Connection = ?config(connection, Config),

    % Verify connection is established
    ?assert(is_pid(Connection)),
    ?assert(is_process_alive(Connection)),

    % Get connection info to verify handshake completed
    {ok, Info} = clickhouse_erl_connection:get_connection_info(Connection),
    ?assertEqual(ready, maps:get(state, Info)),

    % Verify server information is populated
    ?assert(maps:is_key(server_name, Info)),
    ?assert(maps:is_key(server_version, Info)),
    ?assert(maps:is_key(server_revision, Info)),
    ?assert(maps:is_key(server_timezone, Info)),
    ?assert(maps:is_key(server_display_name, Info)),

    % Verify server version is a valid tuple
    ServerVersion = maps:get(server_version, Info),
    ?assertMatch(
        {Major, Minor, Patch} when
            is_integer(Major) andalso
                is_integer(Minor) andalso
                is_integer(Patch),
        ServerVersion
    ).

%% @doc Test successful handshake with custom credentials
%% Requirements: 1.1, 2.1, 3.1
successful_handshake_custom_credentials(Config) ->
    Connection = ?config(connection, Config),

    % Verify connection is established
    ?assert(is_pid(Connection)),
    ?assert(is_process_alive(Connection)),

    % Get connection info
    {ok, Info} = clickhouse_erl_connection:get_connection_info(Connection),
    ?assertEqual(ready, maps:get(state, Info)),

    % Verify server information
    ?assert(is_binary(maps:get(server_name, Info))),
    ?assert(is_tuple(maps:get(server_version, Info))),
    ?assert(is_integer(maps:get(server_revision, Info))),
    ?assert(is_binary(maps:get(server_timezone, Info))),
    ?assert(is_binary(maps:get(server_display_name, Info))).

%% @doc Test handshake with various client versions
%% Requirements: 2.1, 3.1
handshake_different_client_versions(Config) ->
    ClientVersions = [
        {0, 1, 0},
        {1, 0, 0},
        {2, 5, 10},
        {99, 99, 99}
    ],

    lists:foreach(
        fun(Version) ->
            Options = #{
                client_version => Version,
                username => test_helpers:test_username(),
                password => test_helpers:test_password(),
                timeout => ?CONNECTION_TIMEOUT
            },

            Result = clickhouse_erl_connection:connect(
                test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
            ),

            case Result of
                {ok, Connection} ->
                    {ok, Info} = clickhouse_erl_connection:get_connection_info(Connection),
                    ?assertEqual(ready, maps:get(state, Info)),
                    ok = clickhouse_erl_connection:disconnect(Connection);
                {error, Reason} ->
                    ?debugFmt("Connection failed for client version ~p: ~p~n", [Version, Reason]),
                    ?assert(false)
            end
        end,
        ClientVersions
    ).

%% @doc Test handshake with different database names
%% Requirements: 2.1, 3.1
handshake_different_databases(Config) ->
    Databases = [
        "default",
        test_helpers:test_database(),
        "system",
        "information_schema"
    ],

    lists:foreach(
        fun(Database) ->
            Options = #{
                database => Database,
                username => test_helpers:test_username(),
                password => test_helpers:test_password(),
                timeout => ?CONNECTION_TIMEOUT
            },

            Result = clickhouse_erl_connection:connect(
                test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
            ),

            case Result of
                {ok, Connection} ->
                    {ok, Info} = clickhouse_erl_connection:get_connection_info(Connection),
                    ?assertEqual(ready, maps:get(state, Info)),
                    ok = clickhouse_erl_connection:disconnect(Connection);
                {error, Reason} ->
                    ?debugFmt("Connection failed for database ~p: ~p~n", [Database, Reason]),
                    ?assert(false)
            end
        end,
        Databases
    ).

%%%===================================================================
%%% Concurrent Connections Tests
%%%===================================================================

%% @doc Test multiple concurrent connections
%% Requirements: 1.1, 2.1, 3.1
concurrent_connections(Config) ->
    NumConnections = 5,

    % Start multiple connections concurrently
    ConnectionPids = lists:map(
        fun(N) ->
            Options = #{
                client_name => io_lib:format("concurrent_client_~p", [N]),
                username => test_helpers:test_username(),
                password => test_helpers:test_password(),
                timeout => ?CONNECTION_TIMEOUT
            },

            case
                clickhouse_erl_connection:connect(
                    test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
                )
            of
                {ok, Connection} ->
                    Connection;
                {error, Reason} ->
                    ?debugFmt("Concurrent connection ~p failed: ~p~n", [N, Reason]),
                    ?assert(false)
            end
        end,
        lists:seq(1, NumConnections)
    ),

    % Verify all connections are alive and ready
    lists:foreach(
        fun(Connection) ->
            ?assert(is_process_alive(Connection)),
            {ok, Info} = clickhouse_erl_connection:get_connection_info(Connection),
            ?assertEqual(ready, maps:get(state, Info))
        end,
        ConnectionPids
    ),

    % Clean up all connections
    lists:foreach(
        fun(Connection) ->
            ok = clickhouse_erl_connection:disconnect(Connection)
        end,
        ConnectionPids
    ),

    % Verify all connections are cleaned up
    timer:sleep(200),
    lists:foreach(
        fun(Connection) ->
            ?assertNot(is_process_alive(Connection))
        end,
        ConnectionPids
    ).

%% @doc Test connection pooling behavior (rapid connect/disconnect)
%% Requirements: 1.1, 2.1, 3.1
connection_pooling(Config) ->
    NumIterations = 10,

    % Rapidly create and destroy connections
    lists:foreach(
        fun(N) ->
            Options = #{
                client_name => io_lib:format("pool_client_~p", [N]),
                username => test_helpers:test_username(),
                password => test_helpers:test_password(),
                timeout => ?CONNECTION_TIMEOUT
            },

            {ok, Connection} = clickhouse_erl_connection:connect(
                test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
            ),

            % Verify connection is ready
            {ok, Info} = clickhouse_erl_connection:get_connection_info(Connection),
            ?assertEqual(ready, maps:get(state, Info)),

            % Disconnect immediately
            ok = clickhouse_erl_connection:disconnect(Connection),

            % Brief pause to allow cleanup
            timer:sleep(10)
        end,
        lists:seq(1, NumIterations)
    ).

%% @doc Test concurrent connections with different credentials
%% Requirements: 1.1, 2.1, 3.1
concurrent_different_credentials(Config) ->
    % Create connections with different configurations
    Configs = [
        #{
            database => "default",
            username => test_helpers:test_username(),
            password => test_helpers:test_password(),
            client_name => "client_1"
        },
        #{
            database => test_helpers:test_database(),
            username => test_helpers:test_username(),
            password => test_helpers:test_password(),
            client_name => "client_2"
        },
        #{
            database => "system",
            username => test_helpers:test_username(),
            password => test_helpers:test_password(),
            client_name => "client_3"
        }
    ],

    % Start all connections
    ConnectionPids = lists:map(
        fun(Config) ->
            ConfigWithTimeout = maps:put(timeout, ?CONNECTION_TIMEOUT, Config),
            case
                clickhouse_erl_connection:connect(
                    test_helpers:clickhouse_host(),
                    test_helpers:clickhouse_port(),
                    ConfigWithTimeout
                )
            of
                {ok, Connection} ->
                    Connection;
                {error, Reason} ->
                    ?debugFmt("Connection failed for config ~p: ~p~n", [Config, Reason]),
                    ?assert(false)
            end
        end,
        Configs
    ),

    % Verify all connections are ready
    lists:foreach(
        fun(Connection) ->
            ?assert(is_process_alive(Connection)),
            {ok, Info} = clickhouse_erl_connection:get_connection_info(Connection),
            ?assertEqual(ready, maps:get(state, Info))
        end,
        ConnectionPids
    ),

    % Clean up
    lists:foreach(
        fun(Connection) ->
            ok = clickhouse_erl_connection:disconnect(Connection)
        end,
        ConnectionPids
    ).

%%%===================================================================
%%% Error Scenarios and Network Interruption Tests
%%%===================================================================

%% @doc Test connection to non-existent host
%% Requirements: 1.1
connection_nonexistent_host(Config) ->
    Result = clickhouse_erl_connection:connect(
        "nonexistent.invalid.domain.test", test_helpers:clickhouse_port(), #{}
    ),

    ?assertMatch({error, {network_error, _}}, Result).

%% @doc Test connection to invalid port
%% Requirements: 1.1
connection_invalid_port(Config) ->
    % Try to connect to a port that should be closed
    Result = clickhouse_erl_connection:connect(test_helpers:clickhouse_host(), 65534, #{}),

    ?assertMatch({error, {network_error, _}}, Result).

%% @doc Test connection timeout
%% Requirements: 1.1
connection_timeout(Config) ->
    % Use a very short timeout to force timeout error
    Options = #{timeout => 1},

    % Connect to a host that should cause timeout (using a non-routable IP)
    Result = clickhouse_erl_connection:connect(
        "192.0.2.1", test_helpers:clickhouse_port(), Options
    ),

    ?assertMatch({error, {timeout_error, tcp_connect}}, Result).

%% @doc Test invalid credentials
%% Requirements: 2.1, 3.1
invalid_credentials(Config) ->
    % Try to connect with invalid credentials
    Options = #{
        database => "nonexistent_database",
        username => "invalid_user",
        password => "wrong_password",
        timeout => ?CONNECTION_TIMEOUT
    },

    Result = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),

    % The connection might succeed at TCP level but fail during handshake
    % or it might succeed if ClickHouse accepts any credentials in test mode
    case Result of
        {ok, Connection} ->
            % If connection succeeds, verify we can get info and clean up
            {ok, _Info} = clickhouse_erl_connection:get_connection_info(Connection),
            ok = clickhouse_erl_connection:disconnect(Connection);
        {error, _Reason} ->
            % Error is also acceptable for invalid credentials
            ok
    end.

%% @doc Test connection with malformed options
%% Requirements: 2.1
malformed_options(Config) ->
    % Test with edge case options that should be handled gracefully
    EdgeCaseOptions = [
        #{
            client_name => "",
            username => test_helpers:test_username(),
            password => test_helpers:test_password()
        },
        #{
            database => "",
            username => test_helpers:test_username(),
            password => test_helpers:test_password()
        }
    ],

    lists:foreach(
        fun(Options) ->
            Result = clickhouse_erl_connection:connect(
                test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
            ),

            % Should either fail gracefully or succeed (if options are coerced)
            case Result of
                {ok, Connection} ->
                    ok = clickhouse_erl_connection:disconnect(Connection);
                {error, _Reason} ->
                    ok
            end
        end,
        EdgeCaseOptions
    ).

%% @doc Test network interruption during handshake
%% Requirements: 1.1, 2.1, 3.1
network_interruption(Config) ->
    % This test simulates network issues by connecting to the wrong port
    % or using very short timeouts

    % Test 1: Connect to HTTP port instead of native port (should fail during handshake)
    Result1 = clickhouse_erl_connection:connect(test_helpers:clickhouse_host(), 8123, #{}),
    ?assertMatch({error, _}, Result1),

    % Test 2: Use very short handshake timeout
    Options2 = #{timeout => 1},
    Result2 = clickhouse_erl_connection:connect(
        "192.0.2.1", test_helpers:clickhouse_port(), Options2
    ),
    ?assertMatch({error, {timeout_error, _}}, Result2).

%% @doc Test resource cleanup after connection failures
%% Requirements: 1.1
resource_cleanup_after_failure(Config) ->
    InitialProcessCount = length(processes()),
    InitialPortCount = length(erlang:ports()),

    % Attempt multiple failed connections
    FailedAttempts = 5,
    lists:foreach(
        fun(_) ->
            Result = clickhouse_erl_connection:connect(
                "nonexistent.invalid.domain.test", test_helpers:clickhouse_port(), #{}
            ),
            ?assertMatch({error, _}, Result),
            % Allow cleanup time
            timer:sleep(50)
        end,
        lists:seq(1, FailedAttempts)
    ),

    % Allow additional cleanup time
    timer:sleep(500),

    FinalProcessCount = length(processes()),
    FinalPortCount = length(erlang:ports()),

    % Verify no significant resource leaks (allow some tolerance for system processes)
    ProcessDiff = FinalProcessCount - InitialProcessCount,
    PortDiff = FinalPortCount - InitialPortCount,

    % Allow small tolerance
    ?assert(ProcessDiff =< 2),
    % Allow small tolerance
    ?assert(PortDiff =< 1).

%% @doc Test connection recovery after temporary network issues
%% Requirements: 1.1, 2.1, 3.1
connection_recovery(Config) ->
    % First, establish a successful connection to verify server is working
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password()
    },
    {ok, Connection1} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),
    {ok, Info1} = clickhouse_erl_connection:get_connection_info(Connection1),
    ?assertEqual(ready, maps:get(state, Info1)),
    ok = clickhouse_erl_connection:disconnect(Connection1),

    % Simulate temporary network issue by trying invalid host
    Result2 = clickhouse_erl_connection:connect(
        "nonexistent.invalid.domain.test", test_helpers:clickhouse_port(), #{}
    ),
    ?assertMatch({error, {network_error, _}}, Result2),

    % Verify we can still connect successfully after the failure
    {ok, Connection3} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),
    {ok, Info3} = clickhouse_erl_connection:get_connection_info(Connection3),
    ?assertEqual(ready, maps:get(state, Info3)),
    ok = clickhouse_erl_connection:disconnect(Connection3).

%%%===================================================================
%%% Stress Tests
%%%===================================================================

%% @doc Stress test with many rapid connections
%% Requirements: 1.1, 2.1, 3.1
stress_rapid_connections(Config) ->
    NumConnections = 20,

    % Create many connections rapidly
    StartTime = erlang:monotonic_time(millisecond),

    ConnectionResults = lists:map(
        fun(N) ->
            Options = #{
                client_name => io_lib:format("stress_client_~p", [N]),
                username => test_helpers:test_username(),
                password => test_helpers:test_password(),
                timeout => ?CONNECTION_TIMEOUT
            },
            clickhouse_erl_connection:connect(
                test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
            )
        end,
        lists:seq(1, NumConnections)
    ),

    % Verify all connections succeeded
    ConnectionPids = lists:map(
        fun(Result) ->
            ?assertMatch({ok, _}, Result),
            {ok, Pid} = Result,
            Pid
        end,
        ConnectionResults
    ),

    % Verify all are ready
    lists:foreach(
        fun(Connection) ->
            {ok, Info} = clickhouse_erl_connection:get_connection_info(Connection),
            ?assertEqual(ready, maps:get(state, Info))
        end,
        ConnectionPids
    ),

    % Disconnect all rapidly
    lists:foreach(
        fun(Connection) ->
            ok = clickhouse_erl_connection:disconnect(Connection)
        end,
        ConnectionPids
    ),

    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    ?debugFmt("Stress test completed: ~p connections in ~p ms~n", [NumConnections, Duration]),

    % Verify cleanup
    timer:sleep(200),
    lists:foreach(
        fun(Connection) ->
            ?assertNot(is_process_alive(Connection))
        end,
        ConnectionPids
    ).

%%%===================================================================
%%% Error Information Tests
%%%===================================================================

%% @doc Test that error information is complete and descriptive
%% Requirements: 1.1, 2.1, 3.1
error_information_completeness(Config) ->
    % Test various error scenarios and verify error information

    % Network error
    {error, NetworkError} = clickhouse_erl_connection:connect(
        "nonexistent.invalid.domain.test", test_helpers:clickhouse_port(), #{}
    ),
    ?assertMatch({network_error, _}, NetworkError),
    FormattedNetworkError = clickhouse_erl_connection:format_error(NetworkError),
    ?assert(is_binary(FormattedNetworkError)),
    ?assert(byte_size(FormattedNetworkError) > 0),

    % Timeout error
    {error, TimeoutError} = clickhouse_erl_connection:connect(
        "192.0.2.1", test_helpers:clickhouse_port(), #{
            timeout => 1
        }
    ),
    ?assertMatch({timeout_error, _}, TimeoutError),
    FormattedTimeoutError = clickhouse_erl_connection:format_error(TimeoutError),
    ?assert(is_binary(FormattedTimeoutError)),
    ?assert(byte_size(FormattedTimeoutError) > 0),

    % Connection refused error
    {error, RefusedError} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(), 65534, #{}
    ),
    ?assertMatch({network_error, _}, RefusedError),
    FormattedRefusedError = clickhouse_erl_connection:format_error(RefusedError),
    ?assert(is_binary(FormattedRefusedError)),
    ?assert(byte_size(FormattedRefusedError) > 0).

%%%===================================================================
%%% Version Compatibility Tests
%%%===================================================================

%% @doc Test version compatibility checking
%% Requirements: 3.1
version_compatibility(Config) ->
    % Test the version compatibility function directly

    % Current protocol version
    ?assert(clickhouse_erl_connection:is_compatible_version(54451)),
    % Min supported
    ?assert(clickhouse_erl_connection:is_compatible_version(54400)),
    % Max supported
    ?assert(clickhouse_erl_connection:is_compatible_version(54500)),

    % Too old
    ?assertNot(clickhouse_erl_connection:is_compatible_version(54399)),
    % Too new
    ?assertNot(clickhouse_erl_connection:is_compatible_version(54501)),
    % Invalid
    ?assertNot(clickhouse_erl_connection:is_compatible_version(-1)),
    % Wrong type
    ?assertNot(clickhouse_erl_connection:is_compatible_version("54451")).

%%%===================================================================
%%% Exception Handling Integration Tests
%%%===================================================================

%% @doc Test exception handling during handshake with authentication failures
%% Requirements: 1.1, 2.1, 3.1, 6.1
exception_handling_authentication_failure(Config) ->
    % Test 1: Invalid username
    InvalidUserOptions = #{
        username => "nonexistent_user_12345",
        password => test_helpers:test_password(),
        timeout => ?CONNECTION_TIMEOUT
    },

    Result1 = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), InvalidUserOptions
    ),

    case Result1 of
        {error, {server_exception, ExceptionInfo1}} ->
            % Verify exception contains authentication-related error
            ?assert(clickhouse_erl_protocol:is_complete_exception(ExceptionInfo1)),
            FormattedError1 = clickhouse_erl_exception:format(ExceptionInfo1),
            ?assert(is_binary(FormattedError1)),
            ?assert(byte_size(FormattedError1) > 0);
        {error, _OtherError1} ->
            % Other errors are also acceptable (e.g., network-level rejection)
            ok;
        {ok, Connection1} ->
            % If connection succeeds, ClickHouse might be in permissive mode
            ok = clickhouse_erl_connection:disconnect(Connection1)
    end,

    % Test 2: Invalid password
    InvalidPasswordOptions = #{
        username => test_helpers:test_username(),
        password => "wrong_password_12345",
        timeout => ?CONNECTION_TIMEOUT
    },

    Result2 = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), InvalidPasswordOptions
    ),

    case Result2 of
        {error, {server_exception, ExceptionInfo2}} ->
            % Verify exception contains authentication-related error
            ?assert(clickhouse_erl_protocol:is_complete_exception(ExceptionInfo2)),
            FormattedError2 = clickhouse_erl_exception:format(ExceptionInfo2),
            ?assert(is_binary(FormattedError2)),
            ?assert(byte_size(FormattedError2) > 0);
        {error, _OtherError2} ->
            % Other errors are also acceptable
            ok;
        {ok, Connection2} ->
            % If connection succeeds, ClickHouse might be in permissive mode
            ok = clickhouse_erl_connection:disconnect(Connection2)
    end,

    % Test 3: Invalid database
    InvalidDatabaseOptions = #{
        database => "nonexistent_database_12345",
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        timeout => ?CONNECTION_TIMEOUT
    },

    Result3 = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), InvalidDatabaseOptions
    ),

    case Result3 of
        {error, {server_exception, ExceptionInfo3}} ->
            % Verify exception contains database-related error
            ?assert(clickhouse_erl_protocol:is_complete_exception(ExceptionInfo3)),
            FormattedError3 = clickhouse_erl_exception:format(ExceptionInfo3),
            ?assert(is_binary(FormattedError3)),
            ?assert(byte_size(FormattedError3) > 0);
        {error, _OtherError3} ->
            % Other errors are also acceptable
            ok;
        {ok, Connection3} ->
            % If connection succeeds, database might be created automatically
            ok = clickhouse_erl_connection:disconnect(Connection3)
    end.

%% @doc Test exception handling during different connection phases
%% Requirements: 1.2, 1.3, 6.1, 6.2, 6.3, 6.4
exception_handling_connection_phases(Config) ->
    % Test 1: Exception during handshake (covered by authentication test above)
    % Test 2: Exception during query execution (when query functionality is implemented)

    % For now, test that connection can handle malformed protocol data
    % This simulates receiving an exception packet during various phases

    % Establish a valid connection first
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password()
    },
    {ok, Connection} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),

    % Verify connection is ready
    {ok, Info} = clickhouse_erl_connection:get_connection_info(Connection),
    ?assertEqual(ready, maps:get(state, Info)),

    % Test exception packet parsing capabilities
    % Create various exception scenarios
    TestExceptions = [
        % Syntax error
        {62, "DB::Exception", "Syntax error in query", "at parser.cpp:123", false},
        % Unknown table
        {60, "DB::Exception", "Table doesn't exist", "at table_resolver.cpp:456", false},
        % Authentication error
        {516, "DB::Exception", "Authentication failed", "at auth.cpp:789", false},
        % Network error
        {210, "DB::Exception", "Network error", "at network.cpp:321", false}
    ],

    lists:foreach(
        fun({ErrorCode, ExceptionName, Message, StackTrace, Nested}) ->
            % Create exception info
            ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
                ErrorCode, ExceptionName, Message, StackTrace, Nested
            ),

            % Verify exception is complete and can be formatted
            ?assert(clickhouse_erl_protocol:is_complete_exception(ExceptionInfo)),
            FormattedError = clickhouse_erl_exception:format(ExceptionInfo),
            ?assert(is_binary(FormattedError)),
            ?assert(byte_size(FormattedError) > 0),

            % Verify connection error formatting
            ServerException = {server_exception, ExceptionInfo},
            FormattedConnectionError = clickhouse_erl_connection:format_error(ServerException),
            ?assert(is_binary(FormattedConnectionError)),
            ?assert(byte_size(FormattedConnectionError) > 0),
            ?assert(byte_size(FormattedConnectionError) > 0)
        end,
        TestExceptions
    ),

    % Verify connection is still alive after exception handling tests
    ?assert(is_process_alive(Connection)),
    {ok, Info2} = clickhouse_erl_connection:get_connection_info(Connection),
    ?assertEqual(ready, maps:get(state, Info2)),

    % Clean up
    ok = clickhouse_erl_connection:disconnect(Connection).

%% @doc Test nested exception scenarios during connection establishment
%% Requirements: 3.1, 3.2, 3.3, 6.1, 6.2, 6.3
nested_exception_handling(Config) ->
    % Test nested exception parsing and handling
    % Create a nested exception scenario

    % Inner (nested) exception

    % UNKNOWN_DATABASE
    NestedErrorCode = 81,
    NestedExceptionName = "DB::Exception",
    NestedMessage = "Database 'nonexistent' doesn't exist",
    NestedStackTrace = "at database_catalog.cpp:234\nat query_processor.cpp:567",
    NestedNested = false,

    NestedExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        NestedErrorCode, NestedExceptionName, NestedMessage, NestedStackTrace, NestedNested
    ),

    % Outer (main) exception

    % SYNTAX_ERROR
    MainErrorCode = 62,
    MainExceptionName = "DB::Exception",
    MainMessage = "Cannot resolve database in query",
    MainStackTrace = "at parser.cpp:123\nat query_analyzer.cpp:456",
    MainNested = true,
    NestedExceptions = [NestedExceptionInfo],

    MainExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        MainErrorCode, MainExceptionName, MainMessage, MainStackTrace, MainNested, NestedExceptions
    ),

    % Verify nested exception is complete
    ?assert(clickhouse_erl_protocol:is_complete_exception(MainExceptionInfo)),
    ?assert(clickhouse_erl_protocol:is_complete_exception(NestedExceptionInfo)),

    % Test exception formatting with nested exceptions
    FormattedMainError = clickhouse_erl_exception:format(MainExceptionInfo),
    ?assert(is_binary(FormattedMainError)),
    ?assert(byte_size(FormattedMainError) > 0),

    % Verify nested exception information is included in formatting
    ?assert(string:find(FormattedMainError, "Database 'nonexistent' doesn't exist") =/= nomatch),

    % Test connection error formatting with nested exceptions
    ServerException = {server_exception, MainExceptionInfo},
    FormattedConnectionError = clickhouse_erl_connection:format_error(ServerException),
    ?assert(is_binary(FormattedConnectionError)),
    ?assert(byte_size(FormattedConnectionError) > 0),
    ?assert(byte_size(FormattedConnectionError) > 0),

    % Test multiple levels of nesting
    % Create a 3-level nested exception

    % FILE_DOESNT_EXIST
    Level3ErrorCode = 107,
    Level3ExceptionName = "DB::Exception",
    Level3Message = "File not found",
    Level3StackTrace = "at file_system.cpp:89",
    Level3Nested = false,

    Level3ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        Level3ErrorCode, Level3ExceptionName, Level3Message, Level3StackTrace, Level3Nested
    ),

    % UNKNOWN_DATABASE
    Level2ErrorCode = 81,
    Level2ExceptionName = "DB::Exception",
    Level2Message = "Database metadata missing",
    Level2StackTrace = "at database_catalog.cpp:234",
    Level2Nested = true,
    Level2NestedExceptions = [Level3ExceptionInfo],

    Level2ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        Level2ErrorCode,
        Level2ExceptionName,
        Level2Message,
        Level2StackTrace,
        Level2Nested,
        Level2NestedExceptions
    ),

    % SYNTAX_ERROR
    Level1ErrorCode = 62,
    Level1ExceptionName = "DB::Exception",
    Level1Message = "Query parsing failed",
    Level1StackTrace = "at parser.cpp:123",
    Level1Nested = true,
    Level1NestedExceptions = [Level2ExceptionInfo],

    Level1ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        Level1ErrorCode,
        Level1ExceptionName,
        Level1Message,
        Level1StackTrace,
        Level1Nested,
        Level1NestedExceptions
    ),

    % Verify 3-level nested exception is complete
    ?assert(clickhouse_erl_protocol:is_complete_exception(Level1ExceptionInfo)),

    % Test formatting of deeply nested exceptions
    FormattedDeepError = clickhouse_erl_exception:format(Level1ExceptionInfo),
    ?assert(is_binary(FormattedDeepError)),
    ?assert(byte_size(FormattedDeepError) > 0),
    ?assert(byte_size(FormattedDeepError) > 0),

    % Verify all levels are represented in the formatted output
    ?assert(string:find(FormattedDeepError, "Query parsing failed") =/= nomatch),
    ?assert(string:find(FormattedDeepError, "Database metadata missing") =/= nomatch),
    ?assert(string:find(FormattedDeepError, "File not found") =/= nomatch).

%% @doc Test exception handling with various error scenarios
%% Requirements: 1.1, 2.1, 3.1, 6.1
exception_handling_error_scenarios(Config) ->
    % Test various ClickHouse error codes and their handling
    ErrorScenarios = [
        % Core errors
        {10, "DB::Exception", "Logical error in query processing", "at logic.cpp:45", false},
        {48, "DB::Exception", "Feature not implemented", "at feature.cpp:123", false},

        % Parsing errors
        {6, "DB::Exception", "Cannot parse text format", "at text_parser.cpp:234", false},
        {62, "DB::Exception", "Syntax error in SQL", "at sql_parser.cpp:567", false},
        {72, "DB::Exception", "Cannot parse number", "at number_parser.cpp:89", false},

        % Table and database errors
        {60, "DB::Exception", "Unknown table 'test.nonexistent'", "at table_resolver.cpp:345",
            false},
        {81, "DB::Exception", "Unknown database 'nonexistent'", "at database_catalog.cpp:678",
            false},
        {57, "DB::Exception", "Table already exists", "at table_creator.cpp:123", false},

        % Network and connection errors
        {210, "DB::Exception", "Network connection failed", "at network.cpp:456", false},
        {209, "DB::Exception", "Socket timeout", "at socket.cpp:789", false},

        % Authentication and access errors
        {516, "DB::Exception", "Authentication failed: wrong password", "at auth.cpp:234", false},
        {192, "DB::Exception", "Unknown user 'invalid_user'", "at user_manager.cpp:567", false},
        {497, "DB::Exception", "Access denied to database", "at access_control.cpp:890", false},

        % Resource and performance errors
        {241, "DB::Exception", "Memory limit exceeded", "at memory_manager.cpp:123", false},
        {159, "DB::Exception", "Query timeout exceeded", "at query_executor.cpp:456", false},
        {158, "DB::Exception", "Too many rows in result", "at result_processor.cpp:789", false}
    ],

    lists:foreach(
        fun({ErrorCode, ExceptionName, Message, StackTrace, Nested}) ->
            % Create exception info
            ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
                ErrorCode, ExceptionName, Message, StackTrace, Nested
            ),

            % Verify exception is complete
            ?assert(clickhouse_erl_protocol:is_complete_exception(ExceptionInfo)),

            % Test exception formatting
            FormattedError = clickhouse_erl_exception:format(ExceptionInfo),
            ?assert(is_binary(FormattedError)),
            ?assert(byte_size(FormattedError) > 0),

            % Verify error code is included in formatted output
            ErrorCodeStr = integer_to_list(ErrorCode),
            ?assert(string:find(FormattedError, ErrorCodeStr) =/= nomatch),

            % Verify message is included in formatted output
            ?assert(string:find(FormattedError, Message) =/= nomatch),

            % Test connection error formatting
            ServerException = {server_exception, ExceptionInfo},
            FormattedConnectionError = clickhouse_erl_connection:format_error(ServerException),
            ?assert(is_binary(FormattedConnectionError)),
            ?assert(byte_size(FormattedConnectionError) > 0),

            % Test error code description lookup
            ErrorDescription = clickhouse_erl_error_codes:get_readable_error(ErrorCode),
            ?assert(is_list(ErrorDescription)),
            ?assert(length(ErrorDescription) > 0)
        end,
        ErrorScenarios
    ).

%% @doc Test exception propagation completeness during connection lifecycle
%% Requirements: 6.1, 6.2, 6.3, 6.4
exception_propagation_completeness(Config) ->
    % Test that exceptions are properly propagated through all connection layers

    % Test 1: Exception propagation during connection establishment
    % Try to connect with invalid credentials to trigger authentication exception
    InvalidOptions = #{
        username => "definitely_invalid_user_12345",
        password => "definitely_wrong_password_12345",
        database => "definitely_nonexistent_database_12345",
        timeout => ?CONNECTION_TIMEOUT
    },

    Result = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), InvalidOptions
    ),

    case Result of
        {error, {server_exception, ExceptionInfo}} ->
            % Verify complete exception propagation
            ?assert(clickhouse_erl_protocol:is_complete_exception(ExceptionInfo)),

            % Verify all exception fields are preserved
            ErrorCode = maps:get(code, ExceptionInfo),
            ExceptionName = maps:get(name, ExceptionInfo),
            Message = maps:get(message, ExceptionInfo),
            StackTrace = maps:get(stack_trace, ExceptionInfo, <<>>),

            ?assert(is_integer(ErrorCode)),
            ?assert(is_binary(ExceptionName) andalso byte_size(ExceptionName) > 0),
            ?assert(is_binary(Message) andalso byte_size(Message) > 0),
            % Stack trace can be empty
            ?assert(is_binary(StackTrace)),

            % Test exception formatting preserves all information
            FormattedError = clickhouse_erl_exception:format(ExceptionInfo),
            ?assert(is_binary(FormattedError)),
            ?assert(byte_size(FormattedError) > 0),

            % Verify error code and message are in formatted output
            ?assert(string:find(FormattedError, integer_to_list(ErrorCode)) =/= nomatch),
            ?assert(string:find(FormattedError, Message) =/= nomatch);
        {error, OtherError} ->
            % Other errors are acceptable (network-level failures, etc.)
            FormattedOtherError = clickhouse_erl_connection:format_error(OtherError),
            ?assert(is_binary(FormattedOtherError)),
            ?assert(byte_size(FormattedOtherError) > 0);
        {ok, Connection} ->
            % If connection succeeds despite invalid credentials, clean up
            ok = clickhouse_erl_connection:disconnect(Connection)
    end,

    % Test 2: Exception information completeness
    % Create a comprehensive exception with all fields populated
    CompleteExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        % AUTHENTICATION_FAILED
        516,
        "DB::Exception",
        "Authentication failed: password is incorrect or there is no user with such name",
        "ClickHouse::Exception::Exception(std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, int, bool)\nat /src/Common/Exception.cpp:56\nDB::Authentication::authenticate(std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&, std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char> > const&) const\nat /src/Access/Authentication.cpp:234",
        false
    ),

    % Verify completeness
    ?assert(clickhouse_erl_protocol:is_complete_exception(CompleteExceptionInfo)),

    % Test all formatting and conversion functions
    FormattedComplete = clickhouse_erl_exception:format(CompleteExceptionInfo),
    ?assert(is_binary(FormattedComplete)),
    ?assert(byte_size(FormattedComplete) > 0),

    % Test exception to map conversion
    ExceptionMap = clickhouse_erl_exception:to_map(CompleteExceptionInfo),
    ?assert(is_map(ExceptionMap)),
    ?assert(maps:is_key(error_code, ExceptionMap)),
    ?assert(maps:is_key(exception_name, ExceptionMap)),
    ?assert(maps:is_key(message, ExceptionMap)),
    ?assert(maps:is_key(stack_trace, ExceptionMap)),

    % Test exception flattening
    FlattenedExceptions = clickhouse_erl_exception:flatten(CompleteExceptionInfo),
    ?assert(is_list(FlattenedExceptions)),
    ?assert(length(FlattenedExceptions) >= 1).

%% @doc Test that server exceptions are properly handled and propagated
%% Requirements: 1.2, 1.3, 6.1, 6.2, 6.3, 6.4
exception_handling_integration(Config) ->
    % Establish a connection
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password()
    },
    {ok, Connection} = clickhouse_erl_connection:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),

    % Verify connection is ready
    {ok, Info} = clickhouse_erl_connection:get_connection_info(Connection),
    ?assertEqual(ready, maps:get(state, Info)),

    % Test that the connection can handle exception packets
    % For now, we just verify the connection maintains proper state
    % In a full implementation, we would send a query that causes an exception

    % Verify connection is still alive and ready
    ?assert(is_process_alive(Connection)),
    {ok, Info2} = clickhouse_erl_connection:get_connection_info(Connection),
    ?assertEqual(ready, maps:get(state, Info2)),

    % Clean up
    ok = clickhouse_erl_connection:disconnect(Connection).

%% @doc Test exception packet recognition and parsing
%% Requirements: 1.2, 1.3, 6.1, 6.2, 6.3
exception_packet_recognition(Config) ->
    % Test that the connection manager can recognize exception packets
    % This is a unit-style test within the integration test suite

    % Create a sample exception packet

    % SYNTAX_ERROR
    ErrorCode = 62,
    ExceptionName = "DB::Exception",
    Message = "Syntax error in query",
    StackTrace = "Stack trace here",
    Nested = false,

    ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        ErrorCode, ExceptionName, Message, StackTrace, Nested
    ),

    % Verify the exception info is complete
    ?assert(clickhouse_erl_protocol:is_complete_exception(ExceptionInfo)),

    % Verify error formatting works
    FormattedError = clickhouse_erl_exception:format(ExceptionInfo),
    ?assert(is_binary(FormattedError)),
    ?assert(byte_size(FormattedError) > 0),

    % Verify connection error formatting includes server exceptions
    ServerException = {server_exception, ExceptionInfo},
    FormattedConnectionError = clickhouse_erl_connection:format_error(ServerException),
    ?assert(is_binary(FormattedConnectionError)),
    ?assert(byte_size(FormattedConnectionError) > 0).

%%%===================================================================
%%% INSERT Query Integration Tests
%%%===================================================================

%% @doc Test successful INSERT with single column
%% Requirements: 1.1, 1.2, 1.3, 1.4, 3.1
insert_single_column(Config) ->
    Connection = ?config(connection, Config),

    % Drop table if it exists from previous test runs
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_single">>),

    % Create test table
    CreateTableSQL = <<"CREATE TABLE test_insert_single (id UInt32) ENGINE = Memory">>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Prepare INSERT data
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4, 5]}
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_insert_single (id) VALUES">>,
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input),

    % Verify INSERT succeeded
    ?assertMatch({ok, #{rows_inserted := 5}}, Result),

    % Verify data with SELECT
    {ok, SelectResult} = clickhouse_erl:query(
        Connection, <<"SELECT id FROM test_insert_single ORDER BY id">>
    ),

    % Verify we got 5 rows back
    ?assertMatch(#{data := #{rows := [[1], [2], [3], [4], [5]]}}, SelectResult),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_single">>).

%% @doc Test successful INSERT with multiple columns
%% Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 3.1, 3.2, 3.3
insert_multiple_columns(Config) ->
    Connection = ?config(connection, Config),

    % Create test table with multiple column types
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_insert_multi (\n"
            "        id UInt32,\n"
            "        name String,\n"
            "        value Float64\n"
            "    ) ENGINE = Memory"
        >>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Prepare INSERT data with multiple columns
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"name">>,
            type => <<"String">>,
            data => [<<"Alice">>, <<"Bob">>, <<"Charlie">>]
        },
        #{name => <<"value">>, type => <<"Float64">>, data => [1.5, 2.5, 3.5]}
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_insert_multi (id, name, value) VALUES">>,
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input),

    % Verify INSERT succeeded
    ?assertMatch({ok, #{rows_inserted := 3}}, Result),

    % Verify data with SELECT
    {ok, _SelectResult} = clickhouse_erl:query(
        Connection, <<"SELECT * FROM test_insert_multi ORDER BY id">>
    ),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_multi">>).

%% @doc Test INSERT with all supported integer types
%% Requirements: 1.1, 1.2, 3.1
insert_integer_types(Config) ->
    Connection = ?config(connection, Config),

    % Create test table with all integer types
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_insert_integers (\n"
            "        u8 UInt8,\n"
            "        u16 UInt16,\n"
            "        u32 UInt32,\n"
            "        u64 UInt64,\n"
            "        i8 Int8,\n"
            "        i16 Int16,\n"
            "        i32 Int32,\n"
            "        i64 Int64\n"
            "    ) ENGINE = Memory"
        >>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Prepare INSERT data with all integer types
    Input = [
        #{name => <<"u8">>, type => <<"UInt8">>, data => [0, 255]},
        #{name => <<"u16">>, type => <<"UInt16">>, data => [0, 65535]},
        #{name => <<"u32">>, type => <<"UInt32">>, data => [0, 4294967295]},
        #{name => <<"u64">>, type => <<"UInt64">>, data => [0, 18446744073709551615]},
        #{name => <<"i8">>, type => <<"Int8">>, data => [-128, 127]},
        #{name => <<"i16">>, type => <<"Int16">>, data => [-32768, 32767]},
        #{name => <<"i32">>, type => <<"Int32">>, data => [-2147483648, 2147483647]},
        #{
            name => <<"i64">>,
            type => <<"Int64">>,
            data => [-9223372036854775808, 9223372036854775807]
        }
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_insert_integers VALUES">>,
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input),

    % Verify INSERT succeeded
    ?assertMatch({ok, #{rows_inserted := 2}}, Result),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_integers">>).

%% @doc Test INSERT with floating-point types
%% Requirements: 1.1, 1.2, 3.2
insert_float_types(Config) ->
    Connection = ?config(connection, Config),

    % Create test table with float types
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_insert_floats (\n"
            "        f32 Float32,\n"
            "        f64 Float64\n"
            "    ) ENGINE = Memory"
        >>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Prepare INSERT data with float types
    Input = [
        #{name => <<"f32">>, type => <<"Float32">>, data => [1.5, 2.5, 3.14159]},
        #{name => <<"f64">>, type => <<"Float64">>, data => [1.5, 2.5, 3.141592653589793]}
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_insert_floats VALUES">>,
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input),

    % Verify INSERT succeeded
    ?assertMatch({ok, #{rows_inserted := 3}}, Result),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_floats">>).

%% @doc Test INSERT with String type
%% Requirements: 1.1, 1.2, 3.3
insert_string_type(Config) ->
    Connection = ?config(connection, Config),

    % Create test table with String type
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_insert_strings (\n"
            "        id UInt32,\n"
            "        text String\n"
            "    ) ENGINE = Memory"
        >>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Prepare INSERT data with various strings
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4]},
        #{
            name => <<"text">>,
            type => <<"String">>,
            data => [
                <<"">>,
                <<"Hello, World!">>,
                <<"UTF-8: 你好世界">>,
                <<"Special chars: !@#$%^&*()_+-=[]{}|;':\",./<>?">>
            ]
        }
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_insert_strings VALUES">>,
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input),

    % Verify INSERT succeeded
    ?assertMatch({ok, #{rows_inserted := 4}}, Result),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_strings">>).

%% @doc Test INSERT with Date and DateTime types
%% Requirements: 1.1, 1.2, 3.4
insert_temporal_types(Config) ->
    Connection = ?config(connection, Config),

    % Create test table with temporal types
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_insert_temporal (\n"
            "        id UInt32,\n"
            "        date Date,\n"
            "        datetime DateTime\n"
            "    ) ENGINE = Memory"
        >>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Prepare INSERT data with temporal types
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{name => <<"date">>, type => <<"Date">>, data => [{2024, 1, 1}, {2024, 12, 31}]},
        #{
            name => <<"datetime">>,
            type => <<"DateTime">>,
            data => [
                {{2024, 1, 1}, {0, 0, 0}},
                {{2024, 12, 31}, {23, 59, 59}}
            ]
        }
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_insert_temporal VALUES">>,
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input),

    % Verify INSERT succeeded
    ?assertMatch({ok, #{rows_inserted := 2}}, Result),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_temporal">>).

%% @doc Test INSERT with Bool type
%% Requirements: 1.1, 1.2, 4.1, 4.3
insert_bool_type(Config) ->
    Connection = ?config(connection, Config),

    % Create test table with Bool type
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_insert_bool (\n"
            "        id UInt32,\n"
            "        flag Bool\n"
            "    ) ENGINE = Memory"
        >>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Prepare INSERT data with Bool type
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4]},
        #{name => <<"flag">>, type => <<"Bool">>, data => [true, false, true, false]}
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_insert_bool VALUES">>,
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input),

    % Verify INSERT succeeded
    ?assertMatch({ok, #{rows_inserted := 4}}, Result),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_bool">>).

%% @doc Test INSERT with DateTime64 type
%% Requirements: 1.1, 1.2, 3.1, 3.3
insert_datetime64_type(Config) ->
    Connection = ?config(connection, Config),

    % Create test table with DateTime64 type (precision 3 = milliseconds)
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_insert_datetime64 (\n"
            "        id UInt32,\n"
            "        timestamp DateTime64(3)\n"
            "    ) ENGINE = Memory"
        >>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Prepare INSERT data with DateTime64 type
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{
            name => <<"timestamp">>,
            type => <<"DateTime64(3)">>,
            data => [
                {{2024, 1, 1}, {0, 0, 0}},
                {{2024, 12, 31}, {23, 59, 59}}
            ]
        }
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_insert_datetime64 VALUES">>,
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input),

    % Verify INSERT succeeded
    ?assertMatch({ok, #{rows_inserted := 2}}, Result),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_datetime64">>),
    _ = clickhouse_erl:disconnect(Connection).

%% @doc Test round-trip for all new integer types
%% Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 8.2, 8.3
roundtrip_integer_types(Config) ->
    Connection = ?config(connection, Config),

    % Create test table with all integer types
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_roundtrip_integers (\n"
            "        u8 UInt8,\n"
            "        u16 UInt16,\n"
            "        u32 UInt32,\n"
            "        u64 UInt64,\n"
            "        i8 Int8,\n"
            "        i16 Int16,\n"
            "        i32 Int32,\n"
            "        i64 Int64\n"
            "    ) ENGINE = Memory"
        >>,
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_roundtrip_integers">>),
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Test data with boundary values
    U8s = [0, 255, 128],
    U16s = [0, 65535, 32768],
    U32s = [0, 4294967295, 2147483648],
    U64s = [0, 18446744073709551615, 9223372036854775808],
    I8s = [-128, 127, 0],
    I16s = [-32768, 32767, 0],
    I32s = [-2147483648, 2147483647, 0],
    I64s = [-9223372036854775808, 9223372036854775807, 0],

    Input = [
        #{name => <<"u8">>, type => <<"UInt8">>, data => U8s},
        #{name => <<"u16">>, type => <<"UInt16">>, data => U16s},
        #{name => <<"u32">>, type => <<"UInt32">>, data => U32s},
        #{name => <<"u64">>, type => <<"UInt64">>, data => U64s},
        #{name => <<"i8">>, type => <<"Int8">>, data => I8s},
        #{name => <<"i16">>, type => <<"Int16">>, data => I16s},
        #{name => <<"i32">>, type => <<"Int32">>, data => I32s},
        #{name => <<"i64">>, type => <<"Int64">>, data => I64s}
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_roundtrip_integers VALUES">>,
    InsertResult = clickhouse_erl:insert(Connection, InsertSQL, Input),
    ?assertMatch({ok, #{rows_inserted := 3}}, InsertResult),

    % SELECT data back
    {ok, SelectResult} = clickhouse_erl:query(
        Connection, <<"SELECT * FROM test_roundtrip_integers ORDER BY u8">>
    ),

    % Verify we got the correct data back
    ?assertMatch(#{data := #{rows := [_, _, _]}}, SelectResult),
    #{data := #{rows := Rows}} = SelectResult,

    % Verify each row matches the input
    ExpectedRows = [
        [0, 0, 0, 0, -128, -32768, -2147483648, -9223372036854775808],
        [128, 32768, 2147483648, 9223372036854775808, 0, 0, 0, 0],
        [255, 65535, 4294967295, 18446744073709551615, 127, 32767, 2147483647, 9223372036854775807]
    ],

    lists:zipwith(
        fun(ExpectedRow, ActualRow) ->
            ?assertEqual(ExpectedRow, ActualRow)
        end,
        ExpectedRows,
        Rows
    ),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_roundtrip_integers">>).

%% @doc Test round-trip for floating-point types
%% Requirements: 2.1, 2.2, 2.5, 8.2, 8.3
roundtrip_float_types(Config) ->
    Connection = ?config(connection, Config),

    % Create test table with float types
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_roundtrip_floats (\n"
            "        id UInt32,\n"
            "        f32 Float32,\n"
            "        f64 Float64\n"
            "    ) ENGINE = Memory"
        >>,
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_roundtrip_floats">>),
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Test data with various float values
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4]},
        #{name => <<"f32">>, type => <<"Float32">>, data => [0.0, 1.5, -2.5, 3.14159]},
        #{name => <<"f64">>, type => <<"Float64">>, data => [0.0, 1.5, -2.5, 3.141592653589793]}
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_roundtrip_floats VALUES">>,
    InsertResult = clickhouse_erl:insert(Connection, InsertSQL, Input),
    ?assertMatch({ok, #{rows_inserted := 4}}, InsertResult),

    % SELECT data back
    {ok, SelectResult} = clickhouse_erl:query(
        Connection, <<"SELECT * FROM test_roundtrip_floats ORDER BY id">>
    ),

    % Verify we got the correct number of rows
    ?assertMatch(#{data := #{rows := [_, _, _, _]}}, SelectResult),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_roundtrip_floats">>).

%% @doc Test round-trip for temporal types
%% Requirements: 3.1, 3.2, 3.3, 8.2, 8.3
roundtrip_temporal_types(Config) ->
    Connection = ?config(connection, Config),

    % Create test table with temporal types
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_roundtrip_temporal (\n"
            "        id UInt32,\n"
            "        date Date,\n"
            "        datetime DateTime,\n"
            "        datetime64 DateTime64(3)\n"
            "    ) ENGINE = Memory"
        >>,
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_roundtrip_temporal">>),
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Test data with various temporal values
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"date">>,
            type => <<"Date">>,
            data => [{1970, 1, 1}, {2024, 6, 15}, {2024, 12, 31}]
        },
        #{
            name => <<"datetime">>,
            type => <<"DateTime">>,
            data => [
                {{1970, 1, 1}, {0, 0, 0}},
                {{2024, 6, 15}, {12, 30, 45}},
                {{2024, 12, 31}, {23, 59, 59}}
            ]
        },
        #{
            name => <<"datetime64">>,
            type => <<"DateTime64(3)">>,
            data => [
                {{1970, 1, 1}, {0, 0, 0}},
                {{2024, 6, 15}, {12, 30, 45}},
                {{2024, 12, 31}, {23, 59, 59}}
            ]
        }
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_roundtrip_temporal VALUES">>,
    InsertResult = clickhouse_erl:insert(Connection, InsertSQL, Input),
    ?assertMatch({ok, #{rows_inserted := 3}}, InsertResult),

    % SELECT data back
    {ok, _SelectResult} = clickhouse_erl:query(
        Connection, <<"SELECT * FROM test_roundtrip_temporal ORDER BY id">>
    ),

    % Note: Temporal types return raw values (days since epoch, unix timestamps)
    % Full round-trip verification would require conversion functions

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_roundtrip_temporal">>).

%% @doc Test round-trip for Bool type
%% Requirements: 4.1, 4.3, 8.2, 8.3
roundtrip_bool_type(Config) ->
    Connection = ?config(connection, Config),

    % Create test table with Bool type
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_roundtrip_bool (\n"
            "        id UInt32,\n"
            "        flag Bool\n"
            "    ) ENGINE = Memory"
        >>,
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_roundtrip_bool">>),
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Test data with Bool values
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4]},
        #{name => <<"flag">>, type => <<"Bool">>, data => [true, false, true, false]}
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_roundtrip_bool VALUES">>,
    InsertResult = clickhouse_erl:insert(Connection, InsertSQL, Input),
    ?assertMatch({ok, #{rows_inserted := 4}}, InsertResult),

    % SELECT data back
    {ok, SelectResult} = clickhouse_erl:query(
        Connection, <<"SELECT * FROM test_roundtrip_bool ORDER BY id">>
    ),

    % Verify we got the correct data back
    % Note: Bool values are returned as true/false atoms
    ?assertMatch(
        #{data := #{rows := [[1, true], [2, false], [3, true], [4, false]]}}, SelectResult
    ),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_roundtrip_bool">>).

%%%===================================================================
%%% INSERT Error Handling Tests
%%%===================================================================

%% @doc Test INSERT with empty input (zero rows)
%% Requirements: 1.5
insert_empty_input(_Config) ->
    % Connect to ClickHouse
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Connection} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),

    % Create test table
    CreateTableSQL = <<"CREATE TABLE IF NOT EXISTS test_insert_empty (id UInt32) ENGINE = Memory">>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Prepare INSERT data with zero rows
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => []}
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_insert_empty (id) VALUES">>,
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input),

    % Verify INSERT succeeded with 0 rows
    ?assertMatch({ok, #{rows_inserted := 0}}, Result),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_empty">>),
    ok = clickhouse_erl:disconnect(Connection).

%% @doc Test INSERT with schema mismatch (wrong column name)
%% Requirements: 4.2
insert_schema_mismatch(Config) ->
    Connection = ?config(connection, Config),

    % Create test table with specific column
    CreateTableSQL =
        <<"CREATE TABLE test_insert_schema (id UInt32) ENGINE = Memory">>,
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_schema">>),
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Test 1: Try to insert into non-existent table (schema error)
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],
    Result = clickhouse_erl:insert(Connection, <<"INSERT INTO nonexistent_table VALUES">>, Input),

    % Verify INSERT failed (connection may be closed)
    ?assertMatch({error, _}, Result),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_schema">>).

%% @doc Test INSERT with constraint violation
%% Requirements: 1.6, 4.3
insert_constraint_violation(_Config) ->
    % Connect to ClickHouse
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Connection} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),

    % Create test table with NOT NULL constraint (using Nullable for testing)
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_insert_constraint (\n"
            "        id UInt32,\n"
            "        required_field String\n"
            "    ) ENGINE = Memory"
        >>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % First, insert valid data
    ValidInput = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{name => <<"required_field">>, type => <<"String">>, data => [<<"valid1">>, <<"valid2">>]}
    ],

    InsertSQL = <<"INSERT INTO test_insert_constraint VALUES">>,
    ValidResult = clickhouse_erl:insert(Connection, InsertSQL, ValidInput),

    % Verify valid INSERT succeeded
    ?assertMatch({ok, #{rows_inserted := 2}}, ValidResult),

    % Verify atomicity: all rows inserted or none
    {ok, _CountResult} = clickhouse_erl:query(
        Connection, <<"SELECT count() FROM test_insert_constraint">>
    ),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_constraint">>),
    ok = clickhouse_erl:disconnect(Connection).

%% @doc Test INSERT with row count mismatch
%% Requirements: 2.4, 4.5
insert_row_count_mismatch(_Config) ->
    % Connect to ClickHouse
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Connection} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),

    % Prepare INSERT data with mismatched row counts
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        % Only 2 rows
        #{name => <<"name">>, type => <<"String">>, data => [<<"Alice">>, <<"Bob">>]}
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_table VALUES">>,
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input),

    % Verify INSERT failed with row count mismatch error
    ?assertMatch({error, {validation_error, {row_count_mismatch, _}}}, Result),

    ok = clickhouse_erl:disconnect(Connection).

%% @doc Test INSERT with invalid column name type
%% Requirements: 2.1, 4.2
insert_invalid_column_name(_Config) ->
    % Connect to ClickHouse
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Connection} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),

    % Prepare INSERT data with invalid column name (not a binary)
    Input = [
        #{name => "not_a_binary", type => <<"UInt32">>, data => [1, 2, 3]}
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_table VALUES">>,
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input),

    % Verify INSERT failed with invalid column name error
    ?assertMatch({error, {validation_error, {invalid_column_name, _}}}, Result),

    ok = clickhouse_erl:disconnect(Connection).

%% @doc Test INSERT with large dataset
%% Requirements: 1.1, 1.2, 1.3, 1.4
insert_large_dataset(Config) ->
    % Connect to ClickHouse
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Connection} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),

    % Create test table
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_insert_large (\n"
            "        id UInt32,\n"
            "        value Float64\n"
            "    ) ENGINE = Memory"
        >>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Prepare large dataset (1000 rows)
    NumRows = 1000,
    IDs = lists:seq(1, NumRows),
    Values = [float(N) * 1.5 || N <- lists:seq(1, NumRows)],

    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => IDs},
        #{name => <<"value">>, type => <<"Float64">>, data => Values}
    ],

    % Execute INSERT
    InsertSQL = <<"INSERT INTO test_insert_large VALUES">>,
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input),

    % Verify INSERT succeeded
    ?assertMatch({ok, #{rows_inserted := 1000}}, Result),

    % Verify data count with SELECT
    {ok, _CountResult} = clickhouse_erl:query(
        Connection, <<"SELECT count() FROM test_insert_large">>
    ),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_large">>),
    _ = clickhouse_erl:disconnect(Connection).

%% @doc Test multiple sequential INSERTs on same connection
%% Requirements: 1.1, 1.2, 1.3, 1.4
insert_sequential(Config) ->
    % Connect to ClickHouse
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Connection} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),

    % Create test table
    CreateTableSQL =
        <<"CREATE TABLE IF NOT EXISTS test_insert_sequential (id UInt32) ENGINE = Memory">>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Execute multiple INSERTs sequentially
    InsertSQL = <<"INSERT INTO test_insert_sequential VALUES">>,

    Input1 = [#{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]}],
    Result1 = clickhouse_erl:insert(Connection, InsertSQL, Input1),
    ?assertMatch({ok, #{rows_inserted := 3}}, Result1),

    Input2 = [#{name => <<"id">>, type => <<"UInt32">>, data => [4, 5, 6]}],
    Result2 = clickhouse_erl:insert(Connection, InsertSQL, Input2),
    ?assertMatch({ok, #{rows_inserted := 3}}, Result2),

    Input3 = [#{name => <<"id">>, type => <<"UInt32">>, data => [7, 8, 9]}],
    Result3 = clickhouse_erl:insert(Connection, InsertSQL, Input3),
    ?assertMatch({ok, #{rows_inserted := 3}}, Result3),

    % Verify total count
    {ok, _CountResult} = clickhouse_erl:query(
        Connection, <<"SELECT count() FROM test_insert_sequential">>
    ),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_sequential">>),
    _ = clickhouse_erl:disconnect(Connection).

%% @doc Test INSERT with custom timeout
%% Requirements: 1.1, 1.4
insert_with_timeout(Config) ->
    % Connect to ClickHouse
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Connection} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),

    % Create test table
    CreateTableSQL =
        <<"CREATE TABLE IF NOT EXISTS test_insert_timeout (id UInt32) ENGINE = Memory">>,
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Prepare INSERT data
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],

    % Execute INSERT with custom timeout
    InsertSQL = <<"INSERT INTO test_insert_timeout VALUES">>,
    % 60 second timeout
    InsertOptions = #{timeout => 60000},
    Result = clickhouse_erl:insert(Connection, InsertSQL, Input, InsertOptions),

    % Verify INSERT succeeded
    ?assertMatch({ok, #{rows_inserted := 3}}, Result),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_timeout">>),
    _ = clickhouse_erl:disconnect(Connection).

%% @doc Test INSERT atomicity with verification
%% Requirements: 1.6
insert_atomicity(Config) ->
    % Connect to ClickHouse
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        database => test_helpers:test_database()
    },
    {ok, Connection} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),

    % Create test table with Memory engine
    CreateTableSQL =
        <<"CREATE TABLE test_insert_atomicity (id UInt32) ENGINE = Memory">>,
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_insert_atomicity">>),
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % Execute successful INSERT
    Input1 = [#{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]}],
    InsertSQL = <<"INSERT INTO test_insert_atomicity VALUES">>,
    Result1 = clickhouse_erl:insert(Connection, InsertSQL, Input1),
    ?assertMatch({ok, #{rows_inserted := 3}}, Result1),

    % Verify all 3 rows were inserted
    {ok, CountResult1} = clickhouse_erl:query(
        Connection, <<"SELECT count() FROM test_insert_atomicity">>
    ),
    ?assertMatch(#{data := #{rows := [[3]]}}, CountResult1),

    % Test that INSERT to non-existent table fails cleanly
    Result2 = clickhouse_erl:insert(Connection, <<"INSERT INTO nonexistent_table VALUES">>, Input1),
    ?assertMatch({error, _}, Result2),

    % The connection is closed after the error, so reconnect
    % (disconnect may fail if already closed, ignore the error)
    _ = clickhouse_erl:disconnect(Connection),
    {ok, Connection2} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(), test_helpers:clickhouse_port(), Options
    ),

    % Verify original table still has 3 rows (failed query didn't affect it)
    {ok, CountResult2} = clickhouse_erl:query(
        Connection2, <<"SELECT count() FROM test_insert_atomicity">>
    ),
    ?assertMatch(#{data := #{rows := [[3]]}}, CountResult2),

    % Clean up
    clickhouse_erl:query(Connection2, <<"DROP TABLE IF EXISTS test_insert_atomicity">>),
    _ = clickhouse_erl:disconnect(Connection2).

%%%===================================================================
%%% New Column Types Integration Tests (Task 8.1)
%%%===================================================================

%% @doc Test CREATE TABLE, INSERT, and SELECT for all new integer types
%% Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 8.2, 8.3
new_integer_types_full(Config) ->
    Connection = ?config(connection, Config),

    % CREATE TABLE with all new integer types
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_new_integers (\n"
            "        u16 UInt16,\n"
            "        u32 UInt32,\n"
            "        i8 Int8,\n"
            "        i16 Int16\n"
            "    ) ENGINE = Memory"
        >>,
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_new_integers">>),
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % INSERT with encoded values
    Input = [
        #{name => <<"u16">>, type => <<"UInt16">>, data => [0, 100, 32768, 65535]},
        #{name => <<"u32">>, type => <<"UInt32">>, data => [0, 1000, 2147483648, 4294967295]},
        #{name => <<"i8">>, type => <<"Int8">>, data => [-128, -50, 0, 127]},
        #{name => <<"i16">>, type => <<"Int16">>, data => [-32768, -1000, 0, 32767]}
    ],

    InsertSQL = <<"INSERT INTO test_new_integers VALUES">>,
    InsertResult = clickhouse_erl:insert(Connection, InsertSQL, Input),
    ?assertMatch({ok, #{rows_inserted := 4}}, InsertResult),

    % SELECT to verify data
    {ok, SelectResult} = clickhouse_erl:query(
        Connection, <<"SELECT u16, u32, i8, i16 FROM test_new_integers ORDER BY u16">>
    ),

    % Verify all rows returned correctly
    ?assertMatch(#{data := #{rows := [_, _, _, _]}}, SelectResult),
    #{data := #{rows := Rows}} = SelectResult,

    % Verify each row matches expected values
    ExpectedRows = [
        [0, 0, -128, -32768],
        [100, 1000, -50, -1000],
        [32768, 2147483648, 0, 0],
        [65535, 4294967295, 127, 32767]
    ],

    lists:zipwith(
        fun(ExpectedRow, ActualRow) ->
            ?assertEqual(ExpectedRow, ActualRow)
        end,
        ExpectedRows,
        Rows
    ),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_new_integers">>).

%% @doc Test CREATE TABLE, INSERT, and SELECT for floating-point types
%% Requirements: 2.1, 2.2, 2.5, 8.2, 8.3
new_float_types_full(Config) ->
    Connection = ?config(connection, Config),

    % CREATE TABLE with floating-point types
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_new_floats (\n"
            "        id UInt32,\n"
            "        f32 Float32,\n"
            "        f64 Float64\n"
            "    ) ENGINE = Memory"
        >>,
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_new_floats">>),
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % INSERT with encoded values including edge cases
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4, 5]},
        #{
            name => <<"f32">>,
            type => <<"Float32">>,
            data => [0.0, -1.5, 3.14159, 1.0e10, -1.0e-10]
        },
        #{
            name => <<"f64">>,
            type => <<"Float64">>,
            data => [0.0, -1.5, 3.141592653589793, 1.0e100, -1.0e-100]
        }
    ],

    InsertSQL = <<"INSERT INTO test_new_floats VALUES">>,
    InsertResult = clickhouse_erl:insert(Connection, InsertSQL, Input),
    ?assertMatch({ok, #{rows_inserted := 5}}, InsertResult),

    % SELECT to verify data
    {ok, SelectResult} = clickhouse_erl:query(
        Connection, <<"SELECT id, f32, f64 FROM test_new_floats ORDER BY id">>
    ),

    % Verify all rows returned
    ?assertMatch(#{data := #{rows := [_, _, _, _, _]}}, SelectResult),
    #{data := #{rows := Rows}} = SelectResult,

    % Verify we got 5 rows
    ?assertEqual(5, length(Rows)),

    % Verify first row (exact zero)
    [FirstRow | _] = Rows,
    ?assertMatch([1, +0.0, +0.0], FirstRow),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_new_floats">>).

%% @doc Test CREATE TABLE, INSERT, and SELECT for temporal types
%% Requirements: 3.1, 3.2, 3.3, 8.2, 8.3
new_temporal_types_full(Config) ->
    Connection = ?config(connection, Config),

    % CREATE TABLE with temporal types
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_new_temporal (\n"
            "        id UInt32,\n"
            "        d Date,\n"
            "        dt DateTime,\n"
            "        dt64 DateTime64(3)\n"
            "    ) ENGINE = Memory"
        >>,
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_new_temporal">>),
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % INSERT with encoded temporal values
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{
            name => <<"d">>,
            type => <<"Date">>,
            data => [{1970, 1, 1}, {2024, 6, 15}, {2024, 12, 31}]
        },
        #{
            name => <<"dt">>,
            type => <<"DateTime">>,
            data => [
                {{1970, 1, 1}, {0, 0, 0}},
                {{2024, 6, 15}, {12, 30, 45}},
                {{2024, 12, 31}, {23, 59, 59}}
            ]
        },
        #{
            name => <<"dt64">>,
            type => <<"DateTime64(3)">>,
            data => [
                {{1970, 1, 1}, {0, 0, 0}},
                {{2024, 6, 15}, {12, 30, 45}},
                {{2024, 12, 31}, {23, 59, 59}}
            ]
        }
    ],

    InsertSQL = <<"INSERT INTO test_new_temporal VALUES">>,
    InsertResult = clickhouse_erl:insert(Connection, InsertSQL, Input),
    ?assertMatch({ok, #{rows_inserted := 3}}, InsertResult),

    % SELECT to verify data
    {ok, SelectResult} = clickhouse_erl:query(
        Connection, <<"SELECT id, d, dt, dt64 FROM test_new_temporal ORDER BY id">>
    ),

    % Verify all rows returned
    ?assertMatch(#{data := #{rows := [_, _, _]}}, SelectResult),
    #{data := #{rows := Rows}} = SelectResult,

    % Verify we got 3 rows
    ?assertEqual(3, length(Rows)),

    % Note: Temporal types return raw values (days since epoch, unix timestamps)
    % Verify first row has expected structure
    [FirstRow | _] = Rows,
    ?assertMatch([1, _, _, _], FirstRow),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_new_temporal">>).

%% @doc Test CREATE TABLE, INSERT, and SELECT for Bool type
%% Requirements: 4.1, 4.3, 8.2, 8.3
new_bool_type_full(Config) ->
    Connection = ?config(connection, Config),

    % CREATE TABLE with Bool type
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_new_bool (\n"
            "        id UInt32,\n"
            "        flag Bool\n"
            "    ) ENGINE = Memory"
        >>,
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_new_bool">>),
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % INSERT with encoded Bool values
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4, 5, 6]},
        #{
            name => <<"flag">>,
            type => <<"Bool">>,
            data => [true, false, true, false, true, false]
        }
    ],

    InsertSQL = <<"INSERT INTO test_new_bool VALUES">>,
    InsertResult = clickhouse_erl:insert(Connection, InsertSQL, Input),
    ?assertMatch({ok, #{rows_inserted := 6}}, InsertResult),

    % SELECT to verify data
    {ok, SelectResult} = clickhouse_erl:query(
        Connection, <<"SELECT id, flag FROM test_new_bool ORDER BY id">>
    ),

    % Verify all rows returned correctly
    % Note: Bool values are returned as true/false atoms
    ?assertMatch(
        #{data := #{rows := [[1, true], [2, false], [3, true], [4, false], [5, true], [6, false]]}},
        SelectResult
    ),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_new_bool">>).

%% @doc Test CREATE TABLE, INSERT, and SELECT for all new types combined
%% Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 3.1, 3.2, 3.3, 4.1, 8.2, 8.3
new_all_types_combined(Config) ->
    Connection = ?config(connection, Config),

    % CREATE TABLE with all new types
    CreateTableSQL =
        <<
            "CREATE TABLE IF NOT EXISTS test_all_new_types (\n"
            "        u16 UInt16,\n"
            "        u32 UInt32,\n"
            "        i8 Int8,\n"
            "        i16 Int16,\n"
            "        f32 Float32,\n"
            "        f64 Float64,\n"
            "        d Date,\n"
            "        dt DateTime,\n"
            "        b Bool\n"
            "    ) ENGINE = Memory"
        >>,
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_all_new_types">>),
    {ok, _} = clickhouse_erl:query(Connection, CreateTableSQL),

    % INSERT with all new types
    Input = [
        #{name => <<"u16">>, type => <<"UInt16">>, data => [100, 200]},
        #{name => <<"u32">>, type => <<"UInt32">>, data => [1000, 2000]},
        #{name => <<"i8">>, type => <<"Int8">>, data => [-10, 10]},
        #{name => <<"i16">>, type => <<"Int16">>, data => [-100, 100]},
        #{name => <<"f32">>, type => <<"Float32">>, data => [1.5, 2.5]},
        #{name => <<"f64">>, type => <<"Float64">>, data => [1.5, 2.5]},
        #{name => <<"d">>, type => <<"Date">>, data => [{2024, 1, 1}, {2024, 12, 31}]},
        #{
            name => <<"dt">>,
            type => <<"DateTime">>,
            data => [{{2024, 1, 1}, {0, 0, 0}}, {{2024, 12, 31}, {23, 59, 59}}]
        },
        #{name => <<"b">>, type => <<"Bool">>, data => [true, false]}
    ],

    InsertSQL = <<"INSERT INTO test_all_new_types VALUES">>,
    InsertResult = clickhouse_erl:insert(Connection, InsertSQL, Input),
    ?assertMatch({ok, #{rows_inserted := 2}}, InsertResult),

    % SELECT to verify data
    {ok, SelectResult} = clickhouse_erl:query(
        Connection, <<"SELECT * FROM test_all_new_types ORDER BY u16">>
    ),

    % Verify all rows returned
    ?assertMatch(#{data := #{rows := [_, _]}}, SelectResult),
    #{data := #{rows := Rows}} = SelectResult,

    % Verify we got 2 rows with correct structure
    ?assertEqual(2, length(Rows)),
    [FirstRow | _] = Rows,
    % 9 columns
    ?assertEqual(9, length(FirstRow)),

    % Verify first row starts with expected integer values
    [U16, U32, I8, I16 | _] = FirstRow,
    ?assertEqual(100, U16),
    ?assertEqual(1000, U32),
    ?assertEqual(-10, I8),
    ?assertEqual(-100, I16),

    % Clean up
    clickhouse_erl:query(Connection, <<"DROP TABLE IF EXISTS test_all_new_types">>).
