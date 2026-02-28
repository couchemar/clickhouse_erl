%% @doc Property-based tests for composite type composition.
%%
%% Tests Property 10: Type composition validity
%% Validates that nested types maintain correctness at all levels.
-module(prop_clickhouse_erl_types_composition).

-include_lib("proper/include/proper.hrl").

-import(generators, [
    binary_string_gen/0,
    int64_gen/0,
    map_gen/2
]).

-export([
    prop_array_nullable_string_roundtrip/0,
    prop_nullable_array_int64_roundtrip/0,
    prop_array_tuple_roundtrip/0,
    prop_map_string_array_roundtrip/0
]).

%%%===================================================================
%%% Property Definitions
%%%===================================================================

%% @doc Property: Array(Nullable(String)) round trip consistency
%%
%% **Validates: Requirements 6.1**
prop_array_nullable_string_roundtrip() ->
    ?FORALL(
        Data,
        array_nullable_string_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(
                Data,
                {nullable, string}
            ),
            {ok, Decoded, <<>>} = clickhouse_erl_types_array:decode_array_column(
                Encoded,
                {nullable, string},
                length(Data)
            ),
            Data =:= Decoded
        end
    ).

%% @doc Property: Nullable(Array(Int64)) round trip consistency
%%
%% **Validates: Requirements 6.2**
prop_nullable_array_int64_roundtrip() ->
    ?FORALL(
        Data,
        nullable_array_int64_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_nullable:encode_nullable_column(
                Data,
                {array, int64}
            ),
            {ok, Decoded, <<>>} = clickhouse_erl_types_nullable:decode_nullable_column(
                Encoded,
                {array, int64},
                length(Data)
            ),
            Data =:= Decoded
        end
    ).

%% @doc Property: Array(Tuple(String, Int64)) round trip consistency
%%
%% **Validates: Requirements 6.3**
prop_array_tuple_roundtrip() ->
    ?FORALL(
        Data,
        array_tuple_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_array:encode_array_column(
                Data,
                {tuple, [string, int64]}
            ),
            {ok, Decoded, <<>>} = clickhouse_erl_types_array:decode_array_column(
                Encoded,
                {tuple, [string, int64]},
                length(Data)
            ),
            Data =:= Decoded
        end
    ).

%% @doc Property: Map(String, Array(Int64)) round trip consistency
%%
%% **Validates: Requirements 6.4**
prop_map_string_array_roundtrip() ->
    ?FORALL(
        Data,
        map_string_array_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_map:encode_map_column(
                Data,
                string,
                {array, int64}
            ),
            {ok, Decoded, <<>>} = clickhouse_erl_types_map:decode_map_column(
                Encoded,
                string,
                {array, int64},
                length(Data)
            ),
            Data =:= Decoded
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generator for Array(Nullable(String))
array_nullable_string_gen() ->
    ?LET(
        NumRows,
        range(0, 10),
        vector(NumRows, list(nullable_string_gen()))
    ).

%% @doc Generator for Nullable(String)
nullable_string_gen() ->
    oneof([
        {null},
        ?LET(S, binary_string_gen(), {value, S})
    ]).

%% @doc Generator for Nullable(Array(Int64))
nullable_array_int64_gen() ->
    ?LET(
        NumRows,
        range(0, 10),
        vector(NumRows, nullable_array_gen())
    ).

%% @doc Generator for nullable array
nullable_array_gen() ->
    oneof([
        {null},
        ?LET(Arr, list(int64_gen()), {value, Arr})
    ]).

%% @doc Generator for Array(Tuple(String, Int64))
array_tuple_gen() ->
    ?LET(
        NumRows,
        range(0, 10),
        vector(NumRows, list(tuple_string_int64_gen()))
    ).

%% @doc Generator for Tuple(String, Int64)
tuple_string_int64_gen() ->
    ?LET(
        {S, I},
        {binary_string_gen(), int64_gen()},
        {S, I}
    ).

%% @doc Generator for Map(String, Array(Int64))
map_string_array_gen() ->
    ?LET(
        NumRows,
        range(0, 10),
        vector(NumRows, map_gen(binary_string_gen(), list(int64_gen())))
    ).
