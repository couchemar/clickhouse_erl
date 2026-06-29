%% @doc Common Test suite for complex/composite type streaming integration tests
%%
%% Tests SELECT queries returning Array, Nullable, Tuple, Map, and LowCardinality
%% columns via the event-driven streaming parser against a real ClickHouse server.
%%
%% Feature: streamable-packet-parsing (Task 8.5.7.7)
-module(clickhouse_erl_complex_types_streaming_SUITE).

-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Test cases - Nullable
-export([
    nullable_integers/1,
    nullable_strings/1,
    nullable_all_nulls/1,
    nullable_no_nulls/1
]).

%% Test cases - Array
-export([
    array_integers/1,
    array_strings/1,
    array_empty/1,
    array_nested/1
]).

%% Test cases - Tuple
-export([
    tuple_mixed_types/1,
    tuple_single_element/1
]).

%% Test cases - Map
-export([
    map_string_to_int/1,
    map_string_to_string/1,
    map_empty/1
]).

%% Test cases - LowCardinality
-export([
    low_cardinality_string/1,
    low_cardinality_nullable_string/1
]).

%% Test cases - Nested Combinations
-export([
    nullable_array/1,
    array_nullable/1,
    map_with_array_values/1
]).

%% Test cases - Streaming Callback Mode
-export([
    streaming_nullable/1,
    streaming_array/1,
    streaming_map/1,
    streaming_mixed_complex_columns/1
]).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

suite() ->
    [{timetrap, {minutes, 2}}].

all() ->
    [
        {group, nullable_types},
        {group, array_types},
        {group, tuple_types},
        {group, map_types},
        {group, low_cardinality_types},
        {group, nested_combinations},
        {group, streaming_callback}
    ].

groups() ->
    [
        {nullable_types, [], [
            nullable_integers,
            nullable_strings,
            nullable_all_nulls,
            nullable_no_nulls
        ]},
        {array_types, [], [
            array_integers,
            array_strings,
            array_empty,
            array_nested
        ]},
        {tuple_types, [], [
            tuple_mixed_types,
            tuple_single_element
        ]},
        {map_types, [], [
            map_string_to_int,
            map_string_to_string,
            map_empty
        ]},
        {low_cardinality_types, [], [
            low_cardinality_string,
            low_cardinality_nullable_string
        ]},
        {nested_combinations, [], [
            nullable_array,
            array_nullable,
            map_with_array_values
        ]},
        {streaming_callback, [], [
            streaming_nullable,
            streaming_array,
            streaming_map,
            streaming_mixed_complex_columns
        ]}
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

init_per_testcase(_TestCase, Config) ->
    case test_helpers:connect() of
        {ok, Conn} ->
            [{connection, Conn} | Config];
        {error, Reason} ->
            {skip, {connection_failed, Reason}}
    end.

end_per_testcase(_TestCase, Config) ->
    Conn = ?config(connection, Config),
    try
        test_helpers:disconnect(Conn)
    catch
        _:_ -> ok
    end,
    ok.

%%%===================================================================
%%% Test Cases: Nullable Types (batch mode)
%%%===================================================================

%% @doc Nullable integers with mix of null and non-null values
nullable_integers(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_nullable_int_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (val Nullable(Int32)) ENGINE = Memory">>),
    ok = execute(Conn, <<"INSERT INTO ", Table/binary, " VALUES (1), (NULL), (3), (NULL), (5)">>),

    SQL = <<"SELECT val FROM ", Table/binary, " ORDER BY val NULLS LAST">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    %% Non-null values come first (ordered), then nulls
    5 = length(Rows),
    [[1], [3], [5], [null], [null]] = Rows,
    ct:pal("Nullable integer rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Nullable strings with mix of null and non-null values.
%% Nullable uses column-level encoding (null bitmap first, then values).
%% The streaming parser routes Nullable through column-level decode via
%% is_column_level_type/1, so this works correctly.
nullable_strings(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_nullable_str_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (val Nullable(String)) ENGINE = Memory">>
    ),
    ok = execute(Conn, <<"INSERT INTO ", Table/binary, " VALUES ('hello'), (NULL), ('world')">>),

    SQL = <<"SELECT val FROM ", Table/binary, " ORDER BY val NULLS LAST">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    3 = length(Rows),
    %% Ordered: non-null values first (alphabetical), then nulls
    [[<<"hello">>], [<<"world">>], [null]] = Rows,
    ct:pal("Nullable string rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc All null values in a Nullable column
nullable_all_nulls(Config) ->
    Conn = ?config(connection, Config),
    SQL = <<
        "SELECT CAST(NULL AS Nullable(UInt32)) as val "
        "FROM system.numbers LIMIT 3"
    >>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    3 = length(Rows),
    %% All values should be null
    [[null], [null], [null]] = Rows,
    ct:pal("All-null rows: ~p", [Rows]).

%% @doc No null values in a Nullable column
nullable_no_nulls(Config) ->
    Conn = ?config(connection, Config),
    SQL = <<
        "SELECT toNullable(toUInt32(number)) as val "
        "FROM system.numbers LIMIT 5"
    >>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    5 = length(Rows),
    %% Values 0..4, all non-null
    [[0], [1], [2], [3], [4]] = Rows,
    ct:pal("No-null Nullable rows: ~p", [Rows]).

%%%===================================================================
%%% Test Cases: Array Types (batch mode)
%%%===================================================================

%% @doc Array of integers
array_integers(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_array_int_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (val Array(Int32)) ENGINE = Memory">>),
    ok = execute(Conn, <<"INSERT INTO ", Table/binary, " VALUES ([1, 2, 3]), ([4, 5]), ([6])">>),

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    3 = length(Rows),
    %% Each row is [ArrayValue] where ArrayValue is a list
    [[[1, 2, 3]], [[4, 5]], [[6]]] = Rows,
    ct:pal("Array integer rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Array of strings
array_strings(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_array_str_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (val Array(String)) ENGINE = Memory">>),
    ok = execute(
        Conn, <<"INSERT INTO ", Table/binary, " VALUES (['a', 'b']), (['c']), (['d', 'e', 'f'])">>
    ),

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    3 = length(Rows),
    [[[<<"a">>, <<"b">>]], [[<<"c">>]], [[<<"d">>, <<"e">>, <<"f">>]]] = Rows,
    ct:pal("Array string rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Empty arrays
array_empty(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_array_empty_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (val Array(Int32)) ENGINE = Memory">>),
    ok = execute(Conn, <<"INSERT INTO ", Table/binary, " VALUES ([]), ([1]), ([])">>),

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    3 = length(Rows),
    [[[]], [[1]], [[]]] = Rows,
    ct:pal("Array with empties rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Nested arrays: Array(Array(Int32))
array_nested(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_array_nested_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (val Array(Array(Int32))) ENGINE = Memory">>
    ),
    ok = execute(Conn, <<"INSERT INTO ", Table/binary, " VALUES ([[1, 2], [3]]), ([[4, 5, 6]])">>),

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    2 = length(Rows),
    [[[[1, 2], [3]]], [[[4, 5, 6]]]] = Rows,
    ct:pal("Nested array rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: Tuple Types (batch mode)
%%%===================================================================

%% @doc Tuple with mixed types: Tuple(String, Int32)
tuple_mixed_types(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_tuple_mixed_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (val Tuple(String, Int32)) ENGINE = Memory">>
    ),
    ok = execute(Conn, <<"INSERT INTO ", Table/binary, " VALUES (('Alice', 25)), (('Bob', 30))">>),

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    2 = length(Rows),
    [[{<<"Alice">>, 25}], [{<<"Bob">>, 30}]] = Rows,
    ct:pal("Tuple mixed rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Single-element tuple: Tuple(UInt64)
tuple_single_element(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_tuple_single_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (val Tuple(UInt64)) ENGINE = Memory">>),
    ok = execute(Conn, <<"INSERT INTO ", Table/binary, " VALUES ((100)), ((200)), ((300))">>),

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    3 = length(Rows),
    [[{100}], [{200}], [{300}]] = Rows,
    ct:pal("Tuple single-element rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: Map Types (batch mode)
%%%===================================================================

%% @doc Map(String, Int32)
map_string_to_int(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_map_s2i_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (val Map(String, Int32)) ENGINE = Memory">>
    ),
    ok = execute(Conn, <<"INSERT INTO ", Table/binary, " VALUES ({'a': 1, 'b': 2}), ({'c': 3})">>),

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    2 = length(Rows),
    [[#{<<"a">> := 1, <<"b">> := 2}], [#{<<"c">> := 3}]] = Rows,
    ct:pal("Map String->Int rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Map(String, String)
map_string_to_string(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_map_s2s_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (val Map(String, String)) ENGINE = Memory">>
    ),
    ok = execute(
        Conn,
        <<"INSERT INTO ", Table/binary,
            " VALUES ({'key1': 'val1', 'key2': 'val2'}), ({'key3': 'val3'})">>
    ),

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    2 = length(Rows),
    [
        [#{<<"key1">> := <<"val1">>, <<"key2">> := <<"val2">>}],
        [#{<<"key3">> := <<"val3">>}]
    ] = Rows,
    ct:pal("Map String->String rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Empty maps
map_empty(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_map_empty_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (val Map(String, Int32)) ENGINE = Memory">>
    ),
    ok = execute(Conn, <<"INSERT INTO ", Table/binary, " VALUES ({}), ({'a': 1}), ({})">>),

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    3 = length(Rows),
    [[#{}], [#{<<"a">> := 1}], [#{}]] = Rows,
    ct:pal("Map with empties rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: LowCardinality Types (batch mode)
%%%===================================================================

%% @doc LowCardinality(String) with dictionary encoding at column level.
low_cardinality_string(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_lc_str_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (val LowCardinality(String)) ENGINE = Memory">>
    ),
    ok = execute(
        Conn,
        <<"INSERT INTO ", Table/binary, " VALUES ('red'), ('green'), ('red'), ('blue'), ('green')">>
    ),

    SQL = <<"SELECT val FROM ", Table/binary, " ORDER BY val">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    5 = length(Rows),
    %% Ordered alphabetically: blue, green, green, red, red
    [[<<"blue">>], [<<"green">>], [<<"green">>], [<<"red">>], [<<"red">>]] = Rows,
    ct:pal("LowCardinality string rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc LowCardinality(Nullable(String)) with dictionary encoding and null support.
low_cardinality_nullable_string(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_lc_ns_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn,
        <<"CREATE TABLE ", Table/binary, " (val LowCardinality(Nullable(String))) ENGINE = Memory">>
    ),
    ok = execute(
        Conn, <<"INSERT INTO ", Table/binary, " VALUES ('a'), (NULL), ('b'), (NULL), ('a')">>
    ),

    SQL = <<"SELECT val FROM ", Table/binary, " ORDER BY val NULLS LAST">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    5 = length(Rows),
    %% Ordered: a, a, b, then nulls
    [[<<"a">>], [<<"a">>], [<<"b">>], [null], [null]] = Rows,
    ct:pal("LowCardinality Nullable string rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: Nested Combinations (batch mode)
%%%===================================================================

%% @doc Nullable(Array(Int32)) — not directly supported in ClickHouse tables,
%% but can be produced via CAST expressions
nullable_array(Config) ->
    Conn = ?config(connection, Config),
    SQL = <<"SELECT arrayMap(x -> x * 2, [1, 2, 3]) as val">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    1 = length(Rows),
    ct:pal("Array expression rows: ~p", [Rows]).

%% @doc Array(Nullable(Int32))
array_nullable(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_arr_null_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (val Array(Nullable(Int32))) ENGINE = Memory">>
    ),
    ok = execute(
        Conn, <<"INSERT INTO ", Table/binary, " VALUES ([1, NULL, 3]), ([NULL, NULL]), ([4, 5])">>
    ),

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    3 = length(Rows),
    %% Array(Nullable) uses tagged tuples: {value, V} for non-null, {null} for null
    [
        [[{value, 1}, {null}, {value, 3}]],
        [[{null}, {null}]],
        [[{value, 4}, {value, 5}]]
    ] = Rows,
    ct:pal("Array(Nullable) rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Map(String, Array(Int32))
map_with_array_values(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_map_arr_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (val Map(String, Array(Int32))) ENGINE = Memory">>
    ),
    ok = execute(
        Conn, <<"INSERT INTO ", Table/binary, " VALUES ({'nums': [1, 2, 3]}), ({'vals': [4, 5]})">>
    ),

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),

    2 = length(Rows),
    [[#{<<"nums">> := [1, 2, 3]}], [#{<<"vals">> := [4, 5]}]] = Rows,
    ct:pal("Map(String, Array) rows: ~p", [Rows]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: Streaming Callback Mode
%%%===================================================================

%% @doc Nullable values via on_data streaming callback.
%% Nullable columns are routed through column-level decode, producing correct results.
streaming_nullable(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_stream_null_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (val Nullable(Int32)) ENGINE = Memory">>),
    ok = execute(Conn, <<"INSERT INTO ", Table/binary, " VALUES (10), (NULL), (30)">>),

    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := Name, value := Value}}, Acc) ->
            Existing = maps:get(Name, Acc, []),
            {ok, Acc#{Name => [Value | Existing]}};
        ('end', Acc) ->
            {ok, maps:map(fun(_K, V) -> lists:reverse(V) end, Acc)}
    end,

    SQL = <<"SELECT val FROM ", Table/binary, " ORDER BY val NULLS LAST">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{}
    }),

    DataMap = maps:get(data, Result),
    Values = maps:get(<<"val">>, DataMap),
    3 = length(Values),
    %% Ordered: 10, 30, null
    [10, 30, null] = Values,
    ct:pal("Streaming nullable values: ~p", [Values]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Array values via on_data streaming callback
streaming_array(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_stream_arr_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (val Array(Int32)) ENGINE = Memory">>),
    ok = execute(Conn, <<"INSERT INTO ", Table/binary, " VALUES ([1, 2, 3]), ([4, 5]), ([6])">>),

    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := Name, value := Value}}, Acc) ->
            Existing = maps:get(Name, Acc, []),
            {ok, Acc#{Name => [Value | Existing]}};
        ('end', Acc) ->
            {ok, maps:map(fun(_K, V) -> lists:reverse(V) end, Acc)}
    end,

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{}
    }),

    DataMap = maps:get(data, Result),
    Values = maps:get(<<"val">>, DataMap),
    3 = length(Values),
    [[1, 2, 3], [4, 5], [6]] = Values,
    ct:pal("Streaming array values: ~p", [Values]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Map values via on_data streaming callback
streaming_map(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_stream_map_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (val Map(String, Int32)) ENGINE = Memory">>
    ),
    ok = execute(Conn, <<"INSERT INTO ", Table/binary, " VALUES ({'x': 1, 'y': 2}), ({'z': 3})">>),

    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := Name, value := Value}}, Acc) ->
            Existing = maps:get(Name, Acc, []),
            {ok, Acc#{Name => [Value | Existing]}};
        ('end', Acc) ->
            {ok, maps:map(fun(_K, V) -> lists:reverse(V) end, Acc)}
    end,

    SQL = <<"SELECT val FROM ", Table/binary>>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{}
    }),

    DataMap = maps:get(data, Result),
    Values = maps:get(<<"val">>, DataMap),
    2 = length(Values),
    [#{<<"x">> := 1, <<"y">> := 2}, #{<<"z">> := 3}] = Values,
    ct:pal("Streaming map values: ~p", [Values]),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Multiple complex type columns via streaming callback.
%% Nullable(Float64) is correctly handled via column-level decode.
streaming_mixed_complex_columns(Config) ->
    Conn = ?config(connection, Config),
    Table = <<"ct_stream_mixed_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn,
        <<"CREATE TABLE ", Table/binary,
            " (id UInt32, tags Array(String), meta Map(String, String), "
            "score Nullable(Float64)) ENGINE = Memory">>
    ),
    ok = execute(
        Conn,
        <<"INSERT INTO ", Table/binary,
            " VALUES "
            "(1, ['a', 'b'], {'k1': 'v1'}, 9.5), "
            "(2, ['c'], {'k2': 'v2', 'k3': 'v3'}, NULL), "
            "(3, [], {}, 7.0)">>
    ),

    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := Name, value := Value}}, Acc) ->
            Existing = maps:get(Name, Acc, []),
            {ok, Acc#{Name => [Value | Existing]}};
        ('end', Acc) ->
            {ok, maps:map(fun(_K, V) -> lists:reverse(V) end, Acc)}
    end,

    SQL = <<"SELECT id, tags, meta, score FROM ", Table/binary, " ORDER BY id">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{}
    }),

    DataMap = maps:get(data, Result),
    4 = maps:size(DataMap),

    Ids = maps:get(<<"id">>, DataMap),
    [1, 2, 3] = Ids,

    Tags = maps:get(<<"tags">>, DataMap),
    [[<<"a">>, <<"b">>], [<<"c">>], []] = Tags,

    Metas = maps:get(<<"meta">>, DataMap),
    [#{<<"k1">> := <<"v1">>}, #{<<"k2">> := <<"v2">>, <<"k3">> := <<"v3">>}, EmptyMap] = Metas,
    0 = maps:size(EmptyMap),

    Scores = maps:get(<<"score">>, DataMap),
    3 = length(Scores),
    %% Verify actual values: 9.5, null, 7.0
    [9.5, null, 7.0] = Scores,

    ct:pal(
        "Streaming mixed columns: ids=~p tags=~p meta=~p scores=~p",
        [Ids, Tags, Metas, Scores]
    ),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Execute a query and return ok or error.
%% Catches connection crashes (exit signals) and returns error tuple.
-spec execute(pid(), binary()) -> ok | {error, term()}.
execute(Conn, SQL) ->
    try clickhouse_erl:query(Conn, SQL) of
        {ok, _} -> ok;
        {error, Reason} -> {error, Reason}
    catch
        exit:{Reason, _} -> {error, Reason}
    end.

%% @doc Generate unique suffix for table names
-spec unique_suffix() -> binary().
unique_suffix() ->
    integer_to_binary(erlang:unique_integer([positive])).
