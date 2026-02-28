-module(clickhouse_erl_exception_tests).
-include_lib("eunit/include/eunit.hrl").
-include("clickhouse_erl_protocol.hrl").

-define(TEST_ERROR_CODE, 123).
-define(TEST_ERROR_NAME, <<"TestError">>).
-define(TEST_ERROR_MSG, <<"Something went wrong">>).
-define(TEST_STACK_TRACE, <<"Line 1\nLine 2">>).

format_test() ->
    Exception = #exception_info{
        error_code = ?TEST_ERROR_CODE,
        exception_name = ?TEST_ERROR_NAME,
        message = ?TEST_ERROR_MSG,
        stack_trace = ?TEST_STACK_TRACE,
        nested = false,
        nested_exceptions = []
    },

    Formatted = clickhouse_erl_exception:format(Exception),
    ?assertMatch({match, _}, re:run(Formatted, ?TEST_ERROR_NAME)),
    ?assertMatch({match, _}, re:run(Formatted, integer_to_list(?TEST_ERROR_CODE))),
    ?assertMatch({match, _}, re:run(Formatted, ?TEST_ERROR_MSG)),
    ?assertMatch({match, _}, re:run(Formatted, "Stack trace")),
    ok.

%% Test exception display formatting with known error codes
format_with_error_code_description_test() ->
    % Test with a known ClickHouse error code (SYNTAX_ERROR = 62)
    Exception = #exception_info{
        error_code = 62,
        exception_name = <<"DB::Exception">>,
        message = <<"Invalid SQL syntax">>,
        stack_trace = <<"at line 42">>,
        nested = false,
        nested_exceptions = []
    },

    Formatted = clickhouse_erl_exception:format(Exception),

    % Should contain the exception name
    ?assertMatch({match, _}, re:run(Formatted, "DB::Exception")),

    % Should contain the error code
    ?assertMatch({match, _}, re:run(Formatted, "62")),

    % Should contain the error description from error codes module
    ?assertMatch({match, _}, re:run(Formatted, "Syntax error in query")),

    % Should contain the original message
    ?assertMatch({match, _}, re:run(Formatted, "Invalid SQL syntax")),

    % Should contain stack trace section
    ?assertMatch({match, _}, re:run(Formatted, "Stack trace")),
    ?assertMatch({match, _}, re:run(Formatted, "at line 42")),
    ok.

%% Test formatting with unknown error code
format_with_unknown_error_code_test() ->
    Exception = #exception_info{
        error_code = 99999,
        exception_name = <<"CustomException">>,
        message = <<"Custom error message">>,
        stack_trace = <<>>,
        nested = false,
        nested_exceptions = []
    },

    Formatted = clickhouse_erl_exception:format(Exception),

    % Should contain the exception name
    ?assertMatch({match, _}, re:run(Formatted, "CustomException")),

    % Should contain the error code
    ?assertMatch({match, _}, re:run(Formatted, "99999")),

    % Should contain the fallback description for unknown codes
    ?assertMatch({match, _}, re:run(Formatted, "Unknown error code")),

    % Should contain the original message
    ?assertMatch({match, _}, re:run(Formatted, "Custom error message")),
    ok.

%% Test formatting without stack trace
format_without_stack_trace_test() ->
    Exception = #exception_info{
        % UNKNOWN_TABLE
        error_code = 60,
        exception_name = <<"DB::Exception">>,
        message = <<"Table 'test.users' doesn't exist">>,
        stack_trace = <<>>,
        nested = false,
        nested_exceptions = []
    },

    Formatted = clickhouse_erl_exception:format(Exception),

    % Should contain error description
    ?assertMatch({match, _}, re:run(Formatted, "Unknown table")),

    % Should NOT contain stack trace section when empty
    ?assertEqual(nomatch, re:run(Formatted, "Stack trace")),
    ok.

format_nested_test() ->
    NestedExc = #exception_info{
        error_code = 456,
        exception_name = <<"NestedError">>,
        message = <<"Inner cause">>,
        stack_trace = <<>>,
        nested = false,
        nested_exceptions = []
    },

    Exception = #exception_info{
        error_code = ?TEST_ERROR_CODE,
        exception_name = ?TEST_ERROR_NAME,
        message = ?TEST_ERROR_MSG,
        stack_trace = ?TEST_STACK_TRACE,
        nested = true,
        nested_exceptions = [NestedExc]
    },

    Formatted = clickhouse_erl_exception:format(Exception),
    ?assertMatch({match, _}, re:run(Formatted, "Caused by")),
    ?assertMatch({match, _}, re:run(Formatted, "NestedError")),
    ok.

%% Test nested exception formatting with proper indentation and error descriptions
format_nested_with_descriptions_test() ->
    % Create a deeply nested exception chain with known error codes
    Level3Exception = #exception_info{
        error_code = 81,
        exception_name = <<"DB::Exception">>,
        message = <<"Database 'nonexistent' doesn't exist">>,
        stack_trace = <<>>,
        nested = false,
        nested_exceptions = []
    },

    Level2Exception = #exception_info{
        error_code = 60,
        exception_name = <<"DB::Exception">>,
        message = <<"Table 'users' not found">>,
        stack_trace = <<>>,
        nested = true,
        nested_exceptions = [Level3Exception]
    },

    TopException = #exception_info{
        error_code = 62,
        exception_name = <<"DB::Exception">>,
        message = <<"Query parsing failed">>,
        stack_trace = <<"at Parser.cpp:123">>,
        nested = true,
        nested_exceptions = [Level2Exception]
    },

    Formatted = clickhouse_erl_exception:format(TopException),

    % Should contain top-level exception with description
    ?assertMatch({match, _}, re:run(Formatted, "Syntax error in query")),
    ?assertMatch({match, _}, re:run(Formatted, "Query parsing failed")),

    % Should contain "Caused by" section
    ?assertMatch({match, _}, re:run(Formatted, "Caused by")),

    % Should contain nested exception descriptions
    ?assertMatch({match, _}, re:run(Formatted, "Unknown table")),
    ?assertMatch({match, _}, re:run(Formatted, "Unknown database")),

    % Should contain nested messages
    ?assertMatch({match, _}, re:run(Formatted, "Table 'users' not found")),
    ?assertMatch({match, _}, re:run(Formatted, "Database 'nonexistent' doesn't exist")),

    % Should contain stack trace
    ?assertMatch({match, _}, re:run(Formatted, "Stack trace")),
    ?assertMatch({match, _}, re:run(Formatted, "at Parser.cpp:123")),
    ok.

%% Test nested exception indentation
format_nested_indentation_test() ->
    Level2 = #exception_info{
        error_code = 456,
        exception_name = <<"InnerException">>,
        message = <<"Inner message">>,
        stack_trace = <<>>,
        nested = false,
        nested_exceptions = []
    },

    Level1 = #exception_info{
        error_code = 123,
        exception_name = <<"OuterException">>,
        message = <<"Outer message">>,
        stack_trace = <<>>,
        nested = true,
        nested_exceptions = [Level2]
    },

    Formatted = clickhouse_erl_exception:format(Level1),

    % Split into lines to check indentation
    Lines = string:split(Formatted, "\n", all),

    % Find the nested exception line (should be indented)
    NestedLines = [Line || Line <- Lines, string:find(Line, "InnerException") =/= nomatch],
    ?assertEqual(1, length(NestedLines)),

    [NestedLine] = NestedLines,
    % Should start with 2 spaces (indentation)
    ?assertEqual(<<"  ">>, string:slice(NestedLine, 0, 2)),
    ok.

%% Test multiple nested exceptions at same level
format_multiple_nested_test() ->
    Nested1 = #exception_info{
        error_code = 100,
        exception_name = <<"FirstNested">>,
        message = <<"First nested error">>,
        stack_trace = <<>>,
        nested = false,
        nested_exceptions = []
    },

    Nested2 = #exception_info{
        error_code = 200,
        exception_name = <<"SecondNested">>,
        message = <<"Second nested error">>,
        stack_trace = <<>>,
        nested = false,
        nested_exceptions = []
    },

    TopException = #exception_info{
        error_code = 50,
        exception_name = <<"TopException">>,
        message = <<"Top level error">>,
        stack_trace = <<>>,
        nested = true,
        nested_exceptions = [Nested1, Nested2]
    },

    Formatted = clickhouse_erl_exception:format(TopException),

    % Should contain both nested exceptions
    ?assertMatch({match, _}, re:run(Formatted, "FirstNested")),
    ?assertMatch({match, _}, re:run(Formatted, "SecondNested")),
    ?assertMatch({match, _}, re:run(Formatted, "First nested error")),
    ?assertMatch({match, _}, re:run(Formatted, "Second nested error")),
    ok.

to_map_test() ->
    Exception = #exception_info{
        error_code = ?TEST_ERROR_CODE,
        exception_name = ?TEST_ERROR_NAME,
        message = ?TEST_ERROR_MSG,
        stack_trace = ?TEST_STACK_TRACE,
        nested = false,
        nested_exceptions = []
    },

    Map = clickhouse_erl_exception:to_map(Exception),
    ?assertEqual(?TEST_ERROR_CODE, maps:get(error_code, Map)),
    ?assertEqual(?TEST_ERROR_NAME, maps:get(exception_name, Map)),
    ?assertEqual(?TEST_ERROR_MSG, maps:get(message, Map)),
    ?assertEqual(?TEST_STACK_TRACE, maps:get(stack_trace, Map)),
    ?assertEqual(false, maps:get(nested, Map)),
    ?assertEqual([], maps:get(nested_exceptions, Map)),
    ok.

flatten_test() ->
    Level3 = #exception_info{
        error_code = 3,
        exception_name = <<"L3">>,
        message = <<"M3">>,
        stack_trace = <<>>,
        nested = false,
        nested_exceptions = []
    },
    Level2 = #exception_info{
        error_code = 2,
        exception_name = <<"L2">>,
        message = <<"M2">>,
        stack_trace = <<>>,
        nested = true,
        nested_exceptions = [Level3]
    },
    Level1 = #exception_info{
        error_code = 1,
        exception_name = <<"L1">>,
        message = <<"M1">>,
        stack_trace = <<>>,
        nested = true,
        nested_exceptions = [Level2]
    },

    List = clickhouse_erl_exception:flatten(Level1),
    ?assertEqual(3, length(List)),
    [E1, E2, E3] = List,
    ?assertEqual(1, clickhouse_erl_exception:get_code(E1)),
    ?assertEqual(2, clickhouse_erl_exception:get_code(E2)),
    ?assertEqual(3, clickhouse_erl_exception:get_code(E3)),
    ok.

accessors_test() ->
    Exception = #exception_info{
        error_code = ?TEST_ERROR_CODE,
        exception_name = ?TEST_ERROR_NAME,
        message = ?TEST_ERROR_MSG,
        stack_trace = ?TEST_STACK_TRACE,
        nested = false,
        nested_exceptions = []
    },

    ?assert(clickhouse_erl_exception:is_exception(Exception)),
    ?assertNot(clickhouse_erl_exception:is_exception({not_an_exception, some_data})),
    ?assertEqual(?TEST_ERROR_CODE, clickhouse_erl_exception:get_code(Exception)),
    ?assertEqual(?TEST_ERROR_NAME, clickhouse_erl_exception:get_name(Exception)),
    ?assertEqual(?TEST_ERROR_MSG, clickhouse_erl_exception:get_message(Exception)),
    ?assertEqual(?TEST_STACK_TRACE, clickhouse_erl_exception:get_stack_trace(Exception)),
    ok.

compare_test() ->
    Exception1 = #exception_info{
        error_code = 123,
        exception_name = <<"TestError">>,
        message = <<"Test message">>,
        stack_trace = <<"Stack1">>,
        nested = false,
        nested_exceptions = []
    },
    Exception2 = #exception_info{
        error_code = 123,
        exception_name = <<"TestError">>,
        message = <<"Test message">>,
        % Different stack trace
        stack_trace = <<"Stack2">>,
        nested = false,
        nested_exceptions = []
    },
    Exception3 = #exception_info{
        % Different error code
        error_code = 456,
        exception_name = <<"TestError">>,
        message = <<"Test message">>,
        stack_trace = <<"Stack1">>,
        nested = false,
        nested_exceptions = []
    },

    % Same code, name, message
    ?assert(clickhouse_erl_exception:compare(Exception1, Exception2)),
    % Different code
    ?assertNot(clickhouse_erl_exception:compare(Exception1, Exception3)),
    ok.

match_functions_test() ->
    Exception = #exception_info{
        error_code = 123,
        exception_name = <<"DB::Exception">>,
        message = <<"Table not found: users">>,
        stack_trace = <<>>,
        nested = false,
        nested_exceptions = []
    },

    % Test match_code
    ?assert(clickhouse_erl_exception:match_code(Exception, 123)),
    ?assertNot(clickhouse_erl_exception:match_code(Exception, 456)),

    % Test match_name (case-insensitive)
    ?assert(clickhouse_erl_exception:match_name(Exception, <<"DB::Exception">>)),
    ?assert(clickhouse_erl_exception:match_name(Exception, <<"db::exception">>)),
    ?assertNot(clickhouse_erl_exception:match_name(Exception, <<"OtherException">>)),

    % Test match_message (substring, case-insensitive)
    ?assert(clickhouse_erl_exception:match_message(Exception, <<"Table not found">>)),
    ?assert(clickhouse_erl_exception:match_message(Exception, <<"table not found">>)),
    ?assert(clickhouse_erl_exception:match_message(Exception, <<"users">>)),
    ?assertNot(clickhouse_erl_exception:match_message(Exception, <<"columns">>)),
    ok.

nested_utility_functions_test() ->
    Level2 = #exception_info{
        error_code = 2,
        exception_name = "Level2",
        message = "Inner error",
        stack_trace = "",
        nested = false,
        nested_exceptions = []
    },
    Level1 = #exception_info{
        error_code = 1,
        exception_name = "Level1",
        message = "Outer error",
        stack_trace = "",
        nested = true,
        nested_exceptions = [Level2]
    },
    NoNested = #exception_info{
        error_code = 3,
        exception_name = "NoNested",
        message = "Simple error",
        stack_trace = "",
        nested = false,
        nested_exceptions = []
    },

    % Test has_nested
    ?assert(clickhouse_erl_exception:has_nested(Level1)),
    ?assertNot(clickhouse_erl_exception:has_nested(Level2)),
    ?assertNot(clickhouse_erl_exception:has_nested(NoNested)),

    % Test count_nested
    ?assertEqual(1, clickhouse_erl_exception:count_nested(Level1)),
    ?assertEqual(0, clickhouse_erl_exception:count_nested(Level2)),
    ?assertEqual(0, clickhouse_erl_exception:count_nested(NoNested)),
    ok.

find_functions_test() ->
    Level3 = #exception_info{
        error_code = 789,
        exception_name = <<"DeepError">>,
        message = <<"Deep message">>,
        stack_trace = <<>>,
        nested = false,
        nested_exceptions = []
    },
    Level2 = #exception_info{
        error_code = 456,
        exception_name = <<"MiddleError">>,
        message = <<"Middle message">>,
        stack_trace = <<>>,
        nested = true,
        nested_exceptions = [Level3]
    },
    Level1 = #exception_info{
        error_code = 123,
        exception_name = <<"TopError">>,
        message = <<"Top message">>,
        stack_trace = <<>>,
        nested = true,
        nested_exceptions = [Level2]
    },

    % Test find_by_code
    ?assertMatch({ok, _}, clickhouse_erl_exception:find_by_code(Level1, 123)),
    ?assertMatch({ok, _}, clickhouse_erl_exception:find_by_code(Level1, 456)),
    ?assertMatch({ok, _}, clickhouse_erl_exception:find_by_code(Level1, 789)),
    ?assertEqual(not_found, clickhouse_erl_exception:find_by_code(Level1, 999)),

    % Test find_by_name
    ?assertMatch({ok, _}, clickhouse_erl_exception:find_by_name(Level1, <<"TopError">>)),
    ?assertMatch({ok, _}, clickhouse_erl_exception:find_by_name(Level1, <<"MiddleError">>)),
    ?assertMatch({ok, _}, clickhouse_erl_exception:find_by_name(Level1, <<"DeepError">>)),
    ?assertEqual(not_found, clickhouse_erl_exception:find_by_name(Level1, <<"NonExistent">>)),

    % Verify the found exceptions are correct
    {ok, FoundTop} = clickhouse_erl_exception:find_by_code(Level1, 123),
    ?assertEqual(<<"TopError">>, clickhouse_erl_exception:get_name(FoundTop)),

    {ok, FoundDeep} = clickhouse_erl_exception:find_by_name(Level1, <<"DeepError">>),
    ?assertEqual(789, clickhouse_erl_exception:get_code(FoundDeep)),
    ok.
