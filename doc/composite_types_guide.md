# ClickHouse Composite Types Guide

## Overview

This guide explains how to use ClickHouse composite types (Tuple, Array, Map, Nullable, LowCardinality) with the `clickhouse_erl` client. Composite types enable you to work with complex data structures like nested records, variable-length lists, key-value pairs, optional values, and dictionary-encoded columns.

## Table of Contents

- [Tuple Type](#tuple-type)
- [Array Type](#array-type)
- [Map Type](#map-type)
- [Nullable Type](#nullable-type)
- [LowCardinality Type](#lowcardinality-type)
- [Type Composition](#type-composition)
- [Migration Guide](#migration-guide)
- [Best Practices](#best-practices)

## Tuple Type

### What is a Tuple?

A Tuple is a fixed-size collection of heterogeneous values. Each element can have a different type. Tuples are useful for grouping related values together, such as coordinates, structured records, or multi-field keys.

### Erlang Representation

ClickHouse Tuples are represented as Erlang tuples:

```erlang
% Tuple(String, Int64, Float64)
{<<"Alice">>, 25, 95.5}

% Tuple(name String, age Int64)  % Named tuple
{<<"Bob">>, 30}

% Empty tuple
{}
```

### Creating Tables with Tuples

```sql
CREATE TABLE users (
    id UInt64,
    profile Tuple(name String, age Int64, score Float64),
    coordinates Tuple(Float64, Float64)
) ENGINE = Memory
```

### Inserting Tuple Data

```erlang
{ok, Conn} = clickhouse_erl:connect(#{host => "localhost", port => 9000}),

% Insert data with tuples
{ok, _} = clickhouse_erl:insert(Conn, <<"users">>, [
    {1, {<<"Alice">>, 25, 95.5}, {37.7749, -122.4194}},
    {2, {<<"Bob">>, 30, 87.2}, {40.7128, -74.0060}},
    {3, {<<"Charlie">>, 35, 92.8}, {51.5074, -0.1278}}
]).
```

### Querying Tuple Data

```erlang
{ok, Results} = clickhouse_erl:query(Conn, <<"SELECT * FROM users">>),

% Results will be a list of tuples:
% [
%   {1, {<<"Alice">>, 25, 95.5}, {37.7749, -122.4194}},
%   {2, {<<"Bob">>, 30, 87.2}, {40.7128, -74.0060}},
%   {3, {<<"Charlie">>, 35, 92.8}, {51.5074, -0.1278}}
% ]
```

### Nested Tuples

Tuples can contain other tuples:

```erlang
% Tuple(Tuple(Int64, Int64), String)
{{100, 200}, <<"description">>}

% Tuple(name String, address Tuple(city String, zip Int32))
{<<"Alice">>, {<<"San Francisco">>, 94102}}
```

### Common Use Cases

- **Coordinates**: `Tuple(Float64, Float64)` for latitude/longitude
- **Structured records**: `Tuple(name String, age Int64, email String)`
- **Multi-field keys**: `Tuple(user_id UInt64, timestamp DateTime)`
- **Nested data**: `Tuple(header Tuple(...), body Tuple(...))`

## Array Type

### What is an Array?

An Array is a variable-length list of homogeneous values. All elements must have the same type. Arrays are useful for storing lists, tags, time series data, and other collections.

### Erlang Representation

ClickHouse Arrays are represented as Erlang lists:

```erlang
% Array(Int64)
[1, 2, 3, 4, 5]

% Array(String)
[<<"tag1">>, <<"tag2">>, <<"tag3">>]

% Empty array
[]
```

### Creating Tables with Arrays

```sql
CREATE TABLE posts (
    id UInt64,
    title String,
    tags Array(String),
    view_counts Array(Int64)
) ENGINE = Memory
```

### Inserting Array Data

```erlang
{ok, _} = clickhouse_erl:insert(Conn, <<"posts">>, [
    {1, <<"First Post">>, [<<"erlang">>, <<"clickhouse">>], [100, 150, 200]},
    {2, <<"Second Post">>, [<<"database">>, <<"performance">>], [50, 75]},
    {3, <<"Third Post">>, [<<"tutorial">>], [300]}
]).
```

### Querying Array Data

```erlang
{ok, Results} = clickhouse_erl:query(Conn, <<"SELECT * FROM posts">>),

% Results will be a list with arrays:
% [
%   {1, <<"First Post">>, [<<"erlang">>, <<"clickhouse">>], [100, 150, 200]},
%   {2, <<"Second Post">>, [<<"database">>, <<"performance">>], [50, 75]},
%   {3, <<"Third Post">>, [<<"tutorial">>], [300]}
% ]
```

### Nested Arrays

Arrays can contain other arrays:

```erlang
% Array(Array(Int64))
[[1, 2, 3], [4, 5], [6]]

% Array(Array(String))
[[<<"a">>, <<"b">>], [<<"c">>], []]
```

### Arrays of Tuples

Arrays can contain tuples:

```erlang
% Array(Tuple(String, Int64))
[{<<"Alice">>, 25}, {<<"Bob">>, 30}, {<<"Charlie">>, 35}]
```

### Common Use Cases

- **Tags**: `Array(String)` for categorization
- **Time series**: `Array(DateTime)` and `Array(Float64)` for measurements
- **Lists**: `Array(Int64)` for IDs, counts, etc.
- **Nested structures**: `Array(Tuple(...))` for complex records

## Map Type

### What is a Map?

A Map is a collection of key-value pairs. Keys must be comparable types (no arrays or maps as keys), and values can be any type including composite types.

### Erlang Representation

ClickHouse Maps are represented as Erlang maps:

```erlang
% Map(String, Int64)
#{<<"key1">> => 100, <<"key2">> => 200}

% Map(String, String)
#{<<"name">> => <<"Alice">>, <<"email">> => <<"alice@example.com">>}

% Empty map
#{}
```

### Creating Tables with Maps

```sql
CREATE TABLE events (
    id UInt64,
    event_name String,
    properties Map(String, String),
    metrics Map(String, Float64)
) ENGINE = Memory
```

### Inserting Map Data

```erlang
{ok, _} = clickhouse_erl:insert(Conn, <<"events">>, [
    {1, <<"page_view">>, 
     #{<<"page">> => <<"home">>, <<"referrer">> => <<"google">>},
     #{<<"duration">> => 5.2, <<"scroll_depth">> => 0.75}},
    {2, <<"click">>,
     #{<<"button">> => <<"signup">>, <<"location">> => <<"header">>},
     #{<<"x">> => 100.0, <<"y">> => 200.0}}
]).
```

### Querying Map Data

```erlang
{ok, Results} = clickhouse_erl:query(Conn, <<"SELECT * FROM events">>),

% Results will be a list with maps:
% [
%   {1, <<"page_view">>, 
%    #{<<"page">> => <<"home">>, <<"referrer">> => <<"google">>},
%    #{<<"duration">> => 5.2, <<"scroll_depth">> => 0.75}},
%   ...
% ]
```

### Maps with Complex Value Types

Maps can have complex value types:

```erlang
% Map(String, Array(Int64))
#{<<"a">> => [1, 2, 3], <<"b">> => [4, 5]}

% Map(String, Tuple(String, Int64))
#{<<"user1">> => {<<"Alice">>, 25}, <<"user2">> => {<<"Bob">>, 30}}
```

### Key Type Restrictions

Valid key types:
- Primitive types: `String`, `Int64`, `UInt32`, etc.
- `Date`, `DateTime`
- `UUID`, `IPv4`, `IPv6`

Invalid key types:
- `Array(...)` - Arrays cannot be keys
- `Map(...)` - Maps cannot be keys

### Common Use Cases

- **Metadata**: `Map(String, String)` for flexible attributes
- **Metrics**: `Map(String, Float64)` for measurements
- **Configuration**: `Map(String, String)` for settings
- **Flexible schemas**: When column structure varies by row

## Nullable Type

### What is Nullable?

Nullable wraps any type to allow NULL values. This is essential for handling optional or missing data.

### Erlang Representation

Nullable values use tagged tuples to distinguish NULL from actual values:

```erlang
% NULL value
{null}

% Non-NULL value
{value, 42}
{value, <<"foo">>}
{value, [1, 2, 3]}
```

**Why tagged tuples?** This allows distinguishing between `{value, 0}` and `{null}`, or `{value, <<>>}` and `{null}`.

### Creating Tables with Nullable

```sql
CREATE TABLE users (
    id UInt64,
    name String,
    email Nullable(String),
    age Nullable(Int64),
    tags Nullable(Array(String))
) ENGINE = Memory
```

### Inserting Nullable Data

```erlang
{ok, _} = clickhouse_erl:insert(Conn, <<"users">>, [
    {1, <<"Alice">>, {value, <<"alice@example.com">>}, {value, 25}, {value, [<<"admin">>]}},
    {2, <<"Bob">>, {null}, {value, 30}, {null}},
    {3, <<"Charlie">>, {value, <<"charlie@example.com">>}, {null}, {value, []}}
]).
```

### Querying Nullable Data

```erlang
{ok, Results} = clickhouse_erl:query(Conn, <<"SELECT * FROM users">>),

% Results will use tagged tuples for nullable values:
% [
%   {1, <<"Alice">>, {value, <<"alice@example.com">>}, {value, 25}, {value, [<<"admin">>]}},
%   {2, <<"Bob">>, {null}, {value, 30}, {null}},
%   {3, <<"Charlie">>, {value, <<"charlie@example.com">>}, {null}, {value, []}}
% ]
```

### Working with Nullable Values

```erlang
% Pattern matching on nullable values
case Email of
    {null} -> 
        io:format("No email provided~n");
    {value, EmailAddr} -> 
        io:format("Email: ~s~n", [EmailAddr])
end.

% Extracting values with default
get_email_or_default({null}) -> <<"no-email@example.com">>;
get_email_or_default({value, Email}) -> Email.
```

### Nullable Composite Types

Nullable can wrap any type:

```erlang
% Nullable(Array(String))
{null}                    % NULL array
{value, [<<"a">>, <<"b">>]}  % Non-NULL array

% Nullable(Tuple(String, Int64))
{null}                    % NULL tuple
{value, {<<"Alice">>, 25}}   % Non-NULL tuple

% Nullable(Map(String, Int64))
{null}                    % NULL map
{value, #{<<"a">> => 1}}     % Non-NULL map
```

### Common Use Cases

- **Optional fields**: Email, phone number, middle name
- **Missing data**: Sensor readings, survey responses
- **Partial records**: When not all fields are always present
- **Default values**: Use NULL to indicate "use default"

## LowCardinality Type

### What is LowCardinality?

LowCardinality uses dictionary encoding to optimize storage and performance for columns with limited unique values. It's most effective for string columns with high repetition.

### Erlang Representation

LowCardinality values are represented transparently (same as the underlying type):

```erlang
% LowCardinality(String) - same as String
<<"category_a">>

% LowCardinality(Int64) - same as Int64
42
```

The dictionary encoding is handled internally during encoding/decoding.

### Creating Tables with LowCardinality

```sql
CREATE TABLE events (
    id UInt64,
    event_type LowCardinality(String),
    category LowCardinality(String),
    user_id UInt64
) ENGINE = Memory
```

### Inserting LowCardinality Data

```erlang
% Insert data - use regular values, encoding is automatic
{ok, _} = clickhouse_erl:insert(Conn, <<"events">>, [
    {1, <<"click">>, <<"button">>, 100},
    {2, <<"click">>, <<"link">>, 101},
    {3, <<"view">>, <<"page">>, 100},
    {4, <<"click">>, <<"button">>, 102},
    {5, <<"view">>, <<"page">>, 101}
]).
```

### Querying LowCardinality Data

```erlang
{ok, Results} = clickhouse_erl:query(Conn, <<"SELECT * FROM events">>),

% Results look the same as regular types:
% [
%   {1, <<"click">>, <<"button">>, 100},
%   {2, <<"click">>, <<"link">>, 101},
%   ...
% ]
```

### When to Use LowCardinality

**Good candidates:**
- Enum-like columns: status, category, type
- Country codes, language codes
- Product categories, tags
- User roles, permissions
- Columns with < 10,000 unique values

**Poor candidates:**
- High-cardinality columns: user IDs, timestamps, UUIDs
- Columns with mostly unique values
- Very short strings (< 5 bytes)

### Performance Benefits

For a column with 1,000,000 rows and 100 unique values:
- **Regular String**: ~1,000,000 string copies
- **LowCardinality(String)**: 100 strings + 1,000,000 indexes (UInt8)

Storage reduction: ~90% for typical use cases.

### Common Use Cases

- **Enumerations**: Status codes, types, categories
- **Geographic data**: Country, state, city names
- **Classification**: Tags, labels, groups
- **Repeated strings**: Error messages, log levels

## Type Composition

### Combining Composite Types

Composite types can be nested to create complex data structures:

```erlang
% Array of nullable strings
% Array(Nullable(String))
[{value, <<"a">>}, {null}, {value, <<"b">>}]

% Nullable array
% Nullable(Array(Int64))
{null}                % NULL array
{value, [1, 2, 3]}    % Non-NULL array

% Array of tuples
% Array(Tuple(String, Int64))
[{<<"Alice">>, 25}, {<<"Bob">>, 30}]

% Map with array values
% Map(String, Array(Int64))
#{<<"a">> => [1, 2, 3], <<"b">> => [4, 5]}

% Tuple with composite elements
% Tuple(Array(String), Map(String, Int64))
{[<<"tag1">>, <<"tag2">>], #{<<"count">> => 100}}

% Array of low cardinality strings
% Array(LowCardinality(String))
[<<"A">>, <<"B">>, <<"A">>, <<"C">>, <<"B">>]
```

### Complex Nested Example

```sql
CREATE TABLE analytics (
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
) ENGINE = Memory
```

```erlang
{ok, _} = clickhouse_erl:insert(Conn, <<"analytics">>, [
    {1,
     {<<"Alice">>, 
      [<<"premium">>, <<"verified">>],
      #{<<"country">> => <<"US">>, <<"language">> => <<"en">>}},
     [
         {<<"page_view">>, {{2024, 1, 15}, {10, 30, 0}}, 
          {value, #{<<"page">> => <<"home">>}}},
         {<<"click">>, {{2024, 1, 15}, {10, 31, 0}}, 
          {null}}
     ]}
]).
```

### Nesting Depth Limit

The implementation supports nesting up to 5 levels deep. For example:

```erlang
% 5 levels: Array -> Nullable -> Tuple -> Array -> String
% Array(Nullable(Tuple(String, Array(String))))
[
    {value, {<<"name">>, [<<"tag1">>, <<"tag2">>]}},
    {null},
    {value, {<<"other">>, []}}
]
```

## Migration Guide

### From Primitive Types to Composite Types

#### Adding Optional Fields (Nullable)

**Before:**
```sql
CREATE TABLE users (
    id UInt64,
    name String,
    email String  -- Required field
) ENGINE = Memory
```

**After:**
```sql
CREATE TABLE users (
    id UInt64,
    name String,
    email Nullable(String)  -- Now optional
) ENGINE = Memory
```

**Code changes:**
```erlang
% Before
{1, <<"Alice">>, <<"alice@example.com">>}

% After
{1, <<"Alice">>, {value, <<"alice@example.com">>}}
{2, <<"Bob">>, {null}}  % Can now represent missing email
```

#### Adding Lists (Array)

**Before:**
```sql
CREATE TABLE posts (
    id UInt64,
    title String,
    tag1 String,
    tag2 String,
    tag3 String  -- Fixed number of tags
) ENGINE = Memory
```

**After:**
```sql
CREATE TABLE posts (
    id UInt64,
    title String,
    tags Array(String)  -- Variable number of tags
) ENGINE = Memory
```

**Code changes:**
```erlang
% Before
{1, <<"Post">>, <<"erlang">>, <<"database">>, <<"">>}

% After
{1, <<"Post">>, [<<"erlang">>, <<"database">>]}  % No empty strings needed
```

#### Adding Structured Data (Tuple)

**Before:**
```sql
CREATE TABLE locations (
    id UInt64,
    name String,
    lat Float64,
    lon Float64
) ENGINE = Memory
```

**After:**
```sql
CREATE TABLE locations (
    id UInt64,
    name String,
    coordinates Tuple(Float64, Float64)  -- Grouped coordinates
) ENGINE = Memory
```

**Code changes:**
```erlang
% Before
{1, <<"San Francisco">>, 37.7749, -122.4194}

% After
{1, <<"San Francisco">>, {37.7749, -122.4194}}  % Coordinates grouped
```

#### Adding Flexible Attributes (Map)

**Before:**
```sql
CREATE TABLE products (
    id UInt64,
    name String,
    attr1_key String,
    attr1_value String,
    attr2_key String,
    attr2_value String  -- Fixed attributes
) ENGINE = Memory
```

**After:**
```sql
CREATE TABLE products (
    id UInt64,
    name String,
    attributes Map(String, String)  -- Flexible attributes
) ENGINE = Memory
```

**Code changes:**
```erlang
% Before
{1, <<"Product">>, <<"color">>, <<"red">>, <<"size">>, <<"large">>}

% After
{1, <<"Product">>, #{<<"color">> => <<"red">>, <<"size">> => <<"large">>}}
```

#### Optimizing String Columns (LowCardinality)

**Before:**
```sql
CREATE TABLE events (
    id UInt64,
    event_type String,  -- Many repeated values
    category String     -- Many repeated values
) ENGINE = Memory
```

**After:**
```sql
CREATE TABLE events (
    id UInt64,
    event_type LowCardinality(String),  -- Optimized
    category LowCardinality(String)     -- Optimized
) ENGINE = Memory
```

**Code changes:**
```erlang
% No code changes needed - values are the same
{1, <<"click">>, <<"button">>}
```

## Best Practices

### Choosing the Right Type

1. **Use Tuple for fixed-size heterogeneous data**
   - Coordinates, structured records, multi-field keys
   - When element count and types are known at schema design time

2. **Use Array for variable-size homogeneous data**
   - Tags, lists, time series
   - When element count varies but type is consistent

3. **Use Map for flexible key-value data**
   - Metadata, properties, configuration
   - When keys are not known at schema design time

4. **Use Nullable for optional fields**
   - Any field that might be missing or unknown
   - Prefer Nullable over sentinel values (empty strings, -1, etc.)

5. **Use LowCardinality for repeated strings**
   - Enum-like columns with < 10,000 unique values
   - Status codes, categories, types

### Performance Tips

1. **Avoid deep nesting** (> 3 levels)
   - Increases encoding/decoding overhead
   - Makes queries more complex

2. **Use LowCardinality for high-repetition columns**
   - Can reduce storage by 80-90%
   - Improves query performance for filtering and grouping

3. **Prefer Tuple over multiple columns**
   - Better data locality
   - Clearer semantic grouping

4. **Use Array instead of multiple columns**
   - More flexible schema
   - Easier to work with variable-length data

5. **Consider Nullable vs default values**
   - Nullable: When NULL has semantic meaning
   - Default values: When missing data should be treated as a specific value

### Error Handling

All composite type operations return `{ok, Result}` or `{error, Reason}`:

```erlang
case clickhouse_erl_types_array:encode_array_column(Data, int64) of
    {ok, Binary} ->
        % Success
        Binary;
    {error, {array_element_error, Index, Reason}} ->
        % Handle encoding error
        io:format("Error encoding element ~p: ~p~n", [Index, Reason])
end.
```

### Type Validation

Use `validate_type_compatibility/2` to check values before encoding:

```erlang
Type = {array, {tuple, [string, int64]}},
Value = [{<<"Alice">>, 25}, {<<"Bob">>, 30}],

case clickhouse_erl_types_composite:validate_type_compatibility(Type, Value) of
    ok ->
        % Value is compatible
        encode_value(Value);
    {error, Reason} ->
        % Value is incompatible
        io:format("Type mismatch: ~p~n", [Reason])
end.
```

### Testing Composite Types

When testing with composite types:

1. **Test empty collections**: `[]`, `{}`, `#{}`
2. **Test single elements**: `[1]`, `{<<"a">>}`, `#{<<"k">> => 1}`
3. **Test nested structures**: `[[1, 2], [3]]`
4. **Test NULL values**: `{null}`, `[{null}, {value, 1}]`
5. **Test type mismatches**: Verify error handling

## Summary

Composite types enable rich data modeling in ClickHouse:

- **Tuple**: Fixed-size heterogeneous collections
- **Array**: Variable-size homogeneous lists
- **Map**: Flexible key-value pairs
- **Nullable**: Optional values with NULL support
- **LowCardinality**: Dictionary-encoded optimization

These types can be combined to create complex nested structures, providing the flexibility needed for real-world applications while maintaining ClickHouse's performance characteristics.

For more details, see the module documentation:
- `clickhouse_erl_types_tuple`
- `clickhouse_erl_types_array`
- `clickhouse_erl_types_map`
- `clickhouse_erl_types_nullable`
- `clickhouse_erl_types_low_cardinality`
- `clickhouse_erl_types_composite`
