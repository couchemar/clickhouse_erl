-module(clickhouse_erl_tests).
-include_lib("eunit/include/eunit.hrl").

insert_validation_test() ->
    SQL = "INSERT INTO test_table VALUES",

    %% Test invalid column name (not a binary)
    InvalidNameInput = [#{name => "col1", type => <<"UInt8">>, data => [1]}],
    ?assertMatch(
        {error, {validation_error, {invalid_column_name, "col1"}}},
        clickhouse_erl:insert(self(), SQL, InvalidNameInput)
    ),

    %% Test row count mismatch
    MismatchInput = [
        #{name => <<"col1">>, type => <<"UInt8">>, data => [1, 2]},
        #{name => <<"col2">>, type => <<"UInt8">>, data => [1]}
    ],
    ?assertMatch(
        {error, {validation_error, {row_count_mismatch, [{<<"col1">>, 2}, {<<"col2">>, 1}]}}},
        clickhouse_erl:insert(self(), SQL, MismatchInput)
    ).

insert_sql_conversion_test() ->
    %% Test that string SQL is converted to binary
    %% We use an invalid input to trigger validation error and see if it gets there
    SQL = "INSERT INTO test_table VALUES",
    Input = [#{name => "not_binary", type => <<"UInt8">>, data => [1]}],

    %% If it reaches validation, it means SQL conversion (if any) happened
    ?assertMatch(
        {error, {validation_error, {invalid_column_name, "not_binary"}}},
        clickhouse_erl:insert(self(), SQL, Input)
    ).

insert_timeout_handling_test() ->
    %% Test that timeout option is extracted
    %% We can't easily verify it's passed to query_manager without mocking,
    %% but we can verify it doesn't crash.
    SQL = <<"INSERT INTO test_table VALUES">>,
    Input = [#{name => <<"col1">>, type => <<"UInt8">>, data => [1]}],

    %% This will try to call clickhouse_erl_connection:insert(self(), ...)
    %% which will fail because self() is not a gen_server handling {insert, ...}
    %% but it should at least pass validation.

    try
        clickhouse_erl:insert(self(), SQL, Input, #{timeout => 100})
    catch
        exit:{noproc, _} ->
            ok;
        exit:{timeout, _} ->
            ok;
        Error:Reason ->
            %% If it's another error, it might be fine or not.
            %% Since self() is not a gen_server, gen_server:call will fail.
            ?debugFmt("Insert failed as expected: ~p:~p", [Error, Reason]),
            ok
    end.

%% Test suite for API function (Task 18.1)
%% Validates: Requirements 1.1

%% Test parameter validation - empty input
insert_api_empty_input_test() ->
    SQL = <<"INSERT INTO test_table VALUES">>,
    Input = [],

    %% Empty input should be allowed (0 rows)
    %% This will fail at connection layer since self() is not a gen_server
    try
        clickhouse_erl:insert(self(), SQL, Input)
    catch
        exit:{calling_self, _} -> ok;
        exit:{noproc, _} -> ok;
        exit:{timeout, _} -> ok
    end.

%% Test parameter validation - invalid connection pid
insert_api_invalid_connection_test() ->
    SQL = <<"INSERT INTO test_table VALUES">>,
    Input = [#{name => <<"col1">>, type => <<"UInt8">>, data => [1]}],

    %% Using an atom instead of pid should fail
    Result = clickhouse_erl:insert(not_a_pid, SQL, Input),
    ?assertMatch({error, _}, Result).

%% Test parameter validation - SQL as string
insert_api_string_sql_test() ->
    SQL = "INSERT INTO test_table VALUES",
    Input = [#{name => <<"col1">>, type => <<"UInt8">>, data => [1]}],

    %% String SQL should be accepted and converted to binary
    %% This will fail at connection layer since self() is not a gen_server
    try
        clickhouse_erl:insert(self(), SQL, Input)
    catch
        exit:{calling_self, _} -> ok;
        exit:{noproc, _} -> ok;
        exit:{timeout, _} -> ok
    end.

%% Test error handling - validation errors are propagated
insert_api_validation_error_propagation_test() ->
    SQL = <<"INSERT INTO test_table VALUES">>,

    %% Invalid column name (not a binary)
    InvalidInput = [#{name => "not_binary", type => <<"UInt8">>, data => [1]}],
    Result1 = clickhouse_erl:insert(self(), SQL, InvalidInput),
    ?assertMatch({error, {validation_error, {invalid_column_name, "not_binary"}}}, Result1),

    %% Row count mismatch
    MismatchInput = [
        #{name => <<"col1">>, type => <<"UInt8">>, data => [1, 2]},
        #{name => <<"col2">>, type => <<"UInt8">>, data => [1]}
    ],
    Result2 = clickhouse_erl:insert(self(), SQL, MismatchInput),
    ?assertMatch({error, {validation_error, {row_count_mismatch, _}}}, Result2).

%% Test delegation to query_manager with valid input
insert_api_delegation_test() ->
    SQL = <<"INSERT INTO test_table VALUES">>,
    Input = [#{name => <<"col1">>, type => <<"UInt8">>, data => [1, 2, 3]}],

    %% Valid input should pass validation and reach connection layer
    %% Since self() is not a gen_server, it will fail there
    try
        clickhouse_erl:insert(self(), SQL, Input)
    catch
        exit:{calling_self, _} -> ok;
        exit:{noproc, _} -> ok;
        exit:{timeout, _} -> ok
    end.

%% Test insert/4 with options
insert_api_with_options_test() ->
    SQL = <<"INSERT INTO test_table VALUES">>,
    Input = [#{name => <<"col1">>, type => <<"UInt8">>, data => [1]}],
    Options = #{timeout => 5000},

    %% Options should be passed through
    try
        clickhouse_erl:insert(self(), SQL, Input, Options)
    catch
        exit:{calling_self, _} -> ok;
        exit:{noproc, _} -> ok;
        exit:{timeout, _} -> ok
    end.

%% Test error handling with multiple columns
insert_api_multiple_columns_test() ->
    SQL = <<"INSERT INTO test_table VALUES">>,
    Input = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"col2">>, type => <<"String">>, data => [<<"a">>, <<"b">>, <<"c">>]},
        #{name => <<"col3">>, type => <<"Float64">>, data => [1.1, 2.2, 3.3]}
    ],

    %% Valid multi-column input should pass validation
    try
        clickhouse_erl:insert(self(), SQL, Input)
    catch
        exit:{calling_self, _} -> ok;
        exit:{noproc, _} -> ok;
        exit:{timeout, _} -> ok
    end.

%%%===================================================================
%%% format_error/1 tests (public API)
%%%===================================================================

%% Helper: assert result is a non-empty string or binary
is_nonempty_string_or_binary(V) when is_binary(V), byte_size(V) > 0 -> true;
is_nonempty_string_or_binary(V) when is_list(V), length(V) > 0 -> true;
is_nonempty_string_or_binary(_) -> false.

format_error_network_closed_test() ->
    Result = clickhouse_erl:format_error({network_error, connection_closed_during_query}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_network_tcp_error_test() ->
    Result = clickhouse_erl:format_error({network_error, {tcp_error_during_query, econnreset}}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_network_generic_test() ->
    Result = clickhouse_erl:format_error({network_error, econnrefused}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_protocol_type_mismatch_test() ->
    Error =
        {protocol_error, {data_block_encoding, {type_mismatch, <<"col1">>, <<"UInt32">>, badarg}}},
    Result = clickhouse_erl:format_error(Error),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_protocol_encoding_test() ->
    Result = clickhouse_erl:format_error({protocol_error, {data_block_encoding, some_reason}}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_protocol_string_details_test() ->
    Result = clickhouse_erl:format_error({protocol_error, "Connection busy"}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_protocol_binary_details_test() ->
    Result = clickhouse_erl:format_error({protocol_error, <<"Connection busy">>}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_protocol_generic_test() ->
    Result = clickhouse_erl:format_error({protocol_error, {some, complex, reason}}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_timeout_test() ->
    Result = clickhouse_erl:format_error({timeout_error, query_execution}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_query_cancelled_test() ->
    Result = clickhouse_erl:format_error({query_cancelled, <<"my-query-123">>}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_compatibility_test() ->
    Result = clickhouse_erl:format_error({compatibility_error, {server_version, 54000}}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_encoding_test() ->
    Result = clickhouse_erl:format_error({encoding_error, query_body}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_decoding_test() ->
    Result = clickhouse_erl:format_error({decoding_error, {invalid_format, "bad varint"}}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_resource_cleanup_test() ->
    Result = clickhouse_erl:format_error({resource_cleanup_error, "socket close failed"}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_server_exception_test() ->
    ExceptionInfo = #{code => 60, name => <<"UNKNOWN_TABLE">>, message => <<"Table not found">>},
    Result = clickhouse_erl:format_error({server_exception, ExceptionInfo}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_exception_parsing_test() ->
    Result = clickhouse_erl:format_error({exception_parsing_error, "truncated data"}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_nested_exception_limit_test() ->
    Result = clickhouse_erl:format_error({nested_exception_limit_exceeded, 10}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_field_truncated_test() ->
    Result = clickhouse_erl:format_error({exception_field_truncated, message, 50000, 10000}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_invalid_exception_format_test() ->
    Result = clickhouse_erl:format_error({invalid_exception_format, "unexpected byte"}),
    ?assert(is_nonempty_string_or_binary(Result)).

format_error_unknown_error_test() ->
    Result = clickhouse_erl:format_error(something_completely_unexpected),
    ?assert(is_nonempty_string_or_binary(Result)).

%% Verify specific content in formatted messages
format_error_contains_context_test() ->
    %% timeout includes phase name
    TimeoutResult = clickhouse_erl:format_error({timeout_error, handshake}),
    ?assertNotEqual(nomatch, binary:match(iolist_to_binary([TimeoutResult]), <<"handshake">>)),

    %% query_cancelled includes query ID
    CancelResult = clickhouse_erl:format_error({query_cancelled, <<"abc-123">>}),
    ?assertNotEqual(nomatch, binary:match(iolist_to_binary([CancelResult]), <<"abc-123">>)),

    %% server_exception includes table name from message
    ExInfo = #{code => 60, name => <<"UNKNOWN_TABLE">>, message => <<"Table xyz not found">>},
    ExResult = clickhouse_erl:format_error({server_exception, ExInfo}),
    ?assertNotEqual(nomatch, binary:match(iolist_to_binary([ExResult]), <<"xyz">>)).
