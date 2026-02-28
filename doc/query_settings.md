# Query Settings Guide

ClickHouse settings control query execution behavior, resource limits, and output formats. The client supports three input formats for maximum flexibility.

## Simple Map Format (Recommended)

The simplest way to pass settings:

```erlang
{ok, Conn} = clickhouse_erl:connect("localhost", 9000).

{ok, Result} = clickhouse_erl:query(
    Conn,
    <<"SELECT * FROM large_table">>,
    #{settings => #{
        <<"max_threads">> => <<"4">>,
        <<"max_memory_usage">> => <<"10000000000">>
    }}
).
```

**Format**: `#{Key :: binary() => Value :: binary()}`
- Keys and values must be binary strings
- Settings are automatically converted to protocol format
- Default flags are applied (important=false, custom=false, obsolete=false)

## Keyword List Format

For developers familiar with Erlang conventions:

```erlang
{ok, Result} = clickhouse_erl:query(
    Conn,
    <<"SELECT * FROM large_table">>,
    #{settings => [
        {<<"max_threads">>, <<"4">>},
        {<<"max_memory_usage">>, <<"10000000000">>}
    ]}
).
```

**Format**: `[{Key :: binary(), Value :: binary()}]`
- Each setting is a `{Key, Value}` tuple
- Keys and values must be binary strings
- Equivalent to map format with same defaults

## Common Settings Examples

```erlang
% Limit query execution resources
{ok, Result} = clickhouse_erl:query(
    Conn,
    <<"SELECT count(*) FROM events WHERE date >= today() - 7">>,
    #{settings => #{
        <<"max_execution_time">> => <<"30">>,        % 30 seconds timeout
        <<"max_memory_usage">> => <<"5000000000">>,  % 5GB memory limit
        <<"max_threads">> => <<"8">>                 % Use 8 threads
    }}
).

% Control output format
{ok, Result} = clickhouse_erl:query(
    Conn,
    <<"SELECT * FROM users">>,
    #{settings => #{
        <<"output_format_native_write_json_as_string">> => <<"1">>,
        <<"date_time_output_format">> => <<"iso">>
    }}
).

% Enable query profiling
{ok, Result} = clickhouse_erl:query(
    Conn,
    <<"SELECT * FROM large_table">>,
    #{settings => #{
        <<"send_progress_in_http_headers">> => <<"1">>,
        <<"log_queries">> => <<"1">>,
        <<"log_query_threads">> => <<"1">>
    }}
).
```

## Advanced: Protocol Format with Flags

For advanced use cases requiring protocol-level control:

```erlang
{ok, Result} = clickhouse_erl:query(
    Conn,
    <<"SELECT * FROM table">>,
    #{settings => [
        #{
            key => <<"custom_setting">>,
            value => <<"value">>,
            important => true,    % Setting is important
            custom => true,       % Custom user setting
            obsolete => false     % Not obsolete
        }
    ]}
).
```

**When to use flags**:
- `important => true` - Setting must be recognized by server (query fails if unknown)
- `custom => true` - User-defined custom setting
- `obsolete => false` - Setting is not deprecated

**Note**: Most users don't need flags. Use simple map or keyword list format unless you have specific protocol requirements.

## Error Handling

```erlang
% Invalid setting format (non-binary key)
case clickhouse_erl:query(Conn, <<"SELECT 1">>, 
    #{settings => #{key => <<"value">>}}) of
    {error, {invalid_settings_format, _}} ->
        io:format("Setting keys must be binary~n")
end.

% Invalid setting value (non-binary value)
case clickhouse_erl:query(Conn, <<"SELECT 1">>, 
    #{settings => #{<<"key">> => value}}) of
    {error, {invalid_settings_format, _}} ->
        io:format("Setting values must be binary~n")
end.

% Unknown setting (server-side error)
case clickhouse_erl:query(Conn, <<"SELECT 1">>, 
    #{settings => #{<<"unknown_setting">> => <<"value">>}}) of
    {error, {server_exception, ExceptionInfo}} ->
        % Server returns: "Unknown setting unknown_setting"
        io:format("Server error: ~s~n", [maps:get(message, ExceptionInfo)])
end.
```

**Error Types**:
- `{invalid_settings_format, Settings}` - Settings format is invalid
- `{server_exception, ExceptionInfo}` - Server-side errors (unknown setting, invalid value)

## Backward Compatibility

Queries without settings continue to work:

```erlang
% Query without settings option (backward compatible)
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>).

% Query with empty settings map (equivalent to no settings)
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>, #{}).

% Query with empty settings list (sends empty Settings field)
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>, #{settings => []}).

% Existing protocol format continues to work
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>, 
    #{settings => [#{key => <<"max_threads">>, value => <<"4">>}]}).
```

## Best Practices

1. **Use simple map format for clarity**:
   ```erlang
   % ✅ Good: Simple map format
   #{settings => #{<<"max_threads">> => <<"4">>}}
   
   % ❌ Verbose: Protocol format (unnecessary for most cases)
   #{settings => [#{key => <<"max_threads">>, value => <<"4">>, 
                    important => false, custom => false, obsolete => false}]}
   ```

2. **Always use binary strings**:
   ```erlang
   % ✅ Good: Binary strings
   #{settings => #{<<"max_threads">> => <<"4">>}}
   
   % ❌ Bad: Atoms or strings
   #{settings => #{max_threads => "4"}}
   ```

3. **Set resource limits for production queries**:
   ```erlang
   #{settings => #{
       <<"max_execution_time">> => <<"60">>,
       <<"max_memory_usage">> => <<"10000000000">>,
       <<"max_rows_to_read">> => <<"1000000000">>
   }}
   ```

4. **Handle server errors gracefully**:
   ```erlang
   execute_with_settings(Conn, SQL, Settings) ->
       case clickhouse_erl:query(Conn, SQL, #{settings => Settings}) of
           {ok, Result} ->
               {ok, Result};
           {error, {server_exception, #{code := 115}}} ->
               % UNKNOWN_SETTING error - retry without settings
               io:format("Setting not supported, retrying without settings~n"),
               clickhouse_erl:query(Conn, SQL);
           {error, Reason} ->
               {error, Reason}
       end.
   ```

## Migration Guide

If you're using the verbose protocol format, you can simplify:

```erlang
% Before (verbose protocol format)
clickhouse_erl:query(Conn, SQL, #{
    settings => [
        #{key => <<"max_threads">>, value => <<"4">>, 
          important => false, custom => false, obsolete => false},
        #{key => <<"max_memory_usage">>, value => <<"10000000000">>, 
          important => false, custom => false, obsolete => false}
    ]
}).

% After (simple map format - recommended)
clickhouse_erl:query(Conn, SQL, #{
    settings => #{
        <<"max_threads">> => <<"4">>,
        <<"max_memory_usage">> => <<"10000000000">>
    }
}).

% Or keyword list format (alternative)
clickhouse_erl:query(Conn, SQL, #{
    settings => [
        {<<"max_threads">>, <<"4">>},
        {<<"max_memory_usage">>, <<"10000000000">>}
    ]
}).
```
