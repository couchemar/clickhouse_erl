%% @doc Unit tests for LowCardinality type support in the block parser.
%%
%% Tests verify that the block parser can handle LowCardinality(T) columns
%% in streaming mode. LowCardinality uses dictionary encoding at the column
%% level, so the block parser pre-decodes the entire column and emits
%% individual values via column_value events.
-module(clickhouse_erl_parser_block_low_cardinality_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Create a minimal block with one column and given rows.
%% Uses simplified encoding (varint as single byte, no custom serialization).
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

%% @doc Encode a LowCardinality column with dictionary encoding.
%% This builds the wire format: state_version + metadata + dict_size + dict + keys_size + keys
encode_low_cardinality_column(Values, InnerType) ->
    %% State version = 1 (Int64 LE)
    StateVersion = <<1:64/little-signed-integer>>,
    %% Build dictionary (unique values in order)
    Dict = lists:usort(Values),
    DictSize = length(Dict),
    %% Key type = UInt8 (code 0), flags = has_additional_keys | need_update_dictionary
    %% CARDINALITY_HAS_ADDITIONAL_KEYS_BIT = 1 bsl 9 = 512
    %% CARDINALITY_NEED_UPDATE_DICTIONARY = 1 bsl 10 = 1024
    %% Combined = 1536, plus key type 0 = 1536
    Meta = <<1536:64/little-signed-integer>>,
    DictSizeEnc = <<DictSize:64/little-signed-integer>>,
    %% Encode dictionary values
    DictEncoded = encode_dict_values(Dict, InnerType),
    %% Build key mapping
    KeyMap = build_key_map(Dict),
    Keys = [maps:get(V, KeyMap) || V <- Values],
    KeysSize = length(Keys),
    KeysSizeEnc = <<KeysSize:64/little-signed-integer>>,
    KeysEncoded = list_to_binary([<<K:8>> || K <- Keys]),
    <<StateVersion/binary, Meta/binary, DictSizeEnc/binary, DictEncoded/binary, KeysSizeEnc/binary,
        KeysEncoded/binary>>.

encode_dict_values(Values, string) ->
    list_to_binary([encode_string(V) || V <- Values]);
encode_dict_values(Values, uint32) ->
    list_to_binary([<<V:32/little-unsigned-integer>> || V <- Values]);
encode_dict_values(Values, int64) ->
    list_to_binary([<<V:64/little-signed-integer>> || V <- Values]).

encode_string(Bin) when is_binary(Bin) ->
    Len = byte_size(Bin),
    <<Len, Bin/binary>>.

build_key_map(Dict) ->
    {Map, _} = lists:foldl(
        fun(V, {Acc, Idx}) -> {maps:put(V, Idx, Acc), Idx + 1} end,
        {#{}, 0},
        Dict
    ),
    Map.

%%%===================================================================
%%% LowCardinality Column-Level Decoding Tests
%%%===================================================================

parse_low_cardinality_string_test() ->
    %% LowCardinality(String) with 3 rows: "foo", "bar", "foo"
    ColumnData = encode_low_cardinality_column([<<"bar">>, <<"foo">>, <<"bar">>], string),
    Data = create_test_block(<<"col">>, <<"LowCardinality(String)">>, ColumnData, 3),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([<<"bar">>, <<"foo">>, <<"bar">>], ValueEvents).

parse_low_cardinality_uint32_test() ->
    %% LowCardinality(UInt32) with 4 rows: 1, 2, 1, 2
    ColumnData = encode_low_cardinality_column([1, 2, 1, 2], uint32),
    Data = create_test_block(<<"col">>, <<"LowCardinality(UInt32)">>, ColumnData, 4),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([1, 2, 1, 2], ValueEvents).

parse_low_cardinality_single_value_test() ->
    %% LowCardinality(String) with 1 row: "hello"
    ColumnData = encode_low_cardinality_column([<<"hello">>], string),
    Data = create_test_block(<<"col">>, <<"LowCardinality(String)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([<<"hello">>], ValueEvents).

parse_low_cardinality_emits_column_metadata_test() ->
    %% Verify column metadata event includes LowCardinality type
    ColumnData = encode_low_cardinality_column([<<"a">>], string),
    Data = create_test_block(<<"col">>, <<"LowCardinality(String)">>, ColumnData, 1),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ColEvents = [M || {data, column, M} <- Events],
    ?assertMatch([#{name := <<"col">>, type := <<"LowCardinality(String)">>}], ColEvents).

parse_low_cardinality_remainder_test() ->
    %% Verify remainder bytes are preserved after parsing
    ColumnData = encode_low_cardinality_column([<<"x">>], string),
    Remainder = <<99, 100, 101>>,
    Data = create_test_block(<<"col">>, <<"LowCardinality(String)">>, ColumnData, 1),
    FullData = <<Data/binary, Remainder/binary>>,
    State = init_parser(),
    {done, _Events, Rest} = clickhouse_erl_parser_block:parse(FullData, State),
    ?assertEqual(Remainder, Rest).

%%%===================================================================
%%% LowCardinality Zero-Row Block Tests (RowCount=0 fix)
%%%===================================================================

%% @doc Test that decode_low_cardinality_column/3 returns empty list for 0 rows.
%% ClickHouse sends header blocks with NumColumns=1, NumRows=0 before data blocks.
%% For LowCardinality with 0 rows, no state version or column data is sent.
%% Previously this caused {invalid_state_version, -1090921627647} because the
%% decoder tried to read 8 bytes from the next block's data.
decode_low_cardinality_column_zero_rows_test() ->
    Remainder = <<1, 2, 3, 4, 5, 6, 7, 8>>,
    {ok, Values, Rest} =
        clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(
            Remainder, string, 0
        ),
    ?assertEqual([], Values),
    ?assertEqual(Remainder, Rest).

decode_low_cardinality_column_zero_rows_empty_binary_test() ->
    {ok, Values, Rest} =
        clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(
            <<>>, string, 0
        ),
    ?assertEqual([], Values),
    ?assertEqual(<<>>, Rest).

decode_low_cardinality_column_zero_rows_any_inner_type_test() ->
    %% Should work for any inner type when RowCount=0
    {ok, [], <<>>} =
        clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(<<>>, uint32, 0),
    {ok, [], <<>>} =
        clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(<<>>, int64, 0),
    {ok, [], <<>>} =
        clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(<<>>, float64, 0),
    ok.

%% @doc Test that the block parser handles a 0-row LowCardinality block correctly.
%% This simulates the header block ClickHouse sends before the actual data block.
parse_low_cardinality_zero_rows_block_test() ->
    %% 0 rows, no column data (ClickHouse sends no LC data for 0-row blocks)
    Data = create_test_block(<<"col">>, <<"LowCardinality(String)">>, <<>>, 0),
    State = init_parser(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    %% Should have column metadata but no column_value events
    ColEvents = [M || {data, column, M} <- Events],
    ?assertMatch([#{name := <<"col">>, type := <<"LowCardinality(String)">>}], ColEvents),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([], ValueEvents).
