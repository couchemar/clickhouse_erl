%% @doc Unit tests for SERVER_TABLE_COLUMNS (11) parser.
-module(clickhouse_erl_parser_server_table_columns_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test parsing TABLE_COLUMNS packet
parse_table_columns_test() ->
    %% TABLE_COLUMNS contains: external_table_name (string) + column_description (string)
    TableName = <<"test_table">>,
    TableNameData = <<10, TableName/binary>>,

    ColumnDesc = <<"col1 String, col2 UInt64">>,
    ColumnDescData = <<24, ColumnDesc/binary>>,

    Data = <<TableNameData/binary, ColumnDescData/binary>>,

    State = clickhouse_erl_parser_server_table_columns:init(#{version => 54451}),
    {done, Events, Rest} = clickhouse_erl_parser_server_table_columns:parse(Data, State),

    %% Should have 2 data events
    DataEvents = [E || {data, _, _} = E <- Events],
    ?assertEqual(2, length(DataEvents)),
    ?assertEqual(<<>>, Rest).

%% Test parsing with incomplete data
parse_incomplete_data_test() ->
    %% Only table name, missing column description
    TableName = <<"test_table">>,
    Data = <<10, TableName/binary>>,

    State = clickhouse_erl_parser_server_table_columns:init(#{version => 54451}),
    {more, _Events, _UnparsedRest, _NewState} =
        clickhouse_erl_parser_server_table_columns:parse(Data, State),

    ok.

%% Test parsing with remainder
parse_with_remainder_test() ->
    TableName = <<"test_table">>,
    TableNameData = <<10, TableName/binary>>,
    ColumnDesc = <<"col1 String">>,
    ColumnDescData = <<11, ColumnDesc/binary>>,
    Remainder = <<1, 2, 3, 4>>,

    Data = <<TableNameData/binary, ColumnDescData/binary, Remainder/binary>>,

    State = clickhouse_erl_parser_server_table_columns:init(#{version => 54451}),
    {done, _Events, Rest} = clickhouse_erl_parser_server_table_columns:parse(Data, State),

    ?assertEqual(Remainder, Rest).
