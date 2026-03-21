%% @doc Unit tests for Map type support in decode_single_value.
%%
%% Tests verify that the block parser can decode Map(K, V) columns
%% in streaming mode. Map columns use column-level encoding:
%% UInt64 offsets (cumulative pair counts) followed by flattened keys
%% column and flattened values column.
%% The block parser pre-decodes map columns in col_data_header stage
%% and emits individual map values in col_values stage.
-module(clickhouse_erl_parser_block_map_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Create a minimal block with one column and given rows.
%% ColumnData should be the raw binary for the column.
create_test_block(ColumnName, ColumnType, ColumnData, NumRows) ->
    TempTableName = <<0>>,
    BlockInfo = <<0>>,
    NumColumns = <<1>>,
    NumRowsEnc = <<NumRows>>,
    NameLen = byte_size(ColumnName),
    ColName = <<NameLen, ColumnName/binary>>,
    TypeLen = byte_size(ColumnType),
    ColType = <<TypeLen, ColumnType/binary>>,
    <<TempTableName/binary, BlockInfo/binary, NumColumns/binary, NumRowsEnc/binary, ColName/binary,
        ColType/binary, ColumnData/binary>>.

%% @doc Create a two-column block for testing Map alongside scalar columns.
create_two_column_block(
    Col1Name,
    Col1Type,
    Col1Data,
    Col2Name,
    Col2Type,
    Col2Data,
    NumRows
) ->
    TempTableName = <<0>>,
    BlockInfo = <<0>>,
    NumColumns = <<2>>,
    NumRowsEnc = <<NumRows>>,
    Name1Len = byte_size(Col1Name),
    ColName1 = <<Name1Len, Col1Name/binary>>,
    Type1Len = byte_size(Col1Type),
    ColType1 = <<Type1Len, Col1Type/binary>>,
    Name2Len = byte_size(Col2Name),
    ColName2 = <<Name2Len, Col2Name/binary>>,
    Type2Len = byte_size(Col2Type),
    ColType2 = <<Type2Len, Col2Type/binary>>,
    <<TempTableName/binary, BlockInfo/binary, NumColumns/binary, NumRowsEnc/binary, ColName1/binary,
        ColType1/binary, Col1Data/binary, ColName2/binary, ColType2/binary, Col2Data/binary>>.

init_parser() ->
    clickhouse_erl_parser_block:init(#{version => 54451}).

%% @doc Encode UInt64 offsets as little-endian binary.
encode_offsets(Offsets) ->
    iolist_to_binary([<<O:64/little-unsigned>> || O <- Offsets]).

%%%===================================================================
%%% Simple Map Tests
%%%===================================================================

parse_map_string_uint32_single_row_test() ->
    %% Map(String, UInt32): 1 row with {"a" => 10, "b" => 20}
    %% Offsets: [2] (2 pairs in first row)
    %% Keys: "a", "b" as varint-prefixed strings
    %% Values: 10, 20 as UInt32 little-endian
    Offsets = encode_offsets([2]),
    Keys = <<1, "a", 1, "b">>,
    Values = <<10:32/little, 20:32/little>>,
    ColumnData = <<Offsets/binary, Keys/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Map(String, UInt32)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual(1, length(ValueEvents)),
    [Map] = ValueEvents,
    ?assertEqual(#{<<"a">> => 10, <<"b">> => 20}, Map).

parse_map_string_uint32_multiple_rows_test() ->
    %% Map(String, UInt32): 2 rows: {"x" => 1}, {"y" => 2, "z" => 3}
    %% Offsets: [1, 3] (cumulative)
    %% Keys: "x", "y", "z"
    %% Values: 1, 2, 3
    Offsets = encode_offsets([1, 3]),
    Keys = <<1, "x", 1, "y", 1, "z">>,
    Values = <<1:32/little, 2:32/little, 3:32/little>>,
    ColumnData = <<Offsets/binary, Keys/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Map(String, UInt32)">>, ColumnData, 2),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual(2, length(ValueEvents)),
    ?assertEqual(#{<<"x">> => 1}, lists:nth(1, ValueEvents)),
    ?assertEqual(#{<<"y">> => 2, <<"z">> => 3}, lists:nth(2, ValueEvents)).

parse_map_string_int64_test() ->
    %% Map(String, Int64): 1 row with {"key" => -42}
    Offsets = encode_offsets([1]),
    Keys = <<3, "key">>,
    %% -42 as Int64 little-endian
    Values = <<214, 255, 255, 255, 255, 255, 255, 255>>,
    ColumnData = <<Offsets/binary, Keys/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Map(String, Int64)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([#{<<"key">> => -42}], ValueEvents).

parse_map_string_string_test() ->
    %% Map(String, String): 1 row with {"hello" => "world"}
    Offsets = encode_offsets([1]),
    Keys = <<5, "hello">>,
    Values = <<5, "world">>,
    ColumnData = <<Offsets/binary, Keys/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Map(String, String)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([#{<<"hello">> => <<"world">>}], ValueEvents).

%%%===================================================================
%%% Empty Map Tests
%%%===================================================================

parse_map_empty_single_row_test() ->
    %% Map(String, UInt32): 1 row with {} (empty map)
    %% Offsets: [0]
    %% Keys: (none)
    %% Values: (none)
    Offsets = encode_offsets([0]),
    ColumnData = Offsets,
    Data = create_test_block(<<"col">>, <<"Map(String, UInt32)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([#{}], ValueEvents).

parse_map_mixed_empty_and_nonempty_test() ->
    %% Map(String, UInt32): 3 rows: {}, {"a" => 42}, {}
    %% Offsets: [0, 1, 1]
    %% Keys: "a"
    %% Values: 42
    Offsets = encode_offsets([0, 1, 1]),
    Keys = <<1, "a">>,
    Values = <<42:32/little>>,
    ColumnData = <<Offsets/binary, Keys/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Map(String, UInt32)">>, ColumnData, 3),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([#{}, #{<<"a">> => 42}, #{}], ValueEvents).

%%%===================================================================
%%% Remainder / Multi-Column Tests
%%%===================================================================

parse_map_with_remainder_test() ->
    %% Map column followed by extra bytes
    Offsets = encode_offsets([1]),
    Keys = <<1, "k">>,
    Values = <<99:32/little>>,
    ExtraData = <<"extra">>,
    ColumnData = <<Offsets/binary, Keys/binary, Values/binary, ExtraData/binary>>,
    Data = create_test_block(<<"col">>, <<"Map(String, UInt32)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, Remainder} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([#{<<"k">> => 99}], ValueEvents),
    ?assertEqual(<<"extra">>, Remainder).

parse_map_then_scalar_column_test() ->
    %% Two columns: Map(String, UInt32) then UInt32
    %% Row 1: {"a" => 1}, 100
    %% Row 2: {"b" => 2, "c" => 3}, 200
    MapOffsets = encode_offsets([1, 3]),
    MapKeys = <<1, "a", 1, "b", 1, "c">>,
    MapValues = <<1:32/little, 2:32/little, 3:32/little>>,
    MapData = <<MapOffsets/binary, MapKeys/binary, MapValues/binary>>,
    ScalarData = <<100:32/little, 200:32/little>>,
    Data = create_two_column_block(
        <<"m">>,
        <<"Map(String, UInt32)">>,
        MapData,
        <<"num">>,
        <<"UInt32">>,
        ScalarData,
        2
    ),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([#{<<"a">> => 1}, #{<<"b">> => 2, <<"c">> => 3}, 100, 200], ValueEvents).

%%%===================================================================
%%% Truncated Data Tests
%%%===================================================================

parse_map_truncated_offsets_test() ->
    %% Only partial offsets (need 8 bytes for 1 offset, only have 4)
    ColumnData = <<1, 0, 0, 0>>,
    Data = create_test_block(<<"col">>, <<"Map(String, UInt32)">>, ColumnData, 1),
    State = init_parser(),
    Result = clickhouse_erl_parser_block:parse(Data, State),
    ?assertMatch({more, _, _, _}, Result).

parse_map_truncated_values_test() ->
    %% Complete offsets and keys but truncated values
    %% Offsets say 1 pair, key present, but value truncated
    Offsets = encode_offsets([1]),
    Keys = <<1, "a">>,
    Values = <<10, 0>>,
    ColumnData = <<Offsets/binary, Keys/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Map(String, UInt32)">>, ColumnData, 1),
    State = init_parser(),
    Result = clickhouse_erl_parser_block:parse(Data, State),
    ?assertMatch({more, _, _, _}, Result).

%%%===================================================================
%%% Column Event Metadata Tests
%%%===================================================================

parse_map_emits_column_event_test() ->
    %% Verify that the column metadata event is emitted correctly for Map types
    Offsets = encode_offsets([1]),
    Keys = <<1, "k">>,
    Values = <<1:32/little>>,
    ColumnData = <<Offsets/binary, Keys/binary, Values/binary>>,
    Data = create_test_block(<<"mycol">>, <<"Map(String, UInt32)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ColumnEvents = [E || {data, column, E} <- Events],
    ?assertEqual([#{name => <<"mycol">>, type => <<"Map(String, UInt32)">>}], ColumnEvents).
