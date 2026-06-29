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

%%%===================================================================
%%% Feature: block-end-event, Property 3: Row count tracking round-trip
%%%===================================================================

%% Feature: block-end-event, Property 3: Row count tracking round-trip
%% @doc Property 3: Row count tracking round-trip
%% **Validates: Requirements 2.1, 2.2, 2.3**
%%
%% For any non-negative integer N, processing {start, server_data} followed by
%% {data, num_rows, N} followed by {'end', server_data} results in:
%% (a) current_block_rows being N before the end event, and
%% (b) current_block_rows being 0 after the end event.
prop_block_end_row_count_tracking_round_trip() ->
    ?FORALL(
        N,
        non_neg_integer(),
        begin
            OnData = fun(_Event, Acc) -> {ok, Acc} end,
            AccState = clickhouse_erl_connection:init_acc_state(#{
                on_data => OnData,
                accumulator => undefined
            }),

            %% Process {start, server_data} and {data, num_rows, N}
            EventsBefore = [{start, server_data}, {data, num_rows, N}],
            {false, false, false, AccAfterNumRows} =
                clickhouse_erl_connection:process_events(EventsBefore, AccState),

            %% (a) current_block_rows is N before the end event
            RowsBeforeEnd = maps:get(current_block_rows, AccAfterNumRows, undefined),

            %% Process {'end', server_data}
            EventsEnd = [{'end', server_data}],
            {false, false, false, AccAfterEnd} =
                clickhouse_erl_connection:process_events(EventsEnd, AccAfterNumRows),

            %% (b) current_block_rows is 0 after the end event
            RowsAfterEnd = maps:get(current_block_rows, AccAfterEnd, undefined),

            RowsBeforeEnd =:= N andalso RowsAfterEnd =:= 0
        end
    ).

%%%===================================================================
%%% Feature: block-end-event, Property 1: Block_end dispatch biconditional
%%%===================================================================

%% Feature: block-end-event, Property 1: Block_end dispatch biconditional
%% @doc Property 1: Block_end dispatch biconditional
%% **Validates: Requirements 1.1, 1.2, 4.1, 4.2**
%%
%% For any data-carrying block type (server_data, server_totals, server_extremes)
%% and for any non-negative integer row count, processing {start, Type} ->
%% {data, num_rows, NumRows} -> {'end', Type} dispatches block_end to the
%% callback if and only if NumRows > 0.
prop_block_end_dispatch_biconditional() ->
    ?FORALL(
        {BlockType, NumRows},
        {oneof([server_data, server_totals, server_extremes]), non_neg_integer()},
        begin
            Self = self(),
            OnData = fun
                (block_end, Acc) ->
                    Self ! got_block_end,
                    {ok, Acc};
                (_Event, Acc) ->
                    {ok, Acc}
            end,
            AccState = clickhouse_erl_connection:init_acc_state(#{
                on_data => OnData,
                accumulator => undefined
            }),

            Events = [{start, BlockType}, {data, num_rows, NumRows}, {'end', BlockType}],
            {false, false, false, _} =
                clickhouse_erl_connection:process_events(Events, AccState),

            GotBlockEnd =
                receive
                    got_block_end -> true
                after 0 ->
                    false
                end,

            %% block_end dispatched iff NumRows > 0
            GotBlockEnd =:= (NumRows > 0)
        end
    ).

%%%===================================================================
%%% Feature: block-end-event, Property 2: Excluded block types never dispatch block_end
%%%===================================================================

%% Feature: block-end-event, Property 2: Excluded block types never dispatch block_end
%% @doc Property 2: Excluded block types never dispatch block_end
%% **Validates: Requirements 4.3**
%%
%% For any block type that is NOT data-carrying (server_log, server_profile_events),
%% processing {'end', Type} SHALL NOT dispatch block_end to the callback,
%% regardless of any row count stored in AccState.
prop_block_end_excluded_block_types_never_dispatch() ->
    ?FORALL(
        {BlockType, NumRows},
        {oneof([server_log, server_profile_events]), pos_integer()},
        begin
            Self = self(),
            OnData = fun
                (block_end, Acc) ->
                    Self ! got_block_end,
                    {ok, Acc};
                (_Event, Acc) ->
                    {ok, Acc}
            end,
            AccState = clickhouse_erl_connection:init_acc_state(#{
                on_data => OnData,
                accumulator => undefined
            }),

            %% Manually set up AccState as if we were in an excluded block type
            %% We process through the normal event flow
            Events = [{start, BlockType}, {data, num_rows, NumRows}, {'end', BlockType}],
            clickhouse_erl_connection:process_events(Events, AccState),

            %% Verify callback was NOT called with block_end
            GotBlockEnd =
                receive
                    got_block_end -> true
                after 0 ->
                    false
                end,

            GotBlockEnd =:= false
        end
    ).

%%%===================================================================
%%% Feature: block-end-event, Property 4: Default callback idempotence on block_end
%%%===================================================================

%% Feature: block-end-event, Property 4: Default callback idempotence on block_end
%% @doc Property 4: Default callback idempotence on block_end
%% **Validates: Requirements 3.1**
%%
%% For any valid default callback accumulator (map with column_order,
%% column_meta, column_values keys), calling default_on_data_callback(block_end, Acc)
%% returns {ok, Acc} with the accumulator unchanged.
prop_block_end_default_callback_idempotence() ->
    ?FORALL(
        Acc,
        default_callback_acc_gen(),
        begin
            Result = clickhouse_erl_connection:default_on_data_callback(block_end, Acc),
            Result =:= {ok, Acc}
        end
    ).

%%%===================================================================
%%% Feature: block-end-event, Property 5: Block_end count equals non-empty block count
%%%===================================================================

%% Feature: block-end-event, Property 5: Block_end count equals non-empty block count
%% @doc Property 5: Block_end count equals non-empty block count
%% **Validates: Requirements 5.3**
%%
%% For any sequence of parser events representing a query response with K blocks
%% (mix of empty and non-empty), processing all events results in exactly as many
%% block_end dispatches as there are non-empty blocks.
prop_block_end_count_equals_nonempty_block_count() ->
    ?FORALL(
        Blocks,
        non_empty(list(block_spec_gen())),
        begin
            Self = self(),
            OnData = fun
                (block_end, Acc) ->
                    Self ! got_block_end,
                    {ok, Acc};
                (_Event, Acc) ->
                    {ok, Acc}
            end,
            AccState = clickhouse_erl_connection:init_acc_state(#{
                on_data => OnData,
                accumulator => undefined
            }),

            %% Build full event sequence from block specs
            Events = lists:flatmap(fun block_spec_to_events/1, Blocks),
            clickhouse_erl_connection:process_events(Events, AccState),

            %% Count block_end messages received
            BlockEndCount = count_messages(got_block_end),

            %% Count expected non-empty blocks
            ExpectedCount = length([B || {_Type, NumRows} = B <- Blocks, NumRows > 0]),

            BlockEndCount =:= ExpectedCount
        end
    ).

%%%===================================================================
%%% Block-end Generators
%%%===================================================================

%% @doc Generate a block spec: {BlockType, NumRows} where BlockType is data-carrying
-spec block_spec_gen() -> proper_types:type().
block_spec_gen() ->
    {oneof([server_data, server_totals, server_extremes]), non_neg_integer()}.

%% @doc Convert a block spec to a list of parser events
-spec block_spec_to_events({atom(), non_neg_integer()}) -> [term()].
block_spec_to_events({Type, NumRows}) ->
    [{start, Type}, {data, num_rows, NumRows}, {'end', Type}].

%% @doc Count messages of a given type in the mailbox
-spec count_messages(term()) -> non_neg_integer().
count_messages(Msg) ->
    count_messages(Msg, 0).

-spec count_messages(term(), non_neg_integer()) -> non_neg_integer().
count_messages(Msg, Count) ->
    receive
        Msg -> count_messages(Msg, Count + 1)
    after 0 ->
        Count
    end.

%% @doc Generate random default callback accumulator maps
-spec default_callback_acc_gen() -> proper_types:type().
default_callback_acc_gen() ->
    ?LET(
        {ColNames, ColTypes, ColValues},
        {list(non_empty(binary())), list(non_empty(binary())), list(list(binary()))},
        begin
            Names = lists:usort(ColNames),
            MetaMap = maps:from_list([
                {N, #{name => N, type => T}}
             || {N, T} <- lists:zip(Names, pad_list(ColTypes, length(Names)))
            ]),
            ValuesMap = maps:from_list([
                {N, V}
             || {N, V} <- lists:zip(Names, pad_list(ColValues, length(Names)))
            ]),
            #{
                column_order => Names,
                column_meta => MetaMap,
                column_values => ValuesMap
            }
        end
    ).

%% @doc Pad a list to at least Length elements by cycling
-spec pad_list(list(), non_neg_integer()) -> list().
pad_list([], 0) ->
    [];
pad_list([], N) ->
    lists:duplicate(N, <<>>);
pad_list(List, N) when length(List) >= N -> lists:sublist(List, N);
pad_list(List, N) ->
    Repeated = lists:flatten(lists:duplicate((N div length(List)) + 1, List)),
    lists:sublist(Repeated, N).
