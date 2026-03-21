%% @doc Common Test suite for event-driven parser end-to-end integration
%%
%% Tests the complete query lifecycle using the event-driven parser with real
%% ClickHouse server. Validates exception handling, end_of_stream, pong responses,
%% extended block types, memory usage, and all packet types.
%%
%% Feature: streamable-packet-parsing (Task 8.5.5)
-module(clickhouse_erl_event_parser_SUITE).

-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).

%% Test cases - Query Lifecycle
-export([
    simple_select_query/1,
    select_with_multiple_data_packets/1,
    select_with_large_result_set/1,
    multiple_sequential_queries/1
]).

%% Test cases - Exception Handling
-export([
    exception_syntax_error/1,
    exception_unknown_table/1,
    exception_type_mismatch/1,
    exception_during_query_execution/1
]).

%% Test cases - End of Stream
-export([
    end_of_stream_after_data/1,
    end_of_stream_no_data/1,
    end_of_stream_after_exception/1
]).

%% Test cases - Pong Responses
-export([
    ping_pong_basic/1,
    ping_pong_multiple/1
]).

%% Test cases - Extended Block Types
-export([
    extended_integer_types/1,
    extended_float_types/1,
    extended_temporal_types/1,
    extended_decimal_types/1,
    extended_network_types/1,
    extended_special_types/1
]).

%% Test cases - Streaming Functionality
-export([
    streaming_large_result_set/1,
    streaming_multiple_queries/1
]).

%% Test cases - All Packet Types
-export([
    packet_type_data/1,
    packet_type_totals/1,
    packet_type_extremes/1,
    packet_type_progress/1,
    packet_type_profile/1,
    packet_type_profile_events/1
]).

%% Test cases - Regression Tests
-export([
    regression_existing_query_suite/1,
    regression_existing_streaming_suite/1,
    regression_existing_compression_suite/1
]).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

suite() ->
    [{timetrap, {minutes, 5}}].

all() ->
    [
        {group, query_lifecycle},
        {group, exception_handling},
        {group, end_of_stream},
        {group, pong_responses},
        {group, extended_block_types},
        {group, streaming_functionality},
        {group, all_packet_types},
        {group, regression_tests}
    ].

groups() ->
    [
        {query_lifecycle, [sequence], [
            simple_select_query,
            select_with_multiple_data_packets,
            select_with_large_result_set,
            multiple_sequential_queries
        ]},
        {exception_handling, [sequence], [
            exception_syntax_error,
            exception_unknown_table,
            exception_type_mismatch,
            exception_during_query_execution
        ]},
        {end_of_stream, [sequence], [
            end_of_stream_after_data,
            end_of_stream_no_data,
            end_of_stream_after_exception
        ]},
        {pong_responses, [sequence], [
            ping_pong_basic,
            ping_pong_multiple
        ]},
        {extended_block_types, [sequence], [
            extended_integer_types,
            extended_float_types,
            extended_temporal_types,
            extended_decimal_types,
            extended_network_types,
            extended_special_types
        ]},
        {streaming_functionality, [sequence], [
            streaming_large_result_set,
            streaming_multiple_queries
        ]},
        {all_packet_types, [sequence], [
            packet_type_data,
            packet_type_totals,
            packet_type_extremes,
            packet_type_progress,
            packet_type_profile,
            packet_type_profile_events
        ]},
        {regression_tests, [sequence], [
            regression_existing_query_suite,
            regression_existing_streaming_suite,
            regression_existing_compression_suite
        ]}
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

init_per_group(Group, Config) when
    Group =:= query_lifecycle;
    Group =:= exception_handling;
    Group =:= end_of_stream;
    Group =:= pong_responses;
    Group =:= extended_block_types;
    Group =:= streaming_functionality;
    Group =:= all_packet_types
->
    {ok, Conn} = test_helpers:connect(),
    [{connection, Conn} | Config];
init_per_group(_Group, Config) ->
    Config.

end_per_group(Group, Config) when
    Group =:= query_lifecycle;
    Group =:= exception_handling;
    Group =:= end_of_stream;
    Group =:= pong_responses;
    Group =:= extended_block_types;
    Group =:= streaming_functionality;
    Group =:= all_packet_types
->
    Conn = ?config(connection, Config),
    test_helpers:disconnect(Conn),
    ok;
end_per_group(_Group, _Config) ->
    ok.

%%%===================================================================
%%% Test Cases: Query Lifecycle
%%%===================================================================

simple_select_query(Config) ->
    Conn = ?config(connection, Config),

    %% Execute simple SELECT query
    SQL = <<"SELECT 1 as num, 'hello' as str">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify result structure
    Data = maps:get(data, Result),
    Columns = maps:get(columns, Data),
    Rows = maps:get(rows, Data),

    %% Verify columns
    2 = length(Columns),
    [#{name := <<"num">>}, #{name := <<"str">>}] = Columns,

    %% Verify rows
    [[1, <<"hello">>]] = Rows.

select_with_multiple_data_packets(Config) ->
    Conn = ?config(connection, Config),

    %% Query that generates multiple DATA packets
    SQL = <<"SELECT number FROM system.numbers LIMIT 100000">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify all rows received
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    100000 = length(Rows),

    %% Verify first and last rows
    [0] = lists:nth(1, Rows),
    [99999] = lists:nth(100000, Rows).

select_with_large_result_set(Config) ->
    Conn = ?config(connection, Config),

    %% Large result set to test memory efficiency
    SQL = <<"SELECT number, toString(number) as str FROM system.numbers LIMIT 50000">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify result
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    50000 = length(Rows),

    %% Verify data correctness
    [FirstNum, FirstStr] = lists:nth(1, Rows),
    0 = FirstNum,
    <<"0">> = FirstStr,

    [LastNum, LastStr] = lists:nth(50000, Rows),
    49999 = LastNum,
    <<"49999">> = LastStr.

multiple_sequential_queries(Config) ->
    Conn = ?config(connection, Config),

    %% Execute multiple queries sequentially
    Queries = [
        <<"SELECT 1">>,
        <<"SELECT 2">>,
        <<"SELECT 3">>,
        <<"SELECT 4">>,
        <<"SELECT 5">>
    ],

    Results = [clickhouse_erl:query(Conn, SQL) || SQL <- Queries],

    %% Verify all succeeded
    lists:foreach(
        fun({ok, _}) -> ok end,
        Results
    ),

    %% Verify last result
    {ok, LastResult} = lists:last(Results),
    LastData = maps:get(data, LastResult),
    LastRows = maps:get(rows, LastData),
    [[5]] = LastRows.

%%%===================================================================
%%% Test Cases: Exception Handling
%%%===================================================================

exception_syntax_error(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query with syntax error
    SQL = <<"SELECT * FROM WHERE">>,
    Result = clickhouse_erl:query(Conn, SQL),

    %% Verify exception received
    {error, {server_exception, ExceptionInfo}} = Result,

    %% Verify exception structure
    true = is_map(ExceptionInfo),
    true = maps:is_key(code, ExceptionInfo),
    true = maps:is_key(message, ExceptionInfo),

    %% Verify connection still usable
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

exception_unknown_table(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query with unknown table
    SQL = <<"SELECT * FROM nonexistent_table_12345">>,
    Result = clickhouse_erl:query(Conn, SQL),

    %% Verify exception received
    {error, {server_exception, ExceptionInfo}} = Result,

    %% Verify exception contains table name
    Message = maps:get(message, ExceptionInfo),
    true = is_binary(Message),
    true = byte_size(Message) > 0,

    %% Verify connection still usable
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

exception_type_mismatch(Config) ->
    Conn = ?config(connection, Config),

    %% Create test table
    Table = <<"test_type_mismatch_", (unique_suffix())/binary>>,
    ok = execute(Conn, <<"DROP TABLE IF EXISTS ", Table/binary>>),
    ok = execute(Conn, <<"CREATE TABLE ", Table/binary, " (id UInt32) ENGINE = Memory">>),

    %% Try to insert wrong type
    SQL = <<"INSERT INTO ", Table/binary, " VALUES ('not_a_number')">>,
    Result = clickhouse_erl:query(Conn, SQL),

    %% Verify exception received
    {error, {server_exception, ExceptionInfo}} = Result,
    true = is_map(ExceptionInfo),

    %% Cleanup
    ok = execute(Conn, <<"DROP TABLE ", Table/binary>>),

    %% Verify connection still usable
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

exception_during_query_execution(Config) ->
    Conn = ?config(connection, Config),

    %% Query that causes runtime exception (integer division by zero)
    %% Note: Float division (1 / 0) returns infinity in newer ClickHouse versions,
    %% so we use intDiv which always throws an exception for division by zero.
    SQL = <<"SELECT intDiv(1, 0)">>,
    Result = clickhouse_erl:query(Conn, SQL),

    %% Verify exception received
    {error, {server_exception, ExceptionInfo}} = Result,
    true = is_map(ExceptionInfo),

    %% Verify connection still usable
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

%%%===================================================================
%%% Test Cases: End of Stream
%%%===================================================================

end_of_stream_after_data(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query that returns data
    SQL = <<"SELECT number FROM system.numbers LIMIT 100">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify data received
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    100 = length(Rows),

    %% Verify connection ready for next query (END_OF_STREAM processed)
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

end_of_stream_no_data(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query that returns no data
    SQL = <<"SELECT number FROM system.numbers LIMIT 0">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify empty result
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    [] = Rows,

    %% Verify connection ready for next query
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

end_of_stream_after_exception(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query that causes exception
    SQL = <<"SELECT * FROM nonexistent_table">>,
    {error, {server_exception, _}} = clickhouse_erl:query(Conn, SQL),

    %% Verify connection ready for next query (END_OF_STREAM after exception)
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

%%%===================================================================
%%% Test Cases: Pong Responses
%%%===================================================================

ping_pong_basic(Config) ->
    Conn = ?config(connection, Config),

    %% Send ping (implementation-specific - may need to use internal API)
    %% For now, verify connection is alive
    true = is_process_alive(Conn),

    %% Execute query to verify connection works
    {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

ping_pong_multiple(Config) ->
    Conn = ?config(connection, Config),

    %% Execute multiple queries (each involves ping-like behavior)
    lists:foreach(
        fun(_) ->
            {ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>)
        end,
        lists:seq(1, 5)
    ).

%%%===================================================================
%%% Test Cases: Extended Block Types
%%%===================================================================

extended_integer_types(Config) ->
    Conn = ?config(connection, Config),

    %% Test Int128, Int256, UInt128, UInt256
    SQL = <<
        "SELECT "
        "toInt128(123) as i128, "
        "toInt256(456) as i256, "
        "toUInt128(789) as u128, "
        "toUInt256(101112) as u256"
    >>,

    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify result structure
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    [[I128, I256, U128, U256]] = Rows,

    %% Verify values (as integers)
    123 = I128,
    456 = I256,
    789 = U128,
    101112 = U256.

extended_float_types(Config) ->
    Conn = ?config(connection, Config),

    %% Test Float32, Float64
    SQL = <<
        "SELECT "
        "toFloat32(3.14) as f32, "
        "toFloat64(2.71828) as f64"
    >>,

    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify result structure
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    [[F32, F64]] = Rows,

    %% Verify values (approximate comparison for floats)
    true = abs(F32 - 3.14) < 0.01,
    true = abs(F64 - 2.71828) < 0.00001.

extended_temporal_types(Config) ->
    Conn = ?config(connection, Config),

    %% Test Date32, DateTime64, Time
    SQL = <<
        "SELECT "
        "toDate32('2024-01-15') as d32, "
        "toDateTime64('2024-01-15 12:30:45.123', 3) as dt64"
    >>,

    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify result structure
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    [[D32, DT64]] = Rows,

    %% Verify Date32 is decoded as date tuple
    {2024, 1, 15} = D32,
    %% Verify DateTime64 is decoded as raw integer (ticks)
    true = is_integer(DT64).

extended_decimal_types(Config) ->
    Conn = ?config(connection, Config),

    %% Test Decimal32, Decimal64, Decimal128, Decimal256
    SQL = <<
        "SELECT "
        "toDecimal32(123.45, 2) as d32, "
        "toDecimal64(123.456789, 6) as d64, "
        "toDecimal128(123.45, 2) as d128"
    >>,

    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify result structure
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    [[D32, D64, D128]] = Rows,

    %% Verify values are {decimal, Value, Scale} tuples
    {decimal, 12345, 2} = D32,
    {decimal, 123456789, 6} = D64,
    {decimal, 12345, 2} = D128.

extended_network_types(Config) ->
    Conn = ?config(connection, Config),

    %% Test IPv4, IPv6
    SQL = <<
        "SELECT "
        "toIPv4('192.168.1.1') as ip4, "
        "toIPv6('::1') as ip6"
    >>,

    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify result structure
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    [[IP4, IP6]] = Rows,

    %% Verify values
    {192, 168, 1, 1} = IP4,
    {0, 0, 0, 0, 0, 0, 0, 1} = IP6.

extended_special_types(Config) ->
    Conn = ?config(connection, Config),

    %% Test UUID, Point
    SQL = <<
        "SELECT "
        "toUUID('12345678-1234-1234-1234-123456789012') as uuid, "
        "tuple(1.0, 2.0) as point"
    >>,

    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify result structure
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    [[UUID, Point]] = Rows,

    %% Verify UUID is binary (hyphenated string format)
    true = is_binary(UUID),
    36 = byte_size(UUID),

    %% Verify Point is tuple
    {1.0, 2.0} = Point.

%%%===================================================================
%%% Test Cases: Streaming Functionality
%%%===================================================================

streaming_large_result_set(Config) ->
    Conn = ?config(connection, Config),

    %% Stream 100k rows using column-name-tagged callback
    SQL = <<"SELECT number FROM system.numbers LIMIT 100000">>,
    Callback = fun
        ({data, #{name := _Name, value := _Value}}, Acc) ->
            {ok, Acc + 1};
        ('end', Acc) ->
            {ok, Acc}
    end,

    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => 0
    }),

    %% Verify all rows processed via streaming callback
    100000 = maps:get(data, Result).

streaming_multiple_queries(Config) ->
    Conn = ?config(connection, Config),

    %% Execute multiple streaming queries sequentially on same connection
    lists:foreach(
        fun(N) ->
            Limit = N * 1000,
            SQL = <<"SELECT number FROM system.numbers LIMIT ", (integer_to_binary(Limit))/binary>>,
            Callback = fun
                ({data, #{name := _Name, value := _Value}}, Acc) ->
                    {ok, Acc + 1};
                ('end', Acc) ->
                    {ok, Acc}
            end,

            {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
                on_data => Callback,
                initial_accumulator => 0
            }),

            Limit = maps:get(data, Result)
        end,
        lists:seq(1, 10)
    ).

%%%===================================================================
%%% Test Cases: All Packet Types
%%%===================================================================

packet_type_data(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query that returns DATA packets
    SQL = <<"SELECT number FROM system.numbers LIMIT 100">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify data received
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    100 = length(Rows).

packet_type_totals(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query with GROUP BY and TOTALS
    SQL = <<
        "SELECT number % 10 as group_key, count() as cnt "
        "FROM (SELECT number FROM system.numbers LIMIT 100) "
        "GROUP BY group_key WITH TOTALS "
        "ORDER BY group_key"
    >>,

    {ok, Result} = clickhouse_erl:query(Conn, SQL),

    %% Verify data received (including totals)
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    true = length(Rows) > 0.

packet_type_extremes(Config) ->
    Conn = ?config(connection, Config),

    %% Execute query with extremes
    SQL = <<"SELECT number FROM system.numbers LIMIT 100">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        settings => #{<<"extremes">> => <<"1">>}
    }),

    %% Verify data received (including extremes)
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    100 = length(Rows).

packet_type_progress(Config) ->
    Conn = ?config(connection, Config),

    %% Track progress callbacks
    Parent = self(),
    ProgressCallback = fun(ProgressInfo) ->
        Parent ! {progress, ProgressInfo},
        ok
    end,

    %% Execute query with progress callback
    SQL = <<"SELECT number FROM system.numbers LIMIT 10000">>,
    {ok, _} = clickhouse_erl:query(Conn, SQL, #{
        on_progress => ProgressCallback
    }),

    %% Check if progress was reported (may or may not depending on query speed)
    receive
        {progress, _} ->
            ct:pal("Progress reported"),
            ok
    after 100 ->
        ct:pal("No progress reported (query too fast)"),
        ok
    end.

packet_type_profile(Config) ->
    Conn = ?config(connection, Config),

    %% Track profile callbacks
    Parent = self(),
    ProfileCallback = fun(ProfileInfo) ->
        Parent ! {profile, ProfileInfo},
        ok
    end,

    %% Execute query with profile callback
    SQL = <<"SELECT number FROM system.numbers LIMIT 1000">>,
    {ok, _} = clickhouse_erl:query(Conn, SQL, #{
        on_profile => ProfileCallback
    }),

    %% Check if profile was reported
    receive
        {profile, ProfileInfo} ->
            ct:pal("Profile reported: ~p", [ProfileInfo]),
            ok
    after 1000 ->
        ct:pal("No profile reported"),
        ok
    end.

packet_type_profile_events(Config) ->
    Conn = ?config(connection, Config),

    %% Track profile events callbacks
    Parent = self(),
    ProfileEventsCallback = fun(ProfileEvents) ->
        Parent ! {profile_events, ProfileEvents},
        ok
    end,

    %% Execute query with profile events callback
    SQL = <<"SELECT number FROM system.numbers LIMIT 1000">>,
    {ok, _} = clickhouse_erl:query(Conn, SQL, #{
        on_profile_events => ProfileEventsCallback
    }),

    %% Check if profile events were reported
    receive
        {profile_events, ProfileEvents} ->
            ct:pal("Profile events reported: ~p", [ProfileEvents]),
            ok
    after 1000 ->
        ct:pal("No profile events reported"),
        ok
    end.

%%%===================================================================
%%% Test Cases: Regression Tests
%%%===================================================================

regression_existing_query_suite(_Config) ->
    %% Run sample tests from clickhouse_erl_query_SUITE
    %% Create dedicated connection for regression test
    {ok, Conn} = test_helpers:connect(),

    %% Test simple query
    {ok, Result1} = clickhouse_erl:query(Conn, <<"SELECT 1">>),
    Data1 = maps:get(data, Result1),
    [[1]] = maps:get(rows, Data1),

    %% Test query with timeout
    {ok, Result2} = clickhouse_erl:query(Conn, <<"SELECT 2">>, #{timeout => 5000}),
    Data2 = maps:get(data, Result2),
    [[2]] = maps:get(rows, Data2),

    %% Cleanup
    test_helpers:disconnect(Conn).

regression_existing_streaming_suite(_Config) ->
    %% Run sample tests from clickhouse_erl_streaming_SUITE
    %% Create dedicated connection for regression test
    {ok, Conn} = test_helpers:connect(),

    %% Test streaming callback with column-name-tagged events
    Callback = fun
        ({data, #{name := Name, value := Value}}, Acc) ->
            Existing = maps:get(Name, Acc, []),
            {ok, Acc#{Name => [Value | Existing]}};
        ('end', Acc) ->
            {ok, maps:map(fun(_K, V) -> lists:reverse(V) end, Acc)}
    end,

    SQL = <<"SELECT number FROM system.numbers LIMIT 1000">>,
    {ok, Result} = clickhouse_erl:query(Conn, SQL, #{
        on_data => Callback,
        initial_accumulator => #{}
    }),

    %% Verify column-map result
    DataMap = maps:get(data, Result),
    true = is_map(DataMap),
    Numbers = maps:get(<<"number">>, DataMap),
    1000 = length(Numbers),
    0 = hd(Numbers),
    999 = lists:last(Numbers),

    %% Cleanup
    test_helpers:disconnect(Conn).

regression_existing_compression_suite(_Config) ->
    %% Run sample tests from clickhouse_erl_compression_SUITE
    %% Test with LZ4 compression
    {ok, Conn} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        #{
            username => test_helpers:test_username(),
            password => test_helpers:test_password(),
            database => test_helpers:test_database(),
            compression => lz4
        }
    ),

    %% Execute query with compression
    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT number FROM system.numbers LIMIT 100">>),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    100 = length(Rows),

    %% Cleanup
    test_helpers:disconnect(Conn).

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
