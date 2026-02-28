-module(clickhouse_erl_schema_integration_tests).

-include_lib("eunit/include/eunit.hrl").
-include("clickhouse_erl_protocol.hrl").

-define(CONNECT_TIMEOUT, 5000).

schema_error_integration_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Conn) ->
        [
            {"Non-existent column error reporting", ?_test(test_non_existent_column_error(Conn))},
            {"Unknown table error reporting", ?_test(test_unknown_table_error(Conn))}
        ]
    end}.

setup() ->
    test_helpers:setup(),
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        timeout => ?CONNECT_TIMEOUT
    },
    case
        clickhouse_erl_connection:connect(
            test_helpers:clickhouse_host(),
            test_helpers:clickhouse_port(),
            Options
        )
    of
        {ok, Conn} ->
            %% Create a test table
            clickhouse_erl:query(Conn, "DROP TABLE IF EXISTS schema_test"),
            clickhouse_erl:query(Conn, "CREATE TABLE schema_test (id UInt32) ENGINE = Log"),
            Conn;
        {error, Reason} ->
            error({connection_failed, Reason})
    end.

cleanup(Conn) ->
    clickhouse_erl:query(Conn, "DROP TABLE IF EXISTS schema_test"),
    clickhouse_erl_connection:disconnect(Conn),
    test_helpers:cleanup().

test_non_existent_column_error(Conn) ->
    %% Attempt to insert into a column that doesn't exist
    SQL = "INSERT INTO schema_test (id, non_existent_column) VALUES",
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1]},
        #{name => <<"non_existent_column">>, type => <<"UInt32">>, data => [1]}
    ],
    Result = clickhouse_erl:insert(Conn, SQL, Input),

    %% Should return {error, {server_exception, ExceptionInfo}}
    ?assertMatch({error, {server_exception, #exception_info{}}}, Result),
    {error, {server_exception, ExceptionInfo}} = Result,

    %% Verify it is identified as a schema error (Code 16 or 47)
    ?assert(clickhouse_erl_exception:is_schema_error(ExceptionInfo)),
    %% code 16 = NO_SUCH_COLUMN_IN_TABLE (or 47 depending on version)
    ?assert(lists:member(ExceptionInfo#exception_info.error_code, [16, 47])).

test_unknown_table_error(Conn) ->
    %% Attempt to insert into a table that doesn't exist
    SQL = "INSERT INTO non_existent_table (id) VALUES",
    Input = [#{name => <<"id">>, type => <<"UInt32">>, data => [1]}],
    Result = clickhouse_erl:insert(Conn, SQL, Input),

    %% Server may send exception and close connection, or we may get connection error
    %% Both are acceptable error responses for unknown table
    case Result of
        {error, {server_exception, ExceptionInfo}} ->
            %% Verify it is identified as a schema error (Code 60 = UNKNOWN_TABLE)
            ?assert(clickhouse_erl_exception:is_schema_error(ExceptionInfo)),
            ?assertEqual(60, ExceptionInfo#exception_info.error_code);
        {error, {connection_error, _}} ->
            %% Connection closed by server after exception - also acceptable
            ok;
        Other ->
            ?assertMatch({error, {server_exception, _}}, Other)
    end.
