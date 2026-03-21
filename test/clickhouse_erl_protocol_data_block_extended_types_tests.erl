%% @doc Unit tests for extended type parsing in data block module
-module(clickhouse_erl_protocol_data_block_extended_types_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Extended Integer Type Recognition Tests
%%%===================================================================

int128_type_recognition_test() ->
    % Test that Int128 type is recognized
    Binary = <<42:128/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"Int128">>, 1, Binary),
    ?assertMatch({ok, [42], <<>>}, Result).

uint128_type_recognition_test() ->
    % Test that UInt128 type is recognized
    Binary = <<42:128/little-unsigned-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"UInt128">>, 1, Binary),
    ?assertMatch({ok, [42], <<>>}, Result).

int256_type_recognition_test() ->
    % Test that Int256 type is recognized
    Binary = <<42:256/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"Int256">>, 1, Binary),
    ?assertMatch({ok, [42], <<>>}, Result).

uint256_type_recognition_test() ->
    % Test that UInt256 type is recognized
    Binary = <<42:256/little-unsigned-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"UInt256">>, 1, Binary),
    ?assertMatch({ok, [42], <<>>}, Result).

%%%===================================================================
%%% Decimal Type Recognition Tests
%%%===================================================================

decimal32_type_recognition_test() ->
    % Test that Decimal32(9, 2) type is recognized
    Binary = <<12345:32/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"Decimal32(9, 2)">>, 1, Binary
    ),
    ?assertMatch({ok, [{decimal, 12345, 2}], <<>>}, Result).

decimal64_type_recognition_test() ->
    % Test that Decimal64(18, 4) type is recognized
    Binary = <<123456789:64/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"Decimal64(18, 4)">>, 1, Binary
    ),
    ?assertMatch({ok, [{decimal, 123456789, 4}], <<>>}, Result).

%%%===================================================================
%%% Enum Type Recognition Tests
%%%===================================================================

enum8_type_recognition_test() ->
    % Test that Enum8 type is recognized
    Binary = <<1:8/signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"Enum8('active' = 1, 'inactive' = 0)">>, 1, Binary
    ),
    ?assertMatch({ok, [active], <<>>}, Result).

enum16_type_recognition_test() ->
    % Test that Enum16 type is recognized
    Binary = <<1:16/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"Enum16('active' = 1, 'inactive' = 0)">>, 1, Binary
    ),
    ?assertMatch({ok, [active], <<>>}, Result).

%%%===================================================================
%%% Network Type Recognition Tests
%%%===================================================================

ipv4_type_recognition_test() ->
    % Test that IPv4 type is recognized (little-endian: {A,B,C,D} stored as <<D,C,B,A>>)
    Binary = <<1, 1, 168, 192>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"IPv4">>, 1, Binary),
    ?assertMatch({ok, [{192, 168, 1, 1}], <<>>}, Result).

ipv6_type_recognition_test() ->
    % Test that IPv6 type is recognized
    Binary = <<32, 1, 13, 184, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"IPv6">>, 1, Binary),
    ?assertMatch({ok, [_], <<>>}, Result).

%%%===================================================================
%%% UUID Type Recognition Tests
%%%===================================================================

uuid_type_recognition_test() ->
    % Test that UUID type is recognized
    Binary = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"UUID">>, 1, Binary),
    ?assertMatch({ok, [_], <<>>}, Result).

%%%===================================================================
%%% Time Type Recognition Tests
%%%===================================================================

time_type_recognition_test() ->
    % Test that Time type is recognized
    Seconds = 14 * 3600 + 30 * 60 + 45,
    Binary = <<Seconds:32/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"Time">>, 1, Binary),
    ?assertMatch({ok, [{14, 30, 45}], <<>>}, Result).

time64_type_recognition_test() ->
    % Test that Time64 type is recognized
    Nanoseconds = (14 * 3600 + 30 * 60 + 45) * 1000000000,
    Binary = <<Nanoseconds:64/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"Time64">>, 1, Binary),
    ?assertMatch({ok, [{14, 30, 45, 0}], <<>>}, Result).

%%%===================================================================
%%% Special Type Recognition Tests
%%%===================================================================

nothing_type_recognition_test() ->
    % Test that Nothing type is recognized
    Binary = <<0>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"Nothing">>, 1, Binary),
    ?assertMatch({ok, [null], <<>>}, Result).

point_type_recognition_test() ->
    % Test that Point type is recognized
    Binary = <<1.5:64/little-float, 2.5:64/little-float>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"Point">>, 1, Binary),
    ?assertMatch({ok, [{1.5, 2.5}], <<>>}, Result).

interval_second_type_recognition_test() ->
    % Test that IntervalSecond type is recognized
    Binary = <<3600:64/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"IntervalSecond">>, 1, Binary
    ),
    ?assertMatch({ok, [{interval, second, 3600}], <<>>}, Result).

interval_day_type_recognition_test() ->
    % Test that IntervalDay type is recognized
    Binary = <<7:64/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"IntervalDay">>, 1, Binary),
    ?assertMatch({ok, [{interval, day, 7}], <<>>}, Result).

json_type_recognition_test() ->
    % Test that JSON type is recognized
    JsonBinary = <<"{\"key\":\"value\"}">>,
    Len = byte_size(JsonBinary),
    Binary = <<Len, JsonBinary/binary>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"JSON">>, 1, Binary),
    ?assertMatch({ok, [<<"{\"key\":\"value\"}">>], <<>>}, Result).
