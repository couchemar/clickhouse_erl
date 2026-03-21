-module(clickhouse_erl_insert_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("../src/clickhouse_erl_protocol.hrl").

-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).
-export([
    % Basic insert tests
    test_insert_single_row/1,
    test_insert_multi_row/1,
    test_insert_empty_data/1,
    % Type tests
    test_insert_diverse_types/1,
    % Error tests
    test_insert_validation_error/1,
    test_insert_server_exception/1,
    % Schema error tests
    test_non_existent_column_error/1,
    test_unknown_table_error/1
]).

-define(CONNECT_TIMEOUT, 5000).

suite() ->
    [{timetrap, {seconds, 120}}].

all() ->
    [
        {group, insert_basic},
        {group, insert_types},
        {group, insert_errors},
        {group, schema_errors}
    ].

groups() ->
    [
        {insert_basic, [sequence], [
            test_insert_single_row,
            test_insert_multi_row,
            test_insert_empty_data
        ]},
        {insert_types, [sequence], [
            test_insert_diverse_types
        ]},
        {insert_errors, [sequence], [
            test_insert_validation_error,
            test_insert_server_exception
        ]},
        {schema_errors, [sequence], [
            test_non_existent_column_error,
            test_unknown_table_error
        ]}
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

init_per_group(insert_basic, Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        timeout => ?CONNECT_TIMEOUT
    },
    {ok, Conn} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),
    [{connection, Conn}, {table_prefix, <<"test_basic">>} | Config];
init_per_group(insert_types, Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        timeout => ?CONNECT_TIMEOUT
    },
    {ok, Conn} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),
    [{connection, Conn}, {table_prefix, <<"test_types">>} | Config];
init_per_group(insert_errors, Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        timeout => ?CONNECT_TIMEOUT
    },
    {ok, Conn} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),
    [{connection, Conn}, {table_prefix, <<"test_errors">>} | Config];
init_per_group(schema_errors, Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        timeout => ?CONNECT_TIMEOUT
    },
    {ok, Conn} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),
    ok = execute(Conn, <<"DROP TABLE IF EXISTS schema_test">>),
    ok = execute(Conn, <<"CREATE TABLE schema_test (id UInt32) ENGINE = Memory">>),
    [{connection, Conn}, {table_prefix, <<"schema_test">>} | Config];
init_per_group(_Group, Config) ->
    Config.

end_per_group(insert_basic, Config) ->
    Conn = ?config(connection, Config),
    clickhouse_erl:disconnect(Conn),
    ok;
end_per_group(insert_types, Config) ->
    Conn = ?config(connection, Config),
    clickhouse_erl:disconnect(Conn),
    ok;
end_per_group(insert_errors, Config) ->
    Conn = ?config(connection, Config),
    clickhouse_erl:disconnect(Conn),
    ok;
end_per_group(schema_errors, Config) ->
    Conn = ?config(connection, Config),
    % Ignore errors on cleanup - connection may be closed
    _ = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS schema_test">>),
    clickhouse_erl:disconnect(Conn),
    ok;
end_per_group(_Group, _Config) ->
    ok.

%%%===================================================================
%%% Basic Insert Tests
%%%===================================================================

test_insert_single_row(Config) ->
    Conn = ?config(connection, Config),
    Table = <<(?config(table_prefix, Config))/binary, "_single_row">>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (id UInt32, name String) ENGINE = Memory">>
    ),

    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1]},
        #{name => <<"name">>, type => <<"String">>, data => [<<"Alice">>]}
    ],
    SQL = <<"INSERT INTO ", Table/binary, " (id, name) VALUES">>,
    {ok, Result} = clickhouse_erl:insert(Conn, SQL, Input),

    ?assertEqual(1, maps:get(rows_inserted, Result)),

    {ok, QueryResult} = clickhouse_erl:query(
        Conn, <<"SELECT id, name FROM ", Table/binary, " ORDER BY id">>
    ),
    ?assertEqual([[1, <<"Alice">>]], maps:get(rows, maps:get(data, QueryResult))).

test_insert_multi_row(Config) ->
    Conn = ?config(connection, Config),
    Table = <<(?config(table_prefix, Config))/binary, "_multi_row">>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (id UInt32) ENGINE = Memory">>),

    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4, 5]}
    ],
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    {ok, Result} = clickhouse_erl:insert(Conn, SQL, Input),

    ?assertEqual(5, maps:get(rows_inserted, Result)),

    {ok, QueryResult} = clickhouse_erl:query(Conn, <<"SELECT count() FROM ", Table/binary>>),
    ?assertEqual([[5]], maps:get(rows, maps:get(data, QueryResult))).

test_insert_empty_data(Config) ->
    Conn = ?config(connection, Config),
    Table = <<(?config(table_prefix, Config))/binary, "_empty">>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (id UInt32) ENGINE = Memory">>),

    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => []}
    ],
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    {ok, Result} = clickhouse_erl:insert(Conn, SQL, Input),

    ?assertEqual(0, maps:get(rows_inserted, Result)),

    {ok, QueryResult} = clickhouse_erl:query(Conn, <<"SELECT count() FROM ", Table/binary>>),
    ?assertEqual([[0]], maps:get(rows, maps:get(data, QueryResult))).

%%%===================================================================
%%% Type Tests
%%%===================================================================

test_insert_diverse_types(Config) ->
    Conn = ?config(connection, Config),
    Table = <<(?config(table_prefix, Config))/binary, "_diverse">>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn,
        <<"CREATE TABLE ", Table/binary,
            " (\n"
            "            u8 UInt8,\n"
            "            i32 Int32,\n"
            "            f64 Float64,\n"
            "            s String,\n"
            "            b Bool,\n"
            "            d Date,\n"
            "            dt DateTime\n"
            "        ) ENGINE = Memory">>
    ),

    Date = {2023, 1, 1},
    DateTime = {{2023, 1, 1}, {12, 0, 0}},

    Input = [
        #{name => <<"u8">>, type => <<"UInt8">>, data => [42]},
        #{name => <<"i32">>, type => <<"Int32">>, data => [-100]},
        #{name => <<"f64">>, type => <<"Float64">>, data => [3.14159]},
        #{name => <<"s">>, type => <<"String">>, data => [<<"Hello ClickHouse">>]},
        #{name => <<"b">>, type => <<"Bool">>, data => [true]},
        #{name => <<"d">>, type => <<"Date">>, data => [Date]},
        #{name => <<"dt">>, type => <<"DateTime">>, data => [DateTime]}
    ],

    SQL = <<"INSERT INTO ", Table/binary, " VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, SQL, Input),

    {ok, QueryResult} = clickhouse_erl:query(Conn, <<"SELECT * FROM ", Table/binary>>),
    Rows = maps:get(rows, maps:get(data, QueryResult)),
    ?assertEqual(1, length(Rows)),
    [Row] = Rows,

    ?assertEqual(42, lists:nth(1, Row)),
    ?assertEqual(-100, lists:nth(2, Row)),
    ?assert(abs(3.14159 - lists:nth(3, Row)) < 0.00001),
    ?assertEqual(<<"Hello ClickHouse">>, lists:nth(4, Row)),
    ?assertEqual(true, lists:nth(5, Row)),
    ?assertEqual({2023, 1, 1}, lists:nth(6, Row)),
    ?assertEqual({{2023, 1, 1}, {12, 0, 0}}, lists:nth(7, Row)).

%%%===================================================================
%%% Error Tests
%%%===================================================================

test_insert_validation_error(Config) ->
    Conn = ?config(connection, Config),
    SQL = <<"INSERT INTO test VALUES">>,
    Input = [
        #{name => <<"col1">>, type => <<"UInt8">>, data => [1, 2]},
        #{name => <<"col2">>, type => <<"UInt8">>, data => [1]}
    ],
    Result = clickhouse_erl:insert(Conn, SQL, Input),
    ?assertMatch({error, {validation_error, {row_count_mismatch, _}}}, Result).

test_insert_server_exception(Config) ->
    Conn = ?config(connection, Config),
    SQL = <<"INSERT INTO non_existent_table VALUES">>,
    Input = [#{name => <<"id">>, type => <<"UInt32">>, data => [1]}],
    Result = clickhouse_erl:insert(Conn, SQL, Input),
    ?assertMatch({error, {server_exception, #{code := 60}}}, Result).

%%%===================================================================
%%% Schema Error Tests
%%%===================================================================

test_non_existent_column_error(Config) ->
    Conn = ?config(connection, Config),
    SQL = <<"INSERT INTO schema_test (id, non_existent_column) VALUES">>,
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1]},
        #{name => <<"non_existent_column">>, type => <<"UInt32">>, data => [1]}
    ],
    Result = clickhouse_erl:insert(Conn, SQL, Input),

    ?assertMatch({error, {server_exception, #{code := _}}}, Result),
    {error, {server_exception, ExceptionInfo}} = Result,

    ?assert(clickhouse_erl_exception:is_schema_error(ExceptionInfo)),
    Code = maps:get(code, ExceptionInfo),
    ?assert(lists:member(Code, [16, 47])).

test_unknown_table_error(Config) ->
    Conn = ?config(connection, Config),
    SQL = <<"INSERT INTO non_existent_table (id) VALUES">>,
    Input = [#{name => <<"id">>, type => <<"UInt32">>, data => [1]}],
    Result = clickhouse_erl:insert(Conn, SQL, Input),

    % Server may return exception or close connection
    case Result of
        {error, {server_exception, #{code := 60} = ExceptionInfo}} ->
            ?assert(clickhouse_erl_exception:is_schema_error(ExceptionInfo));
        {error, {connection_error, _}} ->
            % Connection closed by server after exception - acceptable
            ok
    end.

%%%===================================================================
%%% Internal Helpers
%%%===================================================================

execute(Conn, SQL) ->
    case clickhouse_erl:query(Conn, SQL) of
        {ok, _} -> ok;
        {error, Reason} -> ct:fail({query_failed, SQL, Reason})
    end.
