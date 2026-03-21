%% @doc Unit tests for SERVER_LOG (10) parser.
-module(clickhouse_erl_parser_server_log_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test that LOG parser delegates to block parser
parse_delegates_to_block_parser_test() ->
    %% LOG parser should delegate to block parser
    %% Test with minimal valid block (1 column, 1 row)
    TempTable = <<0>>,
    BlockInfo = <<0>>,
    NumColumns = <<1>>,
    NumRows = <<1>>,
    ColName = <<3, "col">>,
    ColType = <<6, "String">>,
    ColData = <<5, "hello">>,

    Data =
        <<TempTable/binary, BlockInfo/binary, NumColumns/binary, NumRows/binary, ColName/binary,
            ColType/binary, ColData/binary>>,

    State = clickhouse_erl_parser_server_log:init(#{version => 54451}),
    Result = clickhouse_erl_parser_server_log:parse(Data, State),

    %% Should return done with events (delegated to block parser)
    ?assertMatch({done, _, _}, Result).

%% Test parsing with incomplete data
parse_incomplete_data_test() ->
    %% Incomplete temp table string
    Data = <<>>,

    State = clickhouse_erl_parser_server_log:init(#{version => 54451}),
    {more, Events, UnparsedRest, _NewState} =
        clickhouse_erl_parser_server_log:parse(Data, State),

    ?assertEqual([], Events),
    ?assertEqual(Data, UnparsedRest).

%% Test that init delegates to block parser
init_delegates_to_block_parser_test() ->
    State1 = clickhouse_erl_parser_server_log:init(#{version => 54451}),
    State2 = clickhouse_erl_parser_block:init(#{version => 54451}),

    %% Both should return same initial state
    ?assertEqual(State2, State1).
