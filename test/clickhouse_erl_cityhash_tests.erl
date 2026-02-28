%% @doc Unit tests for CityHash128 checksum module
-module(clickhouse_erl_cityhash_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test hash computation against known reference values from ClickHouse documentation
%% CRITICAL TEST VECTORS from https://clickhouse.com/docs/native-protocol/hash
ch64_moscow_test() ->
    %% CH64(<<"Moscow">>) MUST equal 12507901496292878638 (ClickHouse variant)
    %% CH64(<<"Moscow">>) MUST NOT equal 5992710078453357409 (standard CityHash - wrong!)
    Expected = 12507901496292878638,
    Actual = clickhouse_erl_cityhash:ch64(<<"Moscow">>),
    ?assertEqual(Expected, Actual).

ch64_long_string_test() ->
    %% CH64(<<"How can you write a big system without C++?  -Paul Glick">>)
    %% MUST equal 6237945311650045625
    Input = <<"How can you write a big system without C++?  -Paul Glick">>,
    Expected = 6237945311650045625,
    Actual = clickhouse_erl_cityhash:ch64(Input),
    ?assertEqual(Expected, Actual).

%% Test hash128 computation
hash128_empty_test() ->
    Result = clickhouse_erl_cityhash:hash128(<<>>),
    ?assert(is_binary(Result)),
    ?assertEqual(16, byte_size(Result)).

hash128_small_input_test() ->
    Result = clickhouse_erl_cityhash:hash128(<<"hello">>),
    ?assert(is_binary(Result)),
    ?assertEqual(16, byte_size(Result)).

hash128_medium_input_test() ->
    %% Test input between 16-128 bytes

    % 80 bytes
    Input = binary:copy(<<"test">>, 20),
    Result = clickhouse_erl_cityhash:hash128(Input),
    ?assert(is_binary(Result)),
    ?assertEqual(16, byte_size(Result)).

hash128_large_input_test() ->
    %% Test input > 128 bytes

    % 200 bytes
    Input = binary:copy(<<"test">>, 50),
    Result = clickhouse_erl_cityhash:hash128(Input),
    ?assert(is_binary(Result)),
    ?assertEqual(16, byte_size(Result)).

%% Test checksum verification
verify_valid_checksum_test() ->
    Data = <<"test data">>,
    Hash = clickhouse_erl_cityhash:hash128(Data),
    ?assert(clickhouse_erl_cityhash:verify(Data, Hash)).

verify_invalid_checksum_test() ->
    Data = <<"test data">>,
    InvalidHash = <<0:128/little>>,
    ?assertNot(clickhouse_erl_cityhash:verify(Data, InvalidHash)).

%% Test encode/decode hash
encode_decode_roundtrip_test() ->
    Low = 16#123456789abcdef0,
    High = 16#fedcba9876543210,
    Encoded = clickhouse_erl_cityhash:encode_hash(Low, High),
    ?assertEqual(16, byte_size(Encoded)),
    {DecodedLow, DecodedHigh} = clickhouse_erl_cityhash:decode_hash(Encoded),
    ?assertEqual(Low, DecodedLow),
    ?assertEqual(High, DecodedHigh).

%% Test edge cases
hash128_16_bytes_test() ->
    Input = <<1:128>>,
    Result = clickhouse_erl_cityhash:hash128(Input),
    ?assertEqual(16, byte_size(Result)).

hash128_128_bytes_test() ->
    % 128 bytes
    Input = <<0:1024>>,
    Result = clickhouse_erl_cityhash:hash128(Input),
    ?assertEqual(16, byte_size(Result)).

%% Additional CH64 test vectors from ch-go
ch64_empty_test() ->
    Expected = 11160318154034397263,
    Actual = clickhouse_erl_cityhash:ch64(<<>>),
    ?assertEqual(Expected, Actual).

ch64_ch_test() ->
    Expected = 15020278857692564095,
    Actual = clickhouse_erl_cityhash:ch64(<<"CH">>),
    ?assertEqual(Expected, Actual).

ch64_clickhouse_test() ->
    Expected = 12904064065176299341,
    Actual = clickhouse_erl_cityhash:ch64(<<"ClickHouse">>),
    ?assertEqual(Expected, Actual).

ch64_medium_string_test() ->
    Expected = 15757221730003458568,
    Actual = clickhouse_erl_cityhash:ch64(<<"ClickHouseIsAnOpenSource">>),
    ?assertEqual(Expected, Actual).

ch64_64_bytes_test() ->
    Input = <<"ClickHouseIsAnOpenSourceAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA">>,
    Expected = 6686391753024203911,
    Actual = clickhouse_erl_cityhash:ch64(Input),
    ?assertEqual(Expected, Actual).

ch64_96_bytes_test() ->
    Input =
        <<"ClickHouseIsAnOpenSourceAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA">>,
    Expected = 11821112606263625207,
    Actual = clickhouse_erl_cityhash:ch64(Input),
    ?assertEqual(Expected, Actual).

ch64_very_long_string_test() ->
    Input =
        <<"ClickHouse is an open-source, high performance columnar OLAP database management system for real-time analytics using SQL">>,
    Expected = 12510537841872258940,
    Actual = clickhouse_erl_cityhash:ch64(Input),
    ?assertEqual(Expected, Actual).

%% Test CH128 with known test vectors from ch-go
hash128_test_vector_1_test() ->
    %% First test vector from ch-go ch128.csv
    Input = <<"TSDGQtM27SmjL0naFMqcQ3ETsYKbDbrBeIj">>,
    ExpectedLow = 16#5a568f460b784901,
    ExpectedHigh = 16#8194e9a0cefb22fd,
    Hash = clickhouse_erl_cityhash:hash128(Input),
    {Low, High} = clickhouse_erl_cityhash:decode_hash(Hash),
    ?assertEqual(ExpectedLow, Low),
    ?assertEqual(ExpectedHigh, High).

hash128_test_vector_2_test() ->
    %% Second test vector - medium length
    Input =
        <<"84CRSqvk5zXuR9FvrRkSlnJ9n3vJcw5vorqvhmcmPKQppGZanHc3SGuTXf1rUUORpRGMJL1SNQ0wUkYn6cnB8iBLqKFmXjtjbEfBQcN81qV4lSLJBC4lkmUdb2SkP">>,
    ExpectedLow = 16#2bf935b2f4c4ba91,
    ExpectedHigh = 16#e309e9e8f60de6e5,
    Hash = clickhouse_erl_cityhash:hash128(Input),
    {Low, High} = clickhouse_erl_cityhash:decode_hash(Hash),
    ?assertEqual(ExpectedLow, Low),
    ?assertEqual(ExpectedHigh, High).

hash128_test_vector_3_test() ->
    %% Third test vector - very long string (>128 bytes)
    Input =
        <<"dSuVrKcDPbNrYbVLAAMtu6pnxJwswDsnMxnTuLtB00QANVT1DigXui1OtNHuT143YFLyohKWvHSONRHkzWnq2iqKPgod8Ld7O1CK0jYql8r8hKZnCCT9LV27K2ovfA7gtUcLZdcowuoPRhMNYc2ThhTmg8vrtQUg9Z4dn9oirYbXyiO0bwkCPq2Hs2oMF4IKlKmNcMm009Nn6BMYymAJREv63Ihy1fjXx3QXItn95ZbIWr4dLx2dim7UPHOxTQoZnn3H7y3SuSAQoDFxFLoRY4tzZjhaBnng14pBryp686qg31oRI8AFVMwvnKHynBJYINKHV27tNP20PZtqUnGAaDVksSOXrcqVahybF38Wh2QP6mUnfEwpd8KSnbX1a5UfoibCy71lwyuRX91XhUORvCOGCptoTH0Kn7X5lrtpphrgncJVX82LZiItmEeRMGquS8GuRb5TrZUfJRTuot2RuZ2kLiJRaOJRGckHTZN2JZSXH7fgfHQKpJxuVuXesV91JQtLZ3RlpMluJbhn0YU3Kei4hTiK62eDURphpTc2F8LrfJ3rjsE2AHlX42pMwfcZXLrLevXLNTR5woBtFtd25auwaEnne9Q1moRAzGv47zE4804sr21C2ixaRoPVyy4BrJQPXyPDPrM5QwXltecTGNLjZya70ODap7tnwVXALEVHS4iGNNkuWuP86CDNwzbKidBhViixmjBEdB1pHr0EQEIihAoj993HG8GaNw6w1ib4myEsbxtW2hO1Z4ZNAUR6yFhcx1kd">>,
    ExpectedLow = 16#3e44ce73326da543,
    ExpectedHigh = 16#5ea69e53269d237e,
    Hash = clickhouse_erl_cityhash:hash128(Input),
    {Low, High} = clickhouse_erl_cityhash:decode_hash(Hash),
    ?assertEqual(ExpectedLow, Low),
    ?assertEqual(ExpectedHigh, High).

%% Test encode/decode with zero values
encode_decode_zero_test() ->
    Low = 0,
    High = 0,
    Encoded = clickhouse_erl_cityhash:encode_hash(Low, High),
    ?assertEqual(16, byte_size(Encoded)),
    {DecodedLow, DecodedHigh} = clickhouse_erl_cityhash:decode_hash(Encoded),
    ?assertEqual(Low, DecodedLow),
    ?assertEqual(High, DecodedHigh).

%% Test encode/decode with max values
encode_decode_max_test() ->
    Low = 16#ffffffffffffffff,
    High = 16#ffffffffffffffff,
    Encoded = clickhouse_erl_cityhash:encode_hash(Low, High),
    ?assertEqual(16, byte_size(Encoded)),
    {DecodedLow, DecodedHigh} = clickhouse_erl_cityhash:decode_hash(Encoded),
    ?assertEqual(Low, DecodedLow),
    ?assertEqual(High, DecodedHigh).

%% Test verify with different data
verify_different_data_test() ->
    Data1 = <<"test data 1">>,
    Data2 = <<"test data 2">>,
    Hash1 = clickhouse_erl_cityhash:hash128(Data1),
    ?assertNot(clickhouse_erl_cityhash:verify(Data2, Hash1)).

%% Test hash consistency - same input produces same hash
hash_consistency_test() ->
    Data = <<"consistent test data">>,
    Hash1 = clickhouse_erl_cityhash:hash128(Data),
    Hash2 = clickhouse_erl_cityhash:hash128(Data),
    ?assertEqual(Hash1, Hash2).

%% Test hash uniqueness - different inputs produce different hashes
hash_uniqueness_test() ->
    Data1 = <<"data1">>,
    Data2 = <<"data2">>,
    Hash1 = clickhouse_erl_cityhash:hash128(Data1),
    Hash2 = clickhouse_erl_cityhash:hash128(Data2),
    ?assertNotEqual(Hash1, Hash2).
