# Compression Guide

ClickHouse Erlang client supports data compression for efficient network transfer. Compression reduces bandwidth usage and can significantly improve performance when transferring large datasets.

## Overview

**Supported Compression Methods**:
- **LZ4** - Fast compression with good compression ratios (default choice)
- **LZ4HC** - High compression variant with configurable levels (0-12)
- **ZSTD** - Better compression ratios at the cost of speed
- **None** - Uncompressed data with compression protocol wrapper

**Benefits**:
- Reduced network bandwidth (up to 10x for compressible data)
- Faster data transfer for large result sets
- Lower network costs in cloud environments
- Automatic checksum verification (CityHash128)

**Backward Compatibility**: Compression is disabled by default. Existing code continues to work without changes.

## Basic Usage

### LZ4 Compression (Recommended)

LZ4 provides the best balance of speed and compression ratio for most use cases:

```erlang
% Connect with LZ4 compression enabled
{ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{
    compression => lz4
}).

% All queries automatically use compression
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM large_table">>).

% INSERT operations also use compression
{ok, _} = clickhouse_erl:insert(Conn, <<"INSERT INTO users VALUES">>, ColumnData).
```

### ZSTD Compression

ZSTD offers better compression ratios when network bandwidth is more critical than CPU usage:

```erlang
% Connect with ZSTD compression
{ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{
    compression => zstd
}).

% Queries use ZSTD compression
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM analytics_data">>).
```

### LZ4HC with Compression Level

For maximum compression with LZ4, use LZ4HC with a compression level (0-12):

```erlang
% Connect with LZ4HC at level 9 (higher = better compression, slower)
{ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{
    compression => lz4,
    compression_level => 9
}).

% Standard LZ4 (fast mode) - no compression_level specified
{ok, Conn2} = clickhouse_erl:connect("localhost", 9000, #{
    compression => lz4
}).
```

**Compression Level Guidelines**:
- **0-3**: Fast compression, lower ratios
- **4-6**: Balanced compression (recommended for most cases)
- **7-9**: High compression, slower
- **10-12**: Maximum compression, significantly slower
- **No level specified**: Uses standard LZ4 (fastest)

### Disabled Compression (Default)

Compression is disabled by default for backward compatibility:

```erlang
% These are equivalent - no compression
{ok, Conn1} = clickhouse_erl:connect("localhost", 9000).
{ok, Conn2} = clickhouse_erl:connect("localhost", 9000, #{}).
{ok, Conn3} = clickhouse_erl:connect("localhost", 9000, #{compression => disabled}).
```

## Error Handling

Compression operations return clear error tuples for all failure cases:

```erlang
% Invalid compression method
case clickhouse_erl:connect("localhost", 9000, #{compression => invalid}) of
    {error, {invalid_compression_method, invalid}} ->
        io:format("Unsupported compression method~n")
end.

% Invalid compression level (must be 0-12)
case clickhouse_erl:connect("localhost", 9000, #{
    compression => lz4,
    compression_level => 15
}) of
    {error, {invalid_compression_level, 15}} ->
        io:format("Compression level must be between 0 and 12~n")
end.

% Missing compression library
case clickhouse_erl:connect("localhost", 9000, #{compression => zstd}) of
    {error, {compression_library_missing, zstd}} ->
        io:format("ZSTD library not installed~n")
end.

% Server-side compression errors
case clickhouse_erl:query(Conn, <<"SELECT * FROM table">>) of
    {error, {server_error, unknown_compression_method}} ->
        io:format("Server doesn't support this compression method~n");
    {error, {server_error, cannot_decompress}} ->
        io:format("Server failed to decompress data~n");
    {error, {server_error, cannot_compress}} ->
        io:format("Server failed to compress response~n")
end.

% Checksum verification failure (data corruption)
case clickhouse_erl:query(Conn, <<"SELECT * FROM table">>) of
    {error, {checksum_mismatch, #{expected := Expected, actual := Actual}}} ->
        io:format("Data corruption detected: expected ~p, got ~p~n", [Expected, Actual])
end.
```

**Error Types**:
- `{invalid_compression_method, Method}` - Unsupported compression method
- `{invalid_compression_level, Level}` - Level outside range 0-12
- `{compression_library_missing, Method}` - Required library not installed
- `{compression_failed, Reason}` - Compression operation failed
- `{decompression_failed, Reason}` - Decompression operation failed
- `{checksum_mismatch, Details}` - Data corruption detected
- `{size_mismatch, Details}` - Decompressed size doesn't match expected
- `{server_error, unknown_compression_method}` - Server error code 89
- `{server_error, cannot_compress}` - Server error code 270
- `{server_error, cannot_decompress}` - Server error code 271

## Performance Considerations

### When to Use Compression

**Use compression when**:
- Transferring large result sets (>1MB)
- Network bandwidth is limited or expensive
- Data is highly compressible (text, logs, repeated values)
- Network latency is higher than compression overhead

**Skip compression when**:
- Transferring small datasets (<1KB)
- Data is already compressed (images, videos)
- CPU is more constrained than network
- Local network with high bandwidth

### Compression Method Selection

**LZ4 (Recommended)**:
- Best for most use cases
- Very fast compression/decompression
- Good compression ratios (2-3x typical)
- Low CPU overhead
- Use when: Speed is important, network is reasonably fast

**LZ4HC (High Compression)**:
- Better compression ratios than standard LZ4
- Slower compression, same decompression speed
- Configurable levels (0-12)
- Use when: Network bandwidth is limited, can afford compression time

**ZSTD**:
- Best compression ratios (3-5x typical)
- Slower than LZ4 for both compression and decompression
- Use when: Network bandwidth is very limited, maximum compression needed

**Performance Comparison** (approximate, varies by data):

| Method | Compression Speed | Decompression Speed | Compression Ratio | CPU Usage |
|--------|------------------|---------------------|-------------------|-----------|
| LZ4 | Very Fast | Very Fast | Good (2-3x) | Low |
| LZ4HC (level 6) | Medium | Very Fast | Better (3-4x) | Medium |
| LZ4HC (level 12) | Slow | Very Fast | Best LZ4 (4-5x) | High |
| ZSTD | Medium | Fast | Best (3-5x) | Medium-High |

### Benchmarking

Test compression performance with your actual data:

```erlang
% Benchmark query with and without compression
benchmark_compression() ->
    % Without compression
    {ok, Conn1} = clickhouse_erl:connect("localhost", 9000),
    {Time1, {ok, _}} = timer:tc(fun() ->
        clickhouse_erl:query(Conn1, <<"SELECT * FROM large_table">>)
    end),
    io:format("Without compression: ~p ms~n", [Time1 div 1000]),
    
    % With LZ4 compression
    {ok, Conn2} = clickhouse_erl:connect("localhost", 9000, #{compression => lz4}),
    {Time2, {ok, _}} = timer:tc(fun() ->
        clickhouse_erl:query(Conn2, <<"SELECT * FROM large_table">>)
    end),
    io:format("With LZ4 compression: ~p ms~n", [Time2 div 1000]),
    
    % Calculate improvement
    Improvement = (Time1 - Time2) / Time1 * 100,
    io:format("Performance improvement: ~.1f%~n", [Improvement]).
```

## Best Practices

1. **Start with LZ4** - It provides the best balance for most use cases:
   ```erlang
   {ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{compression => lz4}).
   ```

2. **Use ZSTD for bandwidth-constrained environments**:
   ```erlang
   % Cloud environments with expensive bandwidth
   {ok, Conn} = clickhouse_erl:connect("remote-server", 9000, #{compression => zstd}).
   ```

3. **Tune LZ4HC level based on your needs**:
   ```erlang
   % Balanced: level 6 (good compression, reasonable speed)
   {ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{
       compression => lz4,
       compression_level => 6
   }).
   ```

4. **Handle compression errors gracefully**:
   ```erlang
   connect_with_compression(Host, Port, Method) ->
       case clickhouse_erl:connect(Host, Port, #{compression => Method}) of
           {ok, Conn} ->
               {ok, Conn};
           {error, {compression_library_missing, _}} ->
               % Fallback to no compression
               io:format("Compression library missing, using uncompressed connection~n"),
               clickhouse_erl:connect(Host, Port);
           {error, Reason} ->
               {error, Reason}
       end.
   ```

5. **Test with your actual data** - Compression effectiveness varies significantly:
   ```erlang
   % Highly compressible: text, logs, repeated values
   % Less compressible: random data, already compressed data
   % Always benchmark with representative queries
   ```

## Installation Requirements

### LZ4

Requires lz4 library installed on the system:

```bash
# macOS (Homebrew)
brew install lz4

# Ubuntu/Debian
apt-get install liblz4-dev

# Nix (if using flake.nix)
# Already included in development environment
```

### ZSTD

Requires ezstd Erlang library (automatically fetched by rebar3):

```erlang
% rebar.config already includes:
{deps, [
    {ezstd, "1.0.4"}
]}.
```

### Verification

Check if compression libraries are available:

```erlang
% Check LZ4 availability
case clickhouse_erl_compression:is_available(lz4) of
    true -> io:format("LZ4 available~n");
    false -> io:format("LZ4 not available~n")
end.

% Check ZSTD availability
case clickhouse_erl_compression:is_available(zstd) of
    true -> io:format("ZSTD available~n");
    false -> io:format("ZSTD not available~n")
end.
```
