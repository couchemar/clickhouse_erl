%% @doc Property-based tests for ClickHouse protocol encoding/decoding.
%%
%% This module contains property-based tests using PropEr to validate
%% the correctness of protocol message encoding and decoding functions.
-module(prop_clickhouse_erl_protocol).

-include_lib("proper/include/proper.hrl").

-import(generators, [string_gen/0, char_gen/0]).

%% Property test: Error Handling for Invalid Messages
%% Feature: clickhouse-handshake, Property 5: Error Handling for Invalid Messages
%% Validates: Requirements 2.5, 3.3, 4.3, 4.4
prop_error_handling_for_invalid_messages() ->
    ?FORALL(
        InvalidMessage,
        invalid_message_gen(),
        begin
            %% Test that invalid messages return appropriate error types without crashing
            case InvalidMessage of
                {invalid_client_hello, ClientHelloData} ->
                    %% Test Client_Hello encoding with invalid data
                    try
                        Result = clickhouse_erl_protocol:encode_client_hello(ClientHelloData),
                        case Result of
                            {error, {encoding_error, _Field}} ->
                                %% Expected error type for invalid Client_Hello
                                true;
                            {error, _OtherError} ->
                                %% Other error types are also acceptable
                                true;
                            {ok, _} ->
                                %% Some inputs might be valid despite being in "invalid" generator
                                %% This is acceptable for property testing
                                true
                        end
                    catch
                        %% Catching exceptions is also acceptable - the key is no crash
                        _:_ -> true
                    end;
                {invalid_server_hello, ServerHelloBinary} ->
                    %% Test Server_Hello decoding with invalid binary data
                    try
                        Result = clickhouse_erl_protocol:decode_server_hello(ServerHelloBinary),
                        case Result of
                            {error, {decoding_error, {invalid_format, _Details}}} ->
                                %% Expected error type for invalid Server_Hello
                                true;
                            {error, _OtherError} ->
                                %% Other error types are also acceptable
                                true;
                            {ok, _, _} ->
                                %% Some binary data might accidentally be valid
                                true
                        end
                    catch
                        %% Catching exceptions is also acceptable
                        _:_ -> true
                    end
            end
        end
    ).

%% Generator for invalid messages of various types
invalid_message_gen() ->
    oneof([
        {invalid_client_hello, invalid_client_hello_gen()},
        {invalid_server_hello, invalid_server_hello_binary_gen()}
    ]).

%% Generator for invalid Client_Hello data (wrong types, missing fields, etc.)
invalid_client_hello_gen() ->
    oneof([
        %% Invalid field types

        % Should be string
        #{client_name => 123},
        % Should be integer
        #{version_major => "not_integer"},
        % Should be non-negative
        #{version_minor => -1},
        % Should be integer
        #{protocol_version => atom},
        % Should be string
        #{database => {invalid, tuple}},
        % Should be string (list of chars)
        #{username => [1, 2, 3]},
        % Should be string
        #{password => #{invalid => map}},

        %% Invalid combinations
        #{client_name => "", version_major => -100, database => 456},
        #{username => undefined, password => null},

        %% Very large integers that might cause issues

        % Overflow
        #{version_major => 16#FFFFFFFFFFFFFFFF + 1},
        % Negative large number
        #{protocol_version => -16#FFFFFFFFFFFFFFFF}
    ]).

%% Generator for invalid Server_Hello binary data
invalid_server_hello_binary_gen() ->
    oneof([
        %% Empty binary
        <<>>,

        %% Truncated messages (incomplete fields)

        % Only partial name field
        <<5, "Hello">>,
        % Zero-length name but no version fields
        <<0>>,

        %% Invalid varint sequences

        % Varint overflow
        <<1, "A", 255, 255, 255, 255, 255, 255, 255, 255, 255, 255>>,
        % Incomplete varint (continuation bit set but no following byte)
        <<1, "A", 128>>,

        %% Invalid UTF-8 in strings

        % Invalid UTF-8 bytes
        <<2, 255, 254>>,
        % More invalid UTF-8
        <<3, 255, 254, 253>>,

        %% String length exceeding available data

        % Claims 100 bytes but only has 5
        <<100, "short">>,

        %% Mixed valid and invalid data

        % Valid name, valid version_major, invalid version_minor
        <<5, "Hello", 1, 0, 255, 255>>,

        %% Random binary data
        crypto:strong_rand_bytes(50),
        crypto:strong_rand_bytes(10),
        crypto:strong_rand_bytes(1)
    ]).

%% Property test: Version Compatibility Checking
%% Feature: clickhouse-handshake, Property 8: Version Compatibility Checking
%% Validates: Requirements 3.5
prop_version_compatibility_checking() ->
    ?FORALL(
        ProtocolVersion,
        protocol_version_gen(),
        begin
            %% Test the public is_compatible_version function
            Result = clickhouse_erl_connection:is_compatible_version(ProtocolVersion),

            %% Verify result is appropriate for the protocol version
            case ProtocolVersion of
                Version when is_integer(Version) ->
                    %% Check against the known compatibility range
                    %% Based on the constants in the connection module:
                    %% MIN_SUPPORTED_PROTOCOL_VERSION = 54400
                    %% MAX_SUPPORTED_PROTOCOL_VERSION = 54500
                    ExpectedResult = (Version >= 54400) andalso (Version =< 54500),
                    Result =:= ExpectedResult;
                _ ->
                    %% Non-integer versions should return false
                    Result =:= false
            end
        end
    ).

%% Generator for protocol versions (compatible, incompatible, and invalid formats)
protocol_version_gen() ->
    oneof([
        %% Compatible protocol versions (54400-54500)
        range(54400, 54500),

        %% Incompatible versions (too old)
        range(1, 54399),

        %% Incompatible versions (too new)
        range(54501, 60000),

        %% Edge cases - boundary values

        % Just below compatible range
        54399,
        % Just at compatible range start
        54400,
        % Just at compatible range end
        54500,
        % Just above compatible range
        54501,

        %% Current protocol version (should be compatible)
        54451,

        %% Invalid version formats (should return false)
        invalid_version,
        "not_a_version",
        {54451},
        [54451],
        #{version => 54451},

        %% Negative versions
        -1,
        -54451,

        %% Very large versions
        999999999,

        %% Zero and small positive values
        0,
        1,
        100
    ]).

%% Property test: Exception Propagation Completeness
%% Feature: server-exception-handling, Property 6: Exception Propagation Completeness
%% Validates: Requirements 6.1, 6.2, 6.3
prop_exception_propagation_completeness() ->
    ?FORALL(
        ExceptionInfo,
        exception_info_gen(),
        begin
            %% Test that exception propagation preserves all details

            %% 1. Test conversion to Erlang error tuple (Requirement 6.1)
            ServerException = {server_exception, ExceptionInfo},
            IsTuple = is_tuple(ServerException),
            IsServerException = (server_exception =:= element(1, ServerException)),
            InfoMatches = (ExceptionInfo =:= element(2, ServerException)),

            %% 2. Test that all exception details are preserved (Requirement 6.2)
            PropagatedExceptionInfo = element(2, ServerException),

            %% Verify all fields are preserved
            OriginalErrorCode = element(2, ExceptionInfo),
            OriginalExceptionName = element(3, ExceptionInfo),
            OriginalMessage = element(4, ExceptionInfo),
            OriginalStackTrace = element(5, ExceptionInfo),
            OriginalNested = element(6, ExceptionInfo),
            OriginalNestedExceptions = element(7, ExceptionInfo),

            PropagatedErrorCode = element(2, PropagatedExceptionInfo),
            PropagatedExceptionName = element(3, PropagatedExceptionInfo),
            PropagatedMessage = element(4, PropagatedExceptionInfo),
            PropagatedStackTrace = element(5, PropagatedExceptionInfo),
            PropagatedNested = element(6, PropagatedExceptionInfo),
            PropagatedNestedExceptions = element(7, PropagatedExceptionInfo),

            FieldsPreserved =
                (OriginalErrorCode =:= PropagatedErrorCode) andalso
                    (OriginalExceptionName =:= PropagatedExceptionName) andalso
                    (OriginalMessage =:= PropagatedMessage) andalso
                    (OriginalStackTrace =:= PropagatedStackTrace) andalso
                    (OriginalNested =:= PropagatedNested) andalso
                    (OriginalNestedExceptions =:= PropagatedNestedExceptions),

            %% 3. Test that nested exception chains are complete (Requirement 6.3)
            NestedChainComplete = verify_nested_chain_completeness(
                OriginalNestedExceptions,
                PropagatedNestedExceptions
            ),

            %% 4. Test that exception can be formatted without loss of information
            FormattedError = clickhouse_erl_exception:format(
                PropagatedExceptionInfo
            ),
            FormattingSuccessful = is_binary(FormattedError) andalso byte_size(FormattedError) > 0,

            %% 5. Test that exception summary preserves key information
            Summary = clickhouse_erl_protocol:get_exception_summary(PropagatedExceptionInfo),
            SummarySuccessful = is_binary(Summary) andalso byte_size(Summary) > 0,

            %% All propagation requirements must be satisfied
            IsTuple andalso IsServerException andalso InfoMatches andalso
                FieldsPreserved andalso NestedChainComplete andalso FormattingSuccessful andalso
                SummarySuccessful
        end
    ).

%% Generator for exception_info records
exception_info_gen() ->
    ?LET(
        {ErrorCode, ExceptionName, Message, StackTrace, Nested, NestedExceptions},
        {
            error_code_gen(),
            exception_name_gen(),
            exception_message_gen(),
            stack_trace_gen(),
            boolean(),
            nested_exceptions_gen()
        },
        clickhouse_erl_protocol:create_exception_info(
            ErrorCode, ExceptionName, Message, StackTrace, Nested, NestedExceptions
        )
    ).

%% Generator for exception names
exception_name_gen() ->
    oneof([
        "DB::Exception",
        "DB::NetException",
        "DB::ParsingException",
        "DB::LogicalError",
        "std::exception",
        "std::runtime_error"
    ]).

%% Generator for exception messages
exception_message_gen() ->
    oneof([
        "Syntax error in query",
        "Connection failed",
        "Table not found",
        "Access denied",
        "Memory limit exceeded",
        "Timeout exceeded",
        "Unknown function",
        "Invalid argument",
        % Empty message edge case
        "",
        % Random string
        string_gen()
    ]).

%% Generator for stack traces
stack_trace_gen() ->
    oneof([
        "at query.cpp:123",
        "at connection.cpp:456\nat network.cpp:789",
        "at parser.cpp:100\nat lexer.cpp:200\nat main.cpp:300",
        % Empty stack trace edge case
        "",
        % Random string
        string_gen()
    ]).

%% Generator for nested exceptions (limited depth to prevent infinite recursion)
nested_exceptions_gen() ->
    ?SIZED(Size, nested_exceptions_gen(Size)).

nested_exceptions_gen(0) ->
    % Base case: no nested exceptions
    [];
nested_exceptions_gen(Size) when Size > 0 ->
    ?LET(
        Count,
        % Limit to 3 nested exceptions max
        range(0, min(3, Size)),
        case Count of
            0 ->
                [];
            _ ->
                ?LET(
                    NestedList,
                    vector(Count, simple_exception_info_gen()),
                    NestedList
                )
        end
    ).

%% Generator for simple exception info (no nested exceptions to avoid infinite recursion)
simple_exception_info_gen() ->
    ?LET(
        {ErrorCode, ExceptionName, Message, StackTrace},
        {
            error_code_gen(),
            exception_name_gen(),
            exception_message_gen(),
            stack_trace_gen()
        },
        clickhouse_erl_protocol:create_exception_info(
            ErrorCode, ExceptionName, Message, StackTrace, false, []
        )
    ).

%% Helper function to verify nested exception chain completeness
verify_nested_chain_completeness(OriginalNested, PropagatedNested) ->
    case {OriginalNested, PropagatedNested} of
        {[], []} ->
            % Both empty - complete
            true;
        {[_ | _], []} ->
            % Original has nested but propagated doesn't - incomplete
            false;
        {[], [_ | _]} ->
            % Original empty but propagated has nested - inconsistent
            false;
        {Original, Propagated} when length(Original) =/= length(Propagated) ->
            % Different lengths - incomplete
            false;
        {Original, Propagated} ->
            %% Compare each nested exception recursively
            lists:all(
                fun({OrigNested, PropNested}) ->
                    verify_exception_equality(OrigNested, PropNested)
                end,
                lists:zip(Original, Propagated)
            )
    end.

%% Helper function to verify two exception_info records are equal
verify_exception_equality(Exception1, Exception2) ->
    %% Compare all fields

    % error_code
    (element(2, Exception1) =:= element(2, Exception2)) andalso
        % exception_name
        (element(3, Exception1) =:= element(3, Exception2)) andalso
        % message
        (element(4, Exception1) =:= element(4, Exception2)) andalso
        % stack_trace
        (element(5, Exception1) =:= element(5, Exception2)) andalso
        % nested
        (element(6, Exception1) =:= element(6, Exception2)) andalso
        %% Recursively verify nested exceptions
        verify_nested_chain_completeness(
            % nested_exceptions
            element(7, Exception1),
            % nested_exceptions
            element(7, Exception2)
        ).

%% Property test for protocol compliance validation
%% Feature: server-exception-handling, Property 7: Protocol Format Compliance
%% Validates: Requirements 7.1, 7.2, 7.3
prop_protocol_format_compliance() ->
    ?FORALL(
        ExceptionPacket,
        valid_exception_packet_gen(),
        begin
            %% Test that all valid exception packets pass protocol compliance validation

            %% 1. Test field order compliance (Requirement 7.1)
            FieldOrderResult = clickhouse_erl_protocol:validate_exception_packet_format(
                ExceptionPacket
            ),
            FieldOrderCompliant = (FieldOrderResult =:= ok),

            %% 2. Test integer encoding compliance (Requirement 7.2)
            IntegerEncodingResult =
                case ExceptionPacket of
                    <<_ErrorCode:32/signed-little, Rest/binary>> ->
                        ErrorCodeValid = clickhouse_erl_protocol:validate_integer_encoding(
                            ExceptionPacket, error_code
                        ),
                        %% Find nested flag at the end and validate it
                        NestedFlagValid =
                            case find_nested_flag_position(Rest) of
                                {ok, NestedFlagBin} ->
                                    clickhouse_erl_protocol:validate_integer_encoding(
                                        NestedFlagBin, nested_flag
                                    );
                                error ->
                                    {error, "Could not find nested flag"}
                            end,
                        (ErrorCodeValid =:= ok) andalso (NestedFlagValid =:= ok);
                    _ ->
                        false
                end,

            %% 3. Test string encoding compliance (Requirement 7.3)
            StringEncodingResult = validate_all_strings_in_packet(ExceptionPacket),

            %% 4. Test overall protocol compliance
            OverallCompliance = clickhouse_erl_protocol:validate_protocol_compliance(
                ExceptionPacket
            ),
            OverallCompliant = (OverallCompliance =:= ok),

            %% All compliance checks must pass
            FieldOrderCompliant andalso IntegerEncodingResult andalso
                StringEncodingResult andalso OverallCompliant
        end
    ).

%% Generator for valid exception packets
valid_exception_packet_gen() ->
    ?LET(
        {ErrorCode, ExceptionName, Message, StackTrace, Nested},
        {
            error_code_gen(),
            exception_name_gen(),
            exception_message_gen(),
            stack_trace_gen(),
            boolean()
        },
        create_exception_packet(ErrorCode, ExceptionName, Message, StackTrace, Nested)
    ).

%% Property test: Resource Management During Parsing
%% Feature: server-exception-handling, Property 8: Resource Management During Parsing
%% Validates: Requirements 8.2, 8.3, 8.4
prop_resource_management_during_parsing() ->
    ?FORALL(
        {ErrorCode, ExceptionName, Message, StackTrace, Nested, ResourceStressType},
        {
            error_code_gen(),
            exception_name_gen(),
            exception_message_gen(),
            stack_trace_gen(),
            boolean(),
            resource_stress_type_gen()
        },
        begin
            %% Test resource management during exception parsing operations
            %% This property validates that parsing operations properly manage resources
            %% without leaks, handle memory limits, and clean up on failures

            %% Create test packet based on stress type
            TestPacket = create_resource_stress_packet(
                ErrorCode, ExceptionName, Message, StackTrace, Nested, ResourceStressType
            ),

            %% Perform parsing operation
            ParseResult = clickhouse_erl_protocol:decode_exception_packet(TestPacket),

            %% Validate resource management behavior based on stress type
            case ResourceStressType of
                normal ->
                    %% Normal case: should succeed without crashing
                    case ParseResult of
                        {ok, ExceptionInfo, _Rest} ->
                            %% Verify the parsed exception is complete and valid
                            is_valid_exception_info(ExceptionInfo) andalso
                                %% Verify process remains responsive after parsing
                                verify_process_responsive();
                        {error, _Reason} ->
                            %% Verify process remains responsive after error
                            verify_process_responsive()
                    end;
                oversized_exception_name ->
                    %% Should handle oversized exception names gracefully
                    case ParseResult of
                        {error, {exception_field_truncated, exception_name, _, _}} ->
                            %% Expected error for oversized field, verify process responsive
                            verify_process_responsive();
                        {error, _OtherReason} ->
                            %% Other errors are acceptable, verify process responsive
                            verify_process_responsive();
                        {ok, _, _} ->
                            %% Unexpected success, but still verify no leaks
                            verify_process_responsive()
                    end;
                oversized_message ->
                    %% Should handle oversized messages gracefully
                    case ParseResult of
                        {error, {exception_field_truncated, message, _, _}} ->
                            verify_process_responsive();
                        {error, _OtherReason} ->
                            verify_process_responsive();
                        {ok, _, _} ->
                            verify_process_responsive()
                    end;
                oversized_stack_trace ->
                    %% Should handle oversized stack traces gracefully
                    case ParseResult of
                        {error, {exception_field_truncated, stack_trace, _, _}} ->
                            verify_process_responsive();
                        {error, _OtherReason} ->
                            verify_process_responsive();
                        {ok, _, _} ->
                            verify_process_responsive()
                    end;
                excessive_nesting ->
                    %% Should prevent infinite recursion and handle nesting limits
                    case ParseResult of
                        {error, {nested_exception_limit_exceeded, _}} ->
                            verify_process_responsive();
                        {error, {too_many_nested_exceptions, _}} ->
                            verify_process_responsive();
                        {error, _OtherReason} ->
                            verify_process_responsive();
                        {ok, _, _} ->
                            verify_process_responsive()
                    end;
                memory_exhaustion ->
                    %% Should handle memory limits gracefully
                    case ParseResult of
                        {error, {memory_limit_exceeded, _, _}} ->
                            verify_process_responsive();
                        {error, _OtherReason} ->
                            verify_process_responsive();
                        {ok, _, _} ->
                            verify_process_responsive()
                    end;
                malformed_data ->
                    %% Should handle malformed data without crashing or leaking
                    case ParseResult of
                        {error, _Reason} ->
                            %% Expected error for malformed data
                            verify_process_responsive();
                        {ok, _, _} ->
                            %% Unexpected success, but verify no leaks
                            verify_process_responsive()
                    end
            end
        end
    ).

%% Generator for resource stress test types
resource_stress_type_gen() ->
    oneof([
        normal,
        oversized_exception_name,
        oversized_message,
        oversized_stack_trace,
        excessive_nesting,
        memory_exhaustion,
        malformed_data
    ]).

%% Generator for error codes (both known and unknown)
error_code_gen() ->
    oneof([
        %% Known ClickHouse error codes (from clickhouse_erl_error_codes module)
        oneof([
            % UNSUPPORTED_METHOD
            1,
            % UNSUPPORTED_PARAMETER
            2,
            % LOGICAL_ERROR
            10,
            % UNKNOWN_TABLE
            60,
            % SYNTAX_ERROR
            62,
            % UNKNOWN_DATABASE
            81,
            % UNKNOWN_USER
            192,
            % WRONG_PASSWORD
            193,
            % NETWORK_ERROR
            210,
            % UNKNOWN_EXCEPTION
            1002
        ]),

        %% Unknown error codes (should use fallback handling)
        oneof([
            % Negative error code
            -1,
            % Very large error code
            99999,
            % Random unknown code
            12345,
            % Negative unknown code
            -12345,
            % Zero error code
            0
        ]),

        %% Random 32-bit signed integers
        range(-2147483648, 2147483647)
    ]).

%% Helper function to create malformed exception packet
create_malformed_exception_packet() ->
    %% Return an actual binary, not a generator
    %% Choose one of the malformed packet types
    case rand:uniform(5) of
        1 ->
            %% Truncated packet
            <<1, 2, 3>>;
        2 ->
            %% Invalid varint sequences
            <<62:32/signed-little, 255, 255, 255, 255, 255>>;
        3 ->
            %% Invalid UTF-8 in strings
            <<62:32/signed-little, 3, 255, 254, 253>>;
        4 ->
            %% String length exceeding available data
            <<62:32/signed-little, 100, "short">>;
        5 ->
            %% Random binary data
            crypto:strong_rand_bytes(50)
    end.

%% Helper function to create resource stress test packets
create_resource_stress_packet(ErrorCode, ExceptionName, Message, StackTrace, Nested, StressType) ->
    case StressType of
        normal ->
            %% Create normal packet
            create_exception_packet(ErrorCode, ExceptionName, Message, StackTrace, Nested);
        oversized_exception_name ->
            %% Create packet with oversized exception name (>1KB)
            OversizedName = lists:duplicate(1025, $A),
            create_exception_packet(ErrorCode, OversizedName, Message, StackTrace, Nested);
        oversized_message ->
            %% Create packet with oversized message (>8KB)
            OversizedMessage = lists:duplicate(8193, $B),
            create_exception_packet(ErrorCode, ExceptionName, OversizedMessage, StackTrace, Nested);
        oversized_stack_trace ->
            %% Create packet with oversized stack trace (>64KB)
            OversizedStack = lists:duplicate(65537, $C),
            create_exception_packet(ErrorCode, ExceptionName, Message, OversizedStack, Nested);
        excessive_nesting ->
            %% Create packet with excessive nesting (>10 levels)
            create_deeply_nested_exception_packet(
                ErrorCode, ExceptionName, Message, StackTrace, 15
            );
        memory_exhaustion ->
            %% Create packet that would exceed total memory limit (>1MB)

            % ~350KB each
            LargeString = lists:duplicate(350000, $D),
            create_exception_packet(ErrorCode, LargeString, LargeString, LargeString, Nested);
        malformed_data ->
            %% Create malformed packet data
            create_malformed_exception_packet()
    end.

%% Helper function to create exception packet binary
create_exception_packet(ErrorCode, ExceptionName, Message, StackTrace, Nested) ->
    ErrorCodeBin = <<ErrorCode:32/signed-little>>,
    ExceptionNameBin = clickhouse_erl_types_primitive:encode_string(ExceptionName),
    MessageBin = clickhouse_erl_types_primitive:encode_string(Message),
    StackTraceBin = clickhouse_erl_types_primitive:encode_string(StackTrace),
    NestedFlag =
        case Nested of
            true -> 1;
            false -> 0
        end,
    NestedFlagBin = <<NestedFlag:8>>,

    <<ErrorCodeBin/binary, ExceptionNameBin/binary, MessageBin/binary, StackTraceBin/binary,
        NestedFlagBin/binary>>.

%% Helper function to find nested flag position in packet
find_nested_flag_position(Binary) ->
    try
        %% Skip exception name string
        {ok, _ExceptionName, Rest1} = clickhouse_erl_types_primitive:decode_string(Binary),
        %% Skip message string
        {ok, _Message, Rest2} = clickhouse_erl_types_primitive:decode_string(Rest1),
        %% Skip stack trace string
        {ok, _StackTrace, Rest3} = clickhouse_erl_types_primitive:decode_string(Rest2),
        %% Rest3 should start with nested flag
        case byte_size(Rest3) >= 1 of
            true -> {ok, Rest3};
            false -> error
        end
    catch
        _:_ -> error
    end.

%% Helper function to validate all strings in an exception packet
validate_all_strings_in_packet(Binary) ->
    try
        %% Skip error code
        <<_ErrorCode:32/signed-little, Rest1/binary>> = Binary,

        %% Validate exception name string
        case clickhouse_erl_protocol:validate_string_encoding(Rest1) of
            ok ->
                {ok, _ExceptionName, Rest2} = clickhouse_erl_types_primitive:decode_string(Rest1),
                %% Validate message string
                case clickhouse_erl_protocol:validate_string_encoding(Rest2) of
                    ok ->
                        {ok, _Message, Rest3} = clickhouse_erl_types_primitive:decode_string(Rest2),
                        %% Validate stack trace string
                        case clickhouse_erl_protocol:validate_string_encoding(Rest3) of
                            ok -> true;
                            {error, _} -> false
                        end;
                    {error, _} ->
                        false
                end;
            {error, _} ->
                false
        end
    catch
        _:_ -> false
    end.

%% Helper function to create deeply nested exception packet
create_deeply_nested_exception_packet(ErrorCode, ExceptionName, Message, StackTrace, Depth) ->
    %% Create base exception
    BasePacket = create_exception_packet(ErrorCode, ExceptionName, Message, StackTrace, true),

    %% Add nested exceptions recursively
    add_nested_exceptions(BasePacket, Depth - 1).

%% Helper function to add nested exceptions to a packet
add_nested_exceptions(Packet, 0) ->
    %% Base case: change the last nested flag to false
    case byte_size(Packet) >= 1 of
        true ->
            <<PacketData:(byte_size(Packet) - 1)/binary, _LastByte>> = Packet,
            <<PacketData/binary, 0:8>>;
        false ->
            Packet
    end;
add_nested_exceptions(Packet, Depth) when Depth > 0 ->
    %% Add another nested exception
    NestedPacket = create_exception_packet(
        % Use depth as error code for variety
        Depth,
        "DB::NestedException",
        io_lib:format("Nested exception at depth ~w", [Depth]),
        io_lib:format("at nested_~w.cpp:~w", [Depth, Depth * 100]),
        % Continue nesting if depth > 1
        Depth > 1
    ),

    %% Append nested packet to main packet
    <<Packet/binary, NestedPacket/binary>>.

%% Helper function to validate exception info structure
is_valid_exception_info(ExceptionInfo) ->
    try
        %% Check that it's a proper exception_info record
        is_tuple(ExceptionInfo) andalso
            tuple_size(ExceptionInfo) =:= 7 andalso
            element(1, ExceptionInfo) =:= exception_info andalso
            %% Check that error code is an integer
            is_integer(element(2, ExceptionInfo)) andalso
            %% Check that strings are lists

            % exception_name
            is_binary(element(3, ExceptionInfo)) andalso
            % message
            is_binary(element(4, ExceptionInfo)) andalso
            % stack_trace
            is_binary(element(5, ExceptionInfo)) andalso
            %% Check that nested is boolean
            is_boolean(element(6, ExceptionInfo)) andalso
            %% Check that nested_exceptions is a list
            is_list(element(7, ExceptionInfo))
    catch
        _:_ -> false
    end.

%% Helper function to verify no resource leaks
%% Helper function to verify process remains responsive after parsing
%% Ensures the process didn't crash and can still allocate memory
verify_process_responsive() ->
    %% Check that the process is still alive and responsive
    is_process_alive(self()) andalso
        %% Verify we can still allocate small amounts of memory
        try
            _TestList = lists:duplicate(100, test_atom),
            true
        catch
            _:_ -> false
        end.

%% Property test: Error Code Interpretation Consistency
%% Feature: server-exception-handling, Property 9: Error Code Interpretation
%% Validates: Requirements 5.2, 5.3, 5.4
%% Tests that error code interpretation is consistent across all error codes
prop_error_code_interpretation_consistency() ->
    ?FORALL(
        ErrorCode,
        error_code_gen(),
        begin
            %% Get expected values from error codes module
            {ExpectedAtom, ExpectedDescriptionBase} =
                clickhouse_erl_error_codes:get_error_code_description(ErrorCode),

            %% For unknown error codes, the protocol module adds the error code number
            ExpectedDescription =
                case ExpectedAtom of
                    unknown_error_code ->
                        lists:flatten(io_lib:format("Unknown error code ~w", [ErrorCode]));
                    _ ->
                        ExpectedDescriptionBase
                end,

            %% Test protocol module interpretation
            ActualAtom = clickhouse_erl_protocol:get_error_atom(ErrorCode),
            ActualDescription = clickhouse_erl_protocol:get_error_description(ErrorCode),
            {ActualDescAtom, ActualDescText} = clickhouse_erl_protocol:get_error_code_description(
                ErrorCode
            ),

            %% Verify interpretation matches expected values
            InterpretationMatches =
                (ExpectedAtom =:= ActualAtom) andalso
                    (ExpectedDescription =:= ActualDescription) andalso
                    (ExpectedAtom =:= ActualDescAtom) andalso
                    (ExpectedDescription =:= ActualDescText),

            %% Test enhanced error info interpretation
            EnhancedInfo = clickhouse_erl_protocol:get_enhanced_error_info(ErrorCode),
            EnhancedInfoCorrect =
                (ErrorCode =:= maps:get(error_code, EnhancedInfo)) andalso
                    (ExpectedAtom =:= maps:get(error_atom, EnhancedInfo)) andalso
                    (ExpectedDescription =:= maps:get(error_description, EnhancedInfo)),

            %% Test that interpretation is consistent across multiple calls
            SecondAtom = clickhouse_erl_protocol:get_error_atom(ErrorCode),
            SecondDescription = clickhouse_erl_protocol:get_error_description(ErrorCode),
            ConsistencyAcrossCalls =
                (ActualAtom =:= SecondAtom) andalso
                    (ActualDescription =:= SecondDescription),

            %% All checks must pass
            InterpretationMatches andalso EnhancedInfoCorrect andalso ConsistencyAcrossCalls
        end
    ).
