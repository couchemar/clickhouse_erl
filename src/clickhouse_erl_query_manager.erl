%% @doc ClickHouse query execution manager
%%
%% This module implements the query execution manager that coordinates
%% query execution workflow, validates requests, and integrates with
%% the connection management layer.
%%
%% == Settings Normalization ==
%%
%% The module provides settings normalization that accepts three input formats:
%%
%% ```
%% % Simple map format (recommended)
%% Settings = #{<<"max_threads">> => <<"4">>}.
%%
%% % Keyword list format
%% Settings = [{<<"max_threads">>, <<"4">>}].
%%
%% % Protocol format (advanced)
%% Settings = [#{key => <<"max_threads">>, value => <<"4">>,
%%               important => false, custom => false, obsolete => false}].
%% '''
%%
%% All formats are automatically converted to the internal protocol format
%% with sensible flag defaults (important=false, custom=false, obsolete=false).
%%
%% == Error Cases ==
%%
%% ```
%% {error, {invalid_settings_format, Settings}} - Invalid format
%% '''
%% @end
-module(clickhouse_erl_query_manager).

%% Public API
-export([
    execute_query/2,
    execute_insert/4,
    start_query/3,
    is_expired/1,
    get_query_ref/1,
    get_caller/1,
    get_result_accumulator/1,
    update_result_accumulator/2,
    track_query/2,
    untrack_query/2,
    cleanup_query/2,
    get_active_queries/1,
    cleanup_expired_queries/1,
    notify_query_caller/2,
    is_query_active/2,
    get_query_state/2,
    update_query_state/3,
    get_query_statistics/1,
    cancel_query/2,
    is_cancelled/1,
    get_query_registry/0,
    normalize_settings/1
]).

%% Include protocol definitions
-include("clickhouse_erl_protocol.hrl").
-include_lib("kernel/include/logger.hrl").

%% Type definitions
-type query_error() ::
    {validation_error, empty_query | missing_sql | invalid_sql_type | invalid_arguments | term()}
    | {connection_error, term()}
    | {timeout_error, term()}
    | {protocol_error, term()}
    | {cancellation_error, term()}
    | {send_failed, term()}
    | {server_exception, exception_info()}.

-type insert_result() :: #{
    rows_inserted => non_neg_integer(),
    elapsed_time => non_neg_integer()
}.

-export_type([
    query_error/0,
    insert_result/0,
    query_state/0,
    result_accumulator/0,
    column_data/0,
    query_request/0,
    setting/0,
    settings_input/0
]).

%%%===================================================================
%%% Public API
%%%===================================================================

%% @doc Start tracking a new query
%% Initializes a new query state record
-spec start_query(QueryId :: binary(), Caller :: {pid(), term()}, Timeout :: timeout()) ->
    query_state().
start_query(QueryId, Caller, Timeout) ->
    #query_state{
        query_id = QueryId,
        query_ref = make_ref(),
        caller = Caller,
        start_time = erlang:system_time(millisecond),
        timeout = Timeout,
        result_accumulator = #result_accumulator{
            columns = [],
            rows = [],
            total_rows = 0,
            statistics = #{
                rows_read => 0,
                bytes_read => 0,
                elapsed_time => 0
            }
        },
        cancelled = false
    }.

%% @doc Check if a query has timed out
-spec is_expired(query_state()) -> boolean().
is_expired(#query_state{start_time = StartTime, timeout = Timeout}) ->
    is_expired(StartTime, Timeout).

is_expired(_StartTime, infinity) ->
    false;
is_expired(StartTime, Timeout) ->
    CurrentTime = erlang:system_time(millisecond),
    (CurrentTime - StartTime) > Timeout.

%% @doc Get the query reference
-spec get_query_ref(query_state()) -> reference().
get_query_ref(#query_state{query_ref = Ref}) ->
    Ref.

%% @doc Get the caller
-spec get_caller(query_state()) -> {pid(), term()}.
get_caller(#query_state{caller = Caller}) ->
    Caller.

%% @doc Get result accumulator
-spec get_result_accumulator(query_state()) -> result_accumulator().
get_result_accumulator(#query_state{result_accumulator = Acc}) ->
    Acc.

%% @doc Update result accumulator
-spec update_result_accumulator(query_state(), result_accumulator()) -> query_state().
update_result_accumulator(State, NewAcc) ->
    State#query_state{result_accumulator = NewAcc}.

%% @doc Track an active query in the query registry
%% Requirements: 5.1, 5.3 - Track active queries with references and timeouts
-spec track_query(QueryState :: query_state(), QueryRegistry :: #{reference() => query_state()}) ->
    {ok, NewRegistry :: #{reference() => query_state()}}.
track_query(QueryState, QueryRegistry) ->
    QueryRef = QueryState#query_state.query_ref,
    NewRegistry = maps:put(QueryRef, QueryState, QueryRegistry),
    {ok, NewRegistry}.

%% @doc Remove a query from the active query registry
%% Requirements: 5.3, 5.4 - Handle query cleanup on completion or failure
-spec untrack_query(QueryRef :: reference(), QueryRegistry :: #{reference() => query_state()}) ->
    {ok, NewRegistry :: #{reference() => query_state()}}.
untrack_query(QueryRef, QueryRegistry) ->
    NewRegistry = maps:remove(QueryRef, QueryRegistry),
    {ok, NewRegistry}.

%% @doc Clean up a specific query and notify caller if needed
%% Requirements: 5.4 - Handle query cleanup on completion or failure
-spec cleanup_query(QueryRef :: reference(), QueryRegistry :: #{reference() => query_state()}) ->
    {ok, NewRegistry :: #{reference() => query_state()}} | {error, query_not_found}.
cleanup_query(QueryRef, QueryRegistry) ->
    case maps:get(QueryRef, QueryRegistry, undefined) of
        undefined ->
            {error, query_not_found};
        _QueryState ->
            %% Perform any necessary cleanup for the query state
            %% For now, just remove it from the registry
            %% In future implementations, this could include:
            %% - Canceling network operations
            %% - Freeing memory resources
            %% - Notifying monitoring systems
            NewRegistry = maps:remove(QueryRef, QueryRegistry),
            {ok, NewRegistry}
    end.

%% @doc Get all active queries from the registry
%% Requirements: 5.1 - Track active queries
-spec get_active_queries(QueryRegistry :: #{reference() => query_state()}) ->
    [query_state()].
get_active_queries(QueryRegistry) ->
    maps:values(QueryRegistry).

%% @doc Clean up expired queries from the registry
%% Requirements: 5.3, 5.4 - Handle query cleanup on timeout
-spec cleanup_expired_queries(QueryRegistry :: #{reference() => query_state()}) ->
    {ok, NewRegistry :: #{reference() => query_state()}, ExpiredQueries :: [query_state()]}.
cleanup_expired_queries(QueryRegistry) ->
    {_ExpiredRefs, ExpiredQueries, ActiveRegistry} = maps:fold(
        fun(QueryRef, QueryState, {ExpiredRefsAcc, ExpiredQueriesAcc, ActiveRegistryAcc}) ->
            case is_expired(QueryState) orelse is_cancelled(QueryState) of
                true ->
                    %% Query has expired or been cancelled, add to expired lists
                    {
                        [QueryRef | ExpiredRefsAcc],
                        [QueryState | ExpiredQueriesAcc],
                        ActiveRegistryAcc
                    };
                false ->
                    %% Query is still active, keep in registry
                    {ExpiredRefsAcc, ExpiredQueriesAcc,
                        maps:put(QueryRef, QueryState, ActiveRegistryAcc)}
            end
        end,
        {[], [], #{}},
        QueryRegistry
    ),

    {ok, ActiveRegistry, ExpiredQueries}.

%% @doc Execute a query on the given connection
%% Validates the request, prepares query parameters, and delegates
%% execution to the connection manager with proper error handling.
%% Requirements: 1.4, 2.3, 5.1
-spec execute_query(Connection :: pid(), QueryRequest :: query_request()) ->
    {ok, term()} | {error, query_error()}.
execute_query(Connection, QueryRequest) when is_pid(Connection), is_map(QueryRequest) ->
    case validate_and_prepare_request(QueryRequest) of
        {ok, PreparedRequest} ->
            %% Start tracking the query
            QueryId = maps:get(query_id, PreparedRequest),
            Caller = {self(), make_ref()},
            Timeout = maps:get(timeout, PreparedRequest),
            QueryState = start_query(QueryId, Caller, Timeout),

            %% Track the query in the registry
            {ok, QueryRegistry} = track_query(QueryState, get_query_registry()),

            %% Delegate to connection manager with prepared request
            case execute_with_connection(Connection, PreparedRequest) of
                {ok, Result} ->
                    %% Clean up the query
                    {ok, _} = cleanup_query(QueryState#query_state.query_ref, QueryRegistry),
                    {ok, Result};
                {error, Reason} ->
                    %% Clean up the query
                    {ok, _} = cleanup_query(QueryState#query_state.query_ref, QueryRegistry),
                    {error, map_connection_error(Reason)}
            end;
        {error, _} = ValidationError ->
            ValidationError
    end;
execute_query(_Connection, _QueryRequest) ->
    {error, {validation_error, invalid_arguments}}.

%% @doc Execute an INSERT query on the given connection
%% Validates the input data, prepares INSERT parameters, and delegates
%% execution to the connection manager with proper error handling.
%% Requirements: 1.1, 1.2, 1.3, 1.4
-spec execute_insert(
    Connection :: pid(),
    SQL :: binary(),
    Input :: [column_data()],
    Timeout :: timeout()
) ->
    {ok, insert_result()} | {error, query_error()}.
execute_insert(Connection, SQL, Input, Timeout) when
    is_pid(Connection), is_binary(SQL), is_list(Input)
->
    %% Step 1: Validate input data (Requirements 2.1, 2.4)
    case validate_insert_input(Input) of
        ok ->
            %% Step 2: Prepare INSERT request
            PreparedRequest = prepare_insert_request(SQL, Input, Timeout),
            QueryId = maps:get(query_id, PreparedRequest),
            NumRows = maps:get(num_rows, PreparedRequest),
            NumCols = maps:get(num_columns, PreparedRequest),

            %% Set logger metadata for this query
            logger:set_process_metadata(#{
                query_id => QueryId,
                connection_pid => Connection
            }),

            ?LOG_INFO("Starting INSERT query", #{
                rows => NumRows,
                columns => NumCols
            }),

            %% Step 3: Delegate to connection manager
            StartTime = erlang:system_time(millisecond),
            case clickhouse_erl_connection:insert(Connection, PreparedRequest) of
                {ok, Result} ->
                    Duration = erlang:system_time(millisecond) - StartTime,
                    RowsInserted = maps:get(rows_inserted, Result, 0),

                    ?LOG_INFO("INSERT query completed successfully", #{
                        duration_ms => Duration,
                        rows_inserted => RowsInserted
                    }),

                    %% Clear logger metadata
                    logger:unset_process_metadata(),
                    {ok, Result};
                {error, Reason} ->
                    MappedError = map_connection_error(Reason),
                    ?LOG_ERROR("INSERT query failed", #{
                        reason => MappedError
                    }),

                    %% Clear logger metadata
                    logger:unset_process_metadata(),
                    {error, MappedError}
            end;
        {error, _} = ValidationError ->
            ?LOG_ERROR("INSERT validation failed", #{
                reason => ValidationError,
                connection => Connection
            }),
            ValidationError
    end;
execute_insert(Connection, _SQL, _Input, _Timeout) ->
    ?LOG_ERROR("INSERT failed: invalid arguments", #{
        connection => Connection
    }),
    {error, {validation_error, invalid_arguments}}.

%% @doc Cancel an active query
%% Requirements: 5.4, 5.5 - Add query cancellation capability
-spec cancel_query(QueryRef :: reference(), QueryRegistry :: #{reference() => query_state()}) ->
    {ok, NewRegistry :: #{reference() => query_state()}}
    | {error, query_not_found | query_not_active}.
cancel_query(QueryRef, QueryRegistry) ->
    case maps:get(QueryRef, QueryRegistry, undefined) of
        undefined ->
            {error, query_not_found};
        QueryState ->
            case is_query_active(QueryRef, QueryRegistry) of
                false ->
                    {error, query_not_active};
                true ->
                    %% Send cancellation packet to server
                    case send_cancellation_packet(QueryState) of
                        ok ->
                            %% Update query state to cancelled
                            CancelledState = QueryState#query_state{
                                cancelled = true
                            },
                            NewRegistry = maps:put(QueryRef, CancelledState, QueryRegistry),
                            {ok, NewRegistry};
                        {error, Reason} ->
                            {error, {cancellation_failed, Reason}}
                    end
            end
    end.

%% @doc Check if a query has been cancelled
-spec is_cancelled(query_state()) -> boolean().
is_cancelled(#query_state{cancelled = true}) ->
    true;
is_cancelled(_) ->
    false.

%% @doc Get the query registry
-spec get_query_registry() -> #{reference() => query_state()}.
get_query_registry() ->
    case erlang:get(query_registry) of
        undefined ->
            Registry = #{},
            erlang:put(query_registry, Registry),
            Registry;
        Registry ->
            Registry
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Validate and prepare the query request
%% Performs comprehensive validation of the query request and prepares
%% it for execution by the connection manager.
-spec validate_and_prepare_request(query_request()) ->
    {ok, PreparedRequest :: map()} | {error, query_error()}.
validate_and_prepare_request(QueryRequest) ->
    %% Step 1: Validate SQL query (Requirement 1.4)
    case validate_sql_query(QueryRequest) of
        {ok, SQL} ->
            %% Step 2: Validate and prepare other parameters
            %% Step 2: Validate and prepare other parameters
            PreparedRequest = prepare_query_parameters(QueryRequest, SQL),
            {ok, PreparedRequest};
        {error, _} = Error ->
            Error
    end.

%% @doc Validate SQL query string
%% Ensures the SQL query is present and not empty (Requirement 1.4)
-spec validate_sql_query(query_request()) -> {ok, binary()} | {error, query_error()}.
validate_sql_query(#{sql := SQL}) when is_binary(SQL) ->
    case string:trim(SQL) of
        <<>> ->
            {error, {validation_error, empty_query}};
        TrimmedSQL ->
            {ok, TrimmedSQL}
    end;
validate_sql_query(#{sql := SQL}) when is_list(SQL) ->
    %% Convert string to binary and validate
    validate_sql_query(#{sql => unicode:characters_to_binary(SQL)});
validate_sql_query(#{sql := _}) ->
    {error, {validation_error, invalid_sql_type}};
validate_sql_query(_) ->
    {error, {validation_error, missing_sql}}.

%% @doc Prepare query parameters for execution
%% Prepares query ID, settings, timeout, and parameters
-spec prepare_query_parameters(query_request(), binary()) ->
    PreparedRequest :: map().
prepare_query_parameters(QueryRequest, SQL) ->
    %% Prepare query ID (generate if not provided)
    QueryId = prepare_query_id(QueryRequest),

    %% Prepare settings (validate and normalize)
    Settings = prepare_settings(QueryRequest),

    %% Prepare timeout (use default if not provided)
    Timeout = prepare_timeout(QueryRequest),

    %% Prepare parameters (extract if provided)
    Parameters = prepare_parameters(QueryRequest),

    %% Build prepared request
    #{
        sql => SQL,
        query_id => QueryId,
        settings => Settings,
        timeout => Timeout,
        parameters => Parameters
    }.

%% @doc Prepare query ID (generate if not provided)
%% Requirements: 1.6 - Generate unique query IDs
-spec prepare_query_id(query_request()) -> binary().
prepare_query_id(#{query_id := QueryId}) when is_binary(QueryId), byte_size(QueryId) > 0 ->
    QueryId;
prepare_query_id(_) ->
    %% Generate unique query ID using existing utility
    clickhouse_erl_utils:generate_query_id().

%% @doc Prepare and validate settings
%% Accepts multiple input formats and normalizes to protocol format.
%%
%% This function is the entry point for settings normalization in query preparation.
%% It delegates to normalize_settings/1 for the actual conversion.
%%
%% Examples:
%% ```
%% % With simple map settings
%% prepare_settings(#{settings => #{<<"max_threads">> => <<"4">>}}).
%% % Returns: [#{key => <<"max_threads">>, value => <<"4">>,
%% %             important => false, custom => false, obsolete => false}]
%%
%% % With keyword list settings
%% prepare_settings(#{settings => [{<<"max_threads">>, <<"4">>}]}).
%% % Returns: [#{key => <<"max_threads">>, value => <<"4">>,
%% %             important => false, custom => false, obsolete => false}]
%%
%% % Without settings
%% prepare_settings(#{}).
%% % Returns: []
%% '''
-spec prepare_settings(query_request()) -> [setting()].
prepare_settings(#{settings := Settings}) ->
    normalize_settings(Settings);
prepare_settings(_) ->
    %% No settings provided, use empty list
    [].

%% @doc Normalize settings from various input formats to protocol format
%%
%% Accepts three input formats and converts them to the internal protocol format:
%%
%% 1. Simple map format (recommended):
%%    `#{<<"max_threads">> => <<"4">>, <<"max_memory_usage">> => <<"10000000000">>}'
%%
%% 2. Keyword list format:
%%    `[{<<"max_threads">>, <<"4">>}, {<<"max_memory_usage">>, <<"10000000000">>}]'
%%
%% 3. Protocol format (advanced):
%%    `[#{key => <<"max_threads">>, value => <<"4">>,
%%        important => true, custom => false, obsolete => false}]'
%%
%% All formats are converted to the internal protocol format with default flags:
%% - important => false (setting is not critical)
%% - custom => false (not a custom user setting)
%% - obsolete => false (setting is not deprecated)
%%
%% Examples:
%% ```
%% % Simple map format
%% normalize_settings(#{<<"max_threads">> => <<"4">>}).
%% % Returns: [#{key => <<"max_threads">>, value => <<"4">>,
%% %             important => false, custom => false, obsolete => false}]
%%
%% % Keyword list format
%% normalize_settings([{<<"max_threads">>, <<"4">>}]).
%% % Returns: [#{key => <<"max_threads">>, value => <<"4">>,
%% %             important => false, custom => false, obsolete => false}]
%%
%% % Protocol format with explicit flags
%% normalize_settings([#{key => <<"custom_setting">>, value => <<"value">>,
%%                       important => true, custom => true}]).
%% % Returns: [#{key => <<"custom_setting">>, value => <<"value">>,
%% %             important => true, custom => true, obsolete => false}]
%%
%% % Empty settings
%% normalize_settings(#{}).
%% % Returns: []
%%
%% normalize_settings([]).
%% % Returns: []
%% '''
%%
%% Error cases:
%% ```
%% % Invalid list format (flat list)
%% normalize_settings([<<"key">>, <<"value">>]).
%% % Raises: error({invalid_settings_format, ...})
%%
%% % Mixed formats (not allowed)
%% normalize_settings([{<<"key1">>, <<"val1">>}, #{key => <<"key2">>, value => <<"val2">>}]).
%% % Raises: function_clause
%%
%% % Non-binary keys or values
%% normalize_settings([{key_atom, <<"value">>}]).
%% % Raises: error({invalid_settings_format, ...})
%% '''
-spec normalize_settings(settings_input()) -> [setting()].
normalize_settings(Settings) when is_map(Settings) ->
    normalize_settings_map(Settings);
normalize_settings(Settings) when is_list(Settings) ->
    normalize_settings_list(Settings).

%% @doc Normalize map format settings
%%
%% Converts a simple map of binary key-value pairs to protocol format.
%% Non-binary keys or values are silently skipped.
%%
%% Examples:
%% ```
%% normalize_settings_map(#{<<"max_threads">> => <<"4">>}).
%% % Returns: [#{key => <<"max_threads">>, value => <<"4">>,
%% %             important => false, custom => false, obsolete => false}]
%%
%% normalize_settings_map(#{}).
%% % Returns: []
%% '''
-spec normalize_settings_map(setting_simple_map()) -> [setting()].
normalize_settings_map(Settings) when map_size(Settings) =:= 0 ->
    [];
normalize_settings_map(Settings) ->
    maps:fold(
        fun
            (Key, Value, Acc) when is_binary(Key), is_binary(Value) ->
                [
                    #{
                        key => Key,
                        value => Value,
                        important => false,
                        custom => false,
                        obsolete => false
                    }
                    | Acc
                ];
            (_Key, _Value, Acc) ->
                %% Skip invalid entries (non-binary keys/values)
                Acc
        end,
        [],
        Settings
    ).

%% @doc Normalize list format settings (keyword list or protocol format)
%%
%% Handles two list formats:
%% 1. Keyword list: [{binary(), binary()}]
%% 2. Protocol format: [#{key := binary(), value := binary(), ...}]
%%
%% The function pattern matches on the first element to determine the format.
%% For protocol format, explicit flags are preserved; missing flags default to false.
%%
%% Examples:
%% ```
%% % Keyword list
%% normalize_settings_list([{<<"max_threads">>, <<"4">>}]).
%% % Returns: [#{key => <<"max_threads">>, value => <<"4">>,
%% %             important => false, custom => false, obsolete => false}]
%%
%% % Protocol format with explicit flags
%% normalize_settings_list([#{key => <<"setting">>, value => <<"val">>, important => true}]).
%% % Returns: [#{key => <<"setting">>, value => <<"val">>,
%% %             important => true, custom => false, obsolete => false}]
%%
%% % Empty list
%% normalize_settings_list([]).
%% % Returns: []
%% '''
%%
%% Error cases:
%% ```
%% % Invalid format
%% normalize_settings_list([<<"key">>, <<"value">>]).
%% % Raises: error({invalid_settings_format, ...})
%% '''
-spec normalize_settings_list(setting_keyword_list() | [setting_protocol_format()]) -> [setting()].
normalize_settings_list([]) ->
    [];
normalize_settings_list([{Key, Value} | _] = Settings) when is_binary(Key), is_binary(Value) ->
    %% Keyword list format
    lists:map(
        fun({K, V}) when is_binary(K), is_binary(V) ->
            #{
                key => K,
                value => V,
                important => false,
                custom => false,
                obsolete => false
            }
        end,
        Settings
    );
normalize_settings_list([#{key := _Key, value := _Value} | _] = Settings) ->
    %% Protocol format (already normalized or with flags)
    lists:map(
        fun(Setting) ->
            #{
                key => maps:get(key, Setting),
                value => maps:get(value, Setting),
                important => maps:get(important, Setting, false),
                custom => maps:get(custom, Setting, false),
                obsolete => maps:get(obsolete, Setting, false)
            }
        end,
        Settings
    );
normalize_settings_list(Invalid) ->
    error(
        {invalid_settings_format, Invalid,
            "List settings must be either [{binary(), binary()}] "
            "or [#{key := binary(), value := binary()}]"}
    ).

%% @doc Prepare timeout value
-spec prepare_timeout(query_request()) -> timeout().
prepare_timeout(#{timeout := Timeout}) when is_integer(Timeout), Timeout > 0 ->
    Timeout;
prepare_timeout(#{timeout := infinity}) ->
    infinity;
prepare_timeout(_) ->
    %% Default timeout: 30 seconds
    30000.

%% @doc Prepare parameters list
-spec prepare_parameters(query_request()) -> [{binary(), binary()}].
prepare_parameters(#{parameters := Parameters}) when is_list(Parameters) ->
    Parameters;
prepare_parameters(_) ->
    %% No parameters provided, use empty list
    [].

%% @doc Execute query with connection manager
%% Delegates to the connection manager's query interface
%% Requirements: 2.3, 5.1 - Integration with connection management
-spec execute_with_connection(pid(), map()) -> {ok, term()} | {error, term()}.
execute_with_connection(Connection, PreparedRequest) ->
    _SQL = maps:get(sql, PreparedRequest),

    %% For now, delegate to the existing connection query interface
    %% In future tasks, this will be enhanced to use the full query packet protocol
    %% and handle query state management
    %% Delegate to the connection query interface
    %% We pass the full PreparedRequest so the connection module has access to
    %% all query parameters including query_id, settings, client_info etc.
    clickhouse_erl_connection:query(Connection, PreparedRequest).

%% @doc Map connection errors to query manager error format
-spec map_connection_error(term()) -> query_error().
map_connection_error({network_error, Reason}) ->
    {connection_error, {network, Reason}};
map_connection_error({protocol_error, Reason}) ->
    {protocol_error, Reason};
map_connection_error({timeout_error, Reason}) ->
    {timeout_error, Reason};
map_connection_error({server_exception, ExceptionInfo}) ->
    {server_exception, ExceptionInfo};
map_connection_error({exception_field_truncated, _, _, _} = Reason) ->
    {protocol_error, Reason};
map_connection_error(Reason) ->
    {connection_error, Reason}.

%% @doc Notify caller about query completion or failure
%% Requirements: 5.4 - Handle query cleanup and notification
-spec notify_query_caller(query_state(), {ok, term()} | {error, term()}) -> ok.
notify_query_caller(QueryState, Result) ->
    {CallerPid, CallerRef} = QueryState#query_state.caller,
    case is_process_alive(CallerPid) of
        true ->
            CallerPid ! {query_result, CallerRef, QueryState#query_state.query_ref, Result},
            ok;
        false ->
            %% Caller process is dead, nothing to notify
            ok
    end.

%% @doc Check if a query reference exists in the registry
%% Requirements: 5.1 - Track active queries
-spec is_query_active(QueryRef :: reference(), QueryRegistry :: #{reference() => query_state()}) ->
    boolean().
is_query_active(QueryRef, QueryRegistry) ->
    maps:is_key(QueryRef, QueryRegistry).

%% @doc Get query state by reference
%% Requirements: 5.1 - Track active queries
-spec get_query_state(QueryRef :: reference(), QueryRegistry :: #{reference() => query_state()}) ->
    {ok, query_state()} | {error, query_not_found}.
get_query_state(QueryRef, QueryRegistry) ->
    case maps:get(QueryRef, QueryRegistry, undefined) of
        undefined ->
            {error, query_not_found};
        QueryState ->
            {ok, QueryState}
    end.

%% @doc Update query state in the registry
%% Requirements: 5.1, 5.3 - Track and update active queries
-spec update_query_state(
    QueryRef :: reference(),
    QueryState :: query_state(),
    QueryRegistry :: #{reference() => query_state()}
) ->
    {ok, NewRegistry :: #{reference() => query_state()}} | {error, query_not_found}.
update_query_state(QueryRef, NewQueryState, QueryRegistry) ->
    case maps:is_key(QueryRef, QueryRegistry) of
        true ->
            NewRegistry = maps:put(QueryRef, NewQueryState, QueryRegistry),
            {ok, NewRegistry};
        false ->
            {error, query_not_found}
    end.

%% @doc Get statistics about active queries
%% Requirements: 5.1 - Track active queries
-spec get_query_statistics(QueryRegistry :: #{reference() => query_state()}) ->
    #{
        total_queries => non_neg_integer(),
        expired_queries => non_neg_integer(),
        active_queries => non_neg_integer()
    }.
get_query_statistics(QueryRegistry) ->
    TotalQueries = maps:size(QueryRegistry),
    ExpiredCount = maps:fold(
        fun(_QueryRef, QueryState, Acc) ->
            case is_expired(QueryState) of
                true -> Acc + 1;
                false -> Acc
            end
        end,
        0,
        QueryRegistry
    ),
    ActiveCount = TotalQueries - ExpiredCount,

    #{
        total_queries => TotalQueries,
        expired_queries => ExpiredCount,
        active_queries => ActiveCount
    }.

%% @doc Send cancellation packet to server
-spec send_cancellation_packet(query_state()) -> ok | {error, term()}.
send_cancellation_packet(QueryState) ->
    {ConnectionPid, _} = get_caller(QueryState),
    case is_process_alive(ConnectionPid) of
        true ->
            %% Send cancellation packet to connection process
            ConnectionPid ! {cancel_query, QueryState#query_state.query_id},
            ok;
        false ->
            {error, connection_dead}
    end.

%% @doc Validate INSERT input data
%% Requirements: 2.1, 2.4 - Validate column names and row counts
-spec validate_insert_input([column_data()]) -> ok | {error, query_error()}.
validate_insert_input(Input) ->
    %% Validate column names (must be binaries)
    case clickhouse_erl_protocol_data_block:validate_column_names(Input) of
        ok ->
            %% Validate row counts (all columns must have same count)
            case clickhouse_erl_protocol_data_block:validate_row_counts(Input) of
                ok ->
                    ok;
                {error, {row_count_mismatch, Details}} ->
                    {error, {validation_error, {row_count_mismatch, Details}}}
            end;
        {error, {invalid_column_name, Value}} ->
            {error, {validation_error, {invalid_column_name, Value}}}
    end.

%% @doc Prepare INSERT request parameters
%% Requirements: 1.1, 1.2 - Build prepared request for connection layer
-spec prepare_insert_request(binary(), [column_data()], timeout()) ->
    map().
prepare_insert_request(SQL, Input, Timeout) ->
    %% Generate query ID
    QueryId = clickhouse_erl_utils:generate_query_id(),

    %% Calculate row count (all columns have same count due to validation)
    NumRows =
        case Input of
            [] -> 0;
            [#{data := Data} | _] -> length(Data)
        end,

    %% Build prepared request
    PreparedRequest = #{
        sql => SQL,
        query_id => QueryId,
        input => Input,
        num_columns => length(Input),
        num_rows => NumRows,
        timeout => Timeout
    },

    PreparedRequest.
