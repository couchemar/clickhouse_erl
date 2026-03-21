-module(clickhouse_erl_types_low_cardinality_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Type Parsing Tests
%%%===================================================================

parse_low_cardinality_string_test() ->
    ?assertEqual(
        string,
        clickhouse_erl_types_low_cardinality:parse_low_cardinality_type(
            <<"LowCardinality(String)">>
        )
    ).

parse_low_cardinality_int64_test() ->
    ?assertEqual(
        int64,
        clickhouse_erl_types_low_cardinality:parse_low_cardinality_type(<<"LowCardinality(Int64)">>)
    ).

parse_low_cardinality_uint32_test() ->
    ?assertEqual(
        uint32,
        clickhouse_erl_types_low_cardinality:parse_low_cardinality_type(
            <<"LowCardinality(UInt32)">>
        )
    ).

%%%===================================================================
%%% Dictionary Building Tests
%%%===================================================================

build_dictionary_unique_values_test() ->
    Values = [<<"foo">>, <<"bar">>, <<"baz">>],
    Dict = clickhouse_erl_types_low_cardinality:build_dictionary(Values),
    %% Dictionary should contain only the unique values from input
    ?assertEqual([<<"foo">>, <<"bar">>, <<"baz">>], Dict).

build_dictionary_with_duplicates_test() ->
    Values = [<<"foo">>, <<"foo">>, <<"bar">>, <<"bar">>, <<"bar">>, <<"foo">>],
    Dict = clickhouse_erl_types_low_cardinality:build_dictionary(Values),
    %% Dictionary should contain only unique values in order of first appearance
    ?assertEqual([<<"foo">>, <<"bar">>], Dict).

build_dictionary_all_identical_test() ->
    Values = [<<"same">>, <<"same">>, <<"same">>, <<"same">>],
    Dict = clickhouse_erl_types_low_cardinality:build_dictionary(Values),
    %% Dictionary should contain only the single unique value
    ?assertEqual([<<"same">>], Dict).

build_dictionary_empty_test() ->
    Values = [],
    Dict = clickhouse_erl_types_low_cardinality:build_dictionary(Values),
    %% Dictionary should be empty for empty input
    ?assertEqual([], Dict).

build_dictionary_integers_test() ->
    Values = [100, 200, 100, 300],
    Dict = clickhouse_erl_types_low_cardinality:build_dictionary(Values),
    %% Dictionary should contain unique integers in order of first appearance
    ?assertEqual([100, 200, 300], Dict).

build_key_mapping_test() ->
    Dictionary = [<<"foo">>, <<"bar">>, <<"baz">>],
    Values = [<<"foo">>, <<"bar">>, <<"baz">>],
    Mapping = clickhouse_erl_types_low_cardinality:build_key_mapping(Dictionary, Values),
    ?assertEqual(#{<<"foo">> => 0, <<"bar">> => 1, <<"baz">> => 2}, Mapping).

%%%===================================================================
%%% Key Type Selection Tests
%%%===================================================================

select_key_type_uint8_test() ->
    ?assertEqual(uint8, clickhouse_erl_types_low_cardinality:select_key_type(1)),
    ?assertEqual(uint8, clickhouse_erl_types_low_cardinality:select_key_type(100)),
    ?assertEqual(uint8, clickhouse_erl_types_low_cardinality:select_key_type(256)).

select_key_type_uint16_test() ->
    ?assertEqual(uint16, clickhouse_erl_types_low_cardinality:select_key_type(257)),
    ?assertEqual(uint16, clickhouse_erl_types_low_cardinality:select_key_type(1000)),
    ?assertEqual(uint16, clickhouse_erl_types_low_cardinality:select_key_type(65536)).

select_key_type_uint32_test() ->
    ?assertEqual(uint32, clickhouse_erl_types_low_cardinality:select_key_type(65537)),
    ?assertEqual(uint32, clickhouse_erl_types_low_cardinality:select_key_type(1000000)).

select_key_type_uint64_test() ->
    ?assertEqual(uint64, clickhouse_erl_types_low_cardinality:select_key_type(4294967297)).

%%%===================================================================
%%% Encoding/Decoding Tests - High Cardinality
%%%===================================================================

encode_decode_high_cardinality_test() ->
    %% Many unique values (high cardinality)
    Values = [
        <<"value1">>,
        <<"value2">>,
        <<"value3">>,
        <<"value4">>,
        <<"value5">>,
        <<"value6">>,
        <<"value7">>,
        <<"value8">>,
        <<"value9">>,
        <<"value10">>
    ],
    InnerType = string,

    {ok, Encoded} = clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(
        Values, InnerType
    ),
    %% Prepend state version for decoding (normally done by data block encoder)
    StateVersion = clickhouse_erl_types_integer:encode_int64(1),
    EncodedWithState = <<StateVersion/binary, Encoded/binary>>,
    {ok, Decoded, <<>>} = clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(
        EncodedWithState, InnerType, length(Values)
    ),

    ?assertEqual(Values, Decoded).

%%%===================================================================
%%% Encoding/Decoding Tests - Low Cardinality
%%%===================================================================

encode_decode_low_cardinality_test() ->
    %% Few unique values (low cardinality)
    Values = [<<"foo">>, <<"foo">>, <<"bar">>, <<"bar">>, <<"bar">>, <<"foo">>],
    InnerType = string,

    {ok, Encoded} = clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(
        Values, InnerType
    ),
    %% Prepend state version for decoding (normally done by data block encoder)
    StateVersion = clickhouse_erl_types_integer:encode_int64(1),
    EncodedWithState = <<StateVersion/binary, Encoded/binary>>,
    {ok, Decoded, <<>>} = clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(
        EncodedWithState, InnerType, length(Values)
    ),

    ?assertEqual(Values, Decoded).

%%%===================================================================
%%% Encoding/Decoding Tests - All Identical
%%%===================================================================

encode_decode_all_identical_test() ->
    %% All identical values
    Values = [<<"same">>, <<"same">>, <<"same">>, <<"same">>, <<"same">>],
    InnerType = string,

    {ok, Encoded} = clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(
        Values, InnerType
    ),
    %% Prepend state version for decoding (normally done by data block encoder)
    StateVersion = clickhouse_erl_types_integer:encode_int64(1),
    EncodedWithState = <<StateVersion/binary, Encoded/binary>>,
    {ok, Decoded, <<>>} = clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(
        EncodedWithState, InnerType, length(Values)
    ),

    ?assertEqual(Values, Decoded).

%%%===================================================================
%%% Encoding/Decoding Tests - Empty
%%%===================================================================

encode_decode_empty_test() ->
    Values = [],
    InnerType = string,

    %% RowCount=0: decoder returns immediately without consuming any data.
    %% ClickHouse doesn't send LowCardinality encoding for 0 rows.
    {ok, Decoded, _Rest} = clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(
        <<>>, InnerType, length(Values)
    ),

    ?assertEqual(Values, Decoded).

%%%===================================================================
%%% Key Type Selection Tests - Different Sizes
%%%===================================================================

encode_decode_uint8_keys_test() ->
    %% 10 unique values -> UInt8 keys
    Values = lists:flatten([
        [list_to_binary("val" ++ integer_to_list(I)) || _ <- lists:seq(1, 10)]
     || I <- lists:seq(1, 10)
    ]),
    InnerType = string,

    {ok, Encoded} = clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(
        Values, InnerType
    ),
    %% Prepend state version for decoding (normally done by data block encoder)
    StateVersion = clickhouse_erl_types_integer:encode_int64(1),
    EncodedWithState = <<StateVersion/binary, Encoded/binary>>,
    {ok, Decoded, <<>>} = clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(
        EncodedWithState, InnerType, length(Values)
    ),

    ?assertEqual(Values, Decoded).

encode_decode_uint16_keys_test() ->
    %% 300 unique values -> UInt16 keys
    UniqueValues = [list_to_binary("val" ++ integer_to_list(I)) || I <- lists:seq(1, 300)],
    Values = lists:flatten([UniqueValues || _ <- lists:seq(1, 2)]),
    InnerType = string,

    {ok, Encoded} = clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(
        Values, InnerType
    ),
    %% Prepend state version for decoding (normally done by data block encoder)
    StateVersion = clickhouse_erl_types_integer:encode_int64(1),
    EncodedWithState = <<StateVersion/binary, Encoded/binary>>,
    {ok, Decoded, <<>>} = clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(
        EncodedWithState, InnerType, length(Values)
    ),

    ?assertEqual(Values, Decoded).

%%%===================================================================
%%% Integer Type Tests
%%%===================================================================

encode_decode_int64_test() ->
    Values = [100, 100, 200, 200, 200, 100],
    InnerType = int64,

    {ok, Encoded} = clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(
        Values, InnerType
    ),
    %% Prepend state version for decoding (normally done by data block encoder)
    StateVersion = clickhouse_erl_types_integer:encode_int64(1),
    EncodedWithState = <<StateVersion/binary, Encoded/binary>>,
    {ok, Decoded, <<>>} = clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(
        EncodedWithState, InnerType, length(Values)
    ),

    ?assertEqual(Values, Decoded).

encode_decode_uint32_test() ->
    Values = [1, 2, 3, 1, 2, 3, 1, 2, 3],
    InnerType = uint32,

    {ok, Encoded} = clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(
        Values, InnerType
    ),
    %% Prepend state version for decoding (normally done by data block encoder)
    StateVersion = clickhouse_erl_types_integer:encode_int64(1),
    EncodedWithState = <<StateVersion/binary, Encoded/binary>>,
    {ok, Decoded, <<>>} = clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(
        EncodedWithState, InnerType, length(Values)
    ),

    ?assertEqual(Values, Decoded).
