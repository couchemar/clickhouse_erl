# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0](https://github.com/couchemar/clickhouse_erl/releases/tag/v0.1.0) - 2026-02-28

Initial public release.

### Added

#### Core Protocol
- Native binary TCP protocol implementation (port 9000)
- Connection management with OTP supervision
- SELECT and INSERT query execution
- Query parameters with type validation (requires protocol >= 54459)
- Query settings API (map, keyword list, and protocol formats)
- Query lifecycle management (timeout, cancellation)
- Streaming result sets
- Compression support (LZ4, LZ4HC with levels 0-12, ZSTD)
- Comprehensive error handling with detailed error codes

#### Type System
- **Primitive types**: UInt8-64, Int8-64, Float32/64, String, FixedString, Boolean
- **Temporal types**: Date, Date32, DateTime, DateTime64 (with timezone), Time, Time64
- **Extended integers**: Int128, Int256, UInt128, UInt256
- **Decimal types**: Decimal32/64/128/256 for fixed-precision arithmetic
- **Enum types**: Enum8/16 for categorical data
- **Network types**: IPv4, IPv6
- **Special types**: UUID, Point, Interval, JSON (string serialization), Nothing
- **Composite types**: Array, Tuple, Map, Nullable, LowCardinality

#### Architecture
- OTP behaviors (gen_server, supervisor) for fault tolerance
- Supervision tree with connection isolation
- Response handler for streaming
- Query manager for request coordination
- Compression engine with CityHash128 checksum verification

#### Testing
- Comprehensive unit tests (EUnit)
- Property-based tests (PropEr)
- Integration tests (Common Test suites)
- Test coverage for all type codecs and protocol handlers

#### Documentation
- Complete API documentation
- Query parameters guide
- Query settings guide
- Query lifecycle guide
- Compression guide
- Extended types guide
- Composite types guide
- INSERT guide
- Error handling guide
- Usage examples

### Dependencies
- Erlang/OTP 27+
- ezstd 1.0.4 (for ZSTD compression)
- LZ4 library (system dependency for LZ4 compression)

### Notes
- This is a low-level library focused on protocol implementation
- For connection pooling, use existing Erlang libraries (poolboy, worker_pool)
- Compression is disabled by default for backward compatibility
- JSON type requires `output_format_native_write_json_as_string=1` setting

[0.1.0]: https://github.com/your-org/clickhouse_erl/releases/tag/v0.1.0
