# Extended Types Guide

ClickHouse Erlang client provides comprehensive support for extended ClickHouse types beyond basic integers, floats, and strings.

## Overview

**Supported Extended Type Categories**:
- **Extended Integers**: Int128, Int256, UInt128, UInt256
- **Decimals**: Decimal32/64/128/256 for fixed-precision arithmetic
- **Enums**: Enum8/16 for categorical data
- **Network Types**: IPv4, IPv6
- **UUID**: Universally unique identifiers
- **Time Types**: Time, Time64 for time-of-day values
- **Special Types**: Nothing, Point, Interval, JSON

All extended types integrate seamlessly with composite types (Array, Tuple, Nullable, Map, LowCardinality).

## Extended Integers

Extended integers support high-precision numeric calculations beyond 64-bit limits.

**Type Representations**:
- Values are represented as plain Erlang integers
- Erlang handles arbitrary precision natively

**Example Usage**:
```erlang
% CREATE TABLE
clickhouse_erl:query(Conn, <<"
    CREATE TABLE high_precision (
        id UInt64,
        large_int Int128,
        huge_uint UInt256
    ) ENGINE = Memory
">>).

% INSERT
{ok, _} = clickhouse_erl:insert(Conn, 
    <<"INSERT INTO high_precision VALUES">>,
    [
        #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2, 3]},
        #{name => <<"large_int">>, type => <<"Int128">>, 
          data => [170141183460469231731687303715884105727,  % Max Int128
                   -170141183460469231731687303715884105728, % Min Int128
                   0]},
        #{name => <<"huge_uint">>, type => <<"UInt256">>, 
          data => [115792089237316195423570985008687907853269984665640564039457584007913129639935, % Max
                   0,
                   12345678901234567890123456789012345678901234567890]}
    ]
).

% SELECT returns plain Erlang integers
{ok, [[1, 170141183460469231731687303715884105727, _], _, _]} = 
    clickhouse_erl:query(Conn, <<"SELECT * FROM high_precision">>).
```

## Decimal Types

Decimal types provide fixed-precision arithmetic for financial and scientific data.

**Type Representation**: `{decimal, Value :: integer(), Scale :: non_neg_integer()}`
- Value: Scaled integer (e.g., 12345 for 123.45 with scale 2)
- Scale: Number of decimal places

**Precision Limits**:
- Decimal32: Up to 9 digits
- Decimal64: Up to 18 digits
- Decimal128: Up to 38 digits
- Decimal256: Up to 76 digits

**Example Usage**:
```erlang
% CREATE TABLE
clickhouse_erl:query(Conn, <<"
    CREATE TABLE financial_data (
        id UInt32,
        price Decimal64(18, 4),
        quantity Decimal32(9, 2)
    ) ENGINE = Memory
">>).

% INSERT
{ok, _} = clickhouse_erl:insert(Conn, 
    <<"INSERT INTO financial_data VALUES">>,
    [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{name => <<"price">>, type => <<"Decimal64(18, 4)">>, 
          data => [{decimal, 999950, 4},      % 99.9950
                   {decimal, 1234567890, 4}]}, % 123456.7890
        #{name => <<"quantity">>, type => <<"Decimal32(9, 2)">>, 
          data => [{decimal, 10050, 2},       % 100.50
                   {decimal, 25000, 2}]}       % 250.00
    ]
).

% Convert decimal to float for display
format_decimal({decimal, Value, Scale}) ->
    Value / math:pow(10, Scale).
```

## Enum Types

Enum types represent categorical data with named values.

**Type Representation**:
- Input: Atom, binary string, or integer
- Output: Atom (default)

**Example Usage**:
```erlang
% CREATE TABLE
clickhouse_erl:query(Conn, <<"
    CREATE TABLE user_status (
        id UInt32,
        status Enum8('active' = 1, 'inactive' = 0, 'suspended' = -1)
    ) ENGINE = Memory
">>).

% INSERT (atoms, binaries, or integers)
{ok, _} = clickhouse_erl:insert(Conn, 
    <<"INSERT INTO user_status VALUES">>,
    [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"status">>, 
          type => <<"Enum8('active' = 1, 'inactive' = 0, 'suspended' = -1)">>, 
          data => [active, <<"inactive">>, 1]}  % Mixed formats accepted
    ]
).

% SELECT returns atoms by default
{ok, [[1, active], [2, inactive], [3, active]]} = 
    clickhouse_erl:query(Conn, <<"SELECT * FROM user_status">>).
```

## Network Types

Network types provide efficient storage for IP addresses.

**Type Representations**:
- IPv4: `{A, B, C, D}` tuple, `<<"A.B.C.D">>` binary, or integer
- IPv6: `{A, B, C, D, E, F, G, H}` tuple or `<<"A:B:C:D:E:F:G:H">>` binary

**Example Usage**:
```erlang
% CREATE TABLE
clickhouse_erl:query(Conn, <<"
    CREATE TABLE network_logs (
        id UInt32,
        client_ip IPv4,
        server_ip IPv6
    ) ENGINE = Memory
">>).

% INSERT (multiple formats)
{ok, _} = clickhouse_erl:insert(Conn, 
    <<"INSERT INTO network_logs VALUES">>,
    [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"client_ip">>, type => <<"IPv4">>, 
          data => [{192, 168, 1, 1},           % Tuple format
                   <<"10.0.0.1">>,             % String format
                   3232235777]},               % Integer format
        #{name => <<"server_ip">>, type => <<"IPv6">>, 
          data => [{8193, 3512, 0, 0, 0, 0, 0, 1},  % Tuple format
                   <<"2001:db8::1">>,                % String format
                   <<"fe80::1">>]}
    ]
).

% SELECT returns tuples
{ok, [[1, {192, 168, 1, 1}, {8193, 3512, 0, 0, 0, 0, 0, 1}], _, _]} = 
    clickhouse_erl:query(Conn, <<"SELECT * FROM network_logs">>).
```

## UUID Type

UUID type stores universally unique identifiers in RFC 4122 format.

**Type Representation**:
- Input: Binary string with or without hyphens, or 16-byte binary
- Output: Binary string in canonical hyphenated format

**Example Usage**:
```erlang
% CREATE TABLE
clickhouse_erl:query(Conn, <<"
    CREATE TABLE sessions (
        session_id UUID,
        user_id UInt32
    ) ENGINE = Memory
">>).

% INSERT (multiple formats)
{ok, _} = clickhouse_erl:insert(Conn, 
    <<"INSERT INTO sessions VALUES">>,
    [
        #{name => <<"session_id">>, type => <<"UUID">>, 
          data => [<<"550e8400-e29b-41d4-a716-446655440000">>,  % With hyphens
                   <<"550e8400e29b41d4a716446655440001">>,      % Without hyphens
                   <<85,14,132,0,226,155,65,212,167,22,68,102,85,68,0,2>>]}, % Binary
        #{name => <<"user_id">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ]
).

% SELECT returns canonical hyphenated format
{ok, [[<<"550e8400-e29b-41d4-a716-446655440000">>, 1], _, _]} = 
    clickhouse_erl:query(Conn, <<"SELECT * FROM sessions">>).
```

## Time Types

Time types represent time-of-day values without date components.

**Type Representations**:
- Time: `{Hour, Minute, Second}` tuple or integer (seconds since midnight)
- Time64: `{Hour, Minute, Second, Nanosecond}` tuple or integer (nanoseconds)

**Example Usage**:
```erlang
% CREATE TABLE
clickhouse_erl:query(Conn, <<"
    CREATE TABLE schedules (
        id UInt32,
        start_time Time,
        precise_time Time64
    ) ENGINE = Memory
">>).

% INSERT
{ok, _} = clickhouse_erl:insert(Conn, 
    <<"INSERT INTO schedules VALUES">>,
    [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
        #{name => <<"start_time">>, type => <<"Time">>, 
          data => [{14, 30, 45},    % Tuple format
                   52245]},          % Integer format
        #{name => <<"precise_time">>, type => <<"Time64">>, 
          data => [{14, 30, 45, 123456789},  % Tuple with nanoseconds
                   52245123456789]}          % Integer nanoseconds
    ]
).
```

## Special Types

### Nothing Type

Nothing type represents NULL-only columns, primarily used with `Nullable(Nothing)`.

**Type Representation**: `null` or `undefined` atom

### Point Type

Point type represents 2D geometric points.

**Type Representation**: `{X :: float(), Y :: float()}` tuple

**Example**:
```erlang
#{name => <<"coordinates">>, type => <<"Point">>, 
  data => [{1.5, 2.5}, {-10.0, 20.0}]}
```

### Interval Type

Interval type represents time intervals with various scales.

**Type Representation**: `{interval, Scale :: atom(), Value :: integer()}` tuple

**Supported Scales**: `second`, `minute`, `hour`, `day`, `week`, `month`, `quarter`, `year`

### JSON Type

JSON type stores structured JSON data as strings.

**Type Representation**:
- Input: Binary string (raw JSON), map, or list (auto-encoded to JSON)
- Output: Binary string (raw JSON text)

**IMPORTANT**: Requires `output_format_native_write_json_as_string=1` setting.

**Example**:
```erlang
% Set via connection settings (recommended)
{ok, Conn} = clickhouse_erl:connect("localhost", 9000, #{
    settings => [{<<"output_format_native_write_json_as_string">>, <<"1">>}]
}).

% CREATE TABLE
clickhouse_erl:query(Conn, <<"
    CREATE TABLE events (
        id UInt32,
        metadata JSON
    ) ENGINE = Memory
">>).

% INSERT (multiple formats)
{ok, _} = clickhouse_erl:insert(Conn, 
    <<"INSERT INTO events VALUES">>,
    [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"metadata">>, type => <<"JSON">>, 
          data => [<<"{\"key\":\"value\"}">>,              % Raw JSON string
                   #{key => <<"value">>, count => 42},     % Map (auto-encoded)
                   [{key, <<"value">>}, {count, 42}]]}     % List (auto-encoded)
    ]
).
```

## Composite Types with Extended Types

Extended types work seamlessly with composite types:

```erlang
% Array of Decimals
#{name => <<"prices">>, type => <<"Array(Decimal64(18, 4))">>, 
  data => [[[{decimal, 999950, 4}, {decimal, 1000000, 4}]]]}

% Nullable UUID
#{name => <<"external_id">>, type => <<"Nullable(UUID)">>, 
  data => [<<"550e8400-e29b-41d4-a716-446655440000">>, null]}

% Map with Enum values
#{name => <<"settings">>, type => <<"Map(String, Enum8('on' = 1, 'off' = 0))">>, 
  data => [[#{<<"notifications">> => on, <<"dark_mode">> => off}]]}
```

## Error Handling

All extended type operations return `{ok, Result}` or `{error, Reason}` tuples:

```erlang
% Range validation errors
{error, {value_out_of_range, #{value := Val, min := Min, max := Max, type := Type}}}

% Format validation errors
{error, {invalid_format, #{value := Val, expected_format := Format, type := Type}}}

% Type-specific validation errors
{error, {invalid_enum_value, Value}}
{error, {invalid_ipv4_octet, Octet}}
{error, {invalid_uuid_format, Value}}
{error, {invalid_time_range, Value}}
{error, {invalid_json_syntax, Value}}
{error, {precision_exceeded, #{value := Val, max_precision := Max}}}
```

For more details on specific types, see the module documentation in `src/types/`.
