%% @doc Property tests for event-driven parser correctness.
%%
%% Tests universal properties of event-driven parsing without requiring
%% a live ClickHouse connection. Uses synthetic packet data.
-module(prop_clickhouse_erl_parser_event_driven).

-include_lib("proper/include/proper.hrl").

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Build exception packet from components
build_exception_packet(Code, Name, Message, StackTrace, HasNested) ->
    NameBin = encode_string(Name),
    MessageBin = encode_string(Message),
    StackTraceBin = encode_string(StackTrace),
    NestedByte =
        case HasNested of
            true -> 1;
            false -> 0
        end,
    <<Code:32/signed-little, NameBin/binary, MessageBin/binary, StackTraceBin/binary,
        NestedByte:8>>.

%% @doc Encode a string with varint length prefix (proper ClickHouse format)
encode_string(Str) when is_binary(Str) ->
    Len = byte_size(Str),
    LenBin = encode_varint(Len),
    <<LenBin/binary, Str/binary>>.

%% @doc Encode varint (simple version for lengths < 128)
encode_varint(N) when N < 128 ->
    <<N:8>>;
encode_varint(N) when N < 16384 ->
    <<(N band 127 bor 128):8, (N bsr 7):8>>;
encode_varint(N) ->
    %% For larger numbers, use full varint encoding
    encode_varint_loop(N, <<>>).

encode_varint_loop(0, Acc) ->
    Acc;
encode_varint_loop(N, Acc) when N < 128 ->
    <<Acc/binary, N:8>>;
encode_varint_loop(N, Acc) ->
    Byte = (N band 127) bor 128,
    encode_varint_loop(N bsr 7, <<Acc/binary, Byte:8>>).

%%%===================================================================
%%% Properties
%%%===================================================================

%% @doc Property: Parsing complete packet always succeeds
%% Tag: Feature: streamable-packet-parsing, Property: Complete packet parsing
prop_complete_exception_packet_parsing() ->
    ?FORALL(
        {Code, Name, Message, StackTrace},
        {integer(), ascii_binary(), ascii_binary(), ascii_binary()},
        begin
            Packet = build_exception_packet(Code, Name, Message, StackTrace, false),
            State = clickhouse_erl_parser_server_exception:init(#{}),
            Result = clickhouse_erl_parser_server_exception:parse(Packet, State),

            case Result of
                {done, Events, <<>>} ->
                    %% Verify all expected events are present
                    lists:member({data, error_code, Code}, Events) andalso
                        lists:member({data, exception_name, Name}, Events) andalso
                        lists:member({data, message, Message}, Events) andalso
                        lists:member({data, stack_trace, StackTrace}, Events) andalso
                        lists:member({data, nested, false}, Events);
                _ ->
                    false
            end
        end
    ).

%% @doc Generator for ASCII-only binaries (avoids varint confusion)
ascii_binary() ->
    ?LET(Chars, list(range(32, 126)), list_to_binary(Chars)).

%% @doc Property: Parsing at arbitrary split points produces same result
%% Tag: Feature: streamable-packet-parsing, Property: Split-point independence
prop_exception_split_point_independence() ->
    ?FORALL(
        {Code, Name, Message, StackTrace, SplitPoint},
        {integer(), ascii_binary(), ascii_binary(), ascii_binary(), pos_integer()},
        begin
            Packet = build_exception_packet(Code, Name, Message, StackTrace, false),
            PacketSize = byte_size(Packet),

            case PacketSize > 0 of
                true ->
                    %% Split at valid position
                    ActualSplit = (SplitPoint rem PacketSize) + 1,
                    <<Part1:ActualSplit/binary, Part2/binary>> = Packet,

                    %% Parse in two chunks
                    State1 = clickhouse_erl_parser_server_exception:init(#{}),
                    Result1 = clickhouse_erl_parser_server_exception:parse(Part1, State1),

                    case Result1 of
                        {more, Events1, Buffer1, State2} ->
                            %% Continue with second part
                            Result2 =
                                clickhouse_erl_parser_server_exception:parse(
                                    <<Buffer1/binary, Part2/binary>>, State2
                                ),

                            case Result2 of
                                {done, Events2, <<>>} ->
                                    %% Combine events and verify completeness
                                    AllEvents = Events1 ++ Events2,
                                    lists:member({data, error_code, Code}, AllEvents) andalso
                                        lists:member({data, exception_name, Name}, AllEvents) andalso
                                        lists:member({data, message, Message}, AllEvents) andalso
                                        lists:member({data, stack_trace, StackTrace}, AllEvents) andalso
                                        lists:member({data, nested, false}, AllEvents);
                                _ ->
                                    false
                            end;
                        {done, Events, <<>>} ->
                            %% First part was complete
                            lists:member({data, error_code, Code}, Events) andalso
                                lists:member({data, exception_name, Name}, Events) andalso
                                lists:member({data, message, Message}, Events) andalso
                                lists:member({data, stack_trace, StackTrace}, Events) andalso
                                lists:member({data, nested, false}, Events);
                        _ ->
                            false
                    end;
                false ->
                    true
            end
        end
    ).

%% @doc Property: END_OF_STREAM always returns done immediately
%% Tag: Feature: streamable-packet-parsing, Property: END_OF_STREAM immediate completion
prop_end_of_stream_immediate_completion() ->
    ?FORALL(
        Data,
        binary(),
        begin
            State = clickhouse_erl_parser_server_end_of_stream:init(#{}),
            Result = clickhouse_erl_parser_server_end_of_stream:parse(Data, State),

            case Result of
                {done, [], Remainder} ->
                    %% Should pass through all data as remainder
                    Remainder =:= Data;
                _ ->
                    false
            end
        end
    ).

%% @doc Property: PONG always returns done immediately
%% Tag: Feature: streamable-packet-parsing, Property: PONG immediate completion
prop_pong_immediate_completion() ->
    ?FORALL(
        Data,
        binary(),
        begin
            State = clickhouse_erl_parser_server_pong:init(#{}),
            Result = clickhouse_erl_parser_server_pong:parse(Data, State),

            case Result of
                {done, [], Remainder} ->
                    %% Should pass through all data as remainder
                    Remainder =:= Data;
                _ ->
                    false
            end
        end
    ).

%% @doc Property: Parser state preserves parsed values across incomplete data
%% Tag: Feature: streamable-packet-parsing, Property: State preservation
prop_exception_state_preservation() ->
    ?FORALL(
        {Code, Name},
        {integer(), ascii_binary()},
        begin
            %% Build partial packet (only error code and name)
            NameBin = encode_string(Name),
            PartialPacket = <<Code:32/signed-little, NameBin/binary>>,

            State1 = clickhouse_erl_parser_server_exception:init(#{}),
            Result1 = clickhouse_erl_parser_server_exception:parse(PartialPacket, State1),

            case Result1 of
                {more, Events, _Buffer, _State2} ->
                    %% Verify parsed values are in events
                    lists:member({data, error_code, Code}, Events) andalso
                        lists:member({data, exception_name, Name}, Events);
                {done, Events, <<>>} ->
                    %% If it completed, values should still be present
                    lists:member({data, error_code, Code}, Events) andalso
                        lists:member({data, exception_name, Name}, Events);
                _ ->
                    false
            end
        end
    ).

%% @doc Property: Remainder is correctly preserved
%% Tag: Feature: streamable-packet-parsing, Property: Remainder preservation
prop_exception_remainder_preservation() ->
    ?FORALL(
        {Code, Name, Message, StackTrace, ExtraData},
        {integer(), ascii_binary(), ascii_binary(), ascii_binary(), binary()},
        begin
            Packet = build_exception_packet(Code, Name, Message, StackTrace, false),
            FullData = <<Packet/binary, ExtraData/binary>>,

            State = clickhouse_erl_parser_server_exception:init(#{}),
            Result = clickhouse_erl_parser_server_exception:parse(FullData, State),

            case Result of
                {done, _Events, Remainder} ->
                    %% Remainder should be exactly the extra data
                    Remainder =:= ExtraData;
                _ ->
                    false
            end
        end
    ).

%% @doc Property: Empty strings are handled correctly
%% Tag: Feature: streamable-packet-parsing, Property: Empty string handling
prop_exception_empty_strings() ->
    ?FORALL(
        Code,
        integer(),
        begin
            Packet = build_exception_packet(Code, <<>>, <<>>, <<>>, false),
            State = clickhouse_erl_parser_server_exception:init(#{}),
            Result = clickhouse_erl_parser_server_exception:parse(Packet, State),

            case Result of
                {done, Events, <<>>} ->
                    lists:member({data, error_code, Code}, Events) andalso
                        lists:member({data, exception_name, <<>>}, Events) andalso
                        lists:member({data, message, <<>>}, Events) andalso
                        lists:member({data, stack_trace, <<>>}, Events);
                _ ->
                    false
            end
        end
    ).
