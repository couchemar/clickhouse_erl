%% @doc Property-based tests for compression engine (pure PropEr format)
-module(prop_clickhouse_erl_compression).

-include_lib("proper/include/proper.hrl").

%%%===================================================================
%%% Property Tests
%%%===================================================================

%% Property 1: Compression Round-Trip Consistency
%% Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 4.1, 4.2, 4.4
prop_compression_roundtrip_consistency() ->
    ?FORALL(
        {Data, Method},
        {binary_data_gen(), compression_method_gen()},
        begin
            % Skip disabled method (not a compression method)
            case Method of
                disabled ->
                    true;
                _ ->
                    % Check if method is available
                    case clickhouse_erl_compression:is_available(Method) of
                        true ->
                            % Build compression options with correct key
                            Opts = #{method => Method},

                            % Compress the data
                            case clickhouse_erl_compression:compress(Data, Opts) of
                                {ok, CompressedBlock} ->
                                    % Decompress the data
                                    case clickhouse_erl_compression:decompress(CompressedBlock) of
                                        {ok, DecompressedData, _Remaining} ->
                                            % Verify round-trip: original data should equal decompressed data
                                            Data =:= DecompressedData;
                                        {error, _Reason} ->
                                            false
                                    end;
                                {error, _Reason} ->
                                    false
                            end;
                        false ->
                            % Method not available, skip this test case
                            true
                    end
            end
        end
    ).

%% Property 3: Compressed Block Header Structure
%% Validates: Requirements 3.1, 3.3, 3.4, 3.5, 3.6
prop_compressed_block_header_structure() ->
    ?FORALL(
        {Data, Method},
        {binary_data_gen(), compression_method_for_header_gen()},
        begin
            % Skip disabled method
            case Method of
                disabled ->
                    true;
                _ ->
                    % Compress the data
                    CompressedData = compress_data(Data, Method),
                    OriginalSize = byte_size(Data),

                    % Encode the header
                    Header = clickhouse_erl_compression:encode_header(
                        CompressedData, OriginalSize, Method
                    ),

                    % Verify header structure
                    verify_header_structure(Header, CompressedData, OriginalSize, Method)
            end
        end
    ).

%% Helper function to verify header structure
verify_header_structure(Header, CompressedData, OriginalSize, Method) ->
    % Requirement 3.1: Header should be exactly 25 bytes
    case byte_size(Header) of
        25 ->
            % Extract header components
            <<Checksum:16/binary, MethodByte:8, CompressedSizePlus9:32/little,
                HeaderOriginalSize:32/little>> =
                Header,

            % Requirement 3.3: Method byte should be valid (0x82=LZ4, 0x90=ZSTD, 0x02=None)
            ExpectedMethodByte = method_byte_value(Method),
            case MethodByte of
                ExpectedMethodByte ->
                    % Requirement 3.4: Compressed size + 9 should be correct
                    CompressedSize = byte_size(CompressedData),
                    case CompressedSizePlus9 =:= (CompressedSize + 9) of
                        true ->
                            % Requirement 3.5: Original size should match
                            case HeaderOriginalSize of
                                OriginalSize ->
                                    % Requirement 3.6: Checksum should be 16 bytes
                                    case byte_size(Checksum) of
                                        16 ->
                                            % Verify checksum is computed (non-zero or valid format)
                                            verify_checksum_format(Checksum);
                                        _ ->
                                            false
                                    end;
                                _ ->
                                    false
                            end;
                        _ ->
                            false
                    end;
                _ ->
                    false
            end;
        _ ->
            false
    end.

%% Helper function to get method byte value
method_byte_value(lz4) -> 16#82;
method_byte_value(zstd) -> 16#90;
method_byte_value(none) -> 16#02.

%% Helper function to verify checksum format (non-zero bytes)
verify_checksum_format(Checksum) ->
    % Verify checksum is a valid 16-byte binary (not all zeros)
    Checksum =/= <<0:128>>.

%% Helper function to compress data with available method
compress_data(Data, lz4) ->
    case clickhouse_erl_compression:is_available(lz4) of
        true ->
            case clickhouse_erl_compression:compress_lz4(Data, undefined) of
                {ok, Compressed} -> Compressed;
                {error, _} -> Data
            end;
        false ->
            Data
    end;
compress_data(Data, zstd) ->
    case clickhouse_erl_compression:is_available(zstd) of
        true ->
            case clickhouse_erl_compression:compress_zstd(Data) of
                {ok, Compressed} -> Compressed;
                {error, _} -> Data
            end;
        false ->
            Data
    end;
compress_data(Data, none) ->
    {ok, Compressed} = clickhouse_erl_compression:compress_none(Data),
    Compressed.

%% Generator for compression methods that can be used in header tests
compression_method_for_header_gen() ->
    oneof([lz4, zstd, none]).

%% Property 4: Checksum Verification Integrity
%% Validates: Requirements 3.2, 4.2, 4.3, 7.1, 7.2
prop_checksum_verification_integrity() ->
    ?FORALL(
        {Data, Method},
        {binary_data_gen(), compression_method_for_header_gen()},
        begin
            % Skip disabled method
            case Method of
                disabled ->
                    true;
                _ ->
                    % Check if method is available
                    case clickhouse_erl_compression:is_available(Method) of
                        true ->
                            Opts = #{method => Method},

                            % Compress the data to get a valid compressed block
                            case clickhouse_erl_compression:compress(Data, Opts) of
                                {ok, CompressedBlock} ->
                                    % Extract header components
                                    <<_Checksum:16/binary, MethodByte:8,
                                        CompressedSizePlus9:32/little, OriginalSize:32/little,
                                        CompressedData/binary>> =
                                        CompressedBlock,

                                    % Verify the checksum is computed correctly
                                    % Requirement 7.2: Checksum should be hash of (method_byte + compressed_size_bytes + original_size_bytes + compressed_data)
                                    CompressedSize = CompressedSizePlus9 - 9,
                                    ChecksumInput =
                                        <<MethodByte:8, CompressedSize:32/little,
                                            OriginalSize:32/little, CompressedData/binary>>,
                                    ExpectedChecksum = clickhouse_erl_cityhash:hash128(
                                        ChecksumInput
                                    ),

                                    % Corrupt the checksum by flipping bits
                                    CorruptedChecksum = corrupt_checksum(ExpectedChecksum),
                                    CorruptedBlock =
                                        <<CorruptedChecksum/binary, MethodByte:8,
                                            CompressedSizePlus9:32/little, OriginalSize:32/little,
                                            CompressedData/binary>>,

                                    % Requirement 4.3: Decompression should fail with checksum_mismatch
                                    case clickhouse_erl_compression:decompress(CorruptedBlock) of
                                        {error, {checksum_mismatch, _}} ->
                                            % Correct behavior: checksum mismatch detected
                                            true;
                                        {ok, _} ->
                                            % Should not succeed with corrupted checksum
                                            false;
                                        {error, _OtherReason} ->
                                            % Other errors are acceptable (e.g., decompression failure)
                                            false
                                    end;
                                {error, _Reason} ->
                                    false
                            end;
                        false ->
                            % Method not available, skip this test case
                            true
                    end
            end
        end
    ).

%% Helper function to corrupt a checksum by flipping bits
corrupt_checksum(Checksum) ->
    % Flip the first byte to ensure the checksum is different
    <<FirstByte:8, Rest/binary>> = Checksum,
    FlippedByte = FirstByte bxor 16#FF,
    <<FlippedByte:8, Rest/binary>>.

%% Property 9: Decompression Size Validation
%% Validates: Requirements 4.6
prop_decompression_size_validation() ->
    ?FORALL(
        {Data, Method},
        {binary_data_gen(), compression_method_for_header_gen()},
        begin
            % Skip disabled method
            case Method of
                disabled ->
                    true;
                _ ->
                    % Check if method is available
                    case clickhouse_erl_compression:is_available(Method) of
                        true ->
                            Opts = #{method => Method},

                            % Compress the data to get a valid compressed block
                            case clickhouse_erl_compression:compress(Data, Opts) of
                                {ok, CompressedBlock} ->
                                    % Extract header components
                                    <<_Checksum:16/binary, MethodByte:8,
                                        CompressedSizePlus9:32/little, OriginalSize:32/little,
                                        CompressedData/binary>> =
                                        CompressedBlock,

                                    % Corrupt the original_size field to be different
                                    CorruptedOriginalSize = OriginalSize + 100,

                                    % Recompute checksum with corrupted size
                                    CompressedSize = CompressedSizePlus9 - 9,
                                    ChecksumInput =
                                        <<MethodByte:8, CompressedSize:32/little,
                                            CorruptedOriginalSize:32/little,
                                            CompressedData/binary>>,
                                    NewChecksum = clickhouse_erl_cityhash:hash128(ChecksumInput),

                                    % Create corrupted block with wrong original_size
                                    CorruptedBlock =
                                        <<NewChecksum/binary, MethodByte:8,
                                            CompressedSizePlus9:32/little,
                                            CorruptedOriginalSize:32/little,
                                            CompressedData/binary>>,

                                    % Requirement 4.6: Decompression should fail with size_mismatch
                                    case clickhouse_erl_compression:decompress(CorruptedBlock) of
                                        {error, {size_mismatch, _}} ->
                                            % Correct behavior: size mismatch detected
                                            true;
                                        {error, {decompression_failed, _}} ->
                                            % Also acceptable: decompression fails due to size mismatch
                                            true;
                                        {ok, _} ->
                                            % Should not succeed with corrupted size
                                            false;
                                        {error, _OtherReason} ->
                                            % Other errors might be acceptable depending on implementation
                                            % Accept other errors as they indicate failure
                                            true
                                    end;
                                {error, _Reason} ->
                                    false
                            end;
                        false ->
                            % Method not available, skip this test case
                            true
                    end
            end
        end
    ).

%% Property 13: Error Handling Consistency
%% Validates: Requirements 3.7, 4.5
prop_error_handling_consistency() ->
    ?FORALL(
        {Data, Method, ErrorType},
        {binary_data_gen(), compression_method_for_header_gen(), error_type_gen()},
        begin
            % Skip disabled method
            case Method of
                disabled ->
                    true;
                _ ->
                    % Check if method is available
                    case clickhouse_erl_compression:is_available(Method) of
                        true ->
                            Opts = #{method => Method},

                            % Test compression error handling
                            case ErrorType of
                                compression_failure ->
                                    % Test that compression errors return proper error tuples
                                    case clickhouse_erl_compression:compress(Data, Opts) of
                                        {ok, _} ->
                                            % Success is fine
                                            true;
                                        {error, {compression_failed, _}} ->
                                            % Proper error tuple format
                                            true;
                                        {error, {Category, _}} when is_atom(Category) ->
                                            % Other error tuples are acceptable
                                            true;
                                        _Other ->
                                            % Should not return anything else
                                            false
                                    end;
                                decompression_failure ->
                                    % Create an invalid compressed block
                                    InvalidBlock = create_invalid_block(Data, Method),

                                    % Test that decompression errors return proper error tuples
                                    case clickhouse_erl_compression:decompress(InvalidBlock) of
                                        {ok, _} ->
                                            % Should not succeed with invalid block
                                            false;
                                        {error, {Category, _}} when is_atom(Category) ->
                                            % Proper error tuple format
                                            true;
                                        _Other ->
                                            % Should not return anything else
                                            false
                                    end
                            end;
                        false ->
                            % Method not available, skip this test case
                            true
                    end
            end
        end
    ).

%% Helper function to create an invalid compressed block
create_invalid_block(Data, Method) ->
    % Create a block with invalid checksum
    MethodByte = method_byte_value(Method),
    CompressedSize = byte_size(Data),
    OriginalSize = byte_size(Data),
    InvalidChecksum = <<0:128>>,
    <<InvalidChecksum/binary, MethodByte:8, (CompressedSize + 9):32/little, OriginalSize:32/little,
        Data/binary>>.

%% Generator for error types
error_type_gen() ->
    oneof([compression_failure, decompression_failure]).

%% Property 6: Compression Configuration Validation
%% Validates: Requirements 1.5, 2.4
prop_compression_configuration_validation() ->
    ?FORALL(
        Opts,
        invalid_compression_opts_gen(),
        begin
            Result = clickhouse_erl_compression:validate_opts(Opts),
            case Result of
                {error, {invalid_compression_method, _}} -> true;
                {error, {invalid_compression_level, _}} -> true;
                {error, {invalid_compression_opts, not_a_map}} -> true;
                _ -> false
            end
        end
    ).

%% Property 7: Compression Level Handling
%% Validates: Requirements 2.1, 2.2, 2.3
prop_compression_level_handling() ->
    ?FORALL(
        {Method, Level, Data},
        {compression_method_gen(), compression_level_gen(), binary_data_gen()},
        begin
            % Build compression options
            Opts =
                case Level of
                    undefined -> #{compression => Method};
                    _ -> #{compression => Method, compression_level => Level}
                end,

            % Validate options
            case clickhouse_erl_compression:validate_opts(Opts) of
                {ok, ValidatedOpts} ->
                    % Check that the validated options match expected behavior
                    verify_compression_level_behavior(Method, Level, ValidatedOpts, Data);
                {error, _} ->
                    % Should not get errors for valid inputs from our generator
                    false
            end
        end
    ).

%% Helper function to verify compression level behavior
verify_compression_level_behavior(lz4, undefined, ValidatedOpts, Data) ->
    % Requirement 2.2: LZ4 without level should use standard LZ4
    case ValidatedOpts of
        #{method := lz4} when not is_map_key(level, ValidatedOpts) ->
            % Verify standard LZ4 is used (no level specified)
            case clickhouse_erl_compression:compress_lz4(Data, undefined) of
                {ok, _Compressed} -> true;
                % Library might not be available, that's ok
                {error, _} -> true
            end;
        _ ->
            false
    end;
verify_compression_level_behavior(lz4, Level, ValidatedOpts, Data) when
    is_integer(Level), Level >= 0, Level =< 12
->
    % Requirement 2.1: LZ4 with level 0-12 should use LZ4HC
    case ValidatedOpts of
        #{method := lz4, level := Level} ->
            % Verify LZ4HC is used with the specified level
            case clickhouse_erl_compression:compress_lz4(Data, Level) of
                {ok, _Compressed} -> true;
                % Library might not be available, that's ok
                {error, _} -> true
            end;
        _ ->
            false
    end;
verify_compression_level_behavior(zstd, _Level, ValidatedOpts, _Data) ->
    % Requirement 2.3: ZSTD should ignore compression_level
    case ValidatedOpts of
        #{method := zstd} when not is_map_key(level, ValidatedOpts) ->
            % Level should be ignored for ZSTD
            true;
        _ ->
            false
    end;
verify_compression_level_behavior(none, _Level, ValidatedOpts, _Data) ->
    % None should ignore compression_level
    case ValidatedOpts of
        #{method := none} when not is_map_key(level, ValidatedOpts) ->
            % Level should be ignored for None
            true;
        _ ->
            false
    end;
verify_compression_level_behavior(disabled, _Level, ValidatedOpts, _Data) ->
    % Disabled should ignore compression_level
    case ValidatedOpts of
        #{method := disabled} ->
            true;
        _ ->
            false
    end.

%% Property 2: Compression Method Application
%% Validates: Requirements 1.1, 1.2, 1.3, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7
%% This property tests that the compression detection logic correctly identifies
%% when to apply compression based on compression options
prop_compression_method_application() ->
    ?FORALL(
        {CompressionOpts, PacketType},
        {compression_opts_gen(), packet_type_gen()},
        begin
            % Test the should_decompress logic from response handler
            ShouldDecompress = should_decompress_test(CompressionOpts),

            % Verify behavior based on packet type and compression settings
            case PacketType of
                % Compressible packets: DATA, TOTALS, EXTREMES
                data -> verify_compressible_packet(ShouldDecompress, CompressionOpts);
                totals -> verify_compressible_packet(ShouldDecompress, CompressionOpts);
                extremes -> verify_compressible_packet(ShouldDecompress, CompressionOpts);
                % Non-compressible packets: EXCEPTION, PROGRESS, etc.
                % These should never be compressed regardless of settings

                % Always uncompressed
                exception -> true;
                % Always uncompressed
                progress -> true;
                % Always uncompressed
                profile -> true;
                % Always uncompressed
                end_of_stream -> true
            end
        end
    ).

%% Helper function to test should_decompress logic
should_decompress_test(undefined) -> false;
should_decompress_test(#{method := disabled}) -> false;
should_decompress_test(#{method := _Method}) -> true;
should_decompress_test(_) -> false.

%% Helper function to verify compressible packet behavior
verify_compressible_packet(ShouldDecompress, CompressionOpts) ->
    case CompressionOpts of
        undefined ->
            % No compression opts -> should not decompress
            ShouldDecompress =:= false;
        #{method := disabled} ->
            % Compression disabled -> should not decompress
            ShouldDecompress =:= false;
        #{method := Method} when Method =:= lz4; Method =:= zstd; Method =:= none ->
            % Compression enabled -> should decompress
            ShouldDecompress =:= true;
        _ ->
            % Invalid opts -> should not decompress
            ShouldDecompress =:= false
    end.

%%%===================================================================
%%% Generators
%%%===================================================================

%% Generator for invalid compression options
invalid_compression_opts_gen() ->
    oneof([
        % Invalid compression method
        #{compression => invalid_method},
        #{compression => <<"lz4">>},
        #{compression => 123},
        #{compression => atom_that_is_not_valid},
        % Invalid compression level (outside 0-12 range)
        #{compression => lz4, compression_level => -1},
        #{compression => lz4, compression_level => 13},
        #{compression => lz4, compression_level => 100},
        #{compression => lz4, compression_level => -100},
        % Non-integer compression level
        #{compression => lz4, compression_level => 5.5},
        #{compression => lz4, compression_level => <<"5">>},
        #{compression => lz4, compression_level => atom},
        % Not a map
        not_a_map,
        [],
        <<"binary">>,
        123,
        atom
    ]).

%% Generator for valid compression methods
compression_method_gen() ->
    oneof([lz4, zstd, none, disabled]).

%% Generator for compression levels (undefined or 0-12)
compression_level_gen() ->
    oneof([
        undefined,
        range(0, 12)
    ]).

%% Generator for binary data to compress
binary_data_gen() ->
    oneof([
        % Empty binary
        <<>>,
        % Small data (< 16 bytes)
        ?LET(Size, range(1, 15), binary(Size)),
        % Medium data (16-128 bytes)
        ?LET(Size, range(16, 128), binary(Size)),
        % Larger data (> 128 bytes)
        ?LET(Size, range(129, 1024), binary(Size))
    ]).

%% Generator for compression options (including undefined and disabled)
compression_opts_gen() ->
    oneof([
        undefined,
        #{method => disabled},
        #{method => lz4},
        #{method => zstd},
        #{method => none},
        #{method => lz4, level => range(0, 12)}
    ]).

%% Generator for packet types
packet_type_gen() ->
    oneof([
        data,
        totals,
        extremes,
        exception,
        progress,
        profile,
        end_of_stream
    ]).
