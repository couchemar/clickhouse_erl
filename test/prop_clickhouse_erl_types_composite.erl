-module(prop_clickhouse_erl_types_composite).
-include_lib("proper/include/proper.hrl").

%% Property: type_to_binary is the inverse of parse_column_type.
%% For any valid column_type() term, serializing to binary then parsing back
%% must yield the original term.
prop_type_to_binary_roundtrip() ->
    ?FORALL(
        Type,
        column_type_gen(),
        begin
            Binary = clickhouse_erl_types_composite:type_to_binary(Type),
            Parsed = clickhouse_erl_types_composite:parse_column_type(Binary),
            Parsed =:= Type
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

column_type_gen() ->
    column_type_gen(3).

column_type_gen(0) ->
    primitive_type_gen();
column_type_gen(Depth) ->
    oneof([
        primitive_type_gen(),
        ?LAZY({array, column_type_gen(Depth - 1)}),
        ?LAZY({tuple, non_empty_list_gen(column_type_gen(Depth - 1))}),
        ?LAZY({map, primitive_type_gen(), column_type_gen(Depth - 1)}),
        ?LAZY({nullable, column_type_gen(Depth - 1)}),
        ?LAZY({low_cardinality, primitive_type_gen()})
    ]).

primitive_type_gen() ->
    oneof([
        uint8,
        uint16,
        uint32,
        uint64,
        int8,
        int16,
        int32,
        int64,
        int128,
        uint128,
        int256,
        uint256,
        float32,
        float64,
        string,
        date,
        date32,
        datetime,
        datetime64,
        bool,
        nothing,
        uuid,
        ipv4,
        ipv6
    ]).

non_empty_list_gen(ElemGen) ->
    ?LET(N, range(1, 4), vector(N, ElemGen)).
