# Server Logs Guide

ClickHouse can send server-side log entries during query execution. The `on_log` callback lets you receive these entries in real time.

## Enabling Server Logs

Server logs are controlled by the `send_logs_level` query setting. Set it to the desired log level:

```erlang
Options = #{
    settings => [{<<"send_logs_level">>, <<"trace">>}],
    on_log => fun(Entry) ->
        io:format("~s: ~s~n", [
            maps:get(<<"source">>, Entry),
            maps:get(<<"text">>, Entry)
        ]),
        ok
    end
},
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>, Options).
```

Log levels (from most to least verbose): `trace`, `debug`, `information`, `warning`, `error`, `fatal`.

## Log Entry Format

Each log entry is a map with binary keys:

```erlang
#{
    <<"event_time">> => 1700000000,           %% Unix timestamp
    <<"event_time_microseconds">> => 123456,  %% Microseconds component
    <<"host_name">> => <<"server1">>,         %% Server hostname
    <<"query_id">> => <<"abc-123">>,          %% Query ID
    <<"thread_id">> => 42,                    %% Thread ID
    <<"priority">> => 6,                      %% Log priority (1=Fatal..8=Trace)
    <<"source">> => <<"executeQuery">>,       %% Source module
    <<"text">> => <<"Read 100 rows">>         %% Log message
}
```

## Default Behavior

When no `on_log` callback is provided, server log entries are logged via Erlang's `?LOG_DEBUG` with structured metadata:

```erlang
%% No on_log — entries logged at DEBUG level automatically
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>, #{
    settings => [{<<"send_logs_level">>, <<"trace">>}]
}).
```

To see these in your application, configure the Erlang logger to show debug messages.

## Error Handling

The `on_log` callback is error-tolerant. If it returns `{error, Reason}` or crashes, a warning is logged and query execution continues normally:

```erlang
%% This won't break the query
OnLog = fun(_Entry) -> error(oops) end,
{ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>, #{
    settings => [{<<"send_logs_level">>, <<"trace">>}],
    on_log => OnLog
}).
```

## Callback Validation

The callback must be a function of arity 1. Invalid callbacks are rejected before the query is sent:

```erlang
%% This returns an error immediately
{error, {invalid_callback_arity, 1, 2}} =
    clickhouse_erl:query(Conn, <<"SELECT 1">>, #{
        on_log => fun(_, _) -> ok end
    }).
```

## Works with INSERT Too

The `on_log` callback works with both `query/3` and `insert/4`:

```erlang
{ok, _} = clickhouse_erl:insert(Conn, SQL, Input, #{
    settings => [{<<"send_logs_level">>, <<"information">>}],
    on_log => fun(Entry) ->
        io:format("INSERT log: ~s~n", [maps:get(<<"text">>, Entry)]),
        ok
    end
}).
```
