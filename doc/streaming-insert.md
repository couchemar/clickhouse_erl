# Streaming Insert

Send large datasets to ClickHouse in multiple blocks without loading everything into memory. Two patterns are available:

- **Pull-based**: The engine calls your callback repeatedly to get data blocks
- **Push-based**: You explicitly push data blocks at your own pace

Both patterns provide natural backpressure — each block is flushed to the network before the next one is accepted.

## Pull-Based (Callback-Driven)

Use `streaming_insert/3,4` with an `on_input` callback. The engine invokes the callback repeatedly until it returns `{done, Acc}`.

```erlang
Columns = [
    #{name => <<"id">>, type => <<"UInt32">>},
    #{name => <<"name">>, type => <<"String">>}
],

Callback = fun(Acc) ->
    case Acc < 10 of
        true ->
            Batch = generate_batch(Acc),
            {ok, Batch, Acc + 1};
        false ->
            {done, Acc}
    end
end,

{ok, Result} = clickhouse_erl:streaming_insert(Conn,
    <<"INSERT INTO my_table (id, name) VALUES">>,
    #{on_input => Callback, columns => Columns, initial_accumulator => 0}).

#{rows_inserted := Rows, blocks_sent := Blocks, elapsed_time := Ms} = Result.
```

### Callback Contract

The callback receives the current accumulator and must return one of:

| Return Value | Behavior |
|---|---|
| `{ok, ColumnData, NewAcc}` | Send the data block, continue with NewAcc |
| `{done, FinalAcc}` | Stop streaming, send final blank block |
| `{error, Reason}` | Abort, returns `{error, {callback_error, Reason}}` |

If the callback crashes, the engine catches it and returns `{error, {callback_crashed, {Class, Reason, Stacktrace}}}`.

Empty blocks (zero rows) are skipped without incrementing the block count.

### Options

| Key | Type | Default | Description |
|---|---|---|---|
| `on_input` | `fun/1` | required | Callback function |
| `columns` | `[map()]` | required | Column definitions with empty data lists |
| `initial_accumulator` | `term()` | `#{}` | Initial value passed to first callback |

Extra options (4th argument):

| Key | Type | Default | Description |
|---|---|---|---|
| `timeout` | `pos_integer() \| infinity` | `30000` | Total operation timeout in ms |
| `compression` | `lz4 \| zstd \| disabled` | connection default | Compression method |

## Push-Based (Session-Driven)

Use `start_streaming_insert/3,4` + `send_data/3` + `finish_streaming_insert/2` for explicit control over when data is sent.

```erlang
Columns = [
    #{name => <<"id">>, type => <<"UInt32">>},
    #{name => <<"name">>, type => <<"String">>}
],

{ok, StreamRef} = clickhouse_erl:start_streaming_insert(Conn,
    <<"INSERT INTO my_table (id, name) VALUES">>,
    #{columns => Columns}),

%% Send blocks at your own pace
ok = clickhouse_erl:send_data(Conn, StreamRef, [
    #{name => <<"id">>, data => [1, 2, 3]},
    #{name => <<"name">>, data => [<<"a">>, <<"b">>, <<"c">>]}
]),

ok = clickhouse_erl:send_data(Conn, StreamRef, [
    #{name => <<"id">>, data => [4, 5]},
    #{name => <<"name">>, data => [<<"d">>, <<"e">>]}
]),

{ok, Result} = clickhouse_erl:finish_streaming_insert(Conn, StreamRef).
```

### Session Lifecycle

1. `start_streaming_insert/3,4` — Opens the session, returns `{ok, StreamRef}`
2. `send_data/3` — Sends one data block, returns `ok` (call as many times as needed)
3. `finish_streaming_insert/2` — Sends final blank block, waits for server confirmation

The connection is busy during an active session. Other queries are rejected with `{error, {connection_error, query_in_progress}}`.

## Error Handling

### Pull-Based Errors

| Error | Cause |
|---|---|
| `{error, {validation_error, missing_on_input_callback}}` | No `on_input` in options |
| `{error, {validation_error, empty_columns}}` | Empty columns list |
| `{error, {callback_error, Reason}}` | Callback returned `{error, Reason}` |
| `{error, {callback_crashed, {Class, Reason, Stack}}}` | Callback raised an exception |
| `{error, {invalid_callback_return, Term}}` | Callback returned unexpected term |
| `{error, {validation_error, {row_count_mismatch, _}}}` | Columns have different row counts |
| `{error, {validation_error, {column_name_mismatch, _, _}}}` | Column names don't match definitions |
| `{error, {server_exception, Info}}` | ClickHouse server error |
| `{error, {timeout_error, streaming_insert}}` | Operation exceeded timeout |

### Push-Based Errors

| Error | Cause |
|---|---|
| `{error, {validation_error, empty_columns}}` | Empty columns in start |
| `{error, {validation_error, no_active_streaming_session}}` | No active session |
| `{error, {validation_error, invalid_stream_ref}}` | Wrong StreamRef |
| `{error, {streaming_error, session_failed}}` | Session already failed |
| `{error, {server_exception, Info}}` | ClickHouse server error |
| `{error, {timeout_error, streaming_insert}}` | Session exceeded timeout |
| `{error, {query_cancelled, QueryId}}` | Session was cancelled |

### Connection Recovery

After any error, the connection returns to `ready` state (except network errors which transition to `error`). You can execute new queries without reconnecting.

For push-based mode, always call `finish_streaming_insert/2` to clean up the session, even after errors.

## Compression

Streaming inserts respect the connection's compression settings. Each block is compressed independently.

```erlang
%% With LZ4 compression
{ok, Result} = clickhouse_erl:streaming_insert(Conn, SQL, Opts, #{compression => lz4}).

%% With ZSTD compression
{ok, Result} = clickhouse_erl:streaming_insert(Conn, SQL, Opts, #{compression => zstd}).

%% Compression disabled
{ok, Result} = clickhouse_erl:streaming_insert(Conn, SQL, Opts, #{compression => disabled}).
```

## Backpressure

Both patterns provide natural backpressure:

- **Pull-based**: Each block is flushed to TCP before the next callback invocation
- **Push-based**: `send_data/3` blocks until the data is flushed to TCP

This means memory usage stays bounded — at most one block's worth of data is held in memory at any time, regardless of total dataset size.

## Timeout and Cancellation

### Timeout

Set a timeout for the entire operation:

```erlang
%% Pull-based: timeout in ExtraOptions
clickhouse_erl:streaming_insert(Conn, SQL, Opts, #{timeout => 60000}).

%% Push-based: timeout in ExtraOptions
clickhouse_erl:start_streaming_insert(Conn, SQL, PushOpts, #{timeout => 60000}).
```

### Cancellation

```erlang
%% Cancel during push-based session
ok = clickhouse_erl:cancel_query(Conn).
%% Subsequent send_data returns {error, {query_cancelled, _}}
```

Pull-based streaming runs synchronously inside the gen_server — `cancel_query` cannot interrupt it. Use timeout for pull-based abort.

## Real-World Example: Streaming from ETS

A common pattern is streaming data from an ETS table to ClickHouse in batches. This avoids loading the entire dataset into memory.

### Setup

```erlang
%% Create ETS table with sample data
ets:new(my_data, [named_table, ordered_set, public]),
lists:foreach(fun(Id) ->
    Name = iolist_to_binary(io_lib:format("user_~4..0B", [Id])),
    Score = rand:uniform(10000) / 100.0,
    ets:insert(my_data, {Id, Name, Score})
end, lists:seq(1, 10000)).

%% Column definitions (schema only — no data key needed)
Columns = [
    #{name => <<"id">>, type => <<"UInt32">>},
    #{name => <<"name">>, type => <<"String">>},
    #{name => <<"score">>, type => <<"Float64">>}
].

SQL = <<"INSERT INTO users (id, name, score) VALUES">>.
```

### ETS Batch Reader

```erlang
%% Read up to BatchSize rows from ETS starting at Key.
read_batch(Key, BatchSize) ->
    read_batch(Key, BatchSize, [], [], []).

read_batch('$end_of_table', _, Ids, Names, Scores) ->
    {lists:reverse(Ids), lists:reverse(Names), lists:reverse(Scores), '$end_of_table'};
read_batch(_Key, 0, Ids, Names, Scores) ->
    {lists:reverse(Ids), lists:reverse(Names), lists:reverse(Scores), _Key};
read_batch(Key, N, Ids, Names, Scores) ->
    [{Id, Name, Score}] = ets:lookup(my_data, Key),
    Next = ets:next(my_data, Key),
    read_batch(Next, N - 1, [Id | Ids], [Name | Names], [Score | Scores]).
```

### Pull-Based: Callback Walks ETS

The accumulator is the next ETS key to read. The callback reads a batch and returns it.

```erlang
BatchSize = 500,

Callback = fun(Key) ->
    case Key of
        '$end_of_table' ->
            {done, '$end_of_table'};
        _ ->
            {Ids, Names, Scores, NextKey} = read_batch(Key, BatchSize),
            case Ids of
                [] ->
                    {done, '$end_of_table'};
                _ ->
                    {ok, [
                        #{name => <<"id">>, data => Ids},
                        #{name => <<"name">>, data => Names},
                        #{name => <<"score">>, data => Scores}
                    ], NextKey}
            end
    end
end,

{ok, Result} = clickhouse_erl:streaming_insert(Conn, SQL, #{
    on_input => Callback,
    columns => Columns,
    initial_accumulator => ets:first(my_data)
}).
%% => #{rows_inserted => 10000, blocks_sent => 20, elapsed_time => 25}
```

### Push-Based: Explicit Batch Loop

Useful when you want to interleave other work between batches, or when data arrives from an external source.

```erlang
{ok, StreamRef} = clickhouse_erl:start_streaming_insert(Conn, SQL, #{columns => Columns}),

%% Walk ETS and push batches
push_loop(Conn, StreamRef, ets:first(my_data), 500),

{ok, Result} = clickhouse_erl:finish_streaming_insert(Conn, StreamRef).
%% => #{rows_inserted => 10000, blocks_sent => 20, elapsed_time => 20}

%% Helper
push_loop(_Conn, _StreamRef, '$end_of_table', _BatchSize) -> ok;
push_loop(Conn, StreamRef, Key, BatchSize) ->
    {Ids, Names, Scores, NextKey} = read_batch(Key, BatchSize),
    case Ids of
        [] -> ok;
        _ ->
            ok = clickhouse_erl:send_data(Conn, StreamRef, [
                #{name => <<"id">>, data => Ids},
                #{name => <<"name">>, data => Names},
                #{name => <<"score">>, data => Scores}
            ]),
            push_loop(Conn, StreamRef, NextKey, BatchSize)
    end.
```
