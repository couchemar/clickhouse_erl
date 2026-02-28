# INSERT Quick Reference

Quick reference card for INSERT operations with `clickhouse_erl`.

## Basic Syntax

```erlang
SQL = <<"INSERT INTO table_name (col1, col2, col3) VALUES">>,
Input = [
    #{name => <<"col1">>, type => <<"Type1">>, data => [Val1, Val2, ...]},
    #{name => <<"col2">>, type => <<"Type2">>, data => [Val1, Val2, ...]},
    #{name => <<"col3">>, type => <<"Type3">>, data => [Val1, Val2, ...]}
],
{ok, Result} = clickhouse_erl:insert(Conn, SQL, Input).
```

## Data Types Quick Reference

| ClickHouse Type | Erlang Type | Example |
|----------------|-------------|---------|
| `UInt8` | `0..255` | `[0, 128, 255]` |
| `UInt16` | `0..65535` | `[0, 1000, 65535]` |
| `UInt32` | `0..4294967295` | `[0, 1000000, 4294967295]` |
| `UInt64` | `0..18446744073709551615` | `[0, 1000000000, 18446744073709551615]` |
| `Int8` | `-128..127` | `[-128, 0, 127]` |
| `Int16` | `-32768..32767` | `[-32768, 0, 32767]` |
| `Int32` | `-2147483648..2147483647` | `[-2147483648, 0, 2147483647]` |
| `Int64` | `-9223372036854775808..9223372036854775807` | `[-9223372036854775808, 0, 9223372036854775807]` |
| `Float32` | `float()` | `[3.14, -2.71, 0.0]` |
| `Float64` | `float()` | `[3.141592653589793, -2.718281828459045]` |
| `String` | `binary()` | `[<<"Hello">>, <<"World">>]` |
| `Bool` | `true \| false` | `[true, false, true]` |
| `Date` | `{Y, M, D}` | `[{2023, 1, 1}, {2023, 12, 31}]` |
| `DateTime` | `{{Y,M,D}, {H,M,S}}` | `[{{2023, 1, 1}, {12, 0, 0}}]` |
| `DateTime64(6)` | `{{Y,M,D}, {H,M,S,Us}}` | `[{{2023, 1, 1}, {12, 0, 0, 123456}}]` |

## Common Patterns

### Insert Single Row

```erlang
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1]},
    #{name => <<"name">>, type => <<"String">>, data => [<<"Alice">>]}
],
{ok, _} = clickhouse_erl:insert(Conn, SQL, Input).
```

### Insert Multiple Rows

```erlang
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2, 3]},
    #{name => <<"name">>, type => <<"String">>, data => [<<"Alice">>, <<"Bob">>, <<"Charlie">>]}
],
{ok, _} = clickhouse_erl:insert(Conn, SQL, Input).
```

### Insert with Timeout

```erlang
Options = #{timeout => 30000},  % 30 seconds
{ok, _} = clickhouse_erl:insert(Conn, SQL, Input, Options).
```

### Empty Insert (0 rows)

```erlang
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => []},
    #{name => <<"name">>, type => <<"String">>, data => []}
],
{ok, #{rows_inserted := 0}} = clickhouse_erl:insert(Conn, SQL, Input).
```

## Error Handling Patterns

### Basic Error Handling

```erlang
case clickhouse_erl:insert(Conn, SQL, Input) of
    {ok, #{rows_inserted := N}} ->
        io:format("Inserted ~p rows~n", [N]);
    {error, Reason} ->
        io:format("Error: ~s~n", [clickhouse_erl:format_error(Reason)])
end.
```

### Specific Error Handling

```erlang
case clickhouse_erl:insert(Conn, SQL, Input) of
    {ok, Result} ->
        {ok, Result};
    {error, {row_count_mismatch, _}} ->
        {error, validation_error};
    {error, {server_exception, #{error_code := 16}}} ->
        {error, column_not_found};
    {error, {server_exception, #{error_code := 53}}} ->
        {error, type_mismatch};
    {error, {send_failed, _}} ->
        {error, network_error};
    {error, Reason} ->
        {error, Reason}
end.
```

## Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `{row_count_mismatch, _}` | Columns have different row counts | Ensure all columns have same number of values |
| `{invalid_column_name, _}` | Column name is not binary | Use `<<"name">>` instead of `"name"` |
| `{type_mismatch, _, _, _}` | Data doesn't match type | Check data values match ClickHouse type |
| `{server_exception, #{error_code := 16}}` | Column not in table | Verify column names match table schema |
| `{server_exception, #{error_code := 53}}` | Server-side type mismatch | Check type string matches table definition |
| `{server_exception, #{error_code := 60}}` | Table doesn't exist | Create table or check table name |
| `{send_failed, closed}` | Connection closed | Reconnect to server |
| `{send_failed, timeout}` | Network timeout | Increase timeout or check network |

## Performance Tips

1. **Batch inserts**: Insert 1000-10000 rows per batch for optimal performance
2. **Use binary strings**: Always use `<<"string">>` not `"string"`
3. **Pre-validate data**: Check row counts and types before calling insert
4. **Monitor metrics**: Track `rows_inserted` and `elapsed_time` in results
5. **Connection pooling**: Reuse connections for multiple inserts
6. **Appropriate timeouts**: Set timeouts based on data size

## Result Format

```erlang
#{
    rows_inserted => non_neg_integer(),  % Number of rows inserted
    elapsed_time => non_neg_integer()    % Server processing time in milliseconds
}
```

## See Also

- [INSERT Guide](insert_guide.md) - Comprehensive documentation
- [Examples](examples.md) - Practical code examples
- [Error Handling](error_handling.md) - Detailed error information
