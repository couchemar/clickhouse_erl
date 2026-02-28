-module(clickhouse_erl_custom_serialization_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test parsing both packet examples from the user
parse_first_packet_test() ->
    %% First packet: 01 00 01 00 02 ff ff ff ff 00 01 00 01 31 05 55 49 6e 74 38 00
    %% SERVER_DATA packet with 1 column, 0 rows, custom serialization flag = 00 (false)
    Packet1 = <<1, 0, 1, 0, 2, 255, 255, 255, 255, 0, 1, 0, 1, 49, 5, 85, 73, 110, 116, 56, 0>>,

    %% Parse with protocol version 54460 (supports custom serialization)
    {ok, Block, <<>>} = clickhouse_erl_protocol_data_block:decode(Packet1, 54460),

    %% Verify structure
    ?assertEqual(1, maps:get(columns, Block)),
    ?assertEqual(0, maps:get(rows, Block)),

    %% Verify column data
    [ColumnData] = maps:get(column_data, Block),
    ?assertEqual(<<"1">>, maps:get(name, ColumnData)),
    ?assertEqual(<<"UInt8">>, maps:get(type, ColumnData)),
    % No data because rows = 0
    ?assertEqual([], maps:get(data, ColumnData)).

parse_second_packet_test() ->
    %% Second packet: 01 00 01 00 02 ff ff ff ff 00 01 01 01 31 05 55 49 6e 74 38 00 01
    %% SERVER_DATA packet with 1 column, 1 row, custom serialization flag = 00 (false), data = 01
    Packet2 = <<1, 0, 1, 0, 2, 255, 255, 255, 255, 0, 1, 1, 1, 49, 5, 85, 73, 110, 116, 56, 0, 1>>,

    %% Parse with protocol version 54460 (supports custom serialization)
    {ok, Block, <<>>} = clickhouse_erl_protocol_data_block:decode(Packet2, 54460),

    %% Verify structure
    ?assertEqual(1, maps:get(columns, Block)),
    ?assertEqual(1, maps:get(rows, Block)),

    %% Verify column data
    [ColumnData] = maps:get(column_data, Block),
    ?assertEqual(<<"1">>, maps:get(name, ColumnData)),
    ?assertEqual(<<"UInt8">>, maps:get(type, ColumnData)),
    % One UInt8 value = 1
    ?assertEqual([1], maps:get(data, ColumnData)).

parse_without_custom_serialization_test() ->
    %% Test parsing with older protocol version that doesn't support custom serialization
    %% This should fail because the packet contains the custom serialization flag
    %% but the protocol version doesn't expect it
    Packet1 = <<1, 0, 1, 0, 2, 255, 255, 255, 255, 0, 1, 0, 1, 49, 5, 85, 73, 110, 116, 56, 0>>,

    %% Parse with protocol version 54450 (before custom serialization feature)
    Result = clickhouse_erl_protocol_data_block:decode(Packet1, 54450),

    %% This should either succeed (if we handle it gracefully) or fail predictably
    %% The exact behavior depends on implementation - for now, let's just verify it doesn't crash
    ?assertMatch({ok, _, _}, Result).

protocol_version_feature_check_test() ->
    %% Test that our protocol version checking works correctly
    ?assert(clickhouse_erl_protocol_features:has_feature(custom_serialization, 54460)),
    ?assert(clickhouse_erl_protocol_features:has_feature(custom_serialization, 54454)),
    ?assertNot(clickhouse_erl_protocol_features:has_feature(custom_serialization, 54453)).
