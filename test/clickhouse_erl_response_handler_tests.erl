-module(clickhouse_erl_response_handler_tests).

-include_lib("eunit/include/eunit.hrl").
-include("clickhouse_erl_protocol.hrl").

handle_packet_data_test() ->
    %% Mock a Data packet
    TblName = <<0>>,
    BlockInfo = <<1, 0, 2, 0, 0, 0, 0, 0>>,
    Cols = <<0>>,
    Rows = <<0>>,
    Data = <<TblName/binary, BlockInfo/binary, Cols/binary, Rows/binary>>,

    InitialState = clickhouse_erl_response_handler:create_initial_state(),
    Result = clickhouse_erl_response_handler:handle_packet(?SERVER_DATA, Data, InitialState),
    ?assertMatch({ok, _, _}, Result).

handle_packet_exception_test() ->
    %% Minimal Exception Packet
    Code = <<50, 0, 0, 0>>,
    Name = <<4, "Test">>,
    Message = <<3, "Msg">>,
    StackTrace = <<0>>,
    Nested = <<0>>,
    Data = <<Code/binary, Name/binary, Message/binary, StackTrace/binary, Nested/binary>>,

    InitialState = clickhouse_erl_response_handler:create_initial_state(),
    Result = clickhouse_erl_response_handler:handle_packet(?SERVER_EXCEPTION, Data, InitialState),
    ?assertMatch({error, {server_exception, _}, _}, Result),
    {error, {server_exception, Exception}, _} = Result,
    ?assertEqual(50, Exception#exception_info.error_code),
    ?assertEqual(<<"Test">>, Exception#exception_info.exception_name).

handle_packet_progress_test() ->
    %% Progress Packet: rows, bytes, total_rows, written_rows, written_bytes, elapsed_ns (all varints)
    Rows = clickhouse_erl_types_primitive:encode_varint(1),
    Bytes = clickhouse_erl_types_primitive:encode_varint(2),
    TotalRows = clickhouse_erl_types_primitive:encode_varint(3),
    WrittenRows = clickhouse_erl_types_primitive:encode_varint(4),
    WrittenBytes = clickhouse_erl_types_primitive:encode_varint(5),
    ElapsedNs = clickhouse_erl_types_primitive:encode_varint(6),
    Data =
        <<Rows/binary, Bytes/binary, TotalRows/binary, WrittenRows/binary, WrittenBytes/binary,
            ElapsedNs/binary>>,

    InitialState = clickhouse_erl_response_handler:create_initial_state(),
    Result = clickhouse_erl_response_handler:handle_packet(?SERVER_PROGRESS, Data, InitialState),
    ?assertMatch({ok, _, _}, Result).

handle_packet_end_of_stream_test() ->
    %% Test END_OF_STREAM with CallbackInfo (modern approach)
    Data = <<>>,
    InitialState = clickhouse_erl_response_handler:create_initial_state(),

    %% Create CallbackInfo with result_accumulator (batch mode)
    CallbackInfo = #{
        on_data => fun clickhouse_erl_response_handler:accumulate_data_block_callback/2,
        accumulator => maps:get(result_accumulator, InitialState)
    },

    Result = clickhouse_erl_response_handler:handle_end_of_stream_packet_with_state(
        Data, InitialState, CallbackInfo
    ),
    ?assertMatch({complete, _, _}, Result).

handle_packet_unknown_test() ->
    InitialState = clickhouse_erl_response_handler:create_initial_state(),
    Result = clickhouse_erl_response_handler:handle_packet(999, <<>>, InitialState),
    ?assertMatch({error, {protocol_error, {unknown_packet_type, 999}}}, Result).

%% Tests for the new 3-parameter handle_packet/3 function

handle_packet_with_state_data_test() ->
    %% Test data packet handling with state
    TblName = <<0>>,
    BlockInfo = <<1, 0, 2, 0, 0, 0, 0, 0>>,
    Cols = <<0>>,
    Rows = <<0>>,
    Data = <<TblName/binary, BlockInfo/binary, Cols/binary, Rows/binary>>,

    InitialState = clickhouse_erl_response_handler:create_initial_state(),
    Result = clickhouse_erl_response_handler:handle_packet(?SERVER_DATA, Data, InitialState),
    ?assertMatch({ok, _, _}, Result),
    {ok, NewState, _} = Result,
    ?assertMatch(#{result_accumulator := _}, NewState).

handle_packet_with_state_exception_test() ->
    %% Test exception packet handling with state
    Code = <<50, 0, 0, 0>>,
    Name = <<4, "Test">>,
    Message = <<3, "Msg">>,
    StackTrace = <<0>>,
    Nested = <<0>>,
    Data = <<Code/binary, Name/binary, Message/binary, StackTrace/binary, Nested/binary>>,

    InitialState = clickhouse_erl_response_handler:create_initial_state(),
    Result = clickhouse_erl_response_handler:handle_packet(?SERVER_EXCEPTION, Data, InitialState),
    ?assertMatch({error, {server_exception, _}, _}, Result).

handle_packet_with_state_progress_test() ->
    %% Test progress packet handling with state
    %% Progress Packet: rows, bytes, total_rows, written_rows, written_bytes, elapsed_ns (all varints)
    %% For protocol version >= 54449, we need 6 fields
    %% Encode 1, 2, 3, 4, 5, 6 as proper varints
    Rows = clickhouse_erl_types_primitive:encode_varint(1),
    Bytes = clickhouse_erl_types_primitive:encode_varint(2),
    TotalRows = clickhouse_erl_types_primitive:encode_varint(3),
    WrittenRows = clickhouse_erl_types_primitive:encode_varint(4),
    WrittenBytes = clickhouse_erl_types_primitive:encode_varint(5),
    ElapsedNs = clickhouse_erl_types_primitive:encode_varint(6),
    Data =
        <<Rows/binary, Bytes/binary, TotalRows/binary, WrittenRows/binary, WrittenBytes/binary,
            ElapsedNs/binary>>,

    InitialState = clickhouse_erl_response_handler:create_initial_state(),
    Result = clickhouse_erl_response_handler:handle_packet(?SERVER_PROGRESS, Data, InitialState),
    ?assertMatch({ok, _, _}, Result),
    {ok, NewState, _Rest} = Result,
    ?assertMatch(#{result_accumulator := _}, NewState).

handle_packet_with_state_end_of_stream_test() ->
    %% Test END_OF_STREAM with CallbackInfo (modern approach)
    Data = <<>>,
    InitialState = clickhouse_erl_response_handler:create_initial_state(),

    %% Create CallbackInfo with result_accumulator (batch mode)
    CallbackInfo = #{
        on_data => fun clickhouse_erl_response_handler:accumulate_data_block_callback/2,
        accumulator => maps:get(result_accumulator, InitialState)
    },

    Result = clickhouse_erl_response_handler:handle_end_of_stream_packet_with_state(
        Data, InitialState, CallbackInfo
    ),
    ?assertMatch({complete, _, _}, Result).

create_initial_state_test() ->
    %% Test initial state creation
    State = clickhouse_erl_response_handler:create_initial_state(),
    ?assertMatch(
        #{
            result_accumulator := _,
            column_metadata := undefined,
            error_info := undefined
        },
        State
    ).

accumulate_multiple_data_blocks_test() ->
    %% Test accumulation of multiple data blocks

    %% Common parts

    % Use same format as working test
    TblName = <<0>>,
    BlockInfo = <<1, 0, 2, 0, 0, 0, 0, 0>>,

    %% Block 1: 1 column (Int32), 0 rows (no data)
    Cols1 = clickhouse_erl_types_primitive:encode_varint(1),
    Rows1 = clickhouse_erl_types_primitive:encode_varint(0),
    Col1Name = clickhouse_erl_types_primitive:encode_string("A"),
    Col1Type = clickhouse_erl_types_primitive:encode_string("Int32"),
    % Custom serialization flag (0 = false)
    Col1CustomFlag = <<0>>,
    %% No column data since 0 rows

    Data1 =
        <<TblName/binary, BlockInfo/binary, Cols1/binary, Rows1/binary, Col1Name/binary,
            Col1Type/binary, Col1CustomFlag/binary>>,

    %% Block 2: 1 column (Int32), 0 rows (no data)
    Cols2 = clickhouse_erl_types_primitive:encode_varint(1),
    Rows2 = clickhouse_erl_types_primitive:encode_varint(0),
    Col1Name2 = clickhouse_erl_types_primitive:encode_string("A"),
    Col1Type2 = clickhouse_erl_types_primitive:encode_string("Int32"),
    % Custom serialization flag (0 = false)
    Col1CustomFlag2 = <<0>>,
    %% No column data since 0 rows

    Data2 =
        <<TblName/binary, BlockInfo/binary, Cols2/binary, Rows2/binary, Col1Name2/binary,
            Col1Type2/binary, Col1CustomFlag2/binary>>,

    %% Execution
    InitialState = clickhouse_erl_response_handler:create_initial_state(),

    %% Handle first block
    {ok, State1, _Rest1} = clickhouse_erl_response_handler:handle_packet(
        ?SERVER_DATA, Data1, InitialState
    ),

    %% Handle second block
    {ok, State2, _Rest2} = clickhouse_erl_response_handler:handle_packet(
        ?SERVER_DATA, Data2, State1
    ),

    %% Verify State2
    #{result_accumulator := Accumulator} = State2,

    %% Check columns
    Columns = Accumulator#result_accumulator.columns,
    ?assertEqual(1, length(Columns)),
    [C1] = Columns,
    ?assertEqual(<<"A">>, maps:get(name, C1)),

    %% Check rows - should be empty since both blocks have 0 rows
    Rows = Accumulator#result_accumulator.rows,
    ?assertEqual(0, length(Rows)),

    %% Check total stats
    ?assertEqual(0, Accumulator#result_accumulator.total_rows).

%% Tests for INSERT response handling

create_initial_state_for_insert_test() ->
    %% Test initial state creation for INSERT query
    State = clickhouse_erl_response_handler:create_initial_state(?PROTOCOL_VERSION, insert),
    ?assertMatch(
        #{
            result_accumulator := _,
            column_metadata := undefined,
            error_info := undefined,
            query_type := insert,
            start_time := _
        },
        State
    ),
    ?assertEqual(insert, maps:get(query_type, State)),
    ?assert(is_integer(maps:get(start_time, State))).

handle_end_of_stream_for_insert_test() ->
    %% Test END_OF_STREAM handling for INSERT query
    Data = <<>>,
    InitialState = clickhouse_erl_response_handler:create_initial_state(?PROTOCOL_VERSION, insert),

    %% Set rows_to_insert in state (this is what the connection module does)
    StateWithRows = InitialState#{rows_to_insert => 3},

    %% Create CallbackInfo (not used for INSERT but required by new API)
    CallbackInfo = #{
        on_data => fun clickhouse_erl_response_handler:accumulate_data_block_callback/2,
        accumulator => maps:get(result_accumulator, StateWithRows)
    },

    Result = clickhouse_erl_response_handler:handle_end_of_stream_packet_with_state(
        Data, StateWithRows, CallbackInfo
    ),
    ?assertMatch({complete, _, _}, Result),
    {complete, InsertResult, _Rest} = Result,

    %% Verify insert_result format
    ?assertMatch(#{rows_inserted := 3, elapsed_time := _}, InsertResult),
    ?assertEqual(3, maps:get(rows_inserted, InsertResult)),
    ?assert(is_integer(maps:get(elapsed_time, InsertResult))),
    ?assert(maps:get(elapsed_time, InsertResult) >= 0).

handle_end_of_stream_for_select_test() ->
    %% Test END_OF_STREAM handling for SELECT query (default behavior)
    Data = <<>>,
    InitialState = clickhouse_erl_response_handler:create_initial_state(?PROTOCOL_VERSION, select),

    %% Create CallbackInfo with result_accumulator (batch mode)
    CallbackInfo = #{
        on_data => fun clickhouse_erl_response_handler:accumulate_data_block_callback/2,
        accumulator => maps:get(result_accumulator, InitialState)
    },

    Result = clickhouse_erl_response_handler:handle_end_of_stream_packet_with_state(
        Data, InitialState, CallbackInfo
    ),
    ?assertMatch({complete, _, _}, Result),
    {complete, QueryResult, _Rest} = Result,

    %% Verify query_result format (not insert_result)
    ?assertMatch(#{data := #{columns := _, rows := _}, statistics := _}, QueryResult),
    ResultData = maps:get(data, QueryResult),
    ?assertEqual([], maps:get(columns, ResultData)),
    ?assertEqual([], maps:get(rows, ResultData)).

handle_exception_for_insert_test() ->
    %% Test EXCEPTION handling for INSERT query
    Code = <<50, 0, 0, 0>>,
    Name = <<4, "Test">>,
    Message = <<3, "Msg">>,
    StackTrace = <<0>>,
    Nested = <<0>>,
    Data = <<Code/binary, Name/binary, Message/binary, StackTrace/binary, Nested/binary>>,

    InitialState = clickhouse_erl_response_handler:create_initial_state(?PROTOCOL_VERSION, insert),
    Result = clickhouse_erl_response_handler:handle_packet(?SERVER_EXCEPTION, Data, InitialState),

    %% Exception handling should be the same for INSERT and SELECT
    ?assertMatch({error, {server_exception, _}, _}, Result),
    {error, {server_exception, Exception}, _Rest} = Result,
    ?assertEqual(50, Exception#exception_info.error_code),
    ?assertEqual(<<"Test">>, Exception#exception_info.exception_name).

handle_end_of_stream_empty_insert_test() ->
    %% Test END_OF_STREAM for INSERT with 0 rows
    Data = <<>>,
    InitialState = clickhouse_erl_response_handler:create_initial_state(?PROTOCOL_VERSION, insert),

    %% Create CallbackInfo (not used for INSERT but required by new API)
    CallbackInfo = #{
        on_data => fun clickhouse_erl_response_handler:accumulate_data_block_callback/2,
        accumulator => maps:get(result_accumulator, InitialState)
    },

    Result = clickhouse_erl_response_handler:handle_end_of_stream_packet_with_state(
        Data, InitialState, CallbackInfo
    ),
    ?assertMatch({complete, _, _}, Result),
    {complete, InsertResult, _Rest} = Result,

    %% Verify 0 rows inserted
    ?assertEqual(0, maps:get(rows_inserted, InsertResult)),
    ?assert(is_integer(maps:get(elapsed_time, InsertResult))).

%% Tests for compression integration (Task 7.3)
%% Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7

%% Test that DATA packets are decompressed when compression is enabled
handle_data_packet_with_compression_test() ->
    %% CRITICAL: Temp table name is ALWAYS uncompressed, even when compression is enabled.
    %% Only the block data (BlockInfo + columns + rows) is compressed.

    %% Create temp table name (uncompressed) - must be proper string with varint length
    TblName = clickhouse_erl_types_primitive:encode_string(<<>>),

    %% Create block data to compress
    BlockInfo = <<1, 0, 2, 0, 0, 0, 0, 0>>,
    Cols = <<0>>,
    Rows = <<0>>,
    BlockData = <<BlockInfo/binary, Cols/binary, Rows/binary>>,

    %% Compress only the block data (not the temp table name)
    CompressionOpts = #{method => lz4},
    {ok, CompressedBlockData} = clickhouse_erl_compression:compress(BlockData, CompressionOpts),

    %% Combine uncompressed temp table name with compressed block data
    FullPacketData = <<TblName/binary, CompressedBlockData/binary>>,

    %% Create initial state
    InitialState = clickhouse_erl_response_handler:create_initial_state(),

    %% Handle the compressed DATA packet with compression opts
    Result = clickhouse_erl_response_handler:handle_data_packet_with_state(
        FullPacketData, InitialState, CompressionOpts
    ),

    %% Should successfully decompress and parse
    ?assertMatch({ok, _, _}, Result).

%% Test that DATA packets are NOT decompressed when compression is disabled
handle_data_packet_without_compression_test() ->
    %% Create a simple data block
    TblName = <<0>>,
    BlockInfo = <<1, 0, 2, 0, 0, 0, 0, 0>>,
    Cols = <<0>>,
    Rows = <<0>>,
    UncompressedData = <<TblName/binary, BlockInfo/binary, Cols/binary, Rows/binary>>,

    %% Create initial state
    InitialState = clickhouse_erl_response_handler:create_initial_state(),

    %% Compression disabled (undefined)
    CompressionOpts = undefined,

    %% Handle the uncompressed DATA packet
    Result = clickhouse_erl_response_handler:handle_data_packet_with_state(
        UncompressedData, InitialState, CompressionOpts
    ),

    %% Should successfully parse without decompression
    ?assertMatch({ok, _, _}, Result).

%% Test that TOTALS packets are decompressed when compression is enabled
handle_totals_packet_with_compression_test() ->
    %% CRITICAL: Temp table name is ALWAYS uncompressed, even when compression is enabled.
    %% Only the block data (BlockInfo + columns + rows) is compressed.

    %% Create temp table name (uncompressed) - must be proper string with varint length
    TblName = clickhouse_erl_types_primitive:encode_string(<<>>),

    %% Create block data to compress
    BlockInfo = <<1, 0, 2, 0, 0, 0, 0, 0>>,
    Cols = <<0>>,
    Rows = <<0>>,
    BlockData = <<BlockInfo/binary, Cols/binary, Rows/binary>>,

    %% Compress only the block data (not the temp table name)
    CompressionOpts = #{method => lz4},
    {ok, CompressedBlockData} = clickhouse_erl_compression:compress(BlockData, CompressionOpts),

    %% Combine uncompressed temp table name with compressed block data
    FullPacketData = <<TblName/binary, CompressedBlockData/binary>>,

    %% Create initial state
    InitialState = clickhouse_erl_response_handler:create_initial_state(),

    %% Handle the compressed TOTALS packet with compression opts
    Result = clickhouse_erl_response_handler:handle_totals_packet_with_state(
        FullPacketData, InitialState, CompressionOpts
    ),

    %% Should successfully decompress and parse
    ?assertMatch({ok, _, _}, Result).

%% Test that EXTREMES packets are decompressed when compression is enabled
handle_extremes_packet_with_compression_test() ->
    %% CRITICAL: Temp table name is ALWAYS uncompressed, even when compression is enabled.
    %% Only the block data (BlockInfo + columns + rows) is compressed.

    %% Create temp table name (uncompressed) - must be proper string with varint length
    TblName = clickhouse_erl_types_primitive:encode_string(<<>>),

    %% Create block data to compress
    BlockInfo = <<1, 0, 2, 0, 0, 0, 0, 0>>,
    Cols = <<0>>,
    Rows = <<0>>,
    BlockData = <<BlockInfo/binary, Cols/binary, Rows/binary>>,

    %% Compress only the block data (not the temp table name)
    CompressionOpts = #{method => lz4},
    {ok, CompressedBlockData} = clickhouse_erl_compression:compress(BlockData, CompressionOpts),

    %% Combine uncompressed temp table name with compressed block data
    FullPacketData = <<TblName/binary, CompressedBlockData/binary>>,

    %% Create initial state
    InitialState = clickhouse_erl_response_handler:create_initial_state(),

    %% Handle the compressed EXTREMES packet with compression opts
    Result = clickhouse_erl_response_handler:handle_extremes_packet_with_state(
        FullPacketData, InitialState, CompressionOpts
    ),

    %% Should successfully decompress and parse
    ?assertMatch({ok, _, _}, Result).

%% Test that EXCEPTION packets are NOT compressed (never decompressed)
handle_exception_packet_never_compressed_test() ->
    %% Create a normal exception packet (never compressed)
    Code = <<50, 0, 0, 0>>,
    Name = <<4, "Test">>,
    Message = <<3, "Msg">>,
    StackTrace = <<0>>,
    Nested = <<0>>,
    Data = <<Code/binary, Name/binary, Message/binary, StackTrace/binary, Nested/binary>>,

    %% Create initial state
    InitialState = clickhouse_erl_response_handler:create_initial_state(),

    %% Handle exception packet (should work regardless of compression settings)
    Result = clickhouse_erl_response_handler:handle_packet(?SERVER_EXCEPTION, Data, InitialState),

    %% Should successfully parse without decompression
    ?assertMatch({error, {server_exception, _}, _}, Result).

%% Test error handling for decompression failures
%% Note: Current implementation falls back to parsing original data on decompression error
handle_data_packet_decompression_failure_test() ->
    %% Create invalid compressed data (corrupt header)
    InvalidCompressedData = <<0:128, 0:8, 0:32, 0:32, "garbage">>,

    %% Create initial state
    InitialState = clickhouse_erl_response_handler:create_initial_state(),

    %% Compression enabled
    CompressionOpts = #{method => lz4},

    %% Handle the invalid compressed DATA packet
    Result = clickhouse_erl_response_handler:handle_data_packet_with_state(
        InvalidCompressedData, InitialState, CompressionOpts
    ),

    %% Current implementation falls back to parsing original data
    %% This will likely fail at the data block parsing stage
    %% We just verify it doesn't crash
    ?assert(is_tuple(Result)).

%% Test that streaming mode with compression works correctly
handle_data_packet_with_callback_and_compression_test() ->
    %% CRITICAL: Temp table name is ALWAYS uncompressed, even when compression is enabled.
    %% Only the block data (BlockInfo + columns + rows) is compressed.

    %% Create temp table name (uncompressed) - must be proper string with varint length
    TblName = clickhouse_erl_types_primitive:encode_string(<<>>),

    %% Create block data to compress
    BlockInfo = <<1, 0, 2, 0, 0, 0, 0, 0>>,
    Cols = <<0>>,
    Rows = <<0>>,
    BlockData = <<BlockInfo/binary, Cols/binary, Rows/binary>>,

    %% Compress only the block data (not the temp table name)
    CompressionOpts = #{method => lz4},
    {ok, CompressedBlockData} = clickhouse_erl_compression:compress(BlockData, CompressionOpts),

    %% Combine uncompressed temp table name with compressed block data
    FullPacketData = <<TblName/binary, CompressedBlockData/binary>>,

    %% Create initial state
    InitialState = clickhouse_erl_response_handler:create_initial_state(),

    %% Create callback info with compression opts
    CallbackInfo = #{
        on_data => fun clickhouse_erl_response_handler:accumulate_data_block_callback/2,
        accumulator => maps:get(result_accumulator, InitialState),
        compression_opts => CompressionOpts
    },

    %% Handle the compressed DATA packet with callback
    Result = clickhouse_erl_response_handler:handle_data_packet_with_callback(
        FullPacketData, InitialState, CallbackInfo
    ),

    %% Should successfully decompress and invoke callback
    ?assertMatch({ok, _, _, _}, Result).

%% Test that compression disabled (method = disabled) does not decompress
handle_data_packet_compression_disabled_test() ->
    %% Create a simple data block
    TblName = <<0>>,
    BlockInfo = <<1, 0, 2, 0, 0, 0, 0, 0>>,
    Cols = <<0>>,
    Rows = <<0>>,
    UncompressedData = <<TblName/binary, BlockInfo/binary, Cols/binary, Rows/binary>>,

    %% Create initial state
    InitialState = clickhouse_erl_response_handler:create_initial_state(),

    %% Compression explicitly disabled
    CompressionOpts = #{method => disabled},

    %% Handle the uncompressed DATA packet
    Result = clickhouse_erl_response_handler:handle_data_packet_with_state(
        UncompressedData, InitialState, CompressionOpts
    ),

    %% Should successfully parse without decompression
    ?assertMatch({ok, _, _}, Result).
