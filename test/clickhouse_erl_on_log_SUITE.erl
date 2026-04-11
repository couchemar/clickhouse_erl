-module(clickhouse_erl_on_log_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).
-export([
    on_log_callback_receives_entries/1,
    query_without_on_log_works/1,
    on_log_callback_error_does_not_break_query/1
]).

-define(CONNECT_TIMEOUT, 5000).

suite() ->
    [{timetrap, {seconds, 120}}].

all() ->
    [{group, on_log_tests}].

groups() ->
    [
        {on_log_tests, [sequence], [
            on_log_callback_receives_entries,
            query_without_on_log_works,
            on_log_callback_error_does_not_break_query
        ]}
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

init_per_group(on_log_tests, Config) ->
    Options = #{
        username => test_helpers:test_username(),
        password => test_helpers:test_password(),
        timeout => ?CONNECT_TIMEOUT
    },
    {ok, Conn} = clickhouse_erl:connect(
        test_helpers:clickhouse_host(),
        test_helpers:clickhouse_port(),
        Options
    ),
    [{connection, Conn} | Config];
init_per_group(_Group, Config) ->
    Config.

end_per_group(on_log_tests, Config) ->
    Conn = ?config(connection, Config),
    clickhouse_erl:disconnect(Conn),
    ok;
end_per_group(_Group, _Config) ->
    ok.

%%%===================================================================
%%% Test Cases
%%%===================================================================

%% @doc Execute a query with send_logs_level=trace to trigger SERVER_LOG
%% packets. Verify the on_log callback receives at least one structured log
%% entry with all 8 expected fields.
on_log_callback_receives_entries(Config) ->
    Conn = ?config(connection, Config),
    Self = self(),
    OnLog = fun(Entry) ->
        Self ! {log_entry, Entry},
        ok
    end,
    QueryOpts = #{
        settings => [{<<"send_logs_level">>, <<"trace">>}],
        on_log => OnLog
    },
    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>, QueryOpts),
    %% Verify query returned a valid result
    ?assertMatch(#{data := _}, Result),

    %% Collect all log entries from the mailbox
    Entries = collect_log_entries(5000),
    ?assert(length(Entries) >= 1),

    %% Verify the first entry has all 8 expected fields (binary keys from parser)
    [First | _] = Entries,
    ExpectedKeys = [
        <<"event_time">>,
        <<"event_time_microseconds">>,
        <<"host_name">>,
        <<"query_id">>,
        <<"thread_id">>,
        <<"priority">>,
        <<"source">>,
        <<"text">>
    ],
    lists:foreach(
        fun(Key) ->
            ?assert(maps:is_key(Key, First))
        end,
        ExpectedKeys
    ).

%% @doc Execute a query without on_log callback, verify it completes
%% successfully and returns expected result. Confirms backward compatibility.
query_without_on_log_works(Config) ->
    Conn = ?config(connection, Config),
    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 1">>),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    ?assertEqual([[1]], Rows).

%% @doc Provide a callback that returns {error, intentional}, verify query
%% still completes successfully with correct results.
on_log_callback_error_does_not_break_query(Config) ->
    Conn = ?config(connection, Config),
    OnLog = fun(_Entry) -> {error, intentional} end,
    QueryOpts = #{
        settings => [{<<"send_logs_level">>, <<"trace">>}],
        on_log => OnLog
    },
    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT 42 AS answer">>, QueryOpts),
    Data = maps:get(data, Result),
    Rows = maps:get(rows, Data),
    ?assertEqual([[42]], Rows).

%%%===================================================================
%%% Internal Helpers
%%%===================================================================

%% @doc Collect all {log_entry, Entry} messages from the mailbox.
collect_log_entries(Timeout) ->
    collect_log_entries(Timeout, []).

collect_log_entries(Timeout, Acc) ->
    receive
        {log_entry, Entry} ->
            collect_log_entries(0, [Entry | Acc])
    after Timeout ->
        lists:reverse(Acc)
    end.
