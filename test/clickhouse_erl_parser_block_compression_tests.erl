%% @doc Unit tests for block parser compression/decompression support.
%%
%% Tests verify that clickhouse_erl_parser_block correctly handles compressed
%% block data after the temp table name when compression is enabled.
-module(clickhouse_erl_parser_block_compression_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Build raw block payload (block_info + num_columns + num_rows + column data).
%% This is the data that gets compressed when compression is enabled.
-spec build_raw_block_payload(binary(), binary(), binary()) -> binary().
build_raw_block_payload(ColumnName, ColumnType, ColumnData) ->
    %% BlockInfo: field 0 (end marker)
    BlockInfo = <<0>>,
    %% NumColumns: 1
    NumColumns = <<1>>,
    %% NumRows: 1
    NumRows = <<1>>,
    %% Column name (varint-prefixed)
    NameLen = byte_size(ColumnName),
    ColName = <<NameLen, ColumnName/binary>>,
    %% Column type (varint-prefixed)
    TypeLen = byte_size(ColumnType),
    ColType = <<TypeLen, ColumnType/binary>>,
    <<BlockInfo/binary, NumColumns/binary, NumRows/binary, ColName/binary, ColType/binary,
        ColumnData/binary>>.

%% @doc Build a complete block with uncompressed temp table name + compressed payload.
-spec build_compressed_block(binary(), binary(), binary()) -> binary().
build_compressed_block(ColumnName, ColumnType, ColumnData) ->
    TempTableName = <<0>>,
    RawPayload = build_raw_block_payload(ColumnName, ColumnType, ColumnData),
    {ok, CompressedPayload} = clickhouse_erl_compression:compress(RawPayload, #{method => lz4}),
    <<TempTableName/binary, CompressedPayload/binary>>.

%% @doc Build a complete uncompressed block (for regression testing).
-spec build_uncompressed_block(binary(), binary(), binary()) -> binary().
build_uncompressed_block(ColumnName, ColumnType, ColumnData) ->
    TempTableName = <<0>>,
    RawPayload = build_raw_block_payload(ColumnName, ColumnType, ColumnData),
    <<TempTableName/binary, RawPayload/binary>>.

%% @doc Initialize parser state with compression enabled (LZ4).
-spec init_parser_compressed() -> map().
init_parser_compressed() ->
    clickhouse_erl_parser_block:init(#{
        version => 54451,
        compression_opts => #{method => lz4},
        packet_type => server_data
    }).

%% @doc Initialize parser state with compression disabled.
-spec init_parser_no_compression() -> map().
init_parser_no_compression() ->
    clickhouse_erl_parser_block:init(#{version => 54451}).

%% @doc Initialize parser state with compression explicitly disabled.
-spec init_parser_disabled() -> map().
init_parser_disabled() ->
    clickhouse_erl_parser_block:init(#{
        version => 54451,
        compression_opts => #{method => disabled}
    }).

%%%===================================================================
%%% Compressed Block Parsing Tests
%%%===================================================================

%% Verify that a compressed UInt32 block parses correctly
compressed_uint32_block_test() ->
    Data = build_compressed_block(<<"col">>, <<"UInt32">>, <<42, 0, 0, 0>>),
    State = init_parser_compressed(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([42], ValueEvents).

%% Verify that a compressed String block parses correctly
compressed_string_block_test() ->
    Data = build_compressed_block(<<"name">>, <<"String">>, <<5, "hello">>),
    State = init_parser_compressed(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([<<"hello">>], ValueEvents).

%% Verify that compressed block with trailing data returns correct remainder
compressed_block_with_trailing_data_test() ->
    TrailingData = <<99, 88, 77>>,
    Data = build_compressed_block(<<"col">>, <<"UInt32">>, <<42, 0, 0, 0>>),
    FullData = <<Data/binary, TrailingData/binary>>,
    State = init_parser_compressed(),
    {done, Events, Rest} = clickhouse_erl_parser_block:parse(FullData, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([42], ValueEvents),
    %% Trailing data should be returned as remainder
    ?assertEqual(TrailingData, Rest).

%% Verify that incomplete compressed block returns {more, ...}
incomplete_compressed_block_test() ->
    TempTableName = <<0>>,
    RawPayload = build_raw_block_payload(<<"col">>, <<"UInt32">>, <<42, 0, 0, 0>>),
    {ok, CompressedPayload} = clickhouse_erl_compression:compress(RawPayload, #{method => lz4}),
    %% Truncate the compressed payload to simulate incomplete data
    TruncatedSize = byte_size(CompressedPayload) div 2,
    <<Truncated:TruncatedSize/binary, _/binary>> = CompressedPayload,
    Data = <<TempTableName/binary, Truncated/binary>>,
    State = init_parser_compressed(),
    Result = clickhouse_erl_parser_block:parse(Data, State),
    ?assertMatch({more, _, _, _}, Result).

%% Verify that compression disabled still works (no regression)
no_compression_regression_test() ->
    Data = build_uncompressed_block(<<"col">>, <<"UInt32">>, <<42, 0, 0, 0>>),
    State = init_parser_no_compression(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([42], ValueEvents).

%% Verify that explicitly disabled compression works
disabled_compression_regression_test() ->
    Data = build_uncompressed_block(<<"col">>, <<"UInt32">>, <<42, 0, 0, 0>>),
    State = init_parser_disabled(),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([42], ValueEvents).

%% Verify ZSTD compressed block parses correctly
compressed_zstd_block_test() ->
    TempTableName = <<0>>,
    RawPayload = build_raw_block_payload(<<"col">>, <<"UInt32">>, <<42, 0, 0, 0>>),
    {ok, CompressedPayload} = clickhouse_erl_compression:compress(RawPayload, #{method => zstd}),
    Data = <<TempTableName/binary, CompressedPayload/binary>>,
    State = clickhouse_erl_parser_block:init(#{
        version => 54451,
        compression_opts => #{method => zstd},
        packet_type => server_data
    }),
    {done, Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State),
    ValueEvents = [V || {data, column_value, V} <- Events],
    ?assertEqual([42], ValueEvents).

%% Verify empty block (0 columns, 0 rows) with compression
compressed_empty_block_test() ->
    TempTableName = <<0>>,
    %% Empty block: BlockInfo end marker + 0 columns + 0 rows
    RawPayload = <<0, 0, 0>>,
    {ok, CompressedPayload} = clickhouse_erl_compression:compress(RawPayload, #{method => lz4}),
    Data = <<TempTableName/binary, CompressedPayload/binary>>,
    State = init_parser_compressed(),
    {done, _Events, <<>>} = clickhouse_erl_parser_block:parse(Data, State).

%% Verify that too-small data (less than 25 bytes header) returns {more, ...}
too_small_compressed_data_test() ->
    TempTableName = <<0>>,
    %% Only 10 bytes - not enough for compressed block header (25 bytes)
    TooSmall = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>,
    Data = <<TempTableName/binary, TooSmall/binary>>,
    State = init_parser_compressed(),
    Result = clickhouse_erl_parser_block:parse(Data, State),
    ?assertMatch({more, _, _, _}, Result).
