-module(clickhouse_erl_types_nullable_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Type Parsing Tests
%%%===================================================================

parse_simple_nullable_type_test() ->
    ?assertEqual(string, clickhouse_erl_types_nullable:parse_nullable_type(<<"Nullable(String)">>)),
    ?assertEqual(int64, clickhouse_erl_types_nullable:parse_nullable_type(<<"Nullable(Int64)">>)),
    ?assertEqual(uint32, clickhouse_erl_types_nullable:parse_nullable_type(<<"Nullable(UInt32)">>)).

parse_nullable_array_type_test() ->
    ?assertEqual(
        {array, string},
        clickhouse_erl_types_nullable:parse_nullable_type(<<"Nullable(Array(String))">>)
    ).

parse_nullable_tuple_type_test() ->
    ?assertEqual(
        {tuple, [string, int64]},
        clickhouse_erl_types_nullable:parse_nullable_type(<<"Nullable(Tuple(String, Int64))">>)
    ).

%%%===================================================================
%%% Encoding Tests
%%%===================================================================

encode_all_null_values_test() ->
    %% All values are null
    Values = [{null}, {null}, {null}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, int64),
    ?assert(is_binary(Encoded)),
    %% Should have 3 null mask bytes + 3 int64 placeholders (24 bytes) = 27 bytes
    ?assertEqual(27, byte_size(Encoded)).

encode_all_non_null_values_test() ->
    %% All values are non-null
    Values = [{value, 10}, {value, 20}, {value, 30}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, int64),
    ?assert(is_binary(Encoded)),
    %% Should have 3 null mask bytes + 3 int64 values (24 bytes) = 27 bytes
    ?assertEqual(27, byte_size(Encoded)).

encode_mixed_null_non_null_test() ->
    %% Mix of null and non-null values
    Values = [{value, 10}, {null}, {value, 20}, {null}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, int64),
    ?assert(is_binary(Encoded)),
    %% Should have 4 null mask bytes + 4 int64 values (32 bytes) = 36 bytes
    ?assertEqual(36, byte_size(Encoded)).

encode_nullable_strings_test() ->
    %% Nullable strings
    Values = [{value, <<"hello">>}, {null}, {value, <<"world">>}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, string),
    ?assert(is_binary(Encoded)).

encode_nullable_arrays_test() ->
    %% Nullable arrays
    Values = [{value, [1, 2, 3]}, {null}, {value, [4, 5]}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, {array, int64}),
    ?assert(is_binary(Encoded)).

encode_nullable_tuples_test() ->
    %% Nullable tuples
    Values = [{value, {<<"a">>, 1}}, {null}, {value, {<<"b">>, 2}}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(
        Values, {tuple, [string, int64]}
    ),
    ?assert(is_binary(Encoded)).

%%%===================================================================
%%% Decoding Tests
%%%===================================================================

decode_all_null_values_test() ->
    %% Encode then decode all null values
    Values = [{null}, {null}, {null}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, int64),
    {ok, Decoded, _Rest} = clickhouse_erl_types_nullable:decode_nullable_column(Encoded, int64, 3),
    ?assertEqual(Values, Decoded).

decode_all_non_null_values_test() ->
    %% Encode then decode all non-null values
    Values = [{value, 10}, {value, 20}, {value, 30}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, int64),
    {ok, Decoded, _Rest} = clickhouse_erl_types_nullable:decode_nullable_column(Encoded, int64, 3),
    ?assertEqual(Values, Decoded).

decode_mixed_null_non_null_test() ->
    %% Encode then decode mixed values
    Values = [{value, 10}, {null}, {value, 20}, {null}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, int64),
    {ok, Decoded, _Rest} = clickhouse_erl_types_nullable:decode_nullable_column(Encoded, int64, 4),
    ?assertEqual(Values, Decoded).

decode_nullable_strings_test() ->
    %% Encode then decode nullable strings
    Values = [{value, <<"hello">>}, {null}, {value, <<"world">>}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, string),
    {ok, Decoded, _Rest} = clickhouse_erl_types_nullable:decode_nullable_column(
        Encoded, string, 3
    ),
    ?assertEqual(Values, Decoded).

decode_nullable_arrays_test() ->
    %% Encode then decode nullable arrays
    Values = [{value, [1, 2, 3]}, {null}, {value, [4, 5]}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, {array, int64}),
    {ok, Decoded, _Rest} = clickhouse_erl_types_nullable:decode_nullable_column(
        Encoded, {array, int64}, 3
    ),
    ?assertEqual(Values, Decoded).

decode_nullable_tuples_test() ->
    %% Encode then decode nullable tuples
    Values = [{value, {<<"a">>, 1}}, {null}, {value, {<<"b">>, 2}}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(
        Values, {tuple, [string, int64]}
    ),
    {ok, Decoded, _Rest} = clickhouse_erl_types_nullable:decode_nullable_column(
        Encoded, {tuple, [string, int64]}, 3
    ),
    ?assertEqual(Values, Decoded).

%%%===================================================================
%%% Round Trip Tests
%%%===================================================================

roundtrip_nullable_uint8_test() ->
    Values = [{value, 1}, {null}, {value, 3}, {value, 4}, {null}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, uint8),
    {ok, Decoded, <<>>} = clickhouse_erl_types_nullable:decode_nullable_column(Encoded, uint8, 5),
    ?assertEqual(Values, Decoded).

roundtrip_nullable_float64_test() ->
    Values = [{value, 1.5}, {null}, {value, 3.5}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, float64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_nullable:decode_nullable_column(
        Encoded, float64, 3
    ),
    ?assertEqual(Values, Decoded).

roundtrip_nullable_nested_arrays_test() ->
    %% Nullable(Array(Array(Int64)))
    Values = [{value, [[1, 2], [3]]}, {null}, {value, [[4, 5, 6]]}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(
        Values, {array, {array, int64}}
    ),
    {ok, Decoded, <<>>} = clickhouse_erl_types_nullable:decode_nullable_column(
        Encoded, {array, {array, int64}}, 3
    ),
    ?assertEqual(Values, Decoded).

%%%===================================================================
%%% Edge Cases
%%%===================================================================

encode_empty_nullable_column_test() ->
    %% Empty list of nullable values
    Values = [],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, int64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_nullable:decode_nullable_column(Encoded, int64, 0),
    ?assertEqual(Values, Decoded).

encode_single_null_test() ->
    %% Single null value
    Values = [{null}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, int64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_nullable:decode_nullable_column(Encoded, int64, 1),
    ?assertEqual(Values, Decoded).

encode_single_non_null_test() ->
    %% Single non-null value
    Values = [{value, 42}],
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, int64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_nullable:decode_nullable_column(Encoded, int64, 1),
    ?assertEqual(Values, Decoded).

encode_many_nulls_test() ->
    %% Many null values
    Values = lists:duplicate(100, {null}),
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, int64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_nullable:decode_nullable_column(
        Encoded, int64, 100
    ),
    ?assertEqual(Values, Decoded).

encode_alternating_null_non_null_test() ->
    %% Alternating null and non-null
    Values = lists:flatten([[{value, N}, {null}] || N <- lists:seq(1, 50)]),
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(Values, int64),
    {ok, Decoded, <<>>} = clickhouse_erl_types_nullable:decode_nullable_column(
        Encoded, int64, 100
    ),
    ?assertEqual(Values, Decoded).
