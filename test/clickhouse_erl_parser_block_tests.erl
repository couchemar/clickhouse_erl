%% @doc Integration tests for clickhouse_erl_parser_block extended type support.
%%
%% Tests verify that the block parser can decode blocks containing all 30+ ClickHouse types
%% from the clickhouse_erl_types_* modules through the parse/2 interface.
-module(clickhouse_erl_parser_block_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Create a minimal block with one column and one row
create_test_block(ColumnName, ColumnType, ColumnData) ->
    TempTableName = <<0>>,
    %% BlockInfo: field 0 (end marker)
    BlockInfo = <<0>>,
    %% NumColumns: 1
    NumColumns = <<1>>,
    %% NumRows: 1
    NumRows = <<1>>,
    %% Column name
    NameLen = byte_size(ColumnName),
    ColName = <<NameLen, ColumnName/binary>>,
    %% Column type
    TypeLen = byte_size(ColumnType),
    ColType = <<TypeLen, ColumnType/binary>>,
    %% Column data (no custom serialization flag for simplicity)
    <<TempTableName/binary, BlockInfo/binary, NumColumns/binary, NumRows/binary, ColName/binary,
        ColType/binary, ColumnData/binary>>.

%% @doc Initialize parser state
init_parser() ->
    clickhouse_erl_parser_block:init(#{version => 54451}).

%%%===================================================================
%%% Primitive Types Tests
%%%===================================================================

parse_string_column_test() ->
    Data = create_test_block(<<"col">>, <<"String">>, <<5, "hello">>),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    %% Verify we got column metadata and value events
    ?assert(length(Events) > 0),
    %% Find the column_value event
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual(<<"hello">>, Value).

parse_uint32_column_test() ->
    Data = create_test_block(<<"col">>, <<"UInt32">>, <<42, 0, 0, 0>>),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual(42, Value).

parse_int64_column_test() ->
    Data = create_test_block(<<"col">>, <<"Int64">>, <<255, 255, 255, 255, 255, 255, 255, 255>>),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual(-1, Value).

parse_bool_column_test() ->
    Data = create_test_block(<<"col">>, <<"Bool">>, <<1>>),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual(true, Value).

%%%===================================================================
%%% Float Types Tests
%%%===================================================================

parse_float32_column_test() ->
    Data = create_test_block(<<"col">>, <<"Float32">>, <<0, 0, 128, 63>>),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual(1.0, Value).

parse_float64_column_test() ->
    Data = create_test_block(<<"col">>, <<"Float64">>, <<0, 0, 0, 0, 0, 0, 240, 63>>),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual(1.0, Value).

%%%===================================================================
%%% Extended Integer Types Tests
%%%===================================================================

parse_int128_column_test() ->
    Data = create_test_block(
        <<"col">>, <<"Int128">>, <<42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
    ),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual(42, Value).

parse_uint256_column_test() ->
    Data = create_test_block(
        <<"col">>,
        <<"UInt256">>,
        <<42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0>>
    ),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual(42, Value).

%%%===================================================================
%%% Decimal Types Tests
%%%===================================================================

parse_decimal32_column_test() ->
    %% 123.45 with scale 2 = 12345 as Int32
    Data = create_test_block(<<"col">>, <<"Decimal32(9, 2)">>, <<57, 48, 0, 0>>),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual({decimal, 12345, 2}, Value).

parse_decimal64_column_test() ->
    Data = create_test_block(<<"col">>, <<"Decimal64(18, 2)">>, <<57, 48, 0, 0, 0, 0, 0, 0>>),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual({decimal, 12345, 2}, Value).

%%%===================================================================
%%% Temporal Types Tests
%%%===================================================================

parse_date_column_test() ->
    %% 2020-01-01 = 18262 days since 1970-01-01
    Data = create_test_block(<<"col">>, <<"Date">>, <<86, 71>>),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual({2020, 1, 1}, Value).

parse_datetime_column_test() ->
    %% 2020-01-01 00:00:00 UTC = 1577836800 seconds since 1970-01-01
    %% In little-endian: <<0, 28, 17, 94>>
    Seconds = 1577836800,
    Data = create_test_block(<<"col">>, <<"DateTime">>, <<Seconds:32/little-unsigned>>),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual({{2020, 1, 1}, {0, 0, 0}}, Value).

parse_datetime64_column_test() ->
    %% DateTime64(3) - milliseconds precision
    Data = create_test_block(
        <<"col">>, <<"DateTime64(3)">>, <<0, 112, 68, 117, 109, 1, 0, 0>>
    ),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assert(is_integer(Value)).

%%%===================================================================
%%% Time Types Tests
%%%===================================================================

parse_time_column_test() ->
    %% 14:30:45 = 52245 seconds since midnight
    Seconds = 14 * 3600 + 30 * 60 + 45,
    Data = create_test_block(<<"col">>, <<"Time">>, <<Seconds:32/little-signed>>),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual({14, 30, 45}, Value).

%%%===================================================================
%%% Network Types Tests
%%%===================================================================

parse_ipv4_column_test() ->
    %% 192.168.1.1 in little-endian: <<1,1,168,192>>
    Data = create_test_block(<<"col">>, <<"IPv4">>, <<1, 1, 168, 192>>),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertEqual({192, 168, 1, 1}, Value).

parse_ipv6_column_test() ->
    %% IPv6 address (16 bytes)
    Data = create_test_block(
        <<"col">>, <<"IPv6">>, <<32, 1, 13, 184, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1>>
    ),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertMatch({_, _, _, _, _, _, _, _}, Value).

%%%===================================================================
%%% UUID Test
%%%===================================================================

parse_uuid_column_test() ->
    %% UUID (16 bytes)
    Data = create_test_block(
        <<"col">>, <<"UUID">>, <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
    ),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assert(is_binary(Value)).

%%%===================================================================
%%% Special Types Tests
%%%===================================================================

parse_nothing_column_test() ->
    %% Nothing type has no data - parser will return {more, ...} waiting for data
    %% This is expected behavior since the parser doesn't know the column is complete
    %% In real usage, this would be followed by the next column or end of block
    Data = create_test_block(<<"col">>, <<"Nothing">>, <<>>),
    State = init_parser(),
    Result = clickhouse_erl_parser_block:parse(Data, State),
    %% Parser returns {more, ...} because it's waiting for column data
    %% This is correct - Nothing columns have no data but parser doesn't know that
    ?assertMatch({more, _, _, _}, Result).

parse_point_column_test() ->
    %% Point: two Float64 values (X=1.0, Y=2.0)
    Data = create_test_block(
        <<"col">>, <<"Point">>, <<0, 0, 0, 0, 0, 0, 240, 63, 0, 0, 0, 0, 0, 0, 0, 64>>
    ),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assertMatch({_, _}, Value).

parse_json_column_test() ->
    %% JSON requires uint64 serialization version (1 = string) before column data
    SerializationVersion = <<1:64/little-unsigned-integer>>,
    JsonPayload = <<13, "{\"key\":\"val\"}">>,
    ColumnData = <<SerializationVersion/binary, JsonPayload/binary>>,
    Data = create_test_block(<<"col">>, <<"JSON">>, ColumnData),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [E || {data, column_value, _} = E <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [{data, column_value, Value}] = ValueEvents,
    ?assert(is_binary(Value)).

%%%===================================================================
%%% Error Cases Tests
%%%===================================================================

parse_unsupported_type_test() ->
    Data = create_test_block(<<"col">>, <<"UnsupportedType">>, <<>>),
    State = init_parser(),
    Result = clickhouse_erl_parser_block:parse(Data, State),
    ?assertMatch(
        {error, {col_values, _, <<"UnsupportedType">>, {unsupported_streaming_type, _}}}, Result
    ).
