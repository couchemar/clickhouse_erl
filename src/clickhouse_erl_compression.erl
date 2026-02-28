%% @doc Compression engine for ClickHouse native protocol.
%%
%% This module provides compression and decompression functionality for the ClickHouse
%% native binary protocol. It supports multiple compression methods (LZ4, ZSTD, None)
%% with automatic checksum verification using CityHash128.
%%
%% == Supported Compression Methods ==
%%
%% - **LZ4**: Fast compression with good compression ratios (recommended for most use cases)
%% - **LZ4HC**: High compression variant with configurable levels 0-12
%% - **ZSTD**: Better compression ratios at the cost of speed
%% - **None**: Uncompressed data with compression protocol wrapper
%% - **Disabled**: No compression (default for backward compatibility)
%%
%% == Usage Examples ==
%%
%% === Basic Compression ===
%%
%% ```
%% % Compress with LZ4
%% Data = <<"Hello, ClickHouse!">>,
%% {ok, Compressed} = clickhouse_erl_compression:compress(Data, #{method => lz4}).
%%
%% % Decompress
%% {ok, Decompressed, _Remaining} = clickhouse_erl_compression:decompress(Compressed).
%% Data = Decompressed.  % Verify round-trip
%% '''
%%
%% === LZ4HC with Compression Level ===
%%
%% ```
%% % Use LZ4HC with level 9 for better compression
%% {ok, Compressed} = clickhouse_erl_compression:compress(Data, #{
%%     method => lz4,
%%     level => 9
%% }).
%% '''
%%
%% === ZSTD Compression ===
%%
%% ```
%% % Use ZSTD for maximum compression
%% {ok, Compressed} = clickhouse_erl_compression:compress(Data, #{method => zstd}).
%% '''
%%
%% === Checking Library Availability ===
%%
%% ```
%% case clickhouse_erl_compression:is_available(lz4) of
%%     true -> io:format("LZ4 available~n");
%%     false -> io:format("LZ4 not available - install lz4 library~n")
%% end.
%% '''
%%
%% == Compressed Block Format ==
%%
%% Compressed blocks consist of a 25-byte header followed by compressed data:
%%
%% ```
%% +------------------+------------------+---------------------------+
%% | Checksum (16B)   | Method (1B)      | Compressed Size+9 (4B)   |
%% +------------------+------------------+---------------------------+
%% | Original Size (4B) | Compressed Data (variable)                |
%% +--------------------+-----------------------------------------------+
%% '''
%%
%% - **Checksum**: CityHash128 of (method_byte + sizes + compressed_data)
%% - **Method byte**: 0x82=LZ4, 0x90=ZSTD, 0x02=None
%% - **Compressed size + 9**: Little-endian uint32
%% - **Original size**: Little-endian uint32
%%
%% == Error Handling ==
%%
%% All functions return `{ok, Result}' or `{error, Reason}' tuples:
%%
%% ```
%% case clickhouse_erl_compression:compress(Data, Opts) of
%%     {ok, Compressed} ->
%%         process_compressed(Compressed);
%%     {error, {compression_failed, Reason}} ->
%%         handle_compression_error(Reason);
%%     {error, {compression_library_missing, Method}} ->
%%         install_library(Method)
%% end.
%% '''
%%
%% Common error types:
%% - `{compression_failed, Reason}' - Compression operation failed
%% - `{decompression_failed, Reason}' - Decompression operation failed
%% - `{checksum_mismatch, Details}' - Data corruption detected
%% - `{size_mismatch, Details}' - Decompressed size doesn't match expected
%% - `{compression_library_missing, Method}' - Required library not installed
%%
%% == Integration with Connection Layer ==
%%
%% This module is used internally by the connection layer to compress/decompress
%% data blocks when compression is enabled:
%%
%% ```
%% % Connection with compression enabled
%% {ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{compression => lz4}).
%%
%% % All queries automatically use compression
%% {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM large_table">>).
%% '''
%%
%% == Performance Considerations ==
%%
%% - **LZ4**: Very fast, low CPU usage, good compression (2-3x typical)
%% - **LZ4HC**: Slower compression, same decompression speed, better ratios (3-5x)
%% - **ZSTD**: Medium speed, higher CPU usage, best compression (3-5x)
%% - **Threshold**: Don't compress blocks smaller than 1KB (overhead not worth it)
%%
%% @see clickhouse_erl_cityhash
%% @see clickhouse_erl_connection
-module(clickhouse_erl_compression).

%% API exports
-export([
    compress/2,
    decompress/1,
    validate_opts/1,
    is_available/1,
    compress_lz4/2,
    decompress_lz4/2,
    compress_zstd/1,
    decompress_zstd/2,
    compress_none/1,
    decompress_none/2,
    encode_header/3,
    decode_header/1,
    compress_data_block/2
]).

%% Includes
-include_lib("kernel/include/logger.hrl").

%% Type definitions and exports
-export_type([compression_method/0, compression_opts/0]).

-type compression_method() :: lz4 | zstd | none | disabled.
-type compression_opts() :: #{
    method => compression_method(),
    % Only for LZ4HC
    level => 0..12
}.

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Compress data with specified method and return complete compressed block.
%%
%% The compressed block consists of a 25-byte header followed by compressed data.
%%
%% Header format:
%% - Checksum: 16 bytes (CityHash128 of method_byte + sizes + compressed_data)
%% - Method byte: 1 byte (0x82=LZ4, 0x90=ZSTD, 0x02=None)
%% - Compressed size + 9: 4 bytes little-endian uint32
%% - Original size: 4 bytes little-endian uint32
%%
%% The Opts parameter must be a map with a `method' field:
%% - `#{method => lz4}' - Use standard LZ4 compression (fast)
%% - `#{method => lz4, level => 0..12}' - Use LZ4HC with compression level
%% - `#{method => zstd}' - Use ZSTD compression (better ratio)
%% - `#{method => none}' - No compression (passthrough with header)
%% - `#{method => disabled}' - Returns error (compression disabled)
%%
%% Examples:
%% ```
%% % Compress with LZ4
%% {ok, Block} = compress(<<"data">>, #{method => lz4}).
%%
%% % Compress with LZ4HC level 5
%% {ok, Block} = compress(<<"data">>, #{method => lz4, level => 5}).
%%
%% % Compress with ZSTD
%% {ok, Block} = compress(<<"data">>, #{method => zstd}).
%%
%% % No compression
%% {ok, Block} = compress(<<"data">>, #{method => none}).
%% '''
%%
%% Error cases:
%% - `{error, {compression_disabled, cannot_compress}}' - Method is disabled
%% - `{error, {invalid_compression_opts, not_a_map}}' - Opts is not a map
%% - `{error, {compression_failed, Reason}}' - Compression library error
-spec compress(binary(), compression_opts()) -> {ok, binary()} | {error, term()}.
compress(Data, Opts) when is_binary(Data), is_map(Opts) ->
    case maps:get(method, Opts, disabled) of
        disabled ->
            {error, {compression_disabled, cannot_compress}};
        Method ->
            compress_with_method(Data, Method, Opts)
    end;
compress(_Data, _Opts) ->
    {error, {invalid_compression_opts, not_a_map}}.

%% @doc Decompress a complete compressed block.
%% Validates checksum before decompressing and returns error if checksum
%% doesn't match. Returns {ok, Decompressed, Remaining} where Remaining
%% is any unparsed bytes after the compressed block.
-spec decompress(binary()) -> {ok, binary(), binary()} | {error, term()}.
decompress(CompressedBlock) when is_binary(CompressedBlock) ->
    case byte_size(CompressedBlock) of
        Size when Size < 25 ->
            {error, {invalid_compressed_block, too_small}};
        _ ->
            decompress_block(CompressedBlock)
    end;
decompress(_NotBinary) ->
    {error, {invalid_compressed_block, not_a_binary}}.

%% @doc Compress a data block for CLIENT_DATA packets.
%%
%% This function handles compression of data blocks (including blank blocks) that are
%% sent in CLIENT_DATA packets. When compression is enabled, it applies the compression
%% wrapper (25-byte header + compressed data). When compression is disabled, it returns
%% the data unchanged.
%%
%% CRITICAL: Even blank blocks (0 rows/columns) need the compression wrapper when
%% compression is enabled. The server expects ALL data blocks to be compressed when
%% the query packet indicates compression=1.
%%
%% Examples:
%% ```
%% % Compress blank block with LZ4
%% BlankBlock = clickhouse_erl_protocol_data_block:encode_blank_data_block(),
%% {ok, Compressed} = compress_data_block(BlankBlock, #{method => lz4}).
%%
%% % No compression (disabled)
%% {ok, Uncompressed} = compress_data_block(BlankBlock, #{method => disabled}).
%% '''
%%
%% @param DataBlock Binary data block to compress (can be blank block or data block)
%% @param CompressionOpts Compression options map with method field
%% @returns {ok, CompressedBlock} or {error, Reason}
-spec compress_data_block(binary(), compression_opts() | undefined) ->
    {ok, binary()} | {error, term()}.
compress_data_block(DataBlock, undefined) ->
    % No compression options - return data unchanged
    {ok, DataBlock};
compress_data_block(DataBlock, CompressionOpts) when is_map(CompressionOpts) ->
    case maps:get(method, CompressionOpts, disabled) of
        disabled ->
            % Compression disabled - return data unchanged
            {ok, DataBlock};
        _Method ->
            % Compression enabled - apply compression wrapper
            compress(DataBlock, CompressionOpts)
    end.

%% @doc Compress data with specified method.
-spec compress_with_method(binary(), compression_method(), compression_opts()) ->
    {ok, binary()} | {error, term()}.
compress_with_method(Data, lz4, Opts) ->
    Level = maps:get(level, Opts, undefined),
    case compress_lz4(Data, Level) of
        {ok, CompressedData} ->
            CompressedBlock = build_compressed_block(CompressedData, byte_size(Data), lz4),
            {ok, CompressedBlock};
        {error, Reason} ->
            {error, {compression_failed, Reason}}
    end;
compress_with_method(Data, zstd, _Opts) ->
    case compress_zstd(Data) of
        {ok, CompressedData} ->
            CompressedBlock = build_compressed_block(CompressedData, byte_size(Data), zstd),
            {ok, CompressedBlock};
        {error, Reason} ->
            {error, {compression_failed, Reason}}
    end;
compress_with_method(Data, none, _Opts) ->
    {ok, CompressedData} = compress_none(Data),
    CompressedBlock = build_compressed_block(CompressedData, byte_size(Data), none),
    {ok, CompressedBlock}.

%% @doc Build complete compressed block with header and data.
-spec build_compressed_block(binary(), non_neg_integer(), compression_method()) -> binary().
build_compressed_block(CompressedData, OriginalSize, Method) ->
    Header = encode_header(CompressedData, OriginalSize, Method),
    <<Header/binary, CompressedData/binary>>.

%% @doc Decompress a complete compressed block.
%% Returns {ok, Decompressed, Remaining} where Remaining is any unparsed
%% bytes after the compressed block.
-spec decompress_block(binary()) -> {ok, binary(), binary()} | {error, term()}.
decompress_block(CompressedBlock) ->
    <<Header:25/binary, Rest/binary>> = CompressedBlock,
    case decode_header(Header) of
        {ok, HeaderInfo} ->
            Checksum = maps:get(checksum, HeaderInfo),
            Method = maps:get(method, HeaderInfo),
            CompressedSize = maps:get(compressed_size, HeaderInfo),
            OriginalSize = maps:get(original_size, HeaderInfo),

            % Check if we have enough data
            ActualAvailable = byte_size(Rest),
            case ActualAvailable >= CompressedSize of
                true ->
                    % Extract exactly CompressedSize bytes for decompression
                    <<CompressedData:CompressedSize/binary, Remaining/binary>> = Rest,
                    % Verify checksum before decompressing
                    case
                        verify_checksum_and_decompress(
                            CompressedData, OriginalSize, Method, Checksum
                        )
                    of
                        {ok, Decompressed} ->
                            {ok, Decompressed, Remaining};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                false ->
                    % Not enough data yet - this is incomplete, not an error
                    ?LOG_DEBUG(
                        "Incomplete compressed block: expected ~p bytes, "
                        "available ~p bytes, need ~p more",
                        [CompressedSize, ActualAvailable, CompressedSize - ActualAvailable]
                    ),
                    {error,
                        {truncated_data, #{expected => CompressedSize, actual => ActualAvailable}}}
            end;
        {error, Reason} ->
            {error, {decode_header_failed, Reason}}
    end.

%% @doc Verify checksum and decompress data.
-spec verify_checksum_and_decompress(binary(), non_neg_integer(), compression_method(), binary()) ->
    {ok, binary()} | {error, term()}.
verify_checksum_and_decompress(CompressedData, OriginalSize, Method, ExpectedChecksum) ->
    % Build checksum data: method_byte + compressed_size + original_size + compressed_data
    MethodByte = method_byte(Method),
    CompressedSize = byte_size(CompressedData),
    ChecksumData =
        <<MethodByte:8, (CompressedSize + 9):32/little, OriginalSize:32/little,
            CompressedData/binary>>,

    % Compute actual checksum
    ActualChecksum = clickhouse_erl_cityhash:hash128(ChecksumData),

    % Verify checksum
    case ActualChecksum =:= ExpectedChecksum of
        true ->
            decompress_data(CompressedData, OriginalSize, Method);
        false ->
            ?LOG_ERROR(
                "Checksum mismatch during decompression: expected=~p, "
                "actual=~p, method=~p, original_size=~p",
                [ExpectedChecksum, ActualChecksum, Method, OriginalSize]
            ),
            {error, {checksum_mismatch, #{expected => ExpectedChecksum, actual => ActualChecksum}}}
    end.

%% @doc Decompress data using specified method.
-spec decompress_data(binary(), non_neg_integer(), compression_method()) ->
    {ok, binary()} | {error, term()}.
decompress_data(CompressedData, OriginalSize, lz4) ->
    case decompress_lz4(CompressedData, OriginalSize) of
        {ok, Data} -> {ok, Data};
        {error, Reason} -> {error, {decompression_failed, Reason}}
    end;
decompress_data(CompressedData, OriginalSize, zstd) ->
    case decompress_zstd(CompressedData, OriginalSize) of
        {ok, Data} -> {ok, Data};
        {error, Reason} -> {error, {decompression_failed, Reason}}
    end;
decompress_data(CompressedData, OriginalSize, none) ->
    case decompress_none(CompressedData, OriginalSize) of
        {ok, Data} -> {ok, Data};
        {error, Reason} -> {error, {decompression_failed, Reason}}
    end.

%% @doc Validate compression options.
%% Returns normalized compression options or error tuple.
-spec validate_opts(map()) -> {ok, compression_opts()} | {error, term()}.
validate_opts(Opts) when is_map(Opts) ->
    case maps:get(compression, Opts, disabled) of
        disabled ->
            {ok, #{method => disabled}};
        Method when Method =:= lz4; Method =:= zstd; Method =:= none ->
            validate_method_opts(Method, Opts);
        InvalidMethod ->
            {error, {invalid_compression_method, InvalidMethod}}
    end;
validate_opts(_) ->
    {error, {invalid_compression_opts, not_a_map}}.

%% @doc Check if compression method is available.
%% Returns true if the required library is loaded, false otherwise.
-spec is_available(compression_method()) -> boolean().
is_available(disabled) ->
    true;
is_available(none) ->
    true;
is_available(lz4) ->
    case code:ensure_loaded(clickhouse_erl_lz4_nif) of
        {module, clickhouse_erl_lz4_nif} -> true;
        _ -> false
    end;
is_available(zstd) ->
    case code:ensure_loaded(ezstd) of
        {module, ezstd} -> true;
        _ -> false
    end.

%% @doc Compress data using LZ4 or LZ4HC.
%% Level parameter: undefined for standard LZ4, 0-12 for LZ4HC.
-spec compress_lz4(binary(), undefined | 0..12) -> {ok, binary()} | {error, term()}.
compress_lz4(<<>>, _Level) ->
    % Empty data - return as-is without compression
    {ok, <<>>};
compress_lz4(Data, undefined) ->
    % Standard LZ4 (fast mode)
    try
        clickhouse_erl_lz4_nif:compress(Data)
    catch
        error:Reason ->
            ?LOG_ERROR(
                "LZ4 compression failed: reason=~p, data_size=~p",
                [Reason, byte_size(Data)]
            ),
            {error, {compression_failed, Reason}};
        Class:Reason ->
            ?LOG_ERROR("LZ4 compression failed: class=~p, reason=~p", [Class, Reason]),
            {error, {compression_failed, Reason}}
    end;
compress_lz4(Data, Level) when is_integer(Level), Level >= 0, Level =< 12 ->
    % LZ4HC with compression level
    try
        clickhouse_erl_lz4_nif:compress_hc(Data, Level)
    catch
        error:Reason ->
            ?LOG_ERROR(
                "LZ4HC compression failed: reason=~p, level=~p, data_size=~p",
                [Reason, Level, byte_size(Data)]
            ),
            {error, {compression_failed, Reason}};
        Class:Reason ->
            ?LOG_ERROR(
                "LZ4HC compression failed: class=~p, reason=~p, level=~p",
                [Class, Reason, Level]
            ),
            {error, {compression_failed, Reason}}
    end.

%% @doc Decompress LZ4 compressed data with size validation.
%% OriginalSize is the expected size after decompression.
-spec decompress_lz4(binary(), pos_integer()) -> {ok, binary()} | {error, term()}.
decompress_lz4(<<>>, 0) ->
    % Empty compressed data with size 0 - return empty binary
    {ok, <<>>};
decompress_lz4(CompressedData, OriginalSize) ->
    try
        case clickhouse_erl_lz4_nif:decompress(CompressedData, OriginalSize) of
            {ok, Decompressed} ->
                ActualSize = byte_size(Decompressed),
                case ActualSize =:= OriginalSize of
                    true ->
                        {ok, Decompressed};
                    false ->
                        ?LOG_ERROR(
                            "LZ4 decompression size mismatch: expected=~p, actual=~p",
                            [OriginalSize, ActualSize]
                        ),
                        {error, {size_mismatch, #{expected => OriginalSize, actual => ActualSize}}}
                end;
            {error, NifReason} ->
                log_decompression_error(lz4, NifReason, CompressedData, OriginalSize)
        end
    catch
        error:CatchReason ->
            log_decompression_error(lz4, CatchReason, CompressedData, OriginalSize);
        CatchClass:CatchReason2 ->
            ?LOG_ERROR("LZ4 decompression failed: class=~p, reason=~p", [CatchClass, CatchReason2]),
            {error, {decompression_failed, CatchReason2}}
    end.

%% @doc Compress data using ZSTD.
%% Uses default ZSTD compression level.
-spec compress_zstd(binary()) -> {ok, binary()} | {error, term()}.
compress_zstd(<<>>) ->
    % Empty data - return as-is without compression
    {ok, <<>>};
compress_zstd(Data) ->
    try
        case ezstd:compress(Data) of
            Compressed when is_binary(Compressed) ->
                {ok, Compressed};
            {error, Reason} ->
                ?LOG_ERROR(
                    "ZSTD compression failed: reason=~p, data_size=~p",
                    [Reason, byte_size(Data)]
                ),
                {error, {compression_failed, Reason}}
        end
    catch
        error:CatchReason ->
            ?LOG_ERROR(
                "ZSTD compression failed: reason=~p, data_size=~p",
                [CatchReason, byte_size(Data)]
            ),
            {error, {compression_failed, CatchReason}};
        CatchClass:CatchReason2 ->
            ?LOG_ERROR(
                "ZSTD compression failed: class=~p, reason=~p",
                [CatchClass, CatchReason2]
            ),
            {error, {compression_failed, CatchReason2}}
    end.

%% @doc Decompress ZSTD compressed data with size validation.
%% OriginalSize is the expected size after decompression.
-spec decompress_zstd(binary(), pos_integer()) -> {ok, binary()} | {error, term()}.
decompress_zstd(<<>>, 0) ->
    % Empty compressed data with size 0 - return empty binary
    {ok, <<>>};
decompress_zstd(CompressedData, OriginalSize) ->
    try
        case ezstd:decompress(CompressedData) of
            Decompressed when is_binary(Decompressed) ->
                ActualSize = byte_size(Decompressed),
                case ActualSize =:= OriginalSize of
                    true ->
                        {ok, Decompressed};
                    false ->
                        ?LOG_ERROR(
                            "ZSTD decompression size mismatch: expected=~p, "
                            "actual=~p",
                            [OriginalSize, ActualSize]
                        ),
                        {error, {size_mismatch, #{expected => OriginalSize, actual => ActualSize}}}
                end;
            {error, Reason} ->
                log_decompression_error(zstd, Reason, CompressedData, OriginalSize)
        end
    catch
        error:CatchReason ->
            log_decompression_error(zstd, CatchReason, CompressedData, OriginalSize);
        CatchClass:CatchReason2 ->
            ?LOG_ERROR(
                "ZSTD decompression failed: class=~p, reason=~p",
                [CatchClass, CatchReason2]
            ),
            {error, {decompression_failed, CatchReason2}}
    end.

%% @doc Encode compressed block header (25 bytes).
%% Creates header with checksum, method byte, compressed size + 9, and original size.
%% Header format (ch-go compatible):
%% - Bytes 0-15: checksum (16 bytes)
%% - Byte 16: method byte
%% - Bytes 17-20: compressed size + 9 (4 bytes little-endian) - rawSize in ch-go
%% - Bytes 21-24: original size (4 bytes little-endian) - dataSize in ch-go
%% Checksum is computed over (method_byte + compressed_size_bytes +
%% original_size_bytes + compressed_data).
-spec encode_header(binary(), non_neg_integer(), compression_method()) -> binary().
encode_header(CompressedData, OriginalSize, Method) ->
    % Get method byte
    MethodByte = method_byte(Method),

    % Calculate compressed size
    CompressedSize = byte_size(CompressedData),

    % Build checksum data: method_byte + compressed_size + original_size + compressed_data
    ChecksumData =
        <<MethodByte:8, (CompressedSize + 9):32/little, OriginalSize:32/little,
            CompressedData/binary>>,

    % Compute CityHash128 checksum
    Checksum = clickhouse_erl_cityhash:hash128(ChecksumData),

    % Build 25-byte header: checksum (16 bytes) + method (1 byte) +
    % compressed_size+9 (4 bytes) + original_size (4 bytes)
    <<Checksum/binary, MethodByte:8, (CompressedSize + 9):32/little, OriginalSize:32/little>>.

%% @doc Decode compressed block header (25 bytes).
%% Parses header and extracts checksum, method byte, compressed size + 9, and original size.
%% Returns map with extracted values or error tuple for invalid header.
-spec decode_header(binary()) ->
    {ok, #{
        checksum => binary(),
        method => compression_method(),
        compressed_size => non_neg_integer(),
        original_size => non_neg_integer()
    }}
    | {error, term()}.
decode_header(Header) when byte_size(Header) =:= 25 ->
    <<Checksum:16/binary, MethodByte:8, CompressedSizePlus9:32/little, OriginalSize:32/little>> =
        Header,
    case method_from_byte(MethodByte) of
        {ok, Method} ->
            ?LOG_DEBUG(
                "Decoding compression header: method=~p (byte=~p), "
                "compressed_size=~p, original_size=~p",
                [
                    Method, MethodByte, CompressedSizePlus9 - 9, OriginalSize
                ]
            ),
            {ok, #{
                checksum => Checksum,
                method => Method,
                compressed_size => CompressedSizePlus9 - 9,
                original_size => OriginalSize
            }};
        {error, _} ->
            ?LOG_ERROR("Invalid compression method byte in header: ~p", [MethodByte]),
            {error, {invalid_compression_method_byte, MethodByte}}
    end;
decode_header(Header) when is_binary(Header) ->
    ?LOG_ERROR("Invalid compressed block header size: expected=25, actual=~p", [byte_size(Header)]),
    {error, {invalid_header_size, byte_size(Header)}};
decode_header(NotBinary) ->
    {error, {invalid_header, NotBinary}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Get compression method byte for protocol encoding.
-spec method_byte(compression_method()) -> byte().
method_byte(lz4) -> 16#82;
method_byte(zstd) -> 16#90;
method_byte(none) -> 16#02.

%% @doc Convert method byte to compression method atom.
-spec method_from_byte(byte()) -> {ok, compression_method()} | {error, term()}.
method_from_byte(16#82) -> {ok, lz4};
method_from_byte(16#90) -> {ok, zstd};
method_from_byte(16#02) -> {ok, none};
method_from_byte(Byte) -> {error, {unknown_method_byte, Byte}}.

%% @doc Validate method-specific options.
-spec validate_method_opts(compression_method(), map()) ->
    {ok, compression_opts()} | {error, term()}.
validate_method_opts(lz4, Opts) ->
    case maps:get(compression_level, Opts, undefined) of
        undefined ->
            {ok, #{method => lz4}};
        Level when is_integer(Level), Level >= 0, Level =< 12 ->
            {ok, #{method => lz4, level => Level}};
        Level ->
            {error, {invalid_compression_level, Level}}
    end;
validate_method_opts(Method, Opts) when Method =:= zstd; Method =:= none ->
    % ZSTD and None don't support compression_level
    case maps:is_key(compression_level, Opts) of
        true ->
            ?LOG_WARNING("Compression level ignored for method", #{method => Method}),
            {ok, #{method => Method}};
        false ->
            {ok, #{method => Method}}
    end.

%% @doc Log decompression error and return error tuple
-spec log_decompression_error(atom(), term(), binary(), non_neg_integer()) ->
    {error, {decompression_failed, term()}}.
log_decompression_error(Method, Reason, CompressedData, OriginalSize) ->
    MethodStr = atom_to_list(Method),
    ?LOG_ERROR(
        MethodStr ++ " decompression failed: reason=~p, compressed_size=~p, expected_size=~p",
        [Reason, byte_size(CompressedData), OriginalSize]
    ),
    {error, {decompression_failed, Reason}}.

%% @doc Passthrough compression (no actual compression).
%% Returns the data unchanged. Used with method byte 0x02.
-spec compress_none(binary()) -> {ok, binary()}.
compress_none(Data) ->
    {ok, Data}.

%% @doc Passthrough decompression (no actual decompression).
%% Validates that the data size matches the expected original size.
-spec decompress_none(binary(), non_neg_integer()) -> {ok, binary()} | {error, term()}.
decompress_none(Data, OriginalSize) ->
    ActualSize = byte_size(Data),
    case ActualSize =:= OriginalSize of
        true ->
            {ok, Data};
        false ->
            ?LOG_ERROR("None decompression size mismatch", #{
                expected => OriginalSize,
                actual => ActualSize
            }),
            {error, {size_mismatch, #{expected => OriginalSize, actual => ActualSize}}}
    end.
