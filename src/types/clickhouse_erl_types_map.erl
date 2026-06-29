%% @doc ClickHouse Map type support.
%%
%% This module implements support for the ClickHouse Map type, which represents
%% key-value pairs with comparable key types. Maps use offset-based encoding
%% similar to arrays but with separate key and value columns.
%%
%% == Erlang Data Structure Mapping ==
%%
%% ClickHouse Map values are represented as Erlang maps:
%% ```
%% Map(String, Int64) -> #{<<"key1">> => 100, <<"key2">> => 200}
%% Map(String, Array(Int64)) -> #{<<"a">> => [1,2,3], <<"b">> => [4,5]}
%% '''
%%
%% == Usage Examples ==
%%
%% === Parsing Map Types ===
%% ```
%% % Simple map
%% {KeyType, ValueType} = clickhouse_erl_types_map:parse_map_type(<<"Map(String, Int64)">>).
%% % Returns: {string, int64}
%%
%% % Map with complex value type
%% {K, V} = clickhouse_erl_types_map:parse_map_type(<<"Map(String, Array(Int64))">>).
%% % Returns: {string, {array, int64}}
%% '''
%%
%% === Encoding Maps ===
%% ```
%% Data = [#{<<"a">> => 1, <<"b">> => 2}, #{<<"c">> => 3}],
%% {ok, Binary} = clickhouse_erl_types_map:encode_map_column(Data, string, int64).
%% '''
%%
%% === Decoding Maps ===
%% ```
%% {ok, Maps, Rest} = clickhouse_erl_types_map:decode_map_column(Binary, string, int64, 2).
%% % Returns: {ok, [#{<<"a">> => 1, <<"b">> => 2}, #{<<"c">> => 3}], <<>>}
%% '''
%%
%% == Protocol Details ==
%%
%% Map columns use offset-based encoding with separate key and value columns:
%% 1. Offsets column (UInt64): Cumulative pair counts
%% 2. Keys column: Flattened keys
%% 3. Values column: Flattened values
%%
%% Example: [#{<<"a">> => 1, <<"b">> => 2}, #{<<"c">> => 3}]
%% - Offsets: [2, 3]
%% - Keys: [<<"a">>, <<"b">>, <<"c">>]
%% - Values: [1, 2, 3]
%%
%% == Key Type Restrictions ==
%%
%% Key types must be comparable. Arrays and Maps cannot be used as keys.
%%
%% @see clickhouse_erl_types_composite
-module(clickhouse_erl_types_map).

-include_lib("kernel/include/logger.hrl").

%% Public API
-export([
    % Type parsing
    parse_map_type/1,
    % Column encoding/decoding
    encode_map_column/3,
    decode_map_column/4
]).

%% Type definitions
-type map_type() ::
    {map, clickhouse_erl_types_composite:column_type(),
        clickhouse_erl_types_composite:column_type()}.
-type map_error() ::
    {invalid_map_offsets, term()}
    | {map_key_error, non_neg_integer(), term()}
    | {map_value_error, non_neg_integer(), term()}
    | {invalid_key_type, term()}.

-export_type([map_type/0, map_error/0]).

%%%===================================================================
%%% Type Parsing
%%%===================================================================

%% @doc Parse a Map type definition string.
%%
%% Examples:
%% "Map(String, UInt64)" -> {string, uint64}
%% "Map(String, Array(Int64))" -> {string, {array, int64}}
-spec parse_map_type(binary() | string()) ->
    {clickhouse_erl_types_composite:column_type(), clickhouse_erl_types_composite:column_type()}.
parse_map_type(Type) when is_list(Type) ->
    parse_map_type(list_to_binary(Type));
parse_map_type(Type) when is_binary(Type) ->
    %% Remove "Map(" and closing ")"
    case binary:split(Type, <<"(">>) of
        [<<"Map">>, Rest] ->
            %% Extract parameters (remove trailing ")")
            ParamsContent = binary:part(Rest, 0, byte_size(Rest) - 1),
            %% Parse comma-separated parameters
            case clickhouse_erl_types_composite:parse_type_params(ParamsContent) of
                [KeyTypeStr, ValueTypeStr] ->
                    KeyType = clickhouse_erl_types_composite:parse_column_type(KeyTypeStr),
                    ValueType = clickhouse_erl_types_composite:parse_column_type(ValueTypeStr),
                    %% Validate key type is comparable
                    case validate_key_type(KeyType) of
                        ok ->
                            {KeyType, ValueType};
                        {error, Reason} ->
                            error(Reason)
                    end;
                _ ->
                    error({invalid_map_type, Type})
            end;
        _ ->
            error({invalid_map_type, Type})
    end.

%% @doc Validate that key type is comparable (no arrays or maps as keys).
-spec validate_key_type(clickhouse_erl_types_composite:column_type()) ->
    ok | {error, {invalid_key_type, term()}}.
validate_key_type({array, _}) ->
    {error, {invalid_key_type, array}};
validate_key_type({map, _, _}) ->
    {error, {invalid_key_type, map}};
validate_key_type(_) ->
    ok.

%%%===================================================================
%%% Column Encoding
%%%===================================================================

%% @doc Encode a map column.
%%
%% Transforms a list of maps into:
%% 1. Offsets column (UInt64): cumulative pair counts
%% 2. Keys column: flattened keys
%% 3. Values column: flattened values
-spec encode_map_column(
    [map()],
    clickhouse_erl_types_composite:column_type(),
    clickhouse_erl_types_composite:column_type()
) ->
    {ok, binary()} | {error, term()}.
encode_map_column(Maps, KeyType, ValueType) ->
    %% Calculate cumulative offsets and flatten maps
    {Offsets, FlattenedKeys, FlattenedValues} = calculate_offsets_and_flatten_maps(Maps),

    %% Encode offsets column (UInt64)
    OffsetsEncoded = clickhouse_erl_types_composite:encode_offsets(Offsets),

    %% Encode flattened keys column
    case clickhouse_erl_types_column:encode_column(KeyType, FlattenedKeys) of
        {ok, KeysEncoded} ->
            %% Encode flattened values column
            case clickhouse_erl_types_column:encode_column(ValueType, FlattenedValues) of
                {ok, ValuesEncoded} ->
                    {ok, iolist_to_binary([OffsetsEncoded, KeysEncoded, ValuesEncoded])};
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

%% @doc Calculate cumulative offsets and flatten maps into keys and values lists.
%%
%% Example: [#{a => 1, b => 2}, #{c => 3}] -> {[2, 3], [a,b,c], [1,2,3]}
-spec calculate_offsets_and_flatten_maps([map()]) ->
    {[non_neg_integer()], [term()], [term()]}.
calculate_offsets_and_flatten_maps(Maps) ->
    {Offsets, Keys, Values} = lists:foldl(
        fun(Map, {OffsetsAcc, KeysAcc, ValuesAcc}) ->
            %% Convert map to list of {Key, Value} pairs
            Pairs = maps:to_list(Map),
            PairCount = length(Pairs),

            %% Calculate new offset
            NewOffset =
                case OffsetsAcc of
                    [] -> PairCount;
                    [LastOffset | _] -> LastOffset + PairCount
                end,

            %% Extract keys and values
            {MapKeys, MapValues} = lists:unzip(Pairs),

            {[NewOffset | OffsetsAcc], KeysAcc ++ MapKeys, ValuesAcc ++ MapValues}
        end,
        {[], [], []},
        Maps
    ),
    {lists:reverse(Offsets), Keys, Values}.

%%%===================================================================
%%% Column Decoding
%%%===================================================================

%% @doc Decode a map column.
%%
%% The binary data for a map column consists of:
%% 1. Offsets column (UInt64): cumulative pair counts
%% 2. Keys column: flattened keys
%% 3. Values column: flattened values
-spec decode_map_column(
    binary(),
    clickhouse_erl_types_composite:column_type(),
    clickhouse_erl_types_composite:column_type(),
    non_neg_integer()
) ->
    {ok, [map()], binary()} | {error, term()}.
decode_map_column(Binary, KeyType, ValueType, RowCount) ->
    %% Decode offsets column
    case clickhouse_erl_types_composite:decode_offsets(Binary, RowCount) of
        {ok, Offsets, RestAfterOffsets} ->
            %% Calculate total pair count from last offset
            TotalPairs =
                case Offsets of
                    [] -> 0;
                    _ -> lists:last(Offsets)
                end,

            %% Decode keys column
            case decode_column(RestAfterOffsets, KeyType, TotalPairs) of
                {ok, FlattenedKeys, RestAfterKeys} ->
                    %% Decode values column
                    case decode_column(RestAfterKeys, ValueType, TotalPairs) of
                        {ok, FlattenedValues, Rest} ->
                            %% Reconstruct maps using offset differences
                            Maps = reconstruct_maps(Offsets, FlattenedKeys, FlattenedValues),
                            {ok, Maps, Rest};
                        Error ->
                            Error
                    end;
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

%% @doc Decode a column using the data block decoder.
-spec decode_column(
    binary(), clickhouse_erl_types_composite:column_type(), non_neg_integer()
) ->
    {ok, [term()], binary()} | {error, term()}.
decode_column(Binary, ColumnType, ElementCount) ->
    %% Convert type to binary string for data block decoder
    TypeStr = clickhouse_erl_types_composite:type_to_binary(ColumnType),
    clickhouse_erl_protocol_data_block:decode_column_data(TypeStr, ElementCount, Binary).

%% @doc Reconstruct maps from offsets, keys, and values.
%%
%% Example: Offsets=[2, 3], Keys=[a,b,c], Values=[1,2,3] -> [#{a=>1, b=>2}, #{c=>3}]
-spec reconstruct_maps([non_neg_integer()], [term()], [term()]) -> [map()].
reconstruct_maps(Offsets, FlattenedKeys, FlattenedValues) ->
    reconstruct_maps(Offsets, FlattenedKeys, FlattenedValues, 0, []).

reconstruct_maps([], _Keys, _Values, _PrevOffset, Acc) ->
    lists:reverse(Acc);
reconstruct_maps([Offset | RestOffsets], Keys, Values, PrevOffset, Acc) ->
    %% Calculate how many pairs in this map
    Count = Offset - PrevOffset,
    %% Extract keys and values for this map
    {MapKeys, RestKeys} = lists:split(Count, Keys),
    {MapValues, RestValues} = lists:split(Count, Values),
    %% Create map from keys and values
    Map = maps:from_list(lists:zip(MapKeys, MapValues)),
    reconstruct_maps(RestOffsets, RestKeys, RestValues, Offset, [Map | Acc]).
