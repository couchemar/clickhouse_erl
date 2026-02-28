# ClickHouse Erlang Client Examples

This document provides practical examples for common use cases with the `clickhouse_erl` library.

## Table of Contents

- [Connection Examples](#connection-examples)
- [Query Examples](#query-examples)
- [INSERT Examples](#insert-examples)
- [Composite Type Examples](#composite-type-examples)
- [Error Handling Examples](#error-handling-examples)
- [Production Patterns](#production-patterns)

## Connection Examples

### Basic Connection

```erlang
% Connect with defaults
{ok, Conn} = clickhouse_erl:connect("localhost", 9000),

% Use the connection
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>),

% Clean up
ok = clickhouse_erl:disconnect(Conn).
```

### Connection with Authentication

```erlang
Options = #{
    database => <<"production_db">>,
    username => <<"app_user">>,
    password => <<"secure_password">>,
    timeout => 10000  % 10 second connection timeout
},
{ok, Conn} = clickhouse_erl:connect("clickhouse.example.com", 9000, Options).
```

### Connection Error Handling

```erlang
case clickhouse_erl:connect("localhost", 9000) of
    {ok, Conn} ->
        io:format("Connected successfully~n"),
        {ok, Conn};
    {error, {network_error, econnrefused}} ->
        io:format("Connection refused - is ClickHouse running?~n"),
        {error, connection_refused};
    {error, {timeout_error, connect}} ->
        io:format("Connection timeout~n"),
        {error, timeout};
    {error, Reason} ->
        io:format("Connection failed: ~p~n", [Reason]),
        {error, Reason}
end.
```

## Query Examples

### Simple SELECT

```erlang
{ok, Conn} = clickhouse_erl:connect("localhost", 9000),
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT version()">>),
io:format("ClickHouse version: ~p~n", [Result]).
```

### SELECT with Parameters

```erlang
SQL = <<"SELECT name, age FROM users WHERE age > 21 ORDER BY age DESC LIMIT 10">>,
{ok, Result} = clickhouse_erl:query(Conn, SQL),

#{
    columns := Columns,
    rows := Rows,
    statistics := Stats
} = Result,

io:format("Found ~p users~n", [length(Rows)]).
```

### Query with Timeout

```erlang
SQL = <<"SELECT * FROM large_table">>,
Options = #{timeout => 60000},  % 60 seconds

case clickhouse_erl:query(Conn, SQL, Options) of
    {ok, Result} ->
        io:format("Query completed~n");
    {error, {timeout_error, _}} ->
        io:format("Query timed out after 60 seconds~n")
end.
```

## INSERT Examples

### Basic INSERT

```erlang
% Create table
CreateSQL = <<"
    CREATE TABLE IF NOT EXISTS events (
        timestamp DateTime,
        event_type String,
        user_id UInt64,
        value Float64
    ) ENGINE = MergeTree()
    ORDER BY timestamp
">>,
{ok, _} = clickhouse_erl:query(Conn, CreateSQL),

% Insert data
SQL = <<"INSERT INTO events (timestamp, event_type, user_id, value) VALUES">>,
Input = [
    #{name => <<"timestamp">>, type => <<"DateTime">>, 
      data => [{{2023, 1, 1}, {12, 0, 0}}, {{2023, 1, 1}, {12, 5, 0}}]},
    #{name => <<"event_type">>, type => <<"String">>, 
      data => [<<"click">>, <<"view">>]},
    #{name => <<"user_id">>, type => <<"UInt64">>, 
      data => [1001, 1002]},
    #{name => <<"value">>, type => <<"Float64">>, 
      data => [1.5, 2.3]}
],

{ok, #{rows_inserted := 2}} = clickhouse_erl:insert(Conn, SQL, Input).
```

### INSERT with All Data Types

```erlang
CreateSQL = <<"
    CREATE TABLE IF NOT EXISTS type_examples (
        col_uint8 UInt8,
        col_uint16 UInt16,
        col_uint32 UInt32,
        col_uint64 UInt64,
        col_int8 Int8,
        col_int16 Int16,
        col_int32 Int32,
        col_int64 Int64,
        col_float32 Float32,
        col_float64 Float64,
        col_string String,
        col_bool Bool,
        col_date Date,
        col_datetime DateTime,
        col_datetime64 DateTime64(6)
    ) ENGINE = MergeTree()
    ORDER BY col_uint64
">>,
{ok, _} = clickhouse_erl:query(Conn, CreateSQL),

SQL = <<"INSERT INTO type_examples VALUES">>,
Input = [
    #{name => <<"col_uint8">>, type => <<"UInt8">>, data => [0, 255]},
    #{name => <<"col_uint16">>, type => <<"UInt16">>, data => [0, 65535]},
    #{name => <<"col_uint32">>, type => <<"UInt32">>, data => [0, 4294967295]},
    #{name => <<"col_uint64">>, type => <<"UInt64">>, data => [1, 2]},
    #{name => <<"col_int8">>, type => <<"Int8">>, data => [-128, 127]},
    #{name => <<"col_int16">>, type => <<"Int16">>, data => [-32768, 32767]},
    #{name => <<"col_int32">>, type => <<"Int32">>, data => [-2147483648, 2147483647]},
    #{name => <<"col_int64">>, type => <<"Int64">>, data => [-9223372036854775808, 9223372036854775807]},
    #{name => <<"col_float32">>, type => <<"Float32">>, data => [3.14, -2.71]},
    #{name => <<"col_float64">>, type => <<"Float64">>, data => [3.141592653589793, -2.718281828459045]},
    #{name => <<"col_string">>, type => <<"String">>, data => [<<"Hello">>, <<"World">>]},
    #{name => <<"col_bool">>, type => <<"Bool">>, data => [true, false]},
    #{name => <<"col_date">>, type => <<"Date">>, data => [{2023, 1, 1}, {2023, 12, 31}]},
    #{name => <<"col_datetime">>, type => <<"DateTime">>, 
      data => [{{2023, 1, 1}, {0, 0, 0}}, {{2023, 12, 31}, {23, 59, 59}}]},
    #{name => <<"col_datetime64">>, type => <<"DateTime64(6)">>, 
      data => [{{2023, 1, 1}, {0, 0, 0, 0}}, {{2023, 12, 31}, {23, 59, 59, 999999}}]}
],

{ok, #{rows_inserted := 2}} = clickhouse_erl:insert(Conn, SQL, Input).
```

### Batch INSERT

```erlang
-module(batch_insert_example).
-export([insert_large_dataset/2]).

insert_large_dataset(Conn, TotalRows) ->
    BatchSize = 10000,
    NumBatches = (TotalRows + BatchSize - 1) div BatchSize,
    
    SQL = <<"INSERT INTO large_table (id, value) VALUES">>,
    
    lists:foreach(fun(BatchNum) ->
        StartId = BatchNum * BatchSize + 1,
        EndId = min((BatchNum + 1) * BatchSize, TotalRows),
        
        Input = [
            #{name => <<"id">>, type => <<"UInt64">>, 
              data => lists:seq(StartId, EndId)},
            #{name => <<"value">>, type => <<"String">>, 
              data => [integer_to_binary(I) || I <- lists:seq(StartId, EndId)]}
        ],
        
        {ok, #{rows_inserted := N}} = clickhouse_erl:insert(Conn, SQL, Input),
        io:format("Batch ~p: inserted ~p rows~n", [BatchNum, N])
    end, lists:seq(0, NumBatches - 1)),
    
    io:format("Completed inserting ~p rows in ~p batches~n", [TotalRows, NumBatches]).
```

### INSERT with Partial Columns

```erlang
% Table has columns: id, name, email, created (with DEFAULT now())
% We only insert id and name - email and created use defaults

SQL = <<"INSERT INTO users (id, name) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2, 3]},
    #{name => <<"name">>, type => <<"String">>, 
      data => [<<"Alice">>, <<"Bob">>, <<"Charlie">>]}
],

{ok, #{rows_inserted := 3}} = clickhouse_erl:insert(Conn, SQL, Input).
```

### Empty INSERT

```erlang
% Valid operation - inserts 0 rows
SQL = <<"INSERT INTO users (id, name) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => []},
    #{name => <<"name">>, type => <<"String">>, data => []}
],

{ok, #{rows_inserted := 0}} = clickhouse_erl:insert(Conn, SQL, Input).
```

## Composite Type Examples

### Tuple Examples

```erlang
% Create table with tuples
CreateSQL = <<"
    CREATE TABLE IF NOT EXISTS locations (
        id UInt64,
        name String,
        coordinates Tuple(Float64, Float64),
        metadata Tuple(city String, country String, population Int64)
    ) ENGINE = MergeTree()
    ORDER BY id
">>,
{ok, _} = clickhouse_erl:query(Conn, CreateSQL),

% Insert tuple data
SQL = <<"INSERT INTO locations (id, name, coordinates, metadata) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2]},
    #{name => <<"name">>, type => <<"String">>, 
      data => [<<"San Francisco">>, <<"New York">>]},
    #{name => <<"coordinates">>, type => <<"Tuple(Float64, Float64)">>, 
      data => [{37.7749, -122.4194}, {40.7128, -74.0060}]},
    #{name => <<"metadata">>, type => <<"Tuple(String, String, Int64)">>, 
      data => [{<<"San Francisco">>, <<"USA">>, 873965}, 
               {<<"New York">>, <<"USA">>, 8336817}]}
],

{ok, #{rows_inserted := 2}} = clickhouse_erl:insert(Conn, SQL, Input),

% Query tuple data
{ok, #{rows := Rows}} = clickhouse_erl:query(Conn, <<"SELECT * FROM locations">>),
% Rows = [
%   {1, <<"San Francisco">>, {37.7749, -122.4194}, {<<"San Francisco">>, <<"USA">>, 873965}},
%   {2, <<"New York">>, {40.7128, -74.0060}, {<<"New York">>, <<"USA">>, 8336817}}
% ]
```

### Array Examples

```erlang
% Create table with arrays
CreateSQL = <<"
    CREATE TABLE IF NOT EXISTS posts (
        id UInt64,
        title String,
        tags Array(String),
        view_counts Array(Int64),
        related_posts Array(Array(UInt64))
    ) ENGINE = MergeTree()
    ORDER BY id
">>,
{ok, _} = clickhouse_erl:query(Conn, CreateSQL),

% Insert array data
SQL = <<"INSERT INTO posts (id, title, tags, view_counts, related_posts) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2, 3]},
    #{name => <<"title">>, type => <<"String">>, 
      data => [<<"First Post">>, <<"Second Post">>, <<"Third Post">>]},
    #{name => <<"tags">>, type => <<"Array(String)">>, 
      data => [[<<"erlang">>, <<"clickhouse">>], 
               [<<"database">>, <<"performance">>], 
               [<<"tutorial">>]]},
    #{name => <<"view_counts">>, type => <<"Array(Int64)">>, 
      data => [[100, 150, 200], [50, 75], [300]]},
    #{name => <<"related_posts">>, type => <<"Array(Array(UInt64))">>, 
      data => [[[2, 3]], [[1]], [[1, 2]]]}
],

{ok, #{rows_inserted := 3}} = clickhouse_erl:insert(Conn, SQL, Input),

% Query array data
{ok, #{rows := Rows}} = clickhouse_erl:query(Conn, <<"SELECT * FROM posts">>).
% Rows = [
%   {1, <<"First Post">>, [<<"erlang">>, <<"clickhouse">>], [100, 150, 200], [[2, 3]]},
%   {2, <<"Second Post">>, [<<"database">>, <<"performance">>], [50, 75], [[1]]},
%   {3, <<"Third Post">>, [<<"tutorial">>], [300], [[1, 2]]}
% ]
```

### Map Examples

```erlang
% Create table with maps
CreateSQL = <<"
    CREATE TABLE IF NOT EXISTS events (
        id UInt64,
        event_name String,
        properties Map(String, String),
        metrics Map(String, Float64)
    ) ENGINE = MergeTree()
    ORDER BY id
">>,
{ok, _} = clickhouse_erl:query(Conn, CreateSQL),

% Insert map data
SQL = <<"INSERT INTO events (id, event_name, properties, metrics) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2]},
    #{name => <<"event_name">>, type => <<"String">>, 
      data => [<<"page_view">>, <<"click">>]},
    #{name => <<"properties">>, type => <<"Map(String, String)">>, 
      data => [#{<<"page">> => <<"home">>, <<"referrer">> => <<"google">>},
               #{<<"button">> => <<"signup">>, <<"location">> => <<"header">>}]},
    #{name => <<"metrics">>, type => <<"Map(String, Float64)">>, 
      data => [#{<<"duration">> => 5.2, <<"scroll_depth">> => 0.75},
               #{<<"x">> => 100.0, <<"y">> => 200.0}]}
],

{ok, #{rows_inserted := 2}} = clickhouse_erl:insert(Conn, SQL, Input),

% Query map data
{ok, #{rows := Rows}} = clickhouse_erl:query(Conn, <<"SELECT * FROM events">>).
% Rows = [
%   {1, <<"page_view">>, 
%    #{<<"page">> => <<"home">>, <<"referrer">> => <<"google">>},
%    #{<<"duration">> => 5.2, <<"scroll_depth">> => 0.75}},
%   {2, <<"click">>,
%    #{<<"button">> => <<"signup">>, <<"location">> => <<"header">>},
%    #{<<"x">> => 100.0, <<"y">> => 200.0}}
% ]
```

### Nullable Examples

```erlang
% Create table with nullable columns
CreateSQL = <<"
    CREATE TABLE IF NOT EXISTS users (
        id UInt64,
        name String,
        email Nullable(String),
        age Nullable(Int64),
        tags Nullable(Array(String))
    ) ENGINE = MergeTree()
    ORDER BY id
">>,
{ok, _} = clickhouse_erl:query(Conn, CreateSQL),

% Insert nullable data
SQL = <<"INSERT INTO users (id, name, email, age, tags) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2, 3]},
    #{name => <<"name">>, type => <<"String">>, 
      data => [<<"Alice">>, <<"Bob">>, <<"Charlie">>]},
    #{name => <<"email">>, type => <<"Nullable(String)">>, 
      data => [{value, <<"alice@example.com">>}, {null}, {value, <<"charlie@example.com">>}]},
    #{name => <<"age">>, type => <<"Nullable(Int64)">>, 
      data => [{value, 25}, {value, 30}, {null}]},
    #{name => <<"tags">>, type => <<"Nullable(Array(String))">>, 
      data => [{value, [<<"admin">>]}, {null}, {value, []}]}
],

{ok, #{rows_inserted := 3}} = clickhouse_erl:insert(Conn, SQL, Input),

% Query nullable data
{ok, #{rows := Rows}} = clickhouse_erl:query(Conn, <<"SELECT * FROM users">>).
% Rows = [
%   {1, <<"Alice">>, {value, <<"alice@example.com">>}, {value, 25}, {value, [<<"admin">>]}},
%   {2, <<"Bob">>, {null}, {value, 30}, {null}},
%   {3, <<"Charlie">>, {value, <<"charlie@example.com">>}, {null}, {value, []}}
% ]
```

### LowCardinality Examples

```erlang
% Create table with low cardinality columns
CreateSQL = <<"
    CREATE TABLE IF NOT EXISTS events (
        id UInt64,
        event_type LowCardinality(String),
        category LowCardinality(String),
        user_id UInt64
    ) ENGINE = MergeTree()
    ORDER BY id
">>,
{ok, _} = clickhouse_erl:query(Conn, CreateSQL),

% Insert low cardinality data (values are used normally)
SQL = <<"INSERT INTO events (id, event_type, category, user_id) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2, 3, 4, 5]},
    #{name => <<"event_type">>, type => <<"LowCardinality(String)">>, 
      data => [<<"click">>, <<"click">>, <<"view">>, <<"click">>, <<"view">>]},
    #{name => <<"category">>, type => <<"LowCardinality(String)">>, 
      data => [<<"button">>, <<"link">>, <<"page">>, <<"button">>, <<"page">>]},
    #{name => <<"user_id">>, type => <<"UInt64">>, data => [100, 101, 100, 102, 101]}
],

{ok, #{rows_inserted := 5}} = clickhouse_erl:insert(Conn, SQL, Input),

% Query low cardinality data (values returned normally)
{ok, #{rows := Rows}} = clickhouse_erl:query(Conn, <<"SELECT * FROM events">>).
% Rows = [
%   {1, <<"click">>, <<"button">>, 100},
%   {2, <<"click">>, <<"link">>, 101},
%   {3, <<"view">>, <<"page">>, 100},
%   {4, <<"click">>, <<"button">>, 102},
%   {5, <<"view">>, <<"page">>, 101}
% ]
```

### Complex Nested Example

```erlang
% Create table with deeply nested composite types
CreateSQL = <<"
    CREATE TABLE IF NOT EXISTS analytics (
        id UInt64,
        user_profile Tuple(
            name String,
            tags Array(String),
            metadata Map(String, String)
        ),
        events Array(Tuple(
            event_type LowCardinality(String),
            timestamp DateTime,
            properties Nullable(Map(String, String))
        ))
    ) ENGINE = MergeTree()
    ORDER BY id
">>,
{ok, _} = clickhouse_erl:query(Conn, CreateSQL),

% Insert complex nested data
SQL = <<"INSERT INTO analytics (id, user_profile, events) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1]},
    #{name => <<"user_profile">>, 
      type => <<"Tuple(String, Array(String), Map(String, String))">>, 
      data => [{<<"Alice">>, 
                [<<"premium">>, <<"verified">>],
                #{<<"country">> => <<"US">>, <<"language">> => <<"en">>}}]},
    #{name => <<"events">>, 
      type => <<"Array(Tuple(LowCardinality(String), DateTime, Nullable(Map(String, String))))">>, 
      data => [[
          {<<"page_view">>, {{2024, 1, 15}, {10, 30, 0}}, 
           {value, #{<<"page">> => <<"home">>}}},
          {<<"click">>, {{2024, 1, 15}, {10, 31, 0}}, {null}}
      ]]}
],

{ok, #{rows_inserted := 1}} = clickhouse_erl:insert(Conn, SQL, Input).
```

For more details on composite types, see the [Composite Types Guide](composite_types_guide.md).

{ok, #{rows_inserted := 0}} = clickhouse_erl:insert(Conn, SQL, Input).
```

## Error Handling Examples

### Comprehensive Error Handling

```erlang
-module(error_handling_example).
-export([safe_insert/3]).

safe_insert(Conn, SQL, Input) ->
    case clickhouse_erl:insert(Conn, SQL, Input) of
        {ok, #{rows_inserted := N, elapsed_time := Ms}} ->
            io:format("Success: inserted ~p rows in ~p ms~n", [N, Ms]),
            {ok, N};
            
        % Client-side validation errors
        {error, {row_count_mismatch, Details}} ->
            io:format("Error: Columns have different row counts:~n"),
            lists:foreach(fun({ColName, Count}) ->
                io:format("  ~s: ~p rows~n", [ColName, Count])
            end, Details),
            {error, validation_failed};
            
        {error, {invalid_column_name, Name}} ->
            io:format("Error: Invalid column name: ~p (must be binary)~n", [Name]),
            {error, validation_failed};
            
        {error, {type_mismatch, ColName, Type, Reason}} ->
            io:format("Error: Type mismatch in column ~s (type: ~s): ~p~n", 
                     [ColName, Type, Reason]),
            {error, validation_failed};
            
        % Server-side errors
        {error, {server_exception, #{error_code := 16, message := Msg}}} ->
            io:format("Error: Column not found in table: ~s~n", [Msg]),
            {error, schema_mismatch};
            
        {error, {server_exception, #{error_code := 53, message := Msg}}} ->
            io:format("Error: Type mismatch: ~s~n", [Msg]),
            {error, type_error};
            
        {error, {server_exception, #{error_code := 60, message := Msg}}} ->
            io:format("Error: Table not found: ~s~n", [Msg]),
            {error, table_not_found};
            
        {error, {server_exception, ExceptionInfo}} ->
            #{error_code := Code, message := Msg} = ExceptionInfo,
            io:format("Server error ~p: ~s~n", [Code, Msg]),
            {error, server_error};
            
        % Network errors
        {error, {send_failed, closed}} ->
            io:format("Error: Connection closed~n"),
            {error, connection_closed};
            
        {error, {send_failed, timeout}} ->
            io:format("Error: Network timeout~n"),
            {error, network_timeout};
            
        {error, Reason} ->
            io:format("Unexpected error: ~p~n", [Reason]),
            {error, Reason}
    end.
```

### Retry Logic

```erlang
-module(retry_example).
-export([insert_with_retry/4]).

insert_with_retry(Conn, SQL, Input, MaxRetries) ->
    insert_with_retry(Conn, SQL, Input, MaxRetries, 0).

insert_with_retry(_Conn, _SQL, _Input, MaxRetries, Attempt) when Attempt >= MaxRetries ->
    {error, max_retries_exceeded};
    
insert_with_retry(Conn, SQL, Input, MaxRetries, Attempt) ->
    case clickhouse_erl:insert(Conn, SQL, Input) of
        {ok, Result} ->
            {ok, Result};
            
        {error, {send_failed, _}} ->
            % Network error - retry after delay
            timer:sleep(1000 * (Attempt + 1)),  % Exponential backoff
            io:format("Retry ~p after network error~n", [Attempt + 1]),
            insert_with_retry(Conn, SQL, Input, MaxRetries, Attempt + 1);
            
        {error, {server_exception, _}} ->
            % Server error - don't retry
            {error, server_error};
            
        {error, Reason} ->
            {error, Reason}
    end.
```

## Production Patterns

### Connection Pool Pattern

```erlang
-module(connection_pool_example).
-export([start_pool/2, insert_with_pool/2]).

-record(pool, {
    connections :: [pid()],
    available :: [pid()],
    in_use :: #{pid() => reference()}
}).

start_pool(Size, ConnectOpts) ->
    Connections = [begin
        {ok, Conn} = clickhouse_erl:connect("localhost", 9000, ConnectOpts),
        Conn
    end || _ <- lists:seq(1, Size)],
    
    #pool{
        connections = Connections,
        available = Connections,
        in_use = #{}
    }.

checkout_connection(#pool{available = [Conn | Rest]} = Pool) ->
    Ref = make_ref(),
    {ok, Conn, Pool#pool{
        available = Rest,
        in_use = maps:put(Conn, Ref, Pool#pool.in_use)
    }};
checkout_connection(#pool{available = []}) ->
    {error, no_connections_available}.

checkin_connection(Conn, #pool{available = Avail, in_use = InUse} = Pool) ->
    Pool#pool{
        available = [Conn | Avail],
        in_use = maps:remove(Conn, InUse)
    }.

insert_with_pool(Pool, InsertFun) ->
    case checkout_connection(Pool) of
        {ok, Conn, NewPool} ->
            try
                Result = InsertFun(Conn),
                {Result, checkin_connection(Conn, NewPool)}
            catch
                _:Error ->
                    {{error, Error}, checkin_connection(Conn, NewPool)}
            end;
        {error, Reason} ->
            {{error, Reason}, Pool}
    end.
```

### Monitoring and Metrics

```erlang
-module(metrics_example).
-export([insert_with_metrics/3]).

insert_with_metrics(Conn, SQL, Input) ->
    StartTime = erlang:monotonic_time(millisecond),
    RowCount = length(hd([maps:get(data, Col) || Col <- Input])),
    
    Result = clickhouse_erl:insert(Conn, SQL, Input),
    
    EndTime = erlang:monotonic_time(millisecond),
    TotalTime = EndTime - StartTime,
    
    case Result of
        {ok, #{rows_inserted := N, elapsed_time := ServerTime}} ->
            % Log metrics
            io:format("INSERT metrics:~n"),
            io:format("  Rows: ~p~n", [N]),
            io:format("  Server time: ~p ms~n", [ServerTime]),
            io:format("  Total time: ~p ms~n", [TotalTime]),
            io:format("  Network overhead: ~p ms~n", [TotalTime - ServerTime]),
            io:format("  Throughput: ~p rows/sec~n", [N * 1000 div TotalTime]),
            
            % Send to metrics system (e.g., Prometheus, StatsD)
            % metrics:histogram(insert_duration_ms, TotalTime),
            % metrics:counter(insert_rows_total, N),
            
            Result;
            
        {error, Reason} ->
            % Log error
            io:format("INSERT failed after ~p ms: ~p~n", [TotalTime, Reason]),
            % metrics:counter(insert_errors_total, 1),
            Result
    end.
```

### Data Validation

```erlang
-module(validation_example).
-export([validate_and_insert/3]).

validate_and_insert(Conn, SQL, Input) ->
    case validate_input(Input) of
        ok ->
            clickhouse_erl:insert(Conn, SQL, Input);
        {error, Reason} ->
            {error, {validation_failed, Reason}}
    end.

validate_input(Input) ->
    Validations = [
        fun validate_not_empty/1,
        fun validate_column_names/1,
        fun validate_row_counts/1,
        fun validate_data_types/1
    ],
    
    run_validations(Input, Validations).

run_validations(_Input, []) ->
    ok;
run_validations(Input, [Validation | Rest]) ->
    case Validation(Input) of
        ok -> run_validations(Input, Rest);
        {error, Reason} -> {error, Reason}
    end.

validate_not_empty([]) ->
    {error, empty_input};
validate_not_empty(_) ->
    ok.

validate_column_names(Input) ->
    case lists:all(fun(Col) -> 
        is_binary(maps:get(name, Col))
    end, Input) of
        true -> ok;
        false -> {error, invalid_column_names}
    end.

validate_row_counts(Input) ->
    RowCounts = [length(maps:get(data, Col)) || Col <- Input],
    case lists:usort(RowCounts) of
        [_] -> ok;
        _ -> {error, row_count_mismatch}
    end.

validate_data_types(Input) ->
    % Add type-specific validation here
    ok.
```

### Transaction-like Pattern

```erlang
-module(transaction_example).
-export([insert_with_verification/3]).

insert_with_verification(Conn, SQL, Input) ->
    % Get count before insert
    TableName = extract_table_name(SQL),
    CountSQL = iolist_to_binary([<<"SELECT count() FROM ">>, TableName]),
    {ok, #{rows := [[CountBefore]]}} = clickhouse_erl:query(Conn, CountSQL),
    
    % Perform insert
    case clickhouse_erl:insert(Conn, SQL, Input) of
        {ok, #{rows_inserted := N}} ->
            % Verify count after insert
            {ok, #{rows := [[CountAfter]]}} = clickhouse_erl:query(Conn, CountSQL),
            
            case CountAfter - CountBefore of
                N ->
                    io:format("Verified: ~p rows inserted~n", [N]),
                    {ok, N};
                Actual ->
                    io:format("Warning: Expected ~p rows, found ~p~n", [N, Actual]),
                    {ok, Actual}
            end;
            
        {error, Reason} ->
            {error, Reason}
    end.

extract_table_name(SQL) ->
    % Simple extraction - production code should be more robust
    case binary:split(SQL, [<<" INTO ">>, <<" into ">>]) of
        [_, Rest] ->
            [TableName | _] = binary:split(Rest, [<<" ">>, <<"(">>]),
            TableName;
        _ ->
            <<"unknown">>
    end.
```

## See Also

- [INSERT Guide](insert_guide.md) - Comprehensive INSERT documentation
- [Usage Guide](usage.md) - General library usage
- [Error Handling](error_handling.md) - Error handling strategies
