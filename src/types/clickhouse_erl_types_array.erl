%% @doc ClickHouse Array type support.
%%
%% This module implements support for the ClickHouse Array type, which represents
%% variable-length lists of homogeneous values. Arrays use offset-based encoding
%% for efficient storage and random access.
%%
%% == Erlang Data Structure Mapping ==
%%
%% ClickHouse Array values are represented as Erlang lists:
%% ```
%% Array(Int64) -> [1, 2, 3, 4, 5]
%% Array(String) -> [<<"foo">>, <<"bar">>, <<"baz">>]
%% Array(Array(Int64)) -> [[1, 2], [3, 4, 5], [6]]
%% '''
%%
%% == Usage Examples ==
%%
%% === Parsing Array Types ===
%% ```
%% % Simple array
%% Type1 = clickhouse_erl_types_array:parse_array_type(<<"Array(Int64)">>).
%% % Returns: int64
%%
%% % Nested array
%% Type2 = clickhouse_erl_types_array:parse_array_type(<<"Array(Array(String))">>).
%% % Returns: {array, string}
%%
%% % Array of tuples
%% Type3 = clickhouse_erl_types_array:parse_array_type(<<"Array(Tuple(String, Int64))">>).
%% % Returns: {tuple, [string, int64]}
%% '''
%%
%% === Encoding Arrays ===
%% ```
%% Data = [[1, 2, 3], [4, 5], [6]],
%% {ok, Binary} = clickhouse_erl_types_array:encode_array_column(Data, int64).
%% '''
%%
%% === Decoding Arrays ===
%% ```
%% {ok, Arrays, Rest} = clickhouse_erl_types_array:decode_array_column(Binary, int64, 3).
%% % Returns: {ok, [[1, 2, 3], [4, 5], [6]], <<>>}
%% '''
%%
%% == Protocol Details ==
%%
%% Array columns use offset-based encoding:
%% 1. Offsets column (UInt64): Cumulative element counts
%% 2. Data column: Flattened elements
%%
%% Example: [[1,2,3], [4,5], [6]]
%% - Offsets: [3, 5, 6] (cumulative counts)
%% - Data: [1, 2, 3, 4, 5, 6] (flattened)
%%
%% @see clickhouse_erl_types_composite
-module(clickhouse_erl_types_array).

-include_lib("kernel/include/logger.hrl").

%% Public API
-export([
    % Type parsing
    parse_array_type/1,
    % Column encoding/decoding
    encode_array_column/2,
    decode_array_column/3
]).

%% Type definitions
-type array_type() :: {array, clickhouse_erl_types_composite:column_type()}.
-type array_error() ::
    {invalid_offsets, term()}
    | {array_element_error, non_neg_integer(), term()}.

-export_type([array_type/0, array_error/0]).

%%%===================================================================
%%% Type Parsing
%%%===================================================================

%% @doc Parse an Array type definition string.
%%
%% Examples:
%% "Array(UInt8)" -> uint8
%% "Array(String)" -> string
%% "Array(Array(Int64))" -> {array, int64}
-spec parse_array_type(binary() | string()) -> clickhouse_erl_types_composite:column_type().
parse_array_type(Type) when is_list(Type) ->
    parse_array_type(list_to_binary(Type));
parse_array_type(Type) when is_binary(Type) ->
    %% Remove "Array(" and closing ")"
    case binary:split(Type, <<"(">>) of
        [<<"Array">>, Rest] ->
            %% Extract inner type (remove trailing ")")
            InnerTypeStr = binary:part(Rest, 0, byte_size(Rest) - 1),
            %% Parse the inner type recursively
            clickhouse_erl_types_composite:parse_column_type(InnerTypeStr);
        _ ->
            error({invalid_array_type, Type})
    end.

%%%===================================================================
%%% Column Encoding
%%%===================================================================

%% @doc Encode an array column.
%%
%% Transforms a list of arrays into:
%% 1. Offsets column (UInt64): cumulative element counts
%% 2. Data column: flattened elements
-spec encode_array_column([list()], clickhouse_erl_types_composite:column_type()) ->
    {ok, binary()} | {error, term()}.
encode_array_column(Arrays, ElementType) ->
    %% Calculate cumulative offsets and flatten arrays
    {Offsets, FlattenedData} = calculate_offsets_and_flatten(Arrays),

    %% Encode offsets column (UInt64)
    OffsetsEncoded = clickhouse_erl_types_composite:encode_offsets(Offsets),

    %% Encode flattened data column
    case clickhouse_erl_types_column:encode_column(ElementType, FlattenedData) of
        {ok, DataEncoded} ->
            {ok, iolist_to_binary([OffsetsEncoded, DataEncoded])};
        Error ->
            Error
    end.

%% @doc Calculate cumulative offsets and flatten arrays into single list.
%%
%% Example: [[1,2,3], [4,5], [6]] -> {[3, 5, 6], [1,2,3,4,5,6]}
-spec calculate_offsets_and_flatten([list()]) -> {[non_neg_integer()], [term()]}.
calculate_offsets_and_flatten(Arrays) ->
    {Offsets, FlatData} = lists:foldl(
        fun(Array, {OffsetsAcc, DataAcc}) ->
            Len = length(Array),
            NewOffset =
                case OffsetsAcc of
                    [] -> Len;
                    [LastOffset | _] -> LastOffset + Len
                end,
            {[NewOffset | OffsetsAcc], DataAcc ++ Array}
        end,
        {[], []},
        Arrays
    ),
    {lists:reverse(Offsets), FlatData}.

%%%===================================================================
%%% Column Decoding
%%%===================================================================

%% @doc Decode an array column.
%%
%% The binary data for an array column consists of:
%% 1. Offsets column (UInt64): cumulative element counts
%% 2. Data column: flattened elements
-spec decode_array_column(
    binary(), clickhouse_erl_types_composite:column_type(), non_neg_integer()
) ->
    {ok, [list()], binary()} | {error, term()}.
decode_array_column(Binary, ElementType, RowCount) ->
    %% Decode offsets column
    case clickhouse_erl_types_composite:decode_offsets(Binary, RowCount) of
        {ok, Offsets, RestAfterOffsets} ->
            %% Calculate total element count from last offset
            TotalElements =
                case Offsets of
                    [] -> 0;
                    _ -> lists:last(Offsets)
                end,

            %% Decode flattened data column
            case decode_data_column(RestAfterOffsets, ElementType, TotalElements) of
                {ok, FlattenedData, Rest} ->
                    %% Reconstruct arrays using offset differences
                    Arrays = reconstruct_arrays(Offsets, FlattenedData),
                    {ok, Arrays, Rest};
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

%% @doc Decode the flattened data column.
-spec decode_data_column(
    binary(), clickhouse_erl_types_composite:column_type(), non_neg_integer()
) ->
    {ok, [term()], binary()} | {error, term()}.
decode_data_column(Binary, {low_cardinality, InnerType}, ElementCount) ->
    %% LowCardinality in nested context: no state version prefix
    %% Call nested decoder directly instead of going through data block decoder
    clickhouse_erl_types_low_cardinality:decode_low_cardinality_column_nested(
        Binary,
        InnerType,
        ElementCount
    );
decode_data_column(Binary, ElementType, ElementCount) ->
    %% Convert type to binary string for data block decoder
    TypeStr = clickhouse_erl_types_composite:type_to_binary(ElementType),
    clickhouse_erl_protocol_data_block:decode_column_data(TypeStr, ElementCount, Binary).

%% @doc Reconstruct arrays from offsets and flattened data.
%%
%% Example: Offsets=[3, 5, 6], Data=[1,2,3,4,5,6] -> [[1,2,3], [4,5], [6]]
-spec reconstruct_arrays([non_neg_integer()], [term()]) -> [list()].
reconstruct_arrays(Offsets, FlattenedData) ->
    reconstruct_arrays(Offsets, FlattenedData, 0, []).

reconstruct_arrays([], _Data, _PrevOffset, Acc) ->
    lists:reverse(Acc);
reconstruct_arrays([Offset | RestOffsets], Data, PrevOffset, Acc) ->
    %% Calculate how many elements in this array
    Count = Offset - PrevOffset,
    %% Extract elements for this array
    {ArrayElements, RestData} = lists:split(Count, Data),
    reconstruct_arrays(RestOffsets, RestData, Offset, [ArrayElements | Acc]).
