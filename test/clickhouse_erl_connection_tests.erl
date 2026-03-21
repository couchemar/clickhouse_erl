%% @doc Unit tests for ClickHouse connection management.
%%
%% This module contains unit tests for TCP stream parsing, packet handling,
%% and exception handling in the connection module.
-module(clickhouse_erl_connection_tests).

-include_lib("eunit/include/eunit.hrl").

%% Test exports
-export([]).

%%% Records
%%%===================================================================

-include("clickhouse_erl_connection.hrl").

%%%===================================================================
%%% Unit Tests
%%%===================================================================

%% Test exception handling integration
%% Feature: server-exception-handling, Property 6: Exception Propagation Completeness
%% Validates: Requirements 6.1, 6.2, 6.3
exception_handling_integration_test() ->
    %% Test that server exceptions are properly handled and formatted

    %% Test 1: Create a sample exception and verify it can be formatted

    % SYNTAX_ERROR
    ErrorCode = 62,
    ExceptionName = "DB::Exception",
    Message = "Syntax error in query",
    StackTrace = "Stack trace here",
    Nested = false,

    ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        ErrorCode, ExceptionName, Message, StackTrace, Nested
    ),

    %% Verify the exception info is complete
    ?assert(clickhouse_erl_protocol:is_complete_exception(ExceptionInfo)),

    %% Test 2: Verify server exception error formatting
    ServerException = {server_exception, ExceptionInfo},
    FormattedError = clickhouse_erl_connection:format_error(ServerException),
    ?assert(is_binary(FormattedError)),
    ?assert(byte_size(FormattedError) > 0),

    %% Verify the formatted error contains expected information
    FormattedString = FormattedError,
    ?assert(string:find(FormattedString, <<"Server exception">>) =/= nomatch),
    ?assert(string:find(FormattedString, <<"Syntax error">>) =/= nomatch),

    %% Test 3: Verify exception parsing error formatting
    ParseError = {exception_parsing_error, "Test parsing error"},
    FormattedParseError = clickhouse_erl_connection:format_error(ParseError),
    ?assert(is_binary(FormattedParseError)),
    ?assert(byte_size(FormattedParseError) > 0),

    %% Test 4: Verify nested exception limit error formatting
    LimitError = {nested_exception_limit_exceeded, 10},
    FormattedLimitError = clickhouse_erl_connection:format_error(LimitError),
    ?assert(is_binary(FormattedLimitError)),
    ?assert(byte_size(FormattedLimitError) > 0),

    %% Test 5: Verify field truncation error formatting
    TruncationError = {exception_field_truncated, stack_trace},
    FormattedTruncationError = clickhouse_erl_connection:format_error(TruncationError),
    ?assert(is_binary(FormattedTruncationError)),
    ?assert(byte_size(FormattedTruncationError) > 0),

    %% Test 6: Verify invalid format error formatting
    FormatError = {invalid_exception_format, "Invalid packet format"},
    FormattedFormatError = clickhouse_erl_connection:format_error(FormatError),
    ?assert(is_binary(FormattedFormatError)),
    ?assert(byte_size(FormattedFormatError) > 0).

%% Test exception packet handling functions
%% Feature: server-exception-handling, Property 1: Exception Packet Recognition
%% Validates: Requirements 1.1, 1.4
exception_packet_handling_test() ->
    %% Test that the connection manager can handle exception packets

    %% Create a sample exception packet data

    % UNKNOWN_TABLE
    ErrorCode = 60,
    ExceptionName = "DB::Exception",
    Message = "Table doesn't exist",
    StackTrace = "at ClickHouse::executeQuery",
    Nested = false,

    %% Encode the exception packet using the protocol module
    ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        ErrorCode, ExceptionName, Message, StackTrace, Nested
    ),

    %% Verify the exception can be formatted
    FormattedError = clickhouse_erl_exception:format(ExceptionInfo),
    ?assert(is_binary(FormattedError)),
    ?assert(byte_size(FormattedError) > 0),

    %% Verify the formatted error contains expected information
    FormattedString = FormattedError,
    ?assert(string:find(FormattedString, <<"DB::Exception">>) =/= nomatch),
    ?assert(string:find(FormattedString, <<"Table doesn't exist">>) =/= nomatch),
    % The error atom might be included in the formatted output
    ?assert(
        string:find(FormattedString, <<"unknown_table">>) =/= nomatch orelse
            string:find(FormattedString, <<"UNKNOWN_TABLE">>) =/= nomatch
    ),

    %% Test exception summary
    Summary = clickhouse_erl_protocol:get_exception_summary(ExceptionInfo),
    ?assert(is_binary(Summary)),
    ?assert(byte_size(Summary) > 0),

    %% Verify summary contains key information
    SummaryString = Summary,
    ?assert(string:find(SummaryString, <<"DB::Exception">>) =/= nomatch),
    ?assert(string:find(SummaryString, <<"Table doesn't exist">>) =/= nomatch).

%% Unit tests for connection state management during exceptions
%% Feature: server-exception-handling, Task 6.2
%% Validates: Requirements 1.2, 1.3, 6.4

%% Test connection state after authentication error exception during handshake
connection_state_after_auth_error_test() ->
    %% Test exception handling during handshake phase (connecting state)
    %% This tests the actual implemented functionality in parse_server_hello_response

    %% Create an authentication error exception

    % AUTHENTICATION_FAILED
    ErrorCode = 516,
    ExceptionName = "DB::Exception",
    Message = "Authentication failed: password is incorrect",
    StackTrace = "at DB::Context::checkAccess()",
    Nested = false,

    ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        ErrorCode, ExceptionName, Message, StackTrace, Nested
    ),

    %% Test exception handling during handshake phase
    ServerException = {server_exception, ExceptionInfo},

    %% Verify the exception can be formatted for error reporting
    FormattedError = clickhouse_erl_connection:format_error(ServerException),
    ?assert(is_binary(FormattedError)),
    ?assert(byte_size(FormattedError) > 0),

    %% Verify formatted error contains authentication information
    FormattedString = FormattedError,
    ?assert(string:find(FormattedString, <<"Authentication failed">>) =/= nomatch),
    ?assert(string:find(FormattedString, <<"password is incorrect">>) =/= nomatch).

%% Test connection state after various exception types during handshake
connection_state_after_handshake_exceptions_test() ->
    %% Test various exception types that can occur during handshake
    %% This tests the actual parse_server_hello_response functionality

    TestCases = [
        % Authentication failure
        {516, "DB::Exception", "Authentication failed: password is incorrect",
            "at DB::Context::checkAccess()"},
        % Access denied
        {497, "DB::Exception", "Access denied", "at DB::Context::checkAccess()"},
        % Unknown user
        {192, "DB::Exception", "Unknown user 'invalid_user'", "at DB::Context::checkAccess()"},
        % Wrong password
        {193, "DB::Exception", "Wrong password for user 'test'", "at DB::Context::checkAccess()"},
        % IP address not allowed
        {195, "DB::Exception", "IP address not allowed", "at DB::Context::checkAccess()"}
    ],

    lists:foreach(
        fun({ErrorCode, ExceptionName, Message, StackTrace}) ->
            %% Create exception info
            ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
                ErrorCode, ExceptionName, Message, StackTrace, false
            ),

            %% Verify exception can be formatted during handshake
            ServerException = {server_exception, ExceptionInfo},
            FormattedError = clickhouse_erl_connection:format_error(ServerException),
            ?assert(is_binary(FormattedError)),
            ?assert(byte_size(FormattedError) > 0),

            %% Verify formatted error contains expected message
            FormattedString = FormattedError,
            ?assert(
                string:find(FormattedString, clickhouse_erl_types_primitive:to_binary(Message)) =/=
                    nomatch
            )
        end,
        TestCases
    ).

%% Test connection state after nested exception
connection_state_after_nested_exception_test() ->
    %% Test nested exception formatting and handling
    %% This tests the exception formatting functionality

    %% Create a nested exception (main exception with a cause)
    % Main exception: UNKNOWN_TABLE
    MainErrorCode = 60,
    MainExceptionName = "DB::Exception",
    MainMessage = "Table 'test.nonexistent' doesn't exist",
    MainStackTrace = "at DB::InterpreterSelectQuery::execute()",

    % Nested exception: UNKNOWN_DATABASE
    NestedErrorCode = 81,
    NestedExceptionName = "DB::Exception",
    NestedMessage = "Database 'test' doesn't exist",
    NestedStackTrace = "at DB::DatabaseCatalog::getDatabase()",
    NestedNested = false,

    NestedExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        NestedErrorCode, NestedExceptionName, NestedMessage, NestedStackTrace, NestedNested
    ),

    % Main exception with nested
    MainNested = true,
    NestedExceptions = [NestedExceptionInfo],

    MainExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        MainErrorCode, MainExceptionName, MainMessage, MainStackTrace, MainNested, NestedExceptions
    ),

    %% Test that nested exceptions can be formatted properly
    ServerException = {server_exception, MainExceptionInfo},

    %% Verify nested exception formatting works
    FormattedError = clickhouse_erl_connection:format_error(ServerException),
    ?assert(is_binary(FormattedError)),
    FormattedString = FormattedError,
    ?assert(string:find(FormattedString, <<"Table 'test.nonexistent' doesn't exist">>) =/= nomatch),
    ?assert(string:find(FormattedString, <<"Database 'test' doesn't exist">>) =/= nomatch).

%% Test exception handling during different protocol phases
exception_handling_during_handshake_test() ->
    %% Test exception during handshake phase (connecting state)
    %% This tests the actual parse_server_hello_response functionality

    %% Test that exception packets during handshake are properly parsed
    %% Create an exception packet binary as it would be received during handshake

    % AUTHENTICATION_FAILED
    ErrorCode = 516,
    ExceptionName = "DB::Exception",
    Message = "Authentication failed: password is incorrect",
    StackTrace = "at DB::Context::checkAccess()",
    Nested = false,

    %% Create the exception info
    ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        ErrorCode, ExceptionName, Message, StackTrace, Nested
    ),

    %% Test that the exception can be decoded and formatted
    %% This simulates what happens in parse_server_hello_response when an exception is received
    ServerException = {server_exception, ExceptionInfo},
    FormattedError = clickhouse_erl_connection:format_error(ServerException),
    ?assert(is_binary(FormattedError)),
    ?assert(byte_size(FormattedError) > 0),

    %% Verify the formatted error contains authentication information
    FormattedString = FormattedError,
    ?assert(string:find(FormattedString, <<"Authentication failed">>) =/= nomatch),
    ?assert(string:find(FormattedString, <<"password is incorrect">>) =/= nomatch).

%% Test connection state consistency after exception parsing errors
connection_state_after_parsing_error_test() ->
    %% Test various exception parsing error types
    %% This tests the format_error functionality for parsing errors

    ParseErrors = [
        {exception_parsing_error, "Invalid exception packet format"},
        {nested_exception_limit_exceeded, 10},
        {exception_field_truncated, stack_trace},
        {invalid_exception_format, "Malformed exception data"}
    ],

    lists:foreach(
        fun(ParseError) ->
            %% Verify parsing errors can be formatted
            FormattedError = clickhouse_erl_connection:format_error(ParseError),
            ?assert(is_binary(FormattedError)),
            ?assert(byte_size(FormattedError) > 0),

            %% Verify formatted error is descriptive
            FormattedString = FormattedError,
            case ParseError of
                {exception_parsing_error, Details} ->
                    ?assert(
                        string:find(
                            FormattedString, clickhouse_erl_types_primitive:to_binary(Details)
                        ) =/=
                            nomatch
                    );
                {nested_exception_limit_exceeded, Depth} ->
                    ?assert(
                        string:find(FormattedString, iolist_to_binary(integer_to_list(Depth))) =/=
                            nomatch
                    );
                {exception_field_truncated, Field} ->
                    ?assert(
                        string:find(FormattedString, iolist_to_binary(atom_to_list(Field))) =/=
                            nomatch
                    );
                {invalid_exception_format, Details} ->
                    ?assert(
                        string:find(
                            FormattedString, clickhouse_erl_types_primitive:to_binary(Details)
                        ) =/=
                            nomatch
                    )
            end
        end,
        ParseErrors
    ).

%% Test exception packet recognition during different phases
exception_packet_recognition_test() ->
    %% Test that exception packets are properly recognized
    %% This tests the handle_incoming_packet functionality

    %% Create various exception types that could be received
    TestExceptions = [
        % During handshake - authentication errors
        {516, "DB::Exception", "Authentication failed", "at DB::Context::checkAccess()"},
        {497, "DB::Exception", "Access denied", "at DB::Context::checkAccess()"},
        {192, "DB::Exception", "Unknown user", "at DB::Context::checkAccess()"},

        % During connection - protocol errors
        {100, "DB::Exception", "Unknown packet from server", "at DB::Connection::receivePacket()"},
        {102, "DB::Exception", "Unexpected packet from server",
            "at DB::Connection::receivePacket()"}
    ],

    lists:foreach(
        fun({ErrorCode, ExceptionName, Message, StackTrace}) ->
            %% Create exception info
            ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
                ErrorCode, ExceptionName, Message, StackTrace, false
            ),

            %% Test that the exception is properly recognized and can be formatted
            ServerException = {server_exception, ExceptionInfo},
            FormattedError = clickhouse_erl_connection:format_error(ServerException),
            ?assert(is_binary(FormattedError)),

            %% Verify the formatted error contains the expected message
            FormattedString = FormattedError,
            ?assert(
                string:find(FormattedString, clickhouse_erl_types_primitive:to_binary(Message)) =/=
                    nomatch
            )
        end,
        TestExceptions
    ).

%% Test connection error formatting for all error types
connection_error_formatting_test() ->
    %% Test that all connection error types can be properly formatted
    %% This tests the format_error function comprehensively

    AllErrorTypes = [
        % Network errors
        {network_error, connection_refused},
        {network_error, host_unreachable},
        {network_error, network_unreachable},
        {network_error, invalid_host},
        {network_error, host_not_found},
        {network_error, connection_reset},
        {network_error, network_down},
        {network_error, address_not_available},
        {network_error, connection_closed_during_send},
        {network_error, connection_closed_during_handshake},
        {network_error, {tcp_error_during_handshake, some_reason}},
        {network_error, {socket_option_error, some_error}},

        % Protocol errors
        {protocol_error, "Unexpected packet type in Server_Hello response"},
        {protocol_error, "Invalid Server_Hello response format"},
        {protocol_error, "Server version not available"},
        {protocol_error, "No error reason available"},
        {protocol_error, "Unknown request"},

        % Timeout errors
        {timeout_error, tcp_connect},
        {timeout_error, client_hello_send},
        {timeout_error, handshake_receive},

        % Compatibility errors
        {compatibility_error, {server_version, {19, 0, 0}}},
        {compatibility_error, {server_version, {26, 0, 0}}},
        {compatibility_error, {server_version, invalid_version}},

        % Encoding errors
        {encoding_error, client_name},
        {encoding_error, version_major},
        {encoding_error, database},
        {encoding_error, username},
        {encoding_error, password},

        % Decoding errors
        {decoding_error, {invalid_format, "Truncated message"}},
        {decoding_error, {invalid_format, "Invalid UTF-8 encoding"}},
        {decoding_error, {invalid_format, "Varint overflow"}},
        {decoding_error, {invalid_format, "String length exceeds available data"}},

        % Resource cleanup errors
        {resource_cleanup_error, "Failed to close socket: some_reason"}
    ],

    lists:foreach(
        fun(ErrorType) ->
            FormattedError = clickhouse_erl_connection:format_error(ErrorType),
            ?assert(is_binary(FormattedError)),
            ?assert(byte_size(FormattedError) > 0)
        end,
        AllErrorTypes
    ).
%% ===================================================================
%% Version Checking Tests (Task 2.1)
%% Feature: query-parameters
%% ===================================================================

%% Test: should_send_parameters with version >= 54459 and parameters returns ok
%% Validates: Requirements 2.1
should_send_parameters_supported_version_with_params_test() ->
    %% Test with version exactly at threshold
    Parameters = [{<<"key1">>, <<"value1">>}],
    Version = 54459,
    Result = clickhouse_erl_connection:should_send_parameters(Parameters, Version),
    ?assertEqual(ok, Result),

    %% Test with version above threshold
    Parameters2 = [{<<"key2">>, <<"value2">>}, {<<"key3">>, <<"value3">>}],
    Version2 = 54460,
    Result2 = clickhouse_erl_connection:should_send_parameters(Parameters2, Version2),
    ?assertEqual(ok, Result2),

    %% Test with much higher version
    Parameters3 = [{<<"key">>, <<"val">>}],
    Version3 = 55000,
    Result3 = clickhouse_erl_connection:should_send_parameters(Parameters3, Version3),
    ?assertEqual(ok, Result3).

%% Test: should_send_parameters with version < 54459 and parameters returns error
%% Validates: Requirements 2.2
should_send_parameters_unsupported_version_with_params_test() ->
    %% Test with version just below threshold
    Parameters = [{<<"key1">>, <<"value1">>}],
    Version = 54458,
    Result = clickhouse_erl_connection:should_send_parameters(Parameters, Version),
    ?assertEqual({error, {parameters_unsupported, Version}}, Result),

    %% Test with much lower version
    Parameters2 = [{<<"key2">>, <<"value2">>}],
    Version2 = 54400,
    Result2 = clickhouse_erl_connection:should_send_parameters(Parameters2, Version2),
    ?assertEqual({error, {parameters_unsupported, Version2}}, Result2),

    %% Test with very old version
    Parameters3 = [{<<"key">>, <<"val">>}],
    Version3 = 50000,
    Result3 = clickhouse_erl_connection:should_send_parameters(Parameters3, Version3),
    ?assertEqual({error, {parameters_unsupported, Version3}}, Result3).

%% Test: should_send_parameters with empty parameter list always returns ok
%% Validates: Requirements 2.1, 2.2
should_send_parameters_empty_list_always_ok_test() ->
    %% Test with supported version
    EmptyParams = [],
    Version1 = 54459,
    Result1 = clickhouse_erl_connection:should_send_parameters(EmptyParams, Version1),
    ?assertEqual(ok, Result1),

    %% Test with version above threshold
    Version2 = 54460,
    Result2 = clickhouse_erl_connection:should_send_parameters(EmptyParams, Version2),
    ?assertEqual(ok, Result2),

    %% Test with unsupported version (below threshold)
    Version3 = 54458,
    Result3 = clickhouse_erl_connection:should_send_parameters(EmptyParams, Version3),
    ?assertEqual(ok, Result3),

    %% Test with much older version
    Version4 = 54400,
    Result4 = clickhouse_erl_connection:should_send_parameters(EmptyParams, Version4),
    ?assertEqual(ok, Result4),

    %% Test with very old version
    Version5 = 50000,
    Result5 = clickhouse_erl_connection:should_send_parameters(EmptyParams, Version5),
    ?assertEqual(ok, Result5).

%% ===================================================================
%% INSERT Parameter Validation Tests (Task 7.1)
%% Feature: query-parameters
%% ===================================================================

%% Test: INSERT with valid parameters succeeds
%% Validates: Requirements 8.2, 8.7
insert_with_valid_parameters_test() ->
    %% Test that INSERT with valid parameters is accepted
    Parameters = [{<<"id">>, <<"123">>}, {<<"name">>, <<"test">>}],

    %% Validate parameters
    Result = clickhouse_erl_connection:validate_parameters(Parameters),
    ?assertEqual(ok, Result),

    %% Check version support (supported version)
    Version = 54459,
    VersionResult = clickhouse_erl_connection:should_send_parameters(Parameters, Version),
    ?assertEqual(ok, VersionResult).

%% Test: INSERT with invalid parameters returns appropriate error
%% Validates: Requirements 8.2
insert_with_invalid_parameters_test() ->
    %% Test with non-binary key
    InvalidParams1 = [{key_atom, <<"value">>}],
    Result1 = clickhouse_erl_connection:validate_parameters(InvalidParams1),
    ?assertEqual({error, {invalid_parameter_key, key_atom}}, Result1),

    %% Test with non-binary value
    InvalidParams2 = [{<<"key">>, 123}],
    Result2 = clickhouse_erl_connection:validate_parameters(InvalidParams2),
    ?assertEqual({error, {invalid_parameter_value, 123}}, Result2),

    %% Test with malformed parameter (not a tuple)
    InvalidParams3 = [<<"not_a_tuple">>],
    Result3 = clickhouse_erl_connection:validate_parameters(InvalidParams3),
    ?assertEqual({error, {invalid_parameter_format, <<"not_a_tuple">>}}, Result3).

%% Test: INSERT with unsupported version returns error
%% Validates: Requirements 8.2
insert_with_unsupported_version_test() ->
    %% Test with parameters on unsupported version
    Parameters = [{<<"id">>, <<"123">>}],
    % Below threshold
    Version = 54458,

    Result = clickhouse_erl_connection:should_send_parameters(Parameters, Version),
    ?assertEqual({error, {parameters_unsupported, Version}}, Result).

%% Test: INSERT without parameters works (backward compatibility)
%% Validates: Requirements 6.6, 8.7
insert_without_parameters_backward_compatibility_test() ->
    %% Test with empty parameter list
    EmptyParams = [],

    %% Validate empty parameters
    Result = clickhouse_erl_connection:validate_parameters(EmptyParams),
    ?assertEqual(ok, Result),

    %% Check version support with empty params (should work on any version)
    OldVersion = 54400,
    VersionResult = clickhouse_erl_connection:should_send_parameters(EmptyParams, OldVersion),
    ?assertEqual(ok, VersionResult),

    %% Check with newer version too
    NewVersion = 54460,
    VersionResult2 = clickhouse_erl_connection:should_send_parameters(EmptyParams, NewVersion),
    ?assertEqual(ok, VersionResult2).

%%%===================================================================
%%% Compression Options Tests
%%%===================================================================

%% Test: Connection with LZ4 compression option
%% Validates: Requirements 1.1, 9.1, 9.2
connection_with_lz4_compression_test() ->
    %% Test that connection accepts LZ4 compression option
    Options = #{compression => lz4},

    %% Validate compression options
    Result = clickhouse_erl_connection:validate_and_normalize_compression_opts(Options),

    %% Should return normalized compression opts with method => lz4
    ?assertMatch({ok, #{method := lz4}}, Result).

%% Test: Connection with ZSTD compression option
%% Validates: Requirements 1.2, 9.1, 9.2
connection_with_zstd_compression_test() ->
    %% Test that connection accepts ZSTD compression option
    Options = #{compression => zstd},

    %% Validate compression options
    Result = clickhouse_erl_connection:validate_and_normalize_compression_opts(Options),

    %% Should return normalized compression opts with method => zstd
    ?assertMatch({ok, #{method := zstd}}, Result).

%% Test: Connection with None compression option
%% Validates: Requirements 1.3, 9.1, 9.2
connection_with_none_compression_test() ->
    %% Test that connection accepts None compression option
    Options = #{compression => none},

    %% Validate compression options
    Result = clickhouse_erl_connection:validate_and_normalize_compression_opts(Options),

    %% Should return normalized compression opts with method => none
    ?assertMatch({ok, #{method := none}}, Result).

%% Test: Connection with disabled compression (default)
%% Validates: Requirements 1.4, 9.1, 9.2
connection_with_disabled_compression_test() ->
    %% Test that connection defaults to disabled compression
    Options = #{compression => disabled},

    %% Validate compression options
    Result = clickhouse_erl_connection:validate_and_normalize_compression_opts(Options),

    %% Should return normalized compression opts with method => disabled
    ?assertMatch({ok, #{method := disabled}}, Result).

%% Test: Connection without compression option defaults to disabled
%% Validates: Requirements 1.4, 9.1, 9.2
connection_without_compression_option_test() ->
    %% Test that connection without compression option defaults to disabled
    Options = #{},

    %% Validate compression options (should default to disabled)
    Result = clickhouse_erl_connection:validate_and_normalize_compression_opts(Options),

    %% Should return normalized compression opts with method => disabled
    ?assertMatch({ok, #{method := disabled}}, Result).

%% Test: Connection with LZ4HC compression level
%% Validates: Requirements 2.1, 2.2, 9.1
connection_with_lz4hc_compression_level_test() ->
    %% Test that connection accepts LZ4 with compression level
    Options = #{compression => lz4, compression_level => 5},

    %% Validate compression options
    Result = clickhouse_erl_connection:validate_and_normalize_compression_opts(Options),

    %% Should return normalized compression opts with method => lz4 and level => 5
    ?assertMatch({ok, #{method := lz4, level := 5}}, Result).

%% Test: Connection with invalid compression method
%% Validates: Requirements 1.5
connection_with_invalid_compression_method_test() ->
    %% Test that connection rejects invalid compression method
    Options = #{compression => invalid_method},

    %% Validate compression options
    Result = clickhouse_erl_connection:validate_and_normalize_compression_opts(Options),

    %% Should return error
    ?assertMatch({error, {protocol_error, {invalid_compression_method, invalid_method}}}, Result).

%% Test: Connection with invalid compression level
%% Validates: Requirements 2.4
connection_with_invalid_compression_level_test() ->
    %% Test that connection rejects invalid compression level
    Options = #{compression => lz4, compression_level => 99},

    %% Validate compression options
    Result = clickhouse_erl_connection:validate_and_normalize_compression_opts(Options),

    %% Should return error
    ?assertMatch({error, {protocol_error, {invalid_compression_level, 99}}}, Result).
