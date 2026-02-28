%% @doc Unit tests for compression error code handling
-module(clickhouse_erl_compression_error_codes_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test Cases
%%%===================================================================

%% Test error code 89 (UNKNOWN_COMPRESSION_METHOD)
unknown_compression_method_error_code_test() ->
    ErrorCode = 89,
    {ErrorAtom, Description} = clickhouse_erl_error_codes:get_error_code_description(ErrorCode),

    ?assertEqual(unknown_compression_method, ErrorAtom),
    ?assert(is_list(Description)),
    ?assertEqual("Unknown compression method", Description).

%% Test error code 270 (CANNOT_COMPRESS)
cannot_compress_error_code_test() ->
    ErrorCode = 270,
    {ErrorAtom, Description} = clickhouse_erl_error_codes:get_error_code_description(ErrorCode),

    ?assertEqual(cannot_compress, ErrorAtom),
    ?assert(is_list(Description)),
    ?assertEqual("Cannot compress", Description).

%% Test error code 271 (CANNOT_DECOMPRESS)
cannot_decompress_error_code_test() ->
    ErrorCode = 271,
    {ErrorAtom, Description} = clickhouse_erl_error_codes:get_error_code_description(ErrorCode),

    ?assertEqual(cannot_decompress, ErrorAtom),
    ?assert(is_list(Description)),
    ?assertEqual("Cannot decompress", Description).

%% Test compression library missing error
compression_library_missing_error_test() ->
    %% Test LZ4 library missing
    Method = lz4,
    Error = {error, {compression_library_missing, Method}},

    ?assertMatch({error, {compression_library_missing, lz4}}, Error),

    %% Test ZSTD library missing
    Method2 = zstd,
    Error2 = {error, {compression_library_missing, Method2}},

    ?assertMatch({error, {compression_library_missing, zstd}}, Error2).

%% Test that error atoms can be retrieved individually
get_error_atom_test() ->
    ?assertEqual(unknown_compression_method, clickhouse_erl_error_codes:get_error(89)),
    ?assertEqual(cannot_compress, clickhouse_erl_error_codes:get_error(270)),
    ?assertEqual(cannot_decompress, clickhouse_erl_error_codes:get_error(271)).

%% Test that readable error descriptions can be retrieved
get_readable_error_test() ->
    ?assertEqual(
        "Unknown compression method",
        clickhouse_erl_error_codes:get_readable_error(89)
    ),
    ?assertEqual(
        "Cannot compress",
        clickhouse_erl_error_codes:get_readable_error(270)
    ),
    ?assertEqual(
        "Cannot decompress",
        clickhouse_erl_error_codes:get_readable_error(271)
    ).
