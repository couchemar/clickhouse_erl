%%%-------------------------------------------------------------------
%% @doc Property-based tests for clickhouse_erl_connection callback validation
%%
%% This module contains property-based tests that validate the correctness
%% of callback validation in the connection module.
%% @end
%%%-------------------------------------------------------------------

-module(prop_clickhouse_erl_connection).

-include_lib("proper/include/proper.hrl").

%%%===================================================================
%%% Property Tests
%%%===================================================================

%% @doc Property 1: Callback validation correctness
%% **Feature: on-log-callback, Property 1: Callback validation correctness**
%% **Validates: Requirements 1.3, 1.4, 2.1, 2.2, 2.3**
%%
%% For any term T, calling validate_callback(on_log, T) shall return:
%% - ok if T is a function of arity 1
%% - {error, {invalid_callback_arity, 1, ActualArity}} if T is a function of arity /= 1
%% - {error, {invalid_callback_type, T}} if T is not a function
prop_on_log_callback_validation_correctness() ->
    ?FORALL(
        Term,
        callback_term_gen(),
        begin
            Result = clickhouse_erl_connection:validate_callback(on_log, Term),
            case is_function(Term) of
                true ->
                    {arity, Arity} = erlang:fun_info(Term, arity),
                    case Arity of
                        1 ->
                            Result =:= ok;
                        _ ->
                            Result =:= {error, {invalid_callback_arity, 1, Arity}}
                    end;
                false ->
                    Result =:= {error, {invalid_callback_type, Term}}
            end
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generate random terms: functions of various arities and non-function values
-spec callback_term_gen() -> proper_types:type().
callback_term_gen() ->
    oneof([
        fun_with_arity_gen(),
        non_function_gen()
    ]).

%% @doc Generate functions with arities 0-10
-spec fun_with_arity_gen() -> proper_types:type().
fun_with_arity_gen() ->
    oneof([
        return(fun() -> ok end),
        return(fun(_) -> ok end),
        return(fun(_, _) -> ok end),
        return(fun(_, _, _) -> ok end),
        return(fun(_, _, _, _) -> ok end),
        return(fun(_, _, _, _, _) -> ok end),
        return(fun(_, _, _, _, _, _) -> ok end),
        return(fun(_, _, _, _, _, _, _) -> ok end),
        return(fun(_, _, _, _, _, _, _, _) -> ok end),
        return(fun(_, _, _, _, _, _, _, _, _) -> ok end),
        return(fun(_, _, _, _, _, _, _, _, _, _) -> ok end),
        return(fun(_, _, _, _, _, _, _, _, _, _, _) -> ok end)
    ]).

%% @doc Generate non-function values: atoms, integers, binaries, lists, tuples, pids
-spec non_function_gen() -> proper_types:type().
non_function_gen() ->
    oneof([
        atom(),
        integer(),
        binary(),
        list(integer()),
        ?LET({A, B}, {integer(), atom()}, {A, B}),
        return(self()),
        return("a string list"),
        return(undefined),
        return(#{key => value}),
        float()
    ]).

%% @doc Property 2: Log event accumulation and dispatch
%% **Feature: on-log-callback, Property 2: Log event accumulation and dispatch**
%% **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 4.1, 4.2**
%%
%% For any sequence of server_log block events with N rows and 8 columns,
%% processing the complete event sequence through process_events/2 shall invoke
%% the on_log callback exactly N times, and each invocation shall receive a map
%% containing all 8 keys with the correct values from the corresponding row.
prop_on_log_event_accumulation_and_dispatch() ->
    ?FORALL(
        {NumRows, ColumnValues},
        server_log_block_gen(),
        begin
            Self = self(),
            OnLog = fun(Entry) ->
                Self ! {log_entry, Entry},
                ok
            end,
            AccState = clickhouse_erl_connection:init_acc_state(#{on_log => OnLog}),
            Events = build_server_log_events(NumRows, ColumnValues),
            {false, false, false, _} = clickhouse_erl_connection:process_events(Events, AccState),
            %% Collect all entries
            Entries = collect_entries(NumRows),
            %% Verify count
            CountOk = length(Entries) =:= NumRows,
            %% Verify each entry has all 8 keys with correct values
            ColumnsOk = lists:all(
                fun({RowIdx, Entry}) ->
                    lists:all(
                        fun({ColName, Values}) ->
                            ExpectedVal = lists:nth(RowIdx, Values),
                            maps:get(ColName, Entry, missing) =:= ExpectedVal
                        end,
                        ColumnValues
                    ) andalso map_size(Entry) =:= 8
                end,
                lists:zip(lists:seq(1, NumRows), Entries)
            ),
            CountOk andalso ColumnsOk
        end
    ).

%% @doc Property 4: Error-tolerant callback invocation
%% **Feature: on-log-callback, Property 4: Error-tolerant callback invocation**
%% **Validates: Requirements 4.3, 4.4, 4.5**
%%
%% For any log entry map, invoke_optional_callback(Callback, LogEntry) shall
%% return ok regardless of whether the callback returns ok, returns {error, Reason},
%% or throws an exception.
prop_on_log_error_tolerant_callback_invocation() ->
    ?FORALL(
        {Callback, LogEntry},
        {bad_callback_gen(), log_entry_gen()},
        begin
            Result = clickhouse_erl_connection:invoke_optional_callback(Callback, LogEntry),
            Result =:= ok
        end
    ).

%%%===================================================================
%%% Server Log Generators
%%%===================================================================

%% @doc Generate a server_log block specification: {NumRows, [{ColName, [Values]}]}
-spec server_log_block_gen() -> proper_types:type().
server_log_block_gen() ->
    ?LET(
        NumRows,
        range(1, 20),
        ?LET(
            ColumnValues,
            log_column_values_gen(NumRows),
            {NumRows, ColumnValues}
        )
    ).

%% @doc Generate column values for all 8 log columns with NumRows values each
-spec log_column_values_gen(pos_integer()) -> proper_types:type().
log_column_values_gen(NumRows) ->
    ?LET(
        {EventTimes, EventTimeMicros, HostNames, QueryIds, ThreadIds, Priorities, Sources, Texts},
        {
            vector(NumRows, non_neg_integer()),
            vector(NumRows, non_neg_integer()),
            vector(NumRows, non_empty(binary())),
            vector(NumRows, non_empty(binary())),
            vector(NumRows, non_neg_integer()),
            vector(NumRows, integer(-128, 127)),
            vector(NumRows, non_empty(binary())),
            vector(NumRows, non_empty(binary()))
        },
        [
            {<<"event_time">>, EventTimes},
            {<<"event_time_microseconds">>, EventTimeMicros},
            {<<"host_name">>, HostNames},
            {<<"query_id">>, QueryIds},
            {<<"thread_id">>, ThreadIds},
            {<<"priority">>, Priorities},
            {<<"source">>, Sources},
            {<<"text">>, Texts}
        ]
    ).

%% @doc Build the full event sequence for a server_log block
-spec build_server_log_events(pos_integer(), [{binary(), [term()]}]) -> [term()].
build_server_log_events(NumRows, ColumnValues) ->
    ColumnEvents = lists:flatmap(
        fun({ColName, Values}) ->
            [
                {data, column, #{name => ColName, type => <<"String">>}}
                | [{data, column_value, V} || V <- lists:sublist(Values, NumRows)]
            ]
        end,
        ColumnValues
    ),
    [{start, server_log}] ++ ColumnEvents ++ [{'end', server_log}].

%% @doc Collect N log entries from the process mailbox
-spec collect_entries(non_neg_integer()) -> [map()].
collect_entries(N) ->
    collect_entries(N, []).

-spec collect_entries(non_neg_integer(), [map()]) -> [map()].
collect_entries(0, Acc) ->
    lists:reverse(Acc);
collect_entries(N, Acc) ->
    receive
        {log_entry, Entry} ->
            collect_entries(N - 1, [Entry | Acc])
    after 100 ->
        lists:reverse(Acc)
    end.

%% @doc Generate a random log entry map
-spec log_entry_gen() -> proper_types:type().
log_entry_gen() ->
    ?LET(
        {ET, ETM, HN, QI, TI, P, S, T},
        {
            non_neg_integer(),
            non_neg_integer(),
            binary(),
            binary(),
            non_neg_integer(),
            integer(-128, 127),
            binary(),
            binary()
        },
        #{
            <<"event_time">> => ET,
            <<"event_time_microseconds">> => ETM,
            <<"host_name">> => HN,
            <<"query_id">> => QI,
            <<"thread_id">> => TI,
            <<"priority">> => P,
            <<"source">> => S,
            <<"text">> => T
        }
    ).

%% @doc Generate "bad" callbacks that return errors, unexpected values, or crash
-spec bad_callback_gen() -> proper_types:type().
bad_callback_gen() ->
    oneof([
        return(fun(_) -> {error, some_reason} end),
        return(fun(_) -> {error, {complex, reason}} end),
        return(fun(_) -> unexpected_return_value end),
        return(fun(_) -> 42 end),
        return(fun(_) -> error(intentional_crash) end),
        return(fun(_) -> throw(intentional_throw) end),
        return(fun(_) -> exit(intentional_exit) end),
        return(fun(_) -> ok end)
    ]).

%% @doc Property 3: Optional callback forwarding
%% **Feature: on-log-callback, Property 3: Optional callback forwarding**
%% **Validates: Requirements 5.1, 5.2, 5.3**
%%
%% For any options map containing an on_log key with a function value,
%% add_optional_callbacks(PreparedRequest, Options) shall include the on_log
%% key with the same function value in the returned map.
prop_on_log_optional_callback_forwarding() ->
    ?FORALL(
        {OnLogFun, ExtraKeys},
        {arity1_fun_gen(), optional_extra_keys_gen()},
        begin
            Options = maps:merge(ExtraKeys, #{on_log => OnLogFun}),
            PreparedRequest = #{sql => <<"SELECT 1">>},
            Result = clickhouse_erl_app:add_optional_callbacks(PreparedRequest, Options),
            %% on_log must be preserved
            maps:get(on_log, Result) =:= OnLogFun andalso
                %% sql must still be present
                maps:get(sql, Result) =:= <<"SELECT 1">>
        end
    ).

%%%===================================================================
%%% Property 3 Generators
%%%===================================================================

%% @doc Generate random arity-1 functions
-spec arity1_fun_gen() -> proper_types:type().
arity1_fun_gen() ->
    oneof([
        return(fun(_) -> ok end),
        return(fun(_) -> {error, some_reason} end),
        return(fun(_) -> ignored end),
        return(fun(X) -> X end),
        return(fun(_) -> error(crash) end)
    ]).

%% @doc Generate random extra keys that may or may not be in the forwarding list
-spec optional_extra_keys_gen() -> proper_types:type().
optional_extra_keys_gen() ->
    ?LET(
        Flags,
        {boolean(), boolean(), boolean(), boolean(), boolean()},
        begin
            AllKeys = [on_data, initial_accumulator, on_progress, on_profile, on_profile_events],
            FlagList = tuple_to_list(Flags),
            Selected = [K || {K, true} <- lists:zip(AllKeys, FlagList)],
            maps:from_list([{K, fun(_) -> ok end} || K <- Selected])
        end
    ).
