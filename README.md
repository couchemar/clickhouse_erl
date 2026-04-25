# clickhouse_erl

A native ClickHouse client for Erlang/OTP using the binary TCP protocol (port 9000).

This is a low-level library focused on protocol implementation. For connection pooling, use existing Erlang libraries like [poolboy](https://github.com/devinus/poolboy) or [worker_pool](https://github.com/inaka/worker_pool).

## Project Status

**Version**: 0.1.0  
**Status**: Active development

## Features

- **Native Binary Protocol**: Direct TCP communication (port 9000)
- **Query Execution**: SELECT and INSERT operations
- **Query Parameters**: Parameterized queries with type validation
- **Query Settings**: Flexible settings API
- **Compression**: LZ4, LZ4HC, and ZSTD support
- **Comprehensive Type System**: Primitives, temporals, decimals, enums, network types, composites
- **OTP Supervision**: Fault-isolated connections
- **Streaming**: Large result set handling with `on_data` callbacks
- **Streaming Insert**: Multi-block data ingestion with pull-based and push-based patterns ([guide](doc/streaming-insert.md))
- **Server Logs**: Receive ClickHouse server log entries via `on_log` callback ([guide](doc/server_logs.md))

## Installation

Add to your `rebar.config`:

```erlang
{deps, [
    {clickhouse_erl, {git, "https://github.com/your-org/clickhouse_erl.git", {branch, "main"}}}
]}.
```

## Quick Start

```erlang
% Start application
application:start(clickhouse_erl).

% Connect
{ok, Conn} = clickhouse_erl:connect("localhost", 9000).

% Query
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT version()">>).

% Query with parameters
{ok, Result} = clickhouse_erl:query(
    Conn,
    <<"SELECT * FROM users WHERE id = {user_id:UInt64}">>,
    #{parameters => [{<<"user_id">>, <<"123">>}]}
).

% Insert data
SQL = <<"INSERT INTO users (id, name) VALUES">>,
Input = [
    #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2, 3]},
    #{name => <<"name">>, type => <<"String">>, data => [<<"Alice">>, <<"Bob">>, <<"Charlie">>]}
],
{ok, _} = clickhouse_erl:insert(Conn, SQL, Input).

% Streaming callback (process rows without accumulating entire result)
Callback = fun
    ({data, #{name := Name, value := Value}}, Acc) ->
        Existing = maps:get(Name, Acc, []),
        {ok, Acc#{Name => [Value | Existing]}};
    ('end', Acc) ->
        {ok, maps:map(fun(_K, V) -> lists:reverse(V) end, Acc)}
end,
{ok, StreamResult} = clickhouse_erl:query(Conn, <<"SELECT name, salary FROM employees">>, #{
    on_data => Callback,
    initial_accumulator => #{}
}).
%% StreamResult: #{data => #{<<"name">> => [...], <<"salary">> => [...]}}

% Disconnect
clickhouse_erl:disconnect(Conn).
```

## Compression

Enable compression for better network efficiency:

```erlang
% LZ4 (recommended)
{ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{compression => lz4}).

% ZSTD (better compression)
{ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{compression => zstd}).

% LZ4HC with level
{ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{
    compression => lz4,
    compression_level => 9
}).
```

## Supported Types

### Primitive Types
UInt8-64, Int8-64, Float32/64, String, FixedString, Boolean

### Temporal Types
Date, Date32, DateTime, DateTime64, Time, Time64

### Extended Types
- **Extended Integers**: Int128, Int256, UInt128, UInt256
- **Decimals**: Decimal32/64/128/256
- **Enums**: Enum8/16
- **Network**: IPv4, IPv6
- **Special**: UUID, Point, Interval, JSON, Nothing

### Composite Types
Array, Tuple, Map, Nullable, LowCardinality

## Documentation

- [Query Parameters Guide](doc/query_parameters.md) - Parameterized queries
- [Query Settings Guide](doc/query_settings.md) - ClickHouse settings
- [Query Lifecycle Guide](doc/query_lifecycle.md) - Timeouts and cancellation
- [Compression Guide](doc/compression.md) - Compression options
- [Extended Types Guide](doc/extended_types.md) - Extended type system
- [Composite Types Guide](doc/composite_types_guide.md) - Complex types
- [INSERT Guide](doc/insert_guide.md) - Data insertion
- [Streaming Insert Guide](doc/streaming-insert.md) - Multi-block streaming inserts
- [Error Handling](doc/error_handling.md) - Error types and handling
- [Server Logs Guide](doc/server_logs.md) - Receiving server log entries

## Testing

```bash
# Unit tests
rebar3 eunit

# Property tests
rebar3 proper

# Common Test suites
rebar3 ct

# All tests
rebar3 eunit && rebar3 proper && rebar3 ct
```

Integration tests require a running ClickHouse server:

```bash
docker-compose up -d
rebar3 eunit
docker-compose down
```

## Future Enhancements

- Metrics collection and observability
- Query result streaming with backpressure
- Batch INSERT optimizations
- Automatic reconnection with exponential backoff
- JSON Object Serialization (requires Dynamic type support)

## Contributing

### Requirements
- Erlang/OTP 27+
- ClickHouse server for integration tests
- LZ4 library for compression
- Rebar3

### Standards
- All modules start with `clickhouse_erl_` prefix
- Use OTP behaviors (gen_server, supervisor)
- Return `{ok, Result} | {error, Reason}` tuples
- TDD - write failing tests first
- Zero compilation and dialyzer warnings
- All exports have `-spec` and `@doc`

### Workflow
```bash
rebar3 compile    # Check warnings
rebar3 eunit      # Unit tests
rebar3 proper     # Property tests
rebar3 ct         # Integration tests
rebar3 dialyzer   # Type checking
erlfmt -w src/*.erl test/*.erl  # Format
rebar3 lint       # Lint
```

## Acknowledgments

- [ClickHouse](https://github.com/ClickHouse/ClickHouse) - Official implementation
- [ch-go](https://github.com/ClickHouse/ch-go) - Go client (protocol reference)
- [clickhouse-cpp](https://github.com/ClickHouse/clickhouse-cpp) - C++ client

## Support

- **Issues**: GitHub Issues
- **Documentation**: See `doc/` directory
