-module(prop_clickhouse_erl_types_map).

-include_lib("proper/include/proper.hrl").

-import(generators, [
    int8_gen/0,
    int32_gen/0,
    int64_gen/0,
    uint16_gen/0,
    uint32_gen/0,
    uint64_gen/0,
    float64_gen/0,
    binary_string_gen/0,
    normal_float64_gen/0,
    map_gen/2
]).

-export([
    prop_map_string_int64_roundtrip/0,
    prop_map_int32_uint64_roundtrip/0,
    prop_map_string_float64_roundtrip/0,
    prop_map_string_array_int32_roundtrip/0
]).

%%%===================================================================
%%% Property Tests
%%%===================================================================

%% @doc Property 3: Map round trip consistency
%%
%% For all map types, encoding values and decoding them must produce
%% the original values.
%%
%% Validates Requirements: 3.1, 3.2

prop_map_string_int64_roundtrip() ->
    prop_map_roundtrip(string, binary_string_gen(), int64, int64_gen()).

prop_map_int32_uint64_roundtrip() ->
    prop_map_roundtrip(int32, int32_gen(), uint64, uint64_gen()).

prop_map_string_float64_roundtrip() ->
    prop_map_roundtrip(string, binary_string_gen(), float64, normal_float64_gen()).

%% Maps with complex value types
prop_map_string_array_int32_roundtrip() ->
    prop_map_with_array_values_roundtrip(string, binary_string_gen(), int32, int32_gen()).

%% @doc Property: Map round trip consistency
%%
%% For any list of maps, encoding and then decoding should produce
%% the original maps.
prop_map_roundtrip(KeyType, KeyGen, ValueType, ValueGen) ->
    ?FORALL(
        Maps,
        list(map_gen(KeyGen, ValueGen)),
        begin
            {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(
                Maps, KeyType, ValueType
            ),
            {ok, Decoded, <<>>} = clickhouse_erl_types_map:decode_map_column(
                Encoded, KeyType, ValueType, length(Maps)
            ),
            equals_with_nan_handling(Maps, Decoded)
        end
    ).

%% @doc Property: Map with array values round trip consistency
%%
%% For maps with array values, encoding and then decoding should produce
%% the original maps.
prop_map_with_array_values_roundtrip(KeyType, KeyGen, ElemType, ElemGen) ->
    ?FORALL(
        Maps,
        list(map_gen(KeyGen, list(ElemGen))),
        begin
            {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(
                Maps, KeyType, {array, ElemType}
            ),
            {ok, Decoded, <<>>} = clickhouse_erl_types_map:decode_map_column(
                Encoded, KeyType, {array, ElemType}, length(Maps)
            ),
            equals_with_nan_handling(Maps, Decoded)
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
equals_with_nan_handling(Expected, Actual) when is_map(Expected), is_map(Actual) ->
    maps:size(Expected) =:= maps:size(Actual) andalso
        lists:all(
            fun(Key) ->
                case {maps:find(Key, Expected), maps:find(Key, Actual)} of
                    {{ok, ExpVal}, {ok, ActVal}} ->
                        equals_with_nan_handling(ExpVal, ActVal);
                    _ ->
                        false
                end
            end,
            maps:keys(Expected)
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
