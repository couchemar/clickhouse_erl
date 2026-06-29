%% @doc Common Test suite for column-map accumulation pattern
%%
%% Tests the streaming callback column-map accumulation pattern against a real
%% ClickHouse server. Validates column-name-tagged events, 'end' finalization,
%% multi-block merging, and empty result sets.
%%
%% Feature: streamable-packet-parsing (Task 8.5.6.9)
-module(clickhouse_erl_column_map_accumulation_SUITE).

-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).

%% Test cases - Column Map Accumulation
-export([
    accumulate_two_columns_into_map/1,
    accumulate_single_column/1,
    accumulate_three_columns/1
]).

%% Test cases - End Event Finalization
-export([
    end_event_triggers_reverse/1,
    end_event_custom_finalization/1
]).

%% Test cases - Multi-Block Merge
-export([
    multi_block_merge_via_callback/1
]).

%% Test cases - Empty Result Set
-export([
    empty_result_only_end_event/1,
    empty_result_preserves_initial_accumulator/1
]).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

suite() ->
    [{timetrap, {minutes, 2}}].

all() ->
    [
        {group, column_map_accumulation},
        {group, end_event_finalization},
        {group, multi_block_merge},
        {group, empty_result_set}
    ].

groups() ->
    [
        {column_map_accumulation, [sequence], [
            accumulate_two_columns_into_map,
            accumulate_single_column,
            accumulate_three_columns
        ]},
        {end_event_finalization, [sequence], [
            end_event_triggers_reverse,
            end_event_custom_finalization
        ]},
        {multi_block_merge, [sequence], [
            multi_block_merge_via_callback
        ]},
        {empty_result_set, [sequence], [
            empty_result_only_end_event,
            empty_result_preserves_initial_accumulator
        ]}
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

init_per_group(_Group, Config) ->
    case test_helpers:connect() of
        {ok, Conn} ->
            [{connection, Conn} | Config];
        {error, Reason} ->
            {skip, {connection_failed, Reason}}
    end.

end_per_group(_Group, Config) ->
    Conn = ?config(connection, Config),
    test_helpers:disconnect(Conn),
    ok.

%%%===================================================================
%%% Test Cases: Column Map Accumulation
%%%===================================================================

%% @doc Accumulate SELECT name, salary into #{name => [...], salary => [...]}
accumulate_two_columns_into_map(Config) ->
    Conn = ?config(connection, Config),

    Table = <<"col_map_two_col_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (name String, salary UInt32) ENGINE = Memory">>
    ),
    ok = execute(
        Conn,
        <<"INSERT INTO ", Table/binary,
            " VALUES ('Alice', 50000), ('Bob', 60000), ('Charlie', 70000)">>
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

    SQL = <<"SELECT name, salary FROM ", Table/binary, " ORDER BY name">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{}
    }),

    DataMap = maps:get(data, Result),
    true = is_map(DataMap),

    %% Verify name column
    Names = maps:get(<<"name">>, DataMap),
    [<<"Alice">>, <<"Bob">>, <<"Charlie">>] = Names,

    %% Verify salary column
    Salaries = maps:get(<<"salary">>, DataMap),
    [50000, 60000, 70000] = Salaries,

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%% @doc Accumulate single column into map
accumulate_single_column(Config) ->
    Conn = ?config(connection, Config),

    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := Name, value := Value}}, Acc) ->
            Existing = maps:get(Name, Acc, []),
            {ok, Acc#{Name => [Value | Existing]}};
        ('end', Acc) ->
            {ok, maps:map(fun(_K, V) -> lists:reverse(V) end, Acc)}
    end,

    SQL = <<"SELECT number FROM system.numbers LIMIT 5">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{}
    }),

    DataMap = maps:get(data, Result),
    Numbers = maps:get(<<"number">>, DataMap),
    [0, 1, 2, 3, 4] = Numbers.

%% @doc Accumulate three columns into map
accumulate_three_columns(Config) ->
    Conn = ?config(connection, Config),

    Table = <<"col_map_three_col_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn,
        <<"CREATE TABLE ", Table/binary, " (id UInt32, name String, active UInt8) ENGINE = Memory">>
    ),
    ok = execute(
        Conn,
        <<"INSERT INTO ", Table/binary,
            " VALUES (1, 'Alice', 1), (2, 'Bob', 0), (3, 'Charlie', 1)">>
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

    SQL = <<"SELECT id, name, active FROM ", Table/binary, " ORDER BY id">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{}
    }),

    DataMap = maps:get(data, Result),
    3 = maps:size(DataMap),
    [1, 2, 3] = maps:get(<<"id">>, DataMap),
    [<<"Alice">>, <<"Bob">>, <<"Charlie">>] = maps:get(<<"name">>, DataMap),
    [1, 0, 1] = maps:get(<<"active">>, DataMap),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: End Event Finalization
%%%===================================================================

%% @doc Verify 'end' event triggers lists:reverse on accumulated lists
end_event_triggers_reverse(Config) ->
    Conn = ?config(connection, Config),

    %% Accumulate in reverse (prepend), then reverse on 'end'
    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := Name, value := Value}}, Acc) ->
            Existing = maps:get(Name, Acc, []),
            {ok, Acc#{Name => [Value | Existing]}};
        ('end', Acc) ->
            {ok, maps:map(fun(_K, V) -> lists:reverse(V) end, Acc)}
    end,

    SQL = <<"SELECT number FROM system.numbers LIMIT 10">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{}
    }),

    DataMap = maps:get(data, Result),
    Numbers = maps:get(<<"number">>, DataMap),

    %% Verify order is correct (0..9) — proves 'end' reversed the list
    Expected = lists:seq(0, 9),
    Expected = Numbers.

%% @doc Verify 'end' event allows custom finalization (e.g., compute summary)
end_event_custom_finalization(Config) ->
    Conn = ?config(connection, Config),

    %% Count values during streaming, compute summary on 'end'
    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := _Name, value := Value}}, #{count := C, sum := S}) ->
            {ok, #{count => C + 1, sum => S + Value}};
        ('end', #{count := C, sum := S}) ->
            {ok, #{count => C, sum => S, avg => S / C}}
    end,

    SQL = <<"SELECT number FROM system.numbers LIMIT 100">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{count => 0, sum => 0}
    }),

    Summary = maps:get(data, Result),
    100 = maps:get(count, Summary),
    4950 = maps:get(sum, Summary),
    49.5 = maps:get(avg, Summary).

%%%===================================================================
%%% Test Cases: Multi-Block Merge
%%%===================================================================

%% @doc Verify multi-block results merge correctly via callback
%% Uses enough rows to force multiple DATA blocks from ClickHouse
multi_block_merge_via_callback(Config) ->
    Conn = ?config(connection, Config),

    Table = <<"col_map_multi_block_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(
        Conn, <<"CREATE TABLE ", Table/binary, " (id UInt32, value String) ENGINE = Memory">>
    ),
    ok = execute(
        Conn,
        <<"INSERT INTO ", Table/binary,
            " SELECT number, toString(number) FROM system.numbers LIMIT 100000">>
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

    SQL = <<"SELECT id, value FROM ", Table/binary, " ORDER BY id">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{}
    }),

    DataMap = maps:get(data, Result),
    true = is_map(DataMap),

    Ids = maps:get(<<"id">>, DataMap),
    Values = maps:get(<<"value">>, DataMap),

    %% Verify all 100k rows received
    100000 = length(Ids),
    100000 = length(Values),

    %% Verify first and last values
    0 = hd(Ids),
    99999 = lists:last(Ids),
    <<"0">> = hd(Values),
    <<"99999">> = lists:last(Values),

    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>).

%%%===================================================================
%%% Test Cases: Empty Result Set
%%%===================================================================

%% @doc Verify empty result set: callback receives only 'end' event
empty_result_only_end_event(Config) ->
    Conn = ?config(connection, Config),

    %% Track whether data events were received
    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := _Name, value := _Value}}, #{data_count := C} = Acc) ->
            {ok, Acc#{data_count => C + 1}};
        ('end', Acc) ->
            {ok, Acc#{finalized => true}}
    end,

    SQL = <<"SELECT number FROM system.numbers LIMIT 0">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{data_count => 0, finalized => false}
    }),

    FinalAcc = maps:get(data, Result),
    0 = maps:get(data_count, FinalAcc),
    true = maps:get(finalized, FinalAcc).

%% @doc Verify empty result preserves initial accumulator structure
empty_result_preserves_initial_accumulator(Config) ->
    Conn = ?config(connection, Config),

    Callback = fun
        (block_end, Acc) ->
            {ok, Acc};
        ({data, #{name := Name, value := Value}}, Acc) ->
            Existing = maps:get(Name, Acc, []),
            {ok, Acc#{Name => [Value | Existing]}};
        ('end', Acc) ->
            {ok, Acc}
    end,

    SQL = <<"SELECT number FROM system.numbers LIMIT 0">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{}
    }),

    %% Empty map returned — no columns added, no data events
    DataMap = maps:get(data, Result),
    true = is_map(DataMap),
    0 = maps:size(DataMap).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Execute a query and return ok or error
-spec execute(pid(), binary()) -> ok | {error, term()}.
execute(Conn, SQL) ->
    case clickhouse_erl:query(Conn, SQL) of
        {ok, _} -> ok;
        {error, Reason} -> {error, Reason}
    end.

%% @doc Generate unique suffix for table names
-spec unique_suffix() -> binary().
unique_suffix() ->
    integer_to_binary(erlang:unique_integer([positive])).
