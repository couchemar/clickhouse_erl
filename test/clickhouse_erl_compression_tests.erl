%% @doc Unit tests for clickhouse_erl_compression module
-module(clickhouse_erl_compression_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% validate_opts/1 tests
%%%===================================================================

validate_opts_disabled_test() ->
    ?assertEqual(
        {ok, #{method => disabled}},
        clickhouse_erl_compression:validate_opts(#{})
    ).

validate_opts_explicit_disabled_test() ->
    ?assertEqual(
        {ok, #{method => disabled}},
        clickhouse_erl_compression:validate_opts(#{compression => disabled})
    ).

validate_opts_lz4_no_level_test() ->
    ?assertEqual(
        {ok, #{method => lz4}},
        clickhouse_erl_compression:validate_opts(#{compression => lz4})
    ).

validate_opts_lz4_with_valid_level_test() ->
    ?assertEqual(
        {ok, #{method => lz4, level => 5}},
        clickhouse_erl_compression:validate_opts(#{compression => lz4, compression_level => 5})
    ).

validate_opts_lz4_level_zero_test() ->
    ?assertEqual(
        {ok, #{method => lz4, level => 0}},
        clickhouse_erl_compression:validate_opts(#{compression => lz4, compression_level => 0})
    ).

validate_opts_lz4_level_max_test() ->
    ?assertEqual(
        {ok, #{method => lz4, level => 12}},
        clickhouse_erl_compression:validate_opts(#{compression => lz4, compression_level => 12})
    ).

validate_opts_lz4_invalid_level_negative_test() ->
    ?assertEqual(
        {error, {invalid_compression_level, -1}},
        clickhouse_erl_compression:validate_opts(#{compression => lz4, compression_level => -1})
    ).

validate_opts_lz4_invalid_level_too_high_test() ->
    ?assertEqual(
        {error, {invalid_compression_level, 13}},
        clickhouse_erl_compression:validate_opts(#{compression => lz4, compression_level => 13})
    ).

validate_opts_lz4_invalid_level_not_integer_test() ->
    ?assertEqual(
        {error, {invalid_compression_level, <<"5">>}},
        clickhouse_erl_compression:validate_opts(#{compression => lz4, compression_level => <<"5">>})
    ).

validate_opts_zstd_test() ->
    ?assertEqual(
        {ok, #{method => zstd}},
        clickhouse_erl_compression:validate_opts(#{compression => zstd})
    ).

validate_opts_zstd_ignores_level_test() ->
    ?assertEqual(
        {ok, #{method => zstd}},
        clickhouse_erl_compression:validate_opts(#{compression => zstd, compression_level => 5})
    ).

validate_opts_none_test() ->
    ?assertEqual(
        {ok, #{method => none}},
        clickhouse_erl_compression:validate_opts(#{compression => none})
    ).

validate_opts_none_ignores_level_test() ->
    ?assertEqual(
        {ok, #{method => none}},
        clickhouse_erl_compression:validate_opts(#{compression => none, compression_level => 5})
    ).

validate_opts_invalid_method_test() ->
    ?assertEqual(
        {error, {invalid_compression_method, gzip}},
        clickhouse_erl_compression:validate_opts(#{compression => gzip})
    ).

validate_opts_invalid_method_string_test() ->
    ?assertEqual(
        {error, {invalid_compression_method, "lz4"}},
        clickhouse_erl_compression:validate_opts(#{compression => "lz4"})
    ).

validate_opts_not_map_test() ->
    ?assertEqual(
        {error, {invalid_compression_opts, not_a_map}},
        clickhouse_erl_compression:validate_opts(not_a_map)
    ).

validate_opts_not_map_list_test() ->
    ?assertEqual(
        {error, {invalid_compression_opts, not_a_map}},
        clickhouse_erl_compression:validate_opts([{compression, lz4}])
    ).

%%%===================================================================
%%% is_available/1 tests
%%%===================================================================

is_available_disabled_test() ->
    ?assertEqual(true, clickhouse_erl_compression:is_available(disabled)).

is_available_none_test() ->
    ?assertEqual(true, clickhouse_erl_compression:is_available(none)).

is_available_lz4_test() ->
    % Result depends on whether lz4 library is installed
    Result = clickhouse_erl_compression:is_available(lz4),
    ?assert(is_boolean(Result)).

is_available_zstd_test() ->
    % Result depends on whether ezstd library is installed
    Result = clickhouse_erl_compression:is_available(zstd),
    ?assert(is_boolean(Result)).

%%%===================================================================
%%% compress/2 tests
%%%===================================================================

compress_lz4_valid_test() ->
    Data = <<"test data for compression">>,
    Opts = #{method => lz4},
    case clickhouse_erl_compression:is_available(lz4) of
        true ->
            {ok, Block} = clickhouse_erl_compression:compress(Data, Opts),
            % Verify block has 25-byte header + compressed data
            ?assert(byte_size(Block) >= 25),
            % Verify header can be decoded
            <<Header:25/binary, _CompressedData/binary>> = Block,
            {ok, HeaderInfo} = clickhouse_erl_compression:decode_header(Header),
            ?assertEqual(lz4, maps:get(method, HeaderInfo)),
            ?assertEqual(byte_size(Data), maps:get(original_size, HeaderInfo));
        false ->
            % Skip test if LZ4 not available
            ok
    end.

compress_lz4_with_level_test() ->
    Data = <<"test data for LZ4HC compression">>,
    Opts = #{method => lz4, level => 5},
    case clickhouse_erl_compression:is_available(lz4) of
        true ->
            {ok, Block} = clickhouse_erl_compression:compress(Data, Opts),
            ?assert(byte_size(Block) >= 25),
            <<Header:25/binary, _/binary>> = Block,
            {ok, HeaderInfo} = clickhouse_erl_compression:decode_header(Header),
            ?assertEqual(lz4, maps:get(method, HeaderInfo));
        false ->
            ok
    end.

compress_zstd_valid_test() ->
    Data = <<"test data for ZSTD compression">>,
    Opts = #{method => zstd},
    case clickhouse_erl_compression:is_available(zstd) of
        true ->
            {ok, Block} = clickhouse_erl_compression:compress(Data, Opts),
            ?assert(byte_size(Block) >= 25),
            <<Header:25/binary, _/binary>> = Block,
            {ok, HeaderInfo} = clickhouse_erl_compression:decode_header(Header),
            ?assertEqual(zstd, maps:get(method, HeaderInfo)),
            ?assertEqual(byte_size(Data), maps:get(original_size, HeaderInfo));
        false ->
            ok
    end.

compress_none_valid_test() ->
    Data = <<"test data without compression">>,
    Opts = #{method => none},
    {ok, Block} = clickhouse_erl_compression:compress(Data, Opts),
    % Block should be 25 bytes header + original data
    ?assertEqual(25 + byte_size(Data), byte_size(Block)),
    <<Header:25/binary, CompressedData/binary>> = Block,
    {ok, HeaderInfo} = clickhouse_erl_compression:decode_header(Header),
    ?assertEqual(none, maps:get(method, HeaderInfo)),
    ?assertEqual(byte_size(Data), maps:get(original_size, HeaderInfo)),
    ?assertEqual(byte_size(Data), maps:get(compressed_size, HeaderInfo)),
    ?assertEqual(Data, CompressedData).

compress_disabled_method_test() ->
    Data = <<"test">>,
    Opts = #{method => disabled},
    ?assertEqual(
        {error, {compression_disabled, cannot_compress}},
        clickhouse_erl_compression:compress(Data, Opts)
    ).

compress_empty_data_test() ->
    Data = <<>>,
    Opts = #{method => none},
    {ok, Block} = clickhouse_erl_compression:compress(Data, Opts),
    ?assertEqual(25, byte_size(Block)),
    <<Header:25/binary, CompressedData/binary>> = Block,
    {ok, HeaderInfo} = clickhouse_erl_compression:decode_header(Header),
    ?assertEqual(0, maps:get(original_size, HeaderInfo)),
    ?assertEqual(0, maps:get(compressed_size, HeaderInfo)),
    ?assertEqual(<<>>, CompressedData).

compress_large_data_test() ->
    Data = binary:copy(<<"x">>, 10000),
    Opts = #{method => none},
    {ok, Block} = clickhouse_erl_compression:compress(Data, Opts),
    ?assert(byte_size(Block) >= 25),
    <<Header:25/binary, _/binary>> = Block,
    {ok, HeaderInfo} = clickhouse_erl_compression:decode_header(Header),
    ?assertEqual(byte_size(Data), maps:get(original_size, HeaderInfo)).

compress_invalid_opts_not_map_test() ->
    Data = <<"test">>,
    ?assertEqual(
        {error, {invalid_compression_opts, not_a_map}},
        clickhouse_erl_compression:compress(Data, not_a_map)
    ).

compress_invalid_opts_list_test() ->
    Data = <<"test">>,
    ?assertEqual(
        {error, {invalid_compression_opts, not_a_map}},
        clickhouse_erl_compression:compress(Data, [{method, lz4}])
    ).

compress_no_method_defaults_to_disabled_test() ->
    Data = <<"test">>,
    Opts = #{},
    ?assertEqual(
        {error, {compression_disabled, cannot_compress}},
        clickhouse_erl_compression:compress(Data, Opts)
    ).

compress_roundtrip_lz4_test() ->
    Data = <<"roundtrip test data for LZ4">>,
    Opts = #{method => lz4},
    case clickhouse_erl_compression:is_available(lz4) of
        true ->
            {ok, Block} = clickhouse_erl_compression:compress(Data, Opts),
            {ok, Decompressed, _Remaining} = clickhouse_erl_compression:decompress(Block),
            ?assertEqual(Data, Decompressed);
        false ->
            ok
    end.

compress_roundtrip_zstd_test() ->
    Data = <<"roundtrip test data for ZSTD">>,
    Opts = #{method => zstd},
    case clickhouse_erl_compression:is_available(zstd) of
        true ->
            {ok, Block} = clickhouse_erl_compression:compress(Data, Opts),
            {ok, Decompressed, _Remaining} = clickhouse_erl_compression:decompress(Block),
            ?assertEqual(Data, Decompressed);
        false ->
            ok
    end.

compress_roundtrip_none_test() ->
    Data = <<"roundtrip test data without compression">>,
    Opts = #{method => none},
    {ok, Block} = clickhouse_erl_compression:compress(Data, Opts),
    {ok, Decompressed, _Remaining} = clickhouse_erl_compression:decompress(Block),
    ?assertEqual(Data, Decompressed).

%%%===================================================================
%%% compress_none/1 tests
%%%===================================================================

compress_none_empty_test() ->
    ?assertEqual({ok, <<>>}, clickhouse_erl_compression:compress_none(<<>>)).

compress_none_small_data_test() ->
    Data = <<"hello">>,
    ?assertEqual({ok, Data}, clickhouse_erl_compression:compress_none(Data)).

compress_none_large_data_test() ->
    Data = binary:copy(<<"test">>, 1000),
    ?assertEqual({ok, Data}, clickhouse_erl_compression:compress_none(Data)).

%%%===================================================================
%%% decompress_none/2 tests
%%%===================================================================

decompress_none_empty_test() ->
    ?assertEqual({ok, <<>>}, clickhouse_erl_compression:decompress_none(<<>>, 0)).

decompress_none_valid_size_test() ->
    Data = <<"hello">>,
    ?assertEqual({ok, Data}, clickhouse_erl_compression:decompress_none(Data, 5)).

decompress_none_size_mismatch_test() ->
    Data = <<"hello">>,
    ?assertEqual(
        {error, {size_mismatch, #{expected => 10, actual => 5}}},
        clickhouse_erl_compression:decompress_none(Data, 10)
    ).

decompress_none_large_data_test() ->
    Data = binary:copy(<<"test">>, 1000),
    ExpectedSize = byte_size(Data),
    ?assertEqual({ok, Data}, clickhouse_erl_compression:decompress_none(Data, ExpectedSize)).

%%%===================================================================
%%% encode_header/3 tests
%%%===================================================================

encode_header_lz4_test() ->
    % Test encoding header for LZ4 compression
    CompressedData = <<"compressed_data">>,
    OriginalSize = 100,

    % Compute expected checksum
    MethodByte = 16#82,
    CompressedSize = byte_size(CompressedData),
    ChecksumData =
        <<MethodByte:8, (CompressedSize + 9):32/little, OriginalSize:32/little,
            CompressedData/binary>>,
    ExpectedChecksum = clickhouse_erl_cityhash:hash128(ChecksumData),

    % Encode header
    Header = clickhouse_erl_compression:encode_header(CompressedData, OriginalSize, lz4),

    % Verify header structure (25 bytes)
    ?assertEqual(25, byte_size(Header)),

    % Verify header fields
    <<Checksum:16/binary, Method:8, CompSizePlus9:32/little, OrigSize:32/little>> = Header,
    ?assertEqual(ExpectedChecksum, Checksum),
    ?assertEqual(16#82, Method),
    ?assertEqual(CompressedSize + 9, CompSizePlus9),
    ?assertEqual(OriginalSize, OrigSize).

encode_header_zstd_test() ->
    % Test encoding header for ZSTD compression
    CompressedData = <<"zstd_compressed">>,
    OriginalSize = 200,

    % Compute expected checksum
    MethodByte = 16#90,
    CompressedSize = byte_size(CompressedData),
    ChecksumData =
        <<MethodByte:8, (CompressedSize + 9):32/little, OriginalSize:32/little,
            CompressedData/binary>>,
    ExpectedChecksum = clickhouse_erl_cityhash:hash128(ChecksumData),

    % Encode header
    Header = clickhouse_erl_compression:encode_header(CompressedData, OriginalSize, zstd),

    % Verify header structure (25 bytes)
    ?assertEqual(25, byte_size(Header)),

    % Verify header fields
    <<Checksum:16/binary, Method:8, CompSizePlus9:32/little, OrigSize:32/little>> = Header,
    ?assertEqual(ExpectedChecksum, Checksum),
    ?assertEqual(16#90, Method),
    ?assertEqual(CompressedSize + 9, CompSizePlus9),
    ?assertEqual(OriginalSize, OrigSize).

encode_header_none_test() ->
    % Test encoding header for None compression
    CompressedData = <<"uncompressed">>,
    OriginalSize = byte_size(CompressedData),

    % Compute expected checksum
    MethodByte = 16#02,
    CompressedSize = byte_size(CompressedData),
    ChecksumData =
        <<MethodByte:8, (CompressedSize + 9):32/little, OriginalSize:32/little,
            CompressedData/binary>>,
    ExpectedChecksum = clickhouse_erl_cityhash:hash128(ChecksumData),

    % Encode header
    Header = clickhouse_erl_compression:encode_header(CompressedData, OriginalSize, none),

    % Verify header structure (25 bytes)
    ?assertEqual(25, byte_size(Header)),

    % Verify header fields
    <<Checksum:16/binary, Method:8, CompSizePlus9:32/little, OrigSize:32/little>> = Header,
    ?assertEqual(ExpectedChecksum, Checksum),
    ?assertEqual(16#02, Method),
    ?assertEqual(CompressedSize + 9, CompSizePlus9),
    ?assertEqual(OriginalSize, OrigSize).

encode_header_empty_data_test() ->
    % Test encoding header with empty compressed data
    CompressedData = <<>>,
    OriginalSize = 0,

    % Compute expected checksum
    MethodByte = 16#82,
    CompressedSize = 0,
    ChecksumData = <<MethodByte:8, (CompressedSize + 9):32/little, OriginalSize:32/little>>,
    ExpectedChecksum = clickhouse_erl_cityhash:hash128(ChecksumData),

    % Encode header
    Header = clickhouse_erl_compression:encode_header(CompressedData, OriginalSize, lz4),

    % Verify header structure (25 bytes)
    ?assertEqual(25, byte_size(Header)),

    % Verify header fields
    <<Checksum:16/binary, Method:8, CompSizePlus9:32/little, OrigSize:32/little>> = Header,
    ?assertEqual(ExpectedChecksum, Checksum),
    ?assertEqual(16#82, Method),
    ?assertEqual(9, CompSizePlus9),
    ?assertEqual(0, OrigSize).

encode_header_large_data_test() ->
    % Test encoding header with large compressed data
    CompressedData = binary:copy(<<"x">>, 10000),
    OriginalSize = 50000,

    % Compute expected checksum
    MethodByte = 16#82,
    CompressedSize = byte_size(CompressedData),
    ChecksumData =
        <<MethodByte:8, (CompressedSize + 9):32/little, OriginalSize:32/little,
            CompressedData/binary>>,
    ExpectedChecksum = clickhouse_erl_cityhash:hash128(ChecksumData),

    % Encode header
    Header = clickhouse_erl_compression:encode_header(CompressedData, OriginalSize, lz4),

    % Verify header structure (25 bytes)
    ?assertEqual(25, byte_size(Header)),

    % Verify header fields
    <<Checksum:16/binary, Method:8, CompSizePlus9:32/little, OrigSize:32/little>> = Header,
    ?assertEqual(ExpectedChecksum, Checksum),
    ?assertEqual(16#82, Method),
    ?assertEqual(CompressedSize + 9, CompSizePlus9),
    ?assertEqual(OriginalSize, OrigSize).

%%%===================================================================
%%% decode_header/1 tests
%%%===================================================================

decode_header_lz4_test() ->
    % Test decoding header for LZ4 compression
    CompressedData = <<"compressed_data">>,
    OriginalSize = 100,

    % Encode header first
    Header = clickhouse_erl_compression:encode_header(CompressedData, OriginalSize, lz4),

    % Decode header
    {ok, Result} = clickhouse_erl_compression:decode_header(Header),

    % Verify decoded fields
    ?assertEqual(lz4, maps:get(method, Result)),
    ?assertEqual(byte_size(CompressedData), maps:get(compressed_size, Result)),
    ?assertEqual(OriginalSize, maps:get(original_size, Result)),
    ?assert(is_binary(maps:get(checksum, Result))),
    ?assertEqual(16, byte_size(maps:get(checksum, Result))).

decode_header_zstd_test() ->
    % Test decoding header for ZSTD compression
    CompressedData = <<"zstd_compressed">>,
    OriginalSize = 200,

    % Encode header first
    Header = clickhouse_erl_compression:encode_header(CompressedData, OriginalSize, zstd),

    % Decode header
    {ok, Result} = clickhouse_erl_compression:decode_header(Header),

    % Verify decoded fields
    ?assertEqual(zstd, maps:get(method, Result)),
    ?assertEqual(byte_size(CompressedData), maps:get(compressed_size, Result)),
    ?assertEqual(OriginalSize, maps:get(original_size, Result)).

decode_header_none_test() ->
    % Test decoding header for None compression
    CompressedData = <<"uncompressed">>,
    OriginalSize = byte_size(CompressedData),

    % Encode header first
    Header = clickhouse_erl_compression:encode_header(CompressedData, OriginalSize, none),

    % Decode header
    {ok, Result} = clickhouse_erl_compression:decode_header(Header),

    % Verify decoded fields
    ?assertEqual(none, maps:get(method, Result)),
    ?assertEqual(byte_size(CompressedData), maps:get(compressed_size, Result)),
    ?assertEqual(OriginalSize, maps:get(original_size, Result)).

decode_header_empty_data_test() ->
    % Test decoding header with empty compressed data
    CompressedData = <<>>,
    OriginalSize = 0,

    % Encode header first
    Header = clickhouse_erl_compression:encode_header(CompressedData, OriginalSize, lz4),

    % Decode header
    {ok, Result} = clickhouse_erl_compression:decode_header(Header),

    % Verify decoded fields
    ?assertEqual(lz4, maps:get(method, Result)),
    ?assertEqual(0, maps:get(compressed_size, Result)),
    ?assertEqual(0, maps:get(original_size, Result)).

decode_header_invalid_size_too_small_test() ->
    % Test decoding with header too small (24 bytes instead of 25)
    ShortHeader = <<0:128, 16#82:8, 100:32/little, 100:24/little>>,
    ActualSize = byte_size(ShortHeader),
    ?assertEqual(24, ActualSize),
    ?assertEqual(
        {error, {invalid_header_size, ActualSize}},
        clickhouse_erl_compression:decode_header(ShortHeader)
    ).

decode_header_invalid_size_too_large_test() ->
    % Test decoding with header too large (26 bytes instead of 25)
    LargeHeader = <<0:128, 16#82:8, 100:32/little, 100:32/little, 0:8>>,
    ActualSize = byte_size(LargeHeader),
    ?assertEqual(26, ActualSize),
    ?assertEqual(
        {error, {invalid_header_size, ActualSize}},
        clickhouse_erl_compression:decode_header(LargeHeader)
    ).

decode_header_invalid_method_byte_test() ->
    % Test decoding with invalid method byte
    <<_:16/binary, _/binary>> = <<0:128>>,
    InvalidHeader = <<0:128, 16#FF:8, 100:32/little, 100:32/little>>,
    ?assertEqual(
        {error, {invalid_compression_method_byte, 16#FF}},
        clickhouse_erl_compression:decode_header(InvalidHeader)
    ).

decode_header_not_binary_test() ->
    % Test decoding with non-binary input
    ?assertEqual(
        {error, {invalid_header, 123}},
        clickhouse_erl_compression:decode_header(123)
    ).

decode_header_roundtrip_test() ->
    % Test that encode then decode produces consistent results
    CompressedData = <<"test_data_for_compression">>,
    OriginalSize = 500,

    % Encode with each method
    Methods = [lz4, zstd, none],
    lists:foreach(
        fun(Method) ->
            Header = clickhouse_erl_compression:encode_header(CompressedData, OriginalSize, Method),
            {ok, Decoded} = clickhouse_erl_compression:decode_header(Header),

            ?assertEqual(Method, maps:get(method, Decoded)),
            ?assertEqual(byte_size(CompressedData), maps:get(compressed_size, Decoded)),
            ?assertEqual(OriginalSize, maps:get(original_size, Decoded)),
            ?assert(is_binary(maps:get(checksum, Decoded)))
        end,
        Methods
    ).

%%%===================================================================
%%% compress_data_block/2 tests
%%%===================================================================

compress_data_block_with_undefined_opts_test() ->
    Data = <<"test data">>,
    ?assertEqual({ok, Data}, clickhouse_erl_compression:compress_data_block(Data, undefined)).

compress_data_block_with_disabled_compression_test() ->
    Data = <<"test data">>,
    Opts = #{method => disabled},
    ?assertEqual({ok, Data}, clickhouse_erl_compression:compress_data_block(Data, Opts)).

compress_data_block_with_lz4_test() ->
    Data = <<"test data for compression">>,
    Opts = #{method => lz4},
    {ok, Compressed} = clickhouse_erl_compression:compress_data_block(Data, Opts),
    %% Verify it's compressed (has 25-byte header)
    ?assert(byte_size(Compressed) > 25),
    %% Verify it can be decompressed
    {ok, Decompressed, _Remaining} = clickhouse_erl_compression:decompress(Compressed),
    ?assertEqual(Data, Decompressed).

compress_data_block_with_lz4hc_test() ->
    Data = <<"test data for compression with high compression">>,
    Opts = #{method => lz4, level => 9},
    {ok, Compressed} = clickhouse_erl_compression:compress_data_block(Data, Opts),
    %% Verify it's compressed (has 25-byte header)
    ?assert(byte_size(Compressed) > 25),
    %% Verify it can be decompressed
    {ok, Decompressed, _Remaining} = clickhouse_erl_compression:decompress(Compressed),
    ?assertEqual(Data, Decompressed).

compress_data_block_with_zstd_test() ->
    Data = <<"test data for zstd compression">>,
    Opts = #{method => zstd},
    {ok, Compressed} = clickhouse_erl_compression:compress_data_block(Data, Opts),
    %% Verify it's compressed (has 25-byte header)
    ?assert(byte_size(Compressed) > 25),
    %% Verify it can be decompressed
    {ok, Decompressed, _Remaining} = clickhouse_erl_compression:decompress(Compressed),
    ?assertEqual(Data, Decompressed).

compress_data_block_with_none_test() ->
    Data = <<"test data">>,
    Opts = #{method => none},
    {ok, Compressed} = clickhouse_erl_compression:compress_data_block(Data, Opts),
    %% Verify it has 25-byte header even with 'none' method
    ?assert(byte_size(Compressed) > 25),
    %% Verify it can be decompressed
    {ok, Decompressed, _Remaining} = clickhouse_erl_compression:decompress(Compressed),
    ?assertEqual(Data, Decompressed).

compress_data_block_blank_block_with_lz4_test() ->
    %% Simulate a blank data block (empty binary)
    BlankBlock = clickhouse_erl_protocol_data_block:encode_blank_data_block(),
    BlankBlockBinary = iolist_to_binary(BlankBlock),
    Opts = #{method => lz4},
    {ok, Compressed} = clickhouse_erl_compression:compress_data_block(BlankBlockBinary, Opts),
    %% Verify it's compressed (has 25-byte header)
    ?assert(byte_size(Compressed) > 25),
    %% Verify it can be decompressed
    {ok, Decompressed, _Remaining} = clickhouse_erl_compression:decompress(Compressed),
    ?assertEqual(BlankBlockBinary, Decompressed).

compress_data_block_blank_block_with_zstd_test() ->
    %% Simulate a blank data block (empty binary)
    BlankBlock = clickhouse_erl_protocol_data_block:encode_blank_data_block(),
    BlankBlockBinary = iolist_to_binary(BlankBlock),
    Opts = #{method => zstd},
    {ok, Compressed} = clickhouse_erl_compression:compress_data_block(BlankBlockBinary, Opts),
    %% Verify it's compressed (has 25-byte header)
    ?assert(byte_size(Compressed) > 25),
    %% Verify it can be decompressed
    {ok, Decompressed, _Remaining} = clickhouse_erl_compression:decompress(Compressed),
    ?assertEqual(BlankBlockBinary, Decompressed).

compress_data_block_blank_block_disabled_test() ->
    %% Simulate a blank data block with compression disabled
    BlankBlock = clickhouse_erl_protocol_data_block:encode_blank_data_block(),
    BlankBlockBinary = iolist_to_binary(BlankBlock),
    Opts = #{method => disabled},
    {ok, Result} = clickhouse_erl_compression:compress_data_block(BlankBlockBinary, Opts),
    %% Should return unchanged
    ?assertEqual(BlankBlockBinary, Result).
