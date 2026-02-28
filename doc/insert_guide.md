# INSERT Query Guide

This guide provides comprehensive documentation for inserting data into ClickHouse using the `clickhouse_erl` library.

## Overview

The `clickhouse_erl` library supports efficient column-oriented data insertion using the native binary protocol. INSERT operations are atomic - either all rows are inserted successfully or none are inserted.

## Basic Usage

### Simple INSERT

```erlang
% 1. Connect to ClickHouse
{ok, Conn} = clickhouse_erl:connect("localhost", 9000).

% 2. Prepare INSERT statement
SQL = <<"INSERT INTO users (id, name, age) VALUES">>,

% 3. Prepare column data
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2, 3]},
    #{name => <<"name">>, type => <<"String">>, data => [<<"Alice">>, <<"Bob">>, <<"Charlie">>]},
    #{name => <<"age">>, type => <<"UInt32">>, data => [25, 30, 35]}
],

% 4. Execute INSERT
{ok, Result} = clickhouse_erl:insert(Conn, SQL, Input).

% 5. Check result
#{rows_inserted := 3, elapsed_time := DurationMs} = Result.
```

## Input Format

### Column Data Structure

Each column in the `Input` list must be a map with three required fields:

- **`name`**: Binary string matching the column name in the INSERT statement
- **`type`**: Binary string specifying the ClickHouse type (e.g., `<<"UInt32">>`, `<<"String">>`)
- **`data`**: List of values for this column (all columns must have the same number of values)

```erlang
ColumnData = #{
    name => <<"column_name">>,
    type => <<"ClickHouse_Type">>,
    data => [Value1, Value2, Value3, ...]
}.
```

### Column Order

Columns in the `Input` list can be in any order - they don't need to match the table definition order. However, the column names must match those specified in the INSERT statement.

```erlang
% These are equivalent:
Input1 = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2]},
    #{name => <<"name">>, type => <<"String">>, data => [<<"A">>, <<"B">>]}
],

Input2 = [
    #{name => <<"name">>, type => <<"String">>, data => [<<"A">>, <<"B">>]},
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2]}
].
```

## Supported Data Types

### Integer Types

```erlang
% Unsigned integers
#{name => <<"col_uint8">>, type => <<"UInt8">>, data => [0, 255]},
#{name => <<"col_uint16">>, type => <<"UInt16">>, data => [0, 65535]},
#{name => <<"col_uint32">>, type => <<"UInt32">>, data => [0, 4294967295]},
#{name => <<"col_uint64">>, type => <<"UInt64">>, data => [0, 18446744073709551615]},

% Signed integers
#{name => <<"col_int8">>, type => <<"Int8">>, data => [-128, 127]},
#{name => <<"col_int16">>, type => <<"Int16">>, data => [-32768, 32767]},
#{name => <<"col_int32">>, type => <<"Int32">>, data => [-2147483648, 2147483647]},
#{name => <<"col_int64">>, type => <<"Int64">>, data => [-9223372036854775808, 9223372036854775807]}.
```

### Floating-Point Types

```erlang
#{name => <<"col_float32">>, type => <<"Float32">>, data => [3.14, -2.71, 0.0]},
#{name => <<"col_float64">>, type => <<"Float64">>, data => [3.141592653589793, -2.718281828459045]}.
```

### String Type

Strings must be provided as binary values (UTF-8 encoded).

```erlang
#{name => <<"col_string">>, type => <<"String">>, data => [
    <<"Hello">>,
    <<"World">>,
    <<"UTF-8: 你好"/utf8>>
]}.
```

### Boolean Type

ClickHouse `Bool` is an alias for `UInt8`. Use atoms `true` and `false`, or integers `1` and `0`.

```erlang
#{name => <<"col_bool">>, type => <<"Bool">>, data => [true, false, true]}.
```

### Date and DateTime Types

#### Date

Date values are provided as `{Year, Month, Day}` tuples.

```erlang
#{name => <<"col_date">>, type => <<"Date">>, data => [
    {2023, 1, 1},
    {2023, 12, 31},
    {2024, 2, 29}  % Leap year
]}.
```

#### DateTime

DateTime values are provided as `{{Year, Month, Day}, {Hour, Minute, Second}}` tuples.

```erlang
#{name => <<"col_datetime">>, type => <<"DateTime">>, data => [
    {{2023, 1, 1}, {0, 0, 0}},
    {{2023, 6, 15}, {12, 30, 45}},
    {{2023, 12, 31}, {23, 59, 59}}
]}.
```

#### DateTime64

DateTime64 values with microsecond precision are provided as `{{Year, Month, Day}, {Hour, Minute, Second, Microsecond}}` tuples.

```erlang
#{name => <<"col_datetime64">>, type => <<"DateTime64(6)">>, data => [
    {{2023, 1, 1}, {0, 0, 0, 0}},
    {{2023, 6, 15}, {12, 30, 45, 123456}},
    {{2023, 12, 31}, {23, 59, 59, 999999}}
]}.
```

### Composite Types

#### Tuple

Tuple values are provided as Erlang tuples. All tuples in the column must have the same structure.

```erlang
% Tuple(String, Int64, Float64)
#{name => <<"profile">>, type => <<"Tuple(String, Int64, Float64)">>, data => [
    {<<"Alice">>, 25, 95.5},
    {<<"Bob">>, 30, 87.2},
    {<<"Charlie">>, 35, 92.8}
]}.

% Named tuple: Tuple(name String, age Int64)
#{name => <<"user_info">>, type => <<"Tuple(String, Int64)">>, data => [
    {<<"Alice">>, 25},
    {<<"Bob">>, 30}
]}.

% Nested tuple: Tuple(Tuple(Int64, Int64), String)
#{name => <<"nested">>, type => <<"Tuple(Tuple(Int64, Int64), String)">>, data => [
    {{100, 200}, <<"description">>},
    {{300, 400}, <<"other">>}
]}.
```

#### Array

Array values are provided as Erlang lists. Arrays can have variable lengths.

```erlang
% Array(Int64)
#{name => <<"numbers">>, type => <<"Array(Int64)">>, data => [
    [1, 2, 3],
    [4, 5],
    [6]
]}.

% Array(String)
#{name => <<"tags">>, type => <<"Array(String)">>, data => [
    [<<"erlang">>, <<"clickhouse">>],
    [<<"database">>],
    []  % Empty array is valid
]}.

% Nested array: Array(Array(Int64))
#{name => <<"matrix">>, type => <<"Array(Array(Int64))">>, data => [
    [[1, 2], [3, 4]],
    [[5, 6]],
    []
]}.

% Array of tuples: Array(Tuple(String, Int64))
#{name => <<"users">>, type => <<"Array(Tuple(String, Int64))">>, data => [
    [{<<"Alice">>, 25}, {<<"Bob">>, 30}],
    [{<<"Charlie">>, 35}]
]}.
```

#### Map

Map values are provided as Erlang maps. Keys must be comparable types (no arrays or maps as keys).

```erlang
% Map(String, Int64)
#{name => <<"counts">>, type => <<"Map(String, Int64)">>, data => [
    #{<<"key1">> => 100, <<"key2">> => 200},
    #{<<"key3">> => 300},
    #{}  % Empty map is valid
]}.

% Map(String, String)
#{name => <<"metadata">>, type => <<"Map(String, String)">>, data => [
    #{<<"name">> => <<"Alice">>, <<"email">> => <<"alice@example.com">>},
    #{<<"name">> => <<"Bob">>}
]}.

% Map with complex value type: Map(String, Array(Int64))
#{name => <<"data">>, type => <<"Map(String, Array(Int64))">>, data => [
    #{<<"a">> => [1, 2, 3], <<"b">> => [4, 5]},
    #{<<"c">> => [6]}
]}.
```

#### Nullable

Nullable values use tagged tuples: `{null}` for NULL and `{value, ActualValue}` for non-NULL values.

```erlang
% Nullable(String)
#{name => <<"email">>, type => <<"Nullable(String)">>, data => [
    {value, <<"alice@example.com">>},
    {null},
    {value, <<"charlie@example.com">>}
]}.

% Nullable(Int64)
#{name => <<"age">>, type => <<"Nullable(Int64)">>, data => [
    {value, 25},
    {value, 30},
    {null}
]}.

% Nullable composite type: Nullable(Array(String))
#{name => <<"tags">>, type => <<"Nullable(Array(String))">>, data => [
    {value, [<<"admin">>]},
    {null},
    {value, []}
]}.
```

#### LowCardinality

LowCardinality values are provided as regular values (same as the underlying type). Dictionary encoding is handled automatically.

```erlang
% LowCardinality(String) - use regular strings
#{name => <<"category">>, type => <<"LowCardinality(String)">>, data => [
    <<"A">>,
    <<"B">>,
    <<"A">>,
    <<"C">>,
    <<"B">>,
    <<"A">>
]}.

% LowCardinality is most effective for columns with limited unique values
#{name => <<"status">>, type => <<"LowCardinality(String)">>, data => [
    <<"active">>,
    <<"active">>,
    <<"inactive">>,
    <<"active">>,
    <<"pending">>
]}.
```

For more details on composite types, see the [Composite Types Guide](composite_types_guide.md).

## Advanced Usage

### Empty INSERT

Inserting zero rows is valid and returns success with `rows_inserted => 0`.

```erlang
SQL = <<"INSERT INTO users (id, name) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => []},
    #{name => <<"name">>, type => <<"String">>, data => []}
],
{ok, #{rows_inserted := 0}} = clickhouse_erl:insert(Conn, SQL, Input).
```

### Partial Column INSERT

You can insert data into a subset of table columns. Columns not specified will use their default values or NULL (if nullable).

```erlang
% Table: users (id UInt64, name String, age UInt32 DEFAULT 0, created DateTime DEFAULT now())

% Insert only id and name - age and created will use defaults
SQL = <<"INSERT INTO users (id, name) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2]},
    #{name => <<"name">>, type => <<"String">>, data => [<<"Alice">>, <<"Bob">>]}
],
{ok, _} = clickhouse_erl:insert(Conn, SQL, Input).
```

### INSERT with Timeout

Specify a custom timeout for long-running INSERT operations.

```erlang
SQL = <<"INSERT INTO large_table (id, data) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => lists:seq(1, 1000000)},
    #{name => <<"data">>, type => <<"String">>, data => lists:duplicate(1000000, <<"data">>)}
],

Options = #{timeout => 60000},  % 60 seconds
{ok, Result} = clickhouse_erl:insert(Conn, SQL, Input, Options).
```

### Batch Processing

For large datasets, consider batching inserts to balance memory usage and performance.

```erlang
insert_batch(Conn, SQL, AllData, BatchSize) ->
    Batches = partition_data(AllData, BatchSize),
    lists:foreach(fun(Batch) ->
        {ok, _} = clickhouse_erl:insert(Conn, SQL, Batch)
    end, Batches).

partition_data(Data, BatchSize) ->
    % Split data into batches of BatchSize rows
    % Implementation depends on your data structure
    ...
```

## Error Handling

### Client-Side Validation Errors

These errors are detected before sending data to the server:

#### Row Count Mismatch

All columns must have the same number of rows.

```erlang
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2, 3]},
    #{name => <<"name">>, type => <<"String">>, data => [<<"Alice">>, <<"Bob">>]}  % Only 2 values!
],
{error, {row_count_mismatch, Details}} = clickhouse_erl:insert(Conn, SQL, Input).
% Details: [{<<"id">>, 3}, {<<"name">>, 2}]
```

#### Invalid Column Name

Column names must be binaries.

```erlang
Input = [
    #{name => "id", type => <<"UInt64">>, data => [1, 2]}  % String instead of binary!
],
{error, {invalid_column_name, "id"}} = clickhouse_erl:insert(Conn, SQL, Input).
```

#### Type Mismatch

Data values must match the specified type.

```erlang
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, <<"not_a_number">>, 3]}
],
{error, {type_mismatch, <<"id">>, <<"UInt64">>, Reason}} = clickhouse_erl:insert(Conn, SQL, Input).
```

### Server-Side Errors

These errors are returned by ClickHouse after receiving the data:

#### Schema Mismatch

Column doesn't exist in the table.

```erlang
SQL = <<"INSERT INTO users (id, nonexistent_column) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1]},
    #{name => <<"nonexistent_column">>, type => <<"String">>, data => [<<"value">>]}
],
{error, {server_exception, ExceptionInfo}} = clickhouse_erl:insert(Conn, SQL, Input).

% ExceptionInfo contains:
% #{error_code => 16,  % NO_SUCH_COLUMN_IN_TABLE
%   exception_name => <<"DB::Exception">>,
%   message => <<"There is no column with name nonexistent_column in table users">>,
%   ...}
```

#### Type Mismatch (Server-Side)

Server detects type incompatibility.

```erlang
% Table has UInt32 column, but we send String type
SQL = <<"INSERT INTO users (id, age) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1]},
    #{name => <<"age">>, type => <<"String">>, data => [<<"not_a_number">>]}
],
{error, {server_exception, #{error_code := 53}}} = clickhouse_erl:insert(Conn, SQL, Input).
% Error code 53 = TYPE_MISMATCH
```

#### Constraint Violation

NOT NULL, CHECK, or other constraint violations.

```erlang
% Table has NOT NULL constraint on 'name' column
SQL = <<"INSERT INTO users (id, name) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1]},
    #{name => <<"name">>, type => <<"Nullable(String)">>, data => [null]}
],
{error, {server_exception, ExceptionInfo}} = clickhouse_erl:insert(Conn, SQL, Input).
```

### Network Errors

Connection or transmission failures.

```erlang
{error, {send_failed, closed}} = clickhouse_erl:insert(Conn, SQL, Input).
{error, {send_failed, timeout}} = clickhouse_erl:insert(Conn, SQL, Input).
```

### Error Formatting

Use `format_error/1` for human-readable error messages.

```erlang
case clickhouse_erl:insert(Conn, SQL, Input) of
    {ok, Result} ->
        io:format("Inserted ~p rows~n", [maps:get(rows_inserted, Result)]);
    {error, Reason} ->
        ErrorMsg = clickhouse_erl:format_error(Reason),
        io:format("INSERT failed: ~s~n", [ErrorMsg])
end.
```

## Best Practices

### 1. Use Binary Strings

Always use binary strings for column names and type names.

```erlang
% Good
#{name => <<"id">>, type => <<"UInt64">>, data => [1, 2, 3]}

% Bad
#{name => "id", type => "UInt64", data => [1, 2, 3]}
```

### 2. Validate Data Before INSERT

Check data consistency before calling `insert/3` to catch errors early.

```erlang
validate_input(Input) ->
    % Check all columns have same row count
    RowCounts = [length(maps:get(data, Col)) || Col <- Input],
    case lists:usort(RowCounts) of
        [_SingleCount] -> ok;
        _ -> {error, row_count_mismatch}
    end.
```

### 3. Use Appropriate Batch Sizes

Balance memory usage and network overhead by batching inserts.

- Small batches (100-1000 rows): Lower memory, more network overhead
- Large batches (10000-100000 rows): Higher memory, less network overhead
- Test with your data to find optimal batch size

### 4. Handle Errors Gracefully

Always pattern match on both success and error cases.

```erlang
case clickhouse_erl:insert(Conn, SQL, Input) of
    {ok, #{rows_inserted := N}} ->
        ?LOG_INFO("Successfully inserted ~p rows", [N]),
        {ok, N};
    {error, {server_exception, #{error_code := 16}}} ->
        ?LOG_ERROR("Column not found in table"),
        {error, schema_mismatch};
    {error, Reason} ->
        ?LOG_ERROR("INSERT failed: ~p", [Reason]),
        {error, Reason}
end.
```

### 5. Use Connection Pooling

For high-throughput applications, maintain a pool of connections.

```erlang
% Pseudo-code - implement connection pooling
Pool = create_connection_pool(PoolSize),
Conn = checkout_connection(Pool),
{ok, _} = clickhouse_erl:insert(Conn, SQL, Input),
checkin_connection(Pool, Conn).
```

### 6. Monitor Performance

Track INSERT performance metrics.

```erlang
StartTime = erlang:monotonic_time(millisecond),
{ok, #{rows_inserted := N, elapsed_time := ServerTime}} = 
    clickhouse_erl:insert(Conn, SQL, Input),
TotalTime = erlang:monotonic_time(millisecond) - StartTime,

?LOG_INFO("INSERT performance", #{
    rows => N,
    server_time_ms => ServerTime,
    total_time_ms => TotalTime,
    rows_per_second => N * 1000 div TotalTime
}).
```

## Complete Example

Here's a complete example demonstrating INSERT with error handling:

```erlang
-module(insert_example).
-export([insert_users/1]).

insert_users(Conn) ->
    % Create table
    CreateSQL = <<"
        CREATE TABLE IF NOT EXISTS users (
            id UInt64,
            name String,
            email String,
            age UInt32,
            created DateTime DEFAULT now()
        ) ENGINE = MergeTree()
        ORDER BY id
    ">>,
    {ok, _} = clickhouse_erl:query(Conn, CreateSQL),

    % Prepare INSERT data
    SQL = <<"INSERT INTO users (id, name, email, age) VALUES">>,
    Input = [
        #{name => <<"id">>, type => <<"UInt64">>, 
          data => [1, 2, 3, 4, 5]},
        #{name => <<"name">>, type => <<"String">>, 
          data => [<<"Alice">>, <<"Bob">>, <<"Charlie">>, <<"Diana">>, <<"Eve">>]},
        #{name => <<"email">>, type => <<"String">>, 
          data => [<<"alice@example.com">>, <<"bob@example.com">>, 
                   <<"charlie@example.com">>, <<"diana@example.com">>, 
                   <<"eve@example.com">>]},
        #{name => <<"age">>, type => <<"UInt32">>, 
          data => [25, 30, 35, 28, 32]}
    ],

    % Execute INSERT with error handling
    case clickhouse_erl:insert(Conn, SQL, Input) of
        {ok, #{rows_inserted := N, elapsed_time := Ms}} ->
            io:format("Successfully inserted ~p rows in ~p ms~n", [N, Ms]),
            
            % Verify with SELECT
            {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT count() FROM users">>),
            io:format("Total rows in table: ~p~n", [Result]),
            
            {ok, N};
            
        {error, {row_count_mismatch, Details}} ->
            io:format("Error: Row count mismatch: ~p~n", [Details]),
            {error, validation_failed};
            
        {error, {server_exception, #{error_code := ErrorCode, message := Msg}}} ->
            io:format("Server error ~p: ~s~n", [ErrorCode, Msg]),
            {error, server_error};
            
        {error, Reason} ->
            io:format("INSERT failed: ~p~n", [Reason]),
            {error, Reason}
    end.
```

## Performance Considerations

### Memory Usage

INSERT operations buffer data in memory before sending. For large datasets:

- Monitor memory usage with `erlang:memory()`
- Use batching to limit memory consumption
- Consider streaming approaches for very large datasets (future enhancement)

### Network Bandwidth

The native binary protocol is efficient, but large INSERTs still consume bandwidth:

- Compression support (future enhancement) will reduce bandwidth usage
- Batch multiple small INSERTs into larger operations
- Consider network latency when choosing batch sizes

### Server-Side Performance

ClickHouse INSERT performance depends on:

- Table engine (MergeTree is optimized for bulk inserts)
- Number of columns and data types
- Server hardware and configuration
- Concurrent INSERT operations

## Limitations

Current implementation limitations (may be addressed in future versions):

1. **Single-block INSERT only**: All data must fit in one data block
2. **No compression**: Data is sent uncompressed
3. **No streaming**: Cannot stream data from callbacks or generators
4. **Basic types only**: Complex types (Array, Tuple, Nullable, etc.) not yet supported
5. **No automatic batching**: Application must implement batching logic

## See Also

- [Usage Guide](usage.md) - General library usage
- [Error Handling](error_handling.md) - Comprehensive error handling guide
- [ClickHouse Documentation](https://clickhouse.com/docs/en/sql-reference/statements/insert-into/) - Official INSERT documentation
