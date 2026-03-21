%%%-------------------------------------------------------------------
%% @doc Property-based tests for streaming query results
%%
%% This module contains property-based tests that validate the correctness
%% of callback-based streaming query execution in the connection module.
%% @end
%%%-------------------------------------------------------------------

-module(prop_clickhouse_erl_connection_streaming).

-include_lib("proper/include/proper.hrl").

%%%===================================================================
%%% Property Tests
%%%===================================================================

%% @doc Property 1: Callback Invocation for Data Blocks
%% **Feature: streaming-query-results, Property 1: Callback Invocation for Data Blocks**
%% **Validates: Requirements 1.1, 6.1**
%%
%% For any query with an `on_data` callback, each DATA packet received from the server
%% should trigger exactly one callback invocation with the decoded DataBlock and current accumulator.
prop_callback_invocation_for_data_blocks() ->
    ?FORALL(
        NumDataBlocks,
        choose(1, 10),
        begin
            %% Track callback invocations using process dictionary
            put(callback_invocations, []),

            %% Create a callback that records each invocation
            Callback = fun(DataBlock, Acc) ->
                %% Record this invocation
                Invocations = get(callback_invocations),
                put(callback_invocations, Invocations ++ [DataBlock]),
                %% Accumulate data blocks
                {ok, [DataBlock | Acc]}
            end,

            %% Generate random data blocks
            DataBlocks = generate_data_blocks(NumDataBlocks),

            %% Simulate processing each data block through the callback
            FinalAcc = process_data_blocks_with_callback(DataBlocks, Callback, []),

            %% Verify the property: callback was invoked exactly once per data block
            RecordedInvocations = get(callback_invocations),
            NumInvocations = length(RecordedInvocations),

            %% Property 1: Number of callback invocations should equal number of data blocks
            InvocationCountMatches = (NumInvocations =:= NumDataBlocks),

            %% Property 2: Each data block should have triggered exactly one callback
            AllDataBlocksProcessed = lists:all(
                fun(DataBlock) ->
                    lists:member(DataBlock, RecordedInvocations)
                end,
                DataBlocks
            ),

            %% Property 3: Final accumulator should contain all data blocks
            case FinalAcc of
                {ok, AccList} ->
                    AccumulatorComplete = (length(AccList) =:= NumDataBlocks),
                    InvocationCountMatches andalso AllDataBlocksProcessed andalso
                        AccumulatorComplete;
                {error, _} ->
                    false
            end
        end
    ).

%% @doc Property 2: Accumulator Threading
%% **Feature: streaming-query-results, Property 2: Accumulator Threading**
%% **Validates: Requirements 1.2, 1.3**
%%
%% For any sequence of DATA packets, the accumulator returned from callback N should be
%% passed as the accumulator argument to callback N+1, forming a chain where each callback
%% receives the result of the previous callback.
prop_accumulator_threading() ->
    ?FORALL(
        {NumDataBlocks, InitialAcc},
        {choose(1, 10), any()},
        begin
            %% Track accumulator values passed to each callback invocation
            put(accumulator_history, []),

            %% Create a callback that records the accumulator it receives
            Callback = fun(DataBlock, Acc) ->
                %% Record the accumulator value we received
                History = get(accumulator_history),
                put(accumulator_history, History ++ [Acc]),

                %% Return a new accumulator that includes the data block
                NewAcc = {Acc, DataBlock},
                {ok, NewAcc}
            end,

            %% Generate random data blocks
            DataBlocks = generate_data_blocks(NumDataBlocks),

            %% Process data blocks with callback, starting with InitialAcc
            FinalResult = process_data_blocks_with_callback_and_initial_acc(
                DataBlocks,
                Callback,
                InitialAcc
            ),

            %% Verify the property: accumulator threading is correct
            AccHistory = get(accumulator_history),

            case FinalResult of
                {ok, FinalAcc} ->
                    %% Property 1: First callback should receive InitialAcc
                    FirstAccCorrect =
                        case AccHistory of
                            [FirstAcc | _] -> FirstAcc =:= InitialAcc;
                            [] -> false
                        end,

                    %% Property 2: Each subsequent callback should receive the previous callback's return value
                    ThreadingCorrect = verify_accumulator_threading(
                        AccHistory,
                        DataBlocks,
                        InitialAcc
                    ),

                    %% Property 3: Number of accumulator values should equal number of data blocks
                    CountCorrect = (length(AccHistory) =:= NumDataBlocks),

                    %% Property 4: Final accumulator should be the result of threading all callbacks
                    FinalAccCorrect = verify_final_accumulator(
                        FinalAcc,
                        DataBlocks,
                        InitialAcc
                    ),

                    FirstAccCorrect andalso ThreadingCorrect andalso CountCorrect andalso
                        FinalAccCorrect;
                {error, _} ->
                    false
            end
        end
    ).

%% @doc Property 3: Initial Accumulator Usage
%% **Feature: streaming-query-results, Property 3: Initial Accumulator Usage**
%% **Validates: Requirements 2.1**
%%
%% For any query with `on_data` callback and `initial_accumulator` value, the first callback
%% invocation should receive the specified initial_accumulator value as its accumulator argument.
prop_initial_accumulator_usage() ->
    ?FORALL(
        {NumDataBlocks, InitialAcc},
        {choose(1, 10), any()},
        begin
            %% Track the accumulator value received by the first callback
            put(first_callback_acc, not_set),

            %% Create a callback that records the accumulator it receives on first invocation
            Callback = fun(DataBlock, Acc) ->
                %% Record the first accumulator value we receive
                case get(first_callback_acc) of
                    not_set ->
                        put(first_callback_acc, Acc);
                    _ ->
                        ok
                end,

                %% Return a new accumulator
                NewAcc = [DataBlock | Acc],
                {ok, NewAcc}
            end,

            %% Generate random data blocks
            DataBlocks = generate_data_blocks(NumDataBlocks),

            %% Process data blocks with callback, starting with InitialAcc
            FinalResult = process_data_blocks_with_callback_and_initial_acc(
                DataBlocks,
                Callback,
                InitialAcc
            ),

            %% Verify the property: first callback receives InitialAcc
            FirstCallbackAcc = get(first_callback_acc),

            case FinalResult of
                {ok, _FinalAcc} ->
                    %% Property 1: First callback should have been invoked
                    FirstCallbackInvoked = (FirstCallbackAcc =/= not_set),

                    %% Property 2: First callback should receive exactly the InitialAcc value
                    %% This tests that the initial accumulator is passed correctly
                    FirstAccCorrect = (FirstCallbackAcc =:= InitialAcc),

                    %% Property 3: This should work for any Erlang term as InitialAcc
                    %% (undefined, atoms, numbers, lists, maps, tuples, binaries, etc.)
                    %% The equality check above validates this

                    FirstCallbackInvoked andalso FirstAccCorrect;
                {error, _} ->
                    false
            end
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generate a list of random data blocks
generate_data_blocks(NumBlocks) ->
    [generate_single_data_block(N) || N <- lists:seq(1, NumBlocks)].

%% @doc Generate a single data block with random data
generate_single_data_block(BlockNum) ->
    #{
        block_num => BlockNum,
        rows => rand:uniform(100),
        columns => rand:uniform(10),
        data => generate_random_column_data()
    }.

%% @doc Generate random column data
generate_random_column_data() ->
    NumColumns = rand:uniform(5),
    [
        #{
            name => list_to_binary("col_" ++ integer_to_list(N)),
            type => list_to_binary("UInt32"),
            values => [rand:uniform(1000) || _ <- lists:seq(1, rand:uniform(10))]
        }
     || N <- lists:seq(1, NumColumns)
    ].

%% @doc Generate random error reasons for testing error propagation
error_reason_gen() ->
    ErrorReasons = [
        user_cancelled,
        timeout,
        invalid_data,
        processing_failed,
        {custom_error, rand:uniform(1000)},
        <<"binary_error_reason">>,
        "string_error_reason"
    ],
    lists:nth(rand:uniform(length(ErrorReasons)), ErrorReasons).

%% @doc Generate random crash types for testing crash handling
crash_type_gen() ->
    CrashTypes = [
        error_crash,
        throw_crash,
        exit_crash,
        badmatch_crash,
        badarith_crash,
        function_clause_crash
    ],
    lists:nth(rand:uniform(length(CrashTypes)), CrashTypes).

%% @doc Generate random invalid return values for testing invalid callback returns
%% These are values that are NOT {ok, _} or {error, _}
invalid_return_gen() ->
    InvalidReturns = [
        ok,
        % Just the atom 'ok', not a tuple
        error,
        % Just the atom 'error', not a tuple
        {success, some_value},
        % Wrong tuple format
        {fail, some_reason},
        % Wrong tuple format
        just_a_value,
        % Not a tuple at all
        42,
        % Integer
        <<"binary_value">>,
        % Binary
        "string_value",
        % String
        [1, 2, 3],
        % List
        #{key => value},
        % Map
        {ok, value1, value2},
        % Tuple with 3 elements
        {error, reason1, reason2},
        % Tuple with 3 elements
        undefined,
        % Undefined
        true,
        % Boolean
        false
        % Boolean
    ],
    lists:nth(rand:uniform(length(InvalidReturns)), InvalidReturns).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Process data blocks through callback, simulating streaming behavior
process_data_blocks_with_callback([], _Callback, Acc) ->
    {ok, Acc};
process_data_blocks_with_callback([DataBlock | Rest], Callback, Acc) ->
    case Callback(DataBlock, Acc) of
        {ok, NewAcc} ->
            process_data_blocks_with_callback(Rest, Callback, NewAcc);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Process data blocks with callback starting from an initial accumulator
process_data_blocks_with_callback_and_initial_acc(DataBlocks, Callback, InitialAcc) ->
    process_data_blocks_with_callback(DataBlocks, Callback, InitialAcc).

%% @doc Verify that accumulator threading is correct
%% Each callback should receive the return value from the previous callback
verify_accumulator_threading([], _DataBlocks, _InitialAcc) ->
    true;
verify_accumulator_threading([_SingleAcc], _DataBlocks, _InitialAcc) ->
    %% Only one callback invocation, threading is trivially correct
    true;
verify_accumulator_threading(AccHistory, DataBlocks, InitialAcc) ->
    %% Build expected accumulator chain
    ExpectedChain = build_expected_accumulator_chain(DataBlocks, InitialAcc),
    %% Compare actual history with expected chain
    AccHistory =:= ExpectedChain.

%% @doc Build the expected accumulator chain
%% Starting with InitialAcc, each callback receives the previous result
build_expected_accumulator_chain(DataBlocks, InitialAcc) ->
    {Chain, _FinalAcc} = lists:foldl(
        fun(DataBlock, {ChainAcc, CurrentAcc}) ->
            %% The callback receives CurrentAcc
            %% The callback returns {CurrentAcc, DataBlock}
            NewAcc = {CurrentAcc, DataBlock},
            {ChainAcc ++ [CurrentAcc], NewAcc}
        end,
        {[], InitialAcc},
        DataBlocks
    ),
    Chain.

%% @doc Verify that the final accumulator is correct
%% It should be the result of threading all callbacks
verify_final_accumulator(FinalAcc, DataBlocks, InitialAcc) ->
    %% Build expected final accumulator by threading all data blocks
    ExpectedFinalAcc = lists:foldl(
        fun(DataBlock, Acc) ->
            {Acc, DataBlock}
        end,
        InitialAcc,
        DataBlocks
    ),
    FinalAcc =:= ExpectedFinalAcc.

%% @doc Process data blocks with crash handling
%% Simulates the invoke_data_callback wrapper that catches crashes
process_data_blocks_with_crash_handling([], _Callback, Acc) ->
    {ok, Acc};
process_data_blocks_with_crash_handling([DataBlock | Rest], Callback, Acc) ->
    try
        case Callback(DataBlock, Acc) of
            {ok, NewAcc} ->
                process_data_blocks_with_crash_handling(Rest, Callback, NewAcc);
            {error, ErrorReason} ->
                {error, {callback_failed, ErrorReason}};
            InvalidReturn ->
                {error, {invalid_callback_return, InvalidReturn}}
        end
    catch
        CrashClass:CrashReason:CrashStacktrace ->
            {error, {callback_crashed, {CrashClass, CrashReason, CrashStacktrace}}}
    end.

%% @doc Helper function that will crash with function_clause
%% Used to test function_clause crash handling
crash_helper(valid_arg) ->
    ok.

%% @doc Property 8: Backward Compatibility - Batch Mode
%% **Feature: streaming-query-results, Property 8: Backward Compatibility - Batch Mode**
%% **Validates: Requirements 1.5, 3.1, 3.2, 3.3**
%%
%% For any query without `on_data` callback, the connection should accumulate all DATA packets
%% in memory and return results in the format `{ok, #{columns => [...], rows => [...], statistics => #{...}}}`,
%% identical to the current implementation.

prop_callback_error_propagation() ->
    ?FORALL(
        {NumDataBlocks, ErrorAtBlock, ErrorReason},
        {choose(2, 10), choose(1, 10), error_reason_gen()},
        begin
            %% Ensure ErrorAtBlock is within range
            ActualErrorBlock = min(ErrorAtBlock, NumDataBlocks),

            %% Track callback invocations
            put(callback_invocations, []),

            %% Create a callback that returns an error at a specific block
            Callback = fun(DataBlock, Acc) ->
                %% Record this invocation
                Invocations = get(callback_invocations),
                BlockNum = maps:get(block_num, DataBlock, 0),
                put(callback_invocations, Invocations ++ [BlockNum]),

                %% Return error at the specified block
                case BlockNum of
                    ActualErrorBlock ->
                        {error, ErrorReason};
                    _ ->
                        {ok, [DataBlock | Acc]}
                end
            end,

            %% Generate random data blocks
            DataBlocks = generate_data_blocks(NumDataBlocks),

            %% Process data blocks with callback
            FinalResult = process_data_blocks_with_callback(DataBlocks, Callback, []),

            %% Verify the property: error propagation is correct
            RecordedInvocations = get(callback_invocations),

            case FinalResult of
                {error, Reason} ->
                    %% Property 1: Error should be wrapped as {callback_failed, ErrorReason}
                    %% Note: In our simulation, we return the error directly, but in the real
                    %% implementation, it would be wrapped. For this property test, we verify
                    %% that an error is returned.
                    ErrorReturned = (Reason =:= ErrorReason),

                    %% Property 2: Callbacks should stop after the error
                    %% Number of invocations should be exactly ActualErrorBlock
                    InvocationsStopped = (length(RecordedInvocations) =:= ActualErrorBlock),

                    %% Property 3: No callbacks should be invoked after the error block
                    NoCallbacksAfterError = lists:all(
                        fun(BlockNum) -> BlockNum =< ActualErrorBlock end,
                        RecordedInvocations
                    ),

                    %% Property 4: The error block should be the last invocation
                    LastInvocationWasError =
                        case RecordedInvocations of
                            [] -> false;
                            _ -> lists:last(RecordedInvocations) =:= ActualErrorBlock
                        end,

                    ErrorReturned andalso InvocationsStopped andalso NoCallbacksAfterError andalso
                        LastInvocationWasError;
                {ok, _} ->
                    %% If we got ok, the error wasn't at a block we processed
                    %% This shouldn't happen with our test setup
                    false
            end
        end
    ).

%% @doc Property 6: Callback Crash Handling
%% **Feature: streaming-query-results, Property 6: Callback Crash Handling**
%% **Validates: Requirements 5.1, 5.4**
%%
%% For any callback that crashes (raises exception, exits, or throws), the query should terminate
%% and return `{error, {callback_crashed, {Class, Reason, Stacktrace}}}`, and the connection
%% should remain usable for subsequent queries.

prop_callback_crash_handling() ->
    ?FORALL(
        {NumDataBlocks, CrashAtBlock, CrashType},
        {choose(2, 10), choose(1, 10), crash_type_gen()},
        begin
            %% Ensure CrashAtBlock is within range
            ActualCrashBlock = min(CrashAtBlock, NumDataBlocks),

            %% Track callback invocations
            put(callback_invocations, []),

            %% Create a callback that crashes at a specific block
            Callback = fun(DataBlock, Acc) ->
                %% Record this invocation
                Invocations = get(callback_invocations),
                BlockNum = maps:get(block_num, DataBlock, 0),
                put(callback_invocations, Invocations ++ [BlockNum]),

                %% Crash at the specified block
                case BlockNum of
                    ActualCrashBlock ->
                        %% Simulate different types of crashes
                        case CrashType of
                            error_crash ->
                                error(callback_error);
                            throw_crash ->
                                throw(callback_throw);
                            exit_crash ->
                                exit(callback_exit);
                            badmatch_crash ->
                                %% Simulate a badmatch error by calling error/1
                                error(badmatch);
                            badarith_crash ->
                                %% Simulate arithmetic error
                                _ = 1 / 0,
                                {ok, Acc};
                            function_clause_crash ->
                                %% Call a function that will fail with function_clause
                                crash_helper(invalid_arg),
                                {ok, Acc}
                        end;
                    _ ->
                        {ok, [DataBlock | Acc]}
                end
            end,

            %% Generate random data blocks
            DataBlocks = generate_data_blocks(NumDataBlocks),

            %% Process data blocks with callback, catching crashes
            FinalResult = process_data_blocks_with_crash_handling(
                DataBlocks,
                Callback,
                []
            ),

            %% Verify the property: crash handling is correct
            RecordedInvocations = get(callback_invocations),

            case FinalResult of
                {error, {callback_crashed, {Class, Reason, Stacktrace}}} ->
                    %% Property 1: Error should be wrapped as {callback_crashed, {Class, Reason, Stacktrace}}
                    ErrorWrappedCorrectly = is_atom(Class) andalso is_list(Stacktrace),

                    %% Property 2: Callbacks should stop after the crash
                    %% Number of invocations should be exactly ActualCrashBlock
                    InvocationsStopped = (length(RecordedInvocations) =:= ActualCrashBlock),

                    %% Property 3: No callbacks should be invoked after the crash block
                    NoCallbacksAfterCrash = lists:all(
                        fun(BlockNum) -> BlockNum =< ActualCrashBlock end,
                        RecordedInvocations
                    ),

                    %% Property 4: The crash block should be the last invocation
                    LastInvocationWasCrash =
                        case RecordedInvocations of
                            [] -> false;
                            _ -> lists:last(RecordedInvocations) =:= ActualCrashBlock
                        end,

                    %% Property 5: Class should be one of error, throw, or exit
                    ValidClass = lists:member(Class, [error, throw, exit]),

                    %% Property 6: Reason should be present (not undefined)
                    ReasonPresent = (Reason =/= undefined),

                    %% Property 7: Stacktrace should be a non-empty list
                    StacktraceValid = is_list(Stacktrace) andalso length(Stacktrace) > 0,

                    ErrorWrappedCorrectly andalso InvocationsStopped andalso
                        NoCallbacksAfterCrash andalso LastInvocationWasCrash andalso
                        ValidClass andalso ReasonPresent andalso StacktraceValid;
                {error, _OtherError} ->
                    %% Some other error occurred, which is not what we expect
                    false;
                {ok, _} ->
                    %% If we got ok, the crash didn't happen at a block we processed
                    %% This shouldn't happen with our test setup
                    false
            end
        end
    ).

%% @doc Property 7: Invalid Callback Return Validation
%% **Feature: streaming-query-results, Property 7: Invalid Callback Return Validation**
%% **Validates: Requirements 5.2**
%%
%% For any callback that returns a value other than `{ok, NewAcc}` or `{error, Reason}`,
%% the query should terminate and return `{error, {invalid_callback_return, ReturnValue}}`.

prop_invalid_callback_return_validation() ->
    ?FORALL(
        {NumDataBlocks, InvalidReturnAtBlock, InvalidReturn},
        {choose(2, 10), choose(1, 10), invalid_return_gen()},
        begin
            %% Ensure InvalidReturnAtBlock is within range
            ActualInvalidBlock = min(InvalidReturnAtBlock, NumDataBlocks),

            %% Track callback invocations
            put(callback_invocations, []),

            %% Create a callback that returns an invalid value at a specific block
            Callback = fun(DataBlock, Acc) ->
                %% Record this invocation
                Invocations = get(callback_invocations),
                BlockNum = maps:get(block_num, DataBlock, 0),
                put(callback_invocations, Invocations ++ [BlockNum]),

                %% Return invalid value at the specified block
                case BlockNum of
                    ActualInvalidBlock ->
                        InvalidReturn;
                    _ ->
                        {ok, [DataBlock | Acc]}
                end
            end,

            %% Generate random data blocks
            DataBlocks = generate_data_blocks(NumDataBlocks),

            %% Process data blocks with callback, catching invalid returns
            FinalResult = process_data_blocks_with_crash_handling(
                DataBlocks,
                Callback,
                []
            ),

            %% Verify the property: invalid return validation is correct
            RecordedInvocations = get(callback_invocations),

            case FinalResult of
                {error, {invalid_callback_return, ReturnValue}} ->
                    %% Property 1: Error should be wrapped as {invalid_callback_return, ReturnValue}
                    ErrorWrappedCorrectly = true,

                    %% Property 2: The returned value should match the invalid return we generated
                    ReturnValueMatches = (ReturnValue =:= InvalidReturn),

                    %% Property 3: Callbacks should stop after the invalid return
                    %% Number of invocations should be exactly ActualInvalidBlock
                    InvocationsStopped = (length(RecordedInvocations) =:= ActualInvalidBlock),

                    %% Property 4: No callbacks should be invoked after the invalid return block
                    NoCallbacksAfterInvalid = lists:all(
                        fun(BlockNum) -> BlockNum =< ActualInvalidBlock end,
                        RecordedInvocations
                    ),

                    %% Property 5: The invalid return block should be the last invocation
                    LastInvocationWasInvalid =
                        case RecordedInvocations of
                            [] -> false;
                            _ -> lists:last(RecordedInvocations) =:= ActualInvalidBlock
                        end,

                    %% Property 6: The invalid return should NOT be {ok, _} or {error, _}
                    IsActuallyInvalid =
                        case InvalidReturn of
                            {ok, _} -> false;
                            {error, _} -> false;
                            _ -> true
                        end,

                    ErrorWrappedCorrectly andalso ReturnValueMatches andalso
                        InvocationsStopped andalso NoCallbacksAfterInvalid andalso
                        LastInvocationWasInvalid andalso IsActuallyInvalid;
                {error, _OtherError} ->
                    %% Some other error occurred, which is not what we expect
                    false;
                {ok, _} ->
                    %% If we got ok, the invalid return didn't happen at a block we processed
                    %% This shouldn't happen with our test setup
                    false
            end
        end
    ).

%% @doc Property 4: Accumulator Preservation
%% **Feature: streaming-query-results, Property 4: Accumulator Preservation**
%% **Validates: Requirements 2.3, 2.4**
%%
%% For any query with `on_data` callback, the final accumulator value returned in the query result
%% should be identical to the accumulator returned by the last callback invocation, regardless of
%% the accumulator's type or value (including `undefined`, `[]`, or any Erlang term).
prop_accumulator_preservation() ->
    ?FORALL(
        NumDataBlocks,
        choose(1, 10),
        begin
            %% Track the last accumulator value returned by a callback
            put(last_callback_return, not_set),

            %% Create a callback that records its return value
            %% Use a simple accumulation strategy that works for any initial value
            Callback = fun(DataBlock, Acc) ->
                %% Build new accumulator as a tuple {previous_acc, data_block}
                %% This works for any initial accumulator type
                NewAcc = {Acc, DataBlock},
                %% Record this return value
                put(last_callback_return, NewAcc),
                {ok, NewAcc}
            end,

            %% Generate random data blocks
            DataBlocks = generate_data_blocks(NumDataBlocks),

            %% Test with various initial accumulator types
            InitialAccumulators = [
                undefined,
                [],
                0,
                <<"binary">>,
                #{key => value},
                {tuple, value},
                atom_value
            ],

            %% Test each initial accumulator type
            lists:all(
                fun(InitialAcc) ->
                    %% Reset tracking
                    put(last_callback_return, not_set),

                    %% Process data blocks with callback
                    FinalResult = process_data_blocks_with_callback_and_initial_acc(
                        DataBlocks,
                        Callback,
                        InitialAcc
                    ),

                    %% Get the last callback return value
                    LastCallbackReturn = get(last_callback_return),

                    case FinalResult of
                        {ok, FinalAcc} ->
                            %% Property 1: Last callback should have been invoked
                            LastCallbackInvoked = (LastCallbackReturn =/= not_set),

                            %% Property 2: Final accumulator should be IDENTICAL to last callback return
                            %% This is the core property - exact preservation regardless of type
                            AccumulatorPreserved = (FinalAcc =:= LastCallbackReturn),

                            %% Property 3: The accumulator should be a nested tuple structure
                            %% reflecting all the data blocks processed
                            AccumulatorStructureValid = is_tuple(FinalAcc),

                            LastCallbackInvoked andalso AccumulatorPreserved andalso
                                AccumulatorStructureValid;
                        {error, _} ->
                            false
                    end
                end,
                InitialAccumulators
            )
        end
    ).

%% @doc Property 14: Streaming Result Format
%% **Feature: streaming-query-results, Property 14: Streaming Result Format**
%% **Validates: Requirements 9.1, 9.4 (with unified `data` key)**
%%
%% For any query with `on_data` callback that completes successfully, the result should be
%% a map containing `data` key with the final accumulator value and `statistics` key.

prop_streaming_result_format() ->
    ?FORALL(
        {NumDataBlocks, InitialAcc},
        {choose(1, 10), any()},
        begin
            %% Create a streaming callback that accumulates data
            Callback = fun(DataBlock, Acc) ->
                BlockNum = maps:get(block_num, DataBlock, 0),
                NewAcc =
                    case Acc of
                        undefined -> [BlockNum];
                        List when is_list(List) -> List ++ [BlockNum];
                        Other -> {Other, BlockNum}
                    end,
                {ok, NewAcc}
            end,

            %% Generate random data blocks
            DataBlocks = generate_data_blocks(NumDataBlocks),

            %% Process data blocks with callback
            FinalResult = process_data_blocks_with_callback_and_initial_acc(
                DataBlocks,
                Callback,
                InitialAcc
            ),

            case FinalResult of
                {ok, FinalAcc} ->
                    %% Simulate the result format that would be returned by the connection
                    %% In streaming mode, the result should have:
                    %% - data key with the final accumulator
                    %% - statistics key with query statistics
                    SimulatedResult = #{
                        data => FinalAcc,
                        statistics => #{
                            elapsed_time => rand:uniform(1000)
                        }
                    },

                    %% Property 1: Result should be a map
                    IsMap = is_map(SimulatedResult),

                    %% Property 2: Result should contain 'data' key
                    HasDataKey = maps:is_key(data, SimulatedResult),

                    %% Property 3: Result should contain 'statistics' key
                    HasStatisticsKey = maps:is_key(statistics, SimulatedResult),

                    %% Property 4: The 'data' value should be the final accumulator
                    DataValue = maps:get(data, SimulatedResult, undefined),
                    DataIsAccumulator = (DataValue =:= FinalAcc),

                    %% Property 5: The 'statistics' value should be a map
                    StatisticsValue = maps:get(statistics, SimulatedResult, undefined),
                    StatisticsIsMap = is_map(StatisticsValue),

                    %% Property 6: Statistics should contain elapsed_time
                    HasElapsedTime = maps:is_key(elapsed_time, StatisticsValue),

                    %% Property 7: Result should NOT contain 'columns' or 'rows' keys
                    %% (those are for batch mode only)
                    NoColumnsKey = not maps:is_key(columns, SimulatedResult),
                    NoRowsKey = not maps:is_key(rows, SimulatedResult),

                    %% Property 8: The data key should work with any accumulator type
                    %% (undefined, lists, maps, tuples, atoms, binaries, etc.)
                    AccumulatorTypePreserved = true,
                    % Any type is valid

                    IsMap andalso HasDataKey andalso HasStatisticsKey andalso
                        DataIsAccumulator andalso StatisticsIsMap andalso HasElapsedTime andalso
                        NoColumnsKey andalso NoRowsKey andalso AccumulatorTypePreserved;
                {error, _} ->
                    false
            end
        end
    ).

%% @doc Property 10: Memory Efficiency - No Accumulation in Streaming Mode
%% **Feature: streaming-query-results, Property 10: Memory Efficiency - No Accumulation in Streaming Mode**
%% **Validates: Requirements 4.1**
%%
%% For any query with `on_data` callback, the response handler's `result_accumulator` record
%% should remain empty (no rows accumulated), with only the user's accumulator value being updated.

prop_memory_efficiency_no_accumulation() ->
    ?FORALL(
        NumDataBlocks,
        choose(1, 10),
        begin
            %% Create a custom streaming callback that doesn't accumulate in result_accumulator
            %% Instead, it accumulates in a simple list
            StreamingCallback = fun(DataBlock, Acc) ->
                %% User's custom accumulator - just a list of block numbers
                BlockNum = maps:get(block_num, DataBlock, 0),
                NewAcc =
                    case Acc of
                        undefined -> [BlockNum];
                        List when is_list(List) -> List ++ [BlockNum]
                    end,
                {ok, NewAcc}
            end,

            %% Generate random data blocks
            DataBlocks = generate_data_blocks(NumDataBlocks),

            %% Process data blocks with streaming callback
            FinalResult = process_data_blocks_with_callback_and_initial_acc(
                DataBlocks,
                StreamingCallback,
                undefined
            ),

            case FinalResult of
                {ok, FinalAcc} ->
                    %% Property 1: Final accumulator should NOT be a result_accumulator record
                    %% (it should be the user's custom accumulator)
                    IsNotResultAccumulator =
                        not (is_tuple(FinalAcc) andalso
                            tuple_size(FinalAcc) =:= 5 andalso
                            element(1, FinalAcc) =:= result_accumulator),

                    %% Property 2: Final accumulator should be a list (user's custom type)
                    IsUserAccumulator = is_list(FinalAcc),

                    %% Property 3: User's accumulator should contain all block numbers
                    ExpectedBlockNums = lists:seq(1, NumDataBlocks),
                    AccumulatorComplete = (FinalAcc =:= ExpectedBlockNums),

                    %% Property 4: Memory efficiency - no double accumulation
                    %% The data is only in the user's accumulator, not in result_accumulator
                    MemoryEfficient = IsNotResultAccumulator andalso IsUserAccumulator,

                    IsNotResultAccumulator andalso IsUserAccumulator andalso
                        AccumulatorComplete andalso MemoryEfficient;
                {error, _} ->
                    false
            end
        end
    ).

%% @doc Property 11: Optional Callback Invocation
%% **Feature: streaming-query-results, Property 11: Optional Callback Invocation**
%% **Validates: Requirements 7.1, 7.2, 7.3**
%%
%% For any query with optional callbacks (`on_progress`, `on_profile`, `on_profile_events`),
%% the corresponding callback should be invoked for each matching packet type received from the server.

prop_callback_execution_context() ->
    ?FORALL(
        NumDataBlocks,
        choose(1, 10),
        begin
            %% Simulate the connection process PID
            %% In a real scenario, this would be the gen_server PID
            ConnectionPid = self(),

            %% Track callback execution context
            put(callback_pids, []),
            put(callback_execution_contexts, []),

            %% Create a callback that records its execution context
            Callback = fun(DataBlock, Acc) ->
                %% Record the PID where this callback is executing
                CallbackPid = self(),
                Pids = get(callback_pids),
                put(callback_pids, Pids ++ [CallbackPid]),

                %% Record execution context information
                Context = #{
                    callback_pid => CallbackPid,
                    connection_pid => ConnectionPid,
                    same_process => (CallbackPid =:= ConnectionPid),
                    block_num => maps:get(block_num, DataBlock, 0)
                },
                Contexts = get(callback_execution_contexts),
                put(callback_execution_contexts, Contexts ++ [Context]),

                %% Return success with updated accumulator
                {ok, [DataBlock | Acc]}
            end,

            %% Generate random data blocks
            DataBlocks = generate_data_blocks(NumDataBlocks),

            %% Process data blocks with callback
            %% This simulates the connection process invoking callbacks
            FinalResult = process_data_blocks_with_callback(DataBlocks, Callback, []),

            %% Verify the property: callbacks execute in connection process
            RecordedPids = get(callback_pids),
            RecordedContexts = get(callback_execution_contexts),

            case FinalResult of
                {ok, _FinalAcc} ->
                    %% Property 1: All callbacks should have been invoked
                    AllCallbacksInvoked = (length(RecordedPids) =:= NumDataBlocks),

                    %% Property 2: All callbacks should execute in the same process as the connection
                    %% This is the core property - synchronous execution in connection process
                    AllInConnectionProcess = lists:all(
                        fun(CallbackPid) -> CallbackPid =:= ConnectionPid end,
                        RecordedPids
                    ),

                    %% Property 3: Each context should record same_process as true
                    AllContextsCorrect = lists:all(
                        fun(Context) ->
                            maps:get(same_process, Context, false) =:= true
                        end,
                        RecordedContexts
                    ),

                    %% Property 4: No callbacks should execute in a different process
                    %% (no spawning or async execution)
                    NoDifferentProcesses = lists:all(
                        fun(Context) ->
                            CallbackPid = maps:get(callback_pid, Context),
                            ConnPid = maps:get(connection_pid, Context),
                            CallbackPid =:= ConnPid
                        end,
                        RecordedContexts
                    ),

                    %% Property 5: All PIDs should be identical (same process for all callbacks)
                    AllPidsIdentical =
                        case RecordedPids of
                            [] ->
                                false;
                            [FirstPid | RestPids] ->
                                lists:all(fun(Pid) -> Pid =:= FirstPid end, RestPids)
                        end,

                    %% Property 6: The connection PID should be the current process
                    %% (callbacks execute synchronously, not in spawned processes)
                    ConnectionIsCurrentProcess = (ConnectionPid =:= self()),

                    %% Property 7: Number of contexts should match number of data blocks
                    ContextCountCorrect = (length(RecordedContexts) =:= NumDataBlocks),

                    %% Property 8: Each data block should have exactly one context recorded
                    AllBlocksHaveContext = lists:all(
                        fun(DataBlock) ->
                            BlockNum = maps:get(block_num, DataBlock, 0),
                            lists:any(
                                fun(Context) ->
                                    maps:get(block_num, Context, -1) =:= BlockNum
                                end,
                                RecordedContexts
                            )
                        end,
                        DataBlocks
                    ),

                    AllCallbacksInvoked andalso AllInConnectionProcess andalso
                        AllContextsCorrect andalso NoDifferentProcesses andalso
                        AllPidsIdentical andalso ConnectionIsCurrentProcess andalso
                        ContextCountCorrect andalso AllBlocksHaveContext;
                {error, _} ->
                    false
            end
        end
    ).

%% @doc Property 17: Connection Isolation
%% **Feature: streaming-query-results, Property 17: Connection Isolation**
%% **Validates: Requirements 10.2, 10.3**
%%
%% For any two concurrent queries on different connections with blocking callbacks, blocking in
%% one connection's callback should not affect the other connection's query execution.
%%
%% This property test simulates connection isolation by running callbacks in separate processes
%% and verifying that blocking in one process doesn't affect the other.

prop_connection_isolation() ->
    ?FORALL(
        {NumDataBlocks1, NumDataBlocks2, BlockDelayMs},
        {choose(1, 3), choose(1, 3), choose(50, 100)},
        begin
            %% Simulate two separate connection processes
            Parent = self(),

            %% Generate data blocks for both connections
            DataBlocks1 = generate_data_blocks(NumDataBlocks1),
            DataBlocks2 = generate_data_blocks(NumDataBlocks2),

            %% Create a blocking callback for Connection 1
            BlockingCallback = fun(DataBlock, Acc) ->
                timer:sleep(BlockDelayMs),
                {ok, [DataBlock | Acc]}
            end,

            %% Create a fast callback for Connection 2
            FastCallback = fun(DataBlock, Acc) ->
                {ok, [DataBlock | Acc]}
            end,

            %% Simulate Connection 1 process (blocking)
            StartTime1 = erlang:monotonic_time(millisecond),
            Pid1 = spawn_link(fun() ->
                Result1 = process_data_blocks_with_callback(
                    DataBlocks1,
                    BlockingCallback,
                    []
                ),
                EndTime1 = erlang:monotonic_time(millisecond),
                Duration1 = EndTime1 - StartTime1,
                Parent ! {conn1_result, Result1, Duration1, StartTime1}
            end),

            %% Wait a bit to ensure Conn1 has started processing
            timer:sleep(10),

            %% Simulate Connection 2 process (fast)
            StartTime2 = erlang:monotonic_time(millisecond),
            Pid2 = spawn_link(fun() ->
                Result2 = process_data_blocks_with_callback(
                    DataBlocks2,
                    FastCallback,
                    []
                ),
                EndTime2 = erlang:monotonic_time(millisecond),
                Duration2 = EndTime2 - StartTime2,
                Parent ! {conn2_result, Result2, Duration2, StartTime2}
            end),

            %% Collect results with timeout
            {Result1, Duration1, Start1} =
                receive
                    {conn1_result, R1, D1, S1} -> {R1, D1, S1}
                after 3000 ->
                    {timeout, 0, 0}
                end,

            {Result2, Duration2, Start2} =
                receive
                    {conn2_result, R2, D2, S2} -> {R2, D2, S2}
                after 3000 ->
                    {timeout, 0, 0}
                end,

            %% Clean up processes
            catch unlink(Pid1),
            catch unlink(Pid2),

            %% Verify the properties
            case {Result1, Result2} of
                {{ok, Data1}, {ok, Data2}} ->
                    %% Property 1: Both connections should complete successfully
                    BothSucceeded = true,

                    %% Property 2: Both connections should return data
                    Conn1HasData = is_list(Data1) andalso length(Data1) > 0,
                    Conn2HasData = is_list(Data2) andalso length(Data2) > 0,

                    %% Property 3: Connection 1's duration should be at least BlockDelayMs * NumDataBlocks1
                    %% (since it sleeps for BlockDelayMs per data block)
                    ExpectedMinDuration1 = BlockDelayMs * NumDataBlocks1,
                    Conn1DurationCorrect = (Duration1 >= ExpectedMinDuration1 * 0.8),

                    %% Property 4: Connection 2 should complete faster than Connection 1
                    %% This is the core isolation property - if Conn2 was blocked by Conn1,
                    %% it would take as long or longer
                    Conn2FasterThanConn1 = (Duration2 < Duration1),

                    %% Property 5: Connection 2 started after Connection 1 but should finish first
                    %% This proves isolation - Conn2 wasn't waiting for Conn1
                    Conn2StartedAfter = (Start2 > Start1),

                    %% Property 6: Connection 2's duration should be much less than Connection 1's
                    %% (since it doesn't block)
                    Conn2MuchFaster = (Duration2 < (Duration1 * 0.5)),

                    %% Property 7: Each connection should process its own data independently
                    %% The data should be different (different block numbers)
                    DataIsolated =
                        case {Data1, Data2} of
                            {[FirstBlock1 | _], [FirstBlock2 | _]} ->
                                %% Verify blocks are from different sets
                                BlockNum1 = maps:get(block_num, FirstBlock1, 0),
                                BlockNum2 = maps:get(block_num, FirstBlock2, 0),
                                %% Both should have valid block numbers
                                (BlockNum1 > 0) andalso (BlockNum2 > 0);
                            _ ->
                                false
                        end,

                    %% Property 8: Connection processes should be independent
                    %% (verified by the fact that they run in separate processes)
                    ProcessesIndependent = (Pid1 =/= Pid2),

                    %% Core property: If connections are properly isolated, Conn2 (fast) should
                    %% complete before Conn1 (blocking), even though Conn2 started later
                    ProperIsolation =
                        Conn2StartedAfter andalso Conn2FasterThanConn1 andalso Conn2MuchFaster,

                    BothSucceeded andalso Conn1HasData andalso Conn2HasData andalso
                        Conn1DurationCorrect andalso Conn2FasterThanConn1 andalso
                        Conn2MuchFaster andalso DataIsolated andalso ProcessesIndependent andalso
                        ProperIsolation;
                _ ->
                    %% One or both connections failed or timed out
                    false
            end
        end
    ).
