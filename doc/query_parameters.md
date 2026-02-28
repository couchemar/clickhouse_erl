# Query Parameters Guide

Query parameters enable safe, parameterized queries using placeholder syntax that prevents SQL injection, enables query plan caching, and provides type safety.

## Protocol Requirement

Query parameters require ClickHouse server version with protocol >= 54459 (ClickHouse 21.9+).

## Basic Usage

```erlang
% Connect to ClickHouse
{ok, Conn} = clickhouse_erl:connect("localhost", 9000).

% Execute query with a single parameter
{ok, Result} = clickhouse_erl:query(
    Conn,
    <<"SELECT * FROM users WHERE id = {user_id:UInt64}">>,
    #{parameters => [{<<"user_id">>, <<"12345">>}]}
).
```

**Parameter Format**: `[{Key :: binary(), Value :: binary()}]`
- Keys must match placeholder names in the query
- Values must be binary strings (ClickHouse performs type conversion)
- Placeholders use syntax: `{name:Type}`

## Multiple Parameters

```erlang
% Query with multiple parameters
{ok, Result} = clickhouse_erl:query(
    Conn,
    <<"SELECT * FROM users WHERE id = {id:UInt64} AND name = {name:String}">>,
    #{parameters => [
        {<<"id">>, <<"42">>},
        {<<"name">>, <<"Alice">>}
    ]}
).

% Parameter order is independent of placeholder order
{ok, Result2} = clickhouse_erl:query(
    Conn,
    <<"SELECT {b:String}, {a:UInt64}">>,
    #{parameters => [
        {<<"a">>, <<"1">>},
        {<<"b">>, <<"test">>}
    ]}
).
```

## INSERT with Parameters

```erlang
% Create a test table
clickhouse_erl:query(Conn, 
    <<"CREATE TABLE users (id UInt32, name String, age UInt8) ENGINE = Memory">>).

% INSERT with parameters
{ok, #{rows_inserted := 1}} = clickhouse_erl:insert(
    Conn,
    <<"INSERT INTO users (id, name, age) VALUES ({id:UInt32}, {name:String}, {age:UInt8})">>,
    [],  % No column data (using parameters instead)
    #{parameters => [
        {<<"id">>, <<"123">>},
        {<<"name">>, <<"Bob">>},
        {<<"age">>, <<"30">>}
    ]}
).

% Verify insertion
{ok, [[123, <<"Bob">>, 30]]} = clickhouse_erl:query(
    Conn,
    <<"SELECT * FROM users WHERE id = 123">>
).
```

## Error Handling

Query parameters provide comprehensive error handling:

```erlang
% Invalid parameter format (non-binary key)
case clickhouse_erl:query(Conn, <<"SELECT {id:UInt64}">>, 
    #{parameters => [{id, <<"123">>}]}) of
    {error, {invalid_parameter_key, id}} ->
        io:format("Parameter key must be binary~n")
end.

% Invalid parameter value (non-binary value)
case clickhouse_erl:query(Conn, <<"SELECT {id:UInt64}">>, 
    #{parameters => [{<<"id">>, 123}]}) of
    {error, {invalid_parameter_value, 123}} ->
        io:format("Parameter value must be binary~n")
end.

% Missing parameter
case clickhouse_erl:query(Conn, <<"SELECT {missing:UInt64}">>, 
    #{parameters => []}) of
    {error, {server_exception, ExceptionInfo}} ->
        % Server returns: "Substitution `missing` is not set"
        io:format("Server error: ~s~n", [maps:get(message, ExceptionInfo)])
end.

% Unsupported protocol version
case clickhouse_erl:query(Conn, <<"SELECT {id:UInt64}">>, 
    #{parameters => [{<<"id">>, <<"123">>}]}) of
    {error, {parameters_unsupported, Version}} ->
        io:format("Parameters not supported in protocol version ~p~n", [Version])
end.
```

**Error Types**:
- `{invalid_parameter_key, Key}` - Parameter key is not a binary
- `{invalid_parameter_value, Value}` - Parameter value is not a binary
- `{invalid_parameter_format, Param}` - Parameter is not a `{Key, Value}` tuple
- `{parameters_unsupported, Version}` - Server protocol version < 54459
- `{server_exception, ExceptionInfo}` - Server-side errors (missing substitution, type mismatch)

## Backward Compatibility

Queries without parameters continue to work as before:

```erlang
% Query without parameters option (backward compatible)
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

% Query with empty parameters map (equivalent to no parameters)
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>, #{}).

% Query with empty parameters list (sends empty Parameters field)
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>, #{parameters => []}).
```

## Best Practices

1. **Always use parameters for user input** to prevent SQL injection:
   ```erlang
   % ❌ UNSAFE: String concatenation
   UserId = <<"123">>,
   SQL = <<"SELECT * FROM users WHERE id = ", UserId/binary>>,
   clickhouse_erl:query(Conn, SQL).
   
   % ✅ SAFE: Use parameters
   clickhouse_erl:query(
       Conn,
       <<"SELECT * FROM users WHERE id = {user_id:UInt64}">>,
       #{parameters => [{<<"user_id">>, UserId}]}
   ).
   ```

2. **Specify correct types in placeholders** to ensure type safety:
   ```erlang
   % Correct type annotation
   #{parameters => [{<<"price">>, <<"99.99">>}]}  % {price:Float64}
   #{parameters => [{<<"active">>, <<"1">>}]}     % {active:UInt8}
   ```

3. **Handle version compatibility** when deploying to multiple environments:
   ```erlang
   execute_with_params(Conn, SQL, Params) ->
       case clickhouse_erl:query(Conn, SQL, #{parameters => Params}) of
           {error, {parameters_unsupported, _}} ->
               % Fallback to non-parameterized query
               execute_without_params(Conn, SQL, Params);
           Result ->
               Result
       end.
   ```
