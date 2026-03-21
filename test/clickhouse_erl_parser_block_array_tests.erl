%% @doc Unit tests for Array type support in decode_single_value.
%%
%% Tests verify that the block parser can decode Array(T) columns
%% in streaming mode. Array columns use column-level encoding:
%% UInt64 offsets (cumulative element counts) followed by flattened data.
%% The block parser pre-decodes array columns in col_data_header stage
%% and emits individual array values in col_values stage.
-module(clickhouse_erl_parser_block_array_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Create a minimal block with one column and given rows.
%% ColumnData should be the raw binary for the column (offsets + data for arrays).
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

%% @doc Create a two-column block for testing Array alongside scalar columns.
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
%%% Simple Array Tests
%%%===================================================================

parse_array_uint32_single_row_test() ->
    %% Array(UInt32): 1 row with [10, 20, 30]
    %% Offsets: [3] (3 elements in first row)
    %% Data: 10, 20, 30 as UInt32 little-endian
    Offsets = encode_offsets([3]),
    Values = <<10:32/little, 20:32/little, 30:32/little>>,
    ColumnData = <<Offsets/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Array(UInt32)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([[10, 20, 30]], ValueEvents).

parse_array_uint32_multiple_rows_test() ->
    %% Array(UInt32): 3 rows: [1, 2], [3], [4, 5, 6]
    %% Offsets: [2, 3, 6] (cumulative)
    %% Data: 1, 2, 3, 4, 5, 6 as UInt32
    Offsets = encode_offsets([2, 3, 6]),
    Values = <<1:32/little, 2:32/little, 3:32/little, 4:32/little, 5:32/little, 6:32/little>>,
    ColumnData = <<Offsets/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Array(UInt32)">>, ColumnData, 3),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([[1, 2], [3], [4, 5, 6]], ValueEvents).

parse_array_string_test() ->
    %% Array(String): 2 rows: ["hello", "world"], ["foo"]
    %% Offsets: [2, 3]
    %% Data: "hello", "world", "foo" as varint-prefixed strings
    Offsets = encode_offsets([2, 3]),
    Values = <<5, "hello", 5, "world", 3, "foo">>,
    ColumnData = <<Offsets/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Array(String)">>, ColumnData, 2),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([[<<"hello">>, <<"world">>], [<<"foo">>]], ValueEvents).

parse_array_int64_test() ->
    %% Array(Int64): 1 row with [-1, 0, 42]
    Offsets = encode_offsets([3]),
    Values = <<255, 255, 255, 255, 255, 255, 255, 255, 0:64/little, 42:64/little-signed>>,
    ColumnData = <<Offsets/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Array(Int64)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([[-1, 0, 42]], ValueEvents).

%%%===================================================================
%%% Empty Array Tests
%%%===================================================================

parse_array_empty_single_row_test() ->
    %% Array(UInt32): 1 row with [] (empty array)
    %% Offsets: [0]
    %% Data: (none)
    Offsets = encode_offsets([0]),
    ColumnData = Offsets,
    Data = create_test_block(<<"col">>, <<"Array(UInt32)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([[]], ValueEvents).

parse_array_mixed_empty_and_nonempty_test() ->
    %% Array(UInt32): 3 rows: [], [42], []
    %% Offsets: [0, 1, 1]
    %% Data: 42
    Offsets = encode_offsets([0, 1, 1]),
    Values = <<42:32/little>>,
    ColumnData = <<Offsets/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Array(UInt32)">>, ColumnData, 3),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([[], [42], []], ValueEvents).

%%%===================================================================
%%% Nested Array Tests
%%%===================================================================

parse_nested_array_test() ->
    %% Array(Array(UInt32)): 2 rows: [[1, 2], [3]], [[4]]
    %% Outer offsets: [2, 3] (2 inner arrays in row 1, 1 in row 2)
    %% Inner offsets: [2, 3, 4] (cumulative for inner arrays: [1,2] has 2, [3] has 1, [4] has 1)
    %% Data: 1, 2, 3, 4 as UInt32
    OuterOffsets = encode_offsets([2, 3]),
    InnerOffsets = encode_offsets([2, 3, 4]),
    Values = <<1:32/little, 2:32/little, 3:32/little, 4:32/little>>,
    ColumnData = <<OuterOffsets/binary, InnerOffsets/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Array(Array(UInt32))">>, ColumnData, 2),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([[[1, 2], [3]], [[4]]], ValueEvents).

parse_nested_array_with_empty_test() ->
    %% Array(Array(UInt32)): 2 rows: [[], [1]], [[]]
    %% Outer offsets: [2, 3]
    %% Inner offsets: [0, 1, 1] (first inner is empty, second has 1 elem, third is empty)
    %% Data: 1
    OuterOffsets = encode_offsets([2, 3]),
    InnerOffsets = encode_offsets([0, 1, 1]),
    Values = <<1:32/little>>,
    ColumnData = <<OuterOffsets/binary, InnerOffsets/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Array(Array(UInt32))">>, ColumnData, 2),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([[[], [1]], [[]]], ValueEvents).

%%%===================================================================
%%% Remainder / Multi-Column Tests
%%%===================================================================

parse_array_with_remainder_test() ->
    %% Array column followed by extra bytes (simulating next column or packet data)
    Offsets = encode_offsets([2]),
    Values = <<10:32/little, 20:32/little>>,
    ExtraData = <<"extra">>,
    ColumnData = <<Offsets/binary, Values/binary, ExtraData/binary>>,
    Data = create_test_block(<<"col">>, <<"Array(UInt32)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, Remainder} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([[10, 20]], ValueEvents),
    ?assertEqual(<<"extra">>, Remainder).

parse_array_then_scalar_column_test() ->
    %% Two columns: Array(UInt32) then UInt32
    %% Row 1: [1, 2], 100
    %% Row 2: [3], 200
    ArrayOffsets = encode_offsets([2, 3]),
    ArrayValues = <<1:32/little, 2:32/little, 3:32/little>>,
    ArrayData = <<ArrayOffsets/binary, ArrayValues/binary>>,
    ScalarData = <<100:32/little, 200:32/little>>,
    Data = create_two_column_block(
        <<"arr">>,
        <<"Array(UInt32)">>,
        ArrayData,
        <<"num">>,
        <<"UInt32">>,
        ScalarData,
        2
    ),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([[1, 2], [3], 100, 200], ValueEvents).

%%%===================================================================
%%% Truncated Data Tests
%%%===================================================================

parse_array_truncated_offsets_test() ->
    %% Only partial offsets (need 8 bytes for 1 offset, only have 4)
    ColumnData = <<1, 0, 0, 0>>,
    Data = create_test_block(<<"col">>, <<"Array(UInt32)">>, ColumnData, 1),
    State = init_parser(),
    Result = clickhouse_erl_parser_block:parse(Data, State),
    ?assertMatch({more, _, _, _}, Result).

parse_array_truncated_values_test() ->
    %% Complete offsets but truncated values
    %% Offsets say 2 elements, but only 1 UInt32 value present
    Offsets = encode_offsets([2]),
    Values = <<10:32/little>>,
    ColumnData = <<Offsets/binary, Values/binary>>,
    Data = create_test_block(<<"col">>, <<"Array(UInt32)">>, ColumnData, 1),
    State = init_parser(),
    Result = clickhouse_erl_parser_block:parse(Data, State),
    ?assertMatch({more, _, _, _}, Result).

%%%===================================================================
%%% Column Event Metadata Tests
%%%===================================================================

parse_array_emits_column_event_test() ->
    %% Verify that the column metadata event is emitted correctly for Array types
    Offsets = encode_offsets([1]),
    Values = <<42:32/little>>,
    ColumnData = <<Offsets/binary, Values/binary>>,
    Data = create_test_block(<<"mycol">>, <<"Array(UInt32)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ColumnEvents = [E || {data, column, E} <- Events],
    ?assertEqual([#{name => <<"mycol">>, type => <<"Array(UInt32)">>}], ColumnEvents).
