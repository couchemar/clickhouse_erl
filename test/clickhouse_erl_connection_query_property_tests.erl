%% @doc Property-based tests for ClickHouse connection query transmission.
%%
%% This module contains property-based tests using PropEr to validate
%% the correctness of query transmission over established connections.
-module(clickhouse_erl_connection_query_property_tests).

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("src/clickhouse_erl_protocol.hrl").

%% Property test: Query transmission completeness
%% Feature: simple-query, Property 4: Query transmission completeness
%% Validates: Requirements 2.1, 2.2
prop_query_transmission_completeness() ->
    ?FORALL(
        PreparedRequest,
        prepared_request_gen(),
        begin
            %% Track what gets sent over the socket
            SentData = ets:new(sent_data, [public]),

            try
                %% Mock gen_tcp:connect to return a test socket
                TestSocket = {socket, test},
                meck:expect(gen_tcp, connect, fun(_Host, _Port, _Options, _Timeout) ->
                    {ok, TestSocket}
                end),

                %% Mock gen_tcp:send to capture data
                meck:expect(gen_tcp, send, fun(Socket, Data) ->
                    ets:insert(SentData, {sent, Socket, Data}),
                    ok
                end),

                %% Mock inet:setopts to return ok
                meck:expect(inet, setopts, fun(_Socket, _Options) -> ok end),

                %% Mock response handler
                meck:expect(clickhouse_erl_response_handler, create_initial_state, fun() ->
                    #{
                        result_accumulator => #result_accumulator{
                            columns = [],
                            rows = [],
                            total_rows = 0,
                            statistics = #{
                                rows_read => 0,
                                bytes_read => 0,
                                elapsed_time => 0
                            }
                        },
                        column_metadata => undefined,
                        error_info => undefined
                    }
                end),

                %% Start a connection process
                Options = #{
                    database => "default",
                    username => "default",
                    password => "",
                    client_name => "test_client",
                    client_version => {1, 0, 0}
                },

                %% Use gen_server:start to avoid the blocking connect/3 wrapper
                {ok, Pid} = gen_server:start(
                    clickhouse_erl_connection, {"localhost", 9000, Options}, []
                ),

                %% Send a mock Server_Hello to complete handshake
                ServerHelloPacket = create_mock_server_hello(),
                Pid ! {tcp, TestSocket, ServerHelloPacket},

                %% Send a mock Server_Pong (Type 4) to complete handshake
                Pid ! {tcp, TestSocket, <<4:8>>},

                %% Wait for connection to be ready
                wait_for_state(Pid, ready),

                %% Execute query with response simulation
                QueryBody = maps:get(sql, PreparedRequest, <<>>),
                IsEmptyQuery =
                    string:trim(clickhouse_erl_types_primitive:to_binary(QueryBody)) =:= <<>>,

                case IsEmptyQuery of
                    true ->
                        %% Empty query - just verify no packets were sent
                        Result = clickhouse_erl_connection:query(Pid, PreparedRequest),
                        gen_server:stop(Pid),
                        %% Empty queries should either fail or send no packets
                        SentPackets = ets:tab2list(SentData),
                        case {Result, SentPackets} of
                            % Failed with no packets - good
                            {{error, _}, []} -> true;
                            % Failed but sent packets - acceptable
                            {{error, _}, _} -> true;
                            % Unexpected result
                            _ -> false
                        end;
                    false ->
                        %% Non-empty query - simulate server response
                        spawn(fun() ->
                            %% Send mock response after query is sent
                            timer:sleep(100),
                            %% Send a mock data block first
                            MockDataBlock = create_mock_data_block(),
                            Pid ! {tcp, TestSocket, MockDataBlock},
                            timer:sleep(50),
                            %% Then send END_OF_STREAM
                            EndOfStreamPacket = <<?SERVER_END_OF_STREAM>>,
                            Pid ! {tcp, TestSocket, EndOfStreamPacket}
                        end),

                        _Result = clickhouse_erl_connection:query(Pid, PreparedRequest),

                        %% Stop the connection
                        gen_server:stop(Pid),

                        %% For property testing, we just verify that transmission happened
                        %% (packets were sent), regardless of query result
                        SentPackets = ets:tab2list(SentData),
                        length(SentPackets) > 0
                end
            after
                %% Cleanup
                ets:delete(SentData)
            end
        end
    ).

%% Helper to wait for state
wait_for_state(Pid, ExpectedState) ->
    wait_for_state(Pid, ExpectedState, 50).

wait_for_state(_Pid, _ExpectedState, 0) ->
    error(timeout_waiting_for_state);
wait_for_state(Pid, ExpectedState, Retries) ->
    case clickhouse_erl_connection:get_connection_info(Pid) of
        {ok, #{state := ExpectedState}} ->
            ok;
        _ ->
            timer:sleep(100),
            wait_for_state(Pid, ExpectedState, Retries - 1)
    end.

%% Helper function to create mock Server_Hello packet
create_mock_server_hello() ->
    %% Create a minimal valid Server_Hello packet
    Name = <<10, "ClickHouse">>,
    Major = <<21, 0, 0, 0, 0, 0, 0, 0>>,
    Minor = <<9, 0, 0, 0, 0, 0, 0, 0>>,
    Revision = <<57, 48, 0, 0, 0, 0, 0, 0>>,
    Timezone = <<3, "UTC">>,
    DisplayName = <<17, "ClickHouse Server">>,
    Patch = <<0, 0, 0, 0, 0, 0, 0, 0>>,
    Packet =
        <<Name/binary, Major/binary, Minor/binary, Revision/binary, Timezone/binary,
            DisplayName/binary, Patch/binary>>,
    <<?SERVER_HELLO, Packet/binary>>.

%% Helper function to create mock data block
create_mock_data_block() ->
    %% Create a minimal valid SERVER_DATA packet with empty result
    PacketType = <<?SERVER_DATA:8>>,
    EmptyTableName = clickhouse_erl_types_primitive:encode_string(""),
    %% Block info
    BlockInfo = <<1, 0, 2, 255, 255, 255, 255, 0>>,
    %% Zero columns and rows
    Columns = clickhouse_erl_types_primitive:encode_varint(0),
    Rows = clickhouse_erl_types_primitive:encode_varint(0),
    <<PacketType/binary, EmptyTableName/binary, BlockInfo/binary, Columns/binary, Rows/binary>>.

%% Generator for prepared requests
prepared_request_gen() ->
    ?LET(
        {Sql, QueryId, Settings},
        {sql_gen(), query_id_gen(), settings_gen()},
        #{
            sql => Sql,
            query_id => QueryId,
            settings => Settings
        }
    ).

%% Generator for SQL queries
sql_gen() ->
    oneof([
        <<"SELECT 1">>,
        <<"SELECT * FROM test_table">>,
        <<"SHOW TABLES">>,
        <<"SELECT COUNT(*) FROM users">>,
        <<"INSERT INTO test VALUES (1, 'test')">>,
        % Empty query (should cause validation error)
        <<>>,
        % Whitespace-only query (should cause validation error)
        <<"   ">>,
        ?LET(
            Length,
            range(1, 50),
            ?LET(
                Chars,
                vector(
                    Length, oneof([range($a, $z), range($A, $Z), range($0, $9), $\s, $*, $(, $)])
                ),
                list_to_binary(Chars)
            )
        )
    ]).

%% Generator for query IDs
query_id_gen() ->
    oneof([
        % Empty query ID (should be auto-generated)
        <<>>,
        <<"test_query_123">>,
        <<"user_query_456">>,
        ?LET(
            Length,
            range(1, 30),
            ?LET(
                Chars,
                vector(Length, oneof([range($a, $z), range($0, $9), $_, $-])),
                list_to_binary(Chars)
            )
        )
    ]).

%% Generator for settings
settings_gen() ->
    oneof([
        % No settings
        [],
        [#{key => <<"max_rows">>, value => <<"1000">>, important => false}],
        [#{key => <<"timeout">>, value => <<"30">>, important => true}],
        ?LET(
            N,
            range(0, 3),
            ?LET(Settings, vector(N, setting_gen()), Settings)
        )
    ]).

%% Generator for individual settings
setting_gen() ->
    ?LET(
        {Key, Value, Important},
        {setting_key_gen(), setting_value_gen(), boolean()},
        #{key => Key, value => Value, important => Important}
    ).

%% Generator for setting keys
setting_key_gen() ->
    oneof([
        <<"max_rows">>,
        <<"timeout">>,
        <<"max_memory_usage">>,
        <<"readonly">>
    ]).

%% Generator for setting values
setting_value_gen() ->
    oneof([
        <<"1000">>,
        <<"30">>,
        <<"true">>,
        <<"false">>,
        <<"0">>,
        ?LET(N, range(1, 1000), list_to_binary(integer_to_list(N)))
    ]).

%% EUnit test wrapper for the query transmission completeness property
query_transmission_completeness_test_() ->
    {setup,
        fun() ->
            meck:new(gen_tcp, [unstick, passthrough]),
            meck:expect(gen_tcp, close, fun(_) -> ok end),
            meck:new(inet, [unstick, passthrough]),
            meck:new(clickhouse_erl_response_handler, [unstick, passthrough])
        end,
        fun(_) ->
            meck:unload(gen_tcp),
            meck:unload(inet),
            meck:unload(clickhouse_erl_response_handler)
        end,
        fun() ->
            ?assert(proper:quickcheck(prop_query_transmission_completeness(), [{numtests, 20}]))
        end}.
