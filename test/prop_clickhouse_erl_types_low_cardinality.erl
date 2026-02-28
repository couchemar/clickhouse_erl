-module(prop_clickhouse_erl_types_low_cardinality).

-include_lib("proper/include/proper.hrl").

-import(generators, [
    int8_gen/0,
    uint16_gen/0,
    uint32_gen/0,
    int64_gen/0,
    binary_string_gen/0
]).

-export([
    prop_low_cardinality_int8_roundtrip/0,
    prop_low_cardinality_uint16_roundtrip/0,
    prop_low_cardinality_uint32_roundtrip/0,
    prop_low_cardinality_int64_roundtrip/0,
    prop_low_cardinality_string_roundtrip/0,
    prop_low_cardinality_dictionary_uniqueness/0
]).

%%%===================================================================
%%% Property Tests
%%%===================================================================

%% @doc Property 5: LowCardinality round trip consistency
%%
%% For all low cardinality types, encoding values and decoding them must
%% produce the original values.
%%
%% Validates Requirements: 5.1, 5.2, 5.6

prop_low_cardinality_int8_roundtrip() ->
    prop_low_cardinality_roundtrip(int8, int8_gen()).

prop_low_cardinality_uint16_roundtrip() ->
    prop_low_cardinality_roundtrip(uint16, uint16_gen()).

prop_low_cardinality_uint32_roundtrip() ->
    prop_low_cardinality_roundtrip(uint32, uint32_gen()).

prop_low_cardinality_int64_roundtrip() ->
    prop_low_cardinality_roundtrip(int64, int64_gen()).

prop_low_cardinality_string_roundtrip() ->
    prop_low_cardinality_roundtrip(string, binary_string_gen()).

%% @doc Property 9: LowCardinality dictionary uniqueness
%%
%% Dictionary must contain only unique values.
%%
%% Validates Requirements: 5.1, 5.2, 5.6

prop_low_cardinality_dictionary_uniqueness() ->
    prop_dictionary_uniqueness(binary_string_gen()).

%%%===================================================================
%%% Property Definitions
%%%===================================================================

%% @doc Property: LowCardinality round trip consistency
%%
%% For any list of values, encoding and then decoding should
%% produce the original values.
prop_low_cardinality_roundtrip(InnerType, InnerGen) ->
    ?FORALL(
        Values,
        low_cardinality_gen(InnerGen),
        begin
            {ok, Encoded} = clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(
                Values, InnerType
            ),
            %% Prepend state version for decoding (normally done by data block encoder)
            StateVersion = clickhouse_erl_types_integer:encode_int64(1),
            EncodedWithState = <<StateVersion/binary, Encoded/binary>>,
            {ok, Decoded, <<>>} = clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(
                EncodedWithState, InnerType, length(Values)
            ),
            Values =:= Decoded
        end
    ).

%% @doc Property: Dictionary uniqueness
%%
%% The dictionary built from any list of values must contain only unique values.
prop_dictionary_uniqueness(InnerGen) ->
    ?FORALL(
        Values,
        low_cardinality_gen(InnerGen),
        begin
            Dictionary = clickhouse_erl_types_low_cardinality:build_dictionary(Values),
            %% Dictionary should have no duplicates
            length(Dictionary) =:= length(lists:usort(Dictionary))
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generate low cardinality data
%%
%% Creates lists with controlled cardinality (limited unique values).
%% This simulates real-world low cardinality columns.
low_cardinality_gen(InnerGen) ->
    ?LET(
        UniqueCount,
        range(1, 50),
        begin
            %% Generate a small set of unique values
            UniqueValues = [InnerGen || _ <- lists:seq(1, UniqueCount)],
            %% Repeat them to create a larger dataset with low cardinality
            ?LET(
                Uniques,
                UniqueValues,
                ?LET(
                    Indices,
                    list(range(0, length(Uniques) - 1)),
                    [lists:nth(I + 1, Uniques) || I <- Indices]
                )
            )
        end
    ).
