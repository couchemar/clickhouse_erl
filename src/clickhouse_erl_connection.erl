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
    % Exported for testing
    parse_packet_stream/2,
    parse_packet_data/3,
    is_truncated_data_error/1,
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
    validate_and_normalize_compression_opts/1
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

%% Connection state record
-record(connection_state, {
    socket :: gen_tcp:socket() | undefined,
    host :: string() | inet:ip_address(),
    port :: inet:port_number(),
    options :: connection_options(),
    state :: connecting | ready | error,
    server_info :: connection_info() | undefined,
    error_reason :: connection_error() | undefined,
    active_queries :: #{reference() => {pid(), term()}},
    active_query_state :: active_query_state() | undefined,
    negotiated_version :: non_neg_integer() | undefined,
    buffer = <<>> :: binary(),
    compression_opts :: clickhouse_erl_compression:compression_opts() | undefined
}).

-type active_query_state() :: #{
    caller := {pid(), term()},
    handler_state := clickhouse_erl_response_handler:handler_state(),
    query_id := binary(),
    timeout := timeout(),
    timer_ref := reference() | undefined,
    cancelled := boolean(),
    replied := boolean(),
    is_insert => boolean(),
    rows_to_insert => non_neg_integer(),
    %% Streaming callbacks
    on_data => function() | undefined,
    accumulator => term(),
    on_progress => function() | undefined,
    on_profile => function() | undefined,
    on_profile_events => function() | undefined,
    %% Compression options from connection state
    compression_opts => clickhouse_erl_compression:compression_opts() | undefined
}.

-type state() :: #connection_state{}.

%% Export types for other modules
-export_type([
    connection_options/0,
    connection_info/0,
    connection_error/0
]).

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
                        buffer = <<>>,
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
handle_info({tcp, Socket, Data}, State) ->
    ?LOG_INFO("TCP data received: ~p bytes", [byte_size(Data)]),
    ?LOG_DEBUG("Received data: ~p", [Data]),
    ?LOG_DEBUG("Active query state: ~p~n", [
        State#connection_state.active_query_state =/= undefined
    ]),

    %% Prepend any buffered data to incoming data
    Buffer = State#connection_state.buffer,
    FullData =
        case Buffer of
            <<>> ->
                ?LOG_DEBUG("No buffer, using incoming data only (~p bytes)~n", [byte_size(Data)]),
                Data;
            _ ->
                ?LOG_DEBUG("Buffer prepend: ~p buffered bytes + ~p new bytes = ~p total bytes~n", [
                    byte_size(Buffer), byte_size(Data), byte_size(Buffer) + byte_size(Data)
                ]),
                <<Buffer/binary, Data/binary>>
        end,

    %% Parse packet stream with combined data
    case parse_packet_stream(FullData, State#connection_state{buffer = <<>>}) of
        {ok, NewState, <<>>} ->
            %% All packets parsed successfully, no remaining data
            ?LOG_DEBUG("All packets handled successfully, no remaining data~n", []),
            %% Reactivate socket if query is still active
            case NewState#connection_state.active_query_state of
                undefined ->
                    %% Query completed, no need to reactivate
                    ?LOG_DEBUG("Query completed, not reactivating socket~n", []),
                    {noreply, NewState};
                _ ->
                    %% Query still active, reactivate socket for next packet
                    ?LOG_DEBUG("Query still active, reactivating socket~n", []),
                    case inet:setopts(Socket, [{active, once}]) of
                        ok ->
                            ?LOG_DEBUG("Socket reactivated successfully~n", []),
                            {noreply, NewState};
                        {error, SocketError} ->
                            ?LOG_ERROR("Failed to reactivate socket: ~p~n", [SocketError]),
                            ErrorState = NewState#connection_state{
                                state = error,
                                error_reason =
                                    {network_error, {socket_reactivation_failed, SocketError}}
                            },
                            {noreply, ErrorState}
                    end
            end;
        {ok, NewState, Rest} when byte_size(Rest) > 0 ->
            %% Packets parsed but there's remaining data (shouldn't happen normally)
            ?LOG_WARNING("Unexpected remaining data after parsing: ~p bytes~n", [byte_size(Rest)]),
            %% Buffer the remaining data and reactivate
            BufferedState = NewState#connection_state{buffer = Rest},
            case BufferedState#connection_state.active_query_state of
                undefined ->
                    {noreply, BufferedState};
                _ ->
                    case inet:setopts(Socket, [{active, once}]) of
                        ok ->
                            {noreply, BufferedState};
                        {error, SocketError} ->
                            ErrorState = BufferedState#connection_state{
                                state = error,
                                error_reason =
                                    {network_error, {socket_reactivation_failed, SocketError}}
                            },
                            {noreply, ErrorState}
                    end
            end;
        {incomplete, UnparsedData, PartialState} ->
            %% Incomplete packet, buffer and wait for more data
            ?LOG_DEBUG(
                "Incomplete packet detected: buffering ~p bytes, waiting for more data~n",
                [byte_size(UnparsedData)]
            ),
            BufferedState = PartialState#connection_state{buffer = UnparsedData},
            %% Reactivate socket to receive more data
            case inet:setopts(Socket, [{active, once}]) of
                ok ->
                    ?LOG_DEBUG("Socket reactivated, waiting for more data~n", []),
                    {noreply, BufferedState};
                {error, SocketError} ->
                    ?LOG_ERROR("Failed to reactivate socket: ~p~n", [SocketError]),
                    ErrorState = BufferedState#connection_state{
                        state = error,
                        error_reason =
                            {network_error, {socket_reactivation_failed, SocketError}},
                        % Clear buffer on error
                        buffer = <<>>
                    },
                    {noreply, ErrorState}
            end;
        {error, Reason} ->
            %% Protocol error, fail query and clear buffer
            ?LOG_ERROR("Error handling incoming packet: ~p~n", [Reason]),

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
                % Clear buffer on error
                buffer = <<>>,
                active_query_state = undefined
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
    CallbackType :: on_data | on_progress | on_profile | on_profile_events,
    Callback :: function() | undefined | term(),
    Reason ::
        {invalid_callback_arity, Expected :: non_neg_integer(), Actual :: non_neg_integer()}
        | {invalid_callback_type, term()}.
validate_callback(_CallbackType, undefined) ->
    %% undefined is valid (optional callback)
    ok;
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
            on_profile_events -> 1
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
    CallbackTypes = [on_data, on_progress, on_profile, on_profile_events],

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
    %% Get callback from PreparedRequest (undefined if not present)
    Callback = maps:get(CallbackType, PreparedRequest, undefined),

    %% Validate this callback
    case validate_callback(CallbackType, Callback) of
        ok ->
            %% Continue with remaining callbacks
            validate_callbacks(Rest, PreparedRequest);
        {error, Reason} ->
            %% Validation failed, return error
            {error, Reason}
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
    HandlerState,
    QueryId,
    Timeout,
    TimerRef,
    InitialAccumulator,
    PreparedRequest,
    CompressionOpts
) -> ActiveQueryState when
    From :: {pid(), term()},
    HandlerState :: term(),
    QueryId :: binary(),
    Timeout :: timeout(),
    TimerRef :: reference() | undefined,
    InitialAccumulator :: term(),
    PreparedRequest :: map(),
    CompressionOpts :: clickhouse_erl_compression:compression_opts() | undefined,
    ActiveQueryState :: map().
build_active_query_state(
    From,
    HandlerState,
    QueryId,
    Timeout,
    TimerRef,
    InitialAccumulator,
    PreparedRequest,
    CompressionOpts
) ->
    OnData = maps:get(on_data, PreparedRequest, get_default_on_data_callback()),
    OnProgress = maps:get(on_progress, PreparedRequest, fun(_) -> ok end),
    OnProfile = maps:get(on_profile, PreparedRequest, fun(_) -> ok end),
    OnProfileEvents = maps:get(on_profile_events, PreparedRequest, fun(_) -> ok end),
    #{
        caller => From,
        handler_state => HandlerState,
        query_id => QueryId,
        timeout => Timeout,
        timer_ref => TimerRef,
        cancelled => false,
        replied => false,
        %% Streaming callbacks (always set, never undefined)
        on_data => OnData,
        accumulator => InitialAccumulator,
        on_progress => OnProgress,
        on_profile => OnProfile,
        on_profile_events => OnProfileEvents,
        %% Compression options from connection state
        compression_opts => CompressionOpts
    }.

%% @doc Create ActiveQueryState with proper InitialAccumulator handling
%% This helper encapsulates the common pattern of determining InitialAccumulator
%% and building ActiveQueryState, used by both query and insert operations.
-spec create_active_query_state(
    From,
    HandlerState,
    QueryId,
    Timeout,
    TimerRef,
    PreparedRequest,
    CompressionOpts
) -> ActiveQueryState when
    From :: {pid(), term()},
    HandlerState :: term(),
    QueryId :: binary(),
    Timeout :: timeout(),
    TimerRef :: reference() | undefined,
    PreparedRequest :: map(),
    CompressionOpts :: clickhouse_erl_compression:compression_opts() | undefined,
    ActiveQueryState :: map().
create_active_query_state(
    From, HandlerState, QueryId, Timeout, TimerRef, PreparedRequest, CompressionOpts
) ->
    %% Determine InitialAccumulator based on query mode
    InitialAccumulator =
        case maps:is_key(on_data, PreparedRequest) of
            false ->
                %% Batch mode - initialize with empty result_accumulator
                #result_accumulator{
                    columns = [],
                    rows = [],
                    total_rows = 0,
                    statistics = #{
                        rows_read => 0,
                        bytes_read => 0,
                        elapsed_time => 0
                    }
                };
            true ->
                %% Streaming mode - use provided initial_accumulator or undefined
                maps:get(initial_accumulator, PreparedRequest, undefined)
        end,
    %% Build and return ActiveQueryState
    build_active_query_state(
        From,
        HandlerState,
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

%% @doc Receive server pong (4) packet
-spec receive_server_pong(Socket) -> ok | {error, Reason} when
    Socket :: gen_tcp:socket(),
    Reason :: connection_error().
receive_server_pong(Socket) ->
    % Set socket to active mode to receive data
    case inet:setopts(Socket, [{active, once}]) of
        ok ->
            % Wait for server pong (4) response with timeout
            receive
                {tcp, Socket, <<4:8>>} ->
                    % Server pong received successfully
                    % Set socket back to passive mode
                    case inet:setopts(Socket, [{active, false}]) of
                        ok -> ok;
                        {error, SocketError} -> {error, {network_error, SocketError}}
                    end;
                {tcp_closed, Socket} ->
                    {error, {network_error, connection_closed_during_ping}};
                {tcp_error, Socket, Reason} ->
                    {error, {network_error, {tcp_error_during_ping, Reason}}}
            after ?HANDSHAKE_TIMEOUT ->
                inet:setopts(Socket, [{active, false}]),
                {error, {timeout_error, ping_receive}}
            end;
        {error, SocketError} ->
            {error, {network_error, {socket_option_error, SocketError}}}
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
        HandlerState = clickhouse_erl_response_handler:create_initial_state(),
        %% Start timeout timer if timeout is not infinity
        TimerRef = create_timeout_timer(Timeout, QueryId),
        %% Build ActiveQueryState using helper function
        ActiveQueryState = create_active_query_state(
            From,
            HandlerState,
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
                    NewActiveQueryState = ActiveQueryState#{
                        cancelled => true,
                        replied => true,
                        timer_ref => undefined
                    },
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

%% @doc Propagate server exception to all active queries
-spec propagate_exception_to_queries(ServerException, State) -> NewState when
    ServerException :: {server_exception, exception_info()},
    State :: state(),
    NewState :: state().
propagate_exception_to_queries(ServerException, State) ->
    ActiveQueries = State#connection_state.active_queries,

    % Reply to all active queries with the server exception
    maps:fold(
        fun(_QueryRef, From, _Acc) ->
            gen_server:reply(From, {error, ServerException})
        end,
        ok,
        ActiveQueries
    ),

    % Clear active queries since they've all been replied to
    State#connection_state{active_queries = #{}}.

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
        ok ?= receive_server_pong(Socket),
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

%% @doc Receive and parse Server_Hello response
-spec receive_server_hello(Socket) -> {ok, ServerInfo} | {error, Reason} when
    Socket :: gen_tcp:socket(),
    ServerInfo :: connection_info(),
    Reason :: connection_error().
receive_server_hello(Socket) ->
    % Set socket to active mode to receive data
    case inet:setopts(Socket, [{active, once}]) of
        ok ->
            % Wait for Server_Hello response with timeout
            receive
                {tcp, Socket, Data} ->
                    % Parse the received data and set socket back to passive mode
                    maybe
                        {ok, ServerInfo} ?= parse_server_hello_packet(Data),
                        ?LOG_DEBUG("Handshake successful. ServerInfo: ~p~n", [ServerInfo]),
                        ok ?= inet:setopts(Socket, [{active, false}]),
                        {ok, ServerInfo}
                    else
                        {error, Reason} ->
                            inet:setopts(Socket, [{active, false}]),
                            {error, Reason}
                    end;
                {tcp_closed, Socket} ->
                    {error, {network_error, connection_closed_during_handshake}};
                {tcp_error, Socket, Reason} ->
                    {error, {network_error, {tcp_error_during_handshake, Reason}}}
            after ?HANDSHAKE_TIMEOUT ->
                inet:setopts(Socket, [{active, false}]),
                {error, {timeout_error, handshake_receive}}
            end;
        {error, SocketError} ->
            {error, {network_error, {socket_option_error, SocketError}}}
    end.

%% @doc Parse Server_Hello response data
-spec parse_server_hello_packet(Data) -> {ok, ServerInfo} | {error, Reason} when
    Data :: binary(),
    ServerInfo :: connection_info(),
    Reason :: connection_error().
parse_server_hello_packet(<<PacketType:8, MessageData/binary>>) ->
    % Log the raw response data for debugging
    ?LOG_DEBUG("Received response packet~n", []),
    ?LOG_DEBUG("Raw data: ~p~n", [<<PacketType:8, MessageData/binary>>]),
    ?LOG_DEBUG("Packet type: ~p~n", [PacketType]),
    ?LOG_DEBUG("Message data length: ~p~n", [byte_size(MessageData)]),

    case PacketType of
        ?SERVER_HELLO ->
            ?LOG_DEBUG("Processing Server_Hello packet~n"),
            ?LOG_DEBUG("First 20 bytes of message data: ~p~n", [
                binary:part(MessageData, 0, min(20, byte_size(MessageData)))
            ]),

            case clickhouse_erl_protocol:decode_server_hello(MessageData, ?PROTOCOL_VERSION) of
                {ok, ServerHelloInfo} ->
                    % Convert to connection_info format
                    ServerInfo = #{
                        server_name => maps:get(name, ServerHelloInfo),
                        server_version => {
                            maps:get(version_major, ServerHelloInfo),
                            maps:get(version_minor, ServerHelloInfo),
                            maps:get(version_patch, ServerHelloInfo, 0)
                        },
                        server_revision => maps:get(revision, ServerHelloInfo),
                        server_timezone => maps:get(timezone, ServerHelloInfo, <<"UTC">>),
                        server_display_name => maps:get(display_name, ServerHelloInfo, <<>>)
                    },
                    {ok, ServerInfo};
                {error, Reason} ->
                    {error, Reason}
            end;
        ?SERVER_EXCEPTION ->
            ?LOG_DEBUG("Processing Exception packet during handshake~n"),
            ?LOG_DEBUG("First 20 bytes of exception data: ~p~n", [
                binary:part(MessageData, 0, min(20, byte_size(MessageData)))
            ]),

            case clickhouse_erl_protocol:decode_exception_packet(MessageData) of
                {ok, ExceptionInfo, _Rest} ->
                    % Exception during handshake - return as server exception error
                    ?LOG_DEBUG("Exception parsed successfully: ~p~n", [ExceptionInfo]),
                    {error, {server_exception, ExceptionInfo}};
                {error, ParseError} ->
                    % Failed to parse exception packet
                    ?LOG_DEBUG("Failed to parse exception packet: ~p~n", [ParseError]),
                    {error, ParseError}
            end;
        _ ->
            ?LOG_DEBUG("Unknown packet type: ~p~n", [PacketType]),
            {error, {protocol_error, io_lib:format("Unexpected packet type: ~p", [PacketType])}}
    end;
parse_server_hello_packet(Data) ->
    % Log the raw response data for debugging when it doesn't match expected format
    ?LOG_DEBUG("Invalid response format~n"),
    ?LOG_DEBUG("Raw data: ~p~n", [Data]),
    ?LOG_DEBUG("Data length: ~p~n", [byte_size(Data)]),
    {error, {protocol_error, "Invalid response format"}}.

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
                Major when Major >= 20 andalso Major =< 25 ->
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

packet_type_name(PacketType) ->
    case PacketType of
        0 -> "SERVER_HELLO";
        1 -> "SERVER_DATA";
        2 -> "SERVER_EXCEPTION";
        3 -> "SERVER_PROGRESS";
        4 -> "SERVER_PONG";
        5 -> "SERVER_END_OF_STREAM";
        6 -> "SERVER_PROFILE";
        7 -> "SERVER_TOTALS";
        8 -> "SERVER_EXTREMES";
        9 -> "SERVER_TABLES_STATUS";
        10 -> "SERVER_LOG";
        11 -> "SERVER_TABLE_COLUMNS";
        12 -> "SERVER_PART_UUIDS";
        13 -> "SERVER_READ_TASK_REQUEST";
        14 -> "SERVER_PROFILE_EVENTS";
        _ -> "UNKNOWN"
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
        %% Step 4: Encode data block
        Input = maps:get(input, PreparedRequest),
        NumColumns = maps:get(num_columns, PreparedRequest),
        NumRows = maps:get(num_rows, PreparedRequest),
        DataBlock = #{columns => NumColumns, rows => NumRows, column_data => Input},
        {ok, EncodedDataBlock} ?=
            clickhouse_erl_protocol_data_block:encode_data_block(
                DataBlock, NegotiatedVersion
            ),
        %% CRITICAL: encode_data_block returns
        %% [TempTableName, BlockInfo, NumColumns, NumRows, ColumnData]
        %% We need to extract ONLY the block data
        %% (BlockInfo + NumColumns + NumRows + ColumnData)
        %% and compress that, keeping TempTableName uncompressed.
        %% This matches the pattern in encode_blank_data_block.

        %% Convert to binary to extract temp table name
        FullDataBlockBin = iolist_to_binary(EncodedDataBlock),
        ?LOG_DEBUG("Full data block size: ~p bytes~n", [byte_size(FullDataBlockBin)]),
        %% Decode temp table name to find where block data starts
        {ok, _TempTableName, BlockDataOnly} =
            clickhouse_erl_types_primitive:decode_string(FullDataBlockBin),
        ?LOG_DEBUG("Block data only size (after removing temp table name): ~p bytes~n", [
            byte_size(BlockDataOnly)
        ]),
        %% Apply compression only to block data (BlockInfo + columns + rows)
        CompressedBlockData =
            case
                clickhouse_erl_compression:compress_data_block(
                    BlockDataOnly, State#connection_state.compression_opts
                )
            of
                {ok, Compressed} ->
                    ?LOG_DEBUG("Compressed block data: ~p -> ~p bytes~n", [
                        byte_size(BlockDataOnly), byte_size(Compressed)
                    ]),
                    Compressed;
                {error, CompressReason} ->
                    ?LOG_ERROR("Failed to compress data block", #{reason => CompressReason}),
                    %% Fall back to uncompressed on error
                    BlockDataOnly
            end,
        %% Step 5: Send data block with uncompressed temp table name + compressed block data
        TempTableName = clickhouse_erl_types_primitive:encode_string(""),
        DataPacket = <<?CLIENT_DATA:8, TempTableName/binary, CompressedBlockData/binary>>,
        ?LOG_DEBUG(
            "Sending data packet: type=~p, temp_table_name_size=~p, compressed_block_size=~p~n",
            [?CLIENT_DATA, byte_size(TempTableName), byte_size(CompressedBlockData)]
        ),
        ok ?= gen_tcp:send(Socket, DataPacket),
        ?LOG_DEBUG("Data block sent successfully (~p rows)~n", [NumRows]),
        %% Step 6: Send final blank block
        %% CRITICAL: Blank block must be compressed if compression is enabled
        BlankBlockAfterData = encode_blank_data_block(State#connection_state.compression_opts),
        ok ?= gen_tcp:send(Socket, BlankBlockAfterData),
        ?LOG_DEBUG("Final blank data block sent successfully~n", []),
        %% Step 7: Initialize response handler state
        HandlerState0 =
            clickhouse_erl_response_handler:create_initial_state(
                NegotiatedVersion, insert
            ),
        %% Add rows_to_insert to handler state for INSERT result reporting
        HandlerState = HandlerState0#{rows_to_insert => NumRows},
        %% Step 8: Start timeout timer
        TimerRef = create_timeout_timer(Timeout, QueryId),
        %% Step 9: Update connection state
        %% Build ActiveQueryState using helper function and add INSERT-specific fields
        ActiveQueryState0 = create_active_query_state(
            From,
            HandlerState,
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

%% @doc Parse packet stream, handling multiple packets and incomplete data
%% This function implements the core TCP stream parsing logic for ClickHouse packets.
%% It handles three scenarios:
%% 1. Empty data - returns {ok, State, <<>>}
%% 2. Complete packet(s) - parses and continues with remainder
%% 3. Incomplete packet - returns {incomplete, UnparsedData, State}
%%
%% Requirements: REQ-1.1, REQ-1.2, REQ-1.3, REQ-2.2
-spec parse_packet_stream(Data, State) ->
    {ok, NewState, Rest}
    | {incomplete, UnparsedData, PartialState}
    | {error, Reason}
when
    Data :: binary(),
    State :: state(),
    NewState :: state(),
    Rest :: binary(),
    UnparsedData :: binary(),
    PartialState :: state(),
    Reason :: connection_error().

%% Handle empty data - no more packets to parse
parse_packet_stream(<<>>, State) ->
    ActiveQueryDefined = State#connection_state.active_query_state =/= undefined,
    ?LOG_DEBUG("parse_packet_stream: empty data, no more packets to parse, active_query=~p~n", [
        ActiveQueryDefined
    ]),
    {ok, State, <<>>};
%% Handle complete packet - have packet type byte
parse_packet_stream(<<PacketType:8, Rest/binary>>, State) ->
    ?LOG_DEBUG("parse_packet_stream: parsing packet type ~p [~s], ~p bytes remaining~n", [
        PacketType, packet_type_name(PacketType), byte_size(Rest)
    ]),

    %% Try to parse the packet data
    case parse_packet_data(PacketType, Rest, State) of
        {ok, NewState, Remainder} ->
            %% Packet parsed successfully, continue with remainder (tail-recursive)
            ActiveQueryDefined = NewState#connection_state.active_query_state =/= undefined,
            ?LOG_DEBUG(
                "parse_packet_stream: packet ~p [~s] parsed successfully, "
                "~p bytes remaining, active_query=~p~n",
                [
                    PacketType,
                    packet_type_name(PacketType),
                    byte_size(Remainder),
                    ActiveQueryDefined
                ]
            ),
            parse_packet_stream(Remainder, NewState);
        {incomplete, _Reason} ->
            %% Not enough data for this packet, buffer from packet type
            BufferSize = byte_size(<<PacketType:8, Rest/binary>>),
            ?LOG_DEBUG(
                "parse_packet_stream: incomplete packet, buffering ~p bytes~n",
                [BufferSize]
            ),
            {incomplete, <<PacketType:8, Rest/binary>>, State};
        {error, Reason} ->
            ?LOG_DEBUG("parse_packet_stream: error parsing packet: ~p~n", [Reason]),
            {error, Reason}
    end;
%% Handle incomplete header - less than 1 byte available
parse_packet_stream(Data, State) when byte_size(Data) > 0 ->
    ?LOG_DEBUG(
        "parse_packet_stream: incomplete header, buffering ~p bytes (cannot read packet type)~n",
        [byte_size(Data)]
    ),
    %% Can't read packet type yet, buffer all data
    {incomplete, Data, State}.

%% @doc Parse packet data based on packet type
%% Dispatches to specific packet handlers and detects incomplete packets
%%
%% Requirements: REQ-2.1, REQ-4.1, REQ-4.2
-spec parse_packet_data(PacketType, Data, State) ->
    {ok, NewState, Rest} | {incomplete, Reason} | {error, Reason}
when
    PacketType :: integer(),
    Data :: binary(),
    State :: state(),
    NewState :: state(),
    Rest :: binary(),
    Reason :: term().
parse_packet_data(PacketType, Data, State) ->
    ?LOG_DEBUG("parse_packet_data: dispatching packet type ~p [~s], ~p bytes available~n", [
        PacketType, packet_type_name(PacketType), byte_size(Data)
    ]),

    %% Check if we have an active query
    case State#connection_state.active_query_state of
        undefined ->
            %% No active query - only handle exceptions
            case PacketType of
                ?SERVER_EXCEPTION ->
                    parse_exception_packet_data(Data, State);
                _ ->
                    ?LOG_WARNING("Received packet type ~p with no active query~n", [
                        PacketType
                    ]),
                    {error, {protocol_error, "Received packet with no active query"}}
            end;
        ActiveQueryState ->
            %% Have active query - delegate to query packet handler
            parse_query_packet_data(PacketType, Data, ActiveQueryState, State)
    end.

%% @doc Parse exception packet data
-spec parse_exception_packet_data(Data, State) ->
    {ok, NewState, Rest} | {incomplete, Reason} | {error, Reason}
when
    Data :: binary(),
    State :: state(),
    NewState :: state(),
    Rest :: binary(),
    Reason :: term().
parse_exception_packet_data(Data, State) ->
    case clickhouse_erl_protocol:decode_exception_packet(Data) of
        {ok, ExceptionInfo, Rest} ->
            %% Exception parsed successfully
            ServerException = {server_exception, ExceptionInfo},
            NewState = propagate_exception_to_queries(ServerException, State),
            {ok, NewState, Rest};
        {error, Reason} ->
            %% Protocol error during exception parsing
            {error, Reason}
    end.

%% @doc Parse query packet data (delegates to response handler)
-spec parse_query_packet_data(PacketType, Data, ActiveQueryState, State) ->
    {ok, NewState, Rest} | {incomplete, Reason} | {error, Reason}
when
    PacketType :: integer(),
    Data :: binary(),
    ActiveQueryState :: active_query_state(),
    State :: state(),
    NewState :: state(),
    Rest :: binary(),
    Reason :: term().
parse_query_packet_data(PacketType, Data, ActiveQueryState, State) ->
    IsCancelled = maps:get(cancelled, ActiveQueryState, false),
    HandlerResult = route_packet_to_handler(PacketType, Data, ActiveQueryState, State),
    process_handler_result(HandlerResult, IsCancelled, ActiveQueryState, State).

%% @doc Route packet to appropriate handler based on packet type
-spec route_packet_to_handler(PacketType, Data, ActiveQueryState, State) -> HandlerResult when
    PacketType :: integer(),
    Data :: binary(),
    ActiveQueryState :: active_query_state(),
    State :: state(),
    HandlerResult ::
        {data_updated, NewActiveQueryState :: map(), Rest :: binary()}
        | {query_complete, Result :: term(), Rest :: binary()}
        | {handler_updated, NewHandlerState :: term(), Rest :: binary()}
        | {error, Reason :: term(), Rest :: binary()}
        | {incomplete, Reason :: term()}.
route_packet_to_handler(?SERVER_DATA, Data, ActiveQueryState, _State) ->
    handle_data_packet(Data, ActiveQueryState);
route_packet_to_handler(?SERVER_END_OF_STREAM, Data, ActiveQueryState, _State) ->
    handle_end_of_stream_packet(Data, ActiveQueryState);
route_packet_to_handler(?SERVER_PROGRESS, Data, ActiveQueryState, _State) ->
    handle_optional_callback_packet(
        Data,
        ActiveQueryState,
        on_progress,
        fun clickhouse_erl_response_handler:handle_progress_packet_with_state/3
    );
route_packet_to_handler(?SERVER_PROFILE, Data, ActiveQueryState, _State) ->
    handle_optional_callback_packet(
        Data,
        ActiveQueryState,
        on_profile,
        fun clickhouse_erl_response_handler:handle_profile_packet_with_state/3
    );
route_packet_to_handler(?SERVER_PROFILE_EVENTS, Data, ActiveQueryState, _State) ->
    handle_optional_callback_packet(
        Data,
        ActiveQueryState,
        on_profile_events,
        fun clickhouse_erl_response_handler:handle_profile_events_packet_with_state/3
    );
route_packet_to_handler(PacketType, Data, ActiveQueryState, _State) ->
    handle_generic_packet(PacketType, Data, ActiveQueryState).

%% @doc Handle SERVER_DATA packet with callback-based processing
-spec handle_data_packet(Data, ActiveQueryState) -> HandlerResult when
    Data :: binary(),
    ActiveQueryState :: active_query_state(),
    HandlerResult ::
        {data_updated, NewActiveQueryState :: map(), Rest :: binary()}
        | {error, Reason :: term(), Rest :: binary()}
        | {incomplete, Reason :: term()}.
handle_data_packet(Data, ActiveQueryState) ->
    #{handler_state := HandlerState} = ActiveQueryState,
    CompressionOpts = maps:get(compression_opts, ActiveQueryState, undefined),
    CallbackInfo = #{
        on_data => maps:get(on_data, ActiveQueryState),
        accumulator => maps:get(accumulator, ActiveQueryState),
        compression_opts => CompressionOpts
    },

    case
        clickhouse_erl_response_handler:handle_data_packet_with_callback(
            Data, HandlerState, CallbackInfo
        )
    of
        {ok, NewHandlerState, Rest, NewCallbackInfo} ->
            ?LOG_DEBUG(
                "handle_data_packet: DATA packet parsed successfully, ~p bytes remaining~n",
                [byte_size(Rest)]
            ),
            NewActiveQueryState = ActiveQueryState#{
                handler_state := NewHandlerState,
                accumulator := maps:get(accumulator, NewCallbackInfo)
            },
            {data_updated, NewActiveQueryState, Rest};
        {error, Reason, Rest} ->
            ?LOG_DEBUG("handle_data_packet: error: ~p~n", [Reason]),
            classify_error_result(Reason, Rest)
    end.

%% @doc Handle SERVER_END_OF_STREAM packet (terminal packet)
-spec handle_end_of_stream_packet(Data, ActiveQueryState) -> HandlerResult when
    Data :: binary(),
    ActiveQueryState :: active_query_state(),
    HandlerResult :: {query_complete, Result :: term(), Rest :: binary()}.
handle_end_of_stream_packet(Data, ActiveQueryState) ->
    #{handler_state := HandlerState} = ActiveQueryState,
    CallbackInfo =
        case maps:is_key(on_data, ActiveQueryState) of
            true ->
                #{
                    on_data => maps:get(on_data, ActiveQueryState),
                    accumulator => maps:get(accumulator, ActiveQueryState)
                };
            false ->
                undefined
        end,

    {complete, Result, Rest} =
        clickhouse_erl_response_handler:handle_end_of_stream_packet_with_state(
            Data, HandlerState, CallbackInfo
        ),
    ?LOG_DEBUG("handle_end_of_stream_packet: query completed with result~n", []),
    {query_complete, Result, Rest}.

%% @doc Handle packets with optional callbacks (PROGRESS, PROFILE, PROFILE_EVENTS)
-spec handle_optional_callback_packet(Data, ActiveQueryState, CallbackKey, HandlerFun) ->
    HandlerResult
when
    Data :: binary(),
    ActiveQueryState :: active_query_state(),
    CallbackKey :: atom(),
    HandlerFun :: fun((binary(), term(), map()) -> {ok, term(), binary()} | {error, term()}),
    HandlerResult ::
        {handler_updated, NewHandlerState :: term(), Rest :: binary()}
        | {error, Reason :: term(), Rest :: binary()}
        | {incomplete, Reason :: term()}.
handle_optional_callback_packet(Data, ActiveQueryState, CallbackKey, HandlerFun) ->
    #{handler_state := HandlerState} = ActiveQueryState,
    CallbackInfo = #{CallbackKey => maps:get(CallbackKey, ActiveQueryState, fun(_) -> ok end)},

    case HandlerFun(Data, HandlerState, CallbackInfo) of
        {ok, NewHandlerState, Rest} ->
            ?LOG_DEBUG(
                "handle_optional_callback_packet: ~p packet parsed successfully, "
                "~p bytes remaining~n",
                [CallbackKey, byte_size(Rest)]
            ),
            {handler_updated, NewHandlerState, Rest};
        {error, Reason, Rest} ->
            classify_error_result(Reason, Rest)
    end.

%% @doc Classify error result - handle truncated data errors
%% Returns {incomplete, Reason} for truncated data, {error, Reason, Rest} otherwise
-spec classify_error_result(Reason, Rest) -> {incomplete, Reason} | {error, Reason, Rest} when
    Reason :: term(),
    Rest :: binary().
classify_error_result(Reason, Rest) ->
    case is_truncated_data_error(Reason) of
        true -> {incomplete, Reason};
        false -> {error, Reason, Rest}
    end.

%% @doc Handle generic packets (fallback for unknown packet types)
-spec handle_generic_packet(PacketType, Data, ActiveQueryState) -> HandlerResult when
    PacketType :: integer(),
    Data :: binary(),
    ActiveQueryState :: active_query_state(),
    HandlerResult ::
        {handler_updated, NewHandlerState :: term(), Rest :: binary()}
        | {error, Reason :: term(), Rest :: binary()}
        | {incomplete, Reason :: term()}.
handle_generic_packet(PacketType, Data, ActiveQueryState) ->
    #{handler_state := HandlerState} = ActiveQueryState,
    case clickhouse_erl_response_handler:handle_packet(PacketType, Data, HandlerState) of
        {ok, NewHandlerState, Rest} ->
            ?LOG_DEBUG(
                "handle_generic_packet: packet type ~p parsed successfully, ~p bytes remaining~n",
                [PacketType, byte_size(Rest)]
            ),
            {handler_updated, NewHandlerState, Rest};
        {error, Reason, Rest} when is_tuple(Reason) ->
            classify_error_result(Reason, Rest);
        {error, Reason} when is_tuple(Reason) ->
            classify_error_result(Reason, <<>>)
    end.

%% @doc Process handler result and update connection state
-spec process_handler_result(HandlerResult, IsCancelled, ActiveQueryState, State) ->
    {ok, NewState, Rest} | {incomplete, Reason} | {error, Reason}
when
    HandlerResult ::
        {data_updated, NewActiveQueryState :: map(), Rest :: binary()}
        | {query_complete, Result :: term(), Rest :: binary()}
        | {handler_updated, NewHandlerState :: term(), Rest :: binary()}
        | {error, Reason :: term(), Rest :: binary()}
        | {incomplete, Reason :: term()},
    IsCancelled :: boolean(),
    ActiveQueryState :: active_query_state(),
    State :: state(),
    NewState :: state(),
    Rest :: binary(),
    Reason :: term().
process_handler_result(
    {data_updated, _NewActiveQueryState, Rest}, true, _ActiveQueryState, State
) ->
    %% Ignore data for cancelled query
    {ok, State, Rest};
process_handler_result(
    {data_updated, NewActiveQueryState, Rest}, false, _ActiveQueryState, State
) ->
    NewState = State#connection_state{active_query_state = NewActiveQueryState},
    {ok, NewState, Rest};
process_handler_result({query_complete, Result, Rest}, _IsCancelled, ActiveQueryState, State) ->
    #{caller := Caller, timer_ref := TimerRef} = ActiveQueryState,
    cancel_timer_and_reply_ok(TimerRef, Caller, ActiveQueryState, Result),
    NewState = State#connection_state{active_query_state = undefined},
    {ok, NewState, Rest};
process_handler_result(
    {handler_updated, NewHandlerState, Rest}, IsCancelled, ActiveQueryState, State
) ->
    update_state_if_not_cancelled(IsCancelled, State, ActiveQueryState, NewHandlerState, Rest);
process_handler_result(
    {error, {callback_failed, _} = Reason, Rest}, _IsCancelled, ActiveQueryState, State
) ->
    #{caller := Caller, timer_ref := TimerRef} = ActiveQueryState,
    ?LOG_DEBUG("process_handler_result: callback failed: ~p~n", [Reason]),
    cancel_timer_and_reply(TimerRef, Caller, ActiveQueryState, Reason),
    NewState = State#connection_state{active_query_state = undefined},
    {ok, NewState, Rest};
process_handler_result(
    {error, {server_exception, _} = Reason, Rest}, _IsCancelled, ActiveQueryState, State
) ->
    #{caller := Caller, timer_ref := TimerRef} = ActiveQueryState,
    ?LOG_DEBUG("process_handler_result: server exception received~n", []),
    cancel_timer_and_reply(TimerRef, Caller, ActiveQueryState, Reason),
    NewState = State#connection_state{active_query_state = undefined},
    {ok, NewState, Rest};
process_handler_result({error, Reason, _Rest}, _IsCancelled, ActiveQueryState, _State) ->
    #{caller := Caller, timer_ref := TimerRef} = ActiveQueryState,
    handle_packet_error(Reason, TimerRef, Caller, ActiveQueryState);
process_handler_result({incomplete, Reason}, _IsCancelled, _ActiveQueryState, _State) ->
    {incomplete, Reason}.

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

%% @doc Cancel timer and reply with success if not already replied
%% Helper function to eliminate code duplication
-spec cancel_timer_and_reply_ok(TimerRef, Caller, ActiveQueryState, Result) -> ok when
    TimerRef :: reference() | undefined,
    Caller :: {pid(), term()},
    ActiveQueryState :: map(),
    Result :: term().
cancel_timer_and_reply_ok(TimerRef, Caller, ActiveQueryState, Result) ->
    case TimerRef of
        undefined -> ok;
        _ -> erlang:cancel_timer(TimerRef)
    end,
    case maps:get(replied, ActiveQueryState, false) of
        false ->
            gen_server:reply(Caller, {ok, Result});
        true ->
            ok
    end.

%% @doc Update state with new handler state if query not cancelled
%% Helper function to reduce nesting level
-spec update_state_if_not_cancelled(IsCancelled, State, ActiveQueryState, NewHandlerState, Rest) ->
    {ok, NewState, Rest}
when
    IsCancelled :: boolean(),
    State :: state(),
    ActiveQueryState :: map(),
    NewHandlerState :: term(),
    Rest :: binary(),
    NewState :: state().
update_state_if_not_cancelled(true, State, _ActiveQueryState, _NewHandlerState, Rest) ->
    %% Ignore data for cancelled query
    {ok, State, Rest};
update_state_if_not_cancelled(false, State, ActiveQueryState, NewHandlerState, Rest) ->
    NewActiveQueryState = ActiveQueryState#{handler_state := NewHandlerState},
    NewState = State#connection_state{active_query_state = NewActiveQueryState},
    {ok, NewState, Rest}.

%% @doc Create timeout timer reference
%% Helper function to eliminate code duplication in timer creation
-spec create_timeout_timer(timeout(), binary()) -> reference() | undefined.
create_timeout_timer(infinity, _QueryId) ->
    undefined;
create_timeout_timer(Timeout, QueryId) ->
    erlang:send_after(Timeout, self(), {query_timeout, QueryId}).

%% @doc Get default on_data callback for batch mode
%% Helper function to eliminate code duplication
-spec get_default_on_data_callback() -> fun((map(), list()) -> list()).
get_default_on_data_callback() ->
    fun(DataBlock, Acc) ->
        clickhouse_erl_response_handler:accumulate_data_block_callback(DataBlock, Acc)
    end.

%% @doc Detect if an error is a truncated_data error (incomplete packet)
%% Requirements: REQ-4.1, REQ-4.2
-spec is_truncated_data_error(Error) -> boolean() when
    Error :: term().
is_truncated_data_error({truncated_data, _}) ->
    true;
is_truncated_data_error({profile_events_decode_failed, {truncated_data, _}}) ->
    true;
is_truncated_data_error({profile_events_decode_error, truncated_data}) ->
    true;
is_truncated_data_error({profile_events_decode_error, {truncated_data, _}}) ->
    true;
is_truncated_data_error({data_block_decode_error, truncated_data}) ->
    true;
is_truncated_data_error({data_block_decode_error, {truncated_data, _}}) ->
    true;
is_truncated_data_error({data_block_decode_error, {decoding_failed, {_, {truncated_data, _}}}}) ->
    true;
is_truncated_data_error({decoding_failed, {_, {truncated_data, _}}}) ->
    true;
is_truncated_data_error({decompression_failed, {truncated_data, _}}) ->
    true;
is_truncated_data_error({decompression_failed, {invalid_compressed_block, too_small}}) ->
    true;
is_truncated_data_error({temp_table_decode_error, {truncated_data, _}}) ->
    true;
is_truncated_data_error({protocol_error, Inner}) ->
    %% Check if the inner error is a truncated_data error (recursive check)
    is_truncated_data_error(Inner);
is_truncated_data_error({exception_parsing_error, Details}) when is_list(Details) ->
    %% Check if the details contain truncated_data information
    DetailsStr = lists:flatten(Details),
    string:find(DetailsStr, "truncated_data") =/= nomatch;
is_truncated_data_error(_) ->
    false.

%% @doc Handle packet parsing errors (truncated data vs protocol errors)
-spec handle_packet_error(term(), term(), term(), map()) ->
    {incomplete, term()} | {error, term()}.
handle_packet_error(Reason, TimerRef, Caller, ActiveQueryState) ->
    case is_truncated_data_error(Reason) of
        true ->
            %% Incomplete packet - need more data
            ?LOG_DEBUG(
                "parse_query_packet_data: incomplete packet detected "
                "(truncated_data), need more data~n",
                []
            ),
            {incomplete, Reason};
        false ->
            %% Real protocol error
            ?LOG_DEBUG("parse_query_packet_data: protocol error: ~p~n", [Reason]),
            cancel_timer_and_reply(
                TimerRef, Caller, ActiveQueryState, {protocol_error, Reason}
            ),
            {error, Reason}
    end.

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
-spec check_connection_ready(State) -> ok | {error, Reason} when
    State :: state(),
    Reason :: connection_error().
check_connection_ready(#connection_state{state = ready}) ->
    ok;
check_connection_ready(#connection_state{state = error, error_reason = ErrorReason}) ->
    {error, ErrorReason};
check_connection_ready(#connection_state{state = connecting}) ->
    {error, {protocol_error, "Connection not ready"}}.

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
