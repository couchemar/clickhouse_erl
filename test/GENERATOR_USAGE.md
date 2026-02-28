# PropEr Generator Usage Guide

## Overview

This document explains how to use shared PropEr generators in property-based tests for the clickhouse_erl project. Following these patterns ensures consistency, reduces code duplication, and makes tests easier to maintain.

## Shared Generators Location

All shared generators are defined in `test/generators.erl`. This module exports commonly used generators that can be imported by any property test file.

## When to Use Shared Generators

**Use shared generators when:**
- The generator is used in 2+ test files
- The generator represents a common data type (strings, integers, dates, etc.)
- The generator follows a standard pattern that other tests might need

**Define local generators when:**
- The generator is specific to one test module
- The generator represents test-specific error conditions
- The generator is tightly coupled to the module being tested

## Available Shared Generators

### Character and String Generators

```erlang
-import(generators, [
    char_gen/0,                      % Valid UTF-8 characters
    string_gen/0,                    % UTF-8 strings (character lists)
    non_empty_string_gen/0,          % Non-empty UTF-8 strings
    binary_string_gen/0,             % UTF-8 strings as binaries
    non_empty_binary_string_gen/0    % Non-empty UTF-8 strings as binaries
]).
```

**Usage example:**
```erlang
prop_string_encoding() ->
    ?FORALL(Str, binary_string_gen(),
        begin
            Encoded = encode_string(Str),
            {ok, Decoded, <<>>} = decode_string(Encoded),
            Str =:= Decoded
        end).
```

### Integer Generators

```erlang
-import(generators, [
    int8_gen/0,      % -128 to 127
    int16_gen/0,     % -32768 to 32767
    int32_gen/0,     % -2147483648 to 2147483647
    int64_gen/0,     % Full Int64 range
    uint16_gen/0,    % 0 to 65535
    uint32_gen/0,    % 0 to 4294967295
    uint64_gen/0,    % 0 to 18446744073709551615
    varint_gen/0     % 0 to 2^63-1 (valid varint range)
]).
```

**Usage example:**
```erlang
prop_int32_roundtrip() ->
    ?FORALL(N, int32_gen(),
        begin
            Encoded = encode_int32(N),
            {ok, Decoded, <<>>} = decode_int32(Encoded),
            N =:= Decoded
        end).
```

### Float Generators

```erlang
-import(generators, [
    float32_gen/0,        % Float32 including special values (infinity, nan)
    float64_gen/0,        % Float64 including special values
    normal_float64_gen/0  % Float64 excluding infinity and nan
]).
```

**Usage example:**
```erlang
prop_float64_encoding() ->
    ?FORALL(F, float64_gen(),
        begin
            Encoded = encode_float64(F),
            {ok, Decoded, <<>>} = decode_float64(Encoded),
            case F of
                nan -> Decoded =:= nan;
                _ -> F =:= Decoded
            end
        end).
```

### Temporal Generators

```erlang
-import(generators, [
    date_gen/0,      % Valid Date values (1970-01-01 to 2149-06-06)
    datetime_gen/0   % Valid DateTime values (1970-01-01 to 2106-02-07)
]).
```

**Usage example:**
```erlang
prop_date_roundtrip() ->
    ?FORALL(Date, date_gen(),
        begin
            Encoded = encode_date(Date),
            {ok, Decoded, <<>>} = decode_date(Encoded),
            Date =:= Decoded
        end).
```

### Composite Generators

```erlang
-import(generators, [
    map_gen/2  % map_gen(KeyGen, ValueGen) - generates maps
]).
```

**Usage example:**
```erlang
prop_map_encoding() ->
    ?FORALL(Map, map_gen(binary_string_gen(), int32_gen()),
        begin
            Encoded = encode_map(Map),
            {ok, Decoded, <<>>} = decode_map(Encoded),
            Map =:= Decoded
        end).
```

## Import Pattern

### Standard Import

Add the import declaration after the `-include_lib` directives:

```erlang
-module(prop_clickhouse_erl_types_example).

-include_lib("proper/include/proper.hrl").

-import(generators, [
    int8_gen/0,
    uint32_gen/0,
    binary_string_gen/0
]).
```

### Selective Import

Only import the generators you actually use:

```erlang
% ✅ GOOD - Import only what you need
-import(generators, [
    int32_gen/0,
    binary_string_gen/0
]).

% ❌ BAD - Don't import everything
-import(generators, [
    char_gen/0, string_gen/0, non_empty_string_gen/0,
    binary_string_gen/0, non_empty_binary_string_gen/0,
    int8_gen/0, int16_gen/0, int32_gen/0, int64_gen/0,
    % ... (too many imports)
]).
```

## Generator Composition

Shared generators can be composed to create more complex generators:

```erlang
% Generate list of integers
int_list_gen() ->
    list(int32_gen()).

% Generate tuple of string and integer
string_int_tuple_gen() ->
    {binary_string_gen(), int32_gen()}.

% Generate nullable values
nullable_gen(ValueGen) ->
    oneof([{null}, ValueGen]).
```

## Test-Specific Generators

Some generators should remain in test files because they're specific to error conditions or test scenarios:

### Invalid Value Generators

```erlang
% In prop_clickhouse_erl_types_primitive.erl
invalid_uint16_gen() -> 
    oneof([range(-1000, -1), range(65536, 1000000)]).

invalid_int8_gen() -> 
    oneof([range(-1000, -129), range(128, 1000)]).
```

### Truncated Data Generators

```erlang
% In prop_clickhouse_erl_types_primitive.erl
truncated_uint32_gen() -> 
    oneof([<<>>, binary(1), binary(2), binary(3)]).

truncated_float64_gen() ->
    oneof([<<>>, binary(1), binary(2), binary(3), 
           binary(4), binary(5), binary(6), binary(7)]).
```

### Protocol-Specific Generators

```erlang
% In prop_clickhouse_erl_compression.erl
compression_method_gen() ->
    oneof([lz4, zstd, none, disabled]).

binary_data_gen() ->
    oneof([
        <<>>,
        ?LET(Size, range(1, 15), binary(Size)),
        ?LET(Size, range(16, 128), binary(Size)),
        ?LET(Size, range(129, 1024), binary(Size))
    ]).
```

## Migration Checklist

When migrating property tests to use shared generators:

- [ ] Check `test/generators.erl` for existing generators
- [ ] Import only the generators you need
- [ ] Keep test-specific generators in the test file
- [ ] Verify tests still pass after migration
- [ ] Remove duplicate generator definitions

## Examples from Migrated Tests

### Example 1: Type Primitive Tests

```erlang
-module(prop_clickhouse_erl_types_primitive).
-include_lib("proper/include/proper.hrl").

-import(generators, [
    char_gen/0,
    float32_gen/0,
    float64_gen/0,
    int16_gen/0,
    int8_gen/0,
    string_gen/0,
    uint16_gen/0,
    uint32_gen/0,
    varint_gen/0
]).

% Uses shared generators for valid values
prop_uint16_round_trip() ->
    ?FORALL(N, uint16_gen(),
        begin
            Encoded = encode_uint16(N),
            {ok, Decoded, <<>>} = decode_uint16(Encoded),
            Decoded =:= N
        end).

% Defines local generator for invalid values
invalid_uint16_gen() -> 
    oneof([range(-1000, -1), range(65536, 1000000)]).

prop_uint16_boundary_validation() ->
    ?FORALL(N, invalid_uint16_gen(),
        begin
            Result = encode_uint16(N),
            case Result of
                {error, {value_out_of_range, _}} -> true;
                _ -> false
            end
        end).
```

### Example 2: Temporal Tests

```erlang
-module(prop_clickhouse_erl_types_temporal).
-include_lib("proper/include/proper.hrl").

-import(generators, [date_gen/0, datetime_gen/0]).

% Uses shared generators for valid dates
prop_date_round_trip() ->
    ?FORALL(Date, date_gen(),
        begin
            Encoded = encode_date(Date),
            {ok, Decoded, <<>>} = decode_date(Encoded),
            Decoded =:= Date
        end).

% Defines local generator for invalid dates
invalid_date_gen() ->
    oneof([
        ?LET(Days, range(-10000, -1), 
             calendar:gregorian_days_to_date(Days + 719528)),
        ?LET(Days, range(65536, 100000), 
             calendar:gregorian_days_to_date(Days + 719528))
    ]).
```

### Example 3: Array Tests

```erlang
-module(prop_clickhouse_erl_types_array).
-include_lib("proper/include/proper.hrl").

-import(generators, [
    int8_gen/0,
    uint16_gen/0,
    uint32_gen/0,
    float64_gen/0,
    binary_string_gen/0,
    normal_float64_gen/0
]).

% Composes shared generators for array tests
prop_array_int8_roundtrip() ->
    ?FORALL(Arrays, list(list(int8_gen())),
        begin
            {ok, Encoded} = encode_array_column(Arrays, int8),
            {ok, Decoded, <<>>} = decode_array_column(
                Encoded, int8, length(Arrays)
            ),
            Arrays =:= Decoded
        end).
```

## Best Practices

1. **Import at module level**: Always use `-import(generators, [...])` rather than calling `generators:gen_name()` throughout the code

2. **Document generator purpose**: Add comments for complex local generators explaining what they generate and why

3. **Reuse before creating**: Check `test/generators.erl` before creating a new generator

4. **Keep generators simple**: Complex generators should be broken down into smaller, composable generators

5. **Test generator output**: Verify generators produce expected values by running them interactively:
   ```erlang
   % In rebar3 shell
   proper_gen:sample(generators:int32_gen()).
   proper_gen:sample(generators:binary_string_gen()).
   ```

6. **Version compatibility**: Ensure generators work with both EUnit-wrapped and pure PropEr tests

## Troubleshooting

### Generator not found

```erlang
% Error: function generators:some_gen/0 undefined
```

**Solution**: Check that the generator is exported in `test/generators.erl` and imported in your test file.

### Import conflicts

```erlang
% Error: function int32_gen/0 already imported
```

**Solution**: Remove duplicate imports or local definitions with the same name.

### Generator produces unexpected values

**Solution**: Test the generator interactively:
```erlang
rebar3 shell
proper_gen:sample(generators:your_gen()).
```

## Summary

- Use shared generators from `test/generators.erl` for common data types
- Import only what you need
- Keep test-specific generators in test files
- Document complex generators
- Compose generators for complex data structures
- Verify generators produce expected values
