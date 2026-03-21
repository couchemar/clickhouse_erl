%% @doc Unit tests for SERVER_PART_UUIDS (12) parser.
-module(clickhouse_erl_parser_server_part_uuids_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test parsing PART_UUIDS packet with multiple UUIDs
parse_part_uuids_test() ->
    %% PART_UUIDS contains: count (varint) + array of UUID strings

    % varint 2
    Count = <<2>>,
    UUID1 = <<"550e8400-e29b-41d4-a716-446655440000">>,
    UUID1Data = <<36, UUID1/binary>>,
    UUID2 = <<"6ba7b810-9dad-11d1-80b4-00c04fd430c8">>,
    UUID2Data = <<36, UUID2/binary>>,

    Data = <<Count/binary, UUID1Data/binary, UUID2Data/binary>>,

    State = clickhouse_erl_parser_server_part_uuids:init(#{version => 54451}),
    {done, Events, Rest} = clickhouse_erl_parser_server_part_uuids:parse(Data, State),

    %% Should have count + 2 UUID events
    DataEvents = [E || {data, _, _} = E <- Events],
    ?assert(length(DataEvents) >= 2),
    ?assertEqual(<<>>, Rest).

%% Test parsing with zero UUIDs
parse_zero_uuids_test() ->
    %% Count = 0, no UUIDs
    Data = <<0>>,

    State = clickhouse_erl_parser_server_part_uuids:init(#{version => 54451}),
    {done, Events, Rest} = clickhouse_erl_parser_server_part_uuids:parse(Data, State),

    %% Should have count event only
    ?assert(length(Events) > 0),
    ?assertEqual(<<>>, Rest).

%% Test parsing with incomplete data
parse_incomplete_data_test() ->
    %% Count says 2 but only 1 UUID provided
    Count = <<2>>,
    UUID1 = <<"550e8400-e29b-41d4-a716-446655440000">>,
    UUID1Data = <<36, UUID1/binary>>,

    Data = <<Count/binary, UUID1Data/binary>>,

    State = clickhouse_erl_parser_server_part_uuids:init(#{version => 54451}),
    {more, _Events, _UnparsedRest, _NewState} =
        clickhouse_erl_parser_server_part_uuids:parse(Data, State),

    ok.

%% Test parsing with remainder
parse_with_remainder_test() ->
    Count = <<1>>,
    UUID1 = <<"550e8400-e29b-41d4-a716-446655440000">>,
    UUID1Data = <<36, UUID1/binary>>,
    Remainder = <<1, 2, 3, 4>>,

    Data = <<Count/binary, UUID1Data/binary, Remainder/binary>>,

    State = clickhouse_erl_parser_server_part_uuids:init(#{version => 54451}),
    {done, _Events, Rest} = clickhouse_erl_parser_server_part_uuids:parse(Data, State),

    ?assertEqual(Remainder, Rest).
