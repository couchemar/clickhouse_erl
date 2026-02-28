%% @doc Tests for ClickHouse column type encoding functions.
%%
%% This module contains tests specifically for the clickhouse_erl_types_column module,
%% which handles column-oriented data encoding for bulk operations.
-module(clickhouse_erl_types_column_tests).

-include_lib("eunit/include/eunit.hrl").

%% ============================================================================
%% UInt8 Column Tests
%% ============================================================================

%% Test UInt8 column encoding
encode_uint8_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_uint8_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_uint8_column([42]),
    ?assertEqual([<<42>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_uint8_column([0, 1, 255]),
    ?assertEqual([<<0>>, <<1>>, <<255>>], Result3),

    %% Error case - value out of range
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_uint8_column([256])
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_uint8_column([0, 1, -1])
    ).

%% ============================================================================
%% UInt16 Column Tests
%% ============================================================================

%% Test UInt16 column encoding
encode_uint16_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_uint16_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_uint16_column([1000]),
    ?assertEqual([<<232, 3>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_uint16_column([0, 256, 65535]),
    ?assertEqual([<<0, 0>>, <<0, 1>>, <<255, 255>>], Result3),

    %% Error case - value out of range
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_uint16_column([65536])
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_uint16_column([0, -1])
    ).

%% ============================================================================
%% UInt32 Column Tests
%% ============================================================================

%% Test UInt32 column encoding
encode_uint32_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_uint32_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_uint32_column([1000000]),
    ?assertEqual([<<64, 66, 15, 0>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_uint32_column([0, 65536, 4294967295]),
    ?assertEqual([<<0, 0, 0, 0>>, <<0, 0, 1, 0>>, <<255, 255, 255, 255>>], Result3),

    %% Error case - value out of range
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_uint32_column([4294967296])
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_uint32_column([0, -1])
    ).

%% ============================================================================
%% UInt64 Column Tests
%% ============================================================================

%% Test UInt64 column encoding
encode_uint64_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_uint64_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_uint64_column([1000000000]),
    ?assertEqual([<<0, 202, 154, 59, 0, 0, 0, 0>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_uint64_column([
        0, 4294967296, 18446744073709551615
    ]),
    ?assertEqual(
        [
            <<0, 0, 0, 0, 0, 0, 0, 0>>,
            <<0, 0, 0, 0, 1, 0, 0, 0>>,
            <<255, 255, 255, 255, 255, 255, 255, 255>>
        ],
        Result3
    ),

    %% Error case - value out of range
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_uint64_column([18446744073709551616])
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_uint64_column([0, -1])
    ).

%% ============================================================================
%% Int8 Column Tests
%% ============================================================================

%% Test Int8 column encoding
encode_int8_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_int8_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_int8_column([-42]),
    ?assertEqual([<<214>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_int8_column([-128, 0, 127]),
    ?assertEqual([<<128>>, <<0>>, <<127>>], Result3),

    %% Error case - value out of range
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_int8_column([128])
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_int8_column([0, -129])
    ).

%% ============================================================================
%% Int16 Column Tests
%% ============================================================================

%% Test Int16 column encoding
encode_int16_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_int16_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_int16_column([-1000]),
    ?assertEqual([<<24, 252>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_int16_column([-32768, 0, 32767]),
    ?assertEqual([<<0, 128>>, <<0, 0>>, <<255, 127>>], Result3),

    %% Error case - value out of range
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_int16_column([32768])
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_int16_column([0, -32769])
    ).

%% ============================================================================
%% Int32 Column Tests
%% ============================================================================

%% Test Int32 column encoding
encode_int32_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_int32_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_int32_column([-1000000]),
    ?assertEqual([<<192, 189, 240, 255>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_int32_column([-2147483648, 0, 2147483647]),
    ?assertEqual([<<0, 0, 0, 128>>, <<0, 0, 0, 0>>, <<255, 255, 255, 127>>], Result3),

    %% Error case - value out of range
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_int32_column([2147483648])
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_int32_column([0, -2147483649])
    ).

%% ============================================================================
%% Int64 Column Tests
%% ============================================================================

%% Test Int64 column encoding
encode_int64_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_int64_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_int64_column([-1000000000]),
    ?assertEqual([<<0, 54, 101, 196, 255, 255, 255, 255>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_int64_column([
        -9223372036854775808, 0, 9223372036854775807
    ]),
    ?assertEqual(
        [
            <<0, 0, 0, 0, 0, 0, 0, 128>>,
            <<0, 0, 0, 0, 0, 0, 0, 0>>,
            <<255, 255, 255, 255, 255, 255, 255, 127>>
        ],
        Result3
    ),

    %% Error case - value out of range
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_int64_column([9223372036854775808])
    ),
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_int64_column([0, -9223372036854775809])
    ).

%% ============================================================================
%% Float32 Column Tests
%% ============================================================================

%% Test Float32 column encoding
encode_float32_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_float32_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_float32_column([3.14]),
    ?assertEqual([<<195, 245, 72, 64>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_float32_column([0.0, 1.0, -2.0]),
    ?assertEqual([<<0, 0, 0, 0>>, <<0, 0, 128, 63>>, <<0, 0, 0, 192>>], Result3),

    %% Special values
    {ok, Result4} = clickhouse_erl_types_column:encode_float32_column([infinity, '-infinity', nan]),
    ?assertEqual([<<0, 0, 128, 127>>, <<0, 0, 128, 255>>, <<0, 0, 192, 127>>], Result4),

    %% Integer values (should be converted to float)
    {ok, Result5} = clickhouse_erl_types_column:encode_float32_column([1, 2, 3]),
    Flattened = iolist_to_binary(Result5),
    ?assertEqual(<<0, 0, 128, 63, 0, 0, 0, 64, 0, 0, 64, 64>>, Flattened),

    %% Error case - invalid value
    ?assertMatch(
        {error, {invalid_value, _}},
        clickhouse_erl_types_column:encode_float32_column([not_a_number])
    ).

%% ============================================================================
%% Float64 Column Tests
%% ============================================================================

%% Test Float64 column encoding
encode_float64_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_float64_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_float64_column([3.14159265359]),
    ?assertEqual([<<234, 46, 68, 84, 251, 33, 9, 64>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_float64_column([0.0, 1.0, -2.0]),
    ?assertEqual(
        [<<0, 0, 0, 0, 0, 0, 0, 0>>, <<0, 0, 0, 0, 0, 0, 240, 63>>, <<0, 0, 0, 0, 0, 0, 0, 192>>],
        Result3
    ),

    %% Special values
    {ok, Result4} = clickhouse_erl_types_column:encode_float64_column([infinity, '-infinity', nan]),
    ?assertEqual(
        [
            <<0, 0, 0, 0, 0, 0, 240, 127>>,
            <<0, 0, 0, 0, 0, 0, 240, 255>>,
            <<0, 0, 0, 0, 0, 0, 248, 127>>
        ],
        Result4
    ),

    %% Integer values (should be converted to float)
    {ok, Result5} = clickhouse_erl_types_column:encode_float64_column([1, 2, 3]),
    Flattened = iolist_to_binary(Result5),
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 240, 63, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 8, 64>>,
        Flattened
    ),

    %% Error case - invalid value
    ?assertMatch(
        {error, {invalid_value, _}},
        clickhouse_erl_types_column:encode_float64_column([not_a_number])
    ).

%% ============================================================================
%% String Column Tests
%% ============================================================================

%% Test String Column Encoder
encode_string_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_string_column([]),
    ?assertEqual([], Result1),

    %% Single string value
    {ok, Result2} = clickhouse_erl_types_column:encode_string_column(["hello"]),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(<<5, "hello">>, Flattened2),

    %% Multiple string values (mixed string and binary)
    {ok, Result3} = clickhouse_erl_types_column:encode_string_column(["hello", <<"world">>, ""]),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(<<5, "hello", 5, "world", 0>>, Flattened3),

    %% Unicode strings
    {ok, Result4} = clickhouse_erl_types_column:encode_string_column(["тест", "数据库"]),
    Flattened4 = iolist_to_binary(Result4),
    %% тест is 8 bytes in UTF-8, 数据库 is 9 bytes
    ?assertEqual(<<8, "тест"/utf8, 9, "数据库"/utf8>>, Flattened4),

    %% Long strings
    LongString = lists:duplicate(1000, $a),
    {ok, Result5} = clickhouse_erl_types_column:encode_string_column([LongString]),
    Flattened5 = iolist_to_binary(Result5),
    %% 1000 encoded as varint is 2 bytes (232, 7), plus 1000 bytes of data
    ?assertEqual(1002, byte_size(Flattened5)),

    %% Error case - invalid value (not a string or binary)
    ?assertMatch({error, _}, clickhouse_erl_types_column:encode_string_column([123])).

%% ============================================================================
%% Date Column Tests
%% ============================================================================

%% Test Date column encoding
encode_date_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_date_column([]),
    ?assertEqual([], Result1),

    %% Single value - 1970-01-01 (epoch)
    {ok, Result2} = clickhouse_erl_types_column:encode_date_column([{1970, 1, 1}]),
    ?assertEqual([<<0, 0>>], Result2),

    %% Single value - 1970-01-02 (1 day after epoch)
    {ok, Result3} = clickhouse_erl_types_column:encode_date_column([{1970, 1, 2}]),
    ?assertEqual([<<1, 0>>], Result3),

    %% Multiple values
    {ok, Result4} = clickhouse_erl_types_column:encode_date_column([
        {1970, 1, 1},
        {2020, 1, 1},
        {2149, 6, 6}
    ]),
    ?assertEqual(
        [
            <<0, 0>>,
            % 2020-01-01 -> 18262 days
            <<86, 71>>,
            % 2149-06-06 -> 65535 days (max UInt16)
            <<255, 255>>
        ],
        Result4
    ),

    %% Error case - invalid date
    ?assertMatch(
        {error, {invalid_date, _}},
        clickhouse_erl_types_column:encode_date_column([{2023, 2, 30}])
    ),

    %% Error case - date too early (before 1970)
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_date_column([{1969, 12, 31}])
    ),

    %% Error case - date too late (overflow UInt16)
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_date_column([{2150, 1, 1}])
    ),

    %% Error case - invalid structure
    ?assertMatch(
        {error, {invalid_value, _}},
        clickhouse_erl_types_column:encode_date_column([not_a_date])
    ).

%% ============================================================================
%% DateTime Column Tests
%% ============================================================================

%% Test DateTime column encoding
encode_datetime_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_datetime_column([]),
    ?assertEqual([], Result1),

    %% Single value - 1970-01-01 00:00:00 (epoch)
    {ok, Result2} = clickhouse_erl_types_column:encode_datetime_column([{{1970, 1, 1}, {0, 0, 0}}]),
    ?assertEqual([<<0, 0, 0, 0>>], Result2),

    %% Single value - 1970-01-01 00:00:01 (1 second after epoch)
    {ok, Result3} = clickhouse_erl_types_column:encode_datetime_column([{{1970, 1, 1}, {0, 0, 1}}]),
    ?assertEqual([<<1, 0, 0, 0>>], Result3),

    %% Single value - 2020-01-01 12:00:00
    {ok, Result4} = clickhouse_erl_types_column:encode_datetime_column([{{2020, 1, 1}, {12, 0, 0}}]),
    % 1577880000 seconds -> 0x5E0C89C0 -> <<192, 137, 12, 94>>
    ?assertEqual([<<192, 137, 12, 94>>], Result4),

    %% Multiple values
    {ok, Result5} = clickhouse_erl_types_column:encode_datetime_column([
        {{1970, 1, 1}, {0, 0, 0}},
        {{2000, 1, 1}, {0, 0, 0}},
        {{2020, 1, 1}, {12, 0, 0}}
    ]),
    ?assertEqual(
        [
            <<0, 0, 0, 0>>,
            % 2000-01-01 00:00:00 -> 946684800 seconds
            <<128, 67, 109, 56>>,
            % 2020-01-01 12:00:00 -> 1577880000 seconds
            <<192, 137, 12, 94>>
        ],
        Result5
    ),

    %% Error case - invalid datetime (invalid hour)
    ?assertMatch(
        {error, {invalid_datetime, _}},
        clickhouse_erl_types_column:encode_datetime_column([{{2020, 1, 1}, {25, 0, 0}}])
    ),

    %% Error case - invalid datetime (invalid minute)
    ?assertMatch(
        {error, {invalid_datetime, _}},
        clickhouse_erl_types_column:encode_datetime_column([{{2020, 1, 1}, {12, 60, 0}}])
    ),

    %% Error case - invalid datetime (invalid second)
    ?assertMatch(
        {error, {invalid_datetime, _}},
        clickhouse_erl_types_column:encode_datetime_column([{{2020, 1, 1}, {12, 0, 60}}])
    ),

    %% Error case - invalid date component
    ?assertMatch(
        {error, {invalid_datetime, _}},
        clickhouse_erl_types_column:encode_datetime_column([{{2023, 2, 30}, {12, 0, 0}}])
    ),

    %% Error case - datetime too early (before 1970)
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_datetime_column([{{1969, 12, 31}, {23, 59, 59}}])
    ),

    %% Error case - datetime too late (overflow UInt32)
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_datetime_column([{{2107, 1, 1}, {0, 0, 0}}])
    ),

    %% Error case - invalid structure
    ?assertMatch(
        {error, {invalid_value, _}},
        clickhouse_erl_types_column:encode_datetime_column([not_a_datetime])
    ).

%% ============================================================================
%% Column Encoding IOList Tests
%% ============================================================================

%% Test column encoding with iolist flattening
column_encoding_iolist_test() ->
    %% Verify that column encoders return iolists that can be flattened
    {ok, UInt8Result} = clickhouse_erl_types_column:encode_uint8_column([1, 2, 3]),
    Flattened1 = iolist_to_binary(UInt8Result),
    ?assertEqual(<<1, 2, 3>>, Flattened1),

    {ok, UInt32Result} = clickhouse_erl_types_column:encode_uint32_column([1, 2, 3]),
    Flattened2 = iolist_to_binary(UInt32Result),
    ?assertEqual(<<1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0>>, Flattened2),

    {ok, Int64Result} = clickhouse_erl_types_column:encode_int64_column([-1, 0, 1]),
    Flattened3 = iolist_to_binary(Int64Result),
    ?assertEqual(
        <<255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0>>,
        Flattened3
    ),

    %% Test float column encoders
    {ok, Float32Result} = clickhouse_erl_types_column:encode_float32_column([1.0, 2.0, 3.0]),
    Flattened4 = iolist_to_binary(Float32Result),
    ?assertEqual(<<0, 0, 128, 63, 0, 0, 0, 64, 0, 0, 64, 64>>, Flattened4),

    {ok, Float64Result} = clickhouse_erl_types_column:encode_float64_column([1.0, 2.0, 3.0]),
    Flattened5 = iolist_to_binary(Float64Result),
    ?assertEqual(
        <<0, 0, 0, 0, 0, 0, 240, 63, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 8, 64>>,
        Flattened5
    ).

%% Test Date column encoding with iolist flattening
date_column_encoding_iolist_test() ->
    %% Verify that date column encoder returns iolist that can be flattened
    {ok, DateResult} = clickhouse_erl_types_column:encode_date_column([
        {1970, 1, 1},
        {1970, 1, 2},
        {2020, 1, 1}
    ]),
    Flattened = iolist_to_binary(DateResult),
    % 0 days, 1 day, 18262 days
    ?assertEqual(<<0, 0, 1, 0, 86, 71>>, Flattened).

%% Test DateTime column encoding with iolist flattening
datetime_column_encoding_iolist_test() ->
    %% Verify that datetime column encoder returns iolist that can be flattened
    {ok, DateTimeResult} = clickhouse_erl_types_column:encode_datetime_column([
        {{1970, 1, 1}, {0, 0, 0}},
        {{1970, 1, 1}, {0, 0, 1}},
        {{2020, 1, 1}, {12, 0, 0}}
    ]),
    Flattened = iolist_to_binary(DateTimeResult),
    % 0 seconds, 1 second, 1577880000 seconds
    ?assertEqual(<<0, 0, 0, 0, 1, 0, 0, 0, 192, 137, 12, 94>>, Flattened).

%% ============================================================================
%% Boundary Value Tests
%% ============================================================================

%% Test Date column encoding with boundary values
date_column_boundary_test() ->
    %% Test minimum date (1970-01-01)
    {ok, MinResult} = clickhouse_erl_types_column:encode_date_column([{1970, 1, 1}]),
    ?assertEqual([<<0, 0>>], MinResult),

    %% Test maximum date (2149-06-06 - max UInt16 days)
    {ok, MaxResult} = clickhouse_erl_types_column:encode_date_column([{2149, 6, 6}]),
    ?assertEqual([<<255, 255>>], MaxResult),

    %% Test leap year date
    {ok, LeapResult} = clickhouse_erl_types_column:encode_date_column([{2020, 2, 29}]),
    Flattened = iolist_to_binary(LeapResult),
    ?assertEqual(2, byte_size(Flattened)).

%% Test DateTime column encoding with boundary values
datetime_column_boundary_test() ->
    %% Test minimum datetime (1970-01-01 00:00:00)
    {ok, MinResult} = clickhouse_erl_types_column:encode_datetime_column([{{1970, 1, 1}, {0, 0, 0}}]),
    ?assertEqual([<<0, 0, 0, 0>>], MinResult),

    %% Test datetime with all time components
    {ok, FullResult} = clickhouse_erl_types_column:encode_datetime_column([
        {{2020, 12, 31}, {23, 59, 59}}
    ]),
    Flattened = iolist_to_binary(FullResult),
    ?assertEqual(4, byte_size(Flattened)),

    %% Test leap year datetime
    {ok, LeapResult} = clickhouse_erl_types_column:encode_datetime_column([
        {{2020, 2, 29}, {12, 30, 45}}
    ]),
    Flattened2 = iolist_to_binary(LeapResult),
    ?assertEqual(4, byte_size(Flattened2)).

%% ============================================================================
%% Consistency Tests
%% ============================================================================

%% Test Date column encoding consistency with single value encoder
date_column_consistency_test() ->
    %% Verify column encoder produces same result as single value encoder
    Dates = [{1970, 1, 1}, {2020, 1, 1}, {2149, 6, 6}],
    {ok, ColumnResult} = clickhouse_erl_types_column:encode_date_column(Dates),
    ColumnBinary = iolist_to_binary(ColumnResult),

    %% Encode each date individually and concatenate
    SingleResults = [clickhouse_erl_types_temporal:encode_date(D) || D <- Dates],
    SingleBinary = iolist_to_binary(SingleResults),

    ?assertEqual(SingleBinary, ColumnBinary).

%% Test DateTime column encoding consistency with single value encoder
datetime_column_consistency_test() ->
    %% Verify column encoder produces same result as single value encoder
    DateTimes = [
        {{1970, 1, 1}, {0, 0, 0}},
        {{2000, 1, 1}, {0, 0, 0}},
        {{2020, 1, 1}, {12, 0, 0}}
    ],
    {ok, ColumnResult} = clickhouse_erl_types_column:encode_datetime_column(DateTimes),
    ColumnBinary = iolist_to_binary(ColumnResult),

    %% Encode each datetime individually and concatenate
    SingleResults = [clickhouse_erl_types_temporal:encode_datetime(DT) || DT <- DateTimes],
    SingleBinary = iolist_to_binary(SingleResults),

    ?assertEqual(SingleBinary, ColumnBinary).

%% ============================================================================
%% Comprehensive Column Encoder Tests
%% ============================================================================

%% Test Integer Column Encoders
encode_integer_columns_test() ->
    %% UInt8
    ?assertMatch({ok, _}, clickhouse_erl_types_column:encode_uint8_column([0, 1, 255])),
    ?assertMatch({error, _}, clickhouse_erl_types_column:encode_uint8_column([256])),

    %% UInt16
    ?assertMatch({ok, _}, clickhouse_erl_types_column:encode_uint16_column([0, 65535])),
    ?assertMatch({error, _}, clickhouse_erl_types_column:encode_uint16_column([65536])),

    %% UInt32
    ?assertMatch({ok, _}, clickhouse_erl_types_column:encode_uint32_column([0, 4294967295])),
    ?assertMatch({error, _}, clickhouse_erl_types_column:encode_uint32_column([-1])),

    %% UInt64
    ?assertMatch(
        {ok, _}, clickhouse_erl_types_column:encode_uint64_column([0, 18446744073709551615])
    ),
    % Bignum that doesn't fit in 64 bits
    ?assertMatch(
        {error, _}, clickhouse_erl_types_column:encode_uint64_column([18446744073709551616])
    ),
    % Negative
    ?assertMatch({error, _}, clickhouse_erl_types_column:encode_uint64_column([-1])),

    %% Int8
    ?assertMatch({ok, _}, clickhouse_erl_types_column:encode_int8_column([-128, 127])),
    ?assertMatch({error, _}, clickhouse_erl_types_column:encode_int8_column([128])),

    %% Int16
    ?assertMatch({ok, _}, clickhouse_erl_types_column:encode_int16_column([-32768, 32767])),

    %% Int32
    ?assertMatch(
        {ok, _}, clickhouse_erl_types_column:encode_int32_column([-2147483648, 2147483647])
    ),

    %% Int64
    ?assertMatch(
        {ok, _},
        clickhouse_erl_types_column:encode_int64_column([-9223372036854775808, 9223372036854775807])
    ),
    % Too large
    ?assertMatch(
        {error, _}, clickhouse_erl_types_column:encode_int64_column([9223372036854775808])
    ),
    % Too small
    ?assertMatch(
        {error, _}, clickhouse_erl_types_column:encode_int64_column([-9223372036854775809])
    ).

%% Test Float Column Encoders
encode_float_columns_test() ->
    %% Float32
    ?assertMatch(
        {ok, _}, clickhouse_erl_types_column:encode_float32_column([0.0, 1.5, -1.5, infinity, nan])
    ),
    ?assertMatch({error, _}, clickhouse_erl_types_column:encode_float32_column([not_a_number])),

    %% Float64
    ?assertMatch(
        {ok, _}, clickhouse_erl_types_column:encode_float64_column([0.0, 1.23456789, infinity, nan])
    ).

%% Test Temporal Column Encoders
encode_temporal_columns_test() ->
    %% Date
    ?assertMatch(
        {ok, _}, clickhouse_erl_types_column:encode_date_column([{2023, 1, 1}, {1970, 1, 1}])
    ),
    ?assertMatch({error, _}, clickhouse_erl_types_column:encode_date_column([{2023, 2, 30}])),

    %% Date32
    ?assertMatch({ok, _}, clickhouse_erl_types_column:encode_date32_column([{2023, 1, 1}])),

    %% DateTime
    ?assertMatch(
        {ok, _}, clickhouse_erl_types_column:encode_datetime_column([{{2023, 1, 1}, {12, 0, 0}}])
    ),

    %% DateTime64 - now requires precision parameter
    ?assertMatch({ok, _}, clickhouse_erl_types_column:encode_datetime64_column([1672574400000], 3)).

%% ============================================================================
%% Extended Integer Column Tests
%% ============================================================================

%% Test Int128 column encoding
encode_int128_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_int128_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_int128_column([42]),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(16, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_int128_column([0, 1, -1]),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(48, byte_size(Flattened3)),

    %% Error case - value out of range
    ?assertMatch(
        {error, {value_out_of_range, _}},
        clickhouse_erl_types_column:encode_int128_column([1 bsl 127])
    ).

%% Test UInt128 column encoding
encode_uint128_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_uint128_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_uint128_column([42]),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(16, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_uint128_column([0, 1, 255]),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(48, byte_size(Flattened3)),

    %% Error case - negative value
    ?assertMatch(
        {error, {invalid_value, _}},
        clickhouse_erl_types_column:encode_uint128_column([-1])
    ).

%% Test Int256 column encoding
encode_int256_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_int256_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_int256_column([42]),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(32, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_int256_column([0, 1, -1]),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(96, byte_size(Flattened3)).

%% Test UInt256 column encoding
encode_uint256_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_uint256_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_uint256_column([42]),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(32, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_uint256_column([0, 1, 255]),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(96, byte_size(Flattened3)).

%% ============================================================================
%% Decimal Column Tests
%% ============================================================================

%% Test Decimal32 column encoding
encode_decimal32_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_decimal32_column([], 2),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_decimal32_column([{decimal, 12345, 2}], 2),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(4, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_decimal32_column(
        [{decimal, 100, 2}, {decimal, 200, 2}, {decimal, -100, 2}], 2
    ),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(12, byte_size(Flattened3)).

%% Test Decimal64 column encoding
encode_decimal64_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_decimal64_column([], 4),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_decimal64_column(
        [{decimal, 123456789, 4}], 4
    ),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(8, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_decimal64_column(
        [{decimal, 1000, 4}, {decimal, 2000, 4}], 4
    ),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(16, byte_size(Flattened3)).

%% Test Decimal128 column encoding
encode_decimal128_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_decimal128_column([], 10),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_decimal128_column(
        [{decimal, 123456789012345, 10}], 10
    ),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(16, byte_size(Flattened2)).

%% Test Decimal256 column encoding
encode_decimal256_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_decimal256_column([], 20),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_decimal256_column(
        [{decimal, 123456789012345678901234567890, 20}], 20
    ),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(32, byte_size(Flattened2)).

%% ============================================================================
%% Enum Column Tests
%% ============================================================================

%% Test Enum8 column encoding
encode_enum8_column_test() ->
    Mappings = #{active => 1, inactive => 0, pending => 2},

    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_enum8_column([], Mappings),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_enum8_column([active], Mappings),
    ?assertEqual([<<1>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_enum8_column(
        [active, inactive, pending], Mappings
    ),
    ?assertEqual([<<1>>, <<0>>, <<2>>], Result3),

    %% Error case - invalid value
    ?assertMatch(
        {error, {enum_value_not_found, _}},
        clickhouse_erl_types_column:encode_enum8_column([unknown], Mappings)
    ).

%% Test Enum16 column encoding
encode_enum16_column_test() ->
    Mappings = #{low => -100, medium => 0, high => 100},

    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_enum16_column([], Mappings),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_enum16_column([medium], Mappings),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(2, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_enum16_column([low, medium, high], Mappings),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(6, byte_size(Flattened3)).

%% ============================================================================
%% Network Type Column Tests
%% ============================================================================

%% Test IPv4 column encoding
encode_ipv4_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_ipv4_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_ipv4_column([{192, 168, 1, 1}]),
    ?assertEqual([<<192, 168, 1, 1>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_ipv4_column([
        {192, 168, 1, 1},
        {10, 0, 0, 1},
        {127, 0, 0, 1}
    ]),
    ?assertEqual([<<192, 168, 1, 1>>, <<10, 0, 0, 1>>, <<127, 0, 0, 1>>], Result3),

    %% Error case - invalid octet
    ?assertMatch(
        {error, {invalid_ipv4_octet, _}},
        clickhouse_erl_types_column:encode_ipv4_column([{256, 0, 0, 1}])
    ).

%% Test IPv6 column encoding
encode_ipv6_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_ipv6_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_ipv6_column([{8193, 3512, 0, 0, 0, 0, 0, 1}]),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(16, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_ipv6_column([
        {0, 0, 0, 0, 0, 0, 0, 1},
        {8193, 3512, 0, 0, 0, 0, 0, 1}
    ]),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(32, byte_size(Flattened3)).

%% ============================================================================
%% UUID Column Tests
%% ============================================================================

%% Test UUID column encoding
encode_uuid_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_uuid_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_uuid_column([
        <<"550e8400-e29b-41d4-a716-446655440000">>
    ]),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(16, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_uuid_column([
        <<"550e8400-e29b-41d4-a716-446655440000">>,
        <<"6ba7b810-9dad-11d1-80b4-00c04fd430c8">>
    ]),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(32, byte_size(Flattened3)),

    %% Error case - invalid UUID
    ?assertMatch(
        {error, {invalid_uuid_format, _}},
        clickhouse_erl_types_column:encode_uuid_column([<<"not-a-uuid">>])
    ).

%% ============================================================================
%% Time Column Tests
%% ============================================================================

%% Test Time column encoding
encode_time_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_time_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_time_column([{12, 30, 45}]),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(4, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_time_column([
        {0, 0, 0},
        {12, 30, 45},
        {23, 59, 59}
    ]),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(12, byte_size(Flattened3)),

    %% Error case - invalid time
    ?assertMatch(
        {error, {invalid_hour, _}},
        clickhouse_erl_types_column:encode_time_column([{24, 0, 0}])
    ).

%% Test Time64 column encoding
encode_time64_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_time64_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_time64_column([{12, 30, 45, 123456789}]),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(8, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_time64_column([
        {0, 0, 0, 0},
        {12, 30, 45, 123456789}
    ]),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(16, byte_size(Flattened3)).

%% ============================================================================
%% Special Type Column Tests
%% ============================================================================

%% Test Nothing column encoding
encode_nothing_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_nothing_column([]),
    ?assertEqual([], Result1),

    %% Single value (any value accepted)
    {ok, Result2} = clickhouse_erl_types_column:encode_nothing_column([anything]),
    ?assertEqual([<<0>>], Result2),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_nothing_column([1, 2, 3]),
    ?assertEqual([<<0>>, <<0>>, <<0>>], Result3).

%% Test Point column encoding
encode_point_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_point_column([]),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_point_column([{1.5, 2.5}]),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(16, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_point_column([{0.0, 0.0}, {1.5, 2.5}]),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(32, byte_size(Flattened3)),

    %% Error case - invalid point
    ?assertMatch(
        {error, {invalid_format, _}},
        clickhouse_erl_types_column:encode_point_column([{not_a_float, 2.5}])
    ).

%% Test Interval column encoding
encode_interval_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_interval_column([], second),
    ?assertEqual([], Result1),

    %% Single value
    {ok, Result2} = clickhouse_erl_types_column:encode_interval_column(
        [{interval, second, 3600}], second
    ),
    Flattened2 = iolist_to_binary(Result2),
    ?assertEqual(8, byte_size(Flattened2)),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_interval_column(
        [{interval, day, 1}, {interval, day, 7}], day
    ),
    Flattened3 = iolist_to_binary(Result3),
    ?assertEqual(16, byte_size(Flattened3)),

    %% Error case - invalid scale
    ?assertMatch(
        {error, {invalid_scale, _}},
        clickhouse_erl_types_column:encode_interval_column([{interval, invalid, 1}], invalid)
    ).

%% Test JSON column encoding
encode_json_column_test() ->
    %% Empty column
    {ok, Result1} = clickhouse_erl_types_column:encode_json_column([]),
    ?assertEqual([], Result1),

    %% Single value - binary string
    {ok, Result2} = clickhouse_erl_types_column:encode_json_column([<<"{\"key\":\"value\"}">>]),
    Flattened2 = iolist_to_binary(Result2),
    ?assert(byte_size(Flattened2) > 0),

    %% Multiple values
    {ok, Result3} = clickhouse_erl_types_column:encode_json_column([
        <<"{\"a\":1}">>,
        <<"{\"b\":2}">>
    ]),
    Flattened3 = iolist_to_binary(Result3),
    ?assert(byte_size(Flattened3) > 0),

    %% Error case - invalid JSON
    ?assertMatch(
        {error, {invalid_json, _}},
        clickhouse_erl_types_column:encode_json_column([<<"{invalid">>])
    ).
