%% @doc ClickHouse composite types utility functions.
%%
%% This module provides common utility functions for handling composite types
%% (Tuple, Array, Map, Nullable, LowCardinality). These utilities are shared
%% across all composite type modules to reduce code duplication.
%%
%% == Functionality ==
%%
%% === Offset Operations ===
%% Encode and decode UInt64 offset arrays used by Array and Map types for
%% efficient variable-length data storage.
%%
%% === Type Parsing ===
%% Parse ClickHouse type strings into structured Erlang terms, handling:
%% - Primitive types (UInt8, String, DateTime, etc.)
%% - Composite types (Array, Tuple, Map, Nullable, LowCardinality)
%% - Nested structures (Array(Tuple(String, Int64)))
%% - Type parameters with proper parenthesis matching
%%
%% === Type Validation ===
%% Validate that Erlang values match expected ClickHouse type structures,
%% providing detailed error messages for mismatches.
%%
%% == Usage Examples ==
%%
%% === Offset Encoding/Decoding ===
%% ```
%% % Encode offsets for array: [[1,2,3], [4,5], [6]]
%% Offsets = [3, 5, 6],  % Cumulative counts
%% Binary = clickhouse_erl_types_composite:encode_offsets(Offsets).
%%
%% % Decode offsets
%% {ok, DecodedOffsets, Rest} = clickhouse_erl_types_composite:decode_offsets(Binary, 3).
%% % Returns: {ok, [3, 5, 6], <<>>}
%% '''
%%
%% === Type Parsing ===
%% ```
%% % Parse primitive type
%% Type1 = clickhouse_erl_types_composite:parse_column_type(<<"UInt64">>).
%% % Returns: uint64
%%
%% % Parse array type
%% Type2 = clickhouse_erl_types_composite:parse_column_type(<<"Array(String)">>).
%% % Returns: {array, string}
%%
%% % Parse nested composite type
%% Type3 = clickhouse_erl_types_composite:parse_column_type(
%%     <<"Array(Tuple(String, Int64))">>
%% ).
%% % Returns: {array, {tuple, [string, int64]}}
%%
%% % Parse complex nested structure
%% Type4 = clickhouse_erl_types_composite:parse_column_type(
%%     <<"Map(String, Array(Nullable(Int64)))">>
%% ).
%% % Returns: {map, string, {array, {nullable, int64}}}
%% '''
%%
%% === Type Parameter Parsing ===
%% ```
%% % Parse simple parameters
%% Params1 = clickhouse_erl_types_composite:parse_type_params(<<"String, Int64">>).
%% % Returns: [<<"String">>, <<"Int64">>]
%%
%% % Parse nested parameters (respects parentheses)
%% Params2 = clickhouse_erl_types_composite:parse_type_params(
%%     <<"String, Array(Int64), Tuple(A, B)">>
%% ).
%% % Returns: [<<"String">>, <<"Array(Int64)">>, <<"Tuple(A, B)">>]
%% '''
%%
%% === Type Validation ===
%% ```
%% % Validate primitive type
%% ok = clickhouse_erl_types_composite:validate_type_compatibility(uint8, 42).
%% {error, _} = clickhouse_erl_types_composite:validate_type_compatibility(uint8, 256).
%%
%% % Validate array type
%% ok = clickhouse_erl_types_composite:validate_type_compatibility(
%%     {array, int64}, [1, 2, 3]
%% ).
%%
%% % Validate tuple type
%% ok = clickhouse_erl_types_composite:validate_type_compatibility(
%%     {tuple, [string, int64]}, {<<"Alice">>, 25}
%% ).
%%
%% % Validate nullable type
%% ok = clickhouse_erl_types_composite:validate_type_compatibility(
%%     {nullable, string}, {null}
%% ).
%% ok = clickhouse_erl_types_composite:validate_type_compatibility(
%%     {nullable, string}, {value, <<"foo">>}
%% ).
%% '''
%%
%% @see clickhouse_erl_types_tuple
%% @see clickhouse_erl_types_array
%% @see clickhouse_erl_types_map
%% @see clickhouse_erl_types_nullable
%% @see clickhouse_erl_types_low_cardinality
-module(clickhouse_erl_types_composite).

-include_lib("kernel/include/logger.hrl").

%% Public API
-export([
    % Offset operations
    encode_offsets/1,
    decode_offsets/2,
    % Type parsing (Phase 1.2, 1.3)
    parse_type_params/1,
    parse_column_type/1,
    % Type validation
    validate_type_compatibility/2
]).

-ignore_xref([validate_type_compatibility/2]).

%% Type definitions
-type column_type() ::
    primitive_type()
    | composite_type().

-type primitive_type() ::
    uint8
    | uint16
    | uint32
    | uint64
    | int8
    | int16
    | int32
    | int64
    | float32
    | float64
    | string
    | date
    | date32
    | datetime
    | datetime64
    | uuid
    | ipv4
    | ipv6.

-type composite_type() ::
    {array, column_type()}
    | {tuple, [column_type()]}
    | {map, column_type(), column_type()}
    | {nullable, column_type()}
    | {low_cardinality, column_type()}.

-export_type([column_type/0, primitive_type/0, composite_type/0]).

%%%===================================================================
%%% Offset Operations
%%%===================================================================

%% @doc Encode a list of offsets as UInt64 (little-endian).
%%
%% Used for Array and Map columns to store element counts.
%% Returns a binary of encoded offsets.
-spec encode_offsets([non_neg_integer()]) -> binary().
encode_offsets(Offsets) ->
    <<<<O:64/little-unsigned-integer>> || O <- Offsets>>.

%% @doc Decode N offsets (UInt64 little-endian).
%%
%% Returns {ok, Offsets, Rest} or {error, Reason}.
-spec decode_offsets(binary(), non_neg_integer()) ->
    {ok, [non_neg_integer()], binary()} | {error, term()}.
decode_offsets(Binary, Count) ->
    ExpectedBytes = Count * 8,
    case byte_size(Binary) >= ExpectedBytes of
        true ->
            <<OffsetsBin:ExpectedBytes/binary, Rest/binary>> = Binary,
            Offsets = [O || <<O:64/little-unsigned-integer>> <= OffsetsBin],
            {ok, Offsets, Rest};
        false ->
            {error,
                {truncated_data, #{
                    expected_bytes => ExpectedBytes,
                    actual_bytes => byte_size(Binary),
                    type => offsets
                }}}
    end.

%%%===================================================================
%%% Type Parsing
%%%===================================================================

%% @doc Parse comma-separated type parameters, respecting nested parentheses.
%%
%% Input: "String, Array(Int64), Tuple(A, B)"
%% Output: ["String", "Array(Int64)", "Tuple(A, B)"]
-spec parse_type_params(binary() | string()) -> [binary()].
parse_type_params(Params) when is_list(Params) ->
    parse_type_params(list_to_binary(Params));
parse_type_params(Params) when is_binary(Params) ->
    parse_type_params(Params, <<>>, [], 0).

parse_type_params(<<>>, Buffer, Acc, 0) ->
    case string:trim(Buffer) of
        <<>> -> lists:reverse(Acc);
        Trimmed -> lists:reverse([Trimmed | Acc])
    end;
parse_type_params(<<$(, Rest/binary>>, Buffer, Acc, Depth) ->
    parse_type_params(Rest, <<Buffer/binary, $(>>, Acc, Depth + 1);
parse_type_params(<<$), Rest/binary>>, Buffer, Acc, Depth) when Depth > 0 ->
    parse_type_params(Rest, <<Buffer/binary, $)>>, Acc, Depth - 1);
parse_type_params(<<$,, Rest/binary>>, Buffer, Acc, 0) ->
    Trimmed = string:trim(Buffer),
    parse_type_params(Rest, <<>>, [Trimmed | Acc], 0);
parse_type_params(<<Char, Rest/binary>>, Buffer, Acc, Depth) ->
    parse_type_params(Rest, <<Buffer/binary, Char>>, Acc, Depth).

%% @doc Parse a column type string into a structured type definition.
%%
%% Examples:
%% "UInt8" -> uint8
%% "Array(String)" -> {array, string}
%% "Tuple(Int64, String)" -> {tuple, [int64, string]}
%% "Map(String, UInt32)" -> {map, string, uint32}
%% "Nullable(String)" -> {nullable, string}
%% "LowCardinality(String)" -> {low_cardinality, string}
-spec parse_column_type(binary() | string()) -> column_type().
parse_column_type(Type) when is_list(Type) ->
    parse_column_type(list_to_binary(Type));
parse_column_type(Type) when is_binary(Type) ->
    case Type of
        <<"UInt8">> -> uint8;
        <<"UInt16">> -> uint16;
        <<"UInt32">> -> uint32;
        <<"UInt64">> -> uint64;
        <<"Int8">> -> int8;
        <<"Int16">> -> int16;
        <<"Int32">> -> int32;
        <<"Int64">> -> int64;
        <<"Float32">> -> float32;
        <<"Float64">> -> float64;
        <<"String">> -> string;
        <<"Date">> -> date;
        <<"Date32">> -> date32;
        <<"DateTime">> -> datetime;
        <<"DateTime64", _/binary>> -> datetime64;
        <<"UUID">> -> uuid;
        <<"IPv4">> -> ipv4;
        <<"IPv6">> -> ipv6;
        _ -> parse_composite_type(Type)
    end.

parse_composite_type(Type) ->
    case parse_type_name_and_params(Type) of
        {<<"Array">>, [InnerType]} ->
            {array, parse_column_type(InnerType)};
        {<<"Tuple">>, Elements} ->
            {tuple, [parse_column_type(E) || E <- Elements]};
        {<<"Map">>, [KeyType, ValueType]} ->
            {map, parse_column_type(KeyType), parse_column_type(ValueType)};
        {<<"Nullable">>, [InnerType]} ->
            {nullable, parse_column_type(InnerType)};
        {<<"LowCardinality">>, [InnerType]} ->
            {low_cardinality, parse_column_type(InnerType)};
        {Unknown, _} ->
            error({unknown_type, Unknown})
    end.

parse_type_name_and_params(Type) ->
    case binary:split(Type, <<"(">>) of
        [Name, Rest] ->
            %% Remove trailing ')'
            ParamsContent = binary:part(Rest, 0, byte_size(Rest) - 1),
            Params = parse_type_params(ParamsContent),
            {string:trim(Name), Params};
        [Name] ->
            {string:trim(Name), []}
    end.

%%%===================================================================
%%% Type Validation
%%%===================================================================

%% @doc Validate that a value matches the expected type structure.
%%
%% Returns ok if the value is compatible with the type, or {error, Reason}
%% with a descriptive error message if there's a mismatch.
-spec validate_type_compatibility(column_type(), term()) -> ok | {error, term()}.

%% Primitive types
validate_type_compatibility(uint8, V) when is_integer(V), V >= 0, V =< 255 ->
    ok;
validate_type_compatibility(uint8, V) ->
    {error, {type_mismatch, #{expected => uint8, actual => V}}};
validate_type_compatibility(uint16, V) when is_integer(V), V >= 0, V =< 65535 ->
    ok;
validate_type_compatibility(uint16, V) ->
    {error, {type_mismatch, #{expected => uint16, actual => V}}};
validate_type_compatibility(uint32, V) when is_integer(V), V >= 0, V =< 4294967295 ->
    ok;
validate_type_compatibility(uint32, V) ->
    {error, {type_mismatch, #{expected => uint32, actual => V}}};
validate_type_compatibility(uint64, V) when is_integer(V), V >= 0 ->
    ok;
validate_type_compatibility(uint64, V) ->
    {error, {type_mismatch, #{expected => uint64, actual => V}}};
validate_type_compatibility(int8, V) when is_integer(V), V >= -128, V =< 127 ->
    ok;
validate_type_compatibility(int8, V) ->
    {error, {type_mismatch, #{expected => int8, actual => V}}};
validate_type_compatibility(int16, V) when is_integer(V), V >= -32768, V =< 32767 ->
    ok;
validate_type_compatibility(int16, V) ->
    {error, {type_mismatch, #{expected => int16, actual => V}}};
validate_type_compatibility(int32, V) when is_integer(V), V >= -2147483648, V =< 2147483647 ->
    ok;
validate_type_compatibility(int32, V) ->
    {error, {type_mismatch, #{expected => int32, actual => V}}};
validate_type_compatibility(int64, V) when is_integer(V) ->
    ok;
validate_type_compatibility(int64, V) ->
    {error, {type_mismatch, #{expected => int64, actual => V}}};
validate_type_compatibility(float32, V) when is_float(V) ->
    ok;
validate_type_compatibility(float32, V) when is_integer(V) ->
    ok;
validate_type_compatibility(float32, V) ->
    {error, {type_mismatch, #{expected => float32, actual => V}}};
validate_type_compatibility(float64, V) when is_float(V) ->
    ok;
validate_type_compatibility(float64, V) when is_integer(V) ->
    ok;
validate_type_compatibility(float64, V) ->
    {error, {type_mismatch, #{expected => float64, actual => V}}};
validate_type_compatibility(string, V) when is_binary(V) ->
    ok;
validate_type_compatibility(string, V) ->
    {error, {type_mismatch, #{expected => string, actual => V}}};
validate_type_compatibility(date, {Y, M, D}) when
    is_integer(Y), is_integer(M), is_integer(D)
->
    ok;
validate_type_compatibility(date, V) ->
    {error, {type_mismatch, #{expected => date, actual => V}}};
validate_type_compatibility(datetime, {{Y, M, D}, {H, Mi, S}}) when
    is_integer(Y),
    is_integer(M),
    is_integer(D),
    is_integer(H),
    is_integer(Mi),
    is_integer(S)
->
    ok;
validate_type_compatibility(datetime, V) ->
    {error, {type_mismatch, #{expected => datetime, actual => V}}};
%% Array type
validate_type_compatibility({array, ElemType}, V) when is_list(V) ->
    validate_array_elements(ElemType, V, 0);
validate_type_compatibility({array, _}, V) ->
    {error, {type_mismatch, #{expected => array, actual => V}}};
%% Tuple type
validate_type_compatibility({tuple, ElemTypes}, V) when is_tuple(V) ->
    case tuple_size(V) =:= length(ElemTypes) of
        true ->
            validate_tuple_elements(ElemTypes, tuple_to_list(V), 0);
        false ->
            {error,
                {tuple_size_mismatch, #{
                    expected => length(ElemTypes),
                    actual => tuple_size(V)
                }}}
    end;
validate_type_compatibility({tuple, _}, V) ->
    {error, {type_mismatch, #{expected => tuple, actual => V}}};
%% Map type
validate_type_compatibility({map, KeyType, ValueType}, V) when is_map(V) ->
    validate_map_entries(KeyType, ValueType, maps:to_list(V), 0);
validate_type_compatibility({map, _, _}, V) ->
    {error, {type_mismatch, #{expected => map, actual => V}}};
%% Nullable type
validate_type_compatibility({nullable, _InnerType}, {null}) ->
    ok;
validate_type_compatibility({nullable, InnerType}, {value, V}) ->
    validate_type_compatibility(InnerType, V);
validate_type_compatibility({nullable, _}, V) ->
    {error, {type_mismatch, #{expected => nullable, actual => V}}};
%% LowCardinality type (transparent - validate inner type)
validate_type_compatibility({low_cardinality, InnerType}, V) ->
    validate_type_compatibility(InnerType, V);
%% Unknown types
validate_type_compatibility(Type, V) ->
    {error, {unknown_type, #{type => Type, value => V}}}.

%% Helper: Validate array elements
validate_array_elements(_ElemType, [], _Index) ->
    ok;
validate_array_elements(ElemType, [Elem | Rest], Index) ->
    case validate_type_compatibility(ElemType, Elem) of
        ok ->
            validate_array_elements(ElemType, Rest, Index + 1);
        {error, Reason} ->
            {error, {array_element_error, Index, Reason}}
    end.

%% Helper: Validate tuple elements
validate_tuple_elements([], [], _Index) ->
    ok;
validate_tuple_elements([Type | RestTypes], [Elem | RestElems], Index) ->
    case validate_type_compatibility(Type, Elem) of
        ok ->
            validate_tuple_elements(RestTypes, RestElems, Index + 1);
        {error, Reason} ->
            {error, {tuple_element_error, Index, Reason}}
    end.

%% Helper: Validate map entries
validate_map_entries(_KeyType, _ValueType, [], _Index) ->
    ok;
validate_map_entries(KeyType, ValueType, [{K, V} | Rest], Index) ->
    case validate_type_compatibility(KeyType, K) of
        ok ->
            case validate_type_compatibility(ValueType, V) of
                ok ->
                    validate_map_entries(KeyType, ValueType, Rest, Index + 1);
                {error, Reason} ->
                    {error, {map_value_error, Index, Reason}}
            end;
        {error, Reason} ->
            {error, {map_key_error, Index, Reason}}
    end.
