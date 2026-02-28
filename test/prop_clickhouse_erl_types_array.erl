-module(prop_clickhouse_erl_types_array).

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
    prop_array_int8_roundtrip/0,
    prop_array_uint16_roundtrip/0,
    prop_array_uint32_roundtrip/0,
    prop_array_float64_roundtrip/0,
    prop_array_string_roundtrip/0,
    prop_nested_array_int8_roundtrip/0
]).

%%%===================================================================
%%% Property Definitions
%%%===================================================================

%% @doc Property 2: Array round trip consistency
%%
%% For all array types, encoding values and decoding them must produce
%% the original values.
%%
%% Validates Requirements: 2.1, 2.2

prop_array_int8_roundtrip() ->
    prop_array_roundtrip(int8, int8_gen()).

prop_array_uint16_roundtrip() ->
    prop_array_roundtrip(uint16, uint16_gen()).

prop_array_uint32_roundtrip() ->
    prop_array_roundtrip(uint32, uint32_gen()).

prop_array_float64_roundtrip() ->
    prop_array_roundtrip(float64, normal_float64_gen()).

prop_array_string_roundtrip() ->
    prop_array_roundtrip(string, binary_string_gen()).

prop_nested_array_int8_roundtrip() ->
    prop_nested_array_roundtrip(int8, int8_gen()).

%% @doc Property: Array round trip consistency
%%
%% For any list of arrays, encoding and then decoding should produce
%% the original arrays.
prop_array_roundtrip(ElementType, ElementGen) ->
    ?FORALL(
        Arrays,
        list(list(ElementGen)),
        begin
            {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(Arrays, ElementType),
            {ok, Decoded, <<>>} = clickhouse_erl_types_array:decode_array_column(
                Encoded, ElementType, length(Arrays)
            ),
            equals_with_nan_handling(Arrays, Decoded)
        end
    ).

%% @doc Property: Nested array round trip consistency
%%
%% For any list of nested arrays (Array(Array(T))), encoding and then
%% decoding should produce the original arrays.
prop_nested_array_roundtrip(ElementType, ElementGen) ->
    ?FORALL(
        NestedArrays,
        list(list(list(ElementGen))),
        begin
            {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(
                NestedArrays, {array, ElementType}
            ),
            {ok, Decoded, <<>>} = clickhouse_erl_types_array:decode_array_column(
                Encoded, {array, ElementType}, length(NestedArrays)
            ),
            equals_with_nan_handling(NestedArrays, Decoded)
        end
    ).

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
