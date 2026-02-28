%% @doc Unit tests for composite type composition.
%%
%% Tests nested composite types including:
%% - Array(Nullable(String))
%% - Nullable(Array(Int64))
%% - Array(Tuple(String, Int64))
%% - Map(String, Array(Int64))
%% - Tuple(Array(String), Map(String, Int64))
%% - Array(LowCardinality(String))
-module(clickhouse_erl_types_composition_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Array(Nullable(String)) Tests
%%%===================================================================

array_nullable_string_encode_decode_test() ->
    %% Test data: array of nullable strings
    Data = [
        [{value, <<"hello">>}, {null}, {value, <<"world">>}],
        [{value, <<"foo">>}],
        [],
        [{null}, {null}]
    ],

    %% Encode
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(
        Data,
        {nullable, string}
    ),

    %% Decode
    {ok, Decoded, <<>>} = clickhouse_erl_types_array:decode_array_column(
        Encoded,
        {nullable, string},
        length(Data)
    ),

    ?assertEqual(Data, Decoded).

%%%===================================================================
%%% Nullable(Array(Int64)) Tests
%%%===================================================================

nullable_array_int64_encode_decode_test() ->
    %% Test data: nullable arrays of integers
    Data = [
        {value, [1, 2, 3]},
        {null},
        {value, []},
        {value, [42]}
    ],

    %% Encode
    {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(
        Data,
        {array, int64}
    ),

    %% Decode
    {ok, Decoded, <<>>} = clickhouse_erl_types_nullable:decode_nullable_column(
        Encoded,
        {array, int64},
        length(Data)
    ),

    ?assertEqual(Data, Decoded).

%%%===================================================================
%%% Array(Tuple(String, Int64)) Tests
%%%===================================================================

array_tuple_encode_decode_test() ->
    %% Test data: array of tuples
    Data = [
        [{<<"alice">>, 25}, {<<"bob">>, 30}],
        [{<<"charlie">>, 35}],
        []
    ],

    %% Encode
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(
        Data,
        {tuple, [string, int64]}
    ),

    %% Decode
    {ok, Decoded, <<>>} = clickhouse_erl_types_array:decode_array_column(
        Encoded,
        {tuple, [string, int64]},
        length(Data)
    ),

    ?assertEqual(Data, Decoded).

%%%===================================================================
%%% Map(String, Array(Int64)) Tests
%%%===================================================================

map_string_array_encode_decode_test() ->
    %% Test data: maps with array values
    Data = [
        #{<<"key1">> => [1, 2, 3], <<"key2">> => [4, 5]},
        #{<<"key3">> => []},
        #{}
    ],

    %% Encode
    {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(
        Data,
        string,
        {array, int64}
    ),

    %% Decode
    {ok, Decoded, <<>>} = clickhouse_erl_types_map:decode_map_column(
        Encoded,
        string,
        {array, int64},
        length(Data)
    ),

    ?assertEqual(Data, Decoded).

%%%===================================================================
%%% Tuple(Array(String), Map(String, Int64)) Tests
%%%===================================================================

tuple_array_map_encode_decode_test() ->
    %% Test data: tuples with array and map elements
    Data = [
        {[<<"a">>, <<"b">>], #{<<"x">> => 1, <<"y">> => 2}},
        {[], #{}},
        {[<<"c">>], #{<<"z">> => 3}}
    ],

    %% Encode
    {ok, Encoded} = clickhouse_erl_types_tuple:encode_tuple_column(
        Data,
        [{array, string}, {map, string, int64}]
    ),

    %% Decode
    {ok, Decoded, <<>>} = clickhouse_erl_types_tuple:decode_tuple_column(
        Encoded,
        [{array, string}, {map, string, int64}],
        length(Data)
    ),

    ?assertEqual(Data, Decoded).

%%%===================================================================
%%% Array(LowCardinality(String)) Tests
%%%===================================================================

array_low_cardinality_encode_decode_test() ->
    %% Test data: arrays of low cardinality strings
    Data = [
        [<<"foo">>, <<"bar">>, <<"foo">>],
        [<<"baz">>],
        []
    ],

    %% Encode
    {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(
        Data,
        {low_cardinality, string}
    ),

    %% Decode
    {ok, Decoded, <<>>} = clickhouse_erl_types_array:decode_array_column(
        Encoded,
        {low_cardinality, string},
        length(Data)
    ),

    %% Verify round trip
    ?assertEqual(Data, Decoded).
