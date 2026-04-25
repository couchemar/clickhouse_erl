%% @doc Pure helper functions for streaming insert operations.
%% Validation, type merging, timeout checking, stats tracking, and callback invocation.
-module(clickhouse_erl_streaming_helpers).

%% API
-export([
    validate_streaming_block/2,
    validate_column_names/2,
    merge_column_types/2,
    has_rows/1,
    validate_streaming_request/1,
    safe_invoke_on_input/3,
    check_timeout/2,
    increment_stats/2,
    build_streaming_result/1
]).

-ignore_xref([
    validate_streaming_block/2,
    validate_column_names/2,
    merge_column_types/2,
    has_rows/1,
    validate_streaming_request/1,
    safe_invoke_on_input/3,
    check_timeout/2,
    increment_stats/2,
    build_streaming_result/1
]).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Validate a streaming block against original column definitions.
%% Checks row count consistency within the data and column name matching
%% against original definitions.
-spec validate_streaming_block([map()], [map()]) -> ok | {error, {validation_error, term()}}.
validate_streaming_block(ColumnData, OriginalDefs) when
    is_list(ColumnData), is_list(OriginalDefs)
->
    case validate_row_counts_match_original(ColumnData, OriginalDefs) of
        ok ->
            case clickhouse_erl_protocol_data_block:validate_row_counts(ColumnData) of
                ok ->
                    validate_column_names(ColumnData, OriginalDefs);
                {error, {row_count_mismatch, Details}} ->
                    {error, {validation_error, {row_count_mismatch, Details}}}
            end;
        Error ->
            Error
    end.

%% @doc Validate that column names in the data match the original definitions.
-spec validate_column_names([map()], [map()]) ->
    ok | {error, {validation_error, {column_name_mismatch, [binary()], [binary()]}}}.
validate_column_names(ColumnData, OriginalDefs) ->
    ExpectedNames = [maps:get(name, Def) || Def <- OriginalDefs],
    GotNames = [maps:get(name, Col) || Col <- ColumnData],
    case ExpectedNames =:= GotNames of
        true -> ok;
        false -> {error, {validation_error, {column_name_mismatch, ExpectedNames, GotNames}}}
    end.

%% @doc Merge column types from definitions into column data.
%% Adds the `type` key from column definitions to each column data map,
%% matching by position.
-spec merge_column_types([map()], [map()]) -> [map()].
merge_column_types(ColumnData, ColumnDefs) ->
    lists:zipwith(
        fun(Col, Def) -> Col#{type => maps:get(type, Def)} end,
        ColumnData,
        ColumnDefs
    ).

%% @doc Check if column data has any rows.
-spec has_rows([map()]) -> boolean().
has_rows([]) ->
    false;
has_rows([#{data := Data} | Rest]) ->
    case Data of
        [] -> has_rows(Rest);
        [_ | _] -> true
    end.

%% @doc Validate streaming insert request (on_input callback and columns).
-spec validate_streaming_request(map()) ->
    ok | {error, {validation_error, missing_on_input_callback | empty_columns}}.
validate_streaming_request(PreparedRequest) ->
    case maps:find(on_input, PreparedRequest) of
        {ok, _OnInput} ->
            case maps:get(columns, PreparedRequest, []) of
                [] -> {error, {validation_error, empty_columns}};
                _ -> ok
            end;
        error ->
            {error, {validation_error, missing_on_input_callback}}
    end.

%% @doc Safely invoke the on_input callback, catching crashes.
-spec safe_invoke_on_input(function(), [map()], term()) ->
    {ok, [map()], term()} | {done, term()} | {error, term()}.
safe_invoke_on_input(Callback, _Columns, Acc) ->
    try Callback(Acc) of
        {ok, UpdatedColumns, NewAcc} when is_list(UpdatedColumns) ->
            {ok, UpdatedColumns, NewAcc};
        {done, NewAcc} ->
            {done, NewAcc};
        {error, Reason} ->
            {error, Reason};
        Other ->
            {error, {invalid_callback_return, Other}}
    catch
        error:Err:Stack ->
            {error, {callback_crashed, {error, Err, Stack}}};
        exit:Reason:Stack ->
            {error, {callback_crashed, {exit, Reason, Stack}}};
        throw:Reason:Stack ->
            {error, {callback_crashed, {throw, Reason, Stack}}}
    end.

%% @doc Check remaining time for streaming insert.
-spec check_timeout(non_neg_integer(), timeout()) ->
    ok | {error, {timeout_error, streaming_insert}}.
check_timeout(_StartTime, infinity) ->
    ok;
check_timeout(StartTime, Timeout) ->
    Elapsed = erlang:system_time(millisecond) - StartTime,
    case Elapsed > Timeout of
        true -> {error, {timeout_error, streaming_insert}};
        false -> ok
    end.

%% @doc Increment streaming stats after sending a block.
-spec increment_stats(map(), [map()]) -> map().
increment_stats(Stats, ColumnData) ->
    NumRows =
        case ColumnData of
            [] -> 0;
            [#{data := Data} | _] -> length(Data)
        end,
    Stats#{
        rows_inserted => maps:get(rows_inserted, Stats) + NumRows,
        blocks_sent => maps:get(blocks_sent, Stats) + 1
    }.

%% @doc Build streaming insert result map.
-spec build_streaming_result(map()) -> map().
build_streaming_result(SessionState) ->
    #{rows_inserted := RowsInserted, blocks_sent := BlocksSent} = SessionState,
    ElapsedTime =
        case maps:find(start_time, SessionState) of
            {ok, StartTime} -> erlang:system_time(millisecond) - StartTime;
            error -> 0
        end,
    #{rows_inserted => RowsInserted, blocks_sent => BlocksSent, elapsed_time => ElapsedTime}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Validate that row counts in ColumnData match those in OriginalDefs.
-spec validate_row_counts_match_original([map()], [map()]) ->
    ok | {error, {validation_error, term()}}.
validate_row_counts_match_original([], _OriginalDefs) ->
    ok;
validate_row_counts_match_original(_ColumnData, []) ->
    ok;
validate_row_counts_match_original(ColumnData, OriginalDefs) ->
    ExpectedRows =
        case OriginalDefs of
            [#{data := ExpData} | _] -> length(ExpData);
            _ -> undefined
        end,
    case ExpectedRows of
        0 ->
            ok;
        undefined ->
            ok;
        _ ->
            ActualRows =
                case ColumnData of
                    [#{data := ActData} | _] -> length(ActData);
                    _ -> 0
                end,
            case ExpectedRows =:= ActualRows of
                true ->
                    ok;
                false ->
                    {error,
                        {validation_error,
                            {row_count_mismatch, OriginalDefs, ExpectedRows, ActualRows}}}
            end
    end.
