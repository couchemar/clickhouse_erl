# Streaming Query Results

## How ClickHouse Sends Data

ClickHouse sends query results in **blocks**. Each block contains multiple rows but is encoded **column-by-column** (all values for column 1, then all values for column 2, etc.). A typical query sends multiple blocks (~65K rows each, controlled by `max_block_size` setting).

This means:
- You cannot get row 1 until the entire block is decoded
- But you DON'T need the entire result set in memory — just one block at a time
- Memory usage is bounded to one block regardless of total result size

## API Overview

```erlang
%% Default (batch mode) — accumulates all data, returns #{columns, rows}
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM big_table">>).
#{data := #{columns := Columns, rows := Rows}} = Result.

%% Streaming mode — process data as it arrives via on_data callback
{ok, Result} = clickhouse_erl:query(Conn, SQL, #{
    on_data => fun(Event, Acc) -> {ok, NewAcc} end,
    initial_accumulator => InitialState
}).
```

## The `on_data` Callback

The callback receives events as the parser decodes each value:

```erlang
fun(Event, Acc) -> {ok, NewAcc}
```

Events:
- `{data, #{name => ColName, type => ColType, value => Value}}` — one decoded value
- `block_end` — all column values for the current block have been dispatched (non-empty blocks only)
- `'end'` — query complete, return final accumulator

**Important:** Values arrive column-by-column within each block, NOT row-by-row. For a block with 3 columns and 100 rows, you get: all 100 values of col1, then all 100 values of col2, then all 100 values of col3.

## Common Patterns

### Pattern 1: Count rows without storing data

```erlang
{ok, #{data := Count}} = clickhouse_erl:query(Conn, SQL, #{
    on_data => fun
        ({data, _}, Acc) -> {ok, Acc + 1};
        ('end', Acc) -> {ok, Acc}
    end,
    initial_accumulator => 0
}).
```

### Pattern 2: Accumulate specific columns

```erlang
{ok, #{data := Ids}} = clickhouse_erl:query(Conn,
    <<"SELECT id FROM users WHERE active = 1">>, #{
    on_data => fun
        ({data, #{name := <<"id">>, value := Id}}, Acc) -> {ok, [Id | Acc]};
        ({data, _}, Acc) -> {ok, Acc};
        ('end', Acc) -> {ok, lists:reverse(Acc)}
    end,
    initial_accumulator => []
}).
```

### Pattern 3: Group by column name

```erlang
{ok, #{data := ColumnMap}} = clickhouse_erl:query(Conn, SQL, #{
    on_data => fun
        ({data, #{name := Name, value := Value}}, Acc) ->
            Existing = maps:get(Name, Acc, []),
            {ok, Acc#{Name => [Value | Existing]}};
        ('end', Acc) ->
            {ok, maps:map(fun(_K, V) -> lists:reverse(V) end, Acc)}
    end,
    initial_accumulator => #{}
}).
```

### Pattern 4: Send each value to another process

```erlang
Sink = spawn(fun sink_loop/0),
{ok, _} = clickhouse_erl:query(Conn, SQL, #{
    on_data => fun
        ({data, #{value := Value}}, Acc) ->
            Sink ! {value, Value},
            {ok, Acc};
        ('end', Acc) ->
            Sink ! done,
            {ok, Acc}
    end,
    initial_accumulator => ok
}).
```

### Pattern 5: Bounded-memory row transposition using block_end

Since data arrives column-by-column within each block, you can use the `block_end` event to transpose accumulated column data into rows at block boundaries, then discard the buffer. This keeps memory bounded to one block regardless of total result size:

```erlang
{ok, #{data := AllRows}} = clickhouse_erl:query(Conn,
    <<"SELECT id, name, score FROM users">>, #{
    on_data => fun
        ({data, #{name := Name, value := Value}}, #{cols := Cols} = Acc) ->
            Existing = maps:get(Name, Cols, []),
            {ok, Acc#{cols => Cols#{Name => [Value | Existing]}}};
        (block_end, #{cols := Cols, rows := Rows}) ->
            %% Transpose this block's columns into rows and flush
            IdList = lists:reverse(maps:get(<<"id">>, Cols, [])),
            NameList = lists:reverse(maps:get(<<"name">>, Cols, [])),
            ScoreList = lists:reverse(maps:get(<<"score">>, Cols, [])),
            BlockRows = lists:zip3(IdList, NameList, ScoreList),
            {ok, #{cols => #{}, rows => Rows ++ BlockRows}};
        ('end', #{rows := Rows}) ->
            {ok, Rows}
    end,
    initial_accumulator => #{cols => #{}, rows => []}
}).
```

This approach bounds memory to one block's worth of column data at a time, regardless of how many blocks the query returns.

### Pattern 6: Build rows from columnar data (manual transpose, unbounded)

Since data arrives column-by-column, building rows requires buffering:

```erlang
{ok, #{data := Rows}} = clickhouse_erl:query(Conn,
    <<"SELECT id, name, score FROM users">>, #{
    on_data => fun
        ({data, #{name := Name, value := Value}}, Acc) ->
            Cols = maps:get(columns, Acc, #{}),
            Existing = maps:get(Name, Cols, []),
            {ok, Acc#{columns => Cols#{Name => [Value | Existing]}}};
        ('end', #{columns := Cols}) ->
            %% Transpose columns to rows
            IdList = lists:reverse(maps:get(<<"id">>, Cols, [])),
            NameList = lists:reverse(maps:get(<<"name">>, Cols, [])),
            ScoreList = lists:reverse(maps:get(<<"score">>, Cols, [])),
            Rows = lists:zip3(IdList, NameList, ScoreList),
            {ok, Rows}
    end,
    initial_accumulator => #{columns => #{}}
}).
```

**Note:** This buffers the entire result. For bounded memory, use Pattern 5 (block_end-based transposition), the default batch mode, or process data column-by-column (patterns 1-4).

## When to Use Streaming vs Batch

| Scenario | Use |
|----------|-----|
| Small results (< 100K rows) | Batch mode (default) — simpler |
| Large results, need all rows as list | Batch mode — built-in transpose |
| Large results, aggregate only (count, sum, max) | Streaming — O(1) memory |
| Large results, filter/transform per value | Streaming — avoids full accumulation |
| Large results, pipe to another process/socket | Streaming — immediate forwarding |
| Need rows in order | Batch mode or streaming with `block_end` — streaming gives block-aligned rows |

## Memory Characteristics

- **Batch mode**: Buffers entire result set (all blocks). Memory = O(total rows × columns).
- **Streaming mode**: The callback processes values as they're decoded from each block. If your callback doesn't accumulate (e.g., just forwards values), memory stays at O(block size). If it accumulates, memory depends on what you store.

## Integration with Streaming Insert

A common pattern: stream data FROM one ClickHouse table and INSERT into another (or the same cluster):

```erlang
%% Stream rows out and push them into another table
{ok, StreamRef} = clickhouse_erl:start_streaming_insert(
    DestConn, <<"INSERT INTO dest_table (id, name) VALUES">>,
    #{columns => [
        #{name => <<"id">>, type => <<"UInt64">>},
        #{name => <<"name">>, type => <<"String">>}
    ]}
),

%% Query source, accumulate batches, push when batch is full
BatchSize = 1000,
{ok, _} = clickhouse_erl:query(SourceConn, <<"SELECT id, name FROM source_table">>, #{
    on_data => fun
        ({data, #{name := Name, value := Value}}, #{batch := Batch, count := N} = Acc) ->
            NewBatch = Batch#{Name => [Value | maps:get(Name, Batch, [])]},
            case N + 1 >= BatchSize of
                true ->
                    %% Flush batch
                    ok = clickhouse_erl:send_data(DestConn, StreamRef, [
                        #{name => <<"id">>, data => lists:reverse(maps:get(<<"id">>, NewBatch))},
                        #{name => <<"name">>, data => lists:reverse(maps:get(<<"name">>, NewBatch))}
                    ]),
                    {ok, #{batch => #{}, count => 0}};
                false ->
                    {ok, Acc#{batch => NewBatch, count => N + 1}}
            end;
        ('end', #{batch := Batch}) ->
            %% Flush remaining
            case maps:get(<<"id">>, Batch, []) of
                [] -> ok;
                _ ->
                    ok = clickhouse_erl:send_data(DestConn, StreamRef, [
                        #{name => <<"id">>, data => lists:reverse(maps:get(<<"id">>, Batch))},
                        #{name => <<"name">>, data => lists:reverse(maps:get(<<"name">>, Batch))}
                    ])
            end,
            {ok, done}
    end,
    initial_accumulator => #{batch => #{}, count => 0}
}),

{ok, Result} = clickhouse_erl:finish_streaming_insert(DestConn, StreamRef).
```

## Key Points for AI Agents

1. **Don't expect row-by-row streaming** — ClickHouse protocol is columnar. Values arrive column-by-column within each block.
2. **Use `on_data` for bounded memory** — if your callback doesn't accumulate all values, memory stays proportional to one block.
3. **Default batch mode transposes for you** — returns `#{columns => [...], rows => [[...]]}` with rows already built.
4. **The callback signature is** `fun(Event, Acc) -> {ok, NewAcc}` — always return `{ok, NewAcc}`.
5. **`'end'` event means query complete** — return the final result in your accumulator.
6. **Column metadata comes with each value** — `#{name => ColName, type => ColType, value => Value}`.
7. **For streaming inserts**, data blocks don't need `type` in column maps — the engine merges from column definitions.
8. **`block_end` signals block boundary** — dispatched after all column values for a non-empty block have been delivered. Use it for bounded-memory row transposition or batch-aligned flushing.
