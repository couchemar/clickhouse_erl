%% @doc Configuration helper module for ClickHouse client
%%
%% This module provides functions to read configuration values from the
%% application environment, with fallback to default values.
-module(clickhouse_erl_config).

%% Public API
-export([
    get_max_exception_nesting_depth/0,
    get_max_stack_trace_size/0,
    get_max_exception_message_size/0,
    get_max_exception_name_size/0,
    get_max_total_exception_size/0,
    get_max_nested_exception_count/0,
    get_parsing_limits/0
]).

%% @doc Get maximum exception nesting depth
-spec get_max_exception_nesting_depth() -> non_neg_integer().
get_max_exception_nesting_depth() ->
    application:get_env(clickhouse_erl, max_exception_nesting_depth, 10).

%% @doc Get maximum stack trace size in bytes
-spec get_max_stack_trace_size() -> non_neg_integer().
get_max_stack_trace_size() ->
    application:get_env(clickhouse_erl, max_stack_trace_size, 65536).

%% @doc Get maximum exception message size in bytes
-spec get_max_exception_message_size() -> non_neg_integer().
get_max_exception_message_size() ->
    application:get_env(clickhouse_erl, max_exception_message_size, 8192).

%% @doc Get maximum exception name size in bytes
-spec get_max_exception_name_size() -> non_neg_integer().
get_max_exception_name_size() ->
    application:get_env(clickhouse_erl, max_exception_name_size, 8192).

%% @doc Get maximum total exception size in bytes
-spec get_max_total_exception_size() -> non_neg_integer().
get_max_total_exception_size() ->
    application:get_env(clickhouse_erl, max_total_exception_size, 1048576).

%% @doc Get maximum nested exception count
-spec get_max_nested_exception_count() -> non_neg_integer().
get_max_nested_exception_count() ->
    application:get_env(clickhouse_erl, max_nested_exception_count, 50).

%% @doc Get all parsing limits as a map for convenience
-spec get_parsing_limits() -> #{atom() => non_neg_integer()}.
get_parsing_limits() ->
    #{
        max_exception_nesting_depth => get_max_exception_nesting_depth(),
        max_stack_trace_size => get_max_stack_trace_size(),
        max_exception_message_size => get_max_exception_message_size(),
        max_exception_name_size => get_max_exception_name_size(),
        max_total_exception_size => get_max_total_exception_size(),
        max_nested_exception_count => get_max_nested_exception_count()
    }.
