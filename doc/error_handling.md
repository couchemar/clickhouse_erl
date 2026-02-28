# Error Handling in clickhouse_erl

The `clickhouse_erl` library provides structured error reporting to help diagnose issues ranging from network failures to server-side exceptions.

## Error Format

Most functions return either `{ok, Result}` or `{error, Reason}`. The `Reason` is typically a tuple or an atom.

## Types of Errors

### Network Errors

Occur during connection establishment or packet transmission.

- `{network_error, Reason}`: TCP-level errors (e.g., `econnrefused`, `closed`).
- `{timeout_error, Phase}`: Operation timed out during a specific phase (e.g., `connect`, `query_execution`).

### Protocol Errors

Occur when the data received from or sent to the server doesn't match the expected ClickHouse protocol format.

- `{protocol_error, Reason}`: General protocol violation.
- `{decoding_error, Details}`: Failed to parse a server packet.
- `{encoding_error, Field}`: Failed to encode data for transmission.

### Server Exceptions

When ClickHouse encountered an error while processing a query, it returns a structured exception packet.

- `{server_exception, ExceptionInfo}`: A server-side error.

#### ExceptionInfo Record

The `ExceptionInfo` is a record (defined in `clickhouse_erl_protocol.hrl`) containing:

- `error_code`: ClickHouse error code (e.g., 60 for `UNKNOWN_TABLE`).
- `exception_name`: Name of the exception (e.g., `<<"DB::Exception">>`).
- `message`: Detailed error message.
- `stack_trace`: Server-side stack trace.
- `nested_exceptions`: List of nested exception records if applicable.

#### Common Error Codes

| Code | Name | Description |
|------|------|-------------|
| 16 | NO_SUCH_COLUMN_IN_TABLE | Column mentioned in INSERT/SELECT doesn't exist. |
| 47 | UNKNOWN_IDENTIFIER | Unknown table or alias. |
| 53 | TYPE_MISMATCH | Data type doesn't match schema. |
| 60 | UNKNOWN_TABLE | The table does not exist. |
| 159 | TIMEOUT_EXCEEDED | Query exceeded server-side timeout. |

For a complete list of error codes, see `clickhouse_erl_error_codes.erl`.

### INSERT-Specific Errors

INSERT operations can encounter additional validation errors before data is sent to the server:

#### Row Count Mismatch

All columns in an INSERT must have the same number of rows.

```erlang
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2, 3]},
    #{name => <<"name">>, type => <<"String">>, data => [<<"Alice">>, <<"Bob">>]}  % Only 2 values
],
{error, {row_count_mismatch, [{<<"id">>, 3}, {<<"name">>, 2}]}} = 
    clickhouse_erl:insert(Conn, SQL, Input).
```

#### Invalid Column Name

Column names must be binary strings.

```erlang
Input = [
    #{name => "id", type => <<"UInt64">>, data => [1, 2]}  % String instead of binary
],
{error, {invalid_column_name, "id"}} = clickhouse_erl:insert(Conn, SQL, Input).
```

#### Type Encoding Errors

Data values must be compatible with the specified ClickHouse type.

```erlang
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, <<"not_a_number">>, 3]}
],
{error, {type_mismatch, <<"id">>, <<"UInt64">>, Reason}} = 
    clickhouse_erl:insert(Conn, SQL, Input).
```

For detailed INSERT error handling examples, see the [INSERT Guide](insert_guide.md#error-handling).

## Formatting Errors

Use `clickhouse_erl:format_error/1` to get a human-readable description of any error returned by the library.

```erlang
case clickhouse_erl:query(Conn, "INVALID SQL") of
    {error, Reason} ->
        io:format("Error: ~s~n", [clickhouse_erl:format_error(Reason)])
end.
```
