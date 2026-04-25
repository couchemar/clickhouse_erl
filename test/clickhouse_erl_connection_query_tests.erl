-module(clickhouse_erl_connection_query_tests).

-include_lib("eunit/include/eunit.hrl").
-include("src/clickhouse_erl_protocol.hrl").

query_execution_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        fun test_successful_query/0,
        fun test_server_exception/0,
        fun test_query_timeout/0,
        fun test_query_cancellation/0,
        fun test_concurrent_query_rejection/0,
        fun test_connection_availability_after_completion/0,
        fun test_connection_unavailability_during_cancellation/0
    ]}.

setup() ->
    meck:new(gen_tcp, [unstick, passthrough]),
    meck:new(inet, [unstick, passthrough]),
    %% Mock gen_tcp:close to handle dummy sockets
    meck:expect(gen_tcp, close, fun(_Socket) -> ok end),
    ok.

cleanup(_) ->
    meck:unload(gen_tcp),
    meck:unload(inet).

test_successful_query() ->
    %% Mock gen_tcp:send to return ok
    meck:expect(gen_tcp, send, fun(_Socket, _Data) -> ok end),

    %% Mock gen_tcp:connect/4 to return a dummy socket
    DummySocket = {socket, dummy},
    meck:expect(gen_tcp, connect, fun(_Host, _Port, _Options, _Timeout) -> {ok, DummySocket} end),

    %% Mock inet:setopts to return ok
    meck:expect(inet, setopts, fun(_Socket, _Options) -> ok end),

    %% Start the connection process directly to avoid blocking on connect/3
    Options = #{
        database => "default",
        username => "default",
        password => "",
        client_name => "test_client",
        % Use tuples for versions as per implementation
        client_version => {1, 0, 0}
    },
    {ok, Pid} = gen_server:start(clickhouse_erl_connection, {"localhost", 9000, Options}, []),

    %% Simulate handshake completion
    %% We need to send a Server_Hello packet to the process so it completes handshake
    ServerHelloPacket = create_server_hello_packet(),
    Pid ! {tcp, DummySocket, ServerHelloPacket},

    %% Send Server_Pong (Type 4) to complete handshake
    Pid ! {tcp, DummySocket, <<4:8>>},

    %% Wait for state to become ready
    wait_for_state(Pid, ready),

    %% Now execute query
    PreparedRequest = #{
        sql => "SELECT 1",
        query_id => "test_query_id",
        settings => []
    },

    %% `query` is blocking (gen_server:call). The gen_server will handle it.
    %% It will send CLIENT_QUERY via socket (mocked).

    %% Spawn a process to simulate server response for the query
    spawn(fun() ->
        %% Wait a bit for query to be sent
        timer:sleep(100),
        %% Send SERVER_DATA (columns)
        Packet1 = create_data_packet_columns(),
        Pid ! {tcp, DummySocket, Packet1},
        %% Send SERVER_DATA (rows)
        Packet2 = create_data_packet_rows(),
        Pid ! {tcp, DummySocket, Packet2},
        %% Send END_OF_STREAM
        Packet3 = create_eos_packet(),
        Pid ! {tcp, DummySocket, Packet3}
    end),

    Result = clickhouse_erl_connection:query(Pid, PreparedRequest),

    %% Verify result
    ?assertMatch({ok, _}, Result),
    {ok, QueryResult} = Result,
    ?assert(is_map(QueryResult)),
    ?assert(maps:is_key(columns, maps:get(data, QueryResult))),
    ?assert(maps:is_key(rows, maps:get(data, QueryResult))),

    gen_server:stop(Pid).

test_server_exception() ->
    %% Mock mocks ... (reuse if possible, or reset)
    DummySocket = {socket, dummy},
    meck:expect(gen_tcp, connect, fun(_, _, _, _) -> {ok, DummySocket} end),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(inet, setopts, fun(_, _) -> ok end),

    Options = #{
        client_version => {1, 0, 0}
    },
    {ok, Pid} = gen_server:start(clickhouse_erl_connection, {"localhost", 9000, Options}, []),

    ServerHelloPacket = create_server_hello_packet(),
    Pid ! {tcp, DummySocket, ServerHelloPacket},

    %% Send Server_Pong (Type 4) to complete handshake
    Pid ! {tcp, DummySocket, <<4:8>>},

    wait_for_state(Pid, ready),

    PreparedRequest = #{
        sql => "SELECT error",
        query_id => "error_query",
        settings => []
    },

    spawn(fun() ->
        timer:sleep(50),
        %% Send EXCEPTION_PACKET
        ExPacket = create_exception_packet(60, "DB::Exception", "Table not found"),
        Pid ! {tcp, DummySocket, ExPacket}
    end),

    Result = clickhouse_erl_connection:query(Pid, PreparedRequest),

    ?assertMatch({error, {server_exception, _}}, Result),

    gen_server:stop(Pid).

test_query_timeout() ->
    %% Mock mocks
    DummySocket = {socket, dummy},
    meck:expect(gen_tcp, connect, fun(_, _, _, _) -> {ok, DummySocket} end),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(inet, setopts, fun(_, _) -> ok end),

    Options = #{client_version => {1, 0, 0}},
    {ok, Pid} = gen_server:start(clickhouse_erl_connection, {"localhost", 9000, Options}, []),

    ServerHelloPacket = create_server_hello_packet(),
    Pid ! {tcp, DummySocket, ServerHelloPacket},

    %% Send Server_Pong (Type 4) to complete handshake
    Pid ! {tcp, DummySocket, <<4:8>>},

    wait_for_state(Pid, ready),

    PreparedRequest = #{
        sql => "SELECT sleep(10)",
        query_id => "timeout_query",
        settings => [],
        %% Short timeout
        timeout => 200
    },

    StartTime = erlang:system_time(millisecond),
    Result = clickhouse_erl_connection:query(Pid, PreparedRequest),
    EndTime = erlang:system_time(millisecond),

    %% Verify timeout error
    ?assertMatch({error, {timeout_error, query_execution}}, Result),
    ?assert(EndTime - StartTime >= 200),

    %% Verify connection is NOT ready yet (it should wait for EOF)
    {ok, Info} = clickhouse_erl_connection:get_connection_info(Pid),
    ?assertNotEqual(undefined, maps:get(active_query_state, Info)),

    %% Simulate server sending EOF after cancellation
    Pid ! {tcp, DummySocket, create_eos_packet()},

    %% Now verify connection becomes ready
    wait_for_state(Pid, ready),

    gen_server:stop(Pid).

test_query_cancellation() ->
    %% Mock mocks
    DummySocket = {socket, dummy},
    meck:expect(gen_tcp, connect, fun(_, _, _, _) -> {ok, DummySocket} end),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(inet, setopts, fun(_, _) -> ok end),

    Options = #{client_version => {1, 0, 0}},
    {ok, Pid} = gen_server:start(clickhouse_erl_connection, {"localhost", 9000, Options}, []),

    ServerHelloPacket = create_server_hello_packet(),
    Pid ! {tcp, DummySocket, ServerHelloPacket},

    %% Send Server_Pong (Type 4) to complete handshake
    Pid ! {tcp, DummySocket, <<4:8>>},

    wait_for_state(Pid, ready),

    QueryId = <<"cancel_query_id">>,
    PreparedRequest = #{
        sql => "SELECT long_query",
        query_id => QueryId,
        settings => [],
        timeout => 5000
    },

    %% Start query in a separate process because it's blocking
    Parent = self(),
    spawn_link(fun() ->
        QueryResult = clickhouse_erl_connection:query(Pid, PreparedRequest),
        Parent ! {query_done, QueryResult}
    end),

    %% Wait a bit and then cancel
    timer:sleep(100),
    CancelResult = clickhouse_erl_connection:cancel_query(Pid, QueryId),
    ?assertEqual(ok, CancelResult),

    %% Wait for query process to receive cancellation error
    receive
        {query_done, QueryResult} ->
            ?assertEqual({error, {query_cancelled, QueryId}}, QueryResult)
    after 1000 ->
        ?assert(false, "Timeout waiting for query cancellation reply")
    end,

    %% Verify connection is NOT ready yet
    {ok, Info} = clickhouse_erl_connection:get_connection_info(Pid),
    ?assertNotEqual(undefined, maps:get(active_query_state, Info)),

    %% Simulate server sending EOF
    Pid ! {tcp, DummySocket, create_eos_packet()},

    %% Now verify connection becomes ready
    wait_for_state(Pid, ready),

    gen_server:stop(Pid).

test_concurrent_query_rejection() ->
    %% Test that second query is rejected while first is active
    %% Verify error message: "Connection busy with another query"
    %% Verify first query state is unaffected
    %% Requirements: 5.1

    %% Mock mocks
    DummySocket = {socket, dummy},
    meck:expect(gen_tcp, connect, fun(_, _, _, _) -> {ok, DummySocket} end),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(inet, setopts, fun(_, _) -> ok end),

    Options = #{client_version => {1, 0, 0}},
    {ok, Pid} = gen_server:start(clickhouse_erl_connection, {"localhost", 9000, Options}, []),

    ServerHelloPacket = create_server_hello_packet(),
    Pid ! {tcp, DummySocket, ServerHelloPacket},

    %% Send Server_Pong (Type 4) to complete handshake
    Pid ! {tcp, DummySocket, <<4:8>>},

    wait_for_state(Pid, ready),

    QueryId1 = <<"first_query_id">>,
    PreparedRequest1 = #{
        sql => "SELECT sleep(10)",
        query_id => QueryId1,
        settings => [],
        timeout => 5000
    },

    %% Start first query in a separate process (it's blocking)
    Parent = self(),
    spawn_link(fun() ->
        QueryResult = clickhouse_erl_connection:query(Pid, PreparedRequest1),
        Parent ! {query1_done, QueryResult}
    end),

    %% Wait a bit to ensure first query is active
    timer:sleep(100),

    %% Verify first query is active
    {ok, InfoBefore} = clickhouse_erl_connection:get_connection_info(Pid),
    ActiveQueryBefore = maps:get(active_query_state, InfoBefore),
    ?assertNotEqual(undefined, ActiveQueryBefore),
    ?assertEqual(QueryId1, maps:get(query_id, ActiveQueryBefore)),

    %% Attempt to execute second query while first is active
    QueryId2 = <<"second_query_id">>,
    PreparedRequest2 = #{
        sql => "SELECT 1",
        query_id => QueryId2,
        settings => []
    },

    Result2 = clickhouse_erl_connection:query(Pid, PreparedRequest2),

    %% Verify second query is rejected with correct error message
    ?assertEqual({error, {connection_error, query_in_progress}}, Result2),

    %% Verify first query state is unaffected
    {ok, InfoAfter} = clickhouse_erl_connection:get_connection_info(Pid),
    ActiveQueryAfter = maps:get(active_query_state, InfoAfter),
    ?assertNotEqual(undefined, ActiveQueryAfter),
    ?assertEqual(QueryId1, maps:get(query_id, ActiveQueryAfter)),

    %% Verify the active query state is identical before and after rejection
    ?assertEqual(ActiveQueryBefore, ActiveQueryAfter),

    %% Clean up: cancel first query and send EOF
    clickhouse_erl_connection:cancel_query(Pid, QueryId1),
    Pid ! {tcp, DummySocket, create_eos_packet()},

    %% Wait for first query to complete
    receive
        {query1_done, _} -> ok
    after 1000 ->
        ?assert(false, "Timeout waiting for first query to complete")
    end,

    wait_for_state(Pid, ready),

    gen_server:stop(Pid).

test_connection_availability_after_completion() ->
    %% Test that connection accepts new queries immediately after completion
    %% Execute query and wait for completion
    %% Immediately execute second query
    %% Verify second query is accepted
    %% Requirements: 5.2

    %% Mock mocks
    DummySocket = {socket, dummy},
    meck:expect(gen_tcp, connect, fun(_, _, _, _) -> {ok, DummySocket} end),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(inet, setopts, fun(_, _) -> ok end),

    Options = #{client_version => {1, 0, 0}},
    {ok, Pid} = gen_server:start(clickhouse_erl_connection, {"localhost", 9000, Options}, []),

    ServerHelloPacket = create_server_hello_packet(),
    Pid ! {tcp, DummySocket, ServerHelloPacket},

    %% Send Server_Pong (Type 4) to complete handshake
    Pid ! {tcp, DummySocket, <<4:8>>},

    wait_for_state(Pid, ready),

    %% Execute first query
    QueryId1 = <<"first_query_id">>,
    PreparedRequest1 = #{
        sql => "SELECT 1",
        query_id => QueryId1,
        settings => []
    },

    %% Spawn a process to simulate server response for first query
    spawn(fun() ->
        timer:sleep(50),
        %% Send SERVER_DATA (columns)
        Packet1 = create_data_packet_columns(),
        Pid ! {tcp, DummySocket, Packet1},
        %% Send SERVER_DATA (rows)
        Packet2 = create_data_packet_rows(),
        Pid ! {tcp, DummySocket, Packet2},
        %% Send END_OF_STREAM
        Packet3 = create_eos_packet(),
        Pid ! {tcp, DummySocket, Packet3}
    end),

    Result1 = clickhouse_erl_connection:query(Pid, PreparedRequest1),

    %% Verify first query succeeded
    ?assertMatch({ok, _}, Result1),

    %% Verify connection is ready (active_query_state should be undefined)
    {ok, InfoAfterFirst} = clickhouse_erl_connection:get_connection_info(Pid),
    ?assertEqual(undefined, maps:get(active_query_state, InfoAfterFirst)),
    ?assertEqual(ready, maps:get(state, InfoAfterFirst)),

    %% Immediately execute second query
    QueryId2 = <<"second_query_id">>,
    PreparedRequest2 = #{
        sql => "SELECT 2",
        query_id => QueryId2,
        settings => []
    },

    %% Spawn a process to simulate server response for second query
    spawn(fun() ->
        timer:sleep(50),
        %% Send SERVER_DATA (columns)
        Packet1 = create_data_packet_columns(),
        Pid ! {tcp, DummySocket, Packet1},
        %% Send SERVER_DATA (rows)
        Packet2 = create_data_packet_rows(),
        Pid ! {tcp, DummySocket, Packet2},
        %% Send END_OF_STREAM
        Packet3 = create_eos_packet(),
        Pid ! {tcp, DummySocket, Packet3}
    end),

    Result2 = clickhouse_erl_connection:query(Pid, PreparedRequest2),

    %% Verify second query is accepted and succeeds
    ?assertMatch({ok, _}, Result2),

    %% Verify connection is still ready after second query
    {ok, InfoAfterSecond} = clickhouse_erl_connection:get_connection_info(Pid),
    ?assertEqual(undefined, maps:get(active_query_state, InfoAfterSecond)),
    ?assertEqual(ready, maps:get(state, InfoAfterSecond)),

    gen_server:stop(Pid).

test_connection_unavailability_during_cancellation() ->
    %% Test that new query is rejected while connection waits for EOF after cancellation
    %% Cancel active query
    %% Attempt to execute new query before EOF received
    %% Verify new query is rejected
    %% Requirements: 5.3

    %% Mock mocks
    DummySocket = {socket, dummy},
    meck:expect(gen_tcp, connect, fun(_, _, _, _) -> {ok, DummySocket} end),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    meck:expect(inet, setopts, fun(_, _) -> ok end),

    Options = #{client_version => {1, 0, 0}},
    {ok, Pid} = gen_server:start(clickhouse_erl_connection, {"localhost", 9000, Options}, []),

    ServerHelloPacket = create_server_hello_packet(),
    Pid ! {tcp, DummySocket, ServerHelloPacket},

    %% Send Server_Pong (Type 4) to complete handshake
    Pid ! {tcp, DummySocket, <<4:8>>},

    wait_for_state(Pid, ready),

    QueryId1 = <<"cancellation_query_id">>,
    PreparedRequest1 = #{
        sql => "SELECT long_running_query",
        query_id => QueryId1,
        settings => [],
        timeout => 5000
    },

    %% Start first query in a separate process (it's blocking)
    Parent = self(),
    spawn_link(fun() ->
        QueryResult = clickhouse_erl_connection:query(Pid, PreparedRequest1),
        Parent ! {query1_done, QueryResult}
    end),

    %% Wait a bit to ensure first query is active
    timer:sleep(100),

    %% Verify first query is active
    {ok, InfoBefore} = clickhouse_erl_connection:get_connection_info(Pid),
    ActiveQueryBefore = maps:get(active_query_state, InfoBefore),
    ?assertNotEqual(undefined, ActiveQueryBefore),
    ?assertEqual(QueryId1, maps:get(query_id, ActiveQueryBefore)),

    %% Cancel the active query
    CancelResult = clickhouse_erl_connection:cancel_query(Pid, QueryId1),
    ?assertEqual(ok, CancelResult),

    %% Wait for cancellation to be processed
    timer:sleep(50),

    %% Verify connection still has active query state (waiting for EOF)
    {ok, InfoAfterCancel} = clickhouse_erl_connection:get_connection_info(Pid),
    ActiveQueryAfterCancel = maps:get(active_query_state, InfoAfterCancel),
    ?assertNotEqual(undefined, ActiveQueryAfterCancel),
    ?assertEqual(QueryId1, maps:get(query_id, ActiveQueryAfterCancel)),
    ?assertEqual(true, maps:get(cancelled, ActiveQueryAfterCancel)),

    %% Attempt to execute new query BEFORE EOF is received
    QueryId2 = <<"new_query_during_cancellation">>,
    PreparedRequest2 = #{
        sql => "SELECT 1",
        query_id => QueryId2,
        settings => []
    },

    Result2 = clickhouse_erl_connection:query(Pid, PreparedRequest2),

    %% Verify new query is rejected with correct error message
    ?assertEqual({error, {connection_error, query_in_progress}}, Result2),

    %% Verify active query state is still the cancelled query (unaffected by rejection)
    {ok, InfoAfterRejection} = clickhouse_erl_connection:get_connection_info(Pid),
    ActiveQueryAfterRejection = maps:get(active_query_state, InfoAfterRejection),
    ?assertNotEqual(undefined, ActiveQueryAfterRejection),
    ?assertEqual(QueryId1, maps:get(query_id, ActiveQueryAfterRejection)),
    ?assertEqual(true, maps:get(cancelled, ActiveQueryAfterRejection)),

    %% Now simulate server sending EOF
    Pid ! {tcp, DummySocket, create_eos_packet()},

    %% Wait for first query to complete with cancellation error
    receive
        {query1_done, QueryResult1} ->
            ?assertEqual({error, {query_cancelled, QueryId1}}, QueryResult1)
    after 1000 ->
        ?assert(false, "Timeout waiting for cancelled query to complete")
    end,

    %% Verify connection is now ready and accepts new queries
    wait_for_state(Pid, ready),

    {ok, InfoAfterEOF} = clickhouse_erl_connection:get_connection_info(Pid),
    ?assertEqual(undefined, maps:get(active_query_state, InfoAfterEOF)),
    ?assertEqual(ready, maps:get(state, InfoAfterEOF)),

    gen_server:stop(Pid).

wait_for_state(Pid, ExpectedState) ->
    % 20 * 100ms = 2s timeout
    wait_for_state(Pid, ExpectedState, 20).

wait_for_state(_Pid, _ExpectedState, 0) ->
    throw(timeout_waiting_for_state);
wait_for_state(Pid, ExpectedState, Retries) ->
    case clickhouse_erl_connection:get_connection_info(Pid) of
        {ok, #{state := ExpectedState}} ->
            ok;
        _ ->
            timer:sleep(100),
            wait_for_state(Pid, ExpectedState, Retries - 1)
    end.

%% --- Helper Functions ---

create_server_hello_packet() ->
    %% Build a proper Server_Hello packet using varint encoding
    %% Fields: name (string), major (varint), minor (varint), revision (varint),
    %%         timezone (string), display_name (string), patch (varint)
    Name = clickhouse_erl_types_primitive:encode_string(<<"ClickHouse">>),
    Major = clickhouse_erl_types_primitive:encode_varint(21),
    Minor = clickhouse_erl_types_primitive:encode_varint(9),
    %% Revision 54451 - high enough for timezone, display_name, version_patch features
    Revision = clickhouse_erl_types_primitive:encode_varint(54451),
    Timezone = clickhouse_erl_types_primitive:encode_string(<<"UTC">>),
    DisplayName = clickhouse_erl_types_primitive:encode_string(<<"ClickHouse Server">>),
    Patch = clickhouse_erl_types_primitive:encode_varint(0),
    Packet =
        <<Name/binary, Major/binary, Minor/binary, Revision/binary, Timezone/binary,
            DisplayName/binary, Patch/binary>>,
    <<?SERVER_HELLO, Packet/binary>>.

create_data_packet_columns() ->
    %% Create a minimal valid SERVER_DATA packet with column metadata
    PacketType = <<?SERVER_DATA:8>>,
    EmptyTableName = clickhouse_erl_types_primitive:encode_string(""),
    %% Block info (ch-go compatible format)
    BlockInfo = <<1, 0, 2, 255, 255, 255, 255, 0>>,
    %% Zero columns and rows for metadata packet
    Columns = clickhouse_erl_types_primitive:encode_varint(0),
    Rows = clickhouse_erl_types_primitive:encode_varint(0),
    <<PacketType/binary, EmptyTableName/binary, BlockInfo/binary, Columns/binary, Rows/binary>>.

create_data_packet_rows() ->
    %% Create a minimal valid SERVER_DATA packet with empty result
    PacketType = <<?SERVER_DATA:8>>,
    EmptyTableName = clickhouse_erl_types_primitive:encode_string(""),
    %% Block info
    BlockInfo = <<1, 0, 2, 255, 255, 255, 255, 0>>,
    %% Zero columns and rows
    Columns = clickhouse_erl_types_primitive:encode_varint(0),
    Rows = clickhouse_erl_types_primitive:encode_varint(0),
    <<PacketType/binary, EmptyTableName/binary, BlockInfo/binary, Columns/binary, Rows/binary>>.

create_eos_packet() ->
    <<?SERVER_END_OF_STREAM>>.

create_exception_packet(CodeVal, NameVal, MsgVal) ->
    Code = <<CodeVal:32/little>>,
    NameLen = byte_size(list_to_binary(NameVal)),
    Name = <<NameLen, (list_to_binary(NameVal))/binary>>,
    MsgLen = byte_size(list_to_binary(MsgVal)),
    Msg = <<MsgLen, (list_to_binary(MsgVal))/binary>>,
    StackTrace = <<0>>,
    Nested = <<0>>,
    Packet = <<Code/binary, Name/binary, Msg/binary, StackTrace/binary, Nested/binary>>,
    <<?SERVER_EXCEPTION, Packet/binary>>.
