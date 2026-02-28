%% @doc Unit tests for enum type encoding and decoding.
-module(clickhouse_erl_types_enum_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test Cases
%%%===================================================================

%% Test parse_enum_type/1 with Enum8
parse_enum8_simple_test() ->
    TypeString = <<"Enum8('active' = 1, 'inactive' = 0)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({ok, {enum8, _}}, Result),
    {ok, {enum8, Mappings}} = Result,
    ?assertEqual(1, maps:get(active, Mappings)),
    ?assertEqual(0, maps:get(inactive, Mappings)).

%% Test parse_enum_type/1 with Enum16
parse_enum16_simple_test() ->
    TypeString = <<"Enum16('status1' = 100, 'status2' = 200)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({ok, {enum16, _}}, Result),
    {ok, {enum16, Mappings}} = Result,
    ?assertEqual(100, maps:get(status1, Mappings)),
    ?assertEqual(200, maps:get(status2, Mappings)).

%% Test parse_enum_type/1 with negative values
parse_enum_negative_values_test() ->
    TypeString = <<"Enum8('positive' = 1, 'zero' = 0, 'negative' = -1)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({ok, {enum8, _}}, Result),
    {ok, {enum8, Mappings}} = Result,
    ?assertEqual(1, maps:get(positive, Mappings)),
    ?assertEqual(0, maps:get(zero, Mappings)),
    ?assertEqual(-1, maps:get(negative, Mappings)).

%% Test parse_enum_type/1 with no spaces
parse_enum_no_spaces_test() ->
    TypeString = <<"Enum8('a'=1,'b'=2)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({ok, {enum8, _}}, Result),
    {ok, {enum8, Mappings}} = Result,
    ?assertEqual(1, maps:get(a, Mappings)),
    ?assertEqual(2, maps:get(b, Mappings)).

%% Test parse_enum_type/1 with invalid type
parse_enum_invalid_type_test() ->
    TypeString = <<"Enum32('invalid' = 1)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({error, {parse_header_failed, _}}, Result).

%% Test parse_enum_type/1 with malformed mapping
parse_enum_malformed_mapping_test() ->
    TypeString = <<"Enum8('missing_value' =)">>,
    Result = clickhouse_erl_types_enum:parse_enum_type(TypeString),
    ?assertMatch({error, {parse_mappings_failed, _}}, Result).

%% Test parse_enum_type/1 with non-binary input
parse_enum_non_binary_test() ->
    Result = clickhouse_erl_types_enum:parse_enum_type("not a binary"),
    ?assertMatch({error, {invalid_type, _}}, Result).

%%%===================================================================
%%% Encoding Tests
%%%===================================================================

%% Test encode_enum8/2 with atom value
encode_enum8_atom_test() ->
    Mappings = #{active => 1, inactive => 0},
    Result = clickhouse_erl_types_enum:encode_enum8(active, Mappings),
    ?assertMatch({ok, <<1:8/signed-integer>>}, Result).

%% Test encode_enum8/2 with binary value
encode_enum8_binary_test() ->
    Mappings = #{<<"status1">> => 10, <<"status2">> => 20},
    Result = clickhouse_erl_types_enum:encode_enum8(<<"status1">>, Mappings),
    ?assertMatch({ok, <<10:8/signed-integer>>}, Result).

%% Test encode_enum8/2 with integer value
encode_enum8_integer_test() ->
    Mappings = #{active => 1, inactive => 0},
    Result = clickhouse_erl_types_enum:encode_enum8(1, Mappings),
    ?assertMatch({ok, <<1:8/signed-integer>>}, Result).

%% Test encode_enum8/2 with negative value
encode_enum8_negative_test() ->
    Mappings = #{deleted => -1, active => 1},
    Result = clickhouse_erl_types_enum:encode_enum8(deleted, Mappings),
    ?assertMatch({ok, <<-1:8/signed-integer>>}, Result).

%% Test encode_enum8/2 with value not in mappings
encode_enum8_not_found_test() ->
    Mappings = #{active => 1, inactive => 0},
    Result = clickhouse_erl_types_enum:encode_enum8(unknown, Mappings),
    ?assertMatch({error, {enum_value_not_found, _}}, Result).

%% Test encode_enum8/2 with integer not in mappings
encode_enum8_invalid_integer_test() ->
    Mappings = #{active => 1, inactive => 0},
    Result = clickhouse_erl_types_enum:encode_enum8(99, Mappings),
    ?assertMatch({error, {invalid_enum_value, _}}, Result).

%% Test encode_enum8/2 with out of range value
encode_enum8_out_of_range_test() ->
    Mappings = #{large => 200},
    Result = clickhouse_erl_types_enum:encode_enum8(large, Mappings),
    ?assertMatch({error, {value_out_of_range, _}}, Result).

%% Test encode_enum16/2 with atom value
encode_enum16_atom_test() ->
    Mappings = #{status1 => 100, status2 => 200},
    Result = clickhouse_erl_types_enum:encode_enum16(status1, Mappings),
    ?assertMatch({ok, <<100:16/little-signed-integer>>}, Result).

%% Test encode_enum16/2 with binary value
encode_enum16_binary_test() ->
    Mappings = #{<<"active">> => 1000, <<"inactive">> => 2000},
    Result = clickhouse_erl_types_enum:encode_enum16(<<"active">>, Mappings),
    ?assertMatch({ok, <<1000:16/little-signed-integer>>}, Result).

%% Test encode_enum16/2 with integer value
encode_enum16_integer_test() ->
    Mappings = #{status1 => 100, status2 => 200},
    Result = clickhouse_erl_types_enum:encode_enum16(100, Mappings),
    ?assertMatch({ok, <<100:16/little-signed-integer>>}, Result).

%% Test encode_enum16/2 with negative value
encode_enum16_negative_test() ->
    Mappings = #{deleted => -100, active => 100},
    Result = clickhouse_erl_types_enum:encode_enum16(deleted, Mappings),
    ?assertMatch({ok, <<-100:16/little-signed-integer>>}, Result).

%% Test encode_enum16/2 with value not in mappings
encode_enum16_not_found_test() ->
    Mappings = #{status1 => 100, status2 => 200},
    Result = clickhouse_erl_types_enum:encode_enum16(unknown, Mappings),
    ?assertMatch({error, {enum_value_not_found, _}}, Result).

%% Test encode_enum16/2 with integer not in mappings
encode_enum16_invalid_integer_test() ->
    Mappings = #{status1 => 100, status2 => 200},
    Result = clickhouse_erl_types_enum:encode_enum16(999, Mappings),
    ?assertMatch({error, {invalid_enum_value, _}}, Result).

%% Test encode_enum16/2 with out of range value
encode_enum16_out_of_range_test() ->
    Mappings = #{large => 40000},
    Result = clickhouse_erl_types_enum:encode_enum16(large, Mappings),
    ?assertMatch({error, {value_out_of_range, _}}, Result).

%%%===================================================================
%%% Decoding Tests
%%%===================================================================

%% Test decode_enum8/2 with valid value
decode_enum8_valid_test() ->
    Mappings = #{active => 1, inactive => 0},
    Binary = <<1:8/signed-integer, "rest">>,
    Result = clickhouse_erl_types_enum:decode_enum8(Binary, Mappings),
    ?assertMatch({ok, active, <<"rest">>}, Result).

%% Test decode_enum8/2 with negative value
decode_enum8_negative_test() ->
    Mappings = #{deleted => -1, active => 1},
    Binary = <<-1:8/signed-integer, "rest">>,
    Result = clickhouse_erl_types_enum:decode_enum8(Binary, Mappings),
    ?assertMatch({ok, deleted, <<"rest">>}, Result).

%% Test decode_enum8/2 with value not in mappings
decode_enum8_not_in_mappings_test() ->
    Mappings = #{active => 1, inactive => 0},
    Binary = <<99:8/signed-integer>>,
    Result = clickhouse_erl_types_enum:decode_enum8(Binary, Mappings),
    ?assertMatch({error, {enum_value_not_in_mappings, _}}, Result).

%% Test decode_enum8/2 with truncated data
decode_enum8_truncated_test() ->
    Mappings = #{active => 1},
    Binary = <<>>,
    Result = clickhouse_erl_types_enum:decode_enum8(Binary, Mappings),
    ?assertMatch({error, {truncated_data, _}}, Result).

%% Test decode_enum16/2 with valid value
decode_enum16_valid_test() ->
    Mappings = #{status1 => 100, status2 => 200},
    Binary = <<100:16/little-signed-integer, "rest">>,
    Result = clickhouse_erl_types_enum:decode_enum16(Binary, Mappings),
    ?assertMatch({ok, status1, <<"rest">>}, Result).

%% Test decode_enum16/2 with negative value
decode_enum16_negative_test() ->
    Mappings = #{deleted => -100, active => 100},
    Binary = <<-100:16/little-signed-integer, "rest">>,
    Result = clickhouse_erl_types_enum:decode_enum16(Binary, Mappings),
    ?assertMatch({ok, deleted, <<"rest">>}, Result).

%% Test decode_enum16/2 with value not in mappings
decode_enum16_not_in_mappings_test() ->
    Mappings = #{status1 => 100, status2 => 200},
    Binary = <<999:16/little-signed-integer>>,
    Result = clickhouse_erl_types_enum:decode_enum16(Binary, Mappings),
    ?assertMatch({error, {enum_value_not_in_mappings, _}}, Result).

%% Test decode_enum16/2 with truncated data
decode_enum16_truncated_test() ->
    Mappings = #{status1 => 100},
    Binary = <<1>>,
    Result = clickhouse_erl_types_enum:decode_enum16(Binary, Mappings),
    ?assertMatch({error, {truncated_data, _}}, Result).
