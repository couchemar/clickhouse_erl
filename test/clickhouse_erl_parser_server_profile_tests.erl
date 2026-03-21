%% @doc Unit tests for SERVER_PROFILE (6) parser.
-module(clickhouse_erl_parser_server_profile_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test parsing PROFILE packet with all fields
parse_profile_complete_test() ->
    %% PROFILE contains: rows, blocks, bytes, applied_limit, rows_before_limit, calculated_rows_before_limit
    %% Use proper varint encoding (values < 128 are single byte)

    % varint 100
    Rows = <<100>>,
    % varint 10
    Blocks = <<10>>,
    % varint 200 (requires 2 bytes: 200 = 0xC8 = 10011000, encoded as 200, 1)
    Bytes = <<200, 1>>,
    % bool true
    AppliedLimit = <<1>>,
    % varint 50
    RowsBeforeLimit = <<50>>,
    % bool false
    CalculatedRowsBeforeLimit = <<0>>,

    Data =
        <<Rows/binary, Blocks/binary, Bytes/binary, AppliedLimit/binary, RowsBeforeLimit/binary,
            CalculatedRowsBeforeLimit/binary>>,

    State = clickhouse_erl_parser_server_profile:init(#{version => 54451}),
    {done, Events, Rest} = clickhouse_erl_parser_server_profile:parse(Data, State),

    %% Should have 6 data events
    DataEvents = [E || {data, _, _} = E <- Events],
    ?assertEqual(6, length(DataEvents)),
    ?assertEqual(<<>>, Rest).

%% Test parsing with incomplete data
parse_incomplete_data_test() ->
    %% Only rows field, missing others

    % varint 100
    Data = <<100>>,

    State = clickhouse_erl_parser_server_profile:init(#{version => 54451}),
    Result = clickhouse_erl_parser_server_profile:parse(Data, State),

    %% Should return more since we need blocks field
    ?assertMatch({more, _, _, _}, Result).

%% Test parsing with remainder
parse_with_remainder_test() ->
    % varint 100
    Rows = <<100>>,
    % varint 10
    Blocks = <<10>>,
    % varint 200
    Bytes = <<200, 1>>,
    % bool true
    AppliedLimit = <<1>>,
    % varint 50
    RowsBeforeLimit = <<50>>,
    % bool false
    CalculatedRowsBeforeLimit = <<0>>,
    Remainder = <<1, 2, 3, 4>>,

    Data =
        <<Rows/binary, Blocks/binary, Bytes/binary, AppliedLimit/binary, RowsBeforeLimit/binary,
            CalculatedRowsBeforeLimit/binary, Remainder/binary>>,

    State = clickhouse_erl_parser_server_profile:init(#{version => 54451}),
    {done, _Events, Rest} = clickhouse_erl_parser_server_profile:parse(Data, State),

    ?assertEqual(Remainder, Rest).
