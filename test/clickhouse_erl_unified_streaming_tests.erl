%% @doc Unit tests for unified streaming processing.
%% Tests the default_on_data_callback/2 function and related helpers.
-module(clickhouse_erl_unified_streaming_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Default callback: data accumulation
%%%===================================================================

%% @doc Single column with multiple values produces correct batch format.
default_callback_single_column_test() ->
    Acc0 = initial_default_acc(),
    %% Column meta event
    {ok, Acc1} = clickhouse_erl_connection:default_on_data_callback(
        {column_meta, #{name => <<"id">>, type => <<"UInt64">>}}, Acc0
    ),
    %% Data events
    {ok, Acc2} = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"id">>, type => <<"UInt64">>, value => 1}}, Acc1
    ),
    {ok, Acc3} = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"id">>, type => <<"UInt64">>, value => 2}}, Acc2
    ),
    {ok, Acc4} = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"id">>, type => <<"UInt64">>, value => 3}}, Acc3
    ),
    %% End event
    {ok, Result} = clickhouse_erl_connection:default_on_data_callback('end', Acc4),
    ?assertEqual(
        #{
            columns => [#{name => <<"id">>, type => <<"UInt64">>}],
            rows => [[1], [2], [3]]
        },
        Result
    ).

%% @doc Multiple columns produce correct row-oriented transposition.
default_callback_multi_column_test() ->
    Acc0 = initial_default_acc(),
    %% Column 1 meta + data
    {ok, Acc1} = clickhouse_erl_connection:default_on_data_callback(
        {column_meta, #{name => <<"name">>, type => <<"String">>}}, Acc0
    ),
    {ok, Acc2} = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"name">>, type => <<"String">>, value => <<"alice">>}}, Acc1
    ),
    {ok, Acc3} = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"name">>, type => <<"String">>, value => <<"bob">>}}, Acc2
    ),
    %% Column 2 meta + data
    {ok, Acc4} = clickhouse_erl_connection:default_on_data_callback(
        {column_meta, #{name => <<"age">>, type => <<"UInt8">>}}, Acc3
    ),
    {ok, Acc5} = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"age">>, type => <<"UInt8">>, value => 30}}, Acc4
    ),
    {ok, Acc6} = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"age">>, type => <<"UInt8">>, value => 25}}, Acc5
    ),
    %% End
    {ok, Result} = clickhouse_erl_connection:default_on_data_callback('end', Acc6),
    ?assertEqual(
        #{
            columns => [
                #{name => <<"name">>, type => <<"String">>},
                #{name => <<"age">>, type => <<"UInt8">>}
            ],
            rows => [
                [<<"alice">>, 30],
                [<<"bob">>, 25]
            ]
        },
        Result
    ).

%%%===================================================================
%%% Default callback: zero rows
%%%===================================================================

%% @doc Zero-row query produces empty columns and rows.
default_callback_zero_rows_test() ->
    Acc0 = initial_default_acc(),
    {ok, Result} = clickhouse_erl_connection:default_on_data_callback('end', Acc0),
    ?assertEqual(#{columns => [], rows => []}, Result).

%%%===================================================================
%%% Default callback: multi-block same column
%%%===================================================================

%% @doc Multi-block results append values to existing columns correctly.
default_callback_multi_block_test() ->
    Acc0 = initial_default_acc(),
    %% Block 1: column meta + 2 values
    {ok, Acc1} = clickhouse_erl_connection:default_on_data_callback(
        {column_meta, #{name => <<"x">>, type => <<"Int32">>}}, Acc0
    ),
    {ok, Acc2} = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"x">>, type => <<"Int32">>, value => 10}}, Acc1
    ),
    {ok, Acc3} = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"x">>, type => <<"Int32">>, value => 20}}, Acc2
    ),
    %% Block 2: same column, 2 more values (no new column_meta — first occurrence wins)
    {ok, Acc4} = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"x">>, type => <<"Int32">>, value => 30}}, Acc3
    ),
    {ok, Acc5} = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"x">>, type => <<"Int32">>, value => 40}}, Acc4
    ),
    %% End
    {ok, Result} = clickhouse_erl_connection:default_on_data_callback('end', Acc5),
    ?assertEqual(
        #{
            columns => [#{name => <<"x">>, type => <<"Int32">>}],
            rows => [[10], [20], [30], [40]]
        },
        Result
    ).

%%%===================================================================
%%% Default callback: column_meta first-occurrence wins
%%%===================================================================

%% @doc Column metadata uses first occurrence when same column appears again.
default_callback_column_meta_first_wins_test() ->
    Acc0 = initial_default_acc(),
    %% First occurrence with type Int32
    {ok, Acc1} = clickhouse_erl_connection:default_on_data_callback(
        {column_meta, #{name => <<"x">>, type => <<"Int32">>}}, Acc0
    ),
    %% Second occurrence with different type (should be ignored)
    {ok, Acc2} = clickhouse_erl_connection:default_on_data_callback(
        {column_meta, #{name => <<"x">>, type => <<"UInt64">>}}, Acc1
    ),
    {ok, Acc3} = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"x">>, type => <<"Int32">>, value => 1}}, Acc2
    ),
    {ok, Result} = clickhouse_erl_connection:default_on_data_callback('end', Acc3),
    %% Should use Int32 from first occurrence
    ?assertEqual(
        #{
            columns => [#{name => <<"x">>, type => <<"Int32">>}],
            rows => [[1]]
        },
        Result
    ).

%%%===================================================================
%%% Default callback: returns {ok, Acc} contract
%%%===================================================================

%% @doc Every invocation returns {ok, NewAcc} matching the callback contract.
default_callback_returns_ok_tuple_test() ->
    Acc0 = initial_default_acc(),
    Result1 = clickhouse_erl_connection:default_on_data_callback(
        {column_meta, #{name => <<"a">>, type => <<"String">>}}, Acc0
    ),
    ?assertMatch({ok, _}, Result1),
    {ok, Acc1} = Result1,
    Result2 = clickhouse_erl_connection:default_on_data_callback(
        {data, #{name => <<"a">>, type => <<"String">>, value => <<"v">>}}, Acc1
    ),
    ?assertMatch({ok, _}, Result2),
    {ok, Acc2} = Result2,
    Result3 = clickhouse_erl_connection:default_on_data_callback('end', Acc2),
    ?assertMatch({ok, _}, Result3).

%%%===================================================================
%%% validate_callback: undefined rejection
%%%===================================================================

%% @doc validate_callback rejects undefined for on_progress (Req 8.3).
validate_callback_on_progress_undefined_test() ->
    Result = clickhouse_erl_connection:validate_callback(on_progress, undefined),
    ?assertEqual({error, {invalid_callback_type, undefined}}, Result).

%% @doc validate_callback rejects undefined for on_profile (Req 8.3).
validate_callback_on_profile_undefined_test() ->
    Result = clickhouse_erl_connection:validate_callback(on_profile, undefined),
    ?assertEqual({error, {invalid_callback_type, undefined}}, Result).

%% @doc validate_callback rejects undefined for on_profile_events (Req 8.3).
validate_callback_on_profile_events_undefined_test() ->
    Result = clickhouse_erl_connection:validate_callback(on_profile_events, undefined),
    ?assertEqual({error, {invalid_callback_type, undefined}}, Result).

%% @doc validate_callback rejects undefined for on_data (Req 8.3).
validate_callback_on_data_undefined_test() ->
    Result = clickhouse_erl_connection:validate_callback(on_data, undefined),
    ?assertEqual({error, {invalid_callback_type, undefined}}, Result).

%%%===================================================================
%%% Helpers
%%%===================================================================

%% @doc Create the initial default callback accumulator.
initial_default_acc() ->
    #{
        column_order => [],
        column_meta => #{},
        column_values => #{}
    }.
