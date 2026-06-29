%% @doc ClickHouse Nullable type support.
%%
%% This module implements support for the ClickHouse Nullable type, which wraps
%% any other type to allow NULL values. Nullable uses a null mask for efficient
%% null checking without parsing values.
%%
%% == Erlang Data Structure Mapping ==
%%
%% Nullable values are represented as tagged tuples:
%% ```
%% NULL value: {null}
%% Non-NULL value: {value, ActualValue}
%% '''
%%
%% Examples:
%% ```
%% Nullable(Int64):
%%   {null}           % NULL
%%   {value, 42}      % Non-NULL integer
%%
%% Nullable(String):
%%   {null}           % NULL
%%   {value, <<"foo">>}  % Non-NULL string
%%
%% Nullable(Array(Int64)):
%%   {null}           % NULL
%%   {value, [1,2,3]} % Non-NULL array
%% '''
%%
%% == Usage Examples ==
%%
%% === Parsing Nullable Types ===
%% ```
%% % Nullable primitive
%% Type1 = clickhouse_erl_types_nullable:parse_nullable_type(<<"Nullable(String)">>).
%% % Returns: string
%%
%% % Nullable composite
%% Type2 = clickhouse_erl_types_nullable:parse_nullable_type(<<"Nullable(Array(Int64))">>).
%% % Returns: {array, int64}
%% '''
%%
%% === Encoding Nullable Values ===
%% ```
%% Data = [{value, 10}, {null}, {value, 20}, {null}],
%% {ok, Binary} = clickhouse_erl_types_nullable:encode_nullable_column(Data, int64).
%% '''
%%
%% === Decoding Nullable Values ===
%% ```
%% {ok, Values, Rest} = clickhouse_erl_types_nullable:decode_nullable_column(Binary, int64, 4).
%% % Returns: {ok, [{value, 10}, {null}, {value, 20}, {null}], <<>>}
%% '''
%%
%% == Protocol Details ==
%%
%% Nullable columns use null mask encoding:
%% 1. Null mask (UInt8): 1 = null, 0 = not null
%% 2. Values column: All values (with placeholders for nulls)
%%
%% Both columns have the same row count. Placeholders (default values) are used
%% for null positions to maintain column alignment.
%%
%% Example: [{value, 10}, {null}, {value, 20}]
%% - Null mask: [0, 1, 0]
%% - Values: [10, 0, 20] (0 is placeholder for null)
%%
%% @see clickhouse_erl_types_composite
-module(clickhouse_erl_types_nullable).

-include_lib("kernel/include/logger.hrl").

%% Public API
-export([
    % Type parsing
    parse_nullable_type/1,
    % Column encoding/decoding
    encode_nullable_column/2,
    decode_nullable_column/3
]).

%% Type definitions
-type nullable_value() :: {null} | {value, term()}.
-type nullable_error() ::
    {null_mask_size_mismatch, non_neg_integer(), non_neg_integer()}
    | {nullable_value_error, non_neg_integer(), term()}.

-export_type([nullable_value/0, nullable_error/0]).

%%%===================================================================
%%% Type Parsing
%%%===================================================================

%% @doc Parse a Nullable type definition string.
%%
%% Examples:
%% "Nullable(String)" -> string
%% "Nullable(Int64)" -> int64
%% "Nullable(Array(String))" -> {array, string}
-spec parse_nullable_type(binary() | string()) -> clickhouse_erl_types_composite:column_type().
parse_nullable_type(Type) when is_list(Type) ->
    parse_nullable_type(list_to_binary(Type));
parse_nullable_type(Type) when is_binary(Type) ->
    %% Remove "Nullable(" and closing ")"
    case binary:split(Type, <<"(">>) of
        [<<"Nullable">>, Rest] ->
            %% Extract inner type (remove trailing ")")
            InnerTypeStr = binary:part(Rest, 0, byte_size(Rest) - 1),
            %% Parse the inner type recursively
            clickhouse_erl_types_composite:parse_column_type(InnerTypeStr);
        _ ->
            error({invalid_nullable_type, Type})
    end.

%%%===================================================================
%%% Column Encoding
%%%===================================================================

%% @doc Encode a nullable column.
%%
%% Transforms a list of nullable values into:
%% 1. Null mask (UInt8): 1 = null, 0 = not null
%% 2. Values column: all values (with placeholders for nulls)
-spec encode_nullable_column([nullable_value()], clickhouse_erl_types_composite:column_type()) ->
    {ok, binary()} | {error, term()}.
encode_nullable_column(NullableValues, InnerType) ->
    %% Build null mask and extract values
    {NullMask, Values} = build_mask_and_values(NullableValues, InnerType),

    %% Encode null mask (UInt8)
    NullMaskEncoded = <<
        <<
            (case IsNull of
                true -> 1;
                false -> 0
            end):8
        >>
     || IsNull <- NullMask
    >>,

    %% Encode values column
    case clickhouse_erl_types_column:encode_column(InnerType, Values) of
        {ok, ValuesEncoded} ->
            {ok, iolist_to_binary([NullMaskEncoded, ValuesEncoded])};
        Error ->
            Error
    end.

%% @doc Build null mask and extract values from nullable values.
%%
%% For null values, use a placeholder (default value for the type).
-spec build_mask_and_values([nullable_value()], clickhouse_erl_types_composite:column_type()) ->
    {[boolean()], [term()]}.
build_mask_and_values(NullableValues, InnerType) ->
    Placeholder = get_placeholder_value(InnerType),
    {Mask, Values} = lists:foldl(
        fun
            ({null}, {MaskAcc, ValuesAcc}) ->
                {[true | MaskAcc], [Placeholder | ValuesAcc]};
            ({value, V}, {MaskAcc, ValuesAcc}) ->
                {[false | MaskAcc], [V | ValuesAcc]}
        end,
        {[], []},
        NullableValues
    ),
    {lists:reverse(Mask), lists:reverse(Values)}.

%% @doc Get a placeholder value for a given type.
-spec get_placeholder_value(clickhouse_erl_types_composite:column_type()) -> term().
get_placeholder_value(uint8) ->
    0;
get_placeholder_value(uint16) ->
    0;
get_placeholder_value(uint32) ->
    0;
get_placeholder_value(uint64) ->
    0;
get_placeholder_value(int8) ->
    0;
get_placeholder_value(int16) ->
    0;
get_placeholder_value(int32) ->
    0;
get_placeholder_value(int64) ->
    0;
get_placeholder_value(float32) ->
    0.0;
get_placeholder_value(float64) ->
    0.0;
get_placeholder_value(bool) ->
    false;
get_placeholder_value(string) ->
    <<>>;
get_placeholder_value(date) ->
    0;
get_placeholder_value(date32) ->
    0;
get_placeholder_value(datetime) ->
    0;
get_placeholder_value(datetime64) ->
    0;
get_placeholder_value({array, _}) ->
    [];
get_placeholder_value({tuple, ElementTypes}) ->
    list_to_tuple([get_placeholder_value(T) || T <- ElementTypes]);
get_placeholder_value({map, _, _}) ->
    #{};
get_placeholder_value(_) ->
    0.

%%%===================================================================
%%% Column Decoding
%%%===================================================================

%% @doc Decode a nullable column.
%%
%% The binary data for a nullable column consists of:
%% 1. Null mask (UInt8): 1 = null, 0 = not null
%% 2. Values column: all values (same row count as mask)
-spec decode_nullable_column(
    binary(), clickhouse_erl_types_composite:column_type(), non_neg_integer()
) ->
    {ok, [nullable_value()], binary()} | {error, term()}.
decode_nullable_column(Binary, InnerType, RowCount) ->
    %% Decode null mask (UInt8)
    case decode_null_mask(Binary, RowCount) of
        {ok, NullMask, RestAfterMask} ->
            %% Decode values column
            case decode_values_column(RestAfterMask, InnerType, RowCount) of
                {ok, Values, Rest} ->
                    %% Validate mask and values have same count
                    case length(NullMask) =:= length(Values) of
                        true ->
                            %% Combine mask and values into nullable values
                            NullableValues = combine_mask_and_values(NullMask, Values),
                            {ok, NullableValues, Rest};
                        false ->
                            {error, {null_mask_size_mismatch, length(NullMask), length(Values)}}
                    end;
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

%% @doc Decode the null mask (UInt8 array).
-spec decode_null_mask(binary(), non_neg_integer()) ->
    {ok, [boolean()], binary()} | {error, term()}.
decode_null_mask(Binary, RowCount) ->
    case byte_size(Binary) >= RowCount of
        true ->
            <<MaskBin:RowCount/binary, Rest/binary>> = Binary,
            Mask = [
                case B of
                    1 -> true;
                    0 -> false
                end
             || <<B:8>> <= MaskBin
            ],
            {ok, Mask, Rest};
        false ->
            {error,
                {truncated_data, #{
                    expected_bytes => RowCount,
                    actual_bytes => byte_size(Binary),
                    type => null_mask
                }}}
    end.

%% @doc Decode the values column.
-spec decode_values_column(
    binary(), clickhouse_erl_types_composite:column_type(), non_neg_integer()
) ->
    {ok, [term()], binary()} | {error, term()}.
decode_values_column(Binary, {low_cardinality, InnerType}, RowCount) ->
    %% LowCardinality in nested context: no state version prefix
    %% Call nested decoder directly instead of going through data block decoder
    clickhouse_erl_types_low_cardinality:decode_low_cardinality_column_nested(
        Binary,
        InnerType,
        RowCount
    );
decode_values_column(Binary, InnerType, RowCount) ->
    %% Convert type to binary string for data block decoder
    TypeStr = clickhouse_erl_types_composite:type_to_binary(InnerType),
    clickhouse_erl_protocol_data_block:decode_column_data(TypeStr, RowCount, Binary).

%% @doc Combine null mask and values into nullable values.
-spec combine_mask_and_values([boolean()], [term()]) -> [nullable_value()].
combine_mask_and_values(NullMask, Values) ->
    lists:zipwith(
        fun
            (true, _Value) -> {null};
            (false, Value) -> {value, Value}
        end,
        NullMask,
        Values
    ).
