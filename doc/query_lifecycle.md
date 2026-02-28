# Query Lifecycle Management Guide

This guide covers query execution, timeout handling, cancellation, and connection state management.

## Basic Query Execution

Execute queries with automatic query ID generation:

```erlang
% Connect to ClickHouse
{ok, Conn} = clickhouse_erl:connect("localhost", 9000).

% Execute a simple query
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT number FROM system.numbers LIMIT 10">>).

% Execute with explicit query ID for tracking
{ok, Result2} = clickhouse_erl:query(Conn, <<"SELECT * FROM users WHERE active = 1">>, #{
    query_id => <<"my-query-123">>
}).

% Clean up
clickhouse_erl:disconnect(Conn).
```

**Key Points**:
- Each connection handles one query at a time
- Query IDs are auto-generated if not provided
- Use explicit query IDs for tracking and cancellation

## Query Timeout Handling

Set timeouts to prevent queries from running indefinitely:

```erlang
% Query with 5-second timeout
case clickhouse_erl:query(Conn, <<"SELECT sleep(3) FROM system.numbers LIMIT 100">>, #{
    query_id => <<"timeout-query">>,
    timeout => 5000  % 5 seconds in milliseconds
}) of
    {ok, Result} ->
        io:format("Query completed: ~p~n", [Result]);
    {error, {timeout_error, query_execution}} ->
        io:format("Query timed out and was automatically cancelled~n")
end.
```

**Timeout Behavior**:
- **Default timeout**: 30 seconds (30000 ms)
- **Custom timeout**: Specify in milliseconds in the options map
- **No timeout**: Use `infinity` (not recommended for production)
- **On timeout**: CLIENT_CANCEL packet is automatically sent to the server
- **Connection state**: Waits for SERVER_END_OF_STREAM before accepting new queries

**Example with different timeout values**:
```erlang
% Short timeout for quick queries
{ok, _} = clickhouse_erl:query(Conn, <<"SELECT 1">>, #{timeout => 1000}).

% Long timeout for complex analytics
{ok, _} = clickhouse_erl:query(Conn, 
    <<"SELECT count(*) FROM large_table GROUP BY category">>, 
    #{timeout => 300000}).  % 5 minutes

% No timeout (use with caution)
{ok, _} = clickhouse_erl:query(Conn, <<"SELECT * FROM infinite_stream">>, 
    #{timeout => infinity}).
```

## Query Cancellation

Cancel long-running queries programmatically:

```erlang
% Start a long-running query in a separate process
QueryId = <<"long-query-456">>,
QueryPid = spawn(fun() ->
    Result = clickhouse_erl:query(Conn, <<"SELECT sleep(3) FROM system.numbers LIMIT 1000">>, #{
        query_id => QueryId
    }),
    io:format("Query result: ~p~n", [Result])
end),

% Cancel the query after 100ms
timer:sleep(100),
ok = clickhouse_erl:cancel_query(Conn, QueryId).

% The query process will receive: {error, {query_cancelled, <<"long-query-456">>}}
```

**Cancellation Behavior**:
- Sends CLIENT_CANCEL packet (Type 3) to the server
- Query returns `{error, {query_cancelled, QueryId}}`
- Connection waits for SERVER_END_OF_STREAM before accepting new queries
- Cancellation is graceful - server completes cleanup before responding

**Error Cases**:
```erlang
% Attempting to cancel when no query is active
case clickhouse_erl:cancel_query(Conn, <<"nonexistent">>) of
    {error, {protocol_error, "No active query to cancel"}} ->
        io:format("No active query~n")
end.

% Attempting to cancel with wrong query ID
case clickhouse_erl:cancel_query(Conn, <<"wrong-id">>) of
    {error, {protocol_error, "Query ID does not match active query"}} ->
        io:format("Query ID mismatch~n")
end.
```

## Concurrent Connections

Each connection handles one query at a time. For concurrent query execution, use multiple connections:

```erlang
% Create a pool of connections
NumConnections = 5,
Connections = [
    begin
        {ok, Conn} = clickhouse_erl:connect("localhost", 9000),
        Conn
    end || _ <- lists:seq(1, NumConnections)
],

% Execute queries concurrently across connections
Queries = [
    <<"SELECT count() FROM table1">>,
    <<"SELECT avg(value) FROM table2">>,
    <<"SELECT max(timestamp) FROM table3">>,
    <<"SELECT min(price) FROM table4">>,
    <<"SELECT sum(quantity) FROM table5">>
],

% Spawn workers for each query
Workers = [
    spawn_monitor(fun() ->
        Result = clickhouse_erl:query(Conn, SQL, #{
            query_id => <<"query-", (integer_to_binary(N))/binary>>
        }),
        exit({result, Result})
    end) || {N, {SQL, Conn}} <- lists:enumerate(lists:zip(Queries, Connections))
],

% Collect results
Results = [
    receive
        {'DOWN', Ref, process, Pid, {result, Result}} ->
            Result
    after 30000 ->
        {error, timeout}
    end || {Pid, Ref} <- Workers
].
```

**Note**: Attempting to execute a second query on a busy connection returns:
```erlang
{error, {protocol_error, "Connection busy with another query"}}
```

**Important Notes**:
- For production use, consider using connection pooling libraries like [poolboy](https://github.com/devinus/poolboy)
- Each connection is an independent gen_server process with fault isolation
- Clean up connections when done to avoid resource leaks

**Example: Handling busy connections with retry**:
```erlang
execute_with_retry(Conn, SQL, MaxRetries) ->
    execute_with_retry(Conn, SQL, MaxRetries, 0).

execute_with_retry(_Conn, _SQL, MaxRetries, MaxRetries) ->
    {error, max_retries_exceeded};
execute_with_retry(Conn, SQL, MaxRetries, Attempt) ->
    case clickhouse_erl:query(Conn, SQL) of
        {error, {protocol_error, "Connection busy with another query"}} ->
            timer:sleep(100),  % Wait before retry
            execute_with_retry(Conn, SQL, MaxRetries, Attempt + 1);
        Result ->
            Result
    end.
```

## Error Handling

All query operations return `{ok, Result}` or `{error, Reason}` tuples:

```erlang
case clickhouse_erl:query(Conn, SQL) of
    {ok, Result} ->
        process_result(Result);

    % Query timeout - automatically cancelled
    {error, {timeout_error, query_execution}} ->
        io:format("Query timed out~n"),
        % Connection is still usable after timeout
        retry_with_longer_timeout();

    % Query cancelled by client
    {error, {query_cancelled, QueryId}} ->
        io:format("Query ~s was cancelled~n", [QueryId]),
        % Connection is still usable after cancellation
        ok;

    % Network errors - connection may be unusable
    {error, {network_error, Reason}} ->
        io:format("Network error: ~p~n", [Reason]),
        % Connection is likely broken, reconnect
        clickhouse_erl:disconnect(Conn),
        reconnect_and_retry();

    % Protocol errors - invalid state or request
    {error, {protocol_error, Details}} ->
        io:format("Protocol error: ~s~n", [Details]),
        % Check if connection is busy or in invalid state
        handle_protocol_error(Details);

    % Server exceptions - SQL errors, permission issues, etc.
    {error, {server_exception, ExceptionInfo}} ->
        ErrorMsg = clickhouse_erl:format_error({server_exception, ExceptionInfo}),
        io:format("Server error: ~s~n", [ErrorMsg]),
        % Connection is still usable, fix the query
        fix_query_and_retry()
end.
```

**Error Type Reference**:

| Error Type | Description | Connection State | Recovery Action |
|------------|-------------|------------------|-----------------|
| `timeout_error` | Query exceeded timeout | Usable after EOF | Increase timeout or optimize query |
| `query_cancelled` | Query cancelled by client | Usable after EOF | Normal cancellation, no action needed |
| `network_error` | TCP/connection failure | Unusable | Reconnect and retry |
| `protocol_error` | Invalid state or request | Depends on error | Check connection state, may need reconnect |
| `server_exception` | SQL error or server issue | Usable | Fix query or check permissions |

**Comprehensive Error Handling Example**:
```erlang
execute_query_with_handling(Conn, SQL) ->
    Options = #{
        query_id => generate_query_id(),
        timeout => 30000
    },
    
    case clickhouse_erl:query(Conn, SQL, Options) of
        {ok, Result} ->
            {ok, Result};
            
        {error, {timeout_error, _}} ->
            ?LOG_WARNING("Query timeout, retrying with longer timeout", #{sql => SQL}),
            retry_with_timeout(Conn, SQL, 60000);
            
        {error, {network_error, _} = Error} ->
            ?LOG_ERROR("Network error, connection lost", #{error => Error}),
            {error, connection_lost};
            
        {error, {server_exception, ExceptionInfo}} ->
            Code = maps:get(code, ExceptionInfo, unknown),
            case Code of
                60 -> % UNKNOWN_TABLE
                    ?LOG_ERROR("Table does not exist", #{sql => SQL}),
                    {error, table_not_found};
                62 -> % SYNTAX_ERROR
                    ?LOG_ERROR("SQL syntax error", #{sql => SQL}),
                    {error, syntax_error};
                _ ->
                    ?LOG_ERROR("Server exception", #{
                        code => Code,
                        message => maps:get(message, ExceptionInfo, <<>>)
                    }),
                    {error, server_error}
            end;
            
        {error, Reason} ->
            ?LOG_ERROR("Unexpected error", #{reason => Reason}),
            {error, Reason}
    end.
```
