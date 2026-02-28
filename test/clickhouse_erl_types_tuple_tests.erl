-module(clickhouse_erl_types_tuple_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Type Parsing Tests
%%%===================================================================

parse_tuple_type_simple_test() ->
    Input = "Tuple(UInt8, String)",
    Expected = [uint8, string],
    ?assertEqual(Expected, clickhouse_erl_types_tuple:parse_tuple_type(Input)).

parse_tuple_type_named_test() ->
    Input = "Tuple(A UInt8, B String)",
    Expected = [uint8, string],
    ?assertEqual(Expected, clickhouse_erl_types_tuple:parse_tuple_type(Input)).

parse_tuple_type_nested_test() ->
    Input = "Tuple(Array(Int64), Tuple(String, Date))",
    Expected = [{array, int64}, {tuple, [string, date]}],
    ?assertEqual(Expected, clickhouse_erl_types_tuple:parse_tuple_type(Input)).

%%%===================================================================
%%% Encoding/Decoding Tests
%%%===================================================================

%% NOTE: Since we cannot easily invoke the full column encoding/decoding stack
%% without mocking (due to circular dependency or complex setup),
%% we will rely on integration/property tests for full round-trip of complex types.
%% However, we CAN test the tuple logic if we assume atomic types work or mock them.

%% For unit testing `unzip_tuples_to_columns`, it is internal, but we can test
%% `encode_tuple_column` failure cases.

encode_tuple_size_mismatch_test() ->
    %% Second tuple has wrong size
    Data = [{1, <<"a">>}, {2}],
    Types = [int8, string],
    ?assertMatch(
        {error, {tuple_size_mismatch, _}},
        clickhouse_erl_types_tuple:encode_tuple_column(Data, Types)
    ).

%% Test empty tuple encoding
encode_empty_tuples_test() ->
    Data = [{}, {}, {}],
    Types = [],
    Result = clickhouse_erl_types_tuple:encode_tuple_column(Data, Types),
    ?assertMatch({ok, <<>>}, Result).

%% Test single element tuple encoding
encode_single_element_tuple_test() ->
    Data = [{1}, {2}, {3}],
    Types = [uint8],
    Result = clickhouse_erl_types_tuple:encode_tuple_column(Data, Types),
    ?assertMatch({ok, <<1, 2, 3>>}, Result).

%% Test two element tuple encoding
encode_two_element_tuple_test() ->
    Data = [{1, 100}, {2, 200}, {3, 250}],
    Types = [uint8, uint8],
    Result = clickhouse_erl_types_tuple:encode_tuple_column(Data, Types),
    % First column: 1, 2, 3; Second column: 100, 200, 250
    ?assertMatch({ok, <<1, 2, 3, 100, 200, 250>>}, Result).

%% Test tuple size validation
encode_tuple_validates_size_test() ->
    % Second tuple has wrong size
    Data = [{1, 2}, {3, 4, 5}],
    Types = [uint8, uint8],
    ?assertMatch(
        {error, {tuple_size_mismatch, _}},
        clickhouse_erl_types_tuple:encode_tuple_column(Data, Types)
    ).

%% Test decode empty tuples
decode_empty_tuples_test() ->
    Binary = <<>>,
    Types = [],
    RowCount = 3,
    {ok, Result, Rest} = clickhouse_erl_types_tuple:decode_tuple_column(Binary, Types, RowCount),
    ?assertEqual([{}, {}, {}], Result),
    ?assertEqual(<<>>, Rest).

%% Test multi-element tuples with mixed types
encode_mixed_types_tuple_test() ->
    % Tuple(UInt8, UInt16, UInt32)
    Data = [{1, 1000, 100000}, {2, 2000, 200000}],
    Types = [uint8, uint16, uint32],
    Result = clickhouse_erl_types_tuple:encode_tuple_column(Data, Types),
    % UInt8 column: 1, 2
    % UInt16 column: 1000, 2000 (little-endian)
    % UInt32 column: 100000, 200000 (little-endian)
    Expected =
        {ok, <<
            % UInt8 column
            1,
            2,
            % UInt16 column
            1000:16/little,
            2000:16/little,
            % UInt32 column
            100000:32/little,
            200000:32/little
        >>},
    ?assertEqual(Expected, Result).

%% Test named tuples (names are ignored during encoding)
parse_named_tuple_ignores_names_test() ->
    Input = "Tuple(x UInt8, y UInt16, z String)",
    Expected = [uint8, uint16, string],
    ?assertEqual(Expected, clickhouse_erl_types_tuple:parse_tuple_type(Input)).

%% Test nested tuples parsing
parse_nested_tuple_test() ->
    Input = "Tuple(Tuple(UInt8, UInt16), String)",
    Expected = [{tuple, [uint8, uint16]}, string],
    ?assertEqual(Expected, clickhouse_erl_types_tuple:parse_tuple_type(Input)).

%% Test deeply nested tuples
parse_deeply_nested_tuple_test() ->
    Input = "Tuple(Tuple(Tuple(UInt8)))",
    Expected = [{tuple, [{tuple, [uint8]}]}],
    ?assertEqual(Expected, clickhouse_erl_types_tuple:parse_tuple_type(Input)).

%% Test data block decoder integration
decode_tuple_column_via_data_block_test() ->
    % Create a simple tuple column: Tuple(UInt8, UInt16)
    % Data: {1, 1000}, {2, 2000}
    Binary = <<
        % UInt8 column
        1,
        2,
        % UInt16 column
        1000:16/little,
        2000:16/little
    >>,
    Type = <<"Tuple(UInt8, UInt16)">>,
    NumRows = 2,

    {ok, Data, Rest} = clickhouse_erl_protocol_data_block:decode_column_data(Type, NumRows, Binary),

    ?assertEqual([{1, 1000}, {2, 2000}], Data),
    ?assertEqual(<<>>, Rest).

%% We skip full encode/decode unit tests here requiring mocks and rely on
%% property tests and integration tests where the full stack is available.
