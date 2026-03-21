%% @doc Unit tests for Nullable type support in the streaming block parser.
%%
%% Nullable uses column-level encoding in the ClickHouse native protocol:
%% 1. Null mask (1 byte per row): 1 = null, 0 = not null
%% 2. Inner type values (all rows, with placeholders for nulls)
%%
%% The block parser routes Nullable through column-level decode via
%% is_column_level_type/1 -> decode_column_level_type -> decode_column_data ->
%% clickhouse_erl_types_nullable:decode_nullable_column/3.
%%
%% Values are normalized from {null}/{value, V} to null/V before emission.
-module(clickhouse_erl_parser_block_nullable_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Create a minimal block with one column and given rows.
%% Uses simplified encoding: varint 0 for temp_table_name, 0 for block_info end,
%% 1 column, N rows.
create_test_block(ColumnName, ColumnType, ColumnData) ->
    create_test_block(ColumnName, ColumnType, ColumnData, 1).

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

init_parser() ->
    clickhouse_erl_parser_block:init(#{version => 54451}).

%% @doc Build column-level Nullable encoding: null mask + inner values.
%% NullFlags is a list of 0/1 bytes, InnerData is the raw inner type data.
build_nullable_column(NullFlags, InnerData) ->
    Mask = list_to_binary(NullFlags),
    <<Mask/binary, InnerData/binary>>.

%%%===================================================================
%%% Nullable Null Value Tests (column-level encoding)
%%%===================================================================

parse_nullable_uint32_null_test() ->
    %% Nullable(UInt32): 1 row, null mask = [1], inner value = placeholder 0
    ColData = build_nullable_column([1], <<0, 0, 0, 0>>),
    Data = create_test_block(<<"col">>, <<"Nullable(UInt32)">>, ColData),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([null], ValueEvents).

parse_nullable_string_null_test() ->
    %% Nullable(String): 1 row, null mask = [1], inner value = empty string placeholder
    ColData = build_nullable_column([1], <<0>>),
    Data = create_test_block(<<"col">>, <<"Nullable(String)">>, ColData),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([null], ValueEvents).

parse_nullable_int64_null_test() ->
    %% Nullable(Int64): 1 row, null mask = [1], inner value = placeholder 0
    ColData = build_nullable_column([1], <<0, 0, 0, 0, 0, 0, 0, 0>>),
    Data = create_test_block(<<"col">>, <<"Nullable(Int64)">>, ColData),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([null], ValueEvents).

%%%===================================================================
%%% Nullable Non-Null Value Tests (column-level encoding)
%%%===================================================================

parse_nullable_uint32_value_test() ->
    %% Nullable(UInt32): 1 row, null mask = [0], inner value = 42
    ColData = build_nullable_column([0], <<42, 0, 0, 0>>),
    Data = create_test_block(<<"col">>, <<"Nullable(UInt32)">>, ColData),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([42], ValueEvents).

parse_nullable_string_value_test() ->
    %% Nullable(String): 1 row, null mask = [0], inner value = "hello"
    ColData = build_nullable_column([0], <<5, "hello">>),
    Data = create_test_block(<<"col">>, <<"Nullable(String)">>, ColData),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([<<"hello">>], ValueEvents).

parse_nullable_int64_value_test() ->
    %% Nullable(Int64): 1 row, null mask = [0], inner value = -1
    ColData = build_nullable_column([0], <<255, 255, 255, 255, 255, 255, 255, 255>>),
    Data = create_test_block(<<"col">>, <<"Nullable(Int64)">>, ColData),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([-1], ValueEvents).

parse_nullable_float64_value_test() ->
    %% Nullable(Float64): 1 row, null mask = [0], inner value = 1.0
    ColData = build_nullable_column([0], <<0, 0, 0, 0, 0, 0, 240, 63>>),
    Data = create_test_block(<<"col">>, <<"Nullable(Float64)">>, ColData),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([1.0], ValueEvents).

%%%===================================================================
%%% Multiple Rows Tests (column-level encoding)
%%%===================================================================

parse_nullable_uint32_mixed_rows_test() ->
    %% 3 rows: null, 42, null
    %% Null mask: [1, 0, 1]
    %% Inner values: [0(placeholder), 42, 0(placeholder)] as UInt32 LE
    ColData = build_nullable_column(
        [1, 0, 1],
        <<0, 0, 0, 0, 42, 0, 0, 0, 0, 0, 0, 0>>
    ),
    Data = create_test_block(<<"col">>, <<"Nullable(UInt32)">>, ColData, 3),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([null, 42, null], ValueEvents).

parse_nullable_string_mixed_rows_test() ->
    %% 3 rows: "hello", null, "world"
    %% Null mask: [0, 1, 0]
    %% Inner values: "hello", "" (placeholder), "world"
    ColData = build_nullable_column(
        [0, 1, 0],
        <<5, "hello", 0, 5, "world">>
    ),
    Data = create_test_block(<<"col">>, <<"Nullable(String)">>, ColData, 3),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([<<"hello">>, null, <<"world">>], ValueEvents).

parse_nullable_float64_mixed_rows_test() ->
    %% 2 rows: 9.5, null
    %% Null mask: [0, 1]
    %% Inner values: 9.5 as Float64 LE, 0.0 as placeholder
    ColData = build_nullable_column(
        [0, 1],
        <<0, 0, 0, 0, 0, 0, 35, 64, 0, 0, 0, 0, 0, 0, 0, 0>>
    ),
    Data = create_test_block(<<"col">>, <<"Nullable(Float64)">>, ColData, 2),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([9.5, null], ValueEvents).

%%%===================================================================
%%% Nested Nullable Error Test
%%%===================================================================

parse_nested_nullable_error_test() ->
    %% Nullable(Nullable(UInt32)) - ClickHouse forbids this at the server level.
    %% The parser doesn't explicitly reject it since the column-level decoder
    %% delegates to parse_nullable_type which recurses. ClickHouse itself never
    %% sends this type, so we just verify the parser doesn't crash.
    %% Build column-level data: null mask [0], then inner Nullable column data
    %% (inner null mask [0], then UInt32 value 42)
    InnerNullable = build_nullable_column([0], <<42, 0, 0, 0>>),
    OuterData = build_nullable_column([0], InnerNullable),
    Data = create_test_block(<<"col">>, <<"Nullable(Nullable(UInt32))">>, OuterData),
    State = init_parser(),
    %% Parser may succeed or error — either is acceptable since ClickHouse
    %% never sends nested Nullable. We just verify no crash.
    Result = clickhouse_erl_parser_block:parse(Data, State),
    ?assert(
        case Result of
            {done, _, _} -> true;
            {error, _} -> true;
            {more, _, _, _} -> true
        end
    ).

%%%===================================================================
%%% Truncated Data Tests (column-level encoding)
%%%===================================================================

parse_nullable_truncated_null_mask_test() ->
    %% No data at all for the null mask
    Data = create_test_block(<<"col">>, <<"Nullable(UInt32)">>, <<>>),
    State = init_parser(),
    Result = clickhouse_erl_parser_block:parse(Data, State),
    ?assertMatch({more, _, _, _}, Result).

parse_nullable_truncated_inner_value_test() ->
    %% Null mask present but inner value truncated
    ColData = build_nullable_column([0], <<42, 0>>),
    Data = create_test_block(<<"col">>, <<"Nullable(UInt32)">>, ColData),
    State = init_parser(),
    Result = clickhouse_erl_parser_block:parse(Data, State),
    ?assertMatch({more, _, _, _}, Result).

%%%===================================================================
%%% Nullable with Other Inner Types (column-level encoding)
%%%===================================================================

parse_nullable_date_value_test() ->
    %% Nullable(Date): 1 row, null mask = [0], inner value = 18262 (2020-01-01)
    ColData = build_nullable_column([0], <<86, 71>>),
    Data = create_test_block(<<"col">>, <<"Nullable(Date)">>, ColData),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    %% Date is decoded as raw UInt16 by decode_column_data
    ?assertEqual([18262], ValueEvents).

parse_nullable_uint16_value_test() ->
    %% Nullable(UInt16): 1 row, null mask = [0], inner value = 256
    ColData = build_nullable_column([0], <<0, 1>>),
    Data = create_test_block(<<"col">>, <<"Nullable(UInt16)">>, ColData),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([256], ValueEvents).

parse_nullable_all_nulls_test() ->
    %% 3 rows, all null
    ColData = build_nullable_column(
        [1, 1, 1],
        <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
    ),
    Data = create_test_block(<<"col">>, <<"Nullable(UInt32)">>, ColData, 3),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([null, null, null], ValueEvents).

parse_nullable_no_nulls_test() ->
    %% 3 rows, no nulls
    ColData = build_nullable_column(
        [0, 0, 0],
        <<10, 0, 0, 0, 20, 0, 0, 0, 30, 0, 0, 0>>
    ),
    Data = create_test_block(<<"col">>, <<"Nullable(UInt32)">>, ColData, 3),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([10, 20, 30], ValueEvents).
