-module(prop_clickhouse_erl_types_nullable).

-include_lib("proper/include/proper.hrl").

-import(generators, [
    int8_gen/0,
    uint16_gen/0,
    uint32_gen/0,
    float64_gen/0,
    binary_string_gen/0,
    normal_float64_gen/0
]).

-export([
    prop_nullable_int8_roundtrip/0,
    prop_nullable_uint16_roundtrip/0,
    prop_nullable_uint32_roundtrip/0,
    prop_nullable_float64_roundtrip/0,
    prop_nullable_string_roundtrip/0,
    prop_nullable_mask_consistency/0
]).

%%%===================================================================
%%% Property Tests
%%%===================================================================

%% @doc Property 4: Nullable round trip consistency
%%
%% For all nullable types, encoding values and decoding them must preserve
%% null/non-null distinction.
%%
%% Validates Requirements: 4.1, 4.2

prop_nullable_int8_roundtrip() ->
    prop_nullable_roundtrip(int8, int8_gen()).

prop_nullable_uint16_roundtrip() ->
    prop_nullable_roundtrip(uint16, uint16_gen()).

prop_nullable_uint32_roundtrip() ->
    prop_nullable_roundtrip(uint32, uint32_gen()).

prop_nullable_float64_roundtrip() ->
    prop_nullable_roundtrip(float64, normal_float64_gen()).

prop_nullable_string_roundtrip() ->
    prop_nullable_roundtrip(string, binary_string_gen()).

%% @doc Property 8: Nullable mask consistency
%%
%% Null mask and values column must have same row count.
%%
%% Validates Requirements: 4.6, 4.8

prop_nullable_mask_consistency() ->
    prop_nullable_mask_consistency(int8, int8_gen()).

%%%===================================================================
%%% Property Definitions
%%%===================================================================

%% @doc Property: Nullable round trip consistency
%%
%% For any list of nullable values, encoding and then decoding should
%% produce the original values.
prop_nullable_roundtrip(InnerType, InnerGen) ->
    ?FORALL(
        NullableValues,
        list(nullable_gen(InnerGen)),
        begin
            {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(
                NullableValues, InnerType
            ),
            {ok, Decoded, <<>>} = clickhouse_erl_types_nullable:decode_nullable_column(
                Encoded, InnerType, length(NullableValues)
            ),
            equals_with_nan_handling(NullableValues, Decoded)
        end
    ).

%% @doc Property: Nullable mask consistency
%%
%% The null mask and values column must have the same row count.
prop_nullable_mask_consistency(InnerType, InnerGen) ->
    ?FORALL(
        NullableValues,
        list(nullable_gen(InnerGen)),
        begin
            {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(
                NullableValues, InnerType
            ),
            RowCount = length(NullableValues),

            %% Decode null mask
            <<MaskBin:RowCount/binary, RestAfterMask/binary>> = Encoded,
            MaskCount = byte_size(MaskBin),

            %% Decode values column
            TypeStr = type_to_binary(InnerType),
            {ok, Values, _} = clickhouse_erl_protocol_data_block:decode_column_data(
                TypeStr, RowCount, RestAfterMask
            ),
            ValuesCount = length(Values),

            %% Both must have same count
            MaskCount =:= ValuesCount andalso MaskCount =:= RowCount
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generate nullable values
nullable_gen(InnerGen) ->
    oneof([
        {null},
        ?LET(V, InnerGen, {value, V})
    ]).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Compare values with special handling for NaN and infinity
%%
%% NaN is not equal to itself in Erlang, so we need special handling.
equals_with_nan_handling(Expected, Actual) when is_list(Expected), is_list(Actual) ->
    length(Expected) =:= length(Actual) andalso
        lists:all(
            fun({E, A}) -> equals_with_nan_handling(E, A) end,
            lists:zip(Expected, Actual)
        );
equals_with_nan_handling({null}, {null}) ->
    true;
equals_with_nan_handling({value, E}, {value, A}) ->
    equals_with_nan_handling(E, A);
equals_with_nan_handling(Expected, Actual) when is_float(Expected), is_float(Actual) ->
    case {is_nan(Expected), is_nan(Actual)} of
        {true, true} -> true;
        {false, false} -> Expected =:= Actual;
        _ -> false
    end;
equals_with_nan_handling(Expected, Actual) ->
    Expected =:= Actual.

%% @doc Check if a float is NaN
is_nan(F) when is_float(F) ->
    F /= F;
is_nan(_) ->
    false.

%% @doc Convert parsed type back to binary string for decoding.
type_to_binary(uint8) -> <<"UInt8">>;
type_to_binary(uint16) -> <<"UInt16">>;
type_to_binary(uint32) -> <<"UInt32">>;
type_to_binary(uint64) -> <<"UInt64">>;
type_to_binary(int8) -> <<"Int8">>;
type_to_binary(int16) -> <<"Int16">>;
type_to_binary(int32) -> <<"Int32">>;
type_to_binary(int64) -> <<"Int64">>;
type_to_binary(float32) -> <<"Float32">>;
type_to_binary(float64) -> <<"Float64">>;
type_to_binary(string) -> <<"String">>;
type_to_binary(Type) -> atom_to_binary(Type).
