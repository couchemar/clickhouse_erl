%%%-------------------------------------------------------------------
%% @doc ClickHouse connection supervisor
%%
%% This supervisor manages ClickHouse connection processes with proper
%% restart strategies. It provides dynamic supervision for connection
%% processes that can be started and stopped as needed.
%% @end
%%%-------------------------------------------------------------------

-module(clickhouse_erl_connection_sup).

-behaviour(supervisor).

%% Public API
-export([
    start_link/0,
    start_connection/3,
    stop_connection/1
]).

-ignore_xref([start_link/0]).

%% supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% Public API
%%%===================================================================

%% @doc Start the connection supervisor
-spec start_link() -> {ok, Pid} | {error, Reason} when
    Pid :: pid(),
    Reason :: term().
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% @doc Start a new connection process under supervision
-spec start_connection(Host, Port, Options) -> {ok, Pid} | {error, Reason} when
    Host :: string() | inet:ip_address(),
    Port :: inet:port_number(),
    Options :: clickhouse_erl_connection:connection_options(),
    Pid :: pid(),
    Reason :: term().
start_connection(Host, Port, Options) ->
    % Create a unique child ID based on connection parameters
    ChildId = make_connection_id(Host, Port, Options),

    % Define the child specification for this connection
    ChildSpec = #{
        id => ChildId,
        start => {clickhouse_erl_connection, connect, [Host, Port, Options]},
        % Don't restart failed connections automatically
        restart => temporary,
        % Give 5 seconds for graceful shutdown
        shutdown => 5000,
        type => worker,
        modules => [clickhouse_erl_connection]
    },

    % Start the child process
    case supervisor:start_child(?SERVER, ChildSpec) of
        {ok, Pid} ->
            {ok, Pid};
        {ok, Pid, _Info} ->
            {ok, Pid};
        {error, {already_started, Pid}} ->
            {ok, Pid};
        {error, {Reason, _ChildSpec}} ->
            % Extract the actual error reason, discard supervisor child spec details
            {error, format_connection_error(Reason)};
        {error, Reason} ->
            {error, format_connection_error(Reason)}
    end.

%% @doc Stop a connection process
-spec stop_connection(Connection) -> ok | {error, Reason} when
    Connection :: pid(),
    Reason :: term().
stop_connection(Connection) when is_pid(Connection) ->
    % Check if process is still alive first
    case erlang:is_process_alive(Connection) of
        false ->
            % Process already terminated, consider it a success
            ok;
        true ->
            % Find the child ID for this connection process
            case find_child_id_by_pid(Connection) of
                {ok, ChildId} ->
                    % Terminate the child
                    % Note: For temporary children, supervisor automatically deletes
                    % them after termination, so we don't need to call delete_child
                    case supervisor:terminate_child(?SERVER, ChildId) of
                        ok ->
                            ok;
                        {error, not_found} ->
                            % Child already terminated
                            ok;
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, not_found} ->
                    % Process not found in supervisor, try direct termination
                    try
                        clickhouse_erl_connection:disconnect(Connection),
                        ok
                    catch
                        _:Reason -> {error, Reason}
                    end
            end
    end.

%%%===================================================================
%%% supervisor callbacks
%%%===================================================================

%% @doc Initialize the supervisor
-spec init([]) -> {ok, {SupFlags, ChildSpecs}} when
    SupFlags :: supervisor:sup_flags(),
    ChildSpecs :: [supervisor:child_spec()].
init([]) ->
    % Supervisor flags for dynamic supervision
    SupFlags = #{
        % Restart only failed children
        strategy => one_for_one,
        % Allow up to 10 restarts
        intensity => 10,
        % Within 60 seconds
        period => 60
    },

    % No static children - connections are started dynamically
    ChildSpecs = [],

    {ok, {SupFlags, ChildSpecs}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Create a unique connection ID based on connection parameters
-spec make_connection_id(Host, Port, Options) -> ChildId when
    Host :: string() | inet:ip_address(),
    Port :: inet:port_number(),
    Options :: clickhouse_erl_connection:connection_options(),
    ChildId :: term().
make_connection_id(Host, Port, Options) ->
    % Create a unique identifier that includes connection parameters
    % This allows multiple connections to the same host/port with different options
    Database = maps:get(database, Options, "default"),
    Username = maps:get(username, Options, "default"),

    % Convert host to string if it's an IP address
    HostStr =
        case Host of
            {A, B, C, D} ->
                io_lib:format("~w.~w.~w.~w", [A, B, C, D]);
            {A, B, C, D, E, F, G, H} ->
                io_lib:format("~w:~w:~w:~w:~w:~w:~w:~w", [A, B, C, D, E, F, G, H]);
            HostString when is_list(HostString) -> HostString;
            HostBinary when is_binary(HostBinary) -> binary_to_list(HostBinary);
            _ ->
                io_lib:format("~p", [Host])
        end,

    % Create a unique atom-based ID
    IdString = io_lib:format(
        "connection_~s_~w_~s_~s_~w",
        [HostStr, Port, Database, Username, erlang:system_time()]
    ),
    list_to_atom(lists:flatten(IdString)).

%% @doc Find child ID by process PID
-spec find_child_id_by_pid(Pid) -> {ok, ChildId} | {error, not_found} when
    Pid :: pid(),
    ChildId :: term().
find_child_id_by_pid(Pid) ->
    % Get all children from the supervisor
    Children = supervisor:which_children(?SERVER),
    find_child_id_by_pid_in_list(Pid, Children).

%% @doc Helper function to search for PID in children list
-spec find_child_id_by_pid_in_list(Pid, Children) -> {ok, ChildId} | {error, not_found} when
    Pid :: pid(),
    Children :: [{ChildId, Child, Type, Modules}],
    ChildId :: term(),
    Child :: pid() | undefined,
    Type :: worker | supervisor,
    Modules :: [module()] | dynamic.
find_child_id_by_pid_in_list(_Pid, []) ->
    {error, not_found};
find_child_id_by_pid_in_list(Pid, [{ChildId, Pid, _Type, _Modules} | _Rest]) ->
    {ok, ChildId};
find_child_id_by_pid_in_list(Pid, [_Child | Rest]) ->
    find_child_id_by_pid_in_list(Pid, Rest).

%% @doc Format connection errors to clean public API format
-spec format_connection_error(Reason) -> FormattedReason when
    Reason :: term(),
    FormattedReason :: clickhouse_erl_connection:connection_error().
format_connection_error({protocol_error, Details}) when is_list(Details) ->
    % Convert detailed protocol error to simple format
    case lists:prefix("Unexpected packet type:", Details) of
        true -> {protocol_error, unknown_packet};
        false -> {protocol_error, protocol_error}
    end;
format_connection_error({protocol_error, _}) ->
    {protocol_error, unknown_packet};
format_connection_error({network_error, _} = NetworkError) ->
    NetworkError;
format_connection_error({timeout_error, _} = TimeoutError) ->
    TimeoutError;
format_connection_error({compatibility_error, _} = CompatError) ->
    CompatError;
format_connection_error({encoding_error, _} = EncodingError) ->
    EncodingError;
format_connection_error({decoding_error, _} = DecodingError) ->
    DecodingError;
format_connection_error({server_exception, _} = ServerException) ->
    ServerException;
format_connection_error(_UnknownError) ->
    {protocol_error, unknown_error}.
