%%%-------------------------------------------------------------------
%% @doc clickhouse_erl public API
%% @end
%%%-------------------------------------------------------------------

-module(clickhouse_erl_app).
-include_lib("kernel/include/logger.hrl").

-behaviour(application).

-export([start/2, stop/1]).

%% Public API for connection management
-export([
    connect/2,
    connect/3,
    disconnect/1,
    get_connection_info/1,
    query/2,
    query/3,
    insert/3,
    insert/4,
    cancel_query/1,
    cancel_query/2
]).

start(_StartType, _StartArgs) ->
    clickhouse_erl_sup:start_link().

stop(_State) ->
    % Gracefully stop all connections before shutting down
    case whereis(clickhouse_erl_connection_sup) of
        undefined ->
            ok;
        Pid when is_pid(Pid) ->
            % Get all active connections and stop them gracefully
            Children = supervisor:which_children(clickhouse_erl_connection_sup),
            lists:foreach(fun stop_connection_child/1, Children),
            ok
    end.

%%%===================================================================
%%% Public API
%%%===================================================================

%% @doc Connect to ClickHouse server with default options
-spec connect(Host, Port) -> {ok, Connection} | {error, Reason} when
    Host :: string() | inet:ip_address(),
    Port :: inet:port_number(),
    Connection :: pid(),
    Reason :: clickhouse_erl_connection:connection_error().
connect(Host, Port) ->
    connect(Host, Port, #{}).

%% @doc Connect to ClickHouse server with options
-spec connect(Host, Port, Options) -> {ok, Connection} | {error, Reason} when
    Host :: string() | inet:ip_address(),
    Port :: inet:port_number(),
    Options :: clickhouse_erl_connection:connection_options(),
    Connection :: pid(),
    Reason :: clickhouse_erl_connection:connection_error().
connect(Host, Port, Options) ->
    clickhouse_erl_connection_sup:start_connection(Host, Port, Options).

%% @doc Disconnect from ClickHouse server
-spec disconnect(Connection) -> ok | {error, Reason} when
    Connection :: pid(),
    Reason :: term().
disconnect(Connection) ->
    clickhouse_erl_connection_sup:stop_connection(Connection).

%% @doc Get connection information
-spec get_connection_info(Connection) -> {ok, Info} | {error, Reason} when
    Connection :: pid(),
    Info :: clickhouse_erl_connection:connection_info(),
    Reason :: clickhouse_erl_connection:connection_error().
get_connection_info(Connection) ->
    clickhouse_erl_connection:get_connection_info(Connection).

%% @doc Execute a query on the ClickHouse server
-spec query(Connection, SQL) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    SQL :: string(),
    Result :: term(),
    Reason :: clickhouse_erl_connection:connection_error().
query(Connection, SQL) ->
    query(Connection, SQL, #{}).

%% @doc Execute a query with options
-spec query(Connection, SQL, Options) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    SQL :: string(),
    Options :: map(),
    Result :: term(),
    Reason :: clickhouse_erl_connection:connection_error().
query(Connection, SQL, Options) ->
    %% Normalize settings before preparing request
    RawSettings = maps:get(settings, Options, []),
    NormalizedSettings = clickhouse_erl_query_manager:normalize_settings(RawSettings),

    PreparedRequest = #{
        sql => SQL,
        query_id => maps:get(query_id, Options, clickhouse_erl_utils:generate_query_id()),
        settings => NormalizedSettings,
        parameters => maps:get(parameters, Options, []),
        timeout => maps:get(timeout, Options, 30000)
    },
    %% Pass through streaming callback options if present
    PreparedRequestWithCallbacks =
        case maps:get(on_data, Options, undefined) of
            undefined ->
                PreparedRequest;
            OnData ->
                PreparedRequest#{
                    on_data => OnData,
                    initial_accumulator => maps:get(initial_accumulator, Options, undefined),
                    on_progress => maps:get(on_progress, Options, undefined),
                    on_profile => maps:get(on_profile, Options, undefined),
                    on_profile_events => maps:get(on_profile_events, Options, undefined)
                }
        end,
    clickhouse_erl_connection:query(Connection, PreparedRequestWithCallbacks).

%% @doc Execute an INSERT query on the ClickHouse server
-spec insert(Connection, SQL, Input) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    SQL :: string() | binary(),
    Input :: list(),
    Result :: clickhouse_erl_query_manager:insert_result(),
    Reason :: term().
insert(Connection, SQL, Input) ->
    insert(Connection, SQL, Input, #{}).

%% @doc Execute an INSERT query with options
-spec insert(Connection, SQL, Input, Options) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    SQL :: string() | binary(),
    Input :: list(),
    Options :: map(),
    Result :: clickhouse_erl_query_manager:insert_result(),
    Reason :: term().
insert(Connection, SQL, Input, Options) ->
    %% Convert SQL to binary if it's a string
    BinSQL =
        case is_list(SQL) of
            true -> unicode:characters_to_binary(SQL);
            false -> SQL
        end,
    Timeout = maps:get(timeout, Options, 30000),

    ?LOG_INFO("Executing INSERT query", #{
        connection => Connection,
        sql => BinSQL,
        num_columns => length(Input),
        timeout => Timeout
    }),

    %% Pass through streaming callback options if present
    case maps:get(on_data, Options, undefined) of
        undefined ->
            clickhouse_erl_query_manager:execute_insert(Connection, BinSQL, Input, Timeout);
        OnData ->
            %% Calculate num_columns and num_rows from Input
            NumColumns = length(Input),
            NumRows =
                case Input of
                    [] -> 0;
                    [FirstCol | _] -> length(maps:get(data, FirstCol))
                end,

            %% Build PreparedRequest with callbacks for INSERT
            PreparedRequest = #{
                sql => BinSQL,
                query_id => maps:get(query_id, Options, clickhouse_erl_utils:generate_query_id()),
                settings => maps:get(settings, Options, []),
                parameters => maps:get(parameters, Options, []),
                timeout => Timeout,
                %% Use 'input' key for INSERT data
                input => Input,
                num_columns => NumColumns,
                num_rows => NumRows,
                on_data => OnData,
                initial_accumulator => maps:get(initial_accumulator, Options, undefined),
                on_progress => maps:get(on_progress, Options, undefined),
                on_profile => maps:get(on_profile, Options, undefined),
                on_profile_events => maps:get(on_profile_events, Options, undefined)
            },
            clickhouse_erl_connection:insert(Connection, PreparedRequest)
    end.

%% @doc Cancel the currently active query
-spec cancel_query(Connection) -> ok | {error, Reason} when
    Connection :: pid(),
    Reason :: clickhouse_erl_connection:connection_error() | no_active_query.
cancel_query(Connection) ->
    clickhouse_erl_connection:cancel_query(Connection).

%% @doc Cancel an active query by query ID
-spec cancel_query(Connection, QueryId) -> ok | {error, Reason} when
    Connection :: pid(),
    QueryId :: string(),
    Reason :: clickhouse_erl_connection:connection_error().
cancel_query(Connection, QueryId) ->
    clickhouse_erl_connection:cancel_query(Connection, QueryId).

%% internal functions

%% @doc Helper function to stop a connection child process
-spec stop_connection_child(ChildInfo) -> ok when
    ChildInfo :: {Id, Child, Type, Modules},
    Id :: term(),
    Child :: pid() | undefined,
    Type :: worker | supervisor,
    Modules :: [module()] | dynamic.
stop_connection_child({_Id, undefined, _Type, _Modules}) ->
    % Child not running
    ok;
stop_connection_child({_Id, Pid, _Type, _Modules}) when is_pid(Pid) ->
    % Try to gracefully disconnect the connection
    try
        clickhouse_erl_connection:disconnect(Pid)
    catch
        _:_ -> ok
    end;
stop_connection_child(_) ->
    ok.
