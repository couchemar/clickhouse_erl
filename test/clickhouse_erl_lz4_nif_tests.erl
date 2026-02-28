%% @doc Unit tests for LZ4 NIF wrapper
-module(clickhouse_erl_lz4_nif_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Standard LZ4 Tests
%%%===================================================================

compress_small_data_test() ->
    Data = <<"Hello, World!">>,
    {ok, Compressed} = clickhouse_erl_lz4_nif:compress(Data),
    ?assert(is_binary(Compressed)),
    ?assert(byte_size(Compressed) > 0).

compress_empty_data_test() ->
    Data = <<>>,
    {ok, Compressed} = clickhouse_erl_lz4_nif:compress(Data),
    ?assert(is_binary(Compressed)).

compress_large_data_test() ->
    Data = binary:copy(<<"Test data for compression! ">>, 1000),
    {ok, Compressed} = clickhouse_erl_lz4_nif:compress(Data),
    ?assert(byte_size(Compressed) < byte_size(Data)).

decompress_valid_data_test() ->
    Data = <<"Hello, World!">>,
    {ok, Compressed} = clickhouse_erl_lz4_nif:compress(Data),
    {ok, Decompressed} = clickhouse_erl_lz4_nif:decompress(Compressed, byte_size(Data)),
    ?assertEqual(Data, Decompressed).

decompress_large_data_test() ->
    Data = binary:copy(<<"Test data! ">>, 500),
    {ok, Compressed} = clickhouse_erl_lz4_nif:compress(Data),
    {ok, Decompressed} = clickhouse_erl_lz4_nif:decompress(Compressed, byte_size(Data)),
    ?assertEqual(Data, Decompressed).

decompress_wrong_size_test() ->
    Data = <<"Hello, World!">>,
    {ok, Compressed} = clickhouse_erl_lz4_nif:compress(Data),
    Result = clickhouse_erl_lz4_nif:decompress(Compressed, byte_size(Data) + 10),
    ?assertMatch({error, _}, Result).

%%%===================================================================
%%% LZ4HC Tests
%%%===================================================================

compress_hc_level_0_test() ->
    Data = <<"Test data for LZ4HC compression">>,
    {ok, Compressed} = clickhouse_erl_lz4_nif:compress_hc(Data, 0),
    ?assert(is_binary(Compressed)),
    {ok, Decompressed} = clickhouse_erl_lz4_nif:decompress(Compressed, byte_size(Data)),
    ?assertEqual(Data, Decompressed).

compress_hc_level_6_test() ->
    Data = binary:copy(<<"Repeated data for better compression. ">>, 100),
    {ok, Compressed} = clickhouse_erl_lz4_nif:compress_hc(Data, 6),
    ?assert(is_binary(Compressed)),
    ?assert(byte_size(Compressed) < byte_size(Data)),
    {ok, Decompressed} = clickhouse_erl_lz4_nif:decompress(Compressed, byte_size(Data)),
    ?assertEqual(Data, Decompressed).

compress_hc_level_12_test() ->
    Data = binary:copy(<<"Maximum compression test data. ">>, 100),
    {ok, Compressed} = clickhouse_erl_lz4_nif:compress_hc(Data, 12),
    ?assert(is_binary(Compressed)),
    {ok, Decompressed} = clickhouse_erl_lz4_nif:decompress(Compressed, byte_size(Data)),
    ?assertEqual(Data, Decompressed).

compress_hc_invalid_level_negative_test() ->
    Data = <<"Test">>,
    Result = clickhouse_erl_lz4_nif:compress_hc(Data, -1),
    ?assertMatch({error, invalid_level}, Result).

compress_hc_invalid_level_too_high_test() ->
    Data = <<"Test">>,
    Result = clickhouse_erl_lz4_nif:compress_hc(Data, 13),
    ?assertMatch({error, invalid_level}, Result).

%%%===================================================================
%%% Compression Comparison Tests
%%%===================================================================

compare_standard_vs_hc_test() ->
    Data = binary:copy(<<"Compression comparison test data. ">>, 200),
    {ok, Standard} = clickhouse_erl_lz4_nif:compress(Data),
    {ok, HC} = clickhouse_erl_lz4_nif:compress_hc(Data, 9),

    % HC should produce smaller or equal size
    ?assert(byte_size(HC) =< byte_size(Standard)),

    % Both should decompress to original
    {ok, D1} = clickhouse_erl_lz4_nif:decompress(Standard, byte_size(Data)),
    {ok, D2} = clickhouse_erl_lz4_nif:decompress(HC, byte_size(Data)),
    ?assertEqual(Data, D1),
    ?assertEqual(Data, D2).

%%%===================================================================
%%% Edge Cases
%%%===================================================================

compress_binary_with_nulls_test() ->
    Data = <<0, 1, 2, 0, 0, 3, 4, 0>>,
    {ok, Compressed} = clickhouse_erl_lz4_nif:compress(Data),
    {ok, Decompressed} = clickhouse_erl_lz4_nif:decompress(Compressed, byte_size(Data)),
    ?assertEqual(Data, Decompressed).

compress_random_binary_test() ->
    Data = crypto:strong_rand_bytes(1024),
    {ok, Compressed} = clickhouse_erl_lz4_nif:compress(Data),
    {ok, Decompressed} = clickhouse_erl_lz4_nif:decompress(Compressed, byte_size(Data)),
    ?assertEqual(Data, Decompressed).

compress_highly_compressible_test() ->
    Data = binary:copy(<<0>>, 10000),
    {ok, Compressed} = clickhouse_erl_lz4_nif:compress(Data),
    % Should compress very well
    ?assert(byte_size(Compressed) < byte_size(Data) div 10),
    {ok, Decompressed} = clickhouse_erl_lz4_nif:decompress(Compressed, byte_size(Data)),
    ?assertEqual(Data, Decompressed).
