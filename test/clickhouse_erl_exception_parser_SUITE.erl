%% @doc Common Test suite for SERVER_EXCEPTION parsing with event-driven parser
%%
%% This suite verifies that SERVER_EXCEPTION packets during query execution
%% are handled by the event-driven parser (clickhouse_erl_parser).
-module(clickhouse_erl_exception_parser_SUITE).
-include_lib("common_test/include/ct.hrl").
-include("clickhouse_erl_protocol.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).

%% Test cases
-export([
    invalid_syntax_exception/1,
    missing_table_exception/1,
    type_mismatch_exception/1
]).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

suite() ->
    [{timetrap, {seconds, 30}}].

all() ->
    [{group, exception_parsing}].

groups() ->
    [
        {exception_parsing, [sequence], [
            invalid_syntax_exception,
            missing_table_exception,
            type_mismatch_exception
        ]}
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

init_per_group(exception_parsing, Config) ->
    {ok, Conn} = test_helpers:connect(),
    [{connection, Conn} | Config].

end_per_group(exception_parsing, Config) ->
    Conn = ?config(connection, Config),
    test_helpers:disconnect(Conn),
    ok.

%%%===================================================================
%%% Test Cases
%%%===================================================================

%% @doc Test that invalid SQL syntax triggers SERVER_EXCEPTION with event-driven parser
invalid_syntax_exception(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query with invalid syntax
    PreparedRequest = #{
        sql => <<"SELECT invalid syntax">>,
        query_id => <<"exception-test-query">>
    },

    %% Query should return server_exception error
    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),

    %% Verify we got a server exception
    {error, {server_exception, ExceptionInfo}} = Result,

    %% ExceptionInfo is a map from event-driven parser
    ErrorCode = maps:get(code, ExceptionInfo),
    ExceptionName = maps:get(name, ExceptionInfo),
    Message = maps:get(message, ExceptionInfo),
    StackTrace = maps:get(stack_trace, ExceptionInfo),

    %% Verify error code is non-zero
    true = ErrorCode =/= 0,

    %% Verify exception name is not empty
    true = byte_size(ExceptionName) > 0,

    %% Verify message is not empty
    true = byte_size(Message) > 0,

    %% Verify stack trace is not empty
    true = byte_size(StackTrace) > 0,

    ct:pal("Exception parsed successfully: ~p", [ExceptionInfo]),
    ok.

%% @doc Test that missing table exception is handled correctly
missing_table_exception(Config) ->
    Conn = ?config(connection, Config),

    %% Query non-existent table
    PreparedRequest = #{
        sql => <<"SELECT * FROM nonexistent_table_12345">>,
        query_id => <<"missing-table-test">>
    },

    Result = clickhouse_erl_connection:query(Conn, PreparedRequest),

    %% Should get server exception
    {error, {server_exception, ExceptionInfo}} = Result,

    %% Verify exception contains table name in message
    Message = maps:get(message, ExceptionInfo),
    case binary:match(Message, <<"nonexistent_table">>) of
        nomatch -> ct:fail("Expected 'nonexistent_table' in message");
        _ -> ok
    end,

    ct:pal("Missing table exception: ~s", [Message]),
    ok.

%% @doc Test that type mismatch exception is handled correctly
type_mismatch_exception(Config) ->
    Conn = ?config(connection, Config),

    %% Create a table with specific types
    CreateTable = <<
        "CREATE TABLE IF NOT EXISTS test_type_mismatch_exception "
        "(id UInt32, value String) ENGINE = Memory"
    >>,
    {ok, _} = clickhouse_erl_connection:query(Conn, #{sql => CreateTable}),

    %% Try to insert wrong type (string where UInt32 expected)
    %% This should trigger a type mismatch exception
    InsertQuery = <<"INSERT INTO test_type_mismatch_exception VALUES ('not_a_number', 'test')">>,
    Result = clickhouse_erl_connection:query(Conn, #{sql => InsertQuery}),

    %% Should get server exception
    {error, {server_exception, ExceptionInfo}} = Result,

    ErrorCode = maps:get(code, ExceptionInfo),
    Message = maps:get(message, ExceptionInfo),

    ct:pal("Type mismatch exception - Code: ~p, Message: ~s", [ErrorCode, Message]),

    %% Cleanup
    DropTable = <<"DROP TABLE IF EXISTS test_type_mismatch_exception">>,
    clickhouse_erl_connection:query(Conn, #{sql => DropTable}),

    ok.
