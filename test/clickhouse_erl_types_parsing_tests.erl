%% @doc Unit tests for extended type name parsing
-module(clickhouse_erl_types_parsing_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Decimal Type Parsing Tests
%%%===================================================================

parse_decimal32_valid_test() ->
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal32(9, 2)">>),
    ?assertMatch({ok, {decimal32, 9, 2}}, Result).

parse_decimal32_max_precision_test() ->
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal32(9, 9)">>),
    ?assertMatch({ok, {decimal32, 9, 9}}, Result).

parse_decimal32_no_spaces_test() ->
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal32(5,2)">>),
    ?assertMatch({ok, {decimal32, 5, 2}}, Result).

parse_decimal64_valid_test() ->
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal64(18, 4)">>),
    ?assertMatch({ok, {decimal64, 18, 4}}, Result).

parse_decimal64_max_precision_test() ->
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal64(18, 18)">>),
    ?assertMatch({ok, {decimal64, 18, 18}}, Result).

parse_decimal128_valid_test() ->
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal128(38, 10)">>),
    ?assertMatch({ok, {decimal128, 38, 10}}, Result).

parse_decimal128_max_precision_test() ->
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal128(38, 38)">>),
    ?assertMatch({ok, {decimal128, 38, 38}}, Result).

parse_decimal256_valid_test() ->
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal256(76, 20)">>),
    ?assertMatch({ok, {decimal256, 76, 20}}, Result).

parse_decimal256_max_precision_test() ->
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal256(76, 76)">>),
    ?assertMatch({ok, {decimal256, 76, 76}}, Result).

parse_decimal_string_input_test() ->
    Result = clickhouse_erl_types_decimal:parse_decimal_type("Decimal32(9, 2)"),
    ?assertMatch({ok, {decimal32, 9, 2}}, Result).

parse_decimal_invalid_type_test() ->
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal512(100, 50)">>),
    ?assertMatch({error, {invalid_decimal_type, _}}, Result).

parse_decimal_scale_only_test() ->
    %% Decimal32(S) format - scale only, precision defaults to max (9)
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal32(4)">>),
    ?assertMatch({ok, {decimal32, 9, 4}}, Result).

parse_decimal_malformed_params_test() ->
    %% Missing closing parenthesis
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal32(9, 2">>),
    ?assertMatch({error, {invalid_decimal_format, _}}, Result).

parse_decimal_generic_format_test() ->
    %% Generic Decimal(P, S) format - ClickHouse canonical representation
    Result1 = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal(9, 4)">>),
    ?assertMatch({ok, {decimal32, 9, 4}}, Result1),

    Result2 = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal(18, 6)">>),
    ?assertMatch({ok, {decimal64, 18, 6}}, Result2),

    Result3 = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal(38, 10)">>),
    ?assertMatch({ok, {decimal128, 38, 10}}, Result3),

    Result4 = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal(76, 20)">>),
    ?assertMatch({ok, {decimal256, 76, 20}}, Result4).

parse_decimal_invalid_precision_test() ->
    Result = clickhouse_erl_types_decimal:parse_decimal_type(<<"Decimal32(abc, 2)">>),
    ?assertMatch({error, {invalid_decimal_params, _}}, Result).

%%%===================================================================
%%% Enum Type Parsing Tests
%%%===================================================================

parse_enum8_simple_test() ->
    TypeString = <<"Enum8('active' = 1, 'inactive' = 0)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({ok, {enum8, _}}, Result),
    {ok, {enum8, Mappings}} = Result,
    ?assertEqual(1, maps:get(active, Mappings)),
    ?assertEqual(0, maps:get(inactive, Mappings)).

parse_enum8_negative_values_test() ->
    TypeString = <<"Enum8('positive' = 1, 'zero' = 0, 'negative' = -1)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({ok, {enum8, _}}, Result),
    {ok, {enum8, Mappings}} = Result,
    ?assertEqual(1, maps:get(positive, Mappings)),
    ?assertEqual(0, maps:get(zero, Mappings)),
    ?assertEqual(-1, maps:get(negative, Mappings)).

parse_enum8_no_spaces_test() ->
    TypeString = <<"Enum8('a'=1,'b'=2)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({ok, {enum8, _}}, Result),
    {ok, {enum8, Mappings}} = Result,
    ?assertEqual(1, maps:get(a, Mappings)),
    ?assertEqual(2, maps:get(b, Mappings)).

parse_enum16_simple_test() ->
    TypeString = <<"Enum16('status1' = 100, 'status2' = 200)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({ok, {enum16, _}}, Result),
    {ok, {enum16, Mappings}} = Result,
    ?assertEqual(100, maps:get(status1, Mappings)),
    ?assertEqual(200, maps:get(status2, Mappings)).

parse_enum16_negative_values_test() ->
    TypeString = <<"Enum16('deleted' = -100, 'active' = 100)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({ok, {enum16, _}}, Result),
    {ok, {enum16, Mappings}} = Result,
    ?assertEqual(-100, maps:get(deleted, Mappings)),
    ?assertEqual(100, maps:get(active, Mappings)).

parse_enum_invalid_type_test() ->
    TypeString = <<"Enum32('invalid' = 1)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({error, {parse_header_failed, _}}, Result).

parse_enum_malformed_mapping_test() ->
    TypeString = <<"Enum8('missing_value' =)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({error, {parse_mappings_failed, _}}, Result).

parse_enum_non_binary_test() ->
    Result = clickhouse_erl_types_enum:parse_enum_type("not a binary"),
    ?assertMatch({error, {invalid_type, _}}, Result).

%%%===================================================================
%%% Interval Type Parsing Tests
%%%===================================================================

parse_interval_second_test() ->
    Result = clickhouse_erl_types_special:parse_interval_type(<<"IntervalSecond">>),
    ?assertEqual({ok, {interval, second}}, Result).

parse_interval_minute_test() ->
    Result = clickhouse_erl_types_special:parse_interval_type(<<"IntervalMinute">>),
    ?assertEqual({ok, {interval, minute}}, Result).

parse_interval_hour_test() ->
    Result = clickhouse_erl_types_special:parse_interval_type(<<"IntervalHour">>),
    ?assertEqual({ok, {interval, hour}}, Result).

parse_interval_day_test() ->
    Result = clickhouse_erl_types_special:parse_interval_type(<<"IntervalDay">>),
    ?assertEqual({ok, {interval, day}}, Result).

parse_interval_week_test() ->
    Result = clickhouse_erl_types_special:parse_interval_type(<<"IntervalWeek">>),
    ?assertEqual({ok, {interval, week}}, Result).

parse_interval_month_test() ->
    Result = clickhouse_erl_types_special:parse_interval_type(<<"IntervalMonth">>),
    ?assertEqual({ok, {interval, month}}, Result).

parse_interval_quarter_test() ->
    Result = clickhouse_erl_types_special:parse_interval_type(<<"IntervalQuarter">>),
    ?assertEqual({ok, {interval, quarter}}, Result).

parse_interval_year_test() ->
    Result = clickhouse_erl_types_special:parse_interval_type(<<"IntervalYear">>),
    ?assertEqual({ok, {interval, year}}, Result).

parse_interval_invalid_scale_test() ->
    Result = clickhouse_erl_types_special:parse_interval_type(<<"IntervalCentury">>),
    ?assertMatch({error, {invalid_interval_type, _}}, Result).

parse_interval_malformed_test() ->
    Result = clickhouse_erl_types_special:parse_interval_type(<<"Interval">>),
    ?assertMatch({error, {invalid_interval_type, _}}, Result).

%%%===================================================================
%%% Type Recognition in Data Block Tests
%%%===================================================================

%% Extended Integer Types
recognize_int128_test() ->
    Binary = <<42:128/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"Int128">>, 1, Binary),
    ?assertMatch({ok, [42], <<>>}, Result).

recognize_uint128_test() ->
    Binary = <<42:128/little-unsigned-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"UInt128">>, 1, Binary),
    ?assertMatch({ok, [42], <<>>}, Result).

recognize_int256_test() ->
    Binary = <<42:256/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"Int256">>, 1, Binary),
    ?assertMatch({ok, [42], <<>>}, Result).

recognize_uint256_test() ->
    Binary = <<42:256/little-unsigned-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"UInt256">>, 1, Binary),
    ?assertMatch({ok, [42], <<>>}, Result).

%% Decimal Types with Parameters
recognize_decimal32_test() ->
    Binary = <<12345:32/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"Decimal32(9, 2)">>, 1, Binary
    ),
    ?assertMatch({ok, [{decimal, 12345, 2}], <<>>}, Result).

recognize_decimal64_test() ->
    Binary = <<123456789:64/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"Decimal64(18, 4)">>, 1, Binary
    ),
    ?assertMatch({ok, [{decimal, 123456789, 4}], <<>>}, Result).

recognize_decimal128_test() ->
    Binary = <<12345:128/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"Decimal128(38, 10)">>, 1, Binary
    ),
    ?assertMatch({ok, [{decimal, 12345, 10}], <<>>}, Result).

recognize_decimal256_test() ->
    Binary = <<12345:256/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"Decimal256(76, 20)">>, 1, Binary
    ),
    ?assertMatch({ok, [{decimal, 12345, 20}], <<>>}, Result).

%% Enum Types with Mappings
recognize_enum8_test() ->
    Binary = <<1:8/signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"Enum8('active' = 1, 'inactive' = 0)">>, 1, Binary
    ),
    ?assertMatch({ok, [active], <<>>}, Result).

recognize_enum16_test() ->
    Binary = <<1:16/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"Enum16('active' = 1, 'inactive' = 0)">>, 1, Binary
    ),
    ?assertMatch({ok, [active], <<>>}, Result).

%% Network Types
recognize_ipv4_test() ->
    Binary = <<192, 168, 1, 1>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"IPv4">>, 1, Binary),
    ?assertMatch({ok, [{192, 168, 1, 1}], <<>>}, Result).

recognize_ipv6_test() ->
    Binary = <<32, 1, 13, 184, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"IPv6">>, 1, Binary),
    ?assertMatch({ok, [_], <<>>}, Result).

%% UUID Type
recognize_uuid_test() ->
    Binary = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"UUID">>, 1, Binary),
    ?assertMatch({ok, [_], <<>>}, Result).

%% Time Types
recognize_time_test() ->
    Seconds = 14 * 3600 + 30 * 60 + 45,
    Binary = <<Seconds:32/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"Time">>, 1, Binary),
    ?assertMatch({ok, [{14, 30, 45}], <<>>}, Result).

recognize_time64_test() ->
    Nanoseconds = (14 * 3600 + 30 * 60 + 45) * 1000000000,
    Binary = <<Nanoseconds:64/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"Time64">>, 1, Binary),
    ?assertMatch({ok, [{14, 30, 45, 0}], <<>>}, Result).

%% Special Types
recognize_nothing_test() ->
    Binary = <<0>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"Nothing">>, 1, Binary),
    ?assertMatch({ok, [null], <<>>}, Result).

recognize_point_test() ->
    Binary = <<1.5:64/little-float, 2.5:64/little-float>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"Point">>, 1, Binary),
    ?assertMatch({ok, [{1.5, 2.5}], <<>>}, Result).

recognize_interval_second_test() ->
    Binary = <<3600:64/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"IntervalSecond">>, 1, Binary
    ),
    ?assertMatch({ok, [{interval, second, 3600}], <<>>}, Result).

recognize_interval_day_test() ->
    Binary = <<7:64/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"IntervalDay">>, 1, Binary),
    ?assertMatch({ok, [{interval, day, 7}], <<>>}, Result).

recognize_interval_month_test() ->
    Binary = <<3:64/little-signed-integer>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"IntervalMonth">>, 1, Binary
    ),
    ?assertMatch({ok, [{interval, month, 3}], <<>>}, Result).

recognize_json_test() ->
    JsonBinary = <<"{\"key\":\"value\"}">>,
    Len = byte_size(JsonBinary),
    Binary = <<Len, JsonBinary/binary>>,
    Result = clickhouse_erl_protocol_data_block:decode_column_data(<<"JSON">>, 1, Binary),
    ?assertMatch({ok, [<<"{\"key\":\"value\"}">>], <<>>}, Result).

%%%===================================================================
%%% Error Handling Tests
%%%===================================================================

%% Test invalid decimal type string
invalid_decimal_type_test() ->
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"Decimal32(invalid)">>, 1, <<>>
    ),
    ?assertMatch({error, _}, Result).

%% Test invalid enum type string
invalid_enum_type_test() ->
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"Enum8(malformed">>, 1, <<>>
    ),
    ?assertMatch({error, _}, Result).

%% Test unknown type
unknown_type_test() ->
    Result = clickhouse_erl_protocol_data_block:decode_column_data(
        <<"UnknownType">>, 1, <<>>
    ),
    ?assertMatch({error, {unknown_column_type, <<"UnknownType">>}}, Result).
