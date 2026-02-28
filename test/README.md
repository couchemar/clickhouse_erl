# ClickHouse Erlang Client - Test Organization

This document explains the test organization strategy for the clickhouse_erl project, including when to use different test types and how to structure property-based tests.

## Test File Types

The project uses three main test file types, each serving a specific purpose:

### 1. Unit Tests (`*_tests.erl`)

**Purpose**: Test specific examples, edge cases, and integration scenarios with EUnit.

**Naming**: `clickhouse_erl_<module>_tests.erl`

**When to use**:
- Testing specific input/output examples
- Testing error conditions with known inputs
- Testing edge cases (empty inputs, boundary values)
- Integration tests requiring ClickHouse connection
- Tests requiring setup/teardown with EUnit fixtures

**Example structure**:
```erlang
-module(clickhouse_erl_compression_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test naming: <function>_<condition>_test()
encode_valid_input_test() ->
    Input = <<"test data">>,
    ?assertMatch({ok, _}, clickhouse_erl_compression:compress(Input, #{method => lz4})).

decode_empty_binary_test() ->
    ?assertEqual({error, invalid_format}, 
                 clickhouse_erl_compression:decompress(<<>>)).

%% Setup/cleanup for stateful tests
connection_lifecycle_test_() ->
    {setup,
     fun() -> 
         {ok, Conn} = test_helpers:connect(),
         Conn
     end,
     fun(Conn) -> clickhouse_erl:disconnect(Conn) end,
     fun(Conn) ->
         [?_assertMatch({ok, _}, clickhouse_erl:query(Conn, <<"SELECT 1">>)),
          ?_assertEqual(ok, clickhouse_erl:disconnect(Conn))]
     end}.
```

**Run with**:
```bash
# All unit tests
rebar3 eunit

# Specific module
rebar3 eunit --module=clickhouse_erl_compression_tests

# Single test
rebar3 eunit --test=clickhouse_erl_compression_tests:encode_valid_input_test
```

### 2. Pure Property Tests (`prop_*.erl`)

**Purpose**: Test universal properties across generated inputs using PropEr, without external dependencies.

**Naming**: `prop_clickhouse_erl_<module>.erl`

**When to use**:
- Testing invariants that should hold for all inputs
- Testing encode/decode round-trips
- Testing pure functions without side effects
- Testing protocol packet encoding/decoding
- Testing type conversions and transformations

**Key characteristics**:
- NO EUnit include (`-include_lib("eunit/include/eunit.hrl")`)
- NO test wrappers or setup/teardown
- NO external dependencies (ClickHouse, files, etc.)
- Discovered automatically by `rebar3 proper`

**Example structure**:
```erlang
-module(prop_clickhouse_erl_compression).
-include_lib("proper/include/proper.hrl").

%% No EUnit include
%% No test wrappers

%% Property naming: prop_<invariant_name>()
prop_encode_decode_roundtrip() ->
    ?FORALL(Data, binary(),
        begin
            {ok, Encoded} = clickhouse_erl_compression:compress(Data, #{method => lz4}),
            {ok, Decompressed, _} = clickhouse_erl_compression:decompress(Encoded),
            Data =:= Decompressed
        end).

prop_compression_preserves_size() ->
    ?FORALL({Data, Method}, {binary(), compression_method()},
        begin
            {ok, Compressed} = clickhouse_erl_compression:compress(Data, #{method => Method}),
            {ok, Decompressed, _} = clickhouse_erl_compression:decompress(Compressed),
            byte_size(Data) =:= byte_size(Decompressed)
        end).

%% Generators
compression_method() ->
    oneof([lz4, zstd, none]).
```

**Run with**:
```bash
# All property tests (default 100 iterations)
rebar3 proper

# Quick property tests (10 iterations)
rebar3 as quick_test proper

# Extensive property tests (1000 iterations)
rebar3 as full_test proper

# Specific module
rebar3 proper --module=prop_clickhouse_erl_compression

# Specific property
rebar3 proper --prop=prop_clickhouse_erl_compression:prop_encode_decode_roundtrip
```

### 3. Integration Property Tests (`*_property_tests.erl`)

**Purpose**: Test properties that require external dependencies (ClickHouse connection, setup/teardown).

**Naming**: `clickhouse_erl_<module>_property_tests.erl`

**When to use**:
- Property tests requiring ClickHouse connection
- Property tests requiring setup/teardown
- Property tests requiring external resources (files, processes)
- Property tests that need EUnit fixtures

**Key characteristics**:
- INCLUDES EUnit (`-include_lib("eunit/include/eunit.hrl")`)
- INCLUDES PropEr (`-include_lib("proper/include/proper.hrl")`)
- Uses EUnit wrappers for setup/teardown
- Runs via `rebar3 eunit` (NOT `rebar3 proper`)

**Example structure**:
```erlang
-module(clickhouse_erl_connection_backward_compatibility_property_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("proper/include/proper.hrl").

-import(test_helpers, [connect/0]).

%% EUnit wrapper with setup/teardown
prop_backward_compatibility_test() ->
    %% Reduced iterations to prevent timeouts (50 instead of 100)
    Result = proper:quickcheck(
        prop_backward_compatibility(),
        [{numtests, 50}, {to_file, user}, {max_size, 20}]
    ),
    ?assert(Result =:= true).

%% Property definition with connection parameter
prop_backward_compatibility() ->
    ?FORALL(QueryText, query_gen(),
        begin
            case connect() of
                {ok, Conn} ->
                    try
                        Result1 = clickhouse_erl:query(Conn, QueryText),
                        Result2 = clickhouse_erl:query(Conn, QueryText, #{parameters => []}),
                        verify_same_return_type(Result1, Result2)
                    after
                        clickhouse_erl:disconnect(Conn)
                    end;
                {error, _} ->
                    true  % Skip if connection fails
            end
        end).

%% Generators
query_gen() ->
    oneof([
        return(<<"SELECT 1">>),
        return(<<"SELECT 2 + 2">>),
        return(<<"SELECT 'hello'">>)
    ]).

%% Helper functions
verify_same_return_type({ok, _}, {ok, _}) -> true;
verify_same_return_type({error, _}, {error, _}) -> true;
verify_same_return_type(_, _) -> false.
```

**Run with**:
```bash
# Integration property tests run with unit tests
rebar3 eunit

# Specific module
rebar3 eunit --module=clickhouse_erl_connection_backward_compatibility_property_tests
```

## Decision Tree: Which Test Type to Use?

```
Does the test require external dependencies?
├─ YES → Does it test properties across generated inputs?
│        ├─ YES → Integration Property Test (*_property_tests.erl)
│        │        - Use EUnit wrapper with setup/teardown
│        │        - Reduce iteration count (50 instead of 100)
│        │        - Run via rebar3 eunit
│        └─ NO  → Unit Test (*_tests.erl)
│                 - Use EUnit fixtures for setup/teardown
│                 - Run via rebar3 eunit
│
└─ NO  → Does it test properties across generated inputs?
         ├─ YES → Pure Property Test (prop_*.erl)
         │        - No EUnit include
         │        - No setup/teardown
         │        - Run via rebar3 proper
         └─ NO  → Unit Test (*_tests.erl)
                  - Test specific examples
                  - Run via rebar3 eunit
```

## Setup and Teardown Requirements

### Pure Property Tests (prop_*.erl)

**NO setup/teardown** - These tests must be completely self-contained:
- No ClickHouse connection
- No file I/O
- No process spawning
- No external dependencies

If your test needs any of these, use an integration property test instead.

### Integration Property Tests (*_property_tests.erl)

**Setup/teardown patterns**:

1. **Connection per test**:
```erlang
prop_my_property() ->
    ?FORALL(Input, input_gen(),
        begin
            case test_helpers:connect() of
                {ok, Conn} ->
                    try
                        % Test logic here
                        Result = clickhouse_erl:query(Conn, Input),
                        verify_result(Result)
                    after
                        clickhouse_erl:disconnect(Conn)
                    end;
                {error, _} ->
                    true  % Skip if connection fails
            end
        end).
```

2. **Shared connection** (use sparingly):
```erlang
prop_my_property_test_() ->
    {setup,
     fun() ->
         application:ensure_all_started(clickhouse_erl),
         {ok, Conn} = test_helpers:connect(),
         Conn
     end,
     fun(Conn) ->
         clickhouse_erl:disconnect(Conn)
     end,
     fun(Conn) ->
         ?_assert(proper:quickcheck(prop_my_property(Conn),
                                    [{numtests, 50}, {to_file, user}]))
     end}.

prop_my_property(Conn) ->
    ?FORALL(Input, input_gen(),
        begin
            Result = clickhouse_erl:query(Conn, Input),
            verify_result(Result)
        end).
```

### Unit Tests (*_tests.erl)

**Setup/teardown with EUnit fixtures**:
```erlang
connection_test_() ->
    {setup,
     fun() ->
         % Setup
         {ok, Conn} = test_helpers:connect(),
         Conn
     end,
     fun(Conn) ->
         % Teardown
         clickhouse_erl:disconnect(Conn)
     end,
     fun(Conn) ->
         % Tests
         [?_assertMatch({ok, _}, clickhouse_erl:query(Conn, <<"SELECT 1">>)),
          ?_assertEqual(ok, clickhouse_erl:disconnect(Conn))]
     end}.
```

## Test Helpers and Generators

### test_helpers.erl

**Purpose**: Centralize common test setup, configuration, and utilities.

**When to add**: Same setup code appears in 3+ test files.

**Example**:
```erlang
-module(test_helpers).
-export([connect/0, disconnect/1, test_config/0]).

connect() ->
    Config = test_config(),
    Host = maps:get(host, Config),
    Port = maps:get(port, Config),
    clickhouse_erl:connect(Host, Port, Config).

test_config() ->
    #{host => "localhost", 
      port => 9000, 
      user => "default",
      database => "default"}.

disconnect(Conn) ->
    clickhouse_erl:disconnect(Conn).
```

**Import pattern**:
```erlang
-import(test_helpers, [connect/0, disconnect/1]).
```

### generators.erl

**Purpose**: Reusable PropEr generators for common data types.

**When to add**: Generator is used in 2+ test files.

**Example**:
```erlang
-module(generators).
-include_lib("proper/include/proper.hrl").

-export([binary_string_gen/0, compression_method_gen/0, query_gen/0]).

binary_string_gen() ->
    ?LET(List, list(range(32, 126)), list_to_binary(List)).

compression_method_gen() ->
    oneof([lz4, zstd, none, disabled]).

query_gen() ->
    oneof([
        return(<<"SELECT 1">>),
        return(<<"SELECT 2 + 2">>),
        ?LET(N, range(1, 100), 
             list_to_binary("SELECT " ++ integer_to_list(N)))
    ]).
```

**Import pattern**:
```erlang
-import(generators, [binary_string_gen/0, compression_method_gen/0]).
```

## Iteration Count Guidelines

### Pure Property Tests (prop_*.erl)

- **Default** (100 iterations): `rebar3 proper`
- **Quick** (10 iterations): `rebar3 as quick_test proper` - for CI on every commit
- **Extensive** (1000 iterations): `rebar3 as full_test proper` - for CI on main branch

### Integration Property Tests (*_property_tests.erl)

**Reduce iteration counts** to prevent timeouts:
- **Recommended**: 50 iterations (instead of 100)
- **Reason**: Each iteration requires real ClickHouse connection
- **Configuration**: Pass `{numtests, 50}` to `proper:quickcheck/2`

Example:
```erlang
prop_my_test() ->
    Result = proper:quickcheck(
        prop_my_property(),
        [{numtests, 50}, {to_file, user}, {max_size, 20}]
    ),
    ?assert(Result =:= true).
```

## Test Execution Time Expectations

- **Unit tests**: < 30 seconds total
- **Quick property tests**: < 1 minute total
- **Default property tests**: < 5 minutes total
- **Extensive property tests**: < 10 minutes total
- **Full test suite** (unit + property): < 15 minutes total

If tests exceed these times, consider:
1. Reducing iteration counts for integration property tests
2. Optimizing slow generators
3. Adding timeout settings to EUnit fixtures
4. Splitting large test modules

## Common Patterns and Best Practices

### 1. Skip Tests When Dependencies Unavailable

```erlang
prop_my_property() ->
    ?FORALL(Input, input_gen(),
        begin
            case clickhouse_erl_compression:is_available(lz4) of
                true ->
                    % Test logic
                    test_compression(Input);
                false ->
                    true  % Skip if LZ4 not available
            end
        end).
```

### 2. Handle Connection Failures Gracefully

```erlang
prop_my_property() ->
    ?FORALL(Input, input_gen(),
        begin
            case test_helpers:connect() of
                {ok, Conn} ->
                    try
                        % Test logic
                        test_query(Conn, Input)
                    after
                        clickhouse_erl:disconnect(Conn)
                    end;
                {error, _Reason} ->
                    true  % Skip if connection fails
            end
        end).
```

### 3. Use Appropriate Generator Sizes

```erlang
%% Small data for quick tests
small_binary_gen() ->
    ?LET(Size, range(0, 100), binary(Size)).

%% Large data for thorough tests
large_binary_gen() ->
    ?LET(Size, range(1000, 10000), binary(Size)).

%% Varied sizes for comprehensive coverage
varied_binary_gen() ->
    oneof([
        <<>>,                                    % Empty
        ?LET(Size, range(1, 15), binary(Size)),  % Small
        ?LET(Size, range(16, 128), binary(Size)), % Medium
        ?LET(Size, range(129, 1024), binary(Size)) % Large
    ]).
```

### 4. Document Property Requirements

```erlang
%% Property 1: Compression Round-Trip Consistency
%% Validates: Requirements 3.1, 3.2, 3.3, 3.4
prop_compression_roundtrip_consistency() ->
    ?FORALL({Data, Method}, {binary_data_gen(), compression_method_gen()},
        begin
            {ok, Compressed} = compress(Data, Method),
            {ok, Decompressed, _} = decompress(Compressed),
            Data =:= Decompressed
        end).
```

## Migration from EUnit-Wrapped to Pure PropEr

When migrating property tests from `*_property_tests.erl` to `prop_*.erl`:

1. **Check for external dependencies**:
   - ClickHouse connection? → Keep as `*_property_tests.erl`
   - File I/O? → Keep as `*_property_tests.erl`
   - Pure functions only? → Migrate to `prop_*.erl`

2. **Migration steps**:
   ```bash
   # 1. Create new pure property test file
   cp clickhouse_erl_compression_property_tests.erl prop_clickhouse_erl_compression.erl
   
   # 2. Remove EUnit include and wrappers
   # 3. Keep all prop_* functions unchanged
   # 4. Test with rebar3 proper
   rebar3 proper --module=prop_clickhouse_erl_compression
   
   # 5. Verify all properties pass
   # 6. Delete old file
   rm clickhouse_erl_compression_property_tests.erl
   ```

3. **What to remove**:
   - `-include_lib("eunit/include/eunit.hrl")`
   - `prop_*_test()` wrapper functions
   - `proper:quickcheck/2` calls
   - Setup/teardown logic

4. **What to keep**:
   - `-include_lib("proper/include/proper.hrl")`
   - All `prop_*()` property definitions
   - All generators
   - All helper functions

## ClickHouse Test Environment

**Assumption**: ClickHouse is already running (user's responsibility).

**DO NOT**:
- Add polling/waiting logic for ClickHouse readiness
- Start/stop ClickHouse in tests
- Manage Docker containers in test code

**DO**:
- Use `test_helpers:connect/0` for connections
- Handle connection failures gracefully (skip test)
- Clean up connections in teardown

**ClickHouse Limitations**:
- Maximum sleep time: 3 seconds (3000000 microseconds)
- Queries using `SELECT sleep(N)` where N > 3 will fail with error code 160 (TOO_SLOW)

## Summary

| Test Type | File Pattern | Includes | Setup/Teardown | Run Command | Use Case |
|-----------|-------------|----------|----------------|-------------|----------|
| Unit Tests | `*_tests.erl` | EUnit | Yes (EUnit fixtures) | `rebar3 eunit` | Specific examples, edge cases, integration |
| Pure Property Tests | `prop_*.erl` | PropEr only | No | `rebar3 proper` | Universal properties, pure functions |
| Integration Property Tests | `*_property_tests.erl` | EUnit + PropEr | Yes (EUnit fixtures) | `rebar3 eunit` | Properties requiring external dependencies |

**Key principle**: Separate pure property tests from integration property tests to enable fast, isolated testing of pure functions while maintaining thorough integration testing for stateful operations.
