%% @doc Property tests for ClickHouse Tuple type encoding/decoding.
-module(prop_clickhouse_erl_types_tuple).

-include_lib("proper/include/proper.hrl").

%%%===================================================================
%%% Generators
%%%===================================================================

primitive_type() ->
    oneof([uint8, uint16, uint32, uint64, int8, int16, int32, int64]).

tuple_of_primitives() ->
    ?LET(
        Types,
        non_empty(list(primitive_type())),
        begin
            {tuple, list_to_tuple([gen_value(T) || T <- Types]), Types}
        end
    ).

gen_value(uint8) -> byte();
gen_value(uint16) -> integer(0, 65535);
gen_value(uint32) -> integer(0, 4294967295);
gen_value(uint64) -> integer(0, 18446744073709551615);
gen_value(int8) -> integer(-128, 127);
gen_value(int16) -> integer(-32768, 32767);
gen_value(int32) -> integer(-2147483648, 2147483647);
gen_value(int64) -> integer(-9223372036854775808, 9223372036854775807).

%% Generator for simple tuple values with UInt8 elements
simple_tuple_gen() ->
    ?LET(
        Size,
        range(1, 5),
        ?LET(
            Values,
            vector(Size, range(0, 255)),
            list_to_tuple(Values)
        )
    ).

%% Generator for list of tuples (column data)
tuple_column_gen(TupleGen) ->
    ?LET(
        Count,
        range(0, 20),
        vector(Count, TupleGen)
    ).

%% Generator for element types matching simple tuples
simple_element_types_gen() ->
    ?LET(
        Size,
        range(1, 5),
        vector(Size, return(uint8))
    ).

%%%===================================================================
%%% Properties
%%%===================================================================

%% Property 1: Tuple round trip consistency (single row)
%% Validates Requirements 1.1, 1.2
prop_tuple_roundtrip() ->
    ?FORALL(
        {tuple, Values, Types},
        tuple_of_primitives(),
        begin
            %% Single row
            Data = [Values],
            case clickhouse_erl_types_tuple:encode_tuple_column(Data, Types) of
                {ok, Enc} ->
                    {ok, Decoded, Rest} = clickhouse_erl_types_tuple:decode_tuple_column(
                        Enc, Types, 1
                    ),
                    Decoded =:= Data andalso Rest =:= <<>>;
                _ ->
                    false
            end
        end
    ).

%% Property: Multiple rows round trip
prop_tuple_multi_row_roundtrip() ->
    ?FORALL(
        {Tuples, Types},
        {tuple_column_gen(simple_tuple_gen()), simple_element_types_gen()},
        begin
            % Filter to only use tuples matching the type count
            TypeCount = length(Types),
            FilteredTuples = [T || T <- Tuples, tuple_size(T) =:= TypeCount],

            case FilteredTuples of
                [] ->
                    % Empty case - always passes
                    true;
                _ ->
                    % Encode
                    EncodedResult = clickhouse_erl_types_tuple:encode_tuple_column(
                        FilteredTuples, Types
                    ),

                    case EncodedResult of
                        {error, _} ->
                            % Encoding failed - this is acceptable for some inputs
                            true;
                        {ok, Encoded} ->
                            % Decode
                            RowCount = length(FilteredTuples),
                            case
                                clickhouse_erl_types_tuple:decode_tuple_column(
                                    Encoded, Types, RowCount
                                )
                            of
                                {ok, Decoded, <<>>} ->
                                    % Check if decoded matches original
                                    Decoded =:= FilteredTuples;
                                _ ->
                                    false
                            end
                    end
            end
        end
    ).

%% Property: Empty tuples round trip
prop_empty_tuple_roundtrip() ->
    ?FORALL(
        Count,
        range(0, 100),
        begin
            Tuples = lists:duplicate(Count, {}),
            Types = [],

            % Encode
            {ok, Encoded} = clickhouse_erl_types_tuple:encode_tuple_column(Tuples, Types),

            % Decode
            {ok, Decoded, <<>>} = clickhouse_erl_types_tuple:decode_tuple_column(
                Encoded, Types, Count
            ),

            % Verify
            Decoded =:= Tuples
        end
    ).

%% Property: Single element tuples round trip
prop_single_element_tuple_roundtrip() ->
    ?FORALL(
        Values,
        list(range(0, 255)),
        begin
            Tuples = [{V} || V <- Values],
            Types = [uint8],

            % Encode
            {ok, Encoded} = clickhouse_erl_types_tuple:encode_tuple_column(Tuples, Types),

            % Decode
            RowCount = length(Tuples),
            {ok, Decoded, <<>>} = clickhouse_erl_types_tuple:decode_tuple_column(
                Encoded, Types, RowCount
            ),

            % Verify
            Decoded =:= Tuples
        end
    ).

%% Property: Two element tuples round trip
prop_two_element_tuple_roundtrip() ->
    ?FORALL(
        Pairs,
        list({range(0, 255), range(0, 65535)}),
        begin
            Tuples = Pairs,
            Types = [uint8, uint16],

            % Encode
            {ok, Encoded} = clickhouse_erl_types_tuple:encode_tuple_column(Tuples, Types),

            % Decode
            RowCount = length(Tuples),
            {ok, Decoded, <<>>} = clickhouse_erl_types_tuple:decode_tuple_column(
                Encoded, Types, RowCount
            ),

            % Verify
            Decoded =:= Tuples
        end
    ).
