%% @doc Unit tests for extended integer type encoding and decoding
-module(clickhouse_erl_types_extended_integer_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Int128 Encoding Tests
%%%===================================================================

encode_int128_zero_test() ->
    {ok, Binary} = clickhouse_erl_types_extended_integer:encode_int128(0),
    ?assertEqual(<<0:128/little-signed>>, Binary).

encode_int128_positive_small_test() ->
    {ok, Binary} = clickhouse_erl_types_extended_integer:encode_int128(42),
    ?assertEqual(<<42:128/little-signed>>, Binary).

encode_int128_negative_small_test() ->
    {ok, Binary} = clickhouse_erl_types_extended_integer:encode_int128(-42),
    ?assertEqual(<<-42:128/little-signed>>, Binary).

encode_int128_max_value_test() ->
    Max = 170141183460469231731687303715884105727,
    {ok, Binary} = clickhouse_erl_types_extended_integer:encode_int128(Max),
    ?assertEqual(16, byte_size(Binary)).

encode_int128_min_value_test() ->
    Min = -170141183460469231731687303715884105728,
    {ok, Binary} = clickhouse_erl_types_extended_integer:encode_int128(Min),
    ?assertEqual(16, byte_size(Binary)).

encode_int128_out_of_range_positive_test() ->
    Max = 170141183460469231731687303715884105727,
    Result = clickhouse_erl_types_extended_integer:encode_int128(Max + 1),
    ?assertMatch({error, {value_out_of_range, _}}, Result).

encode_int128_out_of_range_negative_test() ->
    Min = -170141183460469231731687303715884105728,
    Result = clickhouse_erl_types_extended_integer:encode_int128(Min - 1),
    ?assertMatch({error, {value_out_of_range, _}}, Result).

encode_int128_invalid_type_test() ->
    Result = clickhouse_erl_types_extended_integer:encode_int128(<<"not an integer">>),
    ?assertMatch({error, {invalid_value, _}}, Result).

%%%===================================================================
%%% UInt128 Encoding Tests
%%%===================================================================

encode_uint128_zero_test() ->
    {ok, Binary} = clickhouse_erl_types_extended_integer:encode_uint128(0),
    ?assertEqual(<<0:128/little-unsigned>>, Binary).

encode_uint128_positive_small_test() ->
    {ok, Binary} = clickhouse_erl_types_extended_integer:encode_uint128(42),
    ?assertEqual(<<42:128/little-unsigned>>, Binary).

encode_uint128_max_value_test() ->
    Max = 340282366920938463463374607431768211455,
    {ok, Binary} = clickhouse_erl_types_extended_integer:encode_uint128(Max),
    ?assertEqual(16, byte_size(Binary)).

encode_uint128_out_of_range_test() ->
    Max = 340282366920938463463374607431768211455,
    Result = clickhouse_erl_types_extended_integer:encode_uint128(Max + 1),
    ?assertMatch({error, {value_out_of_range, _}}, Result).

encode_uint128_negative_test() ->
    Result = clickhouse_erl_types_extended_integer:encode_uint128(-1),
    ?assertMatch({error, {invalid_value, _}}, Result).

encode_uint128_invalid_type_test() ->
    Result = clickhouse_erl_types_extended_integer:encode_uint128(<<"not an integer">>),
    ?assertMatch({error, {invalid_value, _}}, Result).

%%%===================================================================
%%% Int128 Encoding Format Tests
%%%===================================================================

encode_int128_little_endian_test() ->
    % Test that encoding is little-endian (low 64 bits first, high 64 bits second)
    {ok, Binary} = clickhouse_erl_types_extended_integer:encode_int128(1),
    <<Low:64/little-signed, High:64/little-signed>> = Binary,
    ?assertEqual(1, Low),
    ?assertEqual(0, High).

encode_int128_large_value_structure_test() ->
    % Test a value that requires both low and high parts
    % 2^64 = 18446744073709551616
    Value = 18446744073709551616,
    {ok, Binary} = clickhouse_erl_types_extended_integer:encode_int128(Value),
    <<Low:64/little-signed, High:64/little-signed>> = Binary,
    ?assertEqual(0, Low),
    ?assertEqual(1, High).

%%%===================================================================
%%% UInt128 Encoding Format Tests
%%%===================================================================

encode_uint128_little_endian_test() ->
    % Test that encoding is little-endian (low 64 bits first, high 64 bits second)
    {ok, Binary} = clickhouse_erl_types_extended_integer:encode_uint128(1),
    <<Low:64/little-unsigned, High:64/little-unsigned>> = Binary,
    ?assertEqual(1, Low),
    ?assertEqual(0, High).

encode_uint128_large_value_structure_test() ->
    % Test a value that requires both low and high parts
    % 2^64 = 18446744073709551616
    Value = 18446744073709551616,
    {ok, Binary} = clickhouse_erl_types_extended_integer:encode_uint128(Value),
    <<Low:64/little-unsigned, High:64/little-unsigned>> = Binary,
    ?assertEqual(0, Low),
    ?assertEqual(1, High).
