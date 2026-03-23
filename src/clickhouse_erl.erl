%%%-------------------------------------------------------------------
%% @doc ClickHouse Erlang Client Library
%%
%% This module provides the main public API for the ClickHouse Erlang client.
%% It serves as the primary entry point for establishing connections and
%% managing ClickHouse database interactions.
%%
%% == Usage ==
%%
%% ```
%% % Start the application
%% application:start(clickhouse_erl).
%%
%% % Connect to ClickHouse server
%% {ok, Connection} = clickhouse_erl:connect("localhost", 9000).
%%
%% % Connect with custom options
%% Options = #{
%%     database => "mydb",
%%     username => "user",
%%     password => "pass"
%% },
%% {ok, Connection} = clickhouse_erl:connect("localhost", 9000, Options).
%%
%% % Execute query with settings (simple map format - recommended)
%% {ok, Result} = clickhouse_erl:query(Connection, <<"SELECT * FROM table">>, #{
%%     settings => #{
%%         <<"max_threads">> => <<"4">>,
%%         <<"max_memory_usage">> => <<"10000000000">>
%%     }
%% }).
%%
%% % Execute query with settings (keyword list format)
%% {ok, Result} = clickhouse_erl:query(Connection, <<"SELECT * FROM table">>, #{
%%     settings => [
%%         {<<"max_threads">>, <<"4">>},
%%         {<<"max_memory_usage">>, <<"10000000000">>}
%%     ]
%% }).
%%
%% % Execute query with settings (protocol format - advanced)
%% {ok, Result} = clickhouse_erl:query(Connection, <<"SELECT * FROM table">>, #{
%%     settings => [
%%         #{key => <<"max_threads">>, value => <<"4">>,
%%           important => false, custom => false, obsolete => false}
%%     ]
%% }).
%%
%% % Get connection information
%% {ok, Info} = clickhouse_erl:get_connection_info(Connection).
%%
%% % Disconnect
%% ok = clickhouse_erl:disconnect(Connection).
%% '''
%% @end
%%%-------------------------------------------------------------------

-module(clickhouse_erl).

-include_lib("kernel/include/logger.hrl").
-include("clickhouse_erl_protocol.hrl").

%% Public API for connection management
-export([
    connect/2,
    connect/3,
    disconnect/1,
    get_connection_info/1,
    format_error/1,
    query/2,
    query/3,
    insert/3,
    insert/4,
    cancel_query/1,
    cancel_query/2
]).

%% Application management
-export([
    start/0,
    stop/0
]).

%% Public API - suppress xref warnings (called by library consumers)
-ignore_xref([
    connect/2,
    connect/3,
    disconnect/1,
    get_connection_info/1,
    format_error/1,
    query/2,
    query/3,
    insert/3,
    insert/4,
    cancel_query/1,
    cancel_query/2,
    start/0,
    stop/0
]).

%% Re-export types for convenience
-export_type([
    connection_options/0,
    connection_info/0,
    connection_error/0,
    query_options/0
]).

%% Import types from connection module
-type connection_options() :: clickhouse_erl_connection:connection_options().
-type connection_info() :: clickhouse_erl_connection:connection_info().
-type connection_error() :: clickhouse_erl_connection:connection_error().

%% Query options type
-type query_options() :: #{
    timeout => timeout(),
    query_id => binary(),
    settings => settings_input(),
    parameters => [{binary(), binary()}]
}.

%%%===================================================================
%%% Public API
%%%===================================================================

%% @doc Start the ClickHouse client application
-spec start() -> ok | {error, Reason} when
    Reason :: term().
start() ->
    application:start(clickhouse_erl).

%% @doc Stop the ClickHouse client application
-spec stop() -> ok | {error, Reason} when
    Reason :: term().
stop() ->
    application:stop(clickhouse_erl).

%% @doc Connect to ClickHouse server with default options.
%%
%% Establishes a connection to the ClickHouse server using default
%% connection parameters (database: "default", username: "default",
%% password: ""). The default connection timeout is 5 seconds.
%%
%% @param Host The hostname or IP address of the ClickHouse server.
%% @param Port The port number (typically 9000).
%% @returns {ok, Connection} where Connection is the pid of the connection manager,
%%          or {error, Reason} on failure.
-spec connect(Host, Port) -> {ok, Connection} | {error, Reason} when
    Host :: string() | inet:ip_address(),
    Port :: inet:port_number(),
    Connection :: pid(),
    Reason :: connection_error().
connect(Host, Port) ->
    connect(Host, Port, #{}).

%% @doc Connect to ClickHouse server with custom options.
%%
%% Establishes a connection with specified options. The options map can include:
%% <ul>
%%   <li>`database': binary() | string() - Target database (default: "default")</li>
%%   <li>`username': binary() | string() - Auth username (default: "default")</li>
%%   <li>`password': binary() | string() - Auth password (default: "")</li>
%%   <li>`timeout': timeout() - Connection timeout in ms (default: 5000)</li>
%%   <li>`client_name': binary() | string() - Identification for the server</li>
%%   <li>`client_version': {Major, Minor, Patch} - Version reporting</li>
%%   <li>`compression': lz4 | zstd | none | disabled - Compression method (default: disabled)</li>
%%   <li>`compression_level': 0..12 - LZ4HC compression level (only for lz4 method)</li>
%% </ul>
%%
%% Compression options:
%% <ul>
%%   <li>`lz4' - Fast compression with good ratios (recommended)</li>
%%   <li>`lz4' with `compression_level' - LZ4HC with level 0-12 (higher = better compression)</li>
%%   <li>`zstd' - Better compression ratios, slower than LZ4</li>
%%   <li>`none' - Uncompressed with compression protocol wrapper</li>
%%   <li>`disabled' - No compression (default, backward compatible)</li>
%% </ul>
%%
%% Examples:
%% ```
%% % Basic connection without compression
%% {ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{}).
%%
%% % Connection with LZ4 compression
%% {ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{compression => lz4}).
%%
%% % Connection with LZ4HC level 9
%% {ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{
%%     compression => lz4,
%%     compression_level => 9
%% }).
%%
%% % Connection with ZSTD compression
%% {ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{compression => zstd}).
%% '''
%%
%% Compression errors:
%% ```
%% {error, {compression_library_missing, Method}} - Required library not installed
%% {error, {invalid_compression_method, Method}} - Unsupported compression method
%% {error, {invalid_compression_level, Level}} - Level outside range 0-12
%% '''
%%
%% @param Host The hostname or IP address of the ClickHouse server.
%% @param Port The port number (typically 9000).
%% @param Options Connection options map.
%% @returns {ok, Connection} or {error, Reason}.
-spec connect(Host, Port, Options) -> {ok, Connection} | {error, Reason} when
    Host :: string() | inet:ip_address(),
    Port :: inet:port_number(),
    Options :: connection_options(),
    Connection :: pid(),
    Reason :: connection_error().
connect(Host, Port, Options) ->
    % Ensure the application is started
    case application:ensure_started(clickhouse_erl) of
        ok ->
            clickhouse_erl_app:connect(Host, Port, Options);
        {error, {already_started, clickhouse_erl}} ->
            clickhouse_erl_app:connect(Host, Port, Options);
        {error, Reason} ->
            {error, {application_start_failed, Reason}}
    end.

%% @doc Disconnect from ClickHouse server.
%%
%% Gracefully closes the connection and cleans up associated resources.
%% Any active queries on this connection will be interrupted.
%%
%% @param Connection The connection pid returned by connect/2 or connect/3.
%% @returns ok.
-spec disconnect(Connection) -> ok | {error, Reason} when
    Connection :: pid(),
    Reason :: term().
disconnect(Connection) ->
    clickhouse_erl_app:disconnect(Connection).

%% @doc Get connection information.
%%
%% Returns detailed metadata about the current session and server state.
%%
%% @param Connection The connection pid.
%% @returns {ok, Info} where Info contains server_name, version, revision,
%%          timezone, and display_name.
-spec get_connection_info(Connection) -> {ok, Info} | {error, Reason} when
    Connection :: pid(),
    Info :: connection_info(),
    Reason :: connection_error().
get_connection_info(Connection) ->
    clickhouse_erl_app:get_connection_info(Connection).

%% @doc Execute a SQL query on the ClickHouse server.
%%
%% Executes the given SQL string or binary and returns the results.
%% This is suitable for SELECT, DESCRIBE, and other data-fetching queries.
%%
%% @param Connection The connection pid.
%% @param SQL The SQL query as a string or binary.
%% @returns {ok, Result} where Result is a map containing columns metadata,
%%          row data, and statistics.
-spec query(Connection, SQL) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    SQL :: string() | binary(),
    Result :: term(),
    Reason :: connection_error().
query(Connection, SQL) ->
    clickhouse_erl_app:query(Connection, SQL).

%% @doc Execute a SQL query with specific options.
%%
%% Allows providing options like `timeout', `query_id', `parameters', and ClickHouse `settings'.
%%
%% Settings can be provided in three formats:
%% <ul>
%%   <li>Simple map (recommended): `#{<<"max_threads">> => <<"4">>}'</li>
%%   <li>Keyword list: `[{<<"max_threads">>, <<"4">>}]'</li>
%%   <li>Protocol format: `[#{key => <<"max_threads">>, value => <<"4">>}]'</li>
%% </ul>
%%
%% Examples:
%% ```
%% % Query with simple map settings (recommended)
%% {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM table">>, #{
%%     settings => #{
%%         <<"max_threads">> => <<"4">>,
%%         <<"max_memory_usage">> => <<"10000000000">>
%%     }
%% }).
%%
%% % Query with keyword list settings
%% {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM table">>, #{
%%     settings => [
%%         {<<"max_threads">>, <<"4">>},
%%         {<<"max_memory_usage">>, <<"10000000000">>}
%%     ]
%% }).
%%
%% % Query with protocol format settings (advanced)
%% {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM table">>, #{
%%     settings => [
%%         #{key => <<"max_threads">>, value => <<"4">>,
%%           important => false, custom => false, obsolete => false}
%%     ]
%% }).
%%
%% % Query with parameters and settings
%% {ok, Result} = clickhouse_erl:query(Conn,
%%     <<"SELECT * FROM users WHERE id = {user_id:UInt64}">>, #{
%%     parameters => [{<<"user_id">>, <<"123">>}],
%%     settings => #{<<"max_threads">> => <<"2">>}
%% }).
%%
%% % Query with timeout
%% {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM table">>, #{
%%     timeout => 30000,
%%     settings => #{<<"max_execution_time">> => <<"30">>}
%% }).
%% '''
%%
%% Settings errors:
%% ```
%% {error, {invalid_settings_format, Settings}} - Invalid settings format
%% {error, {server_exception, ExceptionInfo}} - Unknown setting or invalid value
%% '''
%%
%% @param Connection The connection pid.
%% @param SQL The SQL query.
%% @param Options A map of options (e.g., `#{timeout => 5000, settings => #{...}}').
%% @returns {ok, Result} or {error, Reason}.
-spec query(Connection, SQL, Options) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    SQL :: string() | binary(),
    Options :: query_options(),
    Result :: term(),
    Reason :: connection_error().
query(Connection, SQL, Options) ->
    clickhouse_erl_app:query(Connection, SQL, Options).

%% @doc Cancel the currently active query on the connection.
%%
%% This is a convenience function for cancelling the active query when you
%% don't know the query ID (e.g., when the query ID was auto-generated).
%% If there is no active query, returns {error, no_active_query}.
%%
%% @param Connection The connection pid.
%% @returns ok or {error, Reason}.
-spec cancel_query(Connection) -> ok | {error, Reason} when
    Connection :: pid(),
    Reason :: connection_error() | no_active_query.
cancel_query(Connection) ->
    clickhouse_erl_connection:cancel_query(Connection).

%% @doc Cancel an active query on the server by query ID.
%%
%% Notifies the server to stop processing the query identified by QueryId.
%%
%% @param Connection The connection pid.
%% @param QueryId The unique query identifier (string or binary).
%% @returns ok or {error, Reason}.
-spec cancel_query(Connection, QueryId) -> ok | {error, Reason} when
    Connection :: pid(),
    QueryId :: string() | binary(),
    Reason :: connection_error().
cancel_query(Connection, QueryId) ->
    clickhouse_erl_app:cancel_query(Connection, QueryId).

%% @doc Execute an INSERT query with column-oriented data.
%%
%% Sends a SQL INSERT statement followed by a data block.
%% The `Input' must be a list of column maps:
%% <ul>
%%   <li>`name': binary() - Column name</li>
%%   <li>`type': binary() - ClickHouse type name (e.g., <<"UInt32">>)</li>
%%   <li>`data': [term()] - List of values for this column</li>
%% </ul>
%%
%% @param Connection The connection pid.
%% @param SQL The INSERT statement (e.g. <<"INSERT INTO table (a, b) VALUES">>).
%% @param Input List of column data maps.
%% @returns {ok, Result} with `rows_inserted' and `elapsed_time'.
-spec insert(Connection, SQL, Input) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    SQL :: string() | binary(),
    Input :: [term()],
    Result :: term(),
    Reason :: term().
insert(Connection, SQL, Input) ->
    ?LOG_DEBUG("API call: insert/3", #{
        connection => Connection,
        sql => SQL,
        input_size => length(Input)
    }),
    clickhouse_erl_app:insert(Connection, SQL, Input).

%% @doc Execute an INSERT query with additional options.
%%
%% @param Connection The connection pid.
%% @param SQL The INSERT statement.
%% @param Input List of column data maps.
%% @param Options Options map (e.g., `#{timeout => 60000}').
%% @returns {ok, Result} or {error, Reason}.
-spec insert(Connection, SQL, Input, Options) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    SQL :: string() | binary(),
    Input :: [term()],
    Options :: map(),
    Result :: term(),
    Reason :: term().
insert(Connection, SQL, Input, Options) ->
    ?LOG_DEBUG("API call: insert/4", #{
        connection => Connection,
        sql => SQL,
        input_size => length(Input),
        options => Options
    }),
    clickhouse_erl_app:insert(Connection, SQL, Input, Options).

%% @doc Format library errors for human-readable display.
%%
%% Translates error tuples like `{server_exception, ...}' or `{network_error, ...}'
%% into descriptive binaries or strings.
%%
%% @param Error Any error tuple returned by public API functions.
%% @returns A formatted error binary or string.
-spec format_error(Error) -> binary() | string() when
    Error :: connection_error() | term().
format_error(Error) ->
    clickhouse_erl_connection:format_error(Error).

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% No internal functions needed - this module is a pure API wrapper
