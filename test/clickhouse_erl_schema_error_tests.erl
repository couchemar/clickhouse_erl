-module(clickhouse_erl_schema_error_tests).

-include_lib("eunit/include/eunit.hrl").
-include("clickhouse_erl_protocol.hrl").

is_schema_error_test_() ->
    [
        {"NO_SUCH_COLUMN_IN_TABLE (16) is a schema error",
            ?_assert(clickhouse_erl_exception:is_schema_error(#exception_info{error_code = 16}))},
        {"UNKNOWN_IDENTIFIER (47) is a schema error",
            ?_assert(clickhouse_erl_exception:is_schema_error(#exception_info{error_code = 47}))},
        {"EMPTY_LIST_OF_COLUMNS_QUERIED (51) is a schema error",
            ?_assert(clickhouse_erl_exception:is_schema_error(#exception_info{error_code = 51}))},
        {"TYPE_MISMATCH (53) is a schema error",
            ?_assert(clickhouse_erl_exception:is_schema_error(#exception_info{error_code = 53}))},
        {"Logical error (10) is NOT a schema error",
            ?_assertNot(clickhouse_erl_exception:is_schema_error(#exception_info{error_code = 10}))},
        {"Syntax error (62) is NOT a schema error",
            ?_assertNot(clickhouse_erl_exception:is_schema_error(#exception_info{error_code = 62}))}
    ].
