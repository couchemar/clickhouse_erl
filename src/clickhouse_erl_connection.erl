%%%-------------------------------------------------------------------
%% @doc ClickHouse connection manager gen_server
%%
%% This module implements a gen_server that manages individual ClickHouse
%% database connections. It handles TCP connection establishment, protocol
%% handshake, and connection state management.
%%
%% == Query Lifecycle Management ==
%%
%% Each connection handles one active query at a time. For concurrent query
%% execution, use multiple connections (see connection pooling in Phase 3).
%%
%% === Basic Query Execution ===
%%
%% Execute a SELECT query:
%% ```
%% {ok, Conn} = clickhouse_erl_connection:connect("localhost", 9000, #{}),
%% PreparedRequest = #{
%%     sql => <<"SELECT number FROM system.numbers LIMIT 10">>,
%%     query_id => <<"my-query-123">>
%% },
%% {ok, Result} = clickhouse_erl_connection:query(Conn, PreparedRequest),
%% clickhouse_erl_connection:disconnect(Conn).
%% '''
%%
%% === Streaming Query Results ===
%%
%% For large result sets, use streaming mode to process data incrementally
%% without loading everything into memory. Provide an `on_data` callback that
%% processes each data block as it arrives:
%%
%% ```
%% PreparedRequest = #{
%%     sql => <<"SELECT number FROM system.numbers LIMIT 100000">>,
%%     query_id => <<"streaming-query">>,
%%     on_data => fun(DataBlock, Acc) ->
%%         % Process each data block incrementally
%%         RowCount = maps:get(rows, DataBlock, 0),
%%         NewCount = Acc + RowCount,
%%         io:format("Processed ~p rows (total: ~p)~n", [RowCount, NewCount]),
%%         {ok, NewCount}
%%     end,
%%     initial_accumulator => 0
%% },
%% {ok, Result} = clickhouse_erl_connection:query(Conn, PreparedRequest),
%% FinalCount = maps:get(data, Result),
%% io:format("Total rows processed: ~p~n", [FinalCount]).
%% '''
%%
%% ==== Callback Function Signatures ====
%%
%% Data callback (required for streaming):
%% ```
%% fun(DataBlock :: map(), Accumulator :: term()) ->
%%     {ok, NewAccumulator :: term()} | {error, Reason :: term()}
%% '''
%%
%% Optional monitoring callbacks:
%% ```
%% on_progress => fun(ProgressInfo :: map()) -> ok | {error, Reason :: term()}
%% on_profile => fun(ProfileInfo :: map()) -> ok | {error, Reason :: term()}
%% on_profile_events => fun(ProfileEvents :: map()) -> ok | {error, Reason :: term()}
%% '''
%%
%% ==== Result Format Differences ====
%%
%% Streaming mode returns the final accumulator under the `data` key:
%% ```
%% {ok, #{
%%     data => FinalAccumulator,
%%     statistics => #{elapsed_time => Milliseconds}
%% }}
%% '''
%%
%% Batch mode (no callback) returns accumulated data:
%% ```
%% {ok, #{
%%     data => #{columns => [...], rows => [...]},
%%     statistics => #{elapsed_time => Milliseconds}
%% }}
%% '''
%%
%% ==== Memory Efficiency ====
%%
%% Streaming mode processes data blocks incrementally without accumulating them
%% in memory. This enables processing datasets larger than available RAM:
%%
%% ```
%% % Process 10 million rows with constant memory usage
%% PreparedRequest = #{
%%     sql => <<"SELECT * FROM large_table">>,
%%     query_id => <<"large-query">>,
%%     on_data => fun(DataBlock, Acc) ->
%%         % Extract and process rows
%%         Rows = extract_rows(DataBlock),
%%         % Write to file, send to another system, etc.
%%         write_to_file(Rows),
%%         % Accumulator tracks progress, not data
%%         {ok, Acc + length(Rows)}
%%     end,
%%     initial_accumulator => 0
%% }.
%% '''
%%
%% ==== Callback Error Handling ====
%%
%% If a callback returns `{error, Reason}`, the query terminates immediately:
%% ```
%% on_data => fun(DataBlock, Acc) ->
%%     case validate_data(DataBlock) of
%%         ok -> {ok, [DataBlock | Acc]};
%%         {error, Reason} -> {error, {validation_failed, Reason}}
%%     end
%% end
%% '''
%%
%% Callback crashes are caught and wrapped:
%% ```
%% {error, {callback_crashed, {Class, Reason, Stacktrace}}}
%% '''
%%
%% Invalid callback returns are detected:
%% ```
%% {error, {invalid_callback_return, ReturnValue}}
%% '''
%%
%% The connection remains usable after callback errors.
%%
%% ==== Callback Execution Context ====
%%
%% Callbacks execute synchronously within the connection gen_server process.
%% Blocking callbacks will block the connection but not affect other connections.
%% Keep callbacks fast to maintain responsiveness.
%%
%% === Query Execution with Timeout ===
%%
%% Set a custom timeout (in milliseconds) to prevent queries from running
%% indefinitely. If the query exceeds the timeout, it will be automatically
%% cancelled:
%% ```
%% PreparedRequest = #{
%%     sql => <<"SELECT sleep(3)">>,
%%     query_id => <<"timeout-query">>,
%%     timeout => 5000  % 5 second timeout
%% },
%% case clickhouse_erl_connection:query(Conn, PreparedRequest) of
%%     {ok, Result} ->
%%         io:format("Query completed: ~p~n", [Result]);
%%     {error, {timeout_error, query_execution}} ->
%%         io:format("Query timed out and was cancelled~n")
%% end.
%% '''
%%
%% Default timeout is 30 seconds. Use `infinity` for no timeout (not recommended
%% for production).
%%
%% === Query Cancellation ===
%%
%% Cancel a long-running query mid-execution:
%% ```
%% % Start a long-running query in a separate process
%% QueryId = <<"long-query-456">>,
%% spawn(fun() ->
%%     PreparedRequest = #{
%%         sql => <<"SELECT sleep(3) FROM system.numbers LIMIT 1000">>,
%%         query_id => QueryId
%%     },
%%     clickhouse_erl_connection:query(Conn, PreparedRequest)
%% end),
%%
%% % Cancel the query from another process
%% timer:sleep(100),  % Let query start
%% ok = clickhouse_erl_connection:cancel_query(Conn, QueryId).
%% '''
%%
%% After cancellation, the connection waits for the server to send END_OF_STREAM
%% before accepting new queries. The cancelled query returns:
%% `{error, {query_cancelled, QueryId}}'
%%
%% === Error Handling Patterns ===
%%
%% All operations return `{ok, Result}' or `{error, Reason}' tuples. Common
%% error types:
%%
%% ```
%% case clickhouse_erl_connection:query(Conn, PreparedRequest) of
%%     {ok, Result} ->
%%         process_result(Result);
%%
%%     % Query timeout - automatically cancelled
%%     {error, {timeout_error, query_execution}} ->
%%         handle_timeout();
%%
%%     % Query cancelled by client
%%     {error, {query_cancelled, QueryId}} ->
%%         handle_cancellation(QueryId);
%%
%%     % Network errors - connection may be unusable
%%     {error, {network_error, Reason}} ->
%%         reconnect_and_retry();
%%
%%     % Protocol errors - invalid state or request
%%     {error, {protocol_error, Details}} ->
%%         log_error(Details);
%%
%%     % Server exceptions - SQL errors, permission issues, etc.
%%     {error, {server_exception, ExceptionInfo}} ->
%%         ErrorMsg = clickhouse_erl_exception:format(ExceptionInfo),
%%         handle_server_error(ErrorMsg)
%% end.
%% '''
%%
%% === Concurrent Query Execution ===
%%
%% Each connection handles one query at a time. Attempting to execute a second
%% query while one is active returns an error:
%% ```
%% {error, {protocol_error, "Connection busy with another query"}}
%% '''
%%
%% For concurrent queries, create multiple connections:
%% ```
%% % Create connection pool
%% Connections = [
%%     begin
%%         {ok, Conn} = clickhouse_erl_connection:connect("localhost", 9000, #{}),
%%         Conn
%%     end || _ <- lists:seq(1, 5)
%% ],
%%
%% % Execute queries concurrently
%% Results = [
%%     spawn_monitor(fun() ->
%%         PreparedRequest = #{
%%             sql => <<"SELECT ", (integer_to_binary(N))/binary>>,
%%             query_id => <<"query-", (integer_to_binary(N))/binary>>
%%         },
%%         clickhouse_erl_connection:query(Conn, PreparedRequest)
%%     end) || {N, Conn} <- lists:zip(lists:seq(1, 5), Connections)
%% ].
%% '''
%%
%% === Query Parameters Error Handling ===
%%
%% Query parameters provide comprehensive error handling for both client-side
%% validation and server-side errors.
%%
%% ==== Client-Side Validation Errors ====
%%
%% These errors occur before sending the query to the server:
%%
%% ```
%% % Invalid parameter key (not a binary)
%% PreparedRequest = #{
%%     sql => <<"SELECT {id:UInt64}">>,
%%     parameters => [{id, <<"123">>}]  % Atom key instead of binary
%% },
%% {error, {invalid_parameter_key, id}} =
%%     clickhouse_erl_connection:query(Conn, PreparedRequest).
%%
%% % Invalid parameter value (not a binary)
%% PreparedRequest = #{
%%     sql => <<"SELECT {id:UInt64}">>,
%%     parameters => [{<<"id">>, 123}]  % Integer value instead of binary
%% },
%% {error, {invalid_parameter_value, 123}} =
%%     clickhouse_erl_connection:query(Conn, PreparedRequest).
%%
%% % Malformed parameter (not a tuple)
%% PreparedRequest = #{
%%     sql => <<"SELECT {id:UInt64}">>,
%%     parameters => [<<"id">>, <<"123">>]  % List instead of tuple
%% },
%% {error, {invalid_parameter_format, <<"id">>}} =
%%     clickhouse_erl_connection:query(Conn, PreparedRequest).
%%
%% % Unsupported protocol version
%% PreparedRequest = #{
%%     sql => <<"SELECT {id:UInt64}">>,
%%     parameters => [{<<"id">>, <<"123">>}]
%% },
%% {error, {parameters_unsupported, 54400}} =
%%     clickhouse_erl_connection:query(Conn, PreparedRequest).
%% '''
%%
%% ==== Server-Side Errors ====
%%
%% These errors occur after sending the query to the server:
%%
%% ```
%% % Missing substitution - parameter not provided
%% PreparedRequest = #{
%%     sql => <<"SELECT {missing:UInt64}">>,
%%     parameters => []
%% },
%% {error, {server_exception, ExceptionInfo}} =
%%     clickhouse_erl_connection:query(Conn, PreparedRequest).
%% % ExceptionInfo contains: #{message => <<"Substitution `missing` is not set">>, ...}
%%
%% % Type mismatch - value doesn't match type
%% PreparedRequest = #{
%%     sql => <<"SELECT {value:UInt64}">>,
%%     parameters => [{<<"value">>, <<"not_a_number">>}]
%% },
%% {error, {server_exception, ExceptionInfo}} =
%%     clickhouse_erl_connection:query(Conn, PreparedRequest).
%% % ExceptionInfo contains type mismatch error message
%% '''
%%
%% ==== Error Type Reference ====
%%
%% | Error Type | Description | When It Occurs |
%% |------------|-------------|----------------|
%% | `{invalid_parameter_key, Key}` | Parameter key is not a binary | Client validation |
%% | `{invalid_parameter_value, Value}` | Parameter value is not a binary |
%% |                                     | Client validation |
%% | `{invalid_parameter_format, Param}` | Parameter is not a `{Key, Value}` tuple |
%% |                                     | Client validation |
%% | `{parameters_unsupported, Version}` | Server protocol version < 54459 |
%% |                                     | Client validation |
%% | `{server_exception, ExceptionInfo}` | Server-side errors (missing substitution, |
%% |                                     | type mismatch) | Server response |
%%
%% ==== Error Recovery ====
%%
%% Parameter errors are deterministic and require user correction. The connection
%% remains usable after parameter errors:
%%
%% ```
%% case clickhouse_erl_connection:query(Conn, PreparedRequest) of
%%     {ok, Result} ->
%%         process_result(Result);
%%     {error, {invalid_parameter_key, Key}} ->
%%         % Fix parameter format and retry
%%         FixedRequest = fix_parameter_key(PreparedRequest, Key),
%%         clickhouse_erl_connection:query(Conn, FixedRequest);
%%     {error, {parameters_unsupported, Version}} ->
%%         % Fallback to non-parameterized query
%%         execute_without_parameters(Conn, PreparedRequest);
%%     {error, {server_exception, ExceptionInfo}} ->
%%         % Log server error and fix query
%%         ?LOG_ERROR("Server error", #{exception => ExceptionInfo}),
%%         fix_query_and_retry(Conn, PreparedRequest)
%% end.
%% '''
%%
%% == Compression Support ==
%%
%% The connection layer supports data compression for efficient network transfer.
%% Compression reduces bandwidth usage and can significantly improve performance
%% when transferring large datasets.
%%
%% === Enabling Compression ===
%%
%% Specify compression method in connection options:
%%
%% ```
%% % LZ4 compression (recommended - fast with good compression)
%% {ok, Conn} = clickhouse_erl_connection:connect("localhost", 9000, #{
%%     compression => lz4
%% }).
%%
%% % ZSTD compression (better compression ratios)
%% {ok, Conn} = clickhouse_erl_connection:connect("localhost", 9000, #{
%%     compression => zstd
%% }).
%%
%% % LZ4HC with compression level (0-12)
%% {ok, Conn} = clickhouse_erl_connection:connect("localhost", 9000, #{
%%     compression => lz4,
%%     compression_level => 9
%% }).
%%
%% % Disabled (default - backward compatible)
%% {ok, Conn} = clickhouse_erl_connection:connect("localhost", 9000, #{}).
%% '''
%%
%% === Compression Methods ===
%%
%% - **lz4**: Fast compression with good ratios (recommended for most use cases)
%% - **lz4 with level**: LZ4HC with configurable compression level 0-12
%% - **zstd**: Better compression ratios at the cost of speed
%% - **none**: Uncompressed data with compression protocol wrapper
%% - **disabled**: No compression (default)
%%
%% === Automatic Compression ===
%%
%% Once enabled, compression is applied automatically to all compressible packets:
%%
%% ```
%% {ok, Conn} = clickhouse_erl_connection:connect("localhost", 9000, #{
%%     compression => lz4
%% }),
%%
%% % All queries automatically use compression
%% {ok, Result} = clickhouse_erl_connection:query(Conn, PreparedRequest),
%%
%% % INSERT operations also use compression
%% {ok, InsertResult} = clickhouse_erl_connection:insert(Conn, InsertRequest).
%% '''
%%
%% === Compression Error Handling ===
%%
%% Compression errors are returned as error tuples:
%%
%% ```
%% case clickhouse_erl_connection:connect("localhost", 9000, #{compression => lz4}) of
%%     {ok, Conn} ->
%%         use_connection(Conn);
%%     {error, {compression_library_missing, lz4}} ->
%%         io:format("LZ4 library not installed~n");
%%     {error, {invalid_compression_method, Method}} ->
%%         io:format("Unsupported compression method: ~p~n", [Method]);
%%     {error, {invalid_compression_level, Level}} ->
%%         io:format("Invalid compression level: ~p (must be 0-12)~n", [Level])
%% end.
%% '''
%%
%% During query execution, compression errors are handled gracefully:
%%
%% ```
%% case clickhouse_erl_connection:query(Conn, PreparedRequest) of
%%     {ok, Result} ->
%%         process_result(Result);
%%     {error, {checksum_mismatch, Details}} ->
%%         % Data corruption detected
%%         handle_corruption(Details);
%%     {error, {decompression_failed, Reason}} ->
%%         % Decompression error
%%         handle_decompression_error(Reason);
%%     {error, {server_error, cannot_decompress}} ->
%%         % Server-side decompression failure
%%         handle_server_error()
%% end.
%% '''
%%
%% === Performance Considerations ===
%%
%% Compression is most effective for:
%% - Large result sets (>1MB)
%% - Highly compressible data (text, logs, repeated values)
%% - Bandwidth-constrained environments
%%
%% Skip compression for:
%% - Small datasets (<1KB)
%% - Already compressed data
%% - CPU-constrained environments with fast networks
%%
%% === Backward Compatibility ===
%%
%% Compression is disabled by default. Existing code continues to work without
%% changes:
%%
%% ```
%% % These are equivalent - no compression
%% {ok, Conn1} = clickhouse_erl_connection:connect("localhost", 9000, #{}).
%% {ok, Conn2} = clickhouse_erl_connection:connect("localhost", 9000, #{
%%     compression => disabled
%% }).
%% '''
%%
%% @see clickhouse_erl_compression
%% @see clickhouse_erl_cityhash
%%
%% @end
%%%-------------------------------------------------------------------

-module(clickhouse_erl_connection).
-include_lib("kernel/include/logger.hrl").
-include("clickhouse_erl_protocol.hrl").

-behaviour(gen_server).

%% Public API
-export([
    connect/3,
    disconnect/1,
    get_connection_info/1,
    format_error/1,
    is_compatible_version/1,
    query/2,
    insert/2,
    cancel_query/1,
    cancel_query/2,
    % Callback validation (exported for testing)
    validate_callback/2,
    validate_prepared_request/1,
    % Optional callback invocation (exported for testing)
    invoke_optional_callback/2,
    % Parameter validation (exported for testing)
    validate_parameters/1,
    % Version check for parameters (exported for testing)
    should_send_parameters/2,
    % Compression validation (exported for testing)
    validate_and_normalize_compression_opts/1,
    % AccState initialization (exported for testing)
    init_acc_state/1,
    % Event processing (exported for testing)
    process_events/2,
    % Single event processing (exported for testing)
    process_single_event/5,
    % Query result building (exported for testing)
    build_query_result/1,
    % Default streaming callback (exported for testing and fun reference)
    default_on_data_callback/2,
    % Default on_log callback (exported for testing and fun reference)
    default_on_log_callback/1,
    % ActiveQueryState builder (exported for testing)
    build_active_query_state/7,
    % Streaming insert loop helpers (exported for testing)
    streaming_loop/5,
    check_server_response/2,
    % Block encoding and sending (exported for testing)
    encode_and_send_block/2,
    % Streaming insert API (exported for testing)
    get_push_session/1,
    check_push_session_valid/2,
    handle_send_data/4,
    send_and_check/4,
    handle_finish_streaming/2,
    streaming_insert/2,
    start_streaming_insert/2,
    send_data/3,
    finish_streaming_insert/2,
    % Connection state management (exported for testing)
    clear_active_query_state/1,
    clear_active_query_state/2
]).

-ignore_xref([
    connect/3,
    format_error/1,
    is_compatible_version/1,
    validate_callback/2,
    validate_prepared_request/1,
    invoke_optional_callback/2,
    validate_parameters/1,
    should_send_parameters/2,
    validate_and_normalize_compression_opts/1,
    init_acc_state/1,
    process_events/2,
    process_single_event/5,
    build_query_result/1,
    default_on_data_callback/2,
    default_on_log_callback/1,
    build_active_query_state/7,
    get_push_session/1,
    check_push_session_valid/2,
    handle_send_data/4,
    send_and_check/4,
    handle_finish_streaming/2,
    safe_invoke_on_input/3,
    encode_and_send_block/2,
    streaming_loop/5,
    check_server_response/2,
    streaming_insert/2,
    start_streaming_insert/2,
    send_data/3,
    finish_streaming_insert/2,
    clear_active_query_state/1,
    clear_active_query_state/2
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_continue/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% Protocol version compatibility
-define(MIN_SUPPORTED_PROTOCOL_VERSION, 54400).
-define(MAX_SUPPORTED_PROTOCOL_VERSION, 54500).

%% Default values
-define(DEFAULT_DATABASE, "default").
-define(DEFAULT_USERNAME, "default").
-define(DEFAULT_PASSWORD, "").
-define(DEFAULT_CLIENT_NAME, "clickhouse_erl").
-define(DEFAULT_CLIENT_VERSION, {0, 1, 0}).

%% Timeouts
-define(CONNECT_TIMEOUT, 5000).
-define(HANDSHAKE_TIMEOUT, 10000).
-define(DEFAULT_QUERY_TIMEOUT, 30000).

%% Type definitions
-type connection_options() :: #{
    database => binary() | string(),
    username => binary() | string(),
    password => binary() | string(),
    timeout => timeout(),
    client_name => binary() | string(),
    client_version => {
        Major :: non_neg_integer(), Minor :: non_neg_integer(), Patch :: non_neg_integer()
    },
    compression => lz4 | zstd | none | disabled,
    compression_level => 0..12
}.

-type connection_info() :: #{
    server_name => binary(),
    server_version => {
        Major :: non_neg_integer(), Minor :: non_neg_integer(), Patch :: non_neg_integer()
    },
    server_revision => non_neg_integer(),
    server_timezone => binary(),
    server_display_name => binary(),
    state => connecting | ready | error
}.

-type connection_error() ::
    {network_error, Reason :: term()}
    | {protocol_error, Details :: string()}
    | {timeout_error, Phase :: atom()}
    | {compatibility_error, {server_version, Version :: term()}}
    | {encoding_error, Field :: atom()}
    | {decoding_error, {invalid_format, Details :: string()}}
    | {resource_cleanup_error, Details :: string()}
    | {server_exception, exception_info()}
    | exception_parsing_error().

%% Connection state record (shared with test files)
-include("clickhouse_erl_connection.hrl").

-type active_query_state() :: #{
    caller := {pid(), term()},
    query_id := binary(),
    timeout := timeout(),
    timer_ref := reference() | undefined,
    cancelled := boolean(),
    replied := boolean(),
    is_insert => boolean(),
    rows_to_insert => non_neg_integer(),
    %% Always present — default or user-provided
    on_data := function(),
    accumulator := term(),
    on_progress := function(),
    on_profile := function(),
    on_profile_events := function(),
    on_log := function(),
    %% Compression options from connection state
    compression_opts => clickhouse_erl_compression:compression_opts() | undefined,
    %% Event-driven parser state
    parser_state => term() | undefined,
    %% Current column name for event dispatch
    current_column_name => binary() | undefined
}.

-type state() :: #connection_state{}.

%% Default callback accumulator shape
-type default_callback_acc() :: #{
    column_order := [binary()],
    column_meta := #{binary() => #{name := binary(), type := binary()}},
    column_values := #{binary() => [term()]}
}.

%% Batch result format produced by default callback on 'end'
-type batch_result() :: #{
    columns := [#{name := binary(), type := binary()}],
    rows := [[term()]]
}.

%% Export types for other modules
-export_type([
    connection_options/0,
    connection_info/0,
    connection_error/0,
    default_callback_acc/0,
    streaming_insert_result/0
]).

-type streaming_insert_result() :: #{
    rows_inserted := non_neg_integer(),
    blocks_sent := non_neg_integer(),
    elapsed_time := non_neg_integer()
}.

%%%===================================================================
%%% Public API
%%%===================================================================

%% @doc Establish a new connection to a ClickHouse server.
%%
%% Spawns a connection manager process and performs TCP handshake.
%%
%% Connection options include:
%% - `database' - Target database (default: "default")
%% - `username' - Authentication username (default: "default")
%% - `password' - Authentication password (default: "")
%% - `timeout' - Connection timeout in milliseconds (default: 5000)
%% - `client_name' - Client identification string
%% - `client_version' - Client version tuple {Major, Minor, Patch}
%% - `compression' - Compression method: lz4 | zstd | none | disabled (default: disabled)
%% - `compression_level' - LZ4HC compression level 0-12 (only for lz4 method)
%%
%% Compression examples:
%% ```
%% % LZ4 compression (fast, recommended)
%% {ok, Conn} = connect("localhost", 9000, #{compression => lz4}).
%%
%% % LZ4HC with level 9 (better compression)
%% {ok, Conn} = connect("localhost", 9000, #{
%%     compression => lz4,
%%     compression_level => 9
%% }).
%%
%% % ZSTD compression (best compression ratios)
%% {ok, Conn} = connect("localhost", 9000, #{compression => zstd}).
%%
%% % No compression (default, backward compatible)
%% {ok, Conn} = connect("localhost", 9000, #{}).
%% '''
%%
%% Compression error cases:
%% - `{error, {compression_library_missing, Method}}' - Library not installed
%% - `{error, {invalid_compression_method, Method}}' - Unsupported method
%% - `{error, {invalid_compression_level, Level}}' - Level outside 0-12 range
%%
%% @param Host Hostname or IP address.
%% @param Port ClickHouse native protocol port.
%% @param Options Connection configuration map.
%% @returns {ok, Pid} or {error, Reason}.
-spec connect(Host, Port, Options) -> {ok, Pid} | {error, Reason} when
    Host :: string() | inet:ip_address(),
    Port :: inet:port_number(),
    Options :: connection_options(),
    Pid :: pid(),
    Reason :: connection_error().
connect(Host, Port, Options) ->
    case gen_server:start_link(?MODULE, {Host, Port, Options}, []) of
        {ok, Pid} ->
            % Wait for connection to complete by calling a synchronous operation
            % that will only return after handle_continue completes
            case
                gen_server:call(
                    Pid, wait_for_connection, ?CONNECT_TIMEOUT + ?HANDSHAKE_TIMEOUT + 5000
                )
            of
                {ok, ready} ->
                    {ok, Pid};
                {error, Reason} ->
                    gen_server:stop(Pid),
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Close the ClickHouse connection.
%%
%% @param Connection Connection manager pid.
%% @returns ok.
-spec disconnect(Connection) -> ok when
    Connection :: pid().
disconnect(Connection) ->
    gen_server:stop(Connection).

%% @doc Retrieve current connection metadata.
%%
%% @param Connection Connection manager pid.
%% @returns {ok, Info} or {error, Reason}.
-spec get_connection_info(Connection) -> {ok, Info} | {error, Reason} when
    Connection :: pid(),
    Info :: connection_info(),
    Reason :: connection_error().
get_connection_info(Connection) ->
    gen_server:call(Connection, get_connection_info).

%% @doc Execute a non-INSERT SQL query.
%%
%% The PreparedRequest map supports the following options:
%% - sql (required): The SQL query string
%% - query_id (optional): Unique query identifier (auto-generated if not provided)
%% - parameters (optional): List of query parameters as [{Key :: binary(), Value :: binary()}]
%% - timeout (optional): Query timeout in milliseconds (default: 30000)
%% - on_data (optional): Streaming callback function
%% - initial_accumulator (optional): Initial accumulator for streaming mode
%% - on_progress (optional): Progress callback function
%% - on_profile (optional): Profile callback function
%% - on_profile_events (optional): Profile events callback function
%%
%% Query parameters enable safe parameterized queries using placeholder syntax.
%% Example:
%% ```
%% PreparedRequest = #{
%%     sql => <<"SELECT * FROM users WHERE id = {user_id:UInt64}">>,
%%     parameters => [{<<"user_id">>, <<"12345">>}]
%% },
%% {ok, Result} = clickhouse_erl_connection:query(Conn, PreparedRequest).
%% '''
%%
%% Multiple parameters example:
%% ```
%% PreparedRequest = #{
%%     sql => <<"SELECT * FROM users WHERE id = {id:UInt64} AND name = {name:String}">>,
%%     parameters => [
%%         {<<"id">>, <<"42">>},
%%         {<<"name">>, <<"Alice">>}
%%     ]
%% },
%% {ok, Result} = clickhouse_erl_connection:query(Conn, PreparedRequest).
%% '''
%%
%% Parameters are only supported on ClickHouse servers with protocol version >= 54459.
%% If parameters are provided for an unsupported version, an error is returned:
%% `{error, {parameters_unsupported, Version}}'
%%
%% Error handling examples:
%% ```
%% case clickhouse_erl_connection:query(Conn, PreparedRequest) of
%%     {ok, Result} ->
%%         process_result(Result);
%%     {error, {invalid_parameter_key, Key}} ->
%%         io:format("Parameter key must be binary: ~p~n", [Key]);
%%     {error, {invalid_parameter_value, Value}} ->
%%         io:format("Parameter value must be binary: ~p~n", [Value]);
%%     {error, {invalid_parameter_format, Param}} ->
%%         io:format("Parameter must be {Key, Value} tuple: ~p~n", [Param]);
%%     {error, {parameters_unsupported, Version}} ->
%%         io:format("Parameters not supported in version ~p~n", [Version]);
%%     {error, {server_exception, ExceptionInfo}} ->
%%         % Server errors like missing substitution or type mismatch
%%         io:format("Server error: ~s~n", [maps:get(message, ExceptionInfo)])
%% end.
%% '''
%%
%% For backward compatibility, queries without parameters continue to work:
%% ```
%% PreparedRequest = #{sql => <<"SELECT 1">>},
%% {ok, Result} = clickhouse_erl_connection:query(Conn, PreparedRequest).
%% '''
%%
%% @param Connection Connection manager pid.
%% @param PreparedRequest Prepared query information.
%% @returns {ok, Result} or {error, Reason}.
-spec query(Connection, PreparedRequest) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    PreparedRequest :: map(),
    Result :: term(),
    Reason :: connection_error().
query(Connection, PreparedRequest) ->
    gen_server:call(Connection, {query, PreparedRequest}, 30000).

%% @doc Execute an INSERT SQL query with data blocks.
%%
%% The PreparedRequest map supports the following options:
%% - sql (required): The INSERT SQL statement
%% - input (required): Column-oriented data blocks
%% - query_id (optional): Unique query identifier (auto-generated if not provided)
%% - parameters (optional): List of query parameters as [{Key :: binary(), Value :: binary()}]
%% - timeout (optional): Query timeout in milliseconds (default: 30000)
%%
%% Query parameters can be used in INSERT statements for parameterized values.
%% Example:
%% ```
%% PreparedRequest = #{
%%     sql => <<"INSERT INTO users (id, name, age) VALUES ",
%%              "({id:UInt32}, {name:String}, {age:UInt8})">>,
%%     input => [],  % No column data when using parameters
%%     parameters => [
%%         {<<"id">>, <<"123">>},
%%         {<<"name">>, <<"Bob">>},
%%         {<<"age">>, <<"30">>}
%%     ]
%% },
%% {ok, #{rows_inserted := 1}} = clickhouse_erl_connection:insert(Conn, PreparedRequest).
%% '''
%%
%% Parameters are only supported on ClickHouse servers with protocol version >= 54459.
%% If parameters are provided for an unsupported version, an error is returned:
%% `{error, {parameters_unsupported, Version}}'
%%
%% For backward compatibility, INSERT queries without parameters continue to work:
%% ```
%% PreparedRequest = #{
%%     sql => <<"INSERT INTO users (id, name) VALUES">>,
%%     input => [
%%         #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
%%         #{name => <<"name">>, type => <<"String">>,
%%          data => [<<"Alice">>, <<"Bob">>, <<"Charlie">>]}
%%     ]
%% },
%% {ok, #{rows_inserted := 3}} = clickhouse_erl_connection:insert(Conn, PreparedRequest).
%% '''
%%
%% @param Connection Connection manager pid.
%% @param PreparedRequest Prepared INSERT request with data blocks.
%% @returns {ok, InsertResult} or {error, Reason}.
-spec insert(Connection, PreparedRequest) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    PreparedRequest :: map(),
    Result :: term(),
    Reason :: connection_error().
insert(Connection, PreparedRequest) ->
    gen_server:call(Connection, {insert, PreparedRequest}, 30000).

%% @doc Execute a streaming INSERT query using pull-based pattern.
%%
%% @param Connection Connection manager pid.
%% @param PreparedRequest Prepared streaming insert request with `on_input' callback.
%% @returns {ok, Result} or {error, Reason}.
-spec streaming_insert(Connection, PreparedRequest) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    PreparedRequest :: map(),
    Result :: #{
        rows_inserted := non_neg_integer(),
        blocks_sent := non_neg_integer(),
        elapsed_time := non_neg_integer()
    },
    Reason :: connection_error().
streaming_insert(Connection, PreparedRequest) ->
    gen_server:call(Connection, {streaming_insert, PreparedRequest}, 30000).

%% @doc Start a push-based streaming insert session.
%%
%% @param Connection Connection manager pid.
%% @param PreparedRequest Prepared streaming insert request with `columns'.
%% @returns {ok, StreamRef} or {error, Reason}.
-spec start_streaming_insert(Connection, PreparedRequest) -> {ok, StreamRef} | {error, Reason} when
    Connection :: pid(),
    PreparedRequest :: map(),
    StreamRef :: term(),
    Reason :: connection_error().
start_streaming_insert(Connection, PreparedRequest) ->
    gen_server:call(Connection, {start_streaming_insert, PreparedRequest}, 30000).

%% @doc Send a data block during a push-based streaming insert session.
%%
%% @param Connection Connection manager pid.
%% @param StreamRef Stream reference from start_streaming_insert/2.
%% @param ColumnData List of column data maps.
%% @returns ok or {error, Reason}.
-spec send_data(Connection, StreamRef, ColumnData) -> ok | {error, Reason} when
    Connection :: pid(),
    StreamRef :: term(),
    ColumnData :: [map()],
    Reason :: connection_error() | validation_error | streaming_error.
send_data(Connection, StreamRef, ColumnData) ->
    gen_server:call(Connection, {send_data, StreamRef, ColumnData}, 30000).

%% @doc Finish a push-based streaming insert session.
%%
%% @param Connection Connection manager pid.
%% @param StreamRef Stream reference from start_streaming_insert/2.
%% @returns {ok, Result} or {error, Reason}.
-spec finish_streaming_insert(Connection, StreamRef) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    StreamRef :: term(),
    Result :: #{
        rows_inserted := non_neg_integer(),
        blocks_sent := non_neg_integer(),
        elapsed_time := non_neg_integer()
    },
    Reason :: connection_error() | streaming_error.
finish_streaming_insert(Connection, StreamRef) ->
    gen_server:call(Connection, {finish_streaming_insert, StreamRef}, 30000).

%% @doc Request cancellation of the currently active query.
%%
%% This is a convenience function for cancelling the active query when you
%% don't know the query ID (e.g., when the query ID was auto-generated).
%%
%% @param Connection Connection manager pid.
%% @returns ok or {error, Reason}.
-spec cancel_query(Connection) -> ok | {error, Reason} when
    Connection :: pid(),
    Reason :: connection_error() | no_active_query.
cancel_query(Connection) ->
    gen_server:call(Connection, {cancel_active_query}).

%% @doc Request cancellation of an ongoing query by query ID.
%%
%% @param Connection Connection manager pid.
%% @param QueryId Unique query ID (string or binary).
%% @returns ok or {error, Reason}.
-spec cancel_query(Connection, QueryId) -> ok | {error, Reason} when
    Connection :: pid(),
    QueryId :: string() | binary(),
    Reason :: connection_error().
cancel_query(Connection, QueryId) when is_list(QueryId) ->
    gen_server:call(Connection, {cancel_query, list_to_binary(QueryId)});
cancel_query(Connection, QueryId) when is_binary(QueryId) ->
    gen_server:call(Connection, {cancel_query, QueryId}).

%% @doc Format connection error for human-readable display
-spec format_error(Error) -> string() when
    Error :: connection_error().
format_error({network_error, connection_closed_during_query}) ->
    "Connection closed by server during query execution";
format_error({network_error, {tcp_error_during_query, Reason}}) ->
    io_lib:format("TCP error during query execution: ~p", [Reason]);
format_error({network_error, Reason}) ->
    iolist_to_binary(io_lib:format("Network error: ~p", [Reason]));
format_error({protocol_error, {data_block_encoding, {type_mismatch, ColumnName, Type, Reason}}}) ->
    iolist_to_binary(
        io_lib:format("Data block encoding failed: type mismatch for column '~s' (~s): ~p", [
            ColumnName, Type, Reason
        ])
    );
format_error({protocol_error, {data_block_encoding, Reason}}) ->
    iolist_to_binary(io_lib:format("Data block encoding failed: ~p", [Reason]));
format_error({protocol_error, Details}) when is_list(Details); is_binary(Details) ->
    iolist_to_binary(io_lib:format("Protocol error: ~s", [Details]));
format_error({protocol_error, Reason}) ->
    iolist_to_binary(io_lib:format("Protocol error: ~p", [Reason]));
format_error({timeout_error, Phase}) ->
    iolist_to_binary(io_lib:format("Timeout during ~s phase", [Phase]));
format_error({query_cancelled, QueryId}) ->
    iolist_to_binary(io_lib:format("Query cancelled: ~s", [QueryId]));
format_error({compatibility_error, {server_version, Version}}) ->
    iolist_to_binary(io_lib:format("Incompatible server version: ~p", [Version]));
format_error({encoding_error, Field}) ->
    iolist_to_binary(io_lib:format("Encoding error in field: ~p", [Field]));
format_error({decoding_error, {invalid_format, Details}}) ->
    iolist_to_binary(io_lib:format("Decoding error - invalid format: ~s", [Details]));
format_error({resource_cleanup_error, Details}) ->
    iolist_to_binary(io_lib:format("Resource cleanup error: ~s", [Details]));
format_error({server_exception, ExceptionInfo}) ->
    iolist_to_binary(
        io_lib:format("Server exception: ~s", [
            clickhouse_erl_exception:format(ExceptionInfo)
        ])
    );
format_error({exception_parsing_error, Details}) ->
    iolist_to_binary(io_lib:format("Exception parsing error: ~s", [Details]));
format_error({nested_exception_limit_exceeded, Depth}) ->
    iolist_to_binary(io_lib:format("Nested exception limit exceeded at depth ~w", [Depth]));
format_error({exception_field_truncated, Field, Length, MaxLength}) ->
    iolist_to_binary(
        io_lib:format("Exception field ~p truncated: ~w bytes (max ~w)", [Field, Length, MaxLength])
    );
format_error({invalid_exception_format, Details}) ->
    iolist_to_binary(io_lib:format("Invalid exception format: ~s", [Details]));
format_error(UnknownError) ->
    iolist_to_binary(io_lib:format("Unknown error: ~p", [UnknownError])).

%% @doc Check if a server protocol version is compatible with this client
-spec is_compatible_version(Version) -> boolean() when
    Version :: non_neg_integer().
is_compatible_version(Version) when is_integer(Version) ->
    Version >= ?MIN_SUPPORTED_PROTOCOL_VERSION andalso
        Version =< ?MAX_SUPPORTED_PROTOCOL_VERSION;
is_compatible_version(_) ->
    false.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @doc Initialize the connection gen_server
-spec init({Host, Port, Options}) -> {ok, State, {continue, establish_connection}} when
    Host :: string() | inet:ip_address(),
    Port :: inet:port_number(),
    Options :: connection_options(),
    State :: state().
init({Host, Port, Options}) ->
    % Merge provided options with defaults
    DefaultOptions = #{
        database => ?DEFAULT_DATABASE,
        username => ?DEFAULT_USERNAME,
        password => ?DEFAULT_PASSWORD,
        timeout => ?CONNECT_TIMEOUT,
        client_name => ?DEFAULT_CLIENT_NAME,
        client_version => ?DEFAULT_CLIENT_VERSION,
        compression => disabled
    },
    MergedOptions = maps:merge(DefaultOptions, Options),

    % Validate required options
    case validate_connection_options(MergedOptions) of
        ok ->
            % Validate and normalize compression options
            case validate_and_normalize_compression_opts(MergedOptions) of
                {ok, CompressionOpts} ->
                    % Initialize connection state
                    State = #connection_state{
                        socket = undefined,
                        host = Host,
                        port = Port,
                        options = MergedOptions,
                        state = connecting,
                        server_info = undefined,
                        error_reason = undefined,
                        active_queries = #{},
                        active_query_state = undefined,
                        negotiated_version = undefined,
                        compression_opts = CompressionOpts
                    },

                    % Use continue to perform connection establishment after init completes
                    {ok, State, {continue, establish_connection}};
                {error, Reason} ->
                    {stop, Reason}
            end;
        {error, Reason} ->
            {stop, Reason}
    end.

%% @doc Handle synchronous calls
-spec handle_call(Request, From, State) -> {reply, Reply, NewState} when
    Request :: get_connection_info | wait_for_connection | {query, string()} | term(),
    From :: {pid(), term()},
    State :: state(),
    Reply :: {ok, connection_info()} | {ok, ready} | {ok, term()} | {error, connection_error()},
    NewState :: state().
handle_call(get_connection_info, _From, State) ->
    case State#connection_state.state of
        ready ->
            Info = create_connection_info(State),
            {reply, {ok, Info}, State};
        error ->
            reply_with_error_reason(State);
        connecting ->
            Info = create_connection_info(State),
            {reply, {ok, Info}, State}
    end;
handle_call(wait_for_connection, _From, State) ->
    case State#connection_state.state of
        ready ->
            {reply, {ok, ready}, State};
        error ->
            reply_with_error_reason(State);
        connecting ->
            % Connection is still in progress, this should not happen
            % since handle_continue should complete before this call is processed
            {reply, {error, {protocol_error, "Connection still in progress"}}, State}
    end;
handle_call({query, PreparedRequest}, From, State) ->
    case check_connection_ready(State) of
        ok ->
            %% Check if there is already an active query
            case State#connection_state.active_query_state of
                undefined ->
                    %% Execute query and handle potential exceptions
                    case execute_query(State, PreparedRequest, From) of
                        {ok, NewState} ->
                            %% Query sent successfully, response will be handled in handle_info
                            {noreply, NewState};
                        {error, Reason} ->
                            {reply, {error, Reason}, State}
                    end;
                _ ->
                    {reply, {error, {protocol_error, "Connection busy with another query"}}, State}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;
handle_call({insert, PreparedRequest}, From, State) ->
    case check_connection_ready(State) of
        ok ->
            %% Check if there is already an active query
            case State#connection_state.active_query_state of
                undefined ->
                    %% Execute INSERT and handle potential exceptions
                    case execute_insert(State, PreparedRequest, From) of
                        {ok, NewState} ->
                            %% INSERT sent successfully, response will be handled in handle_info
                            {noreply, NewState};
                        {error, Reason} ->
                            {reply, {error, Reason}, State}
                    end;
                _ ->
                    {reply, {error, {protocol_error, "Connection busy with another query"}}, State}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;
handle_call({streaming_insert, PreparedRequest}, _From, State) ->
    case handle_streaming_insert(State, PreparedRequest) of
        {ok, Result, NewState} ->
            {reply, {ok, Result}, NewState};
        {error, Reason, NewState} ->
            {reply, {error, Reason}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;
handle_call({start_streaming_insert, PreparedRequest}, _From, State) ->
    case handle_start_streaming_insert(State, PreparedRequest) of
        {ok, StreamRef, NewState} ->
            {reply, {ok, StreamRef}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;
handle_call({send_data, StreamRef, ColumnData}, _From, State) ->
    case get_push_session(State) of
        {error, Reason} ->
            {reply, {error, Reason}, State};
        {ok, ActiveState, SessionState} ->
            case check_push_session_valid(SessionState, StreamRef) of
                {error, Reason} ->
                    {reply, {error, Reason}, State};
                ok ->
                    handle_send_data(State, ActiveState, SessionState, ColumnData)
            end
    end;
handle_call({finish_streaming_insert, StreamRef}, _From, State) ->
    case get_push_session(State) of
        {error, Reason} ->
            {reply, {error, Reason}, State};
        {ok, _ActiveState, SessionState} ->
            case maps:get(session_failed, SessionState, false) of
                {true, FailReason} ->
                    %% Network errors transition to error state;
                    %% other failures (timeout, cancellation, server exception)
                    %% transition to ready if TCP is still open
                    TargetState =
                        case FailReason of
                            {network_error, _} -> error;
                            _ -> ready
                        end,
                    NewState = clear_active_query_state(State, TargetState),
                    {reply, {error, FailReason}, NewState};
                false ->
                    case maps:get(stream_ref, SessionState) of
                        StreamRef ->
                            handle_finish_streaming(State, SessionState);
                        _ ->
                            {reply, {error, {validation_error, invalid_stream_ref}}, State}
                    end
            end
    end;
handle_call({cancel_active_query}, _From, State) ->
    ?LOG_DEBUG("Cancel active query requested", []),
    do_cancel_query(State, undefined);
handle_call({cancel_query, QueryId}, _From, State) ->
    ?LOG_DEBUG("Cancel query requested for QueryId: ~p", [QueryId]),
    do_cancel_query(State, QueryId);
handle_call(get_error_reason, _From, State) ->
    case State#connection_state.error_reason of
        undefined ->
            {reply, {error, {protocol_error, "No error reason available"}}, State};
        ErrorReason ->
            {reply, {error, ErrorReason}, State}
    end;
handle_call(_Request, _From, State) ->
    {reply, {error, {protocol_error, "Unknown request"}}, State}.

%% @doc Handle asynchronous casts
-spec handle_cast(Request, State) -> {noreply, NewState} when
    Request :: term(),
    State :: state(),
    NewState :: state().
handle_cast(_Request, State) ->
    {noreply, State}.

%% @doc Handle continue messages for deferred initialization
-spec handle_continue(Continue, State) -> {noreply, NewState} when
    Continue :: establish_connection,
    State :: state(),
    NewState :: state().
handle_continue(establish_connection, State) ->
    % Perform the actual connection establishment asynchronously
    case establish_tcp_connection(State) of
        {ok, TcpState} ->
            % TCP connection successful, now perform handshake
            case perform_handshake(TcpState) of
                {ok, HandshakeState} ->
                    % Handshake successful, connection is ready
                    % Socket will be set to {active, once} when queries are executed
                    {noreply, HandshakeState};
                {error, Reason} ->
                    % Handshake failed, clean up resources
                    _ = cleanup_resources(TcpState),
                    ErrorState = TcpState#connection_state{
                        socket = undefined,
                        state = error,
                        error_reason = Reason
                    },
                    {noreply, ErrorState}
            end;
        {error, Reason} ->
            % Connection failed, update state to error
            ErrorState = State#connection_state{
                state = error,
                error_reason = Reason
            },
            {noreply, ErrorState}
    end.

%% @doc Handle info messages (TCP messages, timeouts, etc.)
-spec handle_info(Info, State) -> {noreply, NewState} | {stop, Reason, NewState} when
    Info :: term(),
    State :: state(),
    NewState :: state(),
    Reason :: term().
handle_info({query_timeout, QueryId}, State) ->
    %% Handle query timeout
    case State#connection_state.active_query_state of
        undefined ->
            %% No active query, ignore timeout
            {noreply, State};
        ActiveQueryState ->
            case maps:get(query_id, ActiveQueryState) of
                QueryId ->
                    %% Timeout for the active query - check if already replied
                    case maps:get(replied, ActiveQueryState, false) of
                        true ->
                            {noreply, State};
                        false ->
                            ?LOG_WARNING("Query ~s timed out after ~p ms~n", [
                                QueryId, maps:get(timeout, ActiveQueryState)
                            ]),

                            %% Send cancellation packet to server
                            Socket = State#connection_state.socket,
                            _ = send_cancel_packet(Socket, QueryId),

                            %% Reply to caller
                            Caller = maps:get(caller, ActiveQueryState),
                            gen_server:reply(Caller, {error, {timeout_error, query_execution}}),

                            %% Mark as cancelled and replied, but wait for EOF
                            NewActiveQueryState = ActiveQueryState#{
                                cancelled => true,
                                replied => true
                            },
                            {noreply, State#connection_state{
                                active_query_state = NewActiveQueryState
                            }}
                    end;
                _OtherQueryId ->
                    %% Timeout for a different query, ignore
                    {noreply, State}
            end
    end;
handle_info({streaming_timeout, StreamRef}, State) ->
    %% Handle streaming timeout for push-based mode
    case State#connection_state.active_query_state of
        undefined ->
            {noreply, State};
        ActiveQueryState ->
            case maps:get(push_session, ActiveQueryState, undefined) of
                undefined ->
                    {noreply, State};
                SessionState ->
                    case maps:get(stream_ref, SessionState) of
                        StreamRef ->
                            %% Mark session as failed with reason
                            NewSessionState = SessionState#{
                                session_failed => {true, {timeout_error, streaming_insert}}
                            },
                            {noreply, State#connection_state{
                                active_query_state = ActiveQueryState#{
                                    push_session => NewSessionState
                                }
                            }};
                        _ ->
                            {noreply, State}
                    end
            end
    end;
handle_info({tcp, Socket, Data}, State) ->
    ?LOG_INFO("TCP data received: ~p bytes", [byte_size(Data)]),
    ?LOG_INFO("Received data (first 20 bytes): ~s", [format_binary_for_log(Data)]),
    ?LOG_DEBUG("Received data (full): ~p", [Data]),
    ?LOG_DEBUG("Active query state: ~p~n", [
        State#connection_state.active_query_state =/= undefined
    ]),

    %% Get or initialize parser state
    ParserState =
        case State#connection_state.parser_state of
            undefined ->
                Version = State#connection_state.negotiated_version,
                ?LOG_DEBUG("Initializing parser with version ~p~n", [Version]),
                clickhouse_erl_parser:init(
                    Version,
                    State#connection_state.compression_opts
                );
            PS ->
                ?LOG_DEBUG("Using existing parser state~n", []),
                PS
        end,

    %% Parse with event-driven parser (parser manages buffer internally)
    case clickhouse_erl_parser:parse(Data, ParserState) of
        {ok, EventList, NewParserState} ->
            ?LOG_DEBUG("Parser returned ~p events~n", [length(EventList)]),

            %% Get or initialize accumulator state for event processing
            %% Persist across TCP chunks so multi-packet results accumulate correctly.
            %% An initialized AccState always has the 'on_data_callback' key
            %% (set by init_acc_state). A raw user initial_accumulator won't have it, so we can
            %% distinguish "already initialized" from "needs initialization".
            AccState =
                case State#connection_state.active_query_state of
                    #{accumulator := PrevAcc} when
                        is_map(PrevAcc), is_map_key(on_data_callback, PrevAcc)
                    ->
                        PrevAcc;
                    InitAQS when is_map(InitAQS) ->
                        init_acc_state(InitAQS);
                    _ ->
                        init_acc_state(#{})
                end,

            %% Process events in a single pass
            %% 4-tuple: {HasEndOfStream, NeedMore, HasException, AccState}
            case process_events(EventList, AccState) of
                {callback_error, CallbackReason} ->
                    %% Callback failed - reply with error and clean up
                    NewState = State#connection_state{parser_state = NewParserState},
                    complete_query(NewState, {error, {callback_failed, CallbackReason}});
                {HasEndOfStream, _NeedMore, _HasException, NewAccState} ->
                    handle_parsed_events(
                        HasEndOfStream, NewAccState, NewParserState, State, Socket
                    )
            end;
        {error, Reason} ->
            %% Protocol error, fail query
            FormattedReason = format_error_for_log(Reason),
            ?LOG_ERROR("Parser error: ~p~n", [FormattedReason]),

            %% Notify active query if any
            case State#connection_state.active_query_state of
                undefined ->
                    ok;
                ActiveQueryState ->
                    #{caller := Caller, timer_ref := TimerRef} = ActiveQueryState,
                    cancel_timer_and_reply(TimerRef, Caller, ActiveQueryState, Reason)
            end,

            ErrorState = State#connection_state{
                state = error,
                error_reason = Reason,
                active_query_state = undefined,
                parser_state = undefined
            },
            {noreply, ErrorState}
    end;
handle_info({tcp_closed, Socket}, State) when Socket =:= State#connection_state.socket ->
    % Connection closed by server - handle active query if any
    case State#connection_state.active_query_state of
        undefined ->
            % No active query
            ?LOG_INFO("ClickHouse connection closed by server~n");
        ActiveQueryState ->
            % Active query exists - notify caller and clean up timer
            #{caller := Caller, timer_ref := TimerRef} = ActiveQueryState,
            case TimerRef of
                undefined -> ok;
                _ -> erlang:cancel_timer(TimerRef)
            end,
            gen_server:reply(Caller, {error, {network_error, connection_closed_during_query}})
    end,

    ErrorState = State#connection_state{
        socket = undefined,
        state = error,
        error_reason = {network_error, connection_closed_by_server},
        active_query_state = undefined
    },
    {noreply, ErrorState};
handle_info({tcp_error, Socket, Reason}, State) when Socket =:= State#connection_state.socket ->
    % TCP error occurred - handle active query if any
    case State#connection_state.active_query_state of
        undefined ->
            % No active query
            ?LOG_ERROR("TCP error on ClickHouse connection: ~p~n", [Reason]);
        ActiveQueryState ->
            % Active query exists - notify caller and clean up timer
            #{caller := Caller, timer_ref := TimerRef} = ActiveQueryState,
            case TimerRef of
                undefined -> ok;
                _ -> erlang:cancel_timer(TimerRef)
            end,
            gen_server:reply(Caller, {error, {network_error, {tcp_error_during_query, Reason}}})
    end,

    ErrorState = State#connection_state{
        socket = undefined,
        state = error,
        error_reason = {network_error, {tcp_error, Reason}},
        active_query_state = undefined
    },
    {noreply, ErrorState};
handle_info(Info, State) ->
    ?LOG_DEBUG("Connection process received unknown info: ~p. State=~p~n", [
        Info, State#connection_state.state
    ]),
    {noreply, State}.

%% @doc Clean up when the gen_server terminates
-spec terminate(Reason, State) -> ok when
    Reason :: term(),
    State :: state().
terminate(Reason, State) ->
    % Clean up active query timer if it exists
    case State#connection_state.active_query_state of
        undefined ->
            ok;
        ActiveQueryState ->
            case maps:get(timer_ref, ActiveQueryState, undefined) of
                undefined -> ok;
                TimerRef -> erlang:cancel_timer(TimerRef)
            end
    end,

    % Clean up TCP socket if it exists
    case State#connection_state.socket of
        undefined ->
            ok;
        Socket ->
            try
                gen_tcp:close(Socket)
            catch
                _:CloseError ->
                    % Log cleanup error but don't crash
                    ?LOG_WARNING(
                        "Failed to close socket during termination: ~p (reason: ~p)~n",
                        [CloseError, Reason]
                    )
            end
    end,
    ok.

%% @doc Handle code changes
-spec code_change(OldVsn, State, Extra) -> {ok, NewState} when
    OldVsn :: term(),
    State :: state(),
    Extra :: term(),
    NewState :: state().
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Reply with error reason from connection state
-spec reply_with_error_reason(State) -> {reply, {error, Reason}, State} when
    State :: state(),
    Reason :: connection_error().
reply_with_error_reason(State) ->
    ErrorReason = State#connection_state.error_reason,
    {reply, {error, ErrorReason}, State}.

%% @doc Validate connection options
-spec validate_connection_options(Options) -> ok | {error, Reason} when
    Options :: connection_options(),
    Reason :: connection_error().
validate_connection_options(Options) ->
    Username = maps:get(username, Options),
    case Username of
        "" ->
            {error, {protocol_error, "Username cannot be empty"}};
        <<>> ->
            {error, {protocol_error, "Username cannot be empty"}};
        _ when is_list(Username) orelse is_binary(Username) ->
            ok;
        _ ->
            {error, {protocol_error, "Username must be a string"}}
    end.

%% @doc Validate and normalize compression options from connection options.
%% Extracts compression and compression_level from connection options and
%% validates them using the compression module.
%% Returns normalized compression_opts map with method field.
%% Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 9.1, 9.2
-spec validate_and_normalize_compression_opts(Options) ->
    {ok, CompressionOpts} | {error, Reason}
when
    Options :: connection_options(),
    CompressionOpts :: clickhouse_erl_compression:compression_opts(),
    Reason :: connection_error().
validate_and_normalize_compression_opts(Options) ->
    %% Extract compression options from connection options
    %% Default to disabled for backward compatibility
    CompressionMethod = maps:get(compression, Options, disabled),
    CompressionLevel = maps:get(compression_level, Options, undefined),

    %% Build compression opts map for validation
    CompressionOpts =
        case CompressionLevel of
            undefined ->
                #{compression => CompressionMethod};
            Level ->
                #{compression => CompressionMethod, compression_level => Level}
        end,

    %% Validate using compression module
    case clickhouse_erl_compression:validate_opts(CompressionOpts) of
        {ok, ValidatedOpts} ->
            {ok, ValidatedOpts};
        {error, Reason} ->
            {error, {protocol_error, Reason}}
    end.

%% @doc Validate a single callback function
%% Checks that the callback has the correct arity for its type.
%% Requirements: 8.1, 8.2, 8.3, 8.4
-spec validate_callback(CallbackType, Callback) -> ok | {error, Reason} when
    CallbackType :: on_data | on_progress | on_profile | on_profile_events | on_log,
    Callback :: function() | undefined | term(),
    Reason ::
        {invalid_callback_arity, Expected :: non_neg_integer(), Actual :: non_neg_integer()}
        | {invalid_callback_type, term()}.
validate_callback(CallbackType, Callback) when is_function(Callback) ->
    %% Determine expected arity based on callback type
    ExpectedArity =
        case CallbackType of
            % fun(DataBlock, Acc) -> {ok, NewAcc} | {error, Reason}
            on_data -> 2;
            % fun(ProgressInfo) -> ok | {error, Reason}
            on_progress -> 1;
            % fun(ProfileInfo) -> ok | {error, Reason}
            on_profile -> 1;
            % fun(ProfileEvents) -> ok | {error, Reason}
            on_profile_events -> 1;
            % fun(LogEntry) -> ok | {error, Reason}
            on_log -> 1
        end,

    %% Get actual arity of the callback
    {arity, ActualArity} = erlang:fun_info(Callback, arity),

    %% Validate arity matches expected
    case ActualArity of
        ExpectedArity ->
            ok;
        _ ->
            {error, {invalid_callback_arity, ExpectedArity, ActualArity}}
    end;
validate_callback(_CallbackType, undefined) ->
    %% undefined is not allowed - defaults are set before validation in build_active_query_state
    {error, {invalid_callback_type, undefined}};
validate_callback(_CallbackType, NotAFunction) ->
    %% Not a function and not undefined
    {error, {invalid_callback_type, NotAFunction}}.

%% @doc Validate all callbacks in a PreparedRequest
%% Requirements: 8.1, 8.2, 8.3, 8.4
-spec validate_prepared_request(PreparedRequest) -> ok | {error, Reason} when
    PreparedRequest :: map(),
    Reason ::
        {invalid_callback_arity, Expected :: non_neg_integer(), Actual :: non_neg_integer()}
        | {invalid_callback_type, term()}.
validate_prepared_request(PreparedRequest) ->
    %% List of callback types to validate
    CallbackTypes = [on_data, on_progress, on_profile, on_profile_events, on_log],

    %% Validate each callback if present
    validate_callbacks(CallbackTypes, PreparedRequest).

%% @doc Helper function to validate multiple callbacks
-spec validate_callbacks(CallbackTypes, PreparedRequest) -> ok | {error, Reason} when
    CallbackTypes :: [atom()],
    PreparedRequest :: map(),
    Reason ::
        {invalid_callback_arity, Expected :: non_neg_integer(), Actual :: non_neg_integer()}
        | {invalid_callback_type, term()}.
validate_callbacks([], _PreparedRequest) ->
    %% All callbacks validated successfully
    ok;
validate_callbacks([CallbackType | Rest], PreparedRequest) ->
    %% Only validate callbacks that are actually present in the request.
    %% Missing callbacks get defaults in build_active_query_state.
    case maps:find(CallbackType, PreparedRequest) of
        {ok, Callback} ->
            case validate_callback(CallbackType, Callback) of
                ok ->
                    validate_callbacks(Rest, PreparedRequest);
                {error, Reason} ->
                    {error, Reason}
            end;
        error ->
            %% Not provided — will get a default, skip validation
            validate_callbacks(Rest, PreparedRequest)
    end.

-spec execute_query(State, PreparedRequest, From) -> {ok, NewState} | {error, Reason} when
    State :: state(),
    PreparedRequest :: map(),
    From :: {pid(), term()},
    NewState :: state(),
    Reason :: connection_error().
execute_query(State, PreparedRequest, From) ->
    %% Validate callbacks before executing query
    case validate_prepared_request(PreparedRequest) of
        ok ->
            %% Get timeout from prepared request or use default
            Timeout = maps:get(timeout, PreparedRequest, ?DEFAULT_QUERY_TIMEOUT),
            send_query_packet(State, PreparedRequest, From, Timeout);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Execute INSERT query
%% Sends three-packet sequence: Query → Data block → Blank block
-spec execute_insert(State, PreparedRequest, From) -> {ok, NewState} | {error, Reason} when
    State :: state(),
    PreparedRequest :: map(),
    From :: {pid(), term()},
    NewState :: state(),
    Reason :: connection_error().
execute_insert(State, PreparedRequest, From) ->
    %% Validate callbacks before executing INSERT
    maybe
        ok ?= validate_prepared_request(PreparedRequest),
        %% Get timeout from prepared request or use default
        Timeout = maps:get(timeout, PreparedRequest, ?DEFAULT_QUERY_TIMEOUT),
        %% Validate negotiated version is set (should always be set when state is ready)
        true ?= is_integer(State#connection_state.negotiated_version),
        send_insert_packets(State, PreparedRequest, From, Timeout)
    else
        {error, Reason} -> {error, Reason};
        false -> {error, {protocol_error, "Connection not ready: negotiated version not set"}}
    end.

%% @doc Build common ActiveQueryState map for both query and INSERT operations
-spec build_active_query_state(
    From,
    QueryId,
    Timeout,
    TimerRef,
    InitialAccumulator,
    PreparedRequest,
    CompressionOpts
) -> ActiveQueryState when
    From :: {pid(), term()},
    QueryId :: binary(),
    Timeout :: timeout(),
    TimerRef :: reference() | undefined,
    InitialAccumulator :: term(),
    PreparedRequest :: map(),
    CompressionOpts :: clickhouse_erl_compression:compression_opts() | undefined,
    ActiveQueryState :: map().
build_active_query_state(
    From,
    QueryId,
    Timeout,
    TimerRef,
    InitialAccumulator,
    PreparedRequest,
    CompressionOpts
) ->
    OnProgress = maps:get(on_progress, PreparedRequest, fun(_) -> ok end),
    OnProfile = maps:get(on_profile, PreparedRequest, fun(_) -> ok end),
    OnProfileEvents = maps:get(on_profile_events, PreparedRequest, fun(_) -> ok end),
    OnLog = maps:get(on_log, PreparedRequest, fun default_on_log_callback/1),
    %% Always store on_data — use default callback when user doesn't provide one
    OnData =
        case maps:find(on_data, PreparedRequest) of
            {ok, UserOnData} -> UserOnData;
            error -> fun default_on_data_callback/2
        end,
    #{
        caller => From,
        query_id => QueryId,
        timeout => Timeout,
        timer_ref => TimerRef,
        cancelled => false,
        replied => false,
        accumulator => InitialAccumulator,
        on_data => OnData,
        on_progress => OnProgress,
        on_profile => OnProfile,
        on_profile_events => OnProfileEvents,
        on_log => OnLog,
        compression_opts => CompressionOpts
    }.

%% @doc Create ActiveQueryState with proper InitialAccumulator handling
%% This helper encapsulates the common pattern of determining InitialAccumulator
%% and building ActiveQueryState, used by both query and insert operations.
-spec create_active_query_state(
    From,
    QueryId,
    Timeout,
    TimerRef,
    PreparedRequest,
    CompressionOpts
) -> ActiveQueryState when
    From :: {pid(), term()},
    QueryId :: binary(),
    Timeout :: timeout(),
    TimerRef :: reference() | undefined,
    PreparedRequest :: map(),
    CompressionOpts :: clickhouse_erl_compression:compression_opts() | undefined,
    ActiveQueryState :: map().
create_active_query_state(
    From, QueryId, Timeout, TimerRef, PreparedRequest, CompressionOpts
) ->
    %% Determine InitialAccumulator based on query mode
    InitialAccumulator =
        case maps:is_key(on_data, PreparedRequest) of
            false ->
                %% Batch mode — default callback manages its own accumulator
                #{column_order => [], column_meta => #{}, column_values => #{}};
            true ->
                %% Streaming mode - use provided initial_accumulator or undefined
                maps:get(initial_accumulator, PreparedRequest, undefined)
        end,
    %% Build and return ActiveQueryState
    build_active_query_state(
        From,
        QueryId,
        Timeout,
        TimerRef,
        InitialAccumulator,
        PreparedRequest,
        CompressionOpts
    ).

send_ping(Socket) ->
    PingPacket = <<16#04>>,

    case gen_tcp:send(Socket, PingPacket) of
        ok -> ok;
        {error, Error} -> {error, {network_error, Error}}
    end.

%% @doc Receive SERVER_PONG using event-driven parser (POC)
%% This is a proof-of-concept integration of clickhouse_erl_parser for PONG packets.
%% Pattern can be expanded to other packet types once validated.
-spec receive_server_pong_with_parser(Socket, Version) -> ok | {error, Reason} when
    Socket :: gen_tcp:socket(),
    Version :: non_neg_integer(),
    Reason :: connection_error().
receive_server_pong_with_parser(Socket, Version) ->
    %% Initialize event-driven parser
    ParserState = clickhouse_erl_parser:init(Version),

    %% Set socket to active mode
    case inet:setopts(Socket, [{active, once}]) of
        ok ->
            receive_pong_data(Socket, ParserState);
        {error, SocketError} ->
            {error, {network_error, {socket_option_error, SocketError}}}
    end.

%% @doc Wait for and parse PONG response data from socket.
-spec receive_pong_data(gen_tcp:socket(), map()) -> ok | {error, connection_error()}.
receive_pong_data(Socket, ParserState) ->
    receive
        {tcp, Socket, Data} ->
            handle_pong_tcp_data(Socket, Data, ParserState);
        {tcp_closed, Socket} ->
            {error, {network_error, connection_closed_during_ping}};
        {tcp_error, Socket, Reason} ->
            {error, {network_error, {tcp_error_during_ping, Reason}}}
    after ?HANDSHAKE_TIMEOUT ->
        inet:setopts(Socket, [{active, false}]),
        {error, {timeout_error, pong_receive}}
    end.

%% @doc Parse TCP data for PONG response and verify events.
-spec handle_pong_tcp_data(gen_tcp:socket(), binary(), map()) ->
    ok | {error, connection_error()}.
handle_pong_tcp_data(Socket, Data, ParserState) ->
    case clickhouse_erl_parser:parse(Data, ParserState) of
        {ok, Events, _NewParserState} when is_list(Events) ->
            inet:setopts(Socket, [{active, false}]),
            verify_pong_events(Events);
        {error, Reason} ->
            inet:setopts(Socket, [{active, false}]),
            {error, {protocol_error, Reason}}
    end.

%% @doc Verify PONG events from event-driven parser
-spec verify_pong_events(Events) -> ok | {error, Reason} when
    Events :: list(),
    Reason :: term().
verify_pong_events(Events) ->
    %% Expected: [{start, server_pong}, {'end', server_pong}]
    %% or [{start, server_pong}, {'end', server_pong}, need_more] if buffer has leftover
    case Events of
        [{start, server_pong}, {'end', server_pong}] ->
            ok;
        [{start, server_pong}, {'end', server_pong}, need_more] ->
            %% PONG complete, need_more indicates parser ready for next packet
            ok;
        _Other ->
            {error, {unexpected_pong_events, Events}}
    end.

%% @doc Send the actual query packet after settings are configured
-spec send_query_packet(State, PreparedRequest, From, Timeout) ->
    {ok, NewState} | {error, Reason}
when
    State :: state(),
    PreparedRequest :: map(),
    From :: {pid(), term()},
    Timeout :: timeout(),
    NewState :: state(),
    Reason :: connection_error().
send_query_packet(State, PreparedRequest, From, Timeout) ->
    Socket = State#connection_state.socket,
    NegotiatedVersion = State#connection_state.negotiated_version,

    %% Extract parameters early for error logging
    Parameters = maps:get(parameters, PreparedRequest, []),
    QueryBody = maps:get(sql, PreparedRequest, <<"unknown">>),

    %% Get negotiated protocol version - must be set after handshake
    maybe
        %% Check version is set
        true ?= is_integer(NegotiatedVersion),
        %% Validate parameters
        ok ?= validate_parameters(Parameters),
        ok ?= should_send_parameters(Parameters, NegotiatedVersion),
        %% Generate or use provided query ID
        QueryId = get_or_generate_query_id(PreparedRequest),
        ?LOG_DEBUG("Starting query with ID: ~p (provided: ~p)", [
            QueryId, maps:get(query_id, PreparedRequest, <<>>)
        ]),
        %% Determine compression mode from connection state
        CompressionMode = get_compression_mode(State#connection_state.compression_opts),
        %% Construct QueryInfo map for packet encoding
        QueryInfo = #{
            query_id => QueryId,
            client_info => create_client_info(NegotiatedVersion, QueryId),
            settings => maps:get(settings, PreparedRequest, []),
            query_body => QueryBody,
            parameters => Parameters,
            compression => CompressionMode
        },
        %% Debug logging
        ?LOG_DEBUG("Query body: ~p~n", [maps:get(query_body, QueryInfo)]),
        ?LOG_DEBUG("Parameters: ~p~n", [Parameters]),
        ?LOG_DEBUG("Using negotiated version: ~p~n", [NegotiatedVersion]),
        %% Encode and send query packet
        {ok, PacketData} ?=
            clickhouse_erl_protocol_query_packet:encode(QueryInfo, NegotiatedVersion),
        ?LOG_DEBUG("Encoded query packet, size: ~p bytes~n", [byte_size(PacketData)]),
        ?LOG_INFO("Query packet (first 50 bytes): ~s~n", [
            format_binary_for_log(binary:part(PacketData, 0, min(50, byte_size(PacketData))))
        ]),
        ?LOG_DEBUG("Full packet: ~p~n", [PacketData]),
        %% CRITICAL: Set socket to active mode BEFORE sending query
        %% This prevents race condition where response arrives before we're listening
        ok = inet:setopts(Socket, [{active, once}]),
        %% Query packets are sent directly without size prefix
        ok ?= gen_tcp:send(Socket, PacketData),
        ?LOG_DEBUG("Query packet sent successfully~n", []),
        %% Send blank data block (end of external data)
        %% CRITICAL: Blank block must be compressed if compression is enabled
        BlankBlock = encode_blank_data_block(State#connection_state.compression_opts),
        ?LOG_DEBUG("Blank block size: ~p bytes, compression opts: ~p~n", [
            byte_size(BlankBlock), State#connection_state.compression_opts
        ]),
        ?LOG_DEBUG("First 50 bytes of blank block: ~p~n", [
            binary:part(BlankBlock, 0, min(50, byte_size(BlankBlock)))
        ]),
        ok ?= gen_tcp:send(Socket, BlankBlock),
        ?LOG_DEBUG("Blank data block sent successfully~n", []),
        %% Initialize response handler state
        %% Start timeout timer if timeout is not infinity
        TimerRef = create_timeout_timer(Timeout, QueryId),
        %% Build ActiveQueryState using helper function
        ActiveQueryState = create_active_query_state(
            From,
            QueryId,
            Timeout,
            TimerRef,
            PreparedRequest,
            State#connection_state.compression_opts
        ),
        ?LOG_DEBUG("Set active_query_state with QueryId: ~p", [QueryId]),
        NewState = State#connection_state{active_query_state = ActiveQueryState},
        {ok, NewState}
    else
        false ->
            {error, {protocol_error, "Connection not ready: negotiated version not set"}};
        {error, {invalid_parameter_key, _} = Reason} ->
            %% Parameter validation failed - already logged in validate_parameters_loop
            ?LOG_ERROR("Query failed: parameter validation error", #{
                error => Reason,
                query => QueryBody,
                parameters => Parameters
            }),
            {error, Reason};
        {error, {invalid_parameter_value, _} = Reason} ->
            %% Parameter validation failed - already logged in validate_parameters_loop
            ?LOG_ERROR("Query failed: parameter validation error", #{
                error => Reason,
                query => QueryBody,
                parameters => Parameters
            }),
            {error, Reason};
        {error, {invalid_parameter_format, _} = Reason} ->
            %% Parameter validation failed - already logged in validate_parameters_loop
            ?LOG_ERROR("Query failed: parameter validation error", #{
                error => Reason,
                query => QueryBody,
                parameters => Parameters
            }),
            {error, Reason};
        {error, {parameters_unsupported, _} = Reason} ->
            %% Version check failed - already logged in should_send_parameters
            ?LOG_ERROR("Query failed: parameters not supported by server", #{
                error => Reason,
                query => QueryBody,
                parameters => Parameters
            }),
            {error, Reason};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Get or generate query ID from PreparedRequest
-spec get_or_generate_query_id(map()) -> binary().
get_or_generate_query_id(PreparedRequest) ->
    case maps:get(query_id, PreparedRequest, <<>>) of
        <<>> -> clickhouse_erl_utils:generate_query_id();
        "" -> clickhouse_erl_utils:generate_query_id();
        ProvidedId when is_binary(ProvidedId) -> ProvidedId;
        ProvidedId when is_list(ProvidedId) -> list_to_binary(ProvidedId)
    end.

-spec create_client_info(NegotiatedVersion, QueryId) -> map() when
    NegotiatedVersion :: non_neg_integer(),
    QueryId :: binary().
create_client_info(NegotiatedVersion, QueryId) when is_integer(NegotiatedVersion) ->
    % Get actual client version from application
    {VersionMajor, VersionMinor, VersionPatch} =
        case application:get_key(clickhouse_erl, vsn) of
            {ok, VsnString} when is_list(VsnString) ->
                parse_version_string(VsnString);
            _ ->
                % Fallback to default if app not loaded
                ?DEFAULT_CLIENT_VERSION
        end,

    #{
        % Use 1 like ch-go (ClientQueryInitial)
        query_kind => 1,
        initial_user => <<>>,
        % Set to same value as main query ID like ch-go
        initial_query_id => QueryId,
        initial_address => list_to_binary(
            clickhouse_erl_protocol_client_info:get_initial_address()
        ),
        initial_time => 0,
        % Get actual OS user
        os_user => list_to_binary(clickhouse_erl_protocol_client_info:get_os_user()),
        % Get actual hostname
        client_hostname => list_to_binary(clickhouse_erl_protocol_client_info:get_hostname()),
        % Match the working client name
        client_name => <<"clickhouse_erl">>,
        % Use actual client version
        version_major => VersionMajor,
        version_minor => VersionMinor,
        % Use negotiated version consistently
        protocol_version => NegotiatedVersion,
        quota_key => <<>>,
        distributed_depth => 0,
        version_patch => VersionPatch,
        % Parallel replicas fields - use ch-go defaults (all zeros)
        collaborate_with_initiator => 0,
        count_participating_replicas => 0,
        number_of_current_replica => 0
    }.

%% @doc Parse version string like "0.1.0" into {Major, Minor, Patch}
-spec parse_version_string(string()) ->
    {
        non_neg_integer(), non_neg_integer(), non_neg_integer()
    }.
parse_version_string(VsnString) ->
    Parts = string:tokens(VsnString, "."),
    case Parts of
        [MajorStr, MinorStr, PatchStr] ->
            {list_to_integer(MajorStr), list_to_integer(MinorStr), list_to_integer(PatchStr)};
        _ ->
            ?DEFAULT_CLIENT_VERSION
    end.

%% @doc Handle cancel query request with optional query ID validation
%% Used by both cancel_query/1 and cancel_query/2 to avoid code duplication
-spec do_cancel_query(State, QueryIdToValidate) -> {reply, Result, NewState} when
    State :: state(),
    QueryIdToValidate :: undefined | binary(),
    Result :: ok | {error, Reason},
    NewState :: state(),
    Reason :: no_active_query | connection_error().
do_cancel_query(State, QueryIdToValidate) ->
    case State#connection_state.active_query_state of
        undefined ->
            ?LOG_DEBUG("No active query to cancel", []),
            ErrorReason =
                case QueryIdToValidate of
                    undefined -> no_active_query;
                    _ -> {protocol_error, "No active query to cancel"}
                end,
            {reply, {error, ErrorReason}, State};
        ActiveQueryState ->
            ActiveQueryId = maps:get(query_id, ActiveQueryState),

            %% Determine which query ID to use for cancellation
            QueryIdToCancel =
                case QueryIdToValidate of
                    undefined ->
                        %% cancel_query/1 - use active query ID
                        ?LOG_DEBUG("Cancelling active query with ID: ~p", [ActiveQueryId]),
                        ActiveQueryId;
                    RequestedId ->
                        %% cancel_query/2 - validate requested ID matches active
                        ?LOG_DEBUG("Active query ID: ~p, Requested cancel ID: ~p", [
                            ActiveQueryId, RequestedId
                        ]),
                        RequestedId
                end,

            %% Validate query ID matches (only relevant for cancel_query/2)
            case QueryIdToCancel of
                ActiveQueryId ->
                    ?LOG_DEBUG("Query IDs match, proceeding with cancellation", []),
                    case cancel_active_query(State, ActiveQueryState) of
                        {ok, NewState} ->
                            {reply, ok, NewState};
                        {error, Reason} ->
                            {reply, {error, Reason}, State}
                    end;
                _Mismatch ->
                    ?LOG_WARNING("Query ID mismatch! Active: ~p, Requested: ~p", [
                        ActiveQueryId, QueryIdToCancel
                    ]),
                    {reply, {error, {protocol_error, "Query ID does not match active query"}},
                        State}
            end
    end.

%% @doc Cancel an active query
-spec cancel_active_query(State, ActiveQueryState) -> {ok, NewState} | {error, Reason} when
    State :: state(),
    ActiveQueryState :: active_query_state(),
    NewState :: state(),
    Reason :: connection_error().
cancel_active_query(State, ActiveQueryState) ->
    Socket = State#connection_state.socket,
    QueryId = maps:get(query_id, ActiveQueryState),
    Caller = maps:get(caller, ActiveQueryState),
    TimerRef = maps:get(timer_ref, ActiveQueryState, undefined),

    %% Cancel the timeout timer if it exists
    case TimerRef of
        undefined -> ok;
        _ -> erlang:cancel_timer(TimerRef)
    end,

    %% Send cancellation packet to server
    case send_cancel_packet(Socket, QueryId) of
        ok ->
            %% Check if already replied
            case maps:get(replied, ActiveQueryState) of
                false ->
                    %% Mark query as cancelled and reply to caller
                    gen_server:reply(Caller, {error, {query_cancelled, QueryId}}),

                    %% Update active query state but do not clear it yet
                    %% We need to wait for SERVER_END_OF_STREAM
                    %% Also handle push session if present
                    NewActiveQueryState0 = ActiveQueryState#{
                        cancelled => true,
                        replied => true,
                        timer_ref => undefined
                    },

                    %% If this is a push session, mark it as failed with cancellation reason
                    NewActiveQueryState =
                        case maps:get(push_session, ActiveQueryState, undefined) of
                            undefined ->
                                NewActiveQueryState0;
                            PushSession ->
                                NewPushSession = PushSession#{
                                    session_failed => {true, {query_cancelled, QueryId}}
                                },
                                NewActiveQueryState0#{push_session => NewPushSession}
                        end,

                    {ok, State#connection_state{active_query_state = NewActiveQueryState}};
                true ->
                    %% Already replied (e.g. timeout happened simultaneously)
                    {ok, State}
            end;
        {error, Reason} ->
            {error, {network_error, Reason}}
    end.

%% @doc Send cancel packet to server
-spec send_cancel_packet(Socket, QueryId) -> ok | {error, Reason} when
    Socket :: gen_tcp:socket(),
    QueryId :: binary(),
    Reason :: term().
send_cancel_packet(Socket, _QueryId) ->
    %% Construct cancel packet (Type 3)
    PacketType = clickhouse_erl_types_primitive:encode_varint(?CLIENT_CANCEL),
    case gen_tcp:send(Socket, PacketType) of
        ok ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Encode blank data block (end of external data marker)
%% This is required after every query packet to signal end of external data.
%%
%% CRITICAL PROTOCOL DETAIL: When compression is enabled, only the BLOCK DATA is compressed,
%% NOT the temp table name. The packet structure is:
%% - CLIENT_DATA byte (uncompressed)
%% - Temp table name (uncompressed)
%% - Block data: BlockInfo + columns + rows (compressed if compression enabled)
%%
%% This matches C++ and ch-go implementations where packet type and table name are written
%% to the uncompressed stream, and only the block data goes through CompressedWriteBuffer.
%%
%% @param CompressionOpts Compression options from connection state (undefined or map)
%% @returns Binary CLIENT_DATA packet with properly compressed blank block
-spec encode_blank_data_block(clickhouse_erl_compression:compression_opts() | undefined) ->
    binary().
encode_blank_data_block(CompressionOpts) ->
    %% CLIENT_DATA packet type (2)
    PacketType = <<?CLIENT_DATA:8>>,

    %% Temp table name (empty string) - UNCOMPRESSED
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Block data: BlockInfo + columns + rows - COMPRESSIBLE
    BlockData = [
        clickhouse_erl_protocol_data_block:encode_blank_data_block_info(),
        % 0 columns
        clickhouse_erl_types_primitive:encode_varint(0),
        % 0 rows
        clickhouse_erl_types_primitive:encode_varint(0)
    ],
    BlockDataBinary = iolist_to_binary(BlockData),

    %% Apply compression only to block data if enabled
    CompressedBlockData =
        case clickhouse_erl_compression:compress_data_block(BlockDataBinary, CompressionOpts) of
            {ok, Compressed} ->
                Compressed;
            {error, Reason} ->
                ?LOG_ERROR("Failed to compress blank block data", #{reason => Reason}),
                %% Fall back to uncompressed on error
                BlockDataBinary
        end,

    %% Assemble packet: PacketType + TempTableName (uncompressed) + BlockData (compressed)
    iolist_to_binary([PacketType, TempTableName, CompressedBlockData]).

%% @doc Encode column data as a CLIENT_DATA block and send it over the TCP socket.
%%
%% This is the shared helper used by both single-block insert and streaming insert.
%% It builds a data_block map, encodes it via the protocol module, splits the encoded
%% binary into temp table name (uncompressed) and block data, compresses the block data
%% if compression is enabled, assembles the CLIENT_DATA packet, and sends it.
%%
%% @param State The connection state (provides socket, negotiated version, compression opts)
%% @param ColumnData List of column data maps
%%   #{name => binary(), type => binary(), data => [term()]}
%% @returns ok | {error, Reason}
-spec encode_and_send_block(state(), [map()]) -> ok | {error, term()}.
encode_and_send_block(State, ColumnData) ->
    Socket = State#connection_state.socket,
    NegotiatedVersion = State#connection_state.negotiated_version,
    CompressionOpts = State#connection_state.compression_opts,
    NumColumns = length(ColumnData),
    NumRows =
        case ColumnData of
            [] -> 0;
            [#{data := Data} | _] -> length(Data)
        end,
    DataBlock = #{columns => NumColumns, rows => NumRows, column_data => ColumnData},
    maybe
        {ok, EncodedDataBlock} ?=
            clickhouse_erl_protocol_data_block:encode_data_block(
                DataBlock, NegotiatedVersion
            ),
        %% encode_data_block returns [TempTableName, BlockInfo, NumColumns, NumRows, ColumnData].
        %% Extract block data (everything after temp table name) for compression.
        FullDataBlockBin = iolist_to_binary(EncodedDataBlock),
        {ok, _DecodedTempTableName, BlockDataOnly} =
            clickhouse_erl_types_primitive:decode_string(FullDataBlockBin),
        %% Compress block data if enabled
        CompressedBlockData =
            case clickhouse_erl_compression:compress_data_block(BlockDataOnly, CompressionOpts) of
                {ok, Compressed} ->
                    Compressed;
                {error, CompressReason} ->
                    ?LOG_ERROR("Failed to compress data block", #{reason => CompressReason}),
                    BlockDataOnly
            end,
        %% Assemble and send CLIENT_DATA packet
        TempTableNameEnc = clickhouse_erl_types_primitive:encode_string(""),
        DataPacket = <<?CLIENT_DATA:8, TempTableNameEnc/binary, CompressedBlockData/binary>>,
        ok ?= gen_tcp:send(Socket, DataPacket),
        ?LOG_DEBUG("Data block sent", #{columns => NumColumns, rows => NumRows}),
        ok
    else
        {error, Reason} when is_tuple(Reason) ->
            {error, {protocol_error, {data_block_encoding, Reason}}};
        {error, Reason} ->
            {error, {network_error, Reason}}
    end.

%% @doc Validate a streaming block against original column definitions.
%% Checks row count consistency within the data and column name matching
%% against original definitions.
%%
%% @param ColumnData The column data from the callback or send_data
%% @param OriginalDefs The original column definitions from the streaming insert request
%% @returns ok | {error, {validation_error, {row_count_mismatch, Details}}}
%%          | {error, {validation_error, {column_name_mismatch, Expected, Got}}}
-spec validate_streaming_block([map()], [map()]) -> ok | {error, {validation_error, term()}}.
validate_streaming_block(ColumnData, OriginalDefs) when
    is_list(ColumnData), is_list(OriginalDefs)
->
    clickhouse_erl_streaming_helpers:validate_streaming_block(ColumnData, OriginalDefs).

%% @doc Validate that column names in the data match the original definitions.
%%
%% @param ColumnData The column data to validate
%% @param OriginalDefs The original column definitions
%% @returns ok | {error, {validation_error, {column_name_mismatch, Expected, Got}}}
-spec merge_column_types([map()], [map()]) -> [map()].
merge_column_types(ColumnData, ColumnDefs) ->
    clickhouse_erl_streaming_helpers:merge_column_types(ColumnData, ColumnDefs).

-spec has_rows([map()]) -> boolean().
has_rows(ColumnData) ->
    clickhouse_erl_streaming_helpers:has_rows(ColumnData).

%% @doc Establish TCP connection to ClickHouse server
-spec establish_tcp_connection(State) -> {ok, NewState} | {error, Reason} when
    State :: state(),
    NewState :: state(),
    Reason :: connection_error().
establish_tcp_connection(State) ->
    Host = State#connection_state.host,
    Port = State#connection_state.port,
    Timeout = maps:get(timeout, State#connection_state.options, ?CONNECT_TIMEOUT),

    % TCP connection options
    TcpOptions = [
        binary,
        {active, false},
        {packet, 0},
        {nodelay, true},
        {keepalive, true}
    ],

    case gen_tcp:connect(Host, Port, TcpOptions, Timeout) of
        {ok, Socket} ->
            NewState = State#connection_state{
                socket = Socket,
                % Still connecting until handshake completes
                state = connecting
            },
            {ok, NewState};
        {error, timeout} ->
            {error, {timeout_error, tcp_connect}};
        {error, econnrefused} ->
            {error, {network_error, connection_refused}};
        {error, ehostunreach} ->
            {error, {network_error, host_unreachable}};
        {error, enetunreach} ->
            {error, {network_error, network_unreachable}};
        {error, nxdomain} ->
            {error, {network_error, invalid_host}};
        {error, enotfound} ->
            {error, {network_error, host_not_found}};
        {error, econnreset} ->
            {error, {network_error, connection_reset}};
        {error, enetdown} ->
            {error, {network_error, network_down}};
        {error, eaddrnotavail} ->
            {error, {network_error, address_not_available}};
        {error, Reason} ->
            {error, {network_error, Reason}}
    end.

%% @doc Create connection info map from current state
-spec create_connection_info(State) -> Info when
    State :: state(),
    Info :: #{
        state := connecting | ready | error,
        server_name => binary(),
        server_version => {non_neg_integer(), non_neg_integer(), non_neg_integer()},
        server_revision => non_neg_integer(),
        server_timezone => binary(),
        server_display_name => binary(),
        active_query_state => active_query_state() | undefined
    }.
create_connection_info(State) ->
    BaseInfo = #{
        state => State#connection_state.state
    },

    Info1 =
        case State#connection_state.server_info of
            undefined -> BaseInfo;
            ServerInfo -> maps:merge(BaseInfo, ServerInfo)
        end,

    %% Add active query state for observability and testing
    Info1#{active_query_state => State#connection_state.active_query_state}.

%% @doc Perform ClickHouse handshake protocol
-spec perform_handshake(State) -> {ok, NewState} | {error, Reason} when
    State :: state(),
    NewState :: state(),
    Reason :: connection_error().
perform_handshake(State) ->
    Socket = State#connection_state.socket,
    Options = State#connection_state.options,

    % Prepare Client_Hello message data
    {VersionMajor, VersionMinor, _VersionPatch} = maps:get(
        client_version, Options, ?DEFAULT_CLIENT_VERSION
    ),
    ClientHelloInfo = #{
        client_name => maps:get(client_name, Options, ?DEFAULT_CLIENT_NAME),
        version_major => VersionMajor,
        version_minor => VersionMinor,
        protocol_version => ?PROTOCOL_VERSION,
        database => maps:get(database, Options, ?DEFAULT_DATABASE),
        username => maps:get(username, Options, ?DEFAULT_USERNAME),
        password => maps:get(password, Options, ?DEFAULT_PASSWORD)
    },

    % Send Client_Hello message
    maybe
        ok ?= send_client_hello(Socket, ClientHelloInfo),
        % Receive and parse Server_Hello response
        {ok, ServerInfo} ?= receive_server_hello(Socket),
        % Negotiate protocol version (use minimum of client and server)
        ServerRevision = maps:get(server_revision, ServerInfo),
        NegotiatedVersion = min(?PROTOCOL_VERSION, ServerRevision),
        % Check protocol version compatibility
        ok ?= check_protocol_compatibility(ServerInfo),
        % Send addendum (quota key) if supported by protocol version
        ok ?= send_addendum(Socket, NegotiatedVersion),
        ok ?= send_ping(Socket),
        ok ?= receive_server_pong_with_parser(Socket, NegotiatedVersion),
        % Update connection state to ready with negotiated version
        NewState = State#connection_state{
            state = ready,
            server_info = ServerInfo,
            negotiated_version = NegotiatedVersion
        },
        {ok, NewState}
    else
        {error, Reason} -> {error, Reason}
    end.

%% @doc Send addendum (quota key) if supported by protocol version
-spec send_addendum(Socket, Version) -> ok | {error, Reason} when
    Socket :: gen_tcp:socket(),
    Version :: non_neg_integer(),
    Reason :: connection_error().
send_addendum(Socket, Version) ->
    case clickhouse_erl_protocol_features:has_feature(quota_key, Version) of
        true ->
            %% Send empty quota key (like ch-go default)
            QuotaKey = clickhouse_erl_types_primitive:encode_string(""),
            case gen_tcp:send(Socket, QuotaKey) of
                ok -> ok;
                {error, Reason} -> {error, {network_error, Reason}}
            end;
        false ->
            %% No addendum needed for older protocol versions
            ok
    end.

%% @doc Send Client_Hello message to the server
-spec send_client_hello(Socket, ClientHelloInfo) -> ok | {error, Reason} when
    Socket :: gen_tcp:socket(),
    ClientHelloInfo :: client_hello_info(),
    Reason :: connection_error().
send_client_hello(Socket, ClientHelloInfo) ->
    ?LOG_DEBUG("Sending Client_Hello message~n"),
    ?LOG_DEBUG("Client info: ~p~n", [ClientHelloInfo]),

    case clickhouse_erl_protocol:encode_client_hello(ClientHelloInfo) of
        {ok, MessageData} ->
            % Send packet type (0 for Client_Hello) followed by message data
            % Note: During handshake, packets don't use the size prefix format

            % CLIENT_HELLO packet type
            PacketType = 0,
            FullMessage = <<PacketType:8, MessageData/binary>>,

            ?LOG_DEBUG("Packet type: ~p~n", [PacketType]),
            ?LOG_DEBUG("Message data length: ~p~n", [byte_size(MessageData)]),
            ?LOG_DEBUG("Full message length: ~p~n", [byte_size(FullMessage)]),
            ?LOG_DEBUG("First 20 bytes of full message: ~p~n", [
                binary:part(FullMessage, 0, min(20, byte_size(FullMessage)))
            ]),

            case gen_tcp:send(Socket, FullMessage) of
                ok ->
                    ?LOG_DEBUG("Client_Hello sent successfully~n"),
                    ok;
                {error, timeout} ->
                    {error, {timeout_error, client_hello_send}};
                {error, closed} ->
                    {error, {network_error, connection_closed_during_send}};
                {error, NetworkReason} ->
                    {error, {network_error, NetworkReason}}
            end;
        {error, {encoding_error, _} = EncodingError} ->
            {error, EncodingError}
    end.

%% @doc Receive and parse Server_Hello response using event-driven parser
-spec receive_server_hello(Socket) -> {ok, ServerInfo} | {error, Reason} when
    Socket :: gen_tcp:socket(),
    ServerInfo :: connection_info(),
    Reason :: connection_error().
receive_server_hello(Socket) ->
    % Initialize parser state
    ParserState = clickhouse_erl_parser:init(?PROTOCOL_VERSION),
    % Set socket to active mode to receive data
    case inet:setopts(Socket, [{active, once}]) of
        ok ->
            receive_server_hello_loop(Socket, ParserState, #{});
        {error, SocketError} ->
            {error, {network_error, {socket_option_error, SocketError}}}
    end.

%% @doc Loop to receive and parse Server_Hello using event-driven parser
-spec receive_server_hello_loop(Socket, ParserState, ServerInfo) ->
    {ok, ServerInfo} | {error, Reason}
when
    Socket :: gen_tcp:socket(),
    ParserState :: map(),
    ServerInfo :: connection_info(),
    Reason :: connection_error().
receive_server_hello_loop(Socket, ParserState, ServerInfo) ->
    receive
        {tcp, Socket, Data} ->
            % Parse the received data
            case clickhouse_erl_parser:parse(Data, ParserState) of
                {ok, Events, NewParserState} ->
                    % Process events to extract server info
                    case process_server_hello_events(Events, ServerInfo) of
                        {complete, FinalServerInfo} ->
                            % Server_Hello complete
                            inet:setopts(Socket, [{active, false}]),
                            ?LOG_DEBUG("Handshake successful. ServerInfo: ~p~n", [FinalServerInfo]),
                            {ok, FinalServerInfo};
                        {continue, UpdatedServerInfo} ->
                            % Need more data
                            inet:setopts(Socket, [{active, once}]),
                            receive_server_hello_loop(Socket, NewParserState, UpdatedServerInfo);
                        {error, Reason} ->
                            inet:setopts(Socket, [{active, false}]),
                            {error, Reason}
                    end;
                {error, Reason} ->
                    inet:setopts(Socket, [{active, false}]),
                    {error, {protocol_error, Reason}}
            end;
        {tcp_closed, Socket} ->
            {error, {network_error, connection_closed_during_handshake}};
        {tcp_error, Socket, Reason} ->
            {error, {network_error, {tcp_error_during_handshake, Reason}}}
    after ?HANDSHAKE_TIMEOUT ->
        inet:setopts(Socket, [{active, false}]),
        {error, {timeout_error, handshake_receive}}
    end.

%% @doc Process server_hello events and extract server info
-spec process_server_hello_events(Events, ServerInfo) ->
    {complete, ServerInfo} | {continue, ServerInfo} | {error, Reason}
when
    Events :: list(),
    ServerInfo :: connection_info(),
    Reason :: connection_error().
process_server_hello_events(Events, ServerInfo) ->
    process_server_hello_events(Events, ServerInfo, false).

process_server_hello_events([], ServerInfo, true) ->
    % Completed server_hello
    {complete, ServerInfo};
process_server_hello_events([], ServerInfo, false) ->
    % Need more data
    {continue, ServerInfo};
process_server_hello_events([Event | Rest], ServerInfo, Completed) ->
    case Event of
        {start, server_hello} ->
            process_server_hello_events(Rest, ServerInfo, Completed);
        {data, name, Name} ->
            process_server_hello_events(Rest, ServerInfo#{server_name => Name}, Completed);
        {data, version_major, Major} ->
            process_server_hello_events(Rest, ServerInfo#{version_major => Major}, Completed);
        {data, version_minor, Minor} ->
            process_server_hello_events(Rest, ServerInfo#{version_minor => Minor}, Completed);
        {data, version_patch, Patch} ->
            process_server_hello_events(Rest, ServerInfo#{version_patch => Patch}, Completed);
        {data, revision, Revision} ->
            process_server_hello_events(Rest, ServerInfo#{server_revision => Revision}, Completed);
        {data, timezone, Timezone} ->
            process_server_hello_events(Rest, ServerInfo#{server_timezone => Timezone}, Completed);
        {data, display_name, DisplayName} ->
            process_server_hello_events(
                Rest, ServerInfo#{server_display_name => DisplayName}, Completed
            );
        {'end', server_hello} ->
            % Build final server info
            FinalServerInfo = #{
                server_name => maps:get(server_name, ServerInfo, <<>>),
                server_version => {
                    maps:get(version_major, ServerInfo, 0),
                    maps:get(version_minor, ServerInfo, 0),
                    maps:get(version_patch, ServerInfo, 0)
                },
                server_revision => maps:get(server_revision, ServerInfo, 0),
                server_timezone => maps:get(server_timezone, ServerInfo, <<"UTC">>),
                server_display_name => maps:get(server_display_name, ServerInfo, <<>>)
            },
            process_server_hello_events(Rest, FinalServerInfo, true);
        {start, server_exception} ->
            % Exception during handshake - collect exception info
            collect_exception_info(Rest);
        need_more ->
            process_server_hello_events(Rest, ServerInfo, Completed);
        _ ->
            % Unexpected event
            {error, {protocol_error, {unexpected_event, Event}}}
    end.

%% @doc Collect exception info from events
-spec collect_exception_info(Events) -> {error, Reason} when
    Events :: list(),
    Reason :: connection_error().
collect_exception_info(Events) ->
    collect_exception_info(Events, #{}).

collect_exception_info([], ExceptionInfo) ->
    {error, {server_exception, ExceptionInfo}};
collect_exception_info([Event | Rest], ExceptionInfo) ->
    case Event of
        {data, error_code, Code} ->
            collect_exception_info(Rest, ExceptionInfo#{code => Code});
        {data, exception_name, Name} ->
            collect_exception_info(Rest, ExceptionInfo#{name => Name});
        {data, message, Message} ->
            collect_exception_info(Rest, ExceptionInfo#{message => Message});
        {data, stack_trace, StackTrace} ->
            collect_exception_info(Rest, ExceptionInfo#{stack_trace => StackTrace});
        {data, nested, Nested} ->
            collect_exception_info(Rest, ExceptionInfo#{nested => Nested});
        {'end', server_exception} ->
            {error, {server_exception, ExceptionInfo}};
        _ ->
            collect_exception_info(Rest, ExceptionInfo)
    end.

%% @doc Check protocol version compatibility with server
-spec check_protocol_compatibility(ServerInfo) -> ok | {error, Reason} when
    ServerInfo :: connection_info(),
    Reason :: connection_error().
check_protocol_compatibility(ServerInfo) ->
    case maps:get(server_version, ServerInfo, undefined) of
        undefined ->
            {error, {protocol_error, "Server version not available"}};
        {ServerMajor, ServerMinor, ServerPatch} ->
            % For now, we'll use a simple compatibility check based on major version
            % In a real implementation, this would be more sophisticated
            case ServerMajor of
                Major when Major >= 20 ->
                    ok;
                _UnsupportedMajor ->
                    ServerVersion = {ServerMajor, ServerMinor, ServerPatch},
                    {error, {compatibility_error, {server_version, ServerVersion}}}
            end;
        InvalidVersion ->
            {error, {compatibility_error, {server_version, InvalidVersion}}}
    end.

%% @doc Enhanced resource cleanup with error handling
-spec cleanup_resources(State) -> ok | {error, Reason} when
    State :: state(),
    Reason :: connection_error().
cleanup_resources(State) ->
    Socket = State#connection_state.socket,
    try
        gen_tcp:close(Socket),
        ok
    catch
        _:CloseError ->
            Details = io_lib:format("Failed to close socket: ~p", [CloseError]),
            {error, {resource_cleanup_error, lists:flatten(Details)}}
    end.

%% @doc Send INSERT packet sequence (Query + Data + Blank)
%% Requirements: 1.1, 1.2, 1.3
-spec send_insert_packets(State, PreparedRequest, From, Timeout) ->
    {ok, NewState} | {error, Reason}
when
    State :: state(),
    PreparedRequest :: map(),
    From :: {pid(), term()},
    Timeout :: timeout(),
    NewState :: state(),
    Reason :: connection_error().
send_insert_packets(State, PreparedRequest, From, Timeout) ->
    Socket = State#connection_state.socket,

    %% Get negotiated protocol version
    NegotiatedVersion = State#connection_state.negotiated_version,
    true = is_integer(NegotiatedVersion),

    %% Get query ID from prepared request or generate
    QueryId = maps:get(query_id, PreparedRequest),

    %% Extract parameters from PreparedRequest (default to empty list)
    Parameters = maps:get(parameters, PreparedRequest, []),

    %% Validate parameters
    case validate_parameters(Parameters) of
        ok ->
            %% Check version support for parameters
            case should_send_parameters(Parameters, NegotiatedVersion) of
                ok ->
                    %% Determine compression value for query packet using helper function
                    CompressionValue = get_compression_mode(
                        State#connection_state.compression_opts
                    ),

                    %% Construct QueryInfo map for packet encoding
                    %% (include parameters and compression)
                    QueryInfo = #{
                        query_id => QueryId,
                        client_info => create_client_info(NegotiatedVersion, QueryId),
                        settings => maps:get(settings, PreparedRequest, []),
                        query_body => maps:get(sql, PreparedRequest),
                        parameters => Parameters,
                        compression => CompressionValue
                    },

                    %% Debug logging
                    ?LOG_DEBUG("INSERT query body: ~p~n", [maps:get(query_body, QueryInfo)]),
                    ?LOG_DEBUG("INSERT parameters: ~p~n", [Parameters]),
                    ?LOG_DEBUG("INSERT compression: ~p~n", [CompressionValue]),
                    ?LOG_DEBUG("Using negotiated version: ~p~n", [NegotiatedVersion]),

                    execute_insert_with_validated_params(
                        State,
                        PreparedRequest,
                        From,
                        Timeout,
                        QueryInfo,
                        Socket,
                        NegotiatedVersion,
                        QueryId
                    );
                {error, Reason} ->
                    ?LOG_ERROR("Parameters not supported by server version", #{
                        error => Reason,
                        parameters => Parameters,
                        version => NegotiatedVersion
                    }),
                    {error, Reason}
            end;
        {error, Reason} ->
            ?LOG_ERROR("Parameter validation failed for INSERT", #{
                error => Reason,
                parameters => Parameters
            }),
            {error, Reason}
    end.

%% @doc Execute INSERT with validated parameters
%% Internal helper function to continue INSERT execution after parameter validation
-spec execute_insert_with_validated_params(
    State, PreparedRequest, From, Timeout, QueryInfo, Socket, NegotiatedVersion, QueryId
) ->
    {ok, NewState} | {error, Reason}
when
    State :: state(),
    PreparedRequest :: map(),
    From :: {pid(), term()},
    Timeout :: timeout(),
    QueryInfo :: map(),
    Socket :: gen_tcp:socket(),
    NegotiatedVersion :: non_neg_integer(),
    QueryId :: binary(),
    NewState :: state(),
    Reason :: connection_error().
execute_insert_with_validated_params(
    State, PreparedRequest, From, Timeout, QueryInfo, Socket, NegotiatedVersion, QueryId
) ->
    maybe
        %% Step 1: Encode query packet
        {ok, QueryPacket} ?=
            clickhouse_erl_protocol_query_packet:encode(QueryInfo, NegotiatedVersion),
        ?LOG_DEBUG("Encoded query packet, size: ~p bytes~n", [byte_size(QueryPacket)]),
        %% Step 2: Set socket to active mode BEFORE sending any packets
        %% This prevents race condition where response arrives before we're listening
        ok ?= inet:setopts(Socket, [{active, once}]),
        %% Step 3: Send query packet + blank block
        %% CRITICAL: Blank block must be compressed if compression is enabled
        BlankBlockAfterQuery = encode_blank_data_block(State#connection_state.compression_opts),
        ok ?= gen_tcp:send(Socket, [QueryPacket, BlankBlockAfterQuery]),
        ?LOG_DEBUG("Query packet and blank block sent successfully~n", []),
        %% Step 4: Encode and send data block using shared helper
        Input = maps:get(input, PreparedRequest),
        ok ?= encode_and_send_block(State, Input),
        NumRows = maps:get(num_rows, PreparedRequest),
        ?LOG_DEBUG("Data block sent successfully (~p rows)~n", [NumRows]),
        %% Step 6: Send final blank block
        %% CRITICAL: Blank block must be compressed if compression is enabled
        BlankBlockAfterData = encode_blank_data_block(State#connection_state.compression_opts),
        ok ?= gen_tcp:send(Socket, BlankBlockAfterData),
        ?LOG_DEBUG("Final blank data block sent successfully~n", []),
        %% Step 7: Start timeout timer
        TimerRef = create_timeout_timer(Timeout, QueryId),
        %% Step 8: Update connection state
        %% Build ActiveQueryState using helper function and add INSERT-specific fields
        ActiveQueryState0 = create_active_query_state(
            From,
            QueryId,
            Timeout,
            TimerRef,
            PreparedRequest,
            State#connection_state.compression_opts
        ),
        ActiveQueryState = ActiveQueryState0#{
            is_insert => true,
            rows_to_insert => NumRows
        },
        NewState = State#connection_state{active_query_state = ActiveQueryState},
        {ok, NewState}
    else
        {error, Reason} when is_tuple(Reason) ->
            %% Classify error based on context
            case Reason of
                {protocol_error, _} -> {error, Reason};
                {send_failed, _} -> {error, Reason};
                _ -> {error, {protocol_error, Reason}}
            end;
        {error, Reason} ->
            {error, {network_error, Reason}}
    end.

%% @doc Complete an active query by cancelling its timer, replying, and clearing state.
%% Returns {noreply, NewState} for use in handle_info/handle_cast.
-spec complete_query(state(), Reply) ->
    {noreply, state()}
when
    Reply :: {ok, term()} | {error, term()}.
complete_query(State, Reply) ->
    case State#connection_state.active_query_state of
        undefined ->
            {noreply, State};
        #{caller := Caller, timer_ref := TimerRef} ->
            maybe_cancel_timer(TimerRef),
            gen_server:reply(Caller, Reply),
            CompletedState = State#connection_state{
                active_query_state = undefined,
                parser_state = undefined
            },
            {noreply, CompletedState}
    end.

%% @doc Handle pull-based streaming insert request.
%% Validates inputs, sends query, runs streaming loop, and finalizes.
-spec handle_streaming_insert(State, PreparedRequest) ->
    {ok, Result, NewState} | {error, Reason, NewState} | {error, Reason}
when
    State :: state(),
    PreparedRequest :: map(),
    Result :: streaming_insert_result(),
    NewState :: state(),
    Reason :: term().
handle_streaming_insert(State, PreparedRequest) ->
    maybe
        ok ?= check_connection_ready(State),
        ok ?= check_no_active_query(State),
        ok ?= validate_prepared_request(PreparedRequest),
        ok ?= validate_on_input_present(PreparedRequest),
        ok ?= validate_columns_not_empty(PreparedRequest),
        {ok, NewState} ?= send_query_and_blank_block(State, PreparedRequest),
        StateWithParser = ensure_parser_state(NewState),
        run_streaming_loop(StateWithParser, PreparedRequest)
    end.

%% @doc Handle push-based start_streaming_insert request.
%% Validates inputs, sends query, creates push session state.
-spec handle_start_streaming_insert(State, PreparedRequest) ->
    {ok, StreamRef, NewState} | {error, Reason}
when
    State :: state(),
    PreparedRequest :: map(),
    StreamRef :: reference(),
    NewState :: state(),
    Reason :: term().
handle_start_streaming_insert(State, PreparedRequest) ->
    maybe
        ok ?= check_connection_ready(State),
        ok ?= check_no_active_query(State),
        ok ?= validate_prepared_request(PreparedRequest),
        {ok, NewState} ?= send_query_and_blank_block(State, PreparedRequest),
        StateWithParser = ensure_parser_state(NewState),
        set_passive_and_drain(StateWithParser),
        {ok, StreamRef, FinalState} ?= create_push_session(StateWithParser, PreparedRequest),
        {ok, StreamRef, FinalState}
    end.

%% @doc Check that no active query is in progress.
-spec check_no_active_query(state()) -> ok | {error, term()}.
check_no_active_query(State) ->
    case State#connection_state.active_query_state of
        undefined -> ok;
        _ -> {error, {connection_error, query_in_progress}}
    end.

%% @doc Validate that on_input callback is present in the request.
-spec validate_on_input_present(map()) -> ok | {error, term()}.
validate_on_input_present(PreparedRequest) ->
    case maps:find(on_input, PreparedRequest) of
        {ok, _} -> ok;
        error -> {error, {validation_error, missing_on_input_callback}}
    end.

%% @doc Validate that columns list is not empty.
-spec validate_columns_not_empty(map()) -> ok | {error, term()}.
validate_columns_not_empty(PreparedRequest) ->
    case maps:get(columns, PreparedRequest, []) of
        [] -> {error, {validation_error, empty_columns}};
        _ -> ok
    end.

%% @doc Ensure parser state is initialized.
-spec ensure_parser_state(state()) -> state().
ensure_parser_state(State) ->
    case State#connection_state.parser_state of
        undefined ->
            PS = clickhouse_erl_parser:init(
                State#connection_state.negotiated_version,
                State#connection_state.compression_opts
            ),
            State#connection_state{parser_state = PS};
        _ ->
            State
    end.

%% @doc Set socket to passive mode and drain any pending TCP message.
-spec set_passive_and_drain(state()) -> ok.
set_passive_and_drain(State) ->
    inet:setopts(State#connection_state.socket, [{active, false}]),
    receive
        {tcp, _, _} -> ok
    after 0 -> ok
    end.

%% @doc Run the streaming loop and handle completion/error.
-spec run_streaming_loop(state(), map()) ->
    {ok, streaming_insert_result(), state()} | {error, term(), state()}.
run_streaming_loop(State, PreparedRequest) ->
    Columns = maps:get(columns, PreparedRequest, []),
    OnInput = maps:get(on_input, PreparedRequest),
    InitialAcc = maps:get(initial_accumulator, PreparedRequest, #{}),
    Timeout = maps:get(timeout, PreparedRequest, 30000),
    inet:setopts(State#connection_state.socket, [{active, false}]),
    InitialStats = #{
        rows_inserted => 0,
        blocks_sent => 0,
        start_time => erlang:system_time(millisecond),
        timeout => Timeout
    },
    case streaming_loop(State, Columns, InitialAcc, OnInput, InitialStats) of
        {ok, _FinalAcc, FinalStats} ->
            finalize_streaming_insert(State, FinalStats);
        {error, Reason} ->
            %% Send best-effort blank block
            _ = gen_tcp:send(
                State#connection_state.socket,
                encode_blank_data_block(State#connection_state.compression_opts)
            ),
            %% Drain server response to leave connection clean
            _ = wait_for_end_of_stream(State),
            TargetState =
                case Reason of
                    {network_error, _} -> error;
                    _ -> ready
                end,
            {error, Reason, clear_active_query_state(State, TargetState)}
    end.

%% @doc Send final blank block and return result.
-spec finalize_streaming_insert(state(), map()) ->
    {ok, streaming_insert_result(), state()} | {error, term(), state()}.
finalize_streaming_insert(State, FinalStats) ->
    case
        gen_tcp:send(
            State#connection_state.socket,
            encode_blank_data_block(State#connection_state.compression_opts)
        )
    of
        ok ->
            %% Wait for SERVER_END_OF_STREAM before returning
            case wait_for_end_of_stream(State) of
                ok ->
                    {ok, build_streaming_result(FinalStats), clear_active_query_state(State)};
                {error, Reason} ->
                    {error, Reason, clear_active_query_state(State)}
            end;
        {error, Reason} ->
            {error, {network_error, Reason}, clear_active_query_state(State, error)}
    end.

%% @doc Wait for SERVER_END_OF_STREAM after sending final blank block.
%% Uses passive recv to consume the server's response.
-spec wait_for_end_of_stream(state()) -> ok | {error, term()}.
wait_for_end_of_stream(State) ->
    Socket = State#connection_state.socket,
    StateWithParser = ensure_parser_state(State),
    wait_for_end_of_stream_loop(Socket, StateWithParser#connection_state.parser_state).

wait_for_end_of_stream_loop(Socket, ParserState) ->
    case gen_tcp:recv(Socket, 0, 5000) of
        {ok, Data} ->
            case clickhouse_erl_parser:parse(Data, ParserState) of
                {ok, Events, NewParserState} ->
                    case has_end_of_stream(Events) of
                        true -> ok;
                        false -> wait_for_end_of_stream_loop(Socket, NewParserState)
                    end;
                {error, _Reason} ->
                    ok
            end;
        {error, timeout} ->
            ok;
        {error, Reason} ->
            {error, {network_error, Reason}}
    end.

has_end_of_stream([]) -> false;
has_end_of_stream([{'end', server_end_of_stream} | _]) -> true;
has_end_of_stream([{start, server_end_of_stream} | _]) -> true;
has_end_of_stream([_ | Rest]) -> has_end_of_stream(Rest).

%% @doc Create push session state for start_streaming_insert.
-spec create_push_session(state(), map()) -> {ok, reference(), state()}.
create_push_session(State, PreparedRequest) ->
    StreamRef = make_ref(),
    Columns = maps:get(columns, PreparedRequest, []),
    Timeout = maps:get(timeout, PreparedRequest, 30000),
    SessionState = #{
        streaming_mode => push,
        stream_ref => StreamRef,
        expected_columns => Columns,
        rows_inserted => 0,
        blocks_sent => 0,
        session_failed => false,
        start_time => erlang:system_time(millisecond)
    },
    TimerRef =
        case Timeout =/= infinity of
            true -> erlang:send_after(Timeout, self(), {streaming_timeout, StreamRef});
            false -> undefined
        end,
    ActiveState = State#connection_state.active_query_state,
    NewActiveState = ActiveState#{
        push_session => SessionState, timeout_timer => TimerRef
    },
    {ok, StreamRef, State#connection_state{active_query_state = NewActiveState}}.

%% @doc Send query packet and blank block for streaming insert.
%% Returns {ok, NewState} with active_query_state set, or {error, Reason}.
-spec send_query_and_blank_block(State, PreparedRequest) -> {ok, NewState} | {error, Reason} when
    State :: state(),
    PreparedRequest :: map(),
    NewState :: state(),
    Reason :: connection_error().
send_query_and_blank_block(State, PreparedRequest) ->
    Socket = State#connection_state.socket,
    NegotiatedVersion = State#connection_state.negotiated_version,
    QueryId = maps:get(query_id, PreparedRequest),
    Timeout = maps:get(timeout, PreparedRequest, 30000),

    %% Build QueryInfo - reuse existing pattern (same as execute_query/execute_insert)
    CompressionMode = get_compression_mode(State#connection_state.compression_opts),
    QueryInfo = #{
        query_id => QueryId,
        client_info => create_client_info(NegotiatedVersion, QueryId),
        settings => maps:get(settings, PreparedRequest, []),
        query_body => maps:get(sql, PreparedRequest),
        parameters => maps:get(parameters, PreparedRequest, []),
        compression => CompressionMode
    },

    maybe
        %% Step 1: Encode query packet
        {ok, QueryPacket} ?=
            clickhouse_erl_protocol_query_packet:encode(QueryInfo, NegotiatedVersion),
        %% Step 2: Set socket to active mode BEFORE sending any packets
        ok ?= inet:setopts(Socket, [{active, once}]),
        %% Step 3: Send query packet + blank block
        BlankBlock = encode_blank_data_block(State#connection_state.compression_opts),
        ok ?= gen_tcp:send(Socket, [QueryPacket, BlankBlock]),
        %% Step 4: Start timeout timer
        TimerRef = create_timeout_timer(Timeout, QueryId),
        %% Step 5: Update connection state
        ActiveQueryState = #{
            caller => {self(), undefined},
            query_id => QueryId,
            timeout => Timeout,
            timer_ref => TimerRef,
            cancelled => false,
            replied => false,
            is_insert => true,
            on_data => fun default_on_data_callback/2,
            accumulator => #{}
        },
        NewState = State#connection_state{active_query_state = ActiveQueryState},
        {ok, NewState}
    else
        {error, Reason} when is_tuple(Reason) ->
            %% Classify error based on context
            case Reason of
                {protocol_error, _} -> {error, Reason};
                {send_failed, _} -> {error, Reason};
                _ -> {error, {protocol_error, Reason}}
            end;
        {error, Reason} ->
            {error, {network_error, Reason}}
    end.

%% @doc Build streaming insert result map.
-spec build_streaming_result(SessionState) -> Result when
    SessionState :: #{rows_inserted := non_neg_integer(), blocks_sent := non_neg_integer()},
    Result :: #{
        rows_inserted := non_neg_integer(),
        blocks_sent := non_neg_integer(),
        elapsed_time := non_neg_integer()
    }.
build_streaming_result(SessionState) ->
    clickhouse_erl_streaming_helpers:build_streaming_result(SessionState).

%% @doc Clear active query state for streaming insert.
%% Sets connection state to ready after clearing active query.
-spec clear_active_query_state(State) -> NewState when
    State :: state(),
    NewState :: state().
clear_active_query_state(State) ->
    clear_active_query_state(State, ready).

%% @doc Clear active query state for streaming insert with explicit target state.
%% Use `ready` for normal completion or recoverable errors (callback, validation, server exception
%% when TCP remains open). Use `error` for network errors where the TCP connection is broken.
-spec clear_active_query_state(State, TargetState) -> NewState when
    State :: state(),
    TargetState :: ready | error,
    NewState :: state().
clear_active_query_state(State, TargetState) ->
    %% Cancel timeout timer if it exists
    case State#connection_state.active_query_state of
        #{timeout_timer := TimerRef} when TimerRef =/= undefined ->
            erlang:cancel_timer(TimerRef);
        _ ->
            ok
    end,
    State#connection_state{
        state = TargetState,
        active_query_state = undefined,
        parser_state = undefined
    }.

%% @doc Cancel a timer if it is set.
-spec maybe_cancel_timer(reference() | undefined) -> ok.
maybe_cancel_timer(undefined) ->
    ok;
maybe_cancel_timer(TimerRef) ->
    erlang:cancel_timer(TimerRef),
    ok.

%%%===================================================================
%%% Push-based streaming insert helpers
%%%===================================================================

%% @doc Extract push session from connection state.
%% Returns {ok, ActiveState, SessionState} or {error, Reason}.
-spec get_push_session(state()) ->
    {ok, map(), map()} | {error, term()}.
get_push_session(#connection_state{active_query_state = undefined}) ->
    {error, {validation_error, no_active_streaming_session}};
get_push_session(#connection_state{active_query_state = ActiveState}) ->
    case maps:get(push_session, ActiveState, undefined) of
        undefined ->
            {error, {validation_error, no_active_streaming_session}};
        SessionState ->
            {ok, ActiveState, SessionState}
    end.

%% @doc Check push session is valid for send_data: not failed, ref matches.
-spec check_push_session_valid(map(), reference()) -> ok | {error, term()}.
check_push_session_valid(SessionState, StreamRef) ->
    case maps:get(session_failed, SessionState, false) of
        {true, FailReason} ->
            {error, FailReason};
        false ->
            case maps:get(stream_ref, SessionState) of
                StreamRef -> ok;
                _ -> {error, {validation_error, invalid_stream_ref}}
            end
    end.

%% @doc Handle send_data after session validation passes.
%% Validates column data, encodes, sends, checks server response.
-spec handle_send_data(state(), map(), map(), [map()]) ->
    {reply, ok | {error, term()}, state()}.
handle_send_data(State, ActiveState, SessionState, ColumnData) ->
    ExpectedColumns = maps:get(expected_columns, SessionState),
    case validate_streaming_block(ColumnData, ExpectedColumns) of
        ok ->
            case has_rows(ColumnData) of
                false ->
                    %% Skip empty blocks — session stays active
                    {reply, ok, State};
                true ->
                    %% Merge types from column definitions into data
                    TypedData = merge_column_types(ColumnData, ExpectedColumns),
                    send_and_check(State, ActiveState, SessionState, TypedData)
            end;
        {error, Reason} ->
            %% Validation errors do NOT fail the session — caller can fix data and retry
            {reply, {error, Reason}, State}
    end.

%% @doc Encode, send a data block, then check for server exceptions.
-spec send_and_check(state(), map(), map(), [map()]) ->
    {reply, ok | {error, term()}, state()}.
send_and_check(State, ActiveState, SessionState, ColumnData) ->
    case encode_and_send_block(State, ColumnData) of
        ok ->
            case
                check_server_response(
                    State#connection_state.socket,
                    State#connection_state.parser_state
                )
            of
                {ok, NewParserState} ->
                    NumRows =
                        case ColumnData of
                            [] -> 0;
                            [#{data := Data} | _] -> length(Data)
                        end,
                    NewSession = SessionState#{
                        rows_inserted => maps:get(rows_inserted, SessionState) + NumRows,
                        blocks_sent => maps:get(blocks_sent, SessionState) + 1
                    },
                    {reply, ok, State#connection_state{
                        parser_state = NewParserState,
                        active_query_state = ActiveState#{push_session => NewSession}
                    }};
                {exception, ExceptionInfo, NewParserState} ->
                    NewSession = SessionState#{
                        session_failed => {true, {server_exception, ExceptionInfo}}
                    },
                    {reply, {error, {server_exception, ExceptionInfo}}, State#connection_state{
                        parser_state = NewParserState,
                        active_query_state = ActiveState#{push_session => NewSession}
                    }};
                {error, Reason} ->
                    NewSession = SessionState#{
                        session_failed => {true, {network_error, Reason}}
                    },
                    {reply, {error, {network_error, Reason}}, State#connection_state{
                        active_query_state = ActiveState#{push_session => NewSession}
                    }}
            end;
        {error, Reason} ->
            NewSession = SessionState#{
                session_failed => {true, {network_error, Reason}}
            },
            {reply, {error, {network_error, Reason}}, State#connection_state{
                active_query_state = ActiveState#{push_session => NewSession}
            }}
    end.

%% @doc Handle finish_streaming_insert after validation passes.
-spec handle_finish_streaming(state(), map()) ->
    {reply, {ok, map()} | {error, term()}, state()}.
handle_finish_streaming(State, SessionState) ->
    case
        gen_tcp:send(
            State#connection_state.socket,
            encode_blank_data_block(State#connection_state.compression_opts)
        )
    of
        ok ->
            %% Wait for SERVER_END_OF_STREAM before returning
            case wait_for_end_of_stream(State) of
                ok ->
                    {reply, {ok, build_streaming_result(SessionState)},
                        clear_active_query_state(State)};
                {error, Reason} ->
                    {reply, {error, Reason}, clear_active_query_state(State)}
            end;
        {error, Reason} ->
            {reply, {error, {network_error, Reason}}, clear_active_query_state(State, error)}
    end.

%% @doc Handle the result of process_events after successful parsing.
%% Checks for exceptions, end_of_stream, or continues waiting.
-spec handle_parsed_events(
    boolean(), map(), term(), state(), gen_tcp:socket()
) -> {noreply, state()}.
handle_parsed_events(HasEndOfStream, NewAccState, NewParserState, State, Socket) ->
    NewState = State#connection_state{parser_state = NewParserState},
    UpdatedQueryState =
        case NewState#connection_state.active_query_state of
            undefined -> undefined;
            QS -> QS#{accumulator => NewAccState}
        end,
    NewState2 = NewState#connection_state{active_query_state = UpdatedQueryState},
    ExceptionInfo = maps:get(exception_info, NewAccState, undefined),
    case ExceptionInfo of
        Info when is_map(Info), map_size(Info) > 0 ->
            ?LOG_DEBUG("Exception received: ~p~n", [Info]),
            complete_query(NewState2, {error, {server_exception, Info}});
        _ ->
            handle_end_or_continue(HasEndOfStream, NewAccState, NewState2, Socket)
    end.

%% @doc Handle end_of_stream or reactivate socket for more data.
-spec handle_end_or_continue(
    boolean(), map(), state(), gen_tcp:socket()
) -> {noreply, state()}.
handle_end_or_continue(true, NewAccState, State, _Socket) ->
    ?LOG_DEBUG("Query completed (end_of_stream received)~n", []),
    case State#connection_state.active_query_state of
        undefined ->
            ?LOG_WARNING("Received end_of_stream but no active query~n", []),
            {noreply, State};
        AQS ->
            Result =
                case maps:get(is_insert, AQS, false) of
                    true ->
                        RowsToInsert = maps:get(rows_to_insert, AQS, 0),
                        #{rows_inserted => RowsToInsert};
                    false ->
                        build_query_result(NewAccState)
                end,
            complete_query(State, {ok, Result})
    end;
handle_end_or_continue(false, _NewAccState, State, Socket) ->
    case inet:setopts(Socket, [{active, once}]) of
        ok ->
            {noreply, State};
        {error, SocketError} ->
            ?LOG_ERROR("Failed to reactivate socket: ~p~n", [SocketError]),
            ErrorState = State#connection_state{
                state = error,
                error_reason =
                    {network_error, {socket_reactivation_failed, SocketError}}
            },
            {noreply, ErrorState}
    end.

%% @doc Cancel timer and reply with error if not already replied
%% Helper function to eliminate code duplication
-spec cancel_timer_and_reply(TimerRef, Caller, ActiveQueryState, Error) -> ok when
    TimerRef :: reference() | undefined,
    Caller :: {pid(), term()},
    ActiveQueryState :: map(),
    Error :: term().
cancel_timer_and_reply(TimerRef, Caller, ActiveQueryState, Error) ->
    case TimerRef of
        undefined -> ok;
        _ -> erlang:cancel_timer(TimerRef)
    end,
    case maps:get(replied, ActiveQueryState, false) of
        false ->
            gen_server:reply(Caller, {error, Error});
        true ->
            ok
    end.

%% @doc Create timeout timer reference
%% Helper function to eliminate code duplication in timer creation
-spec create_timeout_timer(timeout(), binary()) -> reference() | undefined.
create_timeout_timer(infinity, _QueryId) ->
    undefined;
create_timeout_timer(Timeout, QueryId) ->
    erlang:send_after(Timeout, self(), {query_timeout, QueryId}).

%% @doc Safely invoke optional callback (non-fatal errors)
%% Optional callbacks (on_progress, on_profile, on_profile_events) are invoked
%% for monitoring purposes. Errors in these callbacks are logged but do not
%% stop query execution.
%% Requirements: 7.4
-spec invoke_optional_callback(Callback, Info) -> ok when
    Callback :: fun((map()) -> ok | {error, term()}),
    Info :: map().
invoke_optional_callback(Callback, Info) ->
    try
        case Callback(Info) of
            ok ->
                ok;
            {error, CallbackReason} ->
                %% Log but don't propagate error
                ?LOG_WARNING("Optional callback returned error", #{
                    error => CallbackReason,
                    info => Info
                }),
                ok;
            InvalidReturn ->
                ?LOG_WARNING("Optional callback returned invalid value", #{
                    return => InvalidReturn,
                    info => Info
                }),
                ok
        end
    catch
        ErrorClass:ErrorReason:ErrorStacktrace ->
            ?LOG_WARNING("Optional callback crashed", #{
                class => ErrorClass,
                reason => ErrorReason,
                stacktrace => ErrorStacktrace,
                info => Info
            }),
            ok
    end.

%% @doc Check if connection is ready for operations
%% Returns ok if ready, {error, Reason} otherwise
%% Rejects if active_query_state is set (connection busy with another query)
-spec check_connection_ready(State) -> ok | {error, Reason} when
    State :: state(),
    Reason :: connection_error().
check_connection_ready(#connection_state{state = ready, active_query_state = undefined}) ->
    ok;
check_connection_ready(#connection_state{state = ready, active_query_state = ActiveQueryState}) when
    ActiveQueryState =/= undefined
->
    {error, {connection_error, query_in_progress}};
check_connection_ready(#connection_state{state = error, error_reason = ErrorReason}) ->
    {error, ErrorReason};
check_connection_ready(#connection_state{state = connecting}) ->
    {error, {protocol_error, "Connection not ready"}}.

%% @doc Format binary data for logging
%% At INFO level: shows only first 20 bytes
%% At DEBUG level: shows full binary
-spec format_binary_for_log(binary()) -> iolist().
format_binary_for_log(Binary) when byte_size(Binary) =< 20 ->
    %% Small binary - show all
    io_lib:format("~p", [Binary]);
format_binary_for_log(Binary) ->
    %% Large binary - show first 20 bytes at INFO, full at DEBUG
    case logger:get_module_level(?MODULE) of
        [{?MODULE, debug}] ->
            io_lib:format("~p", [Binary]);
        _ ->
            <<First20:20/binary, _/binary>> = Binary,
            io_lib:format("~p... (~p bytes total)", [First20, byte_size(Binary)])
    end.

%% @doc Format error reason for logging, truncating any embedded binaries
-spec format_error_for_log(term()) -> term().
format_error_for_log({unknown_column_type, Type}) when is_binary(Type), byte_size(Type) > 50 ->
    <<First50:50/binary, _/binary>> = Type,
    {unknown_column_type, <<First50/binary, "... (truncated)">>};
format_error_for_log({protocol_error, Inner}) ->
    {protocol_error, format_error_for_log(Inner)};
format_error_for_log({ErrorType, Details}) when is_tuple(Details) ->
    {ErrorType, format_error_for_log(Details)};
format_error_for_log({ErrorType, Details}) ->
    {ErrorType, Details};
format_error_for_log(Other) ->
    Other.

%% @doc Validate query parameters format
%% Validates that all parameters are tuples of {binary(), binary()}.
%% Returns ok for valid parameters or {error, Reason} for invalid.
%% Requirements: 1.3, 1.4, 1.5, 7.1, 7.2, 7.3
-spec validate_parameters(Parameters) -> ok | {error, Reason} when
    Parameters :: [{Key :: binary(), Value :: binary()}],
    Reason ::
        {invalid_parameter_key, term()}
        | {invalid_parameter_value, term()}
        | {invalid_parameter_format, term()}.
validate_parameters(Parameters) when is_list(Parameters) ->
    validate_parameters_loop(Parameters).

%% @doc Internal loop for parameter validation
-spec validate_parameters_loop(Parameters) -> ok | {error, Reason} when
    Parameters :: list(),
    Reason ::
        {invalid_parameter_key, term()}
        | {invalid_parameter_value, term()}
        | {invalid_parameter_format, term()}.
validate_parameters_loop([]) ->
    ok;
validate_parameters_loop([{Key, Value} | Rest]) when is_binary(Key), is_binary(Value) ->
    validate_parameters_loop(Rest);
validate_parameters_loop([{Key, _Value} | _Rest]) when not is_binary(Key) ->
    Error = {invalid_parameter_key, Key},
    ?LOG_ERROR("Parameter validation failed: non-binary key", #{
        error => Error,
        key => Key,
        key_type => type_of(Key)
    }),
    {error, Error};
validate_parameters_loop([{_Key, Value} | _Rest]) when not is_binary(Value) ->
    Error = {invalid_parameter_value, Value},
    ?LOG_ERROR("Parameter validation failed: non-binary value", #{
        error => Error,
        value => Value,
        value_type => type_of(Value)
    }),
    {error, Error};
validate_parameters_loop([Param | _Rest]) ->
    Error = {invalid_parameter_format, Param},
    ?LOG_ERROR("Parameter validation failed: invalid format", #{
        error => Error,
        parameter => Param,
        expected_format => "{binary(), binary()}"
    }),
    {error, Error}.

%% @doc Check if parameters are supported by the server version
%% Returns ok if parameters are supported or if the parameter list is empty.
%% Returns {error, {parameters_unsupported, Version}} if parameters are provided
%% but the server version doesn't support them.
%% Requirements: 2.1, 2.2, 7.4
-spec should_send_parameters(Parameters, Version) -> ok | {error, Reason} when
    Parameters :: [{Key :: binary(), Value :: binary()}],
    Version :: non_neg_integer(),
    Reason :: {parameters_unsupported, non_neg_integer()}.
should_send_parameters([], _Version) ->
    %% Empty parameter list is always OK
    ok;
should_send_parameters(_Parameters, Version) ->
    %% Check if version supports parameters feature
    case clickhouse_erl_protocol_features:has_feature(parameters, Version) of
        true ->
            ok;
        false ->
            Error = {parameters_unsupported, Version},
            ?LOG_ERROR("Parameters not supported by server version", #{
                error => Error,
                server_version => Version,
                required_version => 54459
            }),
            {error, Error}
    end.

%% @doc Get type name for logging purposes
-spec type_of(term()) -> atom().
type_of(Term) when is_atom(Term) -> atom;
type_of(Term) when is_binary(Term) -> binary;
type_of(Term) when is_integer(Term) -> integer;
type_of(Term) when is_float(Term) -> float;
type_of(Term) when is_list(Term) -> list;
type_of(Term) when is_tuple(Term) -> tuple;
type_of(Term) when is_map(Term) -> map;
type_of(Term) when is_pid(Term) -> pid;
type_of(Term) when is_reference(Term) -> reference;
type_of(Term) when is_function(Term) -> function;
type_of(_) -> unknown.

%% @doc Get compression mode value for query packet
%% Converts compression_opts to protocol compression mode (0 or 1).
%% Returns ?COMPRESSION_ENABLED (1) if compression is enabled (lz4, zstd, or none).
%% Returns ?COMPRESSION_DISABLED (0) if compression is disabled or undefined.
%% Requirements: 5.1, 5.2
-spec get_compression_mode(CompressionOpts) -> compression_mode() when
    CompressionOpts :: clickhouse_erl_compression:compression_opts() | undefined.
get_compression_mode(undefined) ->
    ?COMPRESSION_DISABLED;
get_compression_mode(CompressionOpts) when is_map(CompressionOpts) ->
    case maps:get(method, CompressionOpts, disabled) of
        disabled -> ?COMPRESSION_DISABLED;
        lz4 -> ?COMPRESSION_ENABLED;
        zstd -> ?COMPRESSION_ENABLED;
        none -> ?COMPRESSION_ENABLED
    end.

%% @doc Process a list of parser events against the accumulator state.
%% Returns {HasEndOfStream, NeedMore, HasException, NewAccState}
%% or {callback_error, Reason} if a streaming callback fails.
-spec process_events([term()], map()) ->
    {boolean(), boolean(), boolean(), map()} | {callback_error, term()}.
process_events(EventList, AccState) ->
    process_events_loop(EventList, false, false, false, AccState).

-spec process_events_loop([term()], boolean(), boolean(), boolean(), map()) ->
    {boolean(), boolean(), boolean(), map()} | {callback_error, term()}.
process_events_loop([], EosAcc, NmAcc, ExAcc, Acc) ->
    {EosAcc, NmAcc, ExAcc, Acc};
process_events_loop([Event | Rest], EosAcc, NmAcc, ExAcc, Acc) ->
    case process_single_event(Event, EosAcc, NmAcc, ExAcc, Acc) of
        {callback_error, _Reason} = Err ->
            Err;
        {NewEos, NewNm, NewEx, NewAcc} ->
            process_events_loop(Rest, NewEos, NewNm, NewEx, NewAcc)
    end.

-spec process_single_event(term(), boolean(), boolean(), boolean(), map()) ->
    {boolean(), boolean(), boolean(), map()} | {callback_error, term()}.
process_single_event(need_more, EosAcc, _NmAcc, ExAcc, Acc) ->
    {EosAcc, true, ExAcc, Acc};
process_single_event({start, server_exception}, EosAcc, NmAcc, _ExAcc, Acc) ->
    {EosAcc, NmAcc, true, Acc#{
        exception_info => #{},
        current_block_type => server_exception
    }};
process_single_event({start, server_log}, EosAcc, NmAcc, ExAcc, Acc) ->
    {EosAcc, NmAcc, ExAcc, Acc#{
        current_block_type => server_log,
        log_columns => #{},
        log_column_order => [],
        log_current_column => undefined
    }};
process_single_event({start, Type}, EosAcc, NmAcc, ExAcc, Acc) when
    Type =:= server_data; Type =:= server_totals; Type =:= server_extremes
->
    {EosAcc, NmAcc, ExAcc, Acc#{current_block_type => Type, current_block_rows => 0}};
process_single_event({start, Type}, EosAcc, NmAcc, ExAcc, Acc) ->
    {EosAcc, NmAcc, ExAcc, Acc#{current_block_type => Type}};
process_single_event({'end', server_end_of_stream}, _EosAcc, NmAcc, ExAcc, Acc) ->
    FinalizedAcc = finalize_streaming_end(Acc),
    {true, NmAcc, ExAcc, FinalizedAcc};
process_single_event({'end', server_exception}, EosAcc, NmAcc, _ExAcc, Acc) ->
    {EosAcc, NmAcc, true, Acc#{current_block_type => undefined}};
process_single_event({'end', Type}, EosAcc, NmAcc, ExAcc, Acc) when
    Type =:= server_data; Type =:= server_totals; Type =:= server_extremes
->
    case maps:get(current_block_rows, Acc, 0) of
        0 ->
            {EosAcc, NmAcc, ExAcc, Acc#{
                current_block_type => undefined,
                current_block_rows => 0
            }};
        _N ->
            case dispatch_block_end(EosAcc, NmAcc, ExAcc, Acc) of
                {callback_error, _} = Err ->
                    Err;
                {NewEos, NewNm, NewEx, NewAcc} ->
                    {NewEos, NewNm, NewEx, NewAcc#{
                        current_block_type => undefined,
                        current_block_rows => 0
                    }}
            end
    end;
process_single_event({'end', server_log}, EosAcc, NmAcc, ExAcc, Acc) ->
    LogColumns = maps:get(log_columns, Acc, #{}),
    LogColumnOrder = maps:get(log_column_order, Acc, []),
    OnLogCallback = maps:get(on_log_callback, Acc, fun(_) -> ok end),
    Entries = assemble_log_entries(LogColumnOrder, LogColumns),
    dispatch_log_entries(OnLogCallback, Entries),
    {EosAcc, NmAcc, ExAcc, Acc#{current_block_type => undefined}};
process_single_event({'end', _Type}, EosAcc, NmAcc, ExAcc, Acc) ->
    {EosAcc, NmAcc, ExAcc, Acc#{current_block_type => undefined}};
process_single_event({data, Field, Value}, EosAcc, NmAcc, ExAcc, Acc) when ExAcc ->
    NewAcc = accumulate_exception_field(Field, Value, Acc),
    {EosAcc, NmAcc, ExAcc, NewAcc};
process_single_event({data, column, ColumnMeta}, EosAcc, NmAcc, ExAcc, Acc) ->
    case maps:get(current_block_type, Acc, undefined) of
        server_data ->
            ColName = maps:get(name, ColumnMeta, undefined),
            ColType = maps:get(type, ColumnMeta, undefined),
            %% If the default callback is in use, update its accumulator with
            %% column metadata directly. The default callback accumulator has a
            %% column_meta key; user accumulators do not.
            Acc2 =
                case maps:get(user_acc, Acc, undefined) of
                    #{column_meta := _} = UserAcc ->
                        %% Default callback accumulator — inject column_meta
                        case maps:is_key(ColName, maps:get(column_meta, UserAcc)) of
                            true ->
                                %% First occurrence wins (Req 5.3)
                                Acc;
                            false ->
                                NewMeta = (maps:get(column_meta, UserAcc))#{
                                    ColName => #{name => ColName, type => ColType}
                                },
                                Acc#{user_acc => UserAcc#{column_meta => NewMeta}}
                        end;
                    _ ->
                        Acc
                end,
            {EosAcc, NmAcc, ExAcc, Acc2#{
                current_column => ColumnMeta,
                current_column_name => ColName,
                current_column_type => ColType
            }};
        server_log ->
            ColName = maps:get(name, ColumnMeta, undefined),
            LogColumnOrder = maps:get(log_column_order, Acc, []),
            {EosAcc, NmAcc, ExAcc, Acc#{
                log_current_column => ColName,
                log_column_order => LogColumnOrder ++ [ColName]
            }};
        _ ->
            {EosAcc, NmAcc, ExAcc, Acc}
    end;
process_single_event({data, column_value, Value}, EosAcc, NmAcc, ExAcc, Acc) ->
    case maps:get(current_block_type, Acc, undefined) of
        server_data ->
            dispatch_column_value(Value, EosAcc, NmAcc, ExAcc, Acc);
        server_log ->
            LogCurrentColumn = maps:get(log_current_column, Acc, undefined),
            LogColumns = maps:get(log_columns, Acc, #{}),
            ExistingValues = maps:get(LogCurrentColumn, LogColumns, []),
            NewLogColumns = LogColumns#{LogCurrentColumn => ExistingValues ++ [Value]},
            {EosAcc, NmAcc, ExAcc, Acc#{log_columns => NewLogColumns}};
        _ ->
            {EosAcc, NmAcc, ExAcc, Acc}
    end;
process_single_event({data, wrote_rows, WroteRows}, EosAcc, NmAcc, ExAcc, Acc) ->
    PrevWritten = maps:get(rows_written, Acc, 0),
    {EosAcc, NmAcc, ExAcc, Acc#{rows_written => PrevWritten + WroteRows}};
process_single_event({data, num_rows, NumRows}, EosAcc, NmAcc, ExAcc, Acc) ->
    case maps:get(current_block_type, Acc, undefined) of
        Type when Type =:= server_data; Type =:= server_totals; Type =:= server_extremes ->
            {EosAcc, NmAcc, ExAcc, Acc#{current_block_rows => NumRows}};
        _ ->
            {EosAcc, NmAcc, ExAcc, Acc}
    end;
process_single_event({data, _Field, _Value}, EosAcc, NmAcc, ExAcc, Acc) ->
    {EosAcc, NmAcc, ExAcc, Acc}.

%% @doc Default streaming callback that replicates batch accumulation behavior.
%% Used when the user does not provide an `on_data' callback. Accumulates
%% column values in a map and transposes to row-oriented format on `'end''.
%%
%% Handles four event types:
%% - `{column_meta, #{name, type}}' — stores column metadata (first occurrence wins)
%% - `{data, #{name, value}}' — accumulates value under column name
%% - `block_end' — block boundary signal; default callback ignores it (returns Acc unchanged)
%% - `'end'' — reverses value lists, transposes to `#{columns, rows}'
%%
%% Returns `{ok, NewAcc}' for data/column_meta/block_end events, and
%% `{ok, #{columns => [...], rows => [...]}' for the `'end'' event.
-spec default_on_data_callback(Event, Acc) -> {ok, NewAcc} when
    Event ::
        {data, #{name := binary(), value := term()}}
        | {column_meta, #{name := binary(), type := binary()}}
        | block_end
        | 'end',
    Acc :: default_callback_acc(),
    NewAcc :: default_callback_acc() | batch_result().
default_on_data_callback(block_end, Acc) ->
    {ok, Acc};
default_on_data_callback({column_meta, #{name := ColName, type := ColType}}, Acc) ->
    #{column_order := Order, column_meta := Meta} = Acc,
    %% First occurrence wins (Req 5.3)
    case maps:is_key(ColName, Meta) of
        true ->
            {ok, Acc};
        false ->
            {ok, Acc#{
                column_order => [ColName | Order],
                column_meta => Meta#{ColName => #{name => ColName, type => ColType}}
            }}
    end;
default_on_data_callback({data, #{name := ColName, value := Value}}, Acc) ->
    #{column_order := Order, column_values := Values} = Acc,
    %% Track column order on first data event if not already tracked via column_meta
    NewOrder =
        case lists:member(ColName, Order) of
            true -> Order;
            false -> [ColName | Order]
        end,
    %% Prepend value (reversed on 'end' for efficiency)
    ExistingValues = maps:get(ColName, Values, []),
    {ok, Acc#{
        column_order => NewOrder,
        column_values => Values#{ColName => [Value | ExistingValues]}
    }};
default_on_data_callback('end', #{column_order := [], column_meta := _, column_values := _}) ->
    %% Zero-row case
    {ok, #{columns => [], rows => []}};
default_on_data_callback('end', Acc) ->
    #{column_order := Order0, column_meta := Meta, column_values := Values} = Acc,
    %% Reverse column order (was accumulated in reverse via prepend)
    Order = lists:reverse(Order0),
    %% Build columns metadata in order
    Columns = [maps:get(ColName, Meta, #{name => ColName, type => <<>>}) || ColName <- Order],
    %% Reverse value lists (were accumulated in reverse)
    ReversedValues = [lists:reverse(maps:get(ColName, Values, [])) || ColName <- Order],
    %% Transpose column-oriented to row-oriented
    Rows = transpose_default_columns(ReversedValues),
    {ok, #{columns => Columns, rows => Rows}}.

%% @doc Transpose column-oriented value lists to row-oriented lists.
%% Input: [[col1_v1, col1_v2], [col2_v1, col2_v2]]
%% Output: [[col1_v1, col2_v1], [col1_v2, col2_v2]]
-spec transpose_default_columns([[term()]]) -> [[term()]].
transpose_default_columns([]) ->
    [];
transpose_default_columns(ColumnLists) ->
    case hd(ColumnLists) of
        [] ->
            [];
        _ ->
            NumRows = length(hd(ColumnLists)),
            [
                [lists:nth(RowIdx, ColData) || ColData <- ColumnLists]
             || RowIdx <- lists:seq(1, NumRows)
            ]
    end.

%% @doc Finalize streaming on end_of_stream by calling callback with 'end'.
%% The callback is always present in AccState (either the default batch-accumulating
%% callback or a user-provided one), so no branching is needed.
-spec finalize_streaming_end(map()) -> map().
finalize_streaming_end(Acc) ->
    Callback = maps:get(on_data_callback, Acc),
    UserAcc = maps:get(user_acc, Acc),
    {ok, FinalUserAcc} = Callback('end', UserAcc),
    Acc#{user_acc => FinalUserAcc}.

%% @doc Default on_log callback that logs each server log entry via ?LOG_DEBUG.
%% Used when no user-provided on_log callback is specified.
-spec default_on_log_callback(LogEntry :: map()) -> ok.
default_on_log_callback(LogEntry) ->
    ?LOG_DEBUG("ClickHouse server log: ~ts", [maps:get(<<"text">>, LogEntry, <<>>)], #{
        source => maps:get(<<"source">>, LogEntry, <<>>),
        priority => maps:get(<<"priority">>, LogEntry, 0),
        ch_query_id => maps:get(<<"query_id">>, LogEntry, <<>>),
        ch_host => maps:get(<<"host_name">>, LogEntry, <<>>)
    }),
    ok.

%% @doc Map parser exception field names to API names and accumulate.
-spec accumulate_exception_field(atom(), term(), map()) -> map().
accumulate_exception_field(Field, Value, Acc) ->
    MappedField =
        case Field of
            error_code -> code;
            exception_name -> name;
            stack_trace -> stack_trace;
            Other -> Other
        end,
    ExInfo = maps:get(exception_info, Acc, #{}),
    Acc#{exception_info => ExInfo#{MappedField => Value}}.

%% @doc Dispatch a column value through the streaming callback.
%% The callback is always present in AccState (either the default batch-accumulating
%% callback or a user-provided one), so no branching is needed.
-spec dispatch_column_value(term(), boolean(), boolean(), boolean(), map()) ->
    {boolean(), boolean(), boolean(), map()} | {callback_error, term()}.
dispatch_column_value(Value, EosAcc, NmAcc, ExAcc, Acc) ->
    Callback = maps:get(on_data_callback, Acc),
    invoke_streaming_callback(Callback, Value, EosAcc, NmAcc, ExAcc, Acc).

%% @doc Invoke the user streaming callback, returning error tuple on failure.
-spec invoke_streaming_callback(function(), term(), boolean(), boolean(), boolean(), map()) ->
    {boolean(), boolean(), boolean(), map()} | {callback_error, term()}.
invoke_streaming_callback(Callback, Value, EosAcc, NmAcc, ExAcc, Acc) ->
    ColName = maps:get(current_column_name, Acc, undefined),
    ColType = maps:get(current_column_type, Acc, undefined),
    UserAcc = maps:get(user_acc, Acc),
    try Callback({data, #{name => ColName, type => ColType, value => Value}}, UserAcc) of
        {ok, NewUserAcc} ->
            {EosAcc, NmAcc, ExAcc, Acc#{user_acc => NewUserAcc}};
        {error, Reason} ->
            {callback_error, Reason};
        Other ->
            {callback_error, {invalid_callback_return, Other}}
    catch
        error:Err:Stack ->
            {callback_error, {callback_crashed, {error, Err, Stack}}}
    end.

%% @doc Dispatch the block_end event through the streaming callback.
%% Invoked when an end-of-block parser event is processed for a data-carrying
%% block type with a non-zero row count. Mirrors invoke_streaming_callback/6
%% but dispatches the bare atom `block_end` instead of a {data, ...} tuple.
%%
%% Requirements: 1.3, 3.2
-spec dispatch_block_end(boolean(), boolean(), boolean(), map()) ->
    {boolean(), boolean(), boolean(), map()} | {callback_error, term()}.
dispatch_block_end(EosAcc, NmAcc, ExAcc, Acc) ->
    Callback = maps:get(on_data_callback, Acc),
    UserAcc = maps:get(user_acc, Acc),
    try Callback(block_end, UserAcc) of
        {ok, NewUserAcc} ->
            {EosAcc, NmAcc, ExAcc, Acc#{user_acc => NewUserAcc}};
        {error, Reason} ->
            {callback_error, Reason};
        Other ->
            {callback_error, {invalid_callback_return, Other}}
    catch
        error:Err:Stack ->
            {callback_error, {callback_crashed, {error, Err, Stack}}}
    end.

%% @doc Safely invoke the on_input callback for pull-based streaming insert.
%% Wraps callback invocation in try...catch to handle crashes and validates
%% return values against expected patterns.
%%
%% Requirements: 2.1, 2.4, 5.4, 5.5
%% Returns:
%%   {ok, UpdatedColumns, NewAcc} - Continue with next block
%%   {done, NewAcc} - Finish streaming
%%   {error, Reason} - Abort with error
%%   {error, {callback_crashed, {Class, Reason, Stacktrace}}} - Callback crashed
%%   {error, {invalid_callback_return, ReturnValue}} - Invalid return term
-spec safe_invoke_on_input(Callback :: function(), Columns :: [map()], Acc :: term()) ->
    {ok, [map()], term()} | {done, term()} | {error, term()}.
safe_invoke_on_input(Callback, Columns, Acc) ->
    clickhouse_erl_streaming_helpers:safe_invoke_on_input(Callback, Columns, Acc).

%% @doc Tail-recursive streaming loop for pull-based streaming insert.
%% Invokes on_input callback, validates block, encodes+send, recurses.
%% Skips empty blocks without incrementing block count.
%%
%% Requirements: 2.1, 2.2, 2.3, 3.3, 3.4, 4.1, 4.2, 4.3
%% Returns: {ok, FinalAcc, Stats} | {error, Reason}
-spec streaming_loop(State, Columns, Acc, OnInput, Stats) ->
    {ok, term(), #{rows_inserted := non_neg_integer(), blocks_sent := non_neg_integer()}}
    | {error, term()}
when
    State :: state(),
    Columns :: [map()],
    Acc :: term(),
    OnInput :: function(),
    Stats :: #{
        rows_inserted := non_neg_integer(),
        blocks_sent := non_neg_integer(),
        start_time := integer(),
        timeout := timeout()
    }.
streaming_loop(State, Columns, Acc, OnInput, Stats) ->
    %% NOTE: Pull-based cancellation via cancel_query/1,2 is not possible during the
    %% synchronous streaming loop because the gen_server is blocked. The only way to
    %% abort a running pull-based streaming loop is via timeout (check_timeout/2 below).
    %% Push-based cancellation works because each send_data is a separate gen_server:call.
    StartTime = maps:get(start_time, Stats),
    Timeout = maps:get(timeout, Stats),
    case check_timeout(StartTime, Timeout) of
        {error, Reason} ->
            {error, Reason};
        ok ->
            case safe_invoke_on_input(OnInput, Columns, Acc) of
                {done, FinalAcc} ->
                    {ok, FinalAcc, Stats};
                {error, Reason} ->
                    {error, {callback_error, Reason}};
                {ok, UpdatedColumns, NewAcc} ->
                    case process_streaming_block(State, UpdatedColumns, Columns) of
                        skip ->
                            streaming_loop(State, Columns, NewAcc, OnInput, Stats);
                        {ok, NewState} ->
                            NewStats = increment_stats(Stats, UpdatedColumns),
                            streaming_loop(NewState, Columns, NewAcc, OnInput, NewStats);
                        {error, Reason} ->
                            {error, Reason}
                    end
            end
    end.

%% @doc Process a single streaming block: validate, encode, send, check server response.
-spec process_streaming_block(state(), [map()], [map()]) ->
    skip | {ok, state()} | {error, term()}.
process_streaming_block(State, UpdatedColumns, OriginalColumns) ->
    maybe
        ok ?= validate_streaming_block(UpdatedColumns, OriginalColumns),
        case has_rows(UpdatedColumns) of
            false ->
                skip;
            true ->
                %% Merge types from column definitions into data
                TypedColumns = merge_column_types(UpdatedColumns, OriginalColumns),
                maybe
                    ok ?= encode_and_send_block(State, TypedColumns),
                    case
                        check_server_response(
                            State#connection_state.socket,
                            State#connection_state.parser_state
                        )
                    of
                        {ok, NewParserState} ->
                            {ok, State#connection_state{parser_state = NewParserState}};
                        {exception, ExceptionInfo, _} ->
                            {error, {server_exception, ExceptionInfo}};
                        {error, Reason} ->
                            {error, Reason}
                    end
                end
        end
    end.

%% @doc Check remaining time for streaming insert.
%% Returns ok if within timeout, {error, {timeout_error, streaming_insert}} if exceeded.
-spec check_timeout(non_neg_integer(), timeout()) ->
    ok | {error, {timeout_error, streaming_insert}}.
check_timeout(_StartTime, infinity) ->
    ok;
check_timeout(StartTime, Timeout) ->
    clickhouse_erl_streaming_helpers:check_timeout(StartTime, Timeout).

%% @doc Non-blocking check for server exceptions during streaming.
%% Uses selective receive with timeout 0 to check for incoming TCP data.
%% Returns {ok, ParserState} if no data, {exception, ExceptionInfo, ParserState} if exception,
%% {error, Reason} if parsing error.
-spec check_server_response(gen_tcp:socket(), map()) ->
    {ok, map()} | {exception, map(), map()} | {error, term()}.
check_server_response(Socket, ParserState) ->
    %% Use passive recv with timeout 0 for non-blocking check.
    %% This avoids leaving the socket in {active, once} mode which would
    %% cause TCP data to arrive as handle_info messages during the streaming loop.
    case gen_tcp:recv(Socket, 0, 0) of
        {ok, Data} ->
            case clickhouse_erl_parser:parse(Data, ParserState) of
                {ok, Events, NewParserState} ->
                    case has_exception(Events) of
                        {true, ExceptionInfo} ->
                            {exception, ExceptionInfo, NewParserState};
                        false ->
                            {ok, NewParserState}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, timeout} ->
            %% No data available - normal case during streaming
            {ok, ParserState};
        {error, _Reason} ->
            %% Socket error - return current state, will be caught on next send
            {ok, ParserState}
    end.

%% @doc Check if events contain a server exception.
%% Returns {true, ExceptionInfo} if found, false otherwise.
-spec has_exception(list()) -> {true, map()} | false.
has_exception(Events) when is_list(Events) ->
    has_exception_loop(Events).

has_exception_loop([]) ->
    false;
has_exception_loop([{start, server_exception} | Rest]) ->
    %% Collect exception info from subsequent events
    {true, collect_exception_info_for_streaming(Rest, #{})};
has_exception_loop([_ | Rest]) ->
    has_exception_loop(Rest).

%% @doc Collect exception info from events for streaming insert.
-spec collect_exception_info_for_streaming(list(), map()) -> map().
collect_exception_info_for_streaming([], Acc) ->
    Acc;
collect_exception_info_for_streaming([{'end', server_exception} | _], Acc) ->
    Acc;
collect_exception_info_for_streaming([{data, field, Value} | Rest], Acc) ->
    collect_exception_info_for_streaming(Rest, Acc#{field => Value});
collect_exception_info_for_streaming([{data, message, Value} | Rest], Acc) ->
    collect_exception_info_for_streaming(Rest, Acc#{message => Value});
collect_exception_info_for_streaming([{data, code, Value} | Rest], Acc) ->
    collect_exception_info_for_streaming(Rest, Acc#{code => Value});
collect_exception_info_for_streaming([_ | Rest], Acc) ->
    collect_exception_info_for_streaming(Rest, Acc).

%% @doc Increment stats for a data block.
%% Adds rows to rows_inserted and 1 to blocks_sent.
-spec increment_stats(Stats, ColumnData) -> NewStats when
    Stats :: #{
        rows_inserted := non_neg_integer(),
        blocks_sent := non_neg_integer(),
        start_time := integer(),
        timeout := timeout()
    },
    ColumnData :: [map()],
    NewStats :: #{
        rows_inserted := non_neg_integer(),
        blocks_sent := non_neg_integer(),
        start_time := integer(),
        timeout := timeout()
    }.
increment_stats(Stats, ColumnData) ->
    clickhouse_erl_streaming_helpers:increment_stats(Stats, ColumnData).

%% @doc Initialize accumulator state for event processing.
%% Always populates `on_data_callback' and `user_acc' fields.
%% When the user provides an `on_data' callback, uses that callback and
%% the user's `initial_accumulator'. Otherwise, uses the default callback
%% that replicates batch accumulation behavior.
-spec init_acc_state(ActiveQueryState :: map()) -> map().
init_acc_state(ActiveQueryState) ->
    {Callback, UserAcc} =
        case maps:get(on_data, ActiveQueryState, undefined) of
            undefined ->
                {fun default_on_data_callback/2, #{
                    column_order => [], column_meta => #{}, column_values => #{}
                }};
            UserCallback when is_function(UserCallback) ->
                {UserCallback, maps:get(accumulator, ActiveQueryState, undefined)}
        end,
    OnLogCallback = maps:get(on_log, ActiveQueryState, fun default_on_log_callback/1),
    #{
        current_column => undefined,
        current_column_name => undefined,
        current_column_type => undefined,
        current_block_type => undefined,
        exception_info => undefined,
        rows_written => 0,
        on_data_callback => Callback,
        user_acc => UserAcc,
        %% Log accumulator fields for server_log block processing
        log_columns => #{},
        log_column_order => [],
        log_current_column => undefined,
        on_log_callback => OnLogCallback
    }.

%% @doc Assemble log entries from column-oriented data into row-oriented maps.
%% Transposes #{col => [vals]} into a list of maps where each map represents one row.
-spec assemble_log_entries(ColumnOrder :: [binary()], Columns :: map()) -> [map()].
assemble_log_entries([], _Columns) ->
    [];
assemble_log_entries(_ColumnOrder, Columns) when map_size(Columns) =:= 0 ->
    [];
assemble_log_entries(ColumnOrder, Columns) ->
    %% Determine number of rows from the first column's value list
    FirstCol = hd(ColumnOrder),
    NumRows = length(maps:get(FirstCol, Columns, [])),
    lists:map(
        fun(RowIdx) ->
            lists:foldl(
                fun(ColName, RowMap) ->
                    Values = maps:get(ColName, Columns, []),
                    RowMap#{ColName => lists:nth(RowIdx, Values)}
                end,
                #{},
                ColumnOrder
            )
        end,
        lists:seq(1, NumRows)
    ).

%% @doc Dispatch assembled log entries to the on_log callback.
%% Invokes invoke_optional_callback/2 for each entry. Errors in individual
%% callbacks do not prevent subsequent entries from being dispatched.
-spec dispatch_log_entries(Callback :: function(), Entries :: [map()]) -> ok.
dispatch_log_entries(_Callback, []) ->
    ok;
dispatch_log_entries(Callback, Entries) ->
    lists:foreach(
        fun(Entry) ->
            invoke_optional_callback(Callback, Entry)
        end,
        Entries
    ).

%% @doc Build query result from accumulated data.
%% Always reads from user_acc — the default callback or user callback
%% has already finalized the accumulator via the 'end' event.
-spec build_query_result(map()) -> map().
build_query_result(#{user_acc := UserAcc}) ->
    #{data => UserAcc}.
