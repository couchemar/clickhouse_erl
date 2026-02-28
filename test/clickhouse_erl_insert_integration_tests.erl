-module(clickhouse_erl_insert_integration_tests).

-include_lib("eunit/include/eunit.hrl").
-include("../src/clickhouse_erl_protocol.hrl").

-define(CONNECT_TIMEOUT, 5000).

insert_integration_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Conn) ->
        {timeout, 120, [
            {"Test single row insert", ?_test(test_insert_single_row(Conn))},
            {"Test multi-row insert", ?_test(test_insert_multi_row(Conn))},
            {"Test empty data insert", ?_test(test_insert_empty_data(Conn))},
            {"Test diverse data types", ?_test(test_insert_diverse_types(Conn))},
            {"Test validation error (client-side)", ?_test(test_insert_validation_error(Conn))},
            {"Test server exception (unknown table)", ?_test(test_insert_server_exception(Conn))}
        ]}
    end}.

setup() ->
    test_helpers:setup(),
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        timeout => ?CONNECT_TIMEOUT
    },
    case
        clickhouse_erl:connect(
            test_helpers:clickhouse_host(),
            test_helpers:clickhouse_port(),
            Options
        )
    of
        {ok, Conn} ->
            Conn;
        {error, Reason} ->
            error({connection_failed, Reason})
    end.

cleanup(Conn) ->
    clickhouse_erl:disconnect(Conn),
    test_helpers:cleanup().

test_insert_single_row(Conn) ->
    Table = <<"test_single_row">>,
    %% Setup table
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (id UInt32, name String) ENGINE = Memory">>
    ),

    %% Insert data
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1]},
        #{name => <<"name">>, type => <<"String">>, data => [<<"Alice">>]}
    ],
    SQL = <<"INSERT INTO ", Table/binary, " (id, name) VALUES">>,
    {ok, Result} = clickhouse_erl:insert(Conn, SQL, Input),

    ?assertEqual(1, maps:get(rows_inserted, Result)),

    %% Verify data
    {ok, QueryResult} = clickhouse_erl:query(
        Conn, <<"SELECT id, name FROM ", Table/binary, " ORDER BY id">>
    ),
    ?assertEqual([[1, <<"Alice">>]], maps:get(rows, maps:get(data, QueryResult))).

test_insert_multi_row(Conn) ->
    Table = <<"test_multi_row">>,
    %% Setup table
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (id UInt32) ENGINE = Memory">>),

    %% Insert data
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4, 5]}
    ],
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    {ok, Result} = clickhouse_erl:insert(Conn, SQL, Input),

    ?assertEqual(5, maps:get(rows_inserted, Result)),

    %% Verify data
    {ok, QueryResult} = clickhouse_erl:query(Conn, <<"SELECT count() FROM ", Table/binary>>),
    ?assertEqual([[5]], maps:get(rows, maps:get(data, QueryResult))).

test_insert_empty_data(Conn) ->
    Table = <<"test_empty_insert">>,
    %% Setup table
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (id UInt32) ENGINE = Memory">>),

    %% Insert empty data
    Input = [
        #{name => <<"id">>, type => <<"UInt32">>, data => []}
    ],
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    {ok, Result} = clickhouse_erl:insert(Conn, SQL, Input),

    ?assertEqual(0, maps:get(rows_inserted, Result)),

    %% Verify data
    {ok, QueryResult} = clickhouse_erl:query(Conn, <<"SELECT count() FROM ", Table/binary>>),
    ?assertEqual([[0]], maps:get(rows, maps:get(data, QueryResult))).

test_insert_diverse_types(Conn) ->
    Table = <<"test_diverse_types">>,
    %% Setup table
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

    %% Prepare data across various types
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

    %% Verify data
    {ok, QueryResult} = clickhouse_erl:query(Conn, <<"SELECT * FROM ", Table/binary>>),
    Rows = maps:get(rows, maps:get(data, QueryResult)),
    ?assertEqual(1, length(Rows)),
    [Row] = Rows,

    %% Note: ClickHouse returns results in raw format for some types
    ?assertEqual(42, lists:nth(1, Row)),
    ?assertEqual(-100, lists:nth(2, Row)),
    ?assert(abs(3.14159 - lists:nth(3, Row)) < 0.00001),
    ?assertEqual(<<"Hello ClickHouse">>, lists:nth(4, Row)),
    %% Bool is returned as 1/0
    ?assertEqual(1, lists:nth(5, Row)),
    %% Date is returned as days since epoch (raw UInt16 value)

    % 2023-01-01 = 19358 days since 1970-01-01
    ?assertEqual(19358, lists:nth(6, Row)),
    %% DateTime is returned as Unix timestamp (raw UInt32 value)

    % 2023-01-01 12:00:00 UTC
    ?assertEqual(1672574400, lists:nth(7, Row)).

test_insert_validation_error(Conn) ->
    SQL = <<"INSERT INTO test VALUES">>,
    %% Mismatched row count
    Input = [
        #{name => <<"col1">>, type => <<"UInt8">>, data => [1, 2]},
        #{name => <<"col2">>, type => <<"UInt8">>, data => [1]}
    ],
    Result = clickhouse_erl:insert(Conn, SQL, Input),
    ?assertMatch({error, {validation_error, {row_count_mismatch, _}}}, Result).

test_insert_server_exception(Conn) ->
    SQL = <<"INSERT INTO non_existent_table VALUES">>,
    Input = [#{name => <<"id">>, type => <<"UInt32">>, data => [1]}],
    Result = clickhouse_erl:insert(Conn, SQL, Input),
    %% Server returns error 60 "Table does not exist" when trying to INSERT into non-existent table
    ?assertMatch({error, {server_exception, #exception_info{error_code = 60}}}, Result).

%% --- Internal Helpers ---

execute(Conn, SQL) ->
    case clickhouse_erl:query(Conn, SQL) of
        {ok, _} -> ok;
        {error, Reason} -> error({query_failed, SQL, Reason})
    end.
