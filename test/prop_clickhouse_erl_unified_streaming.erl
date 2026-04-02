%% @doc Property-based tests for unified streaming processing.
%% Tests correctness properties of the unified callback-based streaming path.
%%
%% Feature: unified-streaming-processing
%%
%% Run via: rebar3 proper --module=prop_clickhouse_erl_unified_streaming
-module(prop_clickhouse_erl_unified_streaming).
-include_lib("proper/include/proper.hrl").

%% Export properties
-export([
    prop_acc_state_always_has_callback_and_accumulator/0,
    prop_default_callback_accumulates_values/0,
    prop_default_callback_end_transformation/0,
    prop_batch_backward_compatibility/0,
    prop_column_metadata_propagation/0,
    prop_callback_error_propagation/0,
    prop_optional_callbacks_always_present/0,
    prop_validation_rejects_invalid_arities/0
]).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generate a valid arity-2 user on_data callback.
user_on_data_callback() ->
    exactly(fun(_, Acc) -> {ok, Acc} end).

%% @doc Generate an arbitrary user accumulator value.
user_accumulator() ->
    oneof([
        exactly(undefined),
        exactly(0),
        exactly([]),
        exactly(#{}),
        binary()
    ]).

%% @doc Generate an ActiveQueryState map without an on_data key (batch mode).
active_query_state_no_on_data() ->
    ?LET(
        Acc,
        user_accumulator(),
        #{
            caller => {self(), make_ref()},
            query_id => <<"test-query">>,
            timeout => 5000,
            timer_ref => undefined,
            cancelled => false,
            replied => false,
            accumulator => Acc
        }
    ).

%% @doc Generate an ActiveQueryState map with an on_data callback (streaming mode).
active_query_state_with_on_data() ->
    ?LET(
        {Callback, Acc},
        {user_on_data_callback(), user_accumulator()},
        #{
            caller => {self(), make_ref()},
            query_id => <<"test-query">>,
            timeout => 5000,
            timer_ref => undefined,
            cancelled => false,
            replied => false,
            on_data => Callback,
            accumulator => Acc
        }
    ).

%% @doc Generate either variant of ActiveQueryState (with or without on_data).
active_query_state() ->
    oneof([
        active_query_state_no_on_data(),
        active_query_state_with_on_data()
    ]).

%% @doc Generate a non-empty binary column name.
column_name() ->
    ?LET(Name, non_empty(binary()), Name).

%% @doc Generate a column value (various Erlang terms that ClickHouse might return).
column_value() ->
    oneof([
        integer(),
        float(),
        binary(),
        boolean(),
        exactly(null)
    ]).

%% @doc Generate a non-empty list of {ColumnName, Value} data events.
%% Produces events for 1-5 distinct columns, each with 1-5 values.
column_data_events() ->
    ?LET(
        NumCols,
        range(1, 5),
        ?LET(
            Cols,
            vector(NumCols, {column_name(), non_empty(list(column_value()))}),
            begin
                %% Deduplicate by column name (keep first occurrence)
                Unique = dedup_columns(Cols),
                %% Flatten to a list of {ColName, Value} pairs in column-major order
                lists:flatmap(
                    fun({Name, Values}) ->
                        [{Name, V} || V <- Values]
                    end,
                    Unique
                )
            end
        )
    ).

%% @doc Generate a ClickHouse type name.
column_type() ->
    oneof([
        <<"UInt8">>,
        <<"UInt16">>,
        <<"UInt32">>,
        <<"UInt64">>,
        <<"Int8">>,
        <<"Int16">>,
        <<"Int32">>,
        <<"Int64">>,
        <<"Float32">>,
        <<"Float64">>,
        <<"String">>,
        <<"Bool">>
    ]).

%% @doc Generate a column set: list of {Name, Type, Values} with equal-length value lists.
%% All columns have the same number of rows (1-10). Column names are unique.
equal_length_column_set() ->
    ?LET(
        {NumCols, NumRows},
        {range(1, 5), range(1, 10)},
        ?LET(
            Cols,
            vector(NumCols, {column_name(), column_type(), vector(NumRows, column_value())}),
            dedup_columns_3(Cols)
        )
    ).

%% @doc Remove duplicate column names from {Name, Type, Values} triples.
dedup_columns_3(Cols) ->
    dedup_columns_3(Cols, #{}, []).

dedup_columns_3([], _Seen, Acc) ->
    lists:reverse(Acc);
dedup_columns_3([{Name, _, _} = Col | Rest], Seen, Acc) ->
    case maps:is_key(Name, Seen) of
        true -> dedup_columns_3(Rest, Seen, Acc);
        false -> dedup_columns_3(Rest, Seen#{Name => true}, [Col | Acc])
    end.

%% @doc Remove duplicate column names, keeping first occurrence.
dedup_columns(Cols) ->
    dedup_columns(Cols, #{}, []).

dedup_columns([], _Seen, Acc) ->
    lists:reverse(Acc);
dedup_columns([{Name, _} = Col | Rest], Seen, Acc) ->
    case maps:is_key(Name, Seen) of
        true -> dedup_columns(Rest, Seen, Acc);
        false -> dedup_columns(Rest, Seen#{Name => true}, [Col | Acc])
    end.

%%%===================================================================
%%% Properties
%%%===================================================================

%% @doc Property 1: AccState always has callback and accumulator
%%
%% For any ActiveQueryState map (with or without an on_data key), calling
%% init_acc_state/1 should produce an AccState where on_data_callback is a
%% function and user_acc is present.
%%
%% Feature: unified-streaming-processing, Property 1: AccState always has callback and accumulator
%% Validates: Requirements 1.2, 1.3, 4.5, 7.1
prop_acc_state_always_has_callback_and_accumulator() ->
    ?FORALL(
        ActiveQueryState,
        active_query_state(),
        begin
            AccState = clickhouse_erl_connection:init_acc_state(ActiveQueryState),
            %% on_data_callback must always be a function
            HasCallback = is_function(maps:get(on_data_callback, AccState)),
            %% user_acc must always be present (key must exist, value may be any term)
            HasUserAcc = maps:is_key(user_acc, AccState),
            HasCallback andalso HasUserAcc
        end
    ).

%% @doc Property 2: Default callback accumulates values under column name
%%
%% For any sequence of {data, #{name, value}} events with random column names
%% and values, calling the Default Callback for each event should produce an
%% accumulator where every value appears in the column_values map under its
%% corresponding column name.
%%
%% Feature: unified-streaming-processing, Property 2: Default callback accumulates values under column name
%% Validates: Requirements 2.1
prop_default_callback_accumulates_values() ->
    ?FORALL(
        DataEvents,
        column_data_events(),
        begin
            InitAcc = #{
                column_order => [],
                column_meta => #{},
                column_values => #{}
            },
            %% Feed all data events through the default callback
            FinalAcc = lists:foldl(
                fun({ColName, Value}, Acc) ->
                    {ok, NewAcc} = clickhouse_erl_connection:default_on_data_callback(
                        {data, #{name => ColName, type => <<"String">>, value => Value}},
                        Acc
                    ),
                    NewAcc
                end,
                InitAcc,
                DataEvents
            ),
            %% Build expected column_values: group values by column name, preserving order
            Expected = build_expected_column_values(DataEvents),
            %% Verify: every value appears under its column name (in reverse, since
            %% the callback prepends for efficiency — reversed only on 'end')
            #{column_values := ActualValues} = FinalAcc,
            maps:fold(
                fun(ColName, ExpectedVals, AllOk) ->
                    ActualVals = maps:get(ColName, ActualValues, []),
                    %% Values are stored in reverse order (prepended)
                    AllOk andalso (lists:reverse(ActualVals) =:= ExpectedVals)
                end,
                true,
                Expected
            )
        end
    ).

%% @doc Property 3: Default callback end transformation produces valid batch format
%%
%% For any set of columns (each with a name, type, and list of values where all
%% columns have equal length), accumulating column_meta and data events through
%% the Default Callback and then calling it with 'end' should produce
%% #{columns => ColumnsMeta, rows => Rows} where ColumnsMeta has the correct
%% name/type for each column and Rows is the correct row-oriented transposition.
%%
%% Feature: unified-streaming-processing, Property 3: Default callback end transformation produces valid batch format
%% Validates: Requirements 2.2
prop_default_callback_end_transformation() ->
    ?FORALL(
        ColumnSet,
        equal_length_column_set(),
        begin
            InitAcc = #{
                column_order => [],
                column_meta => #{},
                column_values => #{}
            },
            %% Feed column_meta events, then data events per column (column-major order)
            AccAfterEvents = lists:foldl(
                fun({ColName, ColType, Values}, Acc0) ->
                    %% column_meta event
                    {ok, Acc1} = clickhouse_erl_connection:default_on_data_callback(
                        {column_meta, #{name => ColName, type => ColType}}, Acc0
                    ),
                    %% data events for this column
                    lists:foldl(
                        fun(Value, AccInner) ->
                            {ok, NewAcc} = clickhouse_erl_connection:default_on_data_callback(
                                {data, #{name => ColName, type => ColType, value => Value}},
                                AccInner
                            ),
                            NewAcc
                        end,
                        Acc1,
                        Values
                    )
                end,
                InitAcc,
                ColumnSet
            ),
            %% Call 'end' to trigger transformation
            {ok, Result} = clickhouse_erl_connection:default_on_data_callback(
                'end', AccAfterEvents
            ),
            %% Verify structure
            #{columns := ResultColumns, rows := ResultRows} = Result,
            %% Expected columns metadata in order
            ExpectedColumns = [#{name => N, type => T} || {N, T, _} <- ColumnSet],
            %% Expected rows: transpose column-major to row-major
            ExpectedRows = transpose_expected(ColumnSet),
            (ResultColumns =:= ExpectedColumns) andalso (ResultRows =:= ExpectedRows)
        end
    ).

%%%===================================================================
%%% Property helpers
%%%===================================================================

%% @doc Transpose column set to row-oriented format.
%% Input: [{Name, Type, [v1, v2, ...]}, ...] (all value lists same length)
%% Output: [[col1_v1, col2_v1, ...], [col1_v2, col2_v2, ...], ...]
transpose_expected([]) ->
    [];
transpose_expected(ColumnSet) ->
    ValueLists = [Vs || {_, _, Vs} <- ColumnSet],
    NumRows = length(hd(ValueLists)),
    [
        [lists:nth(RowIdx, ColVals) || ColVals <- ValueLists]
     || RowIdx <- lists:seq(1, NumRows)
    ].

%% @doc Build expected column_values map from a list of {ColName, Value} pairs.
%% Values are grouped by column name in insertion order.
build_expected_column_values(Events) ->
    lists:foldl(
        fun({ColName, Value}, Acc) ->
            Existing = maps:get(ColName, Acc, []),
            Acc#{ColName => Existing ++ [Value]}
        end,
        #{},
        Events
    ).

%% @doc Property 5: Column metadata propagation to AccState
%%
%% For any column metadata map #{name := Name, type := Type}, processing a
%% {data, column, ColumnMeta} event through process_events/2 should store
%% the column name and type in AccState fields current_column_name and
%% current_column_type.
%%
%% Feature: unified-streaming-processing, Property 5: Column metadata propagation to AccState
%% Validates: Requirements 5.1
prop_column_metadata_propagation() ->
    ?FORALL(
        {ColName, ColType},
        {column_name(), column_type()},
        begin
            %% Build a minimal AccState via init_acc_state (batch mode, no on_data)
            ActiveQueryState = #{
                caller => {self(), make_ref()},
                query_id => <<"test-query">>,
                timeout => 5000,
                timer_ref => undefined,
                cancelled => false,
                replied => false
            },
            AccState0 = clickhouse_erl_connection:init_acc_state(ActiveQueryState),
            %% Set current_block_type to server_data so the column event is processed
            AccState1 = AccState0#{current_block_type => server_data},
            ColumnMeta = #{name => ColName, type => ColType},
            %% Process the column event
            {false, false, false, ResultAcc} =
                clickhouse_erl_connection:process_events(
                    [{data, column, ColumnMeta}], AccState1
                ),
            %% Assert current_column_name and current_column_type are set
            (maps:get(current_column_name, ResultAcc) =:= ColName) andalso
                (maps:get(current_column_type, ResultAcc) =:= ColType)
        end
    ).

%% @doc Property 6: Callback error propagation consistency
%%
%% For any callback function and any error reason, if the callback returns
%% {error, Reason}, then process_events returns {callback_error, Reason}.
%% If the callback crashes with an exception, process_events returns
%% {callback_error, {callback_crashed, {error, _, _}}}.
%%
%% Feature: unified-streaming-processing, Property 6: Callback error propagation consistency
%% Validates: Requirements 6.1, 6.3
prop_callback_error_propagation() ->
    ?FORALL(
        {ErrorReason, CrashOrReturn},
        {error_reason(), oneof([return_error, crash])},
        begin
            %% Build a callback that either returns {error, Reason} or crashes
            Callback =
                case CrashOrReturn of
                    return_error ->
                        fun(_, _) -> {error, ErrorReason} end;
                    crash ->
                        fun(_, _) -> error(ErrorReason) end
                end,
            %% Build an AccState with the error-producing callback
            ActiveQueryState = #{
                caller => {self(), make_ref()},
                query_id => <<"test-query">>,
                timeout => 5000,
                timer_ref => undefined,
                cancelled => false,
                replied => false,
                on_data => Callback,
                accumulator => undefined
            },
            AccState0 = clickhouse_erl_connection:init_acc_state(ActiveQueryState),
            %% Set up for server_data block with a column name
            AccState1 = AccState0#{
                current_block_type => server_data,
                current_column_name => <<"test_col">>,
                current_column_type => <<"String">>
            },
            %% Send a column_value event — this triggers invoke_streaming_callback
            Result = clickhouse_erl_connection:process_events(
                [{data, column_value, <<"test_value">>}], AccState1
            ),
            case CrashOrReturn of
                return_error ->
                    Result =:= {callback_error, ErrorReason};
                crash ->
                    case Result of
                        {callback_error, {callback_crashed, {error, Err, Stack}}} ->
                            (Err =:= ErrorReason) andalso is_list(Stack);
                        _ ->
                            false
                    end
            end
        end
    ).

%%%===================================================================
%%% Error propagation generators
%%%===================================================================

%% @doc Generate an arbitrary error reason term.
error_reason() ->
    oneof([
        exactly(badarg),
        exactly(timeout),
        exactly(noproc),
        binary(),
        {exactly(validation_failed), binary()},
        {exactly(custom_error), integer()}
    ]).

%%%===================================================================
%%% Property 4: Batch backward compatibility (model-based)
%%%===================================================================

%% Feature: unified-streaming-processing, Property 4: Batch result backward compatibility
%% Validates: Requirements 3.1, 5.2
%%
%% Compares the default callback result against a reference model of the old
%% batch transpose logic. The reference model builds the same #{columns, rows}
%% structure that the old finalize_current_column + transpose_columns_to_rows
%% code path produced.
prop_batch_backward_compatibility() ->
    ?FORALL(
        ColumnSet,
        equal_length_column_set(),
        begin
            %% --- Path 1: Default callback ---
            InitAcc = #{
                column_order => [],
                column_meta => #{},
                column_values => #{}
            },
            AccAfterEvents = lists:foldl(
                fun({ColName, ColType, Values}, Acc0) ->
                    {ok, Acc1} = clickhouse_erl_connection:default_on_data_callback(
                        {column_meta, #{name => ColName, type => ColType}}, Acc0
                    ),
                    lists:foldl(
                        fun(Value, AccInner) ->
                            {ok, NewAcc} = clickhouse_erl_connection:default_on_data_callback(
                                {data, #{name => ColName, type => ColType, value => Value}},
                                AccInner
                            ),
                            NewAcc
                        end,
                        Acc1,
                        Values
                    )
                end,
                InitAcc,
                ColumnSet
            ),
            {ok, CallbackResult} = clickhouse_erl_connection:default_on_data_callback(
                'end', AccAfterEvents
            ),

            %% --- Path 2: Reference model (old batch logic) ---
            ReferenceResult = reference_batch_result(ColumnSet),

            CallbackResult =:= ReferenceResult
        end
    ).

%% @doc Reference implementation of the old batch transpose logic.
%% Given [{Name, Type, Values}, ...], produces #{columns => [...], rows => [...]}.
%% This replicates what finalize_current_column + transpose_columns_to_rows did.
reference_batch_result([]) ->
    #{columns => [], rows => []};
reference_batch_result(ColumnSet) ->
    Columns = [#{name => N, type => T} || {N, T, _} <- ColumnSet],
    ValueLists = [Vs || {_, _, Vs} <- ColumnSet],
    Rows = reference_transpose(ValueLists),
    #{columns => Columns, rows => Rows}.

%% @doc Transpose column-major to row-major.
%% [[1,2,3], [a,b,c]] -> [[1,a], [2,b], [3,c]]
reference_transpose([]) ->
    [];
reference_transpose([[] | _]) ->
    [];
reference_transpose(Cols) ->
    Row = [hd(C) || C <- Cols],
    Rest = [tl(C) || C <- Cols],
    [Row | reference_transpose(Rest)].

%%%===================================================================
%%% Property 7: Optional callbacks always present with correct override
%%%===================================================================

%% Feature: unified-streaming-processing, Property 7
%% Validates: Requirements 8.1, 8.5
prop_optional_callbacks_always_present() ->
    ?FORALL(
        {HasProgress, HasProfile, HasProfileEvents},
        {boolean(), boolean(), boolean()},
        begin
            %% Build a PreparedRequest with/without optional callbacks
            UserProgress = fun(Info) -> {got_progress, Info} end,
            UserProfile = fun(Info) -> {got_profile, Info} end,
            UserProfileEvents = fun(Info) -> {got_profile_events, Info} end,
            Base = #{sql => <<"SELECT 1">>, timeout => 5000},
            PR0 =
                case HasProgress of
                    true -> Base#{on_progress => UserProgress};
                    false -> Base
                end,
            PR1 =
                case HasProfile of
                    true -> PR0#{on_profile => UserProfile};
                    false -> PR0
                end,
            PR =
                case HasProfileEvents of
                    true -> PR1#{on_profile_events => UserProfileEvents};
                    false -> PR1
                end,
            %% Build ActiveQueryState
            AQS = clickhouse_erl_connection:build_active_query_state(
                {self(), make_ref()},
                <<"test-id">>,
                5000,
                undefined,
                #{column_order => [], column_meta => #{}, column_values => #{}},
                PR,
                undefined
            ),
            %% All three must be functions
            is_function(maps:get(on_progress, AQS)) andalso
                is_function(maps:get(on_profile, AQS)) andalso
                is_function(maps:get(on_profile_events, AQS)) andalso
                %% User-provided callbacks override defaults
                (not HasProgress orelse maps:get(on_progress, AQS) =:= UserProgress) andalso
                (not HasProfile orelse maps:get(on_profile, AQS) =:= UserProfile) andalso
                (not HasProfileEvents orelse maps:get(on_profile_events, AQS) =:= UserProfileEvents)
        end
    ).

%%%===================================================================
%%% Property 8: Callback validation rejects invalid arities
%%%===================================================================

%% Feature: unified-streaming-processing, Property 8
%% Validates: Requirements 8.6
prop_validation_rejects_invalid_arities() ->
    ?FORALL(
        {CallbackType, WrongArity},
        {oneof([on_data, on_progress, on_profile, on_profile_events]), range(0, 5)},
        begin
            ExpectedArity =
                case CallbackType of
                    on_data -> 2;
                    _ -> 1
                end,
            %% Build a function with the given arity
            Callback = make_fun_with_arity(WrongArity),
            Result = clickhouse_erl_connection:validate_callback(CallbackType, Callback),
            case WrongArity =:= ExpectedArity of
                true ->
                    Result =:= ok;
                false ->
                    Result =:= {error, {invalid_callback_arity, ExpectedArity, WrongArity}}
            end
        end
    ).

%% @doc Create a function with the specified arity (0-5).
make_fun_with_arity(0) -> fun() -> ok end;
make_fun_with_arity(1) -> fun(_) -> ok end;
make_fun_with_arity(2) -> fun(_, _) -> ok end;
make_fun_with_arity(3) -> fun(_, _, _) -> ok end;
make_fun_with_arity(4) -> fun(_, _, _, _) -> ok end;
make_fun_with_arity(5) -> fun(_, _, _, _, _) -> ok end.
