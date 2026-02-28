# ClickHouse Erlang Client Usage Guide

This guide provides an overview of how to use the `clickhouse_erl` library to interact with a ClickHouse server using the native binary protocol.

## Connection Management

### Connecting

To establish a connection, use `clickhouse_erl:connect/2` or `clickhouse_erl:connect/3`.

```erlang
% Default connection (localhost:9000, user: default, database: default)
{ok, Conn} = clickhouse_erl:connect("localhost", 9000).

% Connection with options
Options = #{
    database => <<"my_database">>,
    username => <<"my_user">>,
    password => <<"my_password">>,
    timeout => 5000 % Connection timeout in ms
},
{ok, Conn} = clickhouse_erl:connect("localhost", 9000, Options).
```

### Disconnecting

```erlang
ok = clickhouse_erl:disconnect(Conn).
```

## Running Queries

### SELECT Queries

Use `clickhouse_erl:query/2` or `clickhouse_erl:query/3` for SELECT and other non-INSERT queries.

```erlang
SQL = <<"SELECT name, age FROM users WHERE age > 21">>,
{ok, Result} = clickhouse_erl:query(Conn, SQL).

% Accessing results
#{
    columns := Columns,
    rows := Rows,
    statistics := Stats
} = Result.
```

### INSERT Queries

For INSERT queries, use `clickhouse_erl:insert/3` or `clickhouse_erl:insert/4`. Data must be provided in a column-oriented format.

```erlang
SQL = <<"INSERT INTO users (name, age) VALUES">>,
Input = [
    #{name => <<"name">>, type => <<"String">>, data => [<<"Alice">>, <<"Bob">>]},
    #{name => <<"age">>, type => <<"UInt32">>, data => [25, 30]}
],
{ok, Result} = clickhouse_erl:insert(Conn, SQL, Input).

% Result contains metadata about the operation
#{
    rows_inserted := 2,
    elapsed_time := DurationMs
} = Result.
```

**Note**: For comprehensive INSERT documentation including all supported data types, error handling, and best practices, see the [INSERT Guide](insert_guide.md).

## Streaming Query Results

For large result sets, streaming mode enables incremental data processing without loading all data into memory. This is essential for handling datasets larger than available RAM.

### Basic Streaming

Provide an `on_data` callback to process each data block as it arrives:

```erlang
PreparedRequest = #{
    sql => <<"SELECT * FROM large_table">>,
    query_id => <<"streaming-query">>,
    on_data => fun(DataBlock, Acc) ->
        % Process data block incrementally
        RowCount = maps:get(rows, DataBlock, 0),
        NewCount = Acc + RowCount,
        io:format("Processed ~p rows (total: ~p)~n", [RowCount, NewCount]),
        {ok, NewCount}
    end,
    initial_accumulator => 0
},
{ok, Result} = clickhouse_erl_connection:query(Conn, PreparedRequest),
TotalRows = maps:get(data, Result).
```

### Callback Patterns

#### Accumulating Results

Collect processed data in the accumulator:

```erlang
on_data => fun(DataBlock, Acc) ->
    % Extract specific columns
    Columns = maps:get(column_data, DataBlock, []),
    Values = extract_values(Columns),
    {ok, [Values | Acc]}
end,
initial_accumulator => []
```

#### Writing to External Storage

Stream data directly to files or databases:

```erlang
on_data => fun(DataBlock, FileHandle) ->
    Rows = format_rows(DataBlock),
    ok = file:write(FileHandle, Rows),
    {ok, FileHandle}
end,
initial_accumulator => FileHandle
```

#### Filtering and Transformation

Process only relevant data:

```erlang
on_data => fun(DataBlock, Acc) ->
    FilteredRows = filter_rows(DataBlock, fun(Row) -> 
        Row > 100 
    end),
    {ok, FilteredRows ++ Acc}
end,
initial_accumulator => []
```

### Callback Function Signatures

#### Data Callback (Required for Streaming)

```erlang
fun(DataBlock :: map(), Accumulator :: term()) ->
    {ok, NewAccumulator :: term()} | {error, Reason :: term()}
```

The `DataBlock` map contains:
- `rows` - Number of rows in this block
- `columns` - Number of columns
- `column_data` - List of column data maps with `name`, `type`, and `data` fields

#### Optional Monitoring Callbacks

Monitor query progress and profiling information:

```erlang
PreparedRequest = #{
    sql => <<"SELECT * FROM large_table">>,
    query_id => <<"monitored-query">>,
    on_data => DataCallback,
    on_progress => fun(ProgressInfo) ->
        RowsRead = maps:get(rows_read, ProgressInfo, 0),
        io:format("Progress: ~p rows read~n", [RowsRead]),
        ok
    end,
    on_profile => fun(ProfileInfo) ->
        io:format("Profile: ~p~n", [ProfileInfo]),
        ok
    end
}.
```

### Result Format

Streaming mode returns the final accumulator under the `data` key:

```erlang
{ok, #{
    data => FinalAccumulator,
    statistics => #{elapsed_time => Milliseconds}
}}
```

Batch mode (no callback) returns accumulated data:

```erlang
{ok, #{
    data => #{columns => [...], rows => [...]},
    statistics => #{elapsed_time => Milliseconds}
}}
```

### Error Handling

#### Callback Errors

If a callback returns `{error, Reason}`, the query terminates immediately:

```erlang
on_data => fun(DataBlock, Acc) ->
    case validate_data(DataBlock) of
        ok -> {ok, [DataBlock | Acc]};
        {error, Reason} -> {error, {validation_failed, Reason}}
    end
end
```

The query returns:
```erlang
{error, {callback_failed, {validation_failed, Reason}}}
```

#### Callback Crashes

If a callback crashes, the error is caught and wrapped:

```erlang
{error, {callback_crashed, {Class, Reason, Stacktrace}}}
```

#### Invalid Returns

Callbacks must return `{ok, NewAcc}` or `{error, Reason}`. Other values cause:

```erlang
{error, {invalid_callback_return, ReturnValue}}
```

The connection remains usable after all callback errors.

### Performance Considerations

#### Memory Efficiency

Streaming mode maintains constant memory usage regardless of result set size:

```erlang
% Process 10 million rows with constant memory
PreparedRequest = #{
    sql => <<"SELECT * FROM huge_table">>,
    on_data => fun(DataBlock, Count) ->
        process_and_discard(DataBlock),
        {ok, Count + maps:get(rows, DataBlock, 0)}
    end,
    initial_accumulator => 0
}
```

#### Callback Performance

Callbacks execute synchronously in the connection process. Keep them fast:

- ✅ Quick transformations and filtering
- ✅ Writing to buffered I/O
- ✅ Accumulating lightweight summaries
- ❌ Expensive computations (spawn separate process)
- ❌ Blocking network calls (use async patterns)
- ❌ Large memory allocations

#### Blocking Behavior

A blocking callback only affects its own connection, not others:

```erlang
% Connection 1: Blocking callback
on_data => fun(DataBlock, Acc) ->
    timer:sleep(1000),  % Blocks only this connection
    {ok, Acc}
end

% Connection 2: Continues normally
% Other connections are unaffected
```

### Troubleshooting

#### Callback Not Invoked

If your callback is never called, check:

1. **Query returns no data**: INSERT, DDL, and some queries produce no DATA packets
2. **Callback arity**: Must be exactly 2 for `on_data`
3. **Query execution**: Verify query completes without errors

```erlang
% Queries that don't invoke callbacks:
PreparedRequest = #{
    sql => <<"CREATE TABLE test (id UInt32)">>,  % DDL - no data
    on_data => Callback  % Never invoked
}
```

#### Memory Still Growing

If memory grows despite streaming:

1. **Check accumulator**: Ensure you're not accumulating all data
2. **Verify callback**: Confirm data is processed and discarded
3. **Monitor process**: Use `erlang:process_info(Pid, memory)`

```erlang
% ❌ Bad: Accumulating all data
on_data => fun(DataBlock, Acc) ->
    {ok, [DataBlock | Acc]}  % Grows with result size
end

% ✅ Good: Constant memory
on_data => fun(DataBlock, Count) ->
    process_and_discard(DataBlock),
    {ok, Count + 1}  % Only tracks count
end
```

#### Callback Errors

If callbacks fail unexpectedly:

1. **Add error handling**: Wrap risky operations in try...catch
2. **Validate inputs**: Check DataBlock structure before processing
3. **Log errors**: Use structured logging for debugging

```erlang
on_data => fun(DataBlock, Acc) ->
    try
        Result = process_data(DataBlock),
        {ok, [Result | Acc]}
    catch
        Class:Reason:Stack ->
            ?LOG_ERROR("Callback failed", #{
                class => Class,
                reason => Reason,
                stacktrace => Stack
            }),
            {error, {processing_failed, Reason}}
    end
end
```

#### Connection Hangs

If a connection becomes unresponsive:

1. **Check callback blocking**: Ensure callbacks complete quickly
2. **Verify timeout**: Set appropriate query timeout
3. **Monitor connection**: Use separate process for long operations

```erlang
% Set timeout to prevent indefinite blocking
PreparedRequest = #{
    sql => <<"SELECT * FROM large_table">>,
    timeout => 60000,  % 60 second timeout
    on_data => Callback
}
```

## Timeout and Cancellation

All query functions allow specifying a timeout in milliseconds.

```erlang
Options = #{timeout => 30000},
{error, {timeout_error, _}} = clickhouse_erl:query(Conn, SQL, Options).
```

Active queries can be cancelled using their `QueryId`:

```erlang
ok = clickhouse_erl:cancel_query(Conn, <<"my_query_id">>).
```
