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


## Streaming Callbacks

Process query results incrementally using the `on_data` callback, avoiding accumulation of the entire result set in memory. This is the recommended approach for large result sets.

### Callback Signature

```erlang
fun(Event, Acc) -> {ok, NewAcc}
```

Where `Event` is one of:
- `{data, #{name => ColumnName, value => Value}}` — a single column value, tagged with the column name
- `'end'` — sent when the query completes (end of stream), use to finalize results

### Basic Usage

Pass `on_data` and `initial_accumulator` in the query options map:

```erlang
Callback = fun
    ({data, #{name := Name, value := Value}}, Acc) ->
        Existing = maps:get(Name, Acc, []),
        {ok, Acc#{Name => [Value | Existing]}};
    ('end', Acc) ->
        {ok, maps:map(fun(_K, V) -> lists:reverse(V) end, Acc)}
end,

{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT name, salary FROM employees ORDER BY name">>, #{
    on_data => Callback,
    initial_accumulator => #{}
}).

%% Result: #{data => #{<<"name">> => [<<"Alice">>, <<"Bob">>], <<"salary">> => [50000, 60000]}}
DataMap = maps:get(data, Result).
```

### How It Works

ClickHouse sends data column-by-column (all values for column 1, then all values for column 2, etc.). The streaming callback receives each value tagged with its column name as it arrives from the wire. No intermediate accumulation occurs inside the client — values are dispatched directly to your callback.

The `'end'` event fires when the server sends `END_OF_STREAM`, giving you a chance to finalize your accumulator (e.g., reverse accumulated lists).

### Result Format

- **Streaming mode** (`on_data` provided): Returns `#{data => FinalAccumulator}` where `FinalAccumulator` is the value returned by your callback's `'end'` clause.
- **Batch mode** (no `on_data`): Returns the standard column-oriented result with `#{data => #{columns => [...], rows => [[...], ...]}}`.

### Counting Values

```erlang
Callback = fun
    ({data, #{name := _Name, value := _Value}}, Count) ->
        {ok, Count + 1};
    ('end', Count) ->
        {ok, Count}
end,

{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM large_table">>, #{
    on_data => Callback,
    initial_accumulator => 0
}).

TotalValues = maps:get(data, Result).
```

### Custom Aggregation

```erlang
Callback = fun
    ({data, #{name := <<"salary">>, value := V}}, Acc) ->
        {ok, Acc#{count => maps:get(count, Acc) + 1, sum => maps:get(sum, Acc) + V}};
    ({data, _}, Acc) ->
        {ok, Acc};
    ('end', Acc) ->
        {ok, Acc}
end,

{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT name, salary FROM employees">>, #{
    on_data => Callback,
    initial_accumulator => #{count => 0, sum => 0}
}).
```

### Error Handling

If your callback returns `{error, Reason}` or crashes, the query fails with a descriptive error:

```erlang
%% Callback crash → {error, {callback_crashed, {Class, Reason, Stacktrace}}}
%% Callback error → {error, {callback_failed, Reason}}
%% Invalid return → {error, {invalid_callback_return, ReturnValue}}
```

### Supported Types

Streaming callbacks support all scalar types (String, integers, floats, decimals, dates, UUIDs, etc.) and all composite types (Array, Tuple, Nullable, LowCardinality, Map).

### When to Use Streaming vs Batch

| Scenario | Mode | Reason |
|----------|------|--------|
| Large result sets (10k+ rows) | Streaming | Constant memory usage |
| Custom aggregation during query | Streaming | No intermediate storage |
| Small result sets | Batch | Simpler, returns complete result |


## Internal Architecture: Event-Driven Parser

This section describes how query responses are processed internally. Understanding this is useful for debugging, contributing, or reasoning about performance characteristics.

### Data Flow

When a query is executed, the server sends response packets over TCP. The client processes them through this pipeline:

```
TCP Socket
    │
    ▼
handle_info({tcp, Socket, Data}, State)
    │
    ▼
clickhouse_erl_parser:parse(Data, ParserState)
    │
    ▼
{EventList, NewParserState}
    │
    ▼
lists:foldl(fun process_event/2, AccState, EventList)
    │
    ▼
Updated AccState (columns, callback results, etc.)
```

1. Raw TCP data arrives at the connection process (`clickhouse_erl_connection`)
2. Data is passed directly to `clickhouse_erl_parser:parse/2` with the current parser state
3. The parser emits a list of events and an updated parser state
4. Events are processed sequentially via `lists:foldl/3` to update the accumulator state
5. The updated parser state is stored in the connection state for the next TCP recv

### Event Types

The parser emits four types of events:

- `{start, PacketType}` — a new packet has begun (e.g., `server_data`, `server_exception`)
- `{data, FieldName, Value}` — a parsed field within the current packet
- `{'end', PacketType}` — the current packet is complete
- `need_more` — the parser needs more TCP data to continue (always the last event in the list)

For a DATA packet, the event sequence looks like:

```erlang
{start, server_data}
{data, temp_table_name, <<"">>}
{data, block_info, #{is_overflows => false, bucket_num => -1}}
{data, num_columns, 2}
{data, num_rows, 3}
{data, column, #{name => <<"id">>, type => <<"UInt64">>}}
{data, column_value, 1}
{data, column_value, 2}
{data, column_value, 3}
{data, column, #{name => <<"name">>, type => <<"String">>}}
{data, column_value, <<"Alice">>}
{data, column_value, <<"Bob">>}
{data, column_value, <<"Charlie">>}
{'end', server_data}
```

ClickHouse sends data column-by-column (all values for column 1, then all values for column 2), not row-by-row.

### Incomplete Packets and Buffering

The parser manages its own internal buffer. When a TCP segment contains only part of a packet:

1. The parser processes as much as it can and emits any complete events
2. It buffers the unparsed remainder internally in its state
3. It emits `need_more` as the last event
4. On the next TCP recv, the connection passes new data to the parser, which prepends its buffer automatically

There is no connection-level buffer — the parser is the single source of truth for buffered data. This eliminates double-buffering and simplifies state management.

### Compression Handling

When compression is enabled on the connection, the server wraps block data (after the temp table name) in a compressed block:

```
[temp_table_name] [checksum: 16 bytes] [method: 1 byte] [compressed_size: 4 bytes] [original_size: 4 bytes] [compressed_payload]
```

The block parser handles this transparently:

1. After parsing the temp table name, it checks if compression is enabled (from parser state)
2. If enabled, it calls `clickhouse_erl_compression:decompress/1` on the remaining data
3. The decompressed bytes are then parsed normally (block info, columns, values)
4. If the compressed block is incomplete (not enough TCP data yet), the parser returns `need_more`

Compression is configured at connection time and applies to all DATA, TOTALS, EXTREMES, and PROFILE_EVENTS packets:

```erlang
{ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{compression => lz4}).
```

See the [Compression Guide](compression.md) for details on methods and configuration.

### Streaming vs Batch Mode Internals

The connection's event fold function (`lists:foldl/3`) maintains an accumulator state that tracks parsing context. The behavior differs based on whether `on_data` is provided in query options:

- **Batch mode** (default): Column values are accumulated in an internal map. When `end_of_stream` arrives, the complete result is assembled and returned to the caller.
- **Streaming mode** (`on_data` provided): Each `{data, column_value, Value}` event dispatches to the user's callback as `{data, #{name => ColumnName, value => Value}}`. When `end_of_stream` arrives, the callback receives `'end'` for finalization. No intermediate accumulation occurs inside the client.
