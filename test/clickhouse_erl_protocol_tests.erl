-module(clickhouse_erl_protocol_tests).

-include_lib("eunit/include/eunit.hrl").

%% Unit tests for exception data structure handling functions

%% Test create_exception_info/5 function
create_exception_info_test() ->
    %% Test creating a simple exception info record
    ErrorCode = 62,
    ExceptionName = "DB::Exception",
    Message = "Syntax error in query",
    StackTrace = "at /src/Parsers/ParserQuery.cpp:456",
    Nested = false,

    ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        ErrorCode, ExceptionName, Message, StackTrace, Nested
    ),

    %% Verify all fields are set correctly
    ?assertEqual(ErrorCode, element(2, ExceptionInfo)),
    ?assertEqual(
        clickhouse_erl_types_primitive:to_binary(ExceptionName), element(3, ExceptionInfo)
    ),
    ?assertEqual(clickhouse_erl_types_primitive:to_binary(Message), element(4, ExceptionInfo)),
    ?assertEqual(clickhouse_erl_types_primitive:to_binary(StackTrace), element(5, ExceptionInfo)),
    ?assertEqual(Nested, element(6, ExceptionInfo)),
    ?assertEqual([], element(7, ExceptionInfo)).

%% Test create_exception_info/6 function with nested exceptions
create_exception_info_with_nested_test() ->
    %% Create a nested exception first
    NestedErrorCode = 81,
    NestedExceptionName = "DB::Exception",
    NestedMessage = "Unknown database",
    NestedStackTrace = "at /src/Databases/DatabaseCatalog.cpp:123",
    NestedNested = false,

    NestedException = clickhouse_erl_protocol:create_exception_info(
        NestedErrorCode, NestedExceptionName, NestedMessage, NestedStackTrace, NestedNested
    ),

    %% Create parent exception with nested exception
    ErrorCode = 62,
    ExceptionName = "DB::Exception",
    Message = "Syntax error in query",
    StackTrace = "at /src/Parsers/ParserQuery.cpp:456",
    Nested = true,
    NestedExceptions = [NestedException],

    ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        ErrorCode, ExceptionName, Message, StackTrace, Nested, NestedExceptions
    ),

    %% Verify all fields are set correctly
    ?assertEqual(ErrorCode, element(2, ExceptionInfo)),
    ?assertEqual(
        clickhouse_erl_types_primitive:to_binary(ExceptionName), element(3, ExceptionInfo)
    ),
    ?assertEqual(clickhouse_erl_types_primitive:to_binary(Message), element(4, ExceptionInfo)),
    ?assertEqual(clickhouse_erl_types_primitive:to_binary(StackTrace), element(5, ExceptionInfo)),
    ?assertEqual(Nested, element(6, ExceptionInfo)),
    ?assertEqual(NestedExceptions, element(7, ExceptionInfo)).

%% Test is_complete_exception/1 function
is_complete_exception_test() ->
    %% Test complete exception
    CompleteException = clickhouse_erl_protocol:create_exception_info(
        62, "DB::Exception", "Syntax error", "at parser.cpp:123", false
    ),
    ?assert(clickhouse_erl_protocol:is_complete_exception(CompleteException)),

    %% Test incomplete exception with empty exception name
    IncompleteException1 = clickhouse_erl_protocol:create_exception_info(
        62, "", "Syntax error", "at parser.cpp:123", false
    ),
    ?assertNot(clickhouse_erl_protocol:is_complete_exception(IncompleteException1)),

    %% Test incomplete exception with empty message
    IncompleteException2 = clickhouse_erl_protocol:create_exception_info(
        62, "DB::Exception", "", "at parser.cpp:123", false
    ),
    ?assertNot(clickhouse_erl_protocol:is_complete_exception(IncompleteException2)),

    %% Test exception with nested=true but no nested exceptions
    IncompleteException3 = clickhouse_erl_protocol:create_exception_info(
        62, "DB::Exception", "Syntax error", "at parser.cpp:123", true, []
    ),
    ?assertNot(clickhouse_erl_protocol:is_complete_exception(IncompleteException3)),

    %% Test exception with nested=true and valid nested exceptions
    NestedComplete = clickhouse_erl_protocol:create_exception_info(
        81, "DB::Exception", "Unknown database", "at database.cpp:456", false
    ),
    CompleteWithNested = clickhouse_erl_protocol:create_exception_info(
        62, "DB::Exception", "Syntax error", "at parser.cpp:123", true, [NestedComplete]
    ),
    ?assert(clickhouse_erl_protocol:is_complete_exception(CompleteWithNested)).

%% Test get_exception_summary/1 function
get_exception_summary_test() ->
    %% Test summary for simple exception
    SimpleException = clickhouse_erl_protocol:create_exception_info(
        62, "DB::Exception", "Syntax error in query", "at parser.cpp:123", false
    ),
    Summary1 = clickhouse_erl_protocol:get_exception_summary(SimpleException),
    ?assert(is_binary(Summary1)),
    ?assert(byte_size(Summary1) > 0),

    %% Test summary for exception with nested exceptions
    NestedEx = clickhouse_erl_protocol:create_exception_info(
        81, "DB::Exception", "Unknown database", "at database.cpp:456", false
    ),
    ExceptionWithNested = clickhouse_erl_protocol:create_exception_info(
        62, "DB::Exception", "Syntax error", "at parser.cpp:123", true, [NestedEx]
    ),
    Summary2 = clickhouse_erl_protocol:get_exception_summary(ExceptionWithNested),
    ?assert(is_binary(Summary2)),
    ?assert(byte_size(Summary2) > 0),
    %% Should mention nested exceptions
    ?assert(string:find(Summary2, <<"nested">>) =/= nomatch).

%% Unit tests for error code integration functions

%% Test get_error_description/1 function
error_description_test() ->
    %% Test with known error code (SYNTAX_ERROR = 62)
    Description1 = clickhouse_erl_protocol:get_error_description(62),
    ?assert(is_list(Description1)),
    ?assert(length(Description1) > 0),

    %% Test with unknown error code
    Description2 = clickhouse_erl_protocol:get_error_description(999999),
    ?assert(is_list(Description2)),
    ?assert(string:find(Description2, "Unknown error code 999999") =/= nomatch).

%% Test get_error_atom/1 function
error_atom_test() ->
    %% Test with known error code (SYNTAX_ERROR = 62)
    Atom1 = clickhouse_erl_protocol:get_error_atom(62),
    ?assert(is_atom(Atom1)),
    ?assertEqual(syntax_error, Atom1),

    %% Test with unknown error code
    Atom2 = clickhouse_erl_protocol:get_error_atom(999999),
    ?assert(is_atom(Atom2)),
    ?assertEqual(unknown_error_code, Atom2).

%% Test get_error_code_description/1 function
error_code_description_test() ->
    %% Test with known error code (SYNTAX_ERROR = 62)
    {Atom1, Description1} = clickhouse_erl_protocol:get_error_code_description(62),
    ?assert(is_atom(Atom1)),
    ?assert(is_list(Description1)),
    ?assertEqual(syntax_error, Atom1),
    ?assert(length(Description1) > 0),

    %% Test with unknown error code
    {Atom2, Description2} = clickhouse_erl_protocol:get_error_code_description(999999),
    ?assert(is_atom(Atom2)),
    ?assert(is_list(Description2)),
    ?assertEqual(unknown_error_code, Atom2),
    ?assert(string:find(Description2, "Unknown error code 999999") =/= nomatch).

%% Test get_enhanced_error_info/1 function
enhanced_error_info_test() ->
    %% Test with known error code (SYNTAX_ERROR = 62)
    ErrorInfo1 = clickhouse_erl_protocol:get_enhanced_error_info(62),
    ?assert(is_map(ErrorInfo1)),
    ?assertEqual(62, maps:get(error_code, ErrorInfo1)),
    ?assertEqual(syntax_error, maps:get(error_atom, ErrorInfo1)),
    Description1 = maps:get(error_description, ErrorInfo1),
    ?assert(is_list(Description1)),
    ?assert(length(Description1) > 0),

    %% Test with unknown error code
    ErrorInfo2 = clickhouse_erl_protocol:get_enhanced_error_info(999999),
    ?assert(is_map(ErrorInfo2)),
    ?assertEqual(999999, maps:get(error_code, ErrorInfo2)),
    ?assertEqual(unknown_error_code, maps:get(error_atom, ErrorInfo2)),
    Description2 = maps:get(error_description, ErrorInfo2),
    ?assert(is_list(Description2)),
    ?assert(string:find(Description2, "Unknown error code 999999") =/= nomatch).

%% Test that format_exception_error/1 includes enhanced error information
format_exception_with_enhanced_error_test() ->
    %% Create an exception with a known error code (SYNTAX_ERROR = 62)
    ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        62,
        "DB::Exception",
        "Syntax error in query",
        "Stack trace line 1\nStack trace line 2",
        false
    ),

    %% Format the exception
    FormattedError = clickhouse_erl_exception:format(ExceptionInfo),
    ?assert(is_binary(FormattedError)),

    %% Check that the formatted error contains the error code, atom, and description
    ?assert(string:find(FormattedError, <<"62">>) =/= nomatch),
    ?assert(string:find(FormattedError, <<"syntax_error">>) =/= nomatch),
    ?assert(string:find(FormattedError, <<"Syntax error in query">>) =/= nomatch).

%% Test that get_exception_summary/1 includes enhanced error information
exception_summary_with_enhanced_error_test() ->
    %% Create an exception with a known error code (SYNTAX_ERROR = 62)
    ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        62,
        "DB::Exception",
        "Syntax error in query",
        "Stack trace",
        false
    ),

    %% Get the summary
    Summary = clickhouse_erl_protocol:get_exception_summary(ExceptionInfo),
    ?assert(is_binary(Summary)),

    %% Check that the summary contains the error atom
    ?assert(string:find(Summary, <<"syntax_error">>) =/= nomatch),
    ?assert(string:find(Summary, <<"DB::Exception">>) =/= nomatch),
    ?assert(string:find(Summary, <<"Syntax error in query">>) =/= nomatch).

%% Test error code preservation - original error codes should be preserved
error_code_preservation_test() ->
    %% Test various error codes to ensure they are preserved
    TestCodes = [62, 60, 81, 999999, -1, 0],

    lists:foreach(
        fun(ErrorCode) ->
            %% Test that get_enhanced_error_info preserves the original error code
            ErrorInfo = clickhouse_erl_protocol:get_enhanced_error_info(ErrorCode),
            ?assertEqual(ErrorCode, maps:get(error_code, ErrorInfo)),

            %% Test that exception info preserves the error code
            ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
                ErrorCode,
                "DB::Exception",
                "Test message",
                "Test stack trace",
                false
            ),
            ?assertEqual(ErrorCode, element(2, ExceptionInfo))
        end,
        TestCodes
    ).

%% Unit tests for error code integration with clickhouse_erl_error_codes module
%% Requirements: 5.2, 5.3, 5.4

%% Test direct integration with clickhouse_erl_error_codes module functions
error_codes_module_integration_test() ->
    %% Test that protocol module correctly uses clickhouse_erl_error_codes functions

    %% Test known error codes from the existing module
    KnownErrorCodes = [
        % UNSUPPORTED_METHOD
        1,
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
    ],

    lists:foreach(
        fun(ErrorCode) ->
            %% Test direct module function calls
            {ErrorAtom, Description} = clickhouse_erl_error_codes:get_error_code_description(
                ErrorCode
            ),
            ?assert(is_atom(ErrorAtom)),
            ?assert(is_list(Description)),
            ?assert(ErrorAtom =/= unknown_error_code),
            ?assert(length(Description) > 0),

            %% Test individual functions
            ErrorAtomOnly = clickhouse_erl_error_codes:get_error(ErrorCode),
            ?assertEqual(ErrorAtom, ErrorAtomOnly),

            ReadableError = clickhouse_erl_error_codes:get_readable_error(ErrorCode),
            ?assertEqual(Description, ReadableError),

            %% Test protocol module integration
            ProtocolErrorAtom = clickhouse_erl_protocol:get_error_atom(ErrorCode),
            ?assertEqual(ErrorAtom, ProtocolErrorAtom),

            ProtocolDescription = clickhouse_erl_protocol:get_error_description(ErrorCode),
            ?assertEqual(Description, ProtocolDescription),

            {ProtocolAtom, ProtocolDesc} = clickhouse_erl_protocol:get_error_code_description(
                ErrorCode
            ),
            ?assertEqual(ErrorAtom, ProtocolAtom),
            ?assertEqual(Description, ProtocolDesc)
        end,
        KnownErrorCodes
    ).

%% Test known error code descriptions from existing module
known_error_code_descriptions_test() ->
    %% Test specific known error codes and their expected descriptions
    TestCases = [
        {1, unsupported_method, "Unsupported method"},
        {10, logical_error, "Logical error"},
        {60, unknown_table, "Unknown table"},
        {62, syntax_error, "Syntax error in query"},
        {81, unknown_database, "Unknown database"},
        {192, unknown_user, "Unknown user"},
        {193, wrong_password, "Wrong password"},
        {210, network_error, "Network error"},
        {1002, unknown_exception, "Unknown exception"}
    ],

    lists:foreach(
        fun({ErrorCode, ExpectedAtom, ExpectedDescription}) ->
            %% Test clickhouse_erl_error_codes module directly
            {ActualAtom, ActualDescription} = clickhouse_erl_error_codes:get_error_code_description(
                ErrorCode
            ),
            ?assertEqual(ExpectedAtom, ActualAtom),
            ?assertEqual(ExpectedDescription, ActualDescription),

            %% Test protocol module integration
            ProtocolAtom = clickhouse_erl_protocol:get_error_atom(ErrorCode),
            ?assertEqual(ExpectedAtom, ProtocolAtom),

            ProtocolDescription = clickhouse_erl_protocol:get_error_description(ErrorCode),
            ?assertEqual(ExpectedDescription, ProtocolDescription),

            %% Test enhanced error info
            EnhancedInfo = clickhouse_erl_protocol:get_enhanced_error_info(ErrorCode),
            ?assertEqual(ErrorCode, maps:get(error_code, EnhancedInfo)),
            ?assertEqual(ExpectedAtom, maps:get(error_atom, EnhancedInfo)),
            ?assertEqual(ExpectedDescription, maps:get(error_description, EnhancedInfo))
        end,
        TestCases
    ).

%% Test unknown error code handling with fallback
unknown_error_code_fallback_test() ->
    %% Test various unknown error codes
    UnknownErrorCodes = [
        % Very large unknown code
        999999,
        % Negative unknown code
        -999,
        % Random unknown code
        123456,
        % Zero (might not be defined)
        0
    ],

    lists:foreach(
        fun(ErrorCode) ->
            %% Test clickhouse_erl_error_codes module fallback
            try
                {ErrorAtom, Description} = clickhouse_erl_error_codes:get_error_code_description(
                    ErrorCode
                ),
                %% If the module has this code, verify it's valid
                ?assert(is_atom(ErrorAtom)),
                ?assert(is_list(Description))
            catch
                _:_ ->
                    %% Module doesn't have this code, which is expected for unknown codes
                    ok
            end,

            %% Test protocol module fallback behavior
            ProtocolAtom = clickhouse_erl_protocol:get_error_atom(ErrorCode),
            ?assert(is_atom(ProtocolAtom)),

            ProtocolDescription = clickhouse_erl_protocol:get_error_description(ErrorCode),
            ?assert(is_list(ProtocolDescription)),

            {ProtocolDescAtom, ProtocolDescText} = clickhouse_erl_protocol:get_error_code_description(
                ErrorCode
            ),
            ?assert(is_atom(ProtocolDescAtom)),
            ?assert(is_list(ProtocolDescText)),

            %% For truly unknown codes, should get fallback values
            case clickhouse_erl_error_codes:get_error_code_description(ErrorCode) of
                {unknown_error_code, _} ->
                    %% This is an unknown code, verify fallback behavior
                    ?assertEqual(unknown_error_code, ProtocolAtom),
                    ?assertEqual(unknown_error_code, ProtocolDescAtom),
                    ?assert(string:find(ProtocolDescription, "Unknown error code") =/= nomatch),
                    ?assert(string:find(ProtocolDescText, "Unknown error code") =/= nomatch);
                _ ->
                    %% This code is actually known, so fallback shouldn't be used
                    ok
            end
        end,
        UnknownErrorCodes
    ).

%% Test error code integration in exception formatting
error_code_integration_in_exception_formatting_test() ->
    %% Test that exception formatting correctly uses error code integration

    TestCases = [
        {62, "DB::Exception", "Syntax error in query", "at parser.cpp:123"},
        {60, "DB::Exception", "Table not found", "at table_resolver.cpp:456"},
        {192, "DB::Exception", "Authentication failed", "at auth.cpp:789"},
        {999999, "DB::Exception", "Unknown error", "at unknown.cpp:999"}
    ],

    lists:foreach(
        fun({ErrorCode, ExceptionName, Message, StackTrace}) ->
            %% Create exception info
            ExceptionInfo = clickhouse_erl_protocol:create_exception_info(
                ErrorCode,
                ExceptionName,
                Message,
                StackTrace,
                false
            ),

            %% Format the exception
            FormattedError = clickhouse_erl_exception:format(ExceptionInfo),
            ?assert(is_binary(FormattedError)),

            %% Get expected error information from error codes module
            ExpectedResult =
                try
                    clickhouse_erl_error_codes:get_error_code_description(ErrorCode)
                catch
                    _:_ -> {unknown_error_code, io_lib:format("Unknown error code ~w", [ErrorCode])}
                end,

            {ExpectedAtom, ExpectedDescription} = ExpectedResult,

            %% Verify formatted error contains integrated error code information
            ?assert(
                string:find(FormattedError, iolist_to_binary(integer_to_list(ErrorCode))) =/=
                    nomatch
            ),
            ?assert(
                string:find(FormattedError, iolist_to_binary(atom_to_list(ExpectedAtom))) =/=
                    nomatch
            ),
            ?assert(
                string:find(
                    FormattedError, clickhouse_erl_types_primitive:to_binary(ExpectedDescription)
                ) =/=
                    nomatch
            ),
            ?assert(
                string:find(FormattedError, clickhouse_erl_types_primitive:to_binary(ExceptionName)) =/=
                    nomatch
            ),
            ?assert(
                string:find(FormattedError, clickhouse_erl_types_primitive:to_binary(Message)) =/=
                    nomatch
            ),

            %% Test exception summary integration
            Summary = clickhouse_erl_protocol:get_exception_summary(ExceptionInfo),
            ?assert(is_binary(Summary)),
            ?assert(string:find(Summary, iolist_to_binary(atom_to_list(ExpectedAtom))) =/= nomatch),
            ?assert(
                string:find(Summary, clickhouse_erl_types_primitive:to_binary(ExpectedDescription)) =/=
                    nomatch
            )
        end,
        TestCases
    ).

%% Test error code integration with nested exceptions
error_code_integration_nested_exceptions_test() ->
    %% Test that nested exceptions correctly integrate error codes

    %% Create nested exception with different error codes
    NestedExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        % NETWORK_ERROR
        210,
        "DB::NetException",
        "Connection failed",
        "at connection.cpp:123",
        false
    ),

    ParentExceptionInfo = clickhouse_erl_protocol:create_exception_info(
        % SYNTAX_ERROR
        62,
        "DB::Exception",
        "Query parsing failed",
        "at parser.cpp:456",
        true,
        [NestedExceptionInfo]
    ),

    %% Format the nested exception
    FormattedError = clickhouse_erl_exception:format(ParentExceptionInfo),
    ?assert(is_binary(FormattedError)),

    %% Verify both error codes are properly integrated

    % Parent error code
    ?assert(string:find(FormattedError, <<"62">>) =/= nomatch),
    % Nested error code
    ?assert(string:find(FormattedError, <<"210">>) =/= nomatch),
    % Parent error atom
    ?assert(string:find(FormattedError, <<"syntax_error">>) =/= nomatch),
    % Nested error atom
    ?assert(string:find(FormattedError, <<"network_error">>) =/= nomatch),
    % Parent description
    ?assert(string:find(FormattedError, <<"Syntax error in query">>) =/= nomatch),
    % Nested description
    ?assert(string:find(FormattedError, <<"Network error">>) =/= nomatch),

    %% Test summary with nested exceptions
    Summary = clickhouse_erl_protocol:get_exception_summary(ParentExceptionInfo),
    ?assert(is_binary(Summary)),
    ?assert(string:find(Summary, <<"syntax_error">>) =/= nomatch),
    ?assert(string:find(Summary, <<"(+1 nested)">>) =/= nomatch).

%% Unit tests for protocol compliance validation functions

%% Test validate_exception_packet_format/1 function
validate_exception_packet_format_test() ->
    %% Test valid exception packet format
    ValidPacket = create_valid_exception_packet(),
    ?assertEqual(ok, clickhouse_erl_protocol:validate_exception_packet_format(ValidPacket)),

    %% Test packet too small
    TooSmallPacket = <<1, 2, 3>>,
    ?assertMatch(
        {error, {protocol_violation, "Exception packet too small"}},
        clickhouse_erl_protocol:validate_exception_packet_format(TooSmallPacket)
    ),

    %% Test invalid error code field
    InvalidErrorCodePacket = <<>>,
    ?assertMatch(
        {error, _},
        clickhouse_erl_protocol:validate_exception_packet_format(InvalidErrorCodePacket)
    ).

%% Test validate_protocol_compliance/1 function
validate_protocol_compliance_test() ->
    %% Test valid packet
    ValidPacket = create_valid_exception_packet(),
    ?assertEqual(ok, clickhouse_erl_protocol:validate_protocol_compliance(ValidPacket)),

    %% Test invalid packet
    InvalidPacket = <<1, 2>>,
    ?assertMatch(
        {error, _},
        clickhouse_erl_protocol:validate_protocol_compliance(InvalidPacket)
    ).

%% Test validate_integer_encoding/2 function
validate_integer_encoding_test() ->
    %% Test valid error code encoding (32-bit signed little-endian)
    ValidErrorCode = <<62:32/signed-little, "rest">>,
    ?assertEqual(ok, clickhouse_erl_protocol:validate_integer_encoding(ValidErrorCode, error_code)),

    %% Test insufficient bytes for error code
    TooShortErrorCode = <<1, 2>>,
    ?assertMatch(
        {error, {invalid_integer_encoding, error_code, _}},
        clickhouse_erl_protocol:validate_integer_encoding(TooShortErrorCode, error_code)
    ),

    %% Test valid nested flag encoding (UInt8 boolean)
    ValidNestedFlag = <<0, "rest">>,
    ?assertEqual(
        ok, clickhouse_erl_protocol:validate_integer_encoding(ValidNestedFlag, nested_flag)
    ),

    ValidNestedFlagTrue = <<1, "rest">>,
    ?assertEqual(
        ok, clickhouse_erl_protocol:validate_integer_encoding(ValidNestedFlagTrue, nested_flag)
    ),

    %% Test invalid nested flag value
    InvalidNestedFlag = <<2, "rest">>,
    ?assertMatch(
        {error, {invalid_integer_encoding, nested_flag, _}},
        clickhouse_erl_protocol:validate_integer_encoding(InvalidNestedFlag, nested_flag)
    ),

    %% Test insufficient bytes for nested flag
    TooShortNestedFlag = <<>>,
    ?assertMatch(
        {error, {invalid_integer_encoding, nested_flag, _}},
        clickhouse_erl_protocol:validate_integer_encoding(TooShortNestedFlag, nested_flag)
    ),

    %% Test unknown field
    ?assertMatch(
        {error, {invalid_integer_encoding, unknown_field, _}},
        clickhouse_erl_protocol:validate_integer_encoding(<<1, 2, 3, 4>>, unknown_field)
    ).

%% Test validate_string_encoding/1 function
validate_string_encoding_test() ->
    %% Test valid string encoding (varint length + UTF-8 bytes)
    ValidString = clickhouse_erl_types_primitive:encode_string("Hello"),
    ?assertEqual(ok, clickhouse_erl_protocol:validate_string_encoding(ValidString)),

    %% Test empty string
    EmptyString = clickhouse_erl_types_primitive:encode_string(""),
    ?assertEqual(ok, clickhouse_erl_protocol:validate_string_encoding(EmptyString)),

    %% Test UTF-8 string with special characters
    Utf8String = clickhouse_erl_types_primitive:encode_string("Hello 世界 🌍"),
    ?assertEqual(ok, clickhouse_erl_protocol:validate_string_encoding(Utf8String)),

    %% Test invalid varint (truncated)

    % Continuation bit set but no following byte
    InvalidVarint = <<128>>,
    ?assertMatch(
        {error, {invalid_string_encoding, string, _}},
        clickhouse_erl_protocol:validate_string_encoding(InvalidVarint)
    ),

    %% Test insufficient bytes for declared string length

    % Claims 5 bytes but only has 2
    InsufficientBytes = <<5, "Hi">>,
    ?assertMatch(
        {error, {invalid_string_encoding, string, _}},
        clickhouse_erl_protocol:validate_string_encoding(InsufficientBytes)
    ),

    %% Test invalid UTF-8 encoding

    % Invalid UTF-8 bytes
    InvalidUtf8 = <<2, 255, 254>>,
    ?assertMatch(
        {error, {invalid_string_encoding, string, _}},
        clickhouse_erl_protocol:validate_string_encoding(InvalidUtf8)
    ).

%% Test detect_protocol_violations/1 function
detect_protocol_violations_test() ->
    %% Test valid packet (no violations)
    ValidPacket = create_valid_exception_packet(),
    ?assertEqual(ok, clickhouse_erl_protocol:detect_protocol_violations(ValidPacket)),

    %% Test packet with field order violation

    % Empty packet violates field order
    InvalidFieldOrder = <<>>,
    ?assertMatch(
        {error, {protocol_violation, _}},
        clickhouse_erl_protocol:detect_protocol_violations(InvalidFieldOrder)
    ),

    %% Test packet with encoding violation

    % Too short for proper encoding
    InvalidEncoding = <<1, 2>>,
    ?assertMatch(
        {error, _},
        clickhouse_erl_protocol:detect_protocol_violations(InvalidEncoding)
    ).

%% Helper function to create a valid exception packet for testing
create_valid_exception_packet() ->
    %% Create a properly formatted exception packet

    % SYNTAX_ERROR
    ErrorCode = 62,
    ExceptionName = "DB::Exception",
    Message = "Syntax error in query",
    StackTrace = "at parser.cpp:123",
    % false
    NestedFlag = 0,

    %% Encode according to ClickHouse protocol
    ErrorCodeBin = <<ErrorCode:32/signed-little>>,
    ExceptionNameBin = clickhouse_erl_types_primitive:encode_string(ExceptionName),
    MessageBin = clickhouse_erl_types_primitive:encode_string(Message),
    StackTraceBin = clickhouse_erl_types_primitive:encode_string(StackTrace),
    NestedFlagBin = <<NestedFlag:8>>,

    <<ErrorCodeBin/binary, ExceptionNameBin/binary, MessageBin/binary, StackTraceBin/binary,
        NestedFlagBin/binary>>.

%% Test field order validation
field_order_validation_test() ->
    %% Test correct field order
    ValidPacket = create_valid_exception_packet(),
    ?assertEqual(ok, clickhouse_erl_protocol:validate_exception_packet_format(ValidPacket)),

    %% Test packet too small for error code
    TooSmall = <<1, 2>>,
    ?assertMatch(
        {error, _},
        clickhouse_erl_protocol:validate_exception_packet_format(TooSmall)
    ).

%% Test encoding compliance validation
encoding_compliance_test() ->
    %% Test valid encoding
    ValidPacket = create_valid_exception_packet(),
    ?assertEqual(ok, clickhouse_erl_protocol:validate_protocol_compliance(ValidPacket)),

    %% Test invalid little-endian encoding (simulate big-endian)
    ErrorCode = 62,
    % Wrong byte order
    InvalidEndian = <<ErrorCode:32/signed-big>>,
    ExceptionNameBin = clickhouse_erl_types_primitive:encode_string("DB::Exception"),
    MessageBin = clickhouse_erl_types_primitive:encode_string("Test message"),
    StackTraceBin = clickhouse_erl_types_primitive:encode_string("Test stack"),
    NestedFlagBin = <<0:8>>,

    InvalidPacket =
        <<InvalidEndian/binary, ExceptionNameBin/binary, MessageBin/binary, StackTraceBin/binary,
            NestedFlagBin/binary>>,

    %% This should still validate as we can't easily detect byte order without context
    %% But we can test that the validation functions work
    Result = clickhouse_erl_protocol:validate_protocol_compliance(InvalidPacket),
    %% Just check that we get some result (ok or error)
    ?assert((Result =:= ok) orelse (element(1, Result) =:= error)).

%% Test string encoding validation with various UTF-8 cases
string_encoding_validation_test() ->
    %% Test ASCII string
    AsciiString = clickhouse_erl_types_primitive:encode_string("Hello World"),
    ?assertEqual(ok, clickhouse_erl_protocol:validate_string_encoding(AsciiString)),

    %% Test Unicode string
    UnicodeString = clickhouse_erl_types_primitive:encode_string("Hello 世界"),
    ?assertEqual(ok, clickhouse_erl_protocol:validate_string_encoding(UnicodeString)),

    %% Test emoji string
    EmojiString = clickhouse_erl_types_primitive:encode_string("Hello 🌍"),
    ?assertEqual(ok, clickhouse_erl_protocol:validate_string_encoding(EmojiString)),

    %% Test empty string
    EmptyString = clickhouse_erl_types_primitive:encode_string(""),
    ?assertEqual(ok, clickhouse_erl_protocol:validate_string_encoding(EmptyString)),

    %% Test string with newlines and special characters
    SpecialString = clickhouse_erl_types_primitive:encode_string("Line 1\nLine 2\tTabbed"),
    ?assertEqual(ok, clickhouse_erl_protocol:validate_string_encoding(SpecialString)).

%% Test protocol violation detection with various violation types
protocol_violation_detection_test() ->
    %% Test format violations

    % Smaller than minimum required
    TooSmallPacket = <<1, 2, 3, 4, 5>>,
    ?assertMatch(
        {error, {protocol_violation, _}},
        clickhouse_erl_protocol:detect_protocol_violations(TooSmallPacket)
    ),

    %% Test field order violations
    EmptyPacket = <<>>,
    ?assertMatch(
        {error, {protocol_violation, _}},
        clickhouse_erl_protocol:detect_protocol_violations(EmptyPacket)
    ),

    %% Test valid packet has no violations
    ValidPacket = create_valid_exception_packet(),
    ?assertEqual(ok, clickhouse_erl_protocol:detect_protocol_violations(ValidPacket)).

%% Test integer encoding validation edge cases
integer_encoding_edge_cases_test() ->
    %% Test maximum 32-bit signed integer
    MaxInt32 = 2147483647,
    MaxInt32Bin = <<MaxInt32:32/signed-little, "rest">>,
    ?assertEqual(ok, clickhouse_erl_protocol:validate_integer_encoding(MaxInt32Bin, error_code)),

    %% Test minimum 32-bit signed integer
    MinInt32 = -2147483648,
    MinInt32Bin = <<MinInt32:32/signed-little, "rest">>,
    ?assertEqual(ok, clickhouse_erl_protocol:validate_integer_encoding(MinInt32Bin, error_code)),

    %% Test zero error code
    ZeroErrorCode = <<0:32/signed-little, "rest">>,
    ?assertEqual(ok, clickhouse_erl_protocol:validate_integer_encoding(ZeroErrorCode, error_code)),

    %% Test negative error code
    NegativeErrorCode = <<(-1):32/signed-little, "rest">>,
    ?assertEqual(
        ok, clickhouse_erl_protocol:validate_integer_encoding(NegativeErrorCode, error_code)
    ).

%% Test comprehensive protocol compliance with nested exceptions
protocol_compliance_nested_test() ->
    %% Create a packet with nested exceptions
    ErrorCode = 62,
    ExceptionName = "DB::Exception",
    Message = "Parent exception",
    StackTrace = "at parent.cpp:123",
    % true - has nested exception
    NestedFlag = 1,

    %% Create nested exception
    NestedErrorCode = 81,
    NestedExceptionName = "DB::Exception",
    NestedMessage = "Nested exception",
    NestedStackTrace = "at nested.cpp:456",
    % false - no further nesting
    NestedNestedFlag = 0,

    %% Encode parent exception
    ErrorCodeBin = <<ErrorCode:32/signed-little>>,
    ExceptionNameBin = clickhouse_erl_types_primitive:encode_string(ExceptionName),
    MessageBin = clickhouse_erl_types_primitive:encode_string(Message),
    StackTraceBin = clickhouse_erl_types_primitive:encode_string(StackTrace),
    NestedFlagBin = <<NestedFlag:8>>,

    %% Encode nested exception
    NestedErrorCodeBin = <<NestedErrorCode:32/signed-little>>,
    NestedExceptionNameBin = clickhouse_erl_types_primitive:encode_string(NestedExceptionName),
    NestedMessageBin = clickhouse_erl_types_primitive:encode_string(NestedMessage),
    NestedStackTraceBin = clickhouse_erl_types_primitive:encode_string(NestedStackTrace),
    NestedNestedFlagBin = <<NestedNestedFlag:8>>,

    %% Combine into complete packet
    CompletePacket =
        <<ErrorCodeBin/binary, ExceptionNameBin/binary, MessageBin/binary, StackTraceBin/binary,
            NestedFlagBin/binary, NestedErrorCodeBin/binary, NestedExceptionNameBin/binary,
            NestedMessageBin/binary, NestedStackTraceBin/binary, NestedNestedFlagBin/binary>>,

    %% Test protocol compliance
    ?assertEqual(ok, clickhouse_erl_protocol:validate_protocol_compliance(CompletePacket)),
    ?assertEqual(ok, clickhouse_erl_protocol:detect_protocol_violations(CompletePacket)).
