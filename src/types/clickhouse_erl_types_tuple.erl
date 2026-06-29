%% @doc ClickHouse Tuple type support.
%%
%% This module implements support for the ClickHouse Tuple type, which represents
%% fixed-size heterogeneous collections. Tuples can contain elements of different
%% types and support both named and unnamed variants.
%%
%% == Erlang Data Structure Mapping ==
%%
%% ClickHouse Tuple values are represented as Erlang tuples:
%% ```
%% Tuple(String, Int64, Float64) -> {<<"Alice">>, 25, 95.5}
%% Tuple(name String, age Int64) -> {<<"Bob">>, 30}
%% '''
%%
%% == Usage Examples ==
%%
%% === Parsing Tuple Types ===
%% ```
%% % Unnamed tuple
%% Types1 = clickhouse_erl_types_tuple:parse_tuple_type(<<"Tuple(String, Int64)">>).
%% % Returns: [string, int64]
%%
%% % Named tuple
%% Types2 = clickhouse_erl_types_tuple:parse_tuple_type(<<"Tuple(name String, age Int64)">>).
%% % Returns: [string, int64]
%%
%% % Nested tuple
%% Types3 = clickhouse_erl_types_tuple:parse_tuple_type(<<"Tuple(Tuple(Int64, Int64), String)">>).
%% % Returns: [{tuple, [int64, int64]}, string]
%% '''
%%
%% === Encoding Tuples ===
%% ```
%% Data = [{<<"Alice">>, 25}, {<<"Bob">>, 30}, {<<"Charlie">>, 35}],
%% Types = [string, int64],
%% {ok, Binary} = clickhouse_erl_types_tuple:encode_tuple_column(Data, Types).
%% '''
%%
%% === Decoding Tuples ===
%% ```
%% Types = [string, int64],
%% {ok, Tuples, Rest} = clickhouse_erl_types_tuple:decode_tuple_column(Binary, Types, 3).
%% % Returns: {ok, [{<<"Alice">>, 25}, {<<"Bob">>, 30}, {<<"Charlie">>, 35}], <<>>}
%% '''
%%
%% == Protocol Details ==
%%
%% Tuple columns are encoded as sequential element columns with no additional metadata.
%% For N rows of Tuple(T1, T2, T3), the encoding is:
%% - Column 1: N values of type T1
%% - Column 2: N values of type T2
%% - Column 3: N values of type T3
%%
%% @see clickhouse_erl_types_composite
-module(clickhouse_erl_types_tuple).

-include_lib("kernel/include/logger.hrl").

%% Public API
-export([
    % Type parsing
    parse_tuple_type/1,
    % Column encoding/decoding
    encode_tuple_column/2,
    decode_tuple_column/3
]).

%% Type definitions
-type tuple_type() :: {tuple, [clickhouse_erl_types_composite:column_type()]}.

-export_type([tuple_type/0]).

%%%===================================================================
%%% Type Parsing
%%%===================================================================

%% @doc Parse a Tuple type definition string.
%%
%% Parses both unnamed and named tuple type definitions. For named tuples,
%% the names are ignored and only the types are returned.
%%
%% == Examples ==
%% ```
%% % Unnamed tuple
%% parse_tuple_type(<<"Tuple(UInt8, String)">>).
%% % Returns: [uint8, string]
%%
%% % Named tuple
%% parse_tuple_type(<<"Tuple(id UInt8, name String)">>).
%% % Returns: [uint8, string]
%%
%% % Nested tuple
%% parse_tuple_type(<<"Tuple(Tuple(Int64, Int64), String)">>).
%% % Returns: [{tuple, [int64, int64]}, string]
%% '''
%%
%% @param Type The tuple type string to parse
%% @returns List of element types
-spec parse_tuple_type(binary() | string()) -> [clickhouse_erl_types_composite:column_type()].
parse_tuple_type(Type) when is_list(Type) ->
    parse_tuple_type(list_to_binary(Type));
parse_tuple_type(Type) when is_binary(Type) ->
    %% Remove "Tuple(" and closing ")"
    ParamsContent =
        case binary:split(Type, <<"(">>) of
            [<<"Tuple">>, Rest] ->
                binary:part(Rest, 0, byte_size(Rest) - 1);
            _ ->
                error({invalid_tuple_type, Type})
        end,

    %% Parse comma-separated parameters
    Params = clickhouse_erl_types_composite:parse_type_params(ParamsContent),

    %% Process each parameter to extract type (ignoring name if present)
    lists:map(fun parse_tuple_element/1, Params).

%% @doc Parse a single tuple element, handling optional name.
%%
%% "UInt8" -> uint8
%% "name UInt8" -> uint8
-spec parse_tuple_element(binary()) -> clickhouse_erl_types_composite:column_type().
parse_tuple_element(Param) ->
    %% Check if element has a name (look for space separator)
    %% Note: This is a simplification. A robust parser would need to handle
    %% spaces within nested types (e.g. "Array(String)").
    %% However, since parse_type_params handles nested structures,
    %% we just need to distinguish "Name Type" vs "Type".

    %% Trim whitespace
    P = string:trim(Param),

    %% Split by space first
    Parts = binary:split(P, <<" ">>, [global, trim]),

    case Parts of
        [TypeStr] ->
            %% No space, must be just type
            clickhouse_erl_types_composite:parse_column_type(TypeStr);
        _ ->
            %% Check if it's "Name Type" or complex type like "Array(Int64)"
            %% If the first part looks like a valid identifier and the rest forms a valid type

            %% Strategy: Try to parse the whole string as a type first.
            %% If it fails or if we explicitly want to support named tuples,
            %% we assume the last part(s) form the type or the first part is the name.

            %% Actually, ClickHouse named tuples are "Name Type". Type can be complex.
            %% Let's simpler heuristic:
            %% 1. Attempt to parse the whole string as a type.
            %% 2. If valid, return it.
            %% 3. If invalid (or if we suspect it is named), try removing the first word.

            try
                %% Try parsing as is (unnamed element)
                clickhouse_erl_types_composite:parse_column_type(P)
            catch
                error:{unknown_type, _} ->
                    %% Could be named tuple element "Name Type"
                    %% Remove the first whitespace-separated token and try parsing the rest
                    case binary:split(P, <<" ">>) of
                        [_Name, Rest] ->
                            clickhouse_erl_types_composite:parse_column_type(string:trim(Rest));
                        _ ->
                            error({invalid_tuple_element, Param})
                    end
            end
    end.

%%%===================================================================
%%% Column Encoding
%%%===================================================================

%% @doc Encode a tuple column.
%%
%% Transforms a list of N-element tuples into N separate columns and encodes each.
%% All tuples must have the same number of elements matching the type definition.
%%
%% == Example ==
%% ```
%% Data = [{<<"Alice">>, 25, 95.5}, {<<"Bob">>, 30, 87.2}],
%% Types = [string, int64, float64],
%% {ok, Binary} = encode_tuple_column(Data, Types).
%% '''
%%
%% @param Data List of tuples to encode
%% @param ElementTypes List of element types matching tuple structure
%% @returns {ok, Binary} on success, {error, Reason} on failure
-spec encode_tuple_column([tuple()], [clickhouse_erl_types_composite:column_type()]) ->
    {ok, binary()} | {error, term()}.
encode_tuple_column(Data, ElementTypes) ->
    case unzip_tuples_to_columns(Data, length(ElementTypes)) of
        {ok, Columns} ->
            case check_and_encode_element_columns(Columns, ElementTypes, unused) of
                Binary when is_binary(Binary) ->
                    {ok, Binary};
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

%% Internal: Unzip list of tuples into list of columns (lists of values)
unzip_tuples_to_columns([], NumElements) ->
    %% Prepare empty list of lists
    {ok, lists:duplicate(NumElements, [])};
unzip_tuples_to_columns(Tuples, NumElements) ->
    %% Check first tuple to catch mismatch early
    case Tuples of
        [First | _] when tuple_size(First) /= NumElements ->
            {error,
                {tuple_size_mismatch, #{
                    expected => NumElements,
                    actual => tuple_size(First)
                }}};
        _ ->
            %% Unzip logic
            %% [{A1, B1}, {A2, B2}] -> [[A1, A2], [B1, B2]]
            %% We can use lists:unzip/1 for 2-tuples, lists:unzip3/1 for 3-tuples.
            %% For general N-tuples, we need a custom fold.
            case unzip_tuples_fold(Tuples, NumElements, lists:duplicate(NumElements, [])) of
                {ok, ColumnsReversed} ->
                    %% Reverse inner lists to get proper order
                    Columns = [lists:reverse(Col) || Col <- ColumnsReversed],
                    {ok, Columns};
                Error ->
                    Error
            end
    end.

%% Helper function to fold over tuples and build columns
unzip_tuples_fold([], _NumElements, AccCols) ->
    {ok, AccCols};
unzip_tuples_fold([Tuple | Rest], NumElements, AccCols) ->
    Values = tuple_to_list(Tuple),
    case length(Values) == NumElements of
        true ->
            NewAccCols = append_values(Values, AccCols, []),
            unzip_tuples_fold(Rest, NumElements, NewAccCols);
        false ->
            {error,
                {tuple_size_mismatch, #{
                    expected => NumElements,
                    actual => length(Values)
                }}}
    end.

%% Helper to append each value to its corresponding column accumulator
append_values([], [], Acc) ->
    lists:reverse(Acc);
append_values([V | VRest], [Col | ColRest], Acc) ->
    append_values(VRest, ColRest, [[V | Col] | Acc]).

%% Internal: Encode each element column recursively
check_and_encode_element_columns(Columns, Types, _InitialAcc) ->
    encode_columns_loop(Columns, Types, []).

encode_columns_loop([], [], Acc) ->
    iolist_to_binary(lists:reverse(Acc));
encode_columns_loop([Col | ColRest], [Type | TypeRest], Acc) ->
    case clickhouse_erl_types_column:encode_column(Type, Col) of
        {ok, Encoded} ->
            encode_columns_loop(ColRest, TypeRest, [Encoded | Acc]);
        Error ->
            Error
    end.

%%%===================================================================
%%% Column Decoding
%%%===================================================================

%% @doc Decode a tuple column.
%%
%% The binary data for a tuple column is the concatenation of element columns.
%% Each element column contains RowCount values of its respective type.
%%
%% == Example ==
%% ```
%% Types = [string, int64],
%% {ok, Tuples, Rest} = decode_tuple_column(Binary, Types, 3).
%% % Returns: {ok, [{<<"Alice">>, 25}, {<<"Bob">>, 30}, {<<"Charlie">>, 35}], Rest}
%% '''
%%
%% @param Binary The binary data to decode
%% @param ElementTypes List of element types
%% @param RowCount Number of tuples to decode
%% @returns {ok, Tuples, Rest} on success, {error, Reason} on failure
-spec decode_tuple_column(
    binary(), [clickhouse_erl_types_composite:column_type()], non_neg_integer()
) ->
    {ok, [tuple()], binary()} | {error, term()}.
decode_tuple_column(Binary, [], RowCount) ->
    %% Empty tuple case: returns RowCount empty tuples
    {ok, lists:duplicate(RowCount, {}), Binary};
decode_tuple_column(Binary, ElementTypes, RowCount) ->
    %% Decode each element column sequentially
    case decode_element_columns(Binary, ElementTypes, RowCount, []) of
        {ok, Columns, Rest} ->
            %% Combine columns into tuples
            Tuples = zip_columns_to_tuples(Columns, RowCount),
            {ok, Tuples, Rest};
        Error ->
            Error
    end.

%% Internal: Decode each element column recursively
decode_element_columns(Binary, [], _RowCount, Acc) ->
    {ok, lists:reverse(Acc), Binary};
decode_element_columns(Binary, [Type | RestTypes], RowCount, Acc) ->
    %% Call the data block decoder for each element type
    case
        clickhouse_erl_protocol_data_block:decode_column_data(
            clickhouse_erl_types_composite:type_to_binary(Type), RowCount, Binary
        )
    of
        {ok, Values, NextBinary} ->
            decode_element_columns(NextBinary, RestTypes, RowCount, [Values | Acc]);
        Error ->
            Error
    end.

%% Internal: Zip list of columns (lists of values) into list of tuples
zip_columns_to_tuples(_Columns, 0) ->
    [];
zip_columns_to_tuples(Columns, RowCount) ->
    %% Transpose: [[A1, A2], [B1, B2]] -> [{A1, B1}, {A2, B2}]
    %% We can use list-comprehensions or recursive function.
    %% Since we know row count, we can do it efficiently.
    transpose_to_tuples(Columns, RowCount).

transpose_to_tuples(Columns, RowCount) ->
    %% Columns is a list of lists: [ [A1, ...], [B1, ...] ]
    %% We want: [ {A1, B1, ...}, ... ]

    %% Helper to extract heads and tails
    SplitHeads = fun(Cols, AccHeads, AccTails) ->
        split_heads(Cols, AccHeads, AccTails)
    end,

    lists:reverse(transpose_loop(Columns, RowCount, [], SplitHeads)).

transpose_loop(_Columns, 0, Acc, _SplitHeads) ->
    Acc;
transpose_loop(Columns, N, Acc, SplitHeads) ->
    {Heads, Tails} = SplitHeads(Columns, [], []),
    transpose_loop(Tails, N - 1, [list_to_tuple(Heads) | Acc], SplitHeads).

split_heads([], AccHeads, AccTails) ->
    {lists:reverse(AccHeads), lists:reverse(AccTails)};
split_heads([[H | T] | Rest], AccHeads, AccTails) ->
    split_heads(Rest, [H | AccHeads], [T | AccTails]).
