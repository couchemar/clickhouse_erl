-module(clickhouse_erl_packet_buffering_tests).
-include_lib("eunit/include/eunit.hrl").
-include("clickhouse_erl_protocol.hrl").

packet_buffering_test() ->
    %% Setup state using proper initializer
    State = clickhouse_erl_response_handler:create_initial_state(54460),

    %% Create a Progress packet
    %% Rows=1, Bytes=1, TotalRows=1, WrittenRows=0, WrittenBytes=0, ElapsedNs=0
    ProgressPayload = <<1, 1, 1, 0, 0, 0>>,
    ProgressPacket = <<?SERVER_PROGRESS, ProgressPayload/binary>>,

    %% Create a Data packet (Empty block)
    %% TempTable="", BlockInfo (1, 0, 2, -1, 0), Cols=0, Rows=0
    %% BlockInfo:
    %%   1 (varint) -> 1
    %%   IsOverflows (1 byte) -> 0
    %%   2 (varint) -> 2
    %%   BucketNum (4 bytes int32) -> -1 (0xFFFFFFFF)
    %%   0 (varint) -> 0
    BlockInfo = <<1, 0, 2, 255, 255, 255, 255, 0>>,
    %% 0 string, BlockInfo, 0 cols, 0 rows
    DataPayload = <<0, BlockInfo/binary, 0, 0>>,
    DataPacket = <<?SERVER_DATA, DataPayload/binary>>,

    %% Create EndOfStream packet (no body)
    EOSPacket = <<?SERVER_END_OF_STREAM>>,

    %% Concatenate packets
    TCPData = <<ProgressPacket/binary, DataPacket/binary, EOSPacket/binary>>,

    %% Process Loop Simulation

    %% 1. Process Progress Packet
    <<P1Type:8, P1Body/binary>> = TCPData,
    ?assertEqual(?SERVER_PROGRESS, P1Type),

    {ok, State1, Rest1} = clickhouse_erl_response_handler:handle_packet(P1Type, P1Body, State),

    %% verify Rest1 starts with Data packet
    ExpectedRest1 = <<DataPacket/binary, EOSPacket/binary>>,
    ?assertEqual(ExpectedRest1, Rest1),

    %% 2. Process Data Packet
    <<P2Type:8, P2Body/binary>> = Rest1,
    ?assertEqual(?SERVER_DATA, P2Type),

    {ok, State2, Rest2} = clickhouse_erl_response_handler:handle_packet(P2Type, P2Body, State1),

    ExpectedRest2 = EOSPacket,
    ?assertEqual(ExpectedRest2, Rest2),

    %% 3. Process EOS Packet
    <<P3Type:8, P3Body/binary>> = Rest2,
    ?assertEqual(?SERVER_END_OF_STREAM, P3Type),

    %% For EOS, handle_packet should return complete
    %% EOS has no body, so P3Body IS the rest (empty in this case)
    ?assertEqual(<<>>, P3Body),

    %% Create CallbackInfo for END_OF_STREAM (modern approach)
    CallbackInfo = #{
        on_data => fun clickhouse_erl_response_handler:accumulate_data_block_callback/2,
        accumulator => maps:get(result_accumulator, State2)
    },

    {complete, _Result, Rest3} = clickhouse_erl_response_handler:handle_end_of_stream_packet_with_state(
        P3Body, State2, CallbackInfo
    ),

    ?assertEqual(<<>>, Rest3).

exception_packet_with_rest_test() ->
    %% Setup
    State = clickhouse_erl_response_handler:create_initial_state(54460),

    %% Create Exception Packet
    %% Code=123, Name="Err", Msg="Msg", Stack="Trace", Nested=0
    %% Code: int32 (4 bytes little endian) -> 123 = 0x7B
    Code = <<123, 0, 0, 0>>,
    Name = <<3, "Err">>,
    Msg = <<3, "Msg">>,
    Stack = <<5, "Trace">>,
    Nested = <<0>>,
    ExPayload = <<Code/binary, Name/binary, Msg/binary, Stack/binary, Nested/binary>>,
    ExPacket = <<?SERVER_EXCEPTION, ExPayload/binary>>,

    %% Extra data (e.g. next packet or garbage)
    ExtraData = <<1, 2, 3, 4>>,

    TCPData = <<ExPacket/binary, ExtraData/binary>>,

    <<PType:8, PBody/binary>> = TCPData,

    {error, {server_exception, ExInfo}, Rest} = clickhouse_erl_response_handler:handle_packet(
        PType, PBody, State
    ),

    ?assertEqual(123, ExInfo#exception_info.error_code),
    ?assertEqual(<<"Err">>, ExInfo#exception_info.exception_name),
    ?assertEqual(ExtraData, Rest).

progress_packet_extra_bytes_reproduction_test() ->
    %% Setup state
    State = clickhouse_erl_response_handler:create_initial_state(54460),

    %% Exact bytes from Frame 14 in erlang1.txt: 03 (Type) 01 01 01 00 00 92 d2 36
    %% 01, 01, 01, 00, 00 are standard 5 varints
    %% 92 d2 36 is the extra data (suspected elapsed_ns)
    ProgressPayload = <<1, 1, 1, 0, 0, 16#92, 16#D2, 16#36>>,
    ProgressPacket = <<?SERVER_PROGRESS, ProgressPayload/binary>>,

    %% Next packet (imitating Frame 16 starte: 0e ...)
    NextPacket = <<?SERVER_PROFILE_EVENTS, 0, 1, 2>>,

    TCPData = <<ProgressPacket/binary, NextPacket/binary>>,

    <<PType:8, PBody/binary>> = TCPData,
    ?assertEqual(?SERVER_PROGRESS, PType),

    {ok, _State, Rest} = clickhouse_erl_response_handler:handle_packet(PType, PBody, State),

    %% With current buggy implementation, Rest will include 92 d2 36
    %% And NextPacket
    %% If we fix it, Rest should JUST be NextPacket

    %% Let's assert what we EXPECT if it's fixed, and see it fail
    ?assertEqual(NextPacket, Rest).
