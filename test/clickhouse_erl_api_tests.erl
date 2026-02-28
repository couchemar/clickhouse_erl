-module(clickhouse_erl_api_tests).

-include_lib("eunit/include/eunit.hrl").

api_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"Test insert/3 valid input", fun test_insert_3_valid/0},
        {"Test insert/3 SQL string conversion", fun test_insert_3_sql_conversion/0},
        {"Test insert/4 custom timeout", fun test_insert_4_timeout/0},
        {"Test error propagation", fun test_error_propagation/0}
    ]}.

setup() ->
    meck:new(clickhouse_erl_query_manager, [passthrough]),
    ok.

cleanup(_) ->
    meck:unload(clickhouse_erl_query_manager),
    ok.

test_insert_3_valid() ->
    Conn = self(),
    SQL = <<"INSERT INTO test VALUES">>,
    Input = [#{name => <<"id">>, type => <<"UInt32">>, data => [1]}],

    meck:expect(clickhouse_erl_query_manager, execute_insert, fun(_C, _S, _I, _T) ->
        {ok, #{rows_inserted => 1}}
    end),

    Result = clickhouse_erl:insert(Conn, SQL, Input),

    ?assertEqual({ok, #{rows_inserted => 1}}, Result),
    ?assert(meck:called(clickhouse_erl_query_manager, execute_insert, [Conn, SQL, Input, 30000])).

test_insert_3_sql_conversion() ->
    Conn = self(),
    SQL = "INSERT INTO test VALUES",
    BinSQL = <<"INSERT INTO test VALUES">>,
    Input = [#{name => <<"id">>, type => <<"UInt32">>, data => [1]}],

    meck:expect(clickhouse_erl_query_manager, execute_insert, fun(_C, _S, _I, _T) ->
        {ok, #{rows_inserted => 1}}
    end),

    Result = clickhouse_erl:insert(Conn, SQL, Input),

    ?assertEqual({ok, #{rows_inserted => 1}}, Result),
    ?assert(
        meck:called(clickhouse_erl_query_manager, execute_insert, [Conn, BinSQL, Input, 30000])
    ).

test_insert_4_timeout() ->
    Conn = self(),
    SQL = <<"INSERT INTO test VALUES">>,
    Input = [#{name => <<"id">>, type => <<"UInt32">>, data => [1]}],
    Options = #{timeout => 5000},

    meck:expect(clickhouse_erl_query_manager, execute_insert, fun(_C, _S, _I, _T) ->
        {ok, #{rows_inserted => 1}}
    end),

    Result = clickhouse_erl:insert(Conn, SQL, Input, Options),

    ?assertEqual({ok, #{rows_inserted => 1}}, Result),
    ?assert(meck:called(clickhouse_erl_query_manager, execute_insert, [Conn, SQL, Input, 5000])).

test_error_propagation() ->
    Conn = self(),
    SQL = <<"INSERT INTO test VALUES">>,
    Input = [],
    Error = {error, {validation_error, empty_input}},

    meck:expect(clickhouse_erl_query_manager, execute_insert, fun(_C, _S, _I, _T) ->
        Error
    end),

    Result = clickhouse_erl:insert(Conn, SQL, Input),

    ?assertEqual(Error, Result),
    ?assert(meck:called(clickhouse_erl_query_manager, execute_insert, [Conn, SQL, Input, 30000])).
