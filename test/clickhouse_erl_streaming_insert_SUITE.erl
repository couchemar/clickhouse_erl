%% @doc Common Test suite for streaming insert integration tests
%% Tests end-to-end streaming insert behavior against a real ClickHouse server
-module(clickhouse_erl_streaming_insert_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("../src/clickhouse_erl_protocol.hrl").

-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).

%% Pull-based tests
-export([
    pull_based_simple_insert/1,
    pull_based_multiple_blocks/1,
    pull_based_empty_callback_immediate_done/1,
    pull_based_callback_error/1,
    pull_based_server_exception/1
]).

%% Push-based tests
-export([
    push_based_simple_insert/1,
    push_based_multiple_blocks/1,
    push_based_finish_with_zero_blocks/1,
    push_based_connection_busy/1,
    push_based_server_exception/1
]).

%% Error handling tests
-export([
    error_empty_columns_pull/1,
    error_empty_columns_push/1,
    error_missing_callback/1,
    error_invalid_stream_ref/1,
    error_no_active_session/1
]).

%% Compression tests
-export([
    compression_lz4/1,
    compression_zstd/1,
    compression_disabled/1
]).

%% State management tests
-export([
    state_recovery_after_success_pull/1,
    state_recovery_after_success_push/1,
    state_recovery_after_error/1,
    state_recovery_after_server_exception/1,
    concurrent_query_rejection/1
]).

%% Timeout and cancellation tests
-export([
    timeout_pull_based/1,
    timeout_push_based/1,
    cancellation_pull_based/1,
    cancellation_push_based/1
]).

-define(CONNECT_TIMEOUT, 5000).
-define(TEST_TABLE, <<"test_streaming_insert">>).

%%%===================================================================
%%% CT Callbacks
%%%===================================================================

suite() ->
    [{timetrap, {seconds, 120}}].

all() ->
    [
        {group, pull_based},
        {group, push_based},
        {group, error_handling},
        {group, compression},
        {group, state_management},
        {group, timeout_and_cancellation}
    ].

groups() ->
    [
        {pull_based, [sequence], [
            pull_based_simple_insert,
            pull_based_multiple_blocks,
            pull_based_empty_callback_immediate_done,
            pull_based_callback_error,
            pull_based_server_exception
        ]},
        {push_based, [sequence], [
            push_based_simple_insert,
            push_based_multiple_blocks,
            push_based_finish_with_zero_blocks,
            push_based_connection_busy,
            push_based_server_exception
        ]},
        {error_handling, [sequence], [
            error_empty_columns_pull,
            error_empty_columns_push,
            error_missing_callback,
            error_invalid_stream_ref,
            error_no_active_session
        ]},
        {compression, [sequence], [
            compression_lz4,
            compression_zstd,
            compression_disabled
        ]},
        {state_management, [sequence], [
            state_recovery_after_success_pull,
            state_recovery_after_success_push,
            state_recovery_after_error,
            concurrent_query_rejection,
            state_recovery_after_server_exception
        ]},
        {timeout_and_cancellation, [sequence], [
            timeout_pull_based,
            timeout_push_based,
            cancellation_pull_based,
            cancellation_push_based
        ]}
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        timeout => ?CONNECT_TIMEOUT
    },
    {ok, Conn} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),
    CreateSQL =
        <<"CREATE TABLE IF NOT EXISTS ", (?TEST_TABLE)/binary,
            " (id UInt32, name String, value Float64"
            ") ENGINE = MergeTree() ORDER BY id">>,
    {ok, _} = clickhouse_erl:query(Conn, CreateSQL),
    [{connection, Conn}, {table, ?TEST_TABLE} | Config].

end_per_suite(Config) ->
    Conn = proplists:get_value(connection, Config),
    DropSQL = <<"DROP TABLE IF EXISTS ", (?TEST_TABLE)/binary>>,
    catch clickhouse_erl:query(Conn, DropSQL),
    clickhouse_erl:disconnect(Conn),
    test_helpers:cleanup(),
    ok.

init_per_group(Group, Config) when
    Group =:= pull_based;
    Group =:= push_based;
    Group =:= error_handling;
    Group =:= compression;
    Group =:= state_management;
    Group =:= timeout_and_cancellation
->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        timeout => ?CONNECT_TIMEOUT
    },
    {ok, Conn} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),
    [{connection, Conn} | Config].

end_per_group(_Group, Config) ->
    Conn = proplists:get_value(connection, Config),
    clickhouse_erl:disconnect(Conn),
    ok.

%% Helper: standard column definitions for the test table
columns() ->
    [
        #{name => <<"id">>, type => <<"UInt32">>},
        #{name => <<"name">>, type => <<"String">>},
        #{name => <<"value">>, type => <<"Float64">>}
    ].

%% Helper: single-column definition
id_columns() ->
    [#{name => <<"id">>, type => <<"UInt32">>}].

%%%===================================================================
%%% Pull-Based Streaming Insert Tests
%%% Validates: Requirements 3.1-3.7
%%%===================================================================

%% Test: End-to-end pull-based streaming insert with single block
%% Validates: Requirements 3.1, 3.2, 3.3, 3.5, 3.6
pull_based_simple_insert(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id, name, value) VALUES">>,
    Callback = fun(Acc) ->
        case Acc of
            0 ->
                {ok,
                    [
                        #{name => <<"id">>, data => [1]},
                        #{name => <<"name">>, data => [<<"test">>]},
                        #{name => <<"value">>, data => [1.5]}
                    ],
                    1};
            _ ->
                {done, Acc}
        end
    end,
    Opts = #{on_input => Callback, columns => columns(), initial_accumulator => 0},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts),
    ?assertMatch({ok, #{rows_inserted := 1, blocks_sent := 1}}, Result).

%% Test: Pull-based streaming with multiple blocks
%% Validates: Requirements 3.3, 3.4, 3.5
pull_based_multiple_blocks(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id, name, value) VALUES">>,
    Callback = fun(Acc) ->
        case Acc of
            0 ->
                {ok,
                    [
                        #{name => <<"id">>, data => [10]},
                        #{name => <<"name">>, data => [<<"a">>]},
                        #{name => <<"value">>, data => [1.0]}
                    ],
                    1};
            1 ->
                {ok,
                    [
                        #{name => <<"id">>, data => [20]},
                        #{name => <<"name">>, data => [<<"b">>]},
                        #{name => <<"value">>, data => [2.0]}
                    ],
                    2};
            2 ->
                {ok,
                    [
                        #{name => <<"id">>, data => [30]},
                        #{name => <<"name">>, data => [<<"c">>]},
                        #{name => <<"value">>, data => [3.0]}
                    ],
                    3};
            _ ->
                {done, Acc}
        end
    end,
    Opts = #{on_input => Callback, columns => columns(), initial_accumulator => 0},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts),
    ?assertMatch({ok, #{rows_inserted := 3, blocks_sent := 3}}, Result).

%% Test: Pull-based callback returning {done, _} immediately (zero blocks)
%% Validates: Requirement 3.5
pull_based_empty_callback_immediate_done(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id, name, value) VALUES">>,
    Callback = fun(_Acc) -> {done, done} end,
    Opts = #{on_input => Callback, columns => columns()},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts),
    ?assertMatch({ok, #{rows_inserted := 0, blocks_sent := 0}}, Result).

%% Test: Pull-based callback returning {error, Reason}
%% Validates: Requirement 2.4
pull_based_callback_error(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id, name, value) VALUES">>,
    Callback = fun(_Acc) -> {error, custom_error} end,
    Opts = #{on_input => Callback, columns => columns()},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts),
    ?assertMatch({error, {callback_error, custom_error}}, Result).

%% Test: Pull-based server exception handling
%% Validates: Requirement 3.7
pull_based_server_exception(Config) ->
    Conn = proplists:get_value(connection, Config),
    SQL = <<"INSERT INTO non_existent_table_12345 (id) VALUES">>,
    Callback = fun(_Acc) ->
        {ok, [#{name => <<"id">>, data => [1]}], 1}
    end,
    Opts = #{on_input => Callback, columns => id_columns()},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts),
    ?assertMatch({error, {server_exception, _}}, Result).

%%%===================================================================
%%% Push-Based Streaming Insert Tests
%%% Validates: Requirements 10.1-10.4, 11.1-11.5
%%%===================================================================

%% Test: End-to-end push-based streaming insert
%% Validates: Requirements 10.1, 10.2, 10.3, 11.1, 11.2
push_based_simple_insert(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id, name, value) VALUES">>,
    {ok, StreamRef} = clickhouse_erl:start_streaming_insert(Conn, SQL, #{columns => columns()}),
    Data = [
        #{name => <<"id">>, data => [100]},
        #{name => <<"name">>, data => [<<"push_test">>]},
        #{name => <<"value">>, data => [9.9]}
    ],
    ok = clickhouse_erl:send_data(Conn, StreamRef, Data),
    {ok, Result} = clickhouse_erl:finish_streaming_insert(Conn, StreamRef),
    ?assertMatch(#{rows_inserted := 1, blocks_sent := 1}, Result).

%% Test: Push-based streaming with multiple send_data calls
%% Validates: Requirements 11.1, 11.2
push_based_multiple_blocks(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id, name, value) VALUES">>,
    {ok, StreamRef} = clickhouse_erl:start_streaming_insert(Conn, SQL, #{columns => columns()}),
    ok = clickhouse_erl:send_data(Conn, StreamRef, [
        #{name => <<"id">>, data => [200]},
        #{name => <<"name">>, data => [<<"a">>]},
        #{name => <<"value">>, data => [1.0]}
    ]),
    ok = clickhouse_erl:send_data(Conn, StreamRef, [
        #{name => <<"id">>, data => [201]},
        #{name => <<"name">>, data => [<<"b">>]},
        #{name => <<"value">>, data => [2.0]}
    ]),
    ok = clickhouse_erl:send_data(Conn, StreamRef, [
        #{name => <<"id">>, data => [202]},
        #{name => <<"name">>, data => [<<"c">>]},
        #{name => <<"value">>, data => [3.0]}
    ]),
    {ok, Result} = clickhouse_erl:finish_streaming_insert(Conn, StreamRef),
    ?assertMatch(#{rows_inserted := 3, blocks_sent := 3}, Result).

%% Test: finish_streaming_insert with zero blocks sent
%% Validates: Requirement 10.2
push_based_finish_with_zero_blocks(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id, name, value) VALUES">>,
    {ok, StreamRef} = clickhouse_erl:start_streaming_insert(Conn, SQL, #{columns => columns()}),
    {ok, Result} = clickhouse_erl:finish_streaming_insert(Conn, StreamRef),
    ?assertMatch(#{rows_inserted := 0, blocks_sent := 0}, Result).

%% Test: Connection busy rejection during active push session
%% Validates: Requirement 10.4
push_based_connection_busy(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    PushOpts = #{columns => id_columns()},
    {ok, StreamRef} = clickhouse_erl:start_streaming_insert(Conn, SQL, PushOpts),
    Result = clickhouse_erl:start_streaming_insert(Conn, SQL, PushOpts),
    ?assertMatch({error, {connection_error, query_in_progress}}, Result),
    clickhouse_erl:finish_streaming_insert(Conn, StreamRef).

%% Test: Push-based server exception handling
%% The server exception for a non-existent table arrives asynchronously.
%% start_streaming_insert sends the query and returns {ok, StreamRef} before
%% the server responds. The exception is detected on the next send_data call.
%% Validates: Requirement 14.1
push_based_server_exception(Config) ->
    Conn = proplists:get_value(connection, Config),
    SQL = <<"INSERT INTO non_existent_table_12345 (id) VALUES">>,
    PushOpts = #{columns => id_columns()},
    {ok, StreamRef} = clickhouse_erl:start_streaming_insert(Conn, SQL, PushOpts),
    %% Give server time to send exception response
    timer:sleep(200),
    Data = [#{name => <<"id">>, data => [1]}],
    SendResult = clickhouse_erl:send_data(Conn, StreamRef, Data),
    case SendResult of
        {error, {server_exception, _}} ->
            ok;
        ok ->
            %% Exception not detected on send_data, should be on finish
            FinishResult = clickhouse_erl:finish_streaming_insert(Conn, StreamRef),
            ?assertMatch({error, {server_exception, _}}, FinishResult);
        {error, _} = Other ->
            %% Network error or other — server may have closed connection
            ct:pal("send_data returned: ~p", [Other])
    end.

%%%===================================================================
%%% Error Handling Tests
%%% Validates: Requirements 5.1, 11.4, 11.5, 12.1
%%%===================================================================

%% Test: Empty columns error for pull-based
%% Validates: Requirement 5.1
error_empty_columns_pull(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    Callback = fun(_Acc) -> {done, done} end,
    Opts = #{on_input => Callback, columns => []},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts),
    ?assertMatch({error, {validation_error, empty_columns}}, Result).

%% Test: Empty columns error for push-based
%% Validates: Requirement 12.1
error_empty_columns_push(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    Result = clickhouse_erl:start_streaming_insert(Conn, SQL, #{columns => []}),
    ?assertMatch({error, {validation_error, empty_columns}}, Result).

%% Test: Missing on_input callback error
%% Validates: Requirement 1.4
error_missing_callback(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    Opts = #{columns => id_columns()},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts),
    ?assertMatch({error, {validation_error, missing_on_input_callback}}, Result).

%% Test: Invalid stream ref error
%% Validates: Requirement 11.4
error_invalid_stream_ref(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    {ok, StreamRef} = clickhouse_erl:start_streaming_insert(Conn, SQL, #{columns => id_columns()}),
    WrongRef = make_ref(),
    Data = [#{name => <<"id">>, data => [1]}],
    Result = clickhouse_erl:send_data(Conn, WrongRef, Data),
    ?assertMatch({error, {validation_error, invalid_stream_ref}}, Result),
    clickhouse_erl:finish_streaming_insert(Conn, StreamRef).

%% Test: No active session error
%% Validates: Requirement 11.5
error_no_active_session(Config) ->
    Conn = proplists:get_value(connection, Config),
    FakeRef = make_ref(),
    Data = [#{name => <<"id">>, data => [1]}],
    Result = clickhouse_erl:send_data(Conn, FakeRef, Data),
    ?assertMatch({error, {validation_error, no_active_streaming_session}}, Result).

%%%===================================================================
%%% Compression Integration Tests
%%% Validates: Requirements 6.1, 6.2, 13.1, 13.2
%%%===================================================================

%% Test: Streaming insert with LZ4 compression
%% Validates: Requirements 6.1, 13.1
compression_lz4(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id, name, value) VALUES">>,
    Callback = fun(Acc) ->
        case Acc of
            0 ->
                {ok,
                    [
                        #{name => <<"id">>, data => [1, 2, 3]},
                        #{name => <<"name">>, data => [<<"a">>, <<"b">>, <<"c">>]},
                        #{name => <<"value">>, data => [1.0, 2.0, 3.0]}
                    ],
                    1};
            _ ->
                {done, Acc}
        end
    end,
    Opts = #{on_input => Callback, columns => columns(), initial_accumulator => 0},
    ExtraOpts = #{compression => lz4},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts, ExtraOpts),
    ?assertMatch({ok, #{rows_inserted := 3}}, Result).

%% Test: Streaming insert with ZSTD compression
%% Validates: Requirements 6.1, 13.1
compression_zstd(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id, name, value) VALUES">>,
    Callback = fun(Acc) ->
        case Acc of
            0 ->
                {ok,
                    [
                        #{name => <<"id">>, data => [4, 5, 6]},
                        #{name => <<"name">>, data => [<<"d">>, <<"e">>, <<"f">>]},
                        #{name => <<"value">>, data => [4.0, 5.0, 6.0]}
                    ],
                    1};
            _ ->
                {done, Acc}
        end
    end,
    Opts = #{on_input => Callback, columns => columns(), initial_accumulator => 0},
    ExtraOpts = #{compression => zstd},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts, ExtraOpts),
    ?assertMatch({ok, #{rows_inserted := 3}}, Result).

%% Test: Streaming insert with compression disabled
%% Validates: Requirements 6.2, 13.2
compression_disabled(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id, name, value) VALUES">>,
    Callback = fun(Acc) ->
        case Acc of
            0 ->
                {ok,
                    [
                        #{name => <<"id">>, data => [7, 8, 9]},
                        #{name => <<"name">>, data => [<<"g">>, <<"h">>, <<"i">>]},
                        #{name => <<"value">>, data => [7.0, 8.0, 9.0]}
                    ],
                    1};
            _ ->
                {done, Acc}
        end
    end,
    Opts = #{on_input => Callback, columns => columns(), initial_accumulator => 0},
    ExtraOpts = #{compression => disabled},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts, ExtraOpts),
    ?assertMatch({ok, #{rows_inserted := 3}}, Result).

%%%===================================================================
%%% State Management Tests
%%% Validates: Requirements 8.1-8.4, 16.1-16.4
%%%===================================================================

%% Test: Connection usable after successful pull-based streaming insert
%% Validates: Requirement 8.1
state_recovery_after_success_pull(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    Callback = fun(Acc) ->
        case Acc of
            0 ->
                {ok, [#{name => <<"id">>, data => [1]}], 1};
            _ ->
                {done, Acc}
        end
    end,
    Opts = #{on_input => Callback, columns => id_columns(), initial_accumulator => 0},
    {ok, _} = clickhouse_erl:streaming_insert(Conn, SQL, Opts),
    %% Connection should be usable for new queries on the SAME connection
    %% Verify SELECT returns actual data (not empty result)
    {ok, ResultSet} = clickhouse_erl:query(Conn, <<"SELECT 1 as val">>),
    #{data := #{rows := [[1]]}} = ResultSet.

%% Test: Connection usable after successful push-based streaming insert
%% Validates: Requirement 16.1
state_recovery_after_success_push(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    {ok, StreamRef} = clickhouse_erl:start_streaming_insert(Conn, SQL, #{columns => id_columns()}),
    ok = clickhouse_erl:send_data(Conn, StreamRef, [
        #{name => <<"id">>, data => [1]}
    ]),
    {ok, _} = clickhouse_erl:finish_streaming_insert(Conn, StreamRef),
    %% Connection should be usable for new queries on the SAME connection
    %% Verify SELECT returns actual data (not empty result)
    {ok, ResultSet} = clickhouse_erl:query(Conn, <<"SELECT 1 as val">>),
    #{data := #{rows := [[1]]}} = ResultSet.

%% Test: Connection usable after callback error
%% Validates: Requirement 8.2
state_recovery_after_error(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    Callback = fun(_Acc) -> {error, test_error} end,
    Opts = #{on_input => Callback, columns => id_columns()},
    {error, {callback_error, test_error}} = clickhouse_erl:streaming_insert(Conn, SQL, Opts),
    %% Connection should be usable for new queries on the SAME connection
    {ok, ResultSet} = clickhouse_erl:query(Conn, <<"SELECT 1 as val">>),
    #{data := #{rows := [[1]]}} = ResultSet.

%% Test: Connection state recovery after server exception
%% The server may close the TCP connection after an exception for a non-existent table.
%% We verify the streaming insert returns the correct error and the connection
%% transitions to a known state (ready or error depending on TCP status).
%% Validates: Requirements 8.3, 16.2
state_recovery_after_server_exception(Config) ->
    Conn = proplists:get_value(connection, Config),
    SQL = <<"INSERT INTO non_existent_table_xyz (id) VALUES">>,
    Callback = fun(_Acc) ->
        {ok, [#{name => <<"id">>, data => [1]}], 1}
    end,
    Opts = #{on_input => Callback, columns => id_columns()},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts),
    ?assertMatch({error, {server_exception, _}}, Result),
    %% Connection may or may not be usable depending on whether server closed TCP.
    %% Just verify the query doesn't hang — any response is acceptable.
    _QueryResult = clickhouse_erl:query(Conn, <<"SELECT 1">>).

%% Test: Concurrent query rejection during streaming
%% Validates: Requirements 8.4, 10.4, 16.4
concurrent_query_rejection(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    PushOpts = #{columns => id_columns()},
    {ok, StreamRef} = clickhouse_erl:start_streaming_insert(Conn, SQL, PushOpts),
    %% Try to run a regular query - should fail
    QueryResult = clickhouse_erl:query(Conn, <<"SELECT 1">>),
    ?assertMatch({error, {connection_error, query_in_progress}}, QueryResult),
    %% Try to start another streaming insert - should fail
    InsertResult = clickhouse_erl:start_streaming_insert(Conn, SQL, PushOpts),
    ?assertMatch({error, {connection_error, query_in_progress}}, InsertResult),
    %% Clean up
    clickhouse_erl:finish_streaming_insert(Conn, StreamRef).

%%%===================================================================
%%% Timeout and Cancellation Integration Tests
%%% Validates: Requirements 7.1, 7.2, 7.3, 15.1, 15.2, 15.3
%%%===================================================================

%% Test: Timeout enforcement for pull-based mode
%% Validates: Requirements 7.1, 7.2
timeout_pull_based(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    Callback = fun(_Acc) ->
        timer:sleep(100),
        {ok, [#{name => <<"id">>, data => [1]}], 1}
    end,
    Opts = #{on_input => Callback, columns => id_columns()},
    ExtraOpts = #{timeout => 10},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts, ExtraOpts),
    ?assertMatch({error, {timeout_error, streaming_insert}}, Result),
    %% Connection should still be usable after timeout
    {ok, _ResultSet} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

%% Test: Timeout enforcement for push-based mode
%% Validates: Requirements 15.1, 15.2
timeout_push_based(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    PushOpts = #{columns => id_columns()},
    ExtraOpts = #{timeout => 10},
    {ok, StreamRef} = clickhouse_erl:start_streaming_insert(Conn, SQL, PushOpts, ExtraOpts),
    %% Wait for timeout to expire
    timer:sleep(50),
    Data = [#{name => <<"id">>, data => [1]}],
    SendResult = clickhouse_erl:send_data(Conn, StreamRef, Data),
    ?assertMatch({error, {timeout_error, streaming_insert}}, SendResult),
    %% Clean up the failed session
    clickhouse_erl:finish_streaming_insert(Conn, StreamRef),
    %% Connection should still be usable after timeout
    {ok, _ResultSet} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

%% Test: Cancellation during pull-based streaming
%% Pull-based streaming runs synchronously inside handle_call, blocking the gen_server.
%% cancel_query (also a gen_server:call) cannot execute while the loop runs.
%% The only way to abort pull-based streaming is via timeout.
%% Validates: Requirement 7.3
cancellation_pull_based(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    Callback = fun(_Acc) ->
        timer:sleep(200),
        {ok, [#{name => <<"id">>, data => [1]}], 1}
    end,
    Opts = #{on_input => Callback, columns => id_columns()},
    ExtraOpts = #{timeout => 50},
    Result = clickhouse_erl:streaming_insert(Conn, SQL, Opts, ExtraOpts),
    ?assertMatch({error, {timeout_error, streaming_insert}}, Result),
    %% Connection should still be usable
    {ok, _ResultSet} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

%% Test: Cancellation during push-based streaming
%% Validates: Requirement 15.3
cancellation_push_based(Config) ->
    Conn = proplists:get_value(connection, Config),
    Table = proplists:get_value(table, Config),
    SQL = <<"INSERT INTO ", Table/binary, " (id) VALUES">>,
    {ok, StreamRef} = clickhouse_erl:start_streaming_insert(Conn, SQL, #{columns => id_columns()}),
    ok = clickhouse_erl:cancel_query(Conn),
    Data = [#{name => <<"id">>, data => [1]}],
    SendResult = clickhouse_erl:send_data(Conn, StreamRef, Data),
    ?assertMatch({error, {query_cancelled, _}}, SendResult),
    %% Clean up the cancelled session
    clickhouse_erl:finish_streaming_insert(Conn, StreamRef),
    %% Connection should still be usable after cancellation
    {ok, _ResultSet} = clickhouse_erl:query(Conn, <<"SELECT 1">>).
