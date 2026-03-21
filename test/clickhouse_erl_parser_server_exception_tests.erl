%% @doc Unit tests for clickhouse_erl_parser_server_exception module.
%%
%% Tests exception packet parsing with synthetic data (no live ClickHouse connection).
-module(clickhouse_erl_parser_server_exception_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test Helpers
%%%===================================================================

%% @doc Encode a string with varint length prefix
encode_string(Str) when is_binary(Str) ->
    Len = byte_size(Str),
    <<Len:8, Str/binary>>;
encode_string(Str) when is_list(Str) ->
    encode_string(list_to_binary(Str)).

%% @doc Build a complete exception packet
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

%%%===================================================================
%%% Unit Tests
%%%===================================================================

parse_complete_exception_test() ->
    %% Build a complete exception packet
    Packet = build_exception_packet(
        160,
        <<"TOO_SLOW">>,
        <<"Query execution time exceeded">>,
        <<"at Server.cpp:123">>,
        false
    ),

    State = clickhouse_erl_parser_server_exception:init(#{}),
    Result = clickhouse_erl_parser_server_exception:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    %% Verify all expected events are present
    ?assert(lists:member({data, error_code, 160}, Events)),
    ?assert(lists:member({data, exception_name, <<"TOO_SLOW">>}, Events)),
    ?assert(lists:member({data, message, <<"Query execution time exceeded">>}, Events)),
    ?assert(lists:member({data, stack_trace, <<"at Server.cpp:123">>}, Events)),
    ?assert(lists:member({data, nested, false}, Events)).

parse_exception_with_nested_test() ->
    %% Build exception with nested flag set
    Packet = build_exception_packet(
        42,
        <<"NETWORK_ERROR">>,
        <<"Connection lost">>,
        <<"at Network.cpp:456">>,
        true
    ),

    State = clickhouse_erl_parser_server_exception:init(#{}),
    Result = clickhouse_erl_parser_server_exception:parse(Packet, State),

    ?assertMatch({more, Events, <<>>, _} when is_list(Events), Result),
    {more, Events, _, _} = Result,

    %% Verify nested flag is true
    ?assert(lists:member({data, nested, true}, Events)).

parse_incomplete_error_code_test() ->
    %% Only 3 bytes of error code (need 4)
    Packet = <<160, 0, 0>>,

    State = clickhouse_erl_parser_server_exception:init(#{}),
    Result = clickhouse_erl_parser_server_exception:parse(Packet, State),

    ?assertMatch({more, [], <<160, 0, 0>>, _}, Result).

parse_incomplete_name_test() ->
    %% Error code complete, but name string incomplete

    % Length 10 but no data
    Packet = <<160:32/signed-little, 10>>,

    State = clickhouse_erl_parser_server_exception:init(#{}),
    Result = clickhouse_erl_parser_server_exception:parse(Packet, State),

    ?assertMatch({more, [{data, error_code, 160}], _, _}, Result).

parse_incomplete_message_test() ->
    %% Error code and name complete, message incomplete
    NameBin = encode_string(<<"ERROR">>),
    % Message length 20 but no data
    Packet = <<160:32/signed-little, NameBin/binary, 20>>,

    State = clickhouse_erl_parser_server_exception:init(#{}),
    Result = clickhouse_erl_parser_server_exception:parse(Packet, State),

    ?assertMatch({more, Events, _, _} when is_list(Events), Result),
    {more, Events, _, _} = Result,
    ?assert(lists:member({data, error_code, 160}, Events)),
    ?assert(lists:member({data, exception_name, <<"ERROR">>}, Events)).

parse_incomplete_stack_trace_test() ->
    %% Error code, name, and message complete, stack trace incomplete
    NameBin = encode_string(<<"ERROR">>),
    MessageBin = encode_string(<<"Failed">>),
    % Stack trace length 30 but no data
    Packet = <<160:32/signed-little, NameBin/binary, MessageBin/binary, 30>>,

    State = clickhouse_erl_parser_server_exception:init(#{}),
    Result = clickhouse_erl_parser_server_exception:parse(Packet, State),

    ?assertMatch({more, Events, _, _} when is_list(Events), Result),
    {more, Events, _, _} = Result,
    ?assert(lists:member({data, message, <<"Failed">>}, Events)).

parse_incomplete_nested_flag_test() ->
    %% Everything complete except nested flag
    NameBin = encode_string(<<"ERROR">>),
    MessageBin = encode_string(<<"Failed">>),
    StackTraceBin = encode_string(<<"trace">>),
    Packet = <<160:32/signed-little, NameBin/binary, MessageBin/binary, StackTraceBin/binary>>,

    State = clickhouse_erl_parser_server_exception:init(#{}),
    Result = clickhouse_erl_parser_server_exception:parse(Packet, State),

    ?assertMatch({more, Events, <<>>, _} when is_list(Events), Result),
    {more, Events, _, _} = Result,
    ?assert(lists:member({data, stack_trace, <<"trace">>}, Events)).

parse_empty_strings_test() ->
    %% Exception with empty name, message, and stack trace
    Packet = build_exception_packet(
        0,
        <<"">>,
        <<"">>,
        <<"">>,
        false
    ),

    State = clickhouse_erl_parser_server_exception:init(#{}),
    Result = clickhouse_erl_parser_server_exception:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    ?assert(lists:member({data, error_code, 0}, Events)),
    ?assert(lists:member({data, exception_name, <<>>}, Events)),
    ?assert(lists:member({data, message, <<>>}, Events)),
    ?assert(lists:member({data, stack_trace, <<>>}, Events)).

parse_negative_error_code_test() ->
    %% Test with negative error code (signed integer)
    Packet = build_exception_packet(
        -1,
        <<"UNKNOWN">>,
        <<"Unknown error">>,
        <<"">>,
        false
    ),

    State = clickhouse_erl_parser_server_exception:init(#{}),
    Result = clickhouse_erl_parser_server_exception:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,
    ?assert(lists:member({data, error_code, -1}, Events)).

parse_with_remainder_test() ->
    %% Exception packet followed by additional data
    Packet = build_exception_packet(
        100,
        <<"TEST">>,
        <<"Test message">>,
        <<"stack">>,
        false
    ),
    Remainder = <<"extra_data">>,
    FullData = <<Packet/binary, Remainder/binary>>,

    State = clickhouse_erl_parser_server_exception:init(#{}),
    Result = clickhouse_erl_parser_server_exception:parse(FullData, State),

    ?assertMatch({done, _, <<"extra_data">>}, Result).

parse_resumption_after_incomplete_test() ->
    %% Test that parser can resume after incomplete data
    NameBin = encode_string(<<"ERROR">>),
    Part1 = <<160:32/signed-little, NameBin/binary>>,

    State1 = clickhouse_erl_parser_server_exception:init(#{}),
    {more, Events1, Buffer1, State2} = clickhouse_erl_parser_server_exception:parse(Part1, State1),

    ?assert(lists:member({data, error_code, 160}, Events1)),
    ?assert(lists:member({data, exception_name, <<"ERROR">>}, Events1)),

    %% Now provide the rest of the data
    MessageBin = encode_string(<<"Failed">>),
    StackTraceBin = encode_string(<<"trace">>),
    Part2 = <<MessageBin/binary, StackTraceBin/binary, 0:8>>,

    %% Parser should resume from where it left off
    Result = clickhouse_erl_parser_server_exception:parse(<<Buffer1/binary, Part2/binary>>, State2),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,
    ?assert(lists:member({data, message, <<"Failed">>}, Events)),
    ?assert(lists:member({data, stack_trace, <<"trace">>}, Events)),
    ?assert(lists:member({data, nested, false}, Events)).
