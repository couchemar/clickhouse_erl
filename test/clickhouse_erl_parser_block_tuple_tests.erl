%% @doc Unit tests for Tuple type support in decode_single_value.
%%
%% Tests verify that the block parser can decode Tuple(T1, T2, ...) columns
%% in streaming mode. Tuple columns use column-level encoding:
%% sequential element columns (N values of T1, then N values of T2, etc.).
%% The block parser pre-decodes tuple columns in col_data_header stage
%% and emits individual tuple values in col_values stage.
-module(clickhouse_erl_parser_block_tuple_tests).

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

%% @doc Create a two-column block for testing Tuple alongside scalar columns.
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

%%%===================================================================
%%% Simple Tuple Tests
%%%===================================================================

parse_tuple_uint32_int64_single_row_test() ->
    %% Tuple(UInt32, Int64): 1 row with {10, -5}
    %% Encoding: 1 UInt32 value (10), then 1 Int64 value (-5)
    Col1 = <<10:32/little-unsigned>>,
    Col2 = <<-5:64/little-signed>>,
    ColumnData = <<Col1/binary, Col2/binary>>,
    Data = create_test_block(<<"col">>, <<"Tuple(UInt32, Int64)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([{10, -5}], ValueEvents).

parse_tuple_string_uint32_multiple_rows_test() ->
    %% Tuple(String, UInt32): 3 rows: {"alice", 1}, {"bob", 2}, {"charlie", 3}
    %% Encoding: 3 String values, then 3 UInt32 values
    Strings = <<5, "alice", 3, "bob", 7, "charlie">>,
    Ints = <<1:32/little, 2:32/little, 3:32/little>>,
    ColumnData = <<Strings/binary, Ints/binary>>,
    Data = create_test_block(<<"col">>, <<"Tuple(String, UInt32)">>, ColumnData, 3),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([{<<"alice">>, 1}, {<<"bob">>, 2}, {<<"charlie">>, 3}], ValueEvents).

parse_tuple_three_elements_test() ->
    %% Tuple(UInt8, UInt16, UInt32): 2 rows: {1, 100, 1000}, {2, 200, 2000}
    %% Encoding: 2 UInt8, then 2 UInt16, then 2 UInt32
    Col1 = <<1:8, 2:8>>,
    Col2 = <<100:16/little, 200:16/little>>,
    Col3 = <<1000:32/little, 2000:32/little>>,
    ColumnData = <<Col1/binary, Col2/binary, Col3/binary>>,
    Data = create_test_block(<<"col">>, <<"Tuple(UInt8, UInt16, UInt32)">>, ColumnData, 2),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([{1, 100, 1000}, {2, 200, 2000}], ValueEvents).

%%%===================================================================
%%% Edge Case Tests
%%%===================================================================

parse_tuple_single_element_test() ->
    %% Tuple(Int32): 1 row with {42} (single-element tuple)
    ColumnData = <<42:32/little-signed>>,
    Data = create_test_block(<<"col">>, <<"Tuple(Int32)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([{42}], ValueEvents).

parse_tuple_float_types_test() ->
    %% Tuple(Float32, Float64): 1 row with {1.5, 2.5}
    ColumnData = <<1.5:32/little-float, 2.5:64/little-float>>,
    Data = create_test_block(<<"col">>, <<"Tuple(Float32, Float64)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    [{F32, F64}] = ValueEvents,
    ?assert(abs(F32 - 1.5) < 0.001),
    ?assert(abs(F64 - 2.5) < 0.001).

%%%===================================================================
%%% Remainder / Multi-Column Tests
%%%===================================================================

parse_tuple_with_remainder_test() ->
    %% Tuple column followed by extra bytes
    ColumnData = <<10:32/little, -1:64/little-signed, "extra">>,
    Data = create_test_block(<<"col">>, <<"Tuple(UInt32, Int64)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, Remainder} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([{10, -1}], ValueEvents),
    ?assertEqual(<<"extra">>, Remainder).

parse_tuple_then_scalar_column_test() ->
    %% Two columns: Tuple(UInt32, UInt32) then UInt64
    %% 2 rows: {1, 2} with 100, {3, 4} with 200
    TupleCol1 = <<1:32/little, 3:32/little>>,
    TupleCol2 = <<2:32/little, 4:32/little>>,
    TupleData = <<TupleCol1/binary, TupleCol2/binary>>,
    ScalarData = <<100:64/little, 200:64/little>>,
    Data = create_two_column_block(
        <<"tup">>,
        <<"Tuple(UInt32, UInt32)">>,
        TupleData,
        <<"num">>,
        <<"UInt64">>,
        ScalarData,
        2
    ),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([{1, 2}, {3, 4}, 100, 200], ValueEvents).

%%%===================================================================
%%% Truncated Data Tests
%%%===================================================================

parse_tuple_truncated_first_element_test() ->
    %% Tuple(UInt32, Int64): only 2 bytes of first UInt32 element
    ColumnData = <<10, 0>>,
    Data = create_test_block(<<"col">>, <<"Tuple(UInt32, Int64)">>, ColumnData, 1),
    State = init_parser(),
    Result = clickhouse_erl_parser_block:parse(Data, State),
    ?assertMatch({more, _, _, _}, Result).

parse_tuple_truncated_second_element_test() ->
    %% Tuple(UInt32, Int64): complete UInt32 but truncated Int64
    ColumnData = <<10:32/little, 0, 0, 0>>,
    Data = create_test_block(<<"col">>, <<"Tuple(UInt32, Int64)">>, ColumnData, 1),
    State = init_parser(),
    Result = clickhouse_erl_parser_block:parse(Data, State),
    ?assertMatch({more, _, _, _}, Result).

%%%===================================================================
%%% Column Event Metadata Tests
%%%===================================================================

parse_tuple_emits_column_event_test() ->
    %% Verify that the column metadata event is emitted correctly for Tuple types
    ColumnData = <<42:32/little, -1:64/little-signed>>,
    Data = create_test_block(<<"mycol">>, <<"Tuple(UInt32, Int64)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ColumnEvents = [E || {data, column, E} <- Events],
    ?assertEqual([#{name => <<"mycol">>, type => <<"Tuple(UInt32, Int64)">>}], ColumnEvents).
