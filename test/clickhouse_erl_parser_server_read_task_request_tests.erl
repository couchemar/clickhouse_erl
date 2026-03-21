%% @doc Unit tests for SERVER_READ_TASK_REQUEST (13) parser.
-module(clickhouse_erl_parser_server_read_task_request_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test parsing READ_TASK_REQUEST packet with UUID string
parse_uuid_string_test() ->
    %% READ_TASK_REQUEST contains a single string (UUID)
    UUID = <<"550e8400-e29b-41d4-a716-446655440000">>,
    %% Encode as varint length + UTF-8 string
    Len = byte_size(UUID),
    Data = <<Len:8, UUID/binary>>,

    State = clickhouse_erl_parser_server_read_task_request:init(#{version => 54451}),
    {done, Events, Rest} = clickhouse_erl_parser_server_read_task_request:parse(Data, State),

    ?assertEqual([{data, task_id, UUID}], Events),
    ?assertEqual(<<>>, Rest).

%% Test parsing with incomplete data
parse_incomplete_data_test() ->
    %% Incomplete varint length
    Data = <<>>,

    State = clickhouse_erl_parser_server_read_task_request:init(#{version => 54451}),
    {more, Events, UnparsedRest, _NewState} =
        clickhouse_erl_parser_server_read_task_request:parse(Data, State),

    ?assertEqual([], Events),
    ?assertEqual(Data, UnparsedRest).

%% Test parsing with incomplete string data
parse_incomplete_string_test() ->
    %% Length says 36 bytes but only 10 provided
    Data = <<36:8, "0123456789">>,

    State = clickhouse_erl_parser_server_read_task_request:init(#{version => 54451}),
    {more, Events, UnparsedRest, _NewState} =
        clickhouse_erl_parser_server_read_task_request:parse(Data, State),

    ?assertEqual([], Events),
    ?assertEqual(Data, UnparsedRest).

%% Test parsing with remainder data
parse_with_remainder_test() ->
    UUID = <<"550e8400-e29b-41d4-a716-446655440000">>,
    Len = byte_size(UUID),
    Remainder = <<1, 2, 3, 4>>,
    Data = <<Len:8, UUID/binary, Remainder/binary>>,

    State = clickhouse_erl_parser_server_read_task_request:init(#{version => 54451}),
    {done, Events, Rest} = clickhouse_erl_parser_server_read_task_request:parse(Data, State),

    ?assertEqual([{data, task_id, UUID}], Events),
    ?assertEqual(Remainder, Rest).
