%% @doc Connection state record shared between clickhouse_erl_connection
%% and its test files. Single source of truth — no more duplicate definitions.

-record(connection_state, {
    socket :: gen_tcp:socket() | undefined,
    host :: string() | inet:ip_address(),
    port :: inet:port_number(),
    options :: map(),
    state :: connecting | ready | error,
    server_info :: map() | undefined,
    error_reason :: term() | undefined,
    active_queries :: map(),
    active_query_state :: map() | undefined,
    negotiated_version :: non_neg_integer() | undefined,
    compression_opts :: map() | undefined,
    %% Event-driven parser state
    parser_state = undefined :: map() | undefined
}).
