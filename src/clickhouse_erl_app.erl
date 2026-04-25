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
    connect/3,
    disconnect/1,
    get_connection_info/1,
    query/2,
    query/3,
    insert/3,
    insert/4,
    cancel_query/2,
    add_optional_callbacks/2,
    streaming_insert/4,
    start_streaming_insert/4,
    send_data/3,
    finish_streaming_insert/2
]).

-ignore_xref([add_optional_callbacks/2]).

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
    %% Pass through streaming callback options if present (omit if undefined)
    PreparedRequestWithCallbacks = add_optional_callbacks(PreparedRequest, Options),
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
    BinSQL = ensure_binary_sql(SQL),
    Timeout = maps:get(timeout, Options, 30000),

    ?LOG_INFO("Executing INSERT query", #{
        connection => Connection,
        sql => BinSQL,
        num_columns => length(Input),
        timeout => Timeout
    }),

    %% Pass through streaming callback options if present (omit if undefined)
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
                num_rows => NumRows
            },
            %% Add callbacks only if provided (omit undefined values)
            PreparedRequestWithCallbacks = add_optional_callbacks(
                PreparedRequest#{on_data => OnData}, Options
            ),
            clickhouse_erl_connection:insert(Connection, PreparedRequestWithCallbacks)
    end.

%% @doc Cancel an active query by query ID
-spec cancel_query(Connection, QueryId) -> ok | {error, Reason} when
    Connection :: pid(),
    QueryId :: string(),
    Reason :: clickhouse_erl_connection:connection_error().
cancel_query(Connection, QueryId) ->
    clickhouse_erl_connection:cancel_query(Connection, QueryId).

%% internal functions

%% @doc Convert SQL to binary if it's a string.
-spec ensure_binary_sql(string() | binary()) -> binary().
ensure_binary_sql(SQL) when is_binary(SQL) -> SQL;
ensure_binary_sql(SQL) when is_list(SQL) -> unicode:characters_to_binary(SQL).

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

%% @doc Add optional callback options to PreparedRequest, omitting undefined values.
%% This ensures validation passes since undefined callbacks are no longer allowed.
-spec add_optional_callbacks(PreparedRequest, Options) -> PreparedRequest when
    PreparedRequest :: map(),
    Options :: map().
add_optional_callbacks(PreparedRequest, Options) ->
    lists:foldl(
        fun(Key, Acc) ->
            case maps:get(Key, Options, undefined) of
                undefined -> Acc;
                Value -> Acc#{Key => Value}
            end
        end,
        PreparedRequest,
        [on_data, initial_accumulator, on_progress, on_profile, on_profile_events, on_log]
    ).

%% @doc Execute a streaming INSERT query using pull-based pattern.
%%
%% @param Connection The connection pid.
%% @param SQL The INSERT statement.
%% @param Options Options map containing `on_input' callback and optional `initial_accumulator'.
%% @param ExtraOptions Additional options map.
%% @returns {ok, Result} or {error, Reason}.
-spec streaming_insert(Connection, SQL, Options, ExtraOptions) ->
    {ok, Result} | {error, Reason}
when
    Connection :: pid(),
    SQL :: string() | binary(),
    Options :: #{
        on_input := fun(), columns := [clickhouse_erl:column_def()], initial_accumulator => term()
    },
    ExtraOptions :: map(),
    Result :: clickhouse_erl_connection:streaming_insert_result(),
    Reason :: clickhouse_erl_connection:connection_error().
streaming_insert(Connection, SQL, Options, ExtraOptions) ->
    BinSQL = ensure_binary_sql(SQL),
    Timeout = maps:get(timeout, ExtraOptions, 30000),

    %% Validate required options
    case maps:is_key(on_input, Options) of
        false ->
            {error, {validation_error, missing_on_input_callback}};
        true ->
            case maps:get(on_input, Options) of
                undefined ->
                    {error, {validation_error, missing_on_input_callback}};
                _ ->
                    %% Validate columns are provided
                    case maps:get(columns, Options, undefined) of
                        undefined ->
                            {error, {validation_error, empty_columns}};
                        Columns when is_list(Columns), length(Columns) =:= 0 ->
                            {error, {validation_error, empty_columns}};
                        _ ->
                            ?LOG_INFO("Executing streaming INSERT query", #{
                                connection => Connection,
                                sql => BinSQL,
                                timeout => Timeout
                            }),

                            PreparedRequest = #{
                                sql => BinSQL,
                                query_id => maps:get(
                                    query_id, ExtraOptions, clickhouse_erl_utils:generate_query_id()
                                ),
                                settings => maps:get(settings, ExtraOptions, []),
                                parameters => maps:get(parameters, ExtraOptions, []),
                                timeout => Timeout,
                                columns => maps:get(columns, Options, []),
                                on_input => maps:get(on_input, Options),
                                initial_accumulator => maps:get(initial_accumulator, Options, #{})
                            },
                            clickhouse_erl_connection:streaming_insert(Connection, PreparedRequest)
                    end
            end
    end.

%% @doc Start a push-based streaming insert session.
%%
%% @param Connection The connection pid.
%% @param SQL The INSERT statement.
%% @param Options Options map containing `columns' (list of column definitions).
%% @param ExtraOptions Additional options map.
%% @returns {ok, StreamRef} or {error, Reason}.
-spec start_streaming_insert(Connection, SQL, Options, ExtraOptions) ->
    {ok, StreamRef} | {error, Reason}
when
    Connection :: pid(),
    SQL :: string() | binary(),
    Options :: #{columns := [clickhouse_erl:column_def()]},
    ExtraOptions :: map(),
    StreamRef :: term(),
    Reason :: clickhouse_erl_connection:connection_error().
start_streaming_insert(Connection, SQL, Options, ExtraOptions) ->
    BinSQL = ensure_binary_sql(SQL),
    Timeout = maps:get(timeout, ExtraOptions, 30000),

    %% Validate columns are provided
    Columns = maps:get(columns, Options, []),
    case Columns of
        [] ->
            {error, {validation_error, empty_columns}};
        _ ->
            ?LOG_INFO("Starting streaming INSERT session", #{
                connection => Connection,
                sql => BinSQL,
                num_columns => length(Columns),
                timeout => Timeout
            }),

            PreparedRequest = #{
                sql => BinSQL,
                query_id => maps:get(
                    query_id, ExtraOptions, clickhouse_erl_utils:generate_query_id()
                ),
                settings => maps:get(settings, ExtraOptions, []),
                parameters => maps:get(parameters, ExtraOptions, []),
                timeout => Timeout,
                columns => Columns
            },
            clickhouse_erl_connection:start_streaming_insert(Connection, PreparedRequest)
    end.

%% @doc Send a data block during a push-based streaming insert session.
%%
%% @param Connection The connection pid.
%% @param StreamRef The stream reference returned by start_streaming_insert/3,4.
%% @param ColumnData List of column data maps to send.
%% @returns ok or {error, Reason}.
-spec send_data(Connection, StreamRef, ColumnData) -> ok | {error, Reason} when
    Connection :: pid(),
    StreamRef :: term(),
    ColumnData :: [map()],
    Reason :: clickhouse_erl_connection:connection_error() | validation_error | streaming_error.
send_data(Connection, StreamRef, ColumnData) ->
    clickhouse_erl_connection:send_data(Connection, StreamRef, ColumnData).

%% @doc Finish a push-based streaming insert session.
%%
%% @param Connection The connection pid.
%% @param StreamRef The stream reference returned by start_streaming_insert/3,4.
%% @returns {ok, Result} or {error, Reason}.
-spec finish_streaming_insert(Connection, StreamRef) -> {ok, Result} | {error, Reason} when
    Connection :: pid(),
    StreamRef :: term(),
    Result :: clickhouse_erl_connection:streaming_insert_result(),
    Reason :: clickhouse_erl_connection:connection_error() | streaming_error.
finish_streaming_insert(Connection, StreamRef) ->
    clickhouse_erl_connection:finish_streaming_insert(Connection, StreamRef).
