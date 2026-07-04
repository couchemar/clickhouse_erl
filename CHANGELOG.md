# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0](https://github.com/couchemar/clickhouse_erl/releases/tag/v0.5.0) - 2026-07-04

### Added
- `block_end` event in streaming callbacks — dispatched after all column values for a non-empty block have been delivered, enabling bounded-memory row transposition and batch-aligned processing
- `type_to_binary/1` shared function in `clickhouse_erl_types_composite` — single source of truth for type atom → binary string conversion (deduplicates from 5 modules)
- `column_def()` type — schema-only column definitions without `data` key for streaming insert APIs
- `column_type()` typedef expanded with `bool`, `int128`, `uint128`, `int256`, `uint256`, `nothing`
- Bool type support in composite types (Nullable(Bool), Tuple(Int64, Bool), Array(Bool), etc.)
- Streaming queries documentation in `doc/streaming-queries.md`
- Property test for type serialization round-trip (`prop_type_to_binary_roundtrip`)

### Changed
- Streaming insert callbacks use arity-1 (`fun(Acc)`) — engine merges `type` from column definitions automatically
- Server version compatibility check removed upper bound (supports ClickHouse 26.x+)
- `clickhouse_erl_streaming_helpers` extracted from connection module (god_modules lint fix)
- `ensure_binary_sql/1` helper extracted in `clickhouse_erl_app` (DRY fix)

## [0.4.0](https://github.com/couchemar/clickhouse_erl/releases/tag/v0.4.0) - 2026-04-25

### Added
- Streaming insert support with two patterns:
  - Pull-based (`streaming_insert/3,4`) — engine calls `on_input` callback repeatedly
  - Push-based (`start_streaming_insert/3,4` + `send_data/3` + `finish_streaming_insert/2`) — caller pushes blocks explicitly
- Per-block compression support for streaming inserts (LZ4, ZSTD, disabled)
- Timeout and cancellation support for both streaming insert modes
- Connection state recovery after streaming insert success or failure
- Detailed documentation in `doc/streaming-insert.md`

## [0.3.0](https://github.com/couchemar/clickhouse_erl/releases/tag/v0.3.0) - 2026-04-12

### Changed
- Unified batch and streaming query paths — batch mode now uses a default `on_data` callback (`default_on_data_callback/2`) instead of a separate column accumulation path
- Streaming data events now include column type: `{data, #{name => ColName, type => ColType, value => Value}}`
- `clickhouse_erl_app`: extracted `add_optional_callbacks/2` helper to DRY callback option forwarding for both `query/3` and `insert/4`

### Added
- `on_log` callback option for receiving server log entries during query execution — pass `#{on_log => fun(LogEntry) -> ok end}` in query options
- `default_on_log_callback/1` — default callback that logs server entries via `?LOG_DEBUG` with structured metadata when no user callback is provided
- `default_on_data_callback/2` — batch-accumulating callback that collects column values and transposes to `#{columns, rows}` on `'end'`
- `default_callback_acc()` and `batch_result()` types exported from connection module

### Fixed
- `clickhouse_erl_types_time`: `encode_time64/1` for raw integer input now correctly converts through `time64_to_nanoseconds/1`

### Removed
- `finalize_current_column/1`, `find_and_merge_column/3,4`, `transpose_columns_to_rows/1` — replaced by default callback
- Batch-mode branching in `dispatch_column_value/5`, `finalize_streaming_end/1`, and `build_query_result/1`

## [0.2.0](https://github.com/couchemar/clickhouse_erl/releases/tag/v0.2.0) - 2026-03-21

### Added
- Event-driven streaming parser (`clickhouse_erl_parser` + `src/parsers/`) with dedicated modules for all server packet types: SERVER_HELLO, SERVER_DATA, SERVER_EXCEPTION, SERVER_PROGRESS, SERVER_PONG, SERVER_END_OF_STREAM, SERVER_PROFILE, SERVER_LOG, SERVER_TABLE_COLUMNS, SERVER_PART_UUIDS, SERVER_READ_TASK_REQUEST
- `clickhouse_erl_parser_behaviour` module defining `-callback` declarations (`init/1`, `parse/2`) and exported types (`parser_state/0`, `event/0`, `parse_result/0`)
- `clickhouse_erl_connection.hrl` header for shared connection state record
- True streaming callbacks with column-name-tagged events via `on_data` query option
- User-controlled result finalization via `'end'` event in streaming callback
- `initial_accumulator` query option for streaming mode state management
- Compression support in block parser (LZ4, ZSTD) — decompresses inline after temp table name
- Complex/composite type support in block parser: Nullable, Array, Tuple, Map, LowCardinality (column-level decoding)
- `LowCardinality(Nullable(T))` wire format support — dictionary index 0 maps to `null`, Nullable wrapper stripped for dictionary decoding

### Changed
- Connection module rewritten to use event-driven parser — TCP data flows through `clickhouse_erl_parser:parse/2`, events processed via tail-recursive `process_events_loop/5`
- Streaming mode callback signature: `fun({data, #{name => ColName, value => Value}}, Acc) -> {ok, NewAcc}; ('end', Acc) -> {ok, FinalAcc} end`
- Streaming mode result format: `#{data => FinalAccumulator}`
- Parser manages its own internal buffer — no connection-level buffer or double buffering
- All 11 parser modules implement `-behaviour(clickhouse_erl_parser_behaviour)`
- Connection module event processing uses explicit tail recursion (`process_events_loop/5`, `process_single_event/5`) instead of `lists:foldl` + `throw`
- Extracted helper functions in connection module: `finalize_streaming_end/1`, `accumulate_exception_field/3`, `dispatch_column_value/5`, `invoke_streaming_callback/6`, `receive_pong_data/2`, `handle_pong_tcp_data/3`
- Refactored `clickhouse_erl_exception` to extract `format_stack_trace_suffix/1` and `is_schema_error_code/1` helpers
- Refactored `clickhouse_erl_protocol_data_block` to merge custom serialization check into `maybe_consume_custom_flag/3` (DRY fix)
- IPv4 encode/decode uses little-endian byte order to match ClickHouse wire format
- `clickhouse_erl_protocol_server_hello:parse/1` now returns `{ok, Info, Rest}` 3-tuple with unconsumed bytes

### Removed
- `clickhouse_erl_response_handler` module (replaced by event-driven parser)
- `clickhouse_erl_callback_event_adapter` module (streaming callbacks are now direct)
- `get_default_on_data_callback` (batch mode uses existing column accumulation path)
- ~718 lines of dead code from connection module: `parse_packet_stream`, `parse_packet_data`, `process_handler_result`, `packet_type_name`, `propagate_exception_to_queries`, `update_state_if_not_cancelled`, `cancel_timer_and_reply_ok`, `is_truncated_data_error`, `handle_packet_error`
- `handler_state` field from `active_query_state()` type
- Connection-level `buffer` and `parsing_state` fields (parser manages buffer internally)
- Test files: `clickhouse_erl_response_handler_tests`, `prop_clickhouse_erl_response_handler`, `clickhouse_erl_response_handler_event_processing_tests`, `clickhouse_erl_response_handler_state_machine_tests`, `prop_clickhouse_erl_response_handler_state_machine`, `clickhouse_erl_packet_buffering_tests`, `clickhouse_erl_connection_packet_boundary_tests`, `clickhouse_erl_profile_events_parsing_tests`
- Dead properties from `prop_clickhouse_erl_connection_streaming`
- Dead test helpers from `clickhouse_erl_connection_tests`

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
- Event-driven streaming parser (`clickhouse_erl_parser` + `src/parsers/`)
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
