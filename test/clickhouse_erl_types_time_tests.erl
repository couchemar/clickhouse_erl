%% @doc Unit tests for Time and Time64 type encoding/decoding.
%% Covers specific examples and edge cases, particularly the integer input paths.
-module(clickhouse_erl_types_time_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% encode_time64/1 with integer input
%%%===================================================================

%% @doc Encoding an integer nanosecond value produces correct 8-byte LE binary.
encode_time64_integer_test() ->
    Ns = 52245123456789,
    {ok, Encoded} = clickhouse_erl_types_time:encode_time64(Ns),
    ?assertEqual(8, byte_size(Encoded)),
    <<Decoded:64/little-signed>> = Encoded,
    ?assertEqual(Ns, Decoded).

%% @doc Integer encode then decode roundtrips to the equivalent tuple.
encode_time64_integer_roundtrip_test() ->
    %% 14:30:45.123456789 as nanoseconds
    Ns = (14 * 3600 + 30 * 60 + 45) * 1000000000 + 123456789,
    {ok, Encoded} = clickhouse_erl_types_time:encode_time64(Ns),
    {ok, Decoded, <<>>} = clickhouse_erl_types_time:decode_time64(Encoded),
    ?assertEqual({14, 30, 45, 123456789}, Decoded).

%% @doc Tuple and integer encoding produce identical bytes for the same time.
encode_time64_tuple_integer_equivalence_test() ->
    Tuple = {14, 30, 45, 123456789},
    Ns = (14 * 3600 + 30 * 60 + 45) * 1000000000 + 123456789,
    {ok, FromTuple} = clickhouse_erl_types_time:encode_time64(Tuple),
    {ok, FromInt} = clickhouse_erl_types_time:encode_time64(Ns),
    ?assertEqual(FromTuple, FromInt).

%% @doc Zero nanoseconds encodes to midnight.
encode_time64_zero_test() ->
    {ok, Encoded} = clickhouse_erl_types_time:encode_time64(0),
    {ok, Decoded, <<>>} = clickhouse_erl_types_time:decode_time64(Encoded),
    ?assertEqual({0, 0, 0, 0}, Decoded).

%% @doc Max valid time64 (23:59:59.999999999) roundtrips correctly.
encode_time64_max_test() ->
    Ns = (23 * 3600 + 59 * 60 + 59) * 1000000000 + 999999999,
    {ok, Encoded} = clickhouse_erl_types_time:encode_time64(Ns),
    {ok, Decoded, <<>>} = clickhouse_erl_types_time:decode_time64(Encoded),
    ?assertEqual({23, 59, 59, 999999999}, Decoded).

%%%===================================================================
%%% encode_time/1 with integer input
%%%===================================================================

%% @doc Encoding an integer seconds value produces correct 4-byte LE binary.
encode_time_integer_test() ->
    Secs = 52245,
    {ok, Encoded} = clickhouse_erl_types_time:encode_time(Secs),
    ?assertEqual(4, byte_size(Encoded)),
    <<Decoded:32/little-signed>> = Encoded,
    ?assertEqual(Secs, Decoded).

%% @doc Integer encode then decode roundtrips to the equivalent tuple.
encode_time_integer_roundtrip_test() ->
    %% 14:30:45 = 52245 seconds
    Secs = 14 * 3600 + 30 * 60 + 45,
    {ok, Encoded} = clickhouse_erl_types_time:encode_time(Secs),
    {ok, Decoded, <<>>} = clickhouse_erl_types_time:decode_time(Encoded),
    ?assertEqual({14, 30, 45}, Decoded).

%% @doc Tuple and integer encoding produce identical bytes for the same time.
encode_time_tuple_integer_equivalence_test() ->
    Tuple = {14, 30, 45},
    Secs = 14 * 3600 + 30 * 60 + 45,
    {ok, FromTuple} = clickhouse_erl_types_time:encode_time(Tuple),
    {ok, FromInt} = clickhouse_erl_types_time:encode_time(Secs),
    ?assertEqual(FromTuple, FromInt).
