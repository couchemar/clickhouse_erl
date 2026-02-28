-module(prop_clickhouse_erl_types_composite).
-include_lib("proper/include/proper.hrl").

%%%===================================================================
%%% Generators
%%%===================================================================

offset_list() ->
    list(non_neg_integer()).

monotonic_offset_list() ->
    ?LET(
        List,
        list(non_neg_integer()),
        lists:reverse(
            element(
                2,
                lists:foldl(
                    fun(X, {Sum, Acc}) ->
                        NewSum = Sum + X,
                        {NewSum, [NewSum | Acc]}
                    end,
                    {0, [0]},
                    List
                )
            )
        )
    ).

%%%===================================================================
%%% Properties
%%%===================================================================

prop_offset_roundtrip() ->
    ?FORALL(
        Offsets,
        offset_list(),
        begin
            Encoded = clickhouse_erl_types_composite:encode_offsets(Offsets),
            Count = length(Offsets),
            {ok, Decoded, Rest} = clickhouse_erl_types_composite:decode_offsets(Encoded, Count),
            Decoded =:= Offsets andalso Rest =:= <<>>
        end
    ).

prop_monotonic_offset_roundtrip() ->
    ?FORALL(
        Offsets,
        monotonic_offset_list(),
        begin
            Encoded = clickhouse_erl_types_composite:encode_offsets(Offsets),
            Count = length(Offsets),
            {ok, Decoded, Rest} = clickhouse_erl_types_composite:decode_offsets(Encoded, Count),
            Decoded =:= Offsets andalso Rest =:= <<>>
        end
    ).
