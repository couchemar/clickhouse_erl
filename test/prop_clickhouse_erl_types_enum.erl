%% @doc Property-based tests for enum type encoding and decoding.
%%
%% Feature: extended-types-support
%% Tests universal properties for Enum8 and Enum16 types.
-module(prop_clickhouse_erl_types_enum).
-include_lib("proper/include/proper.hrl").

%%%===================================================================
%%% Properties
%%%===================================================================

%% Property 11: Enum encode-decode roundtrip
%% Validates: Requirements 3.1, 3.2, 3.3, 3.4
%%
%% For any valid enum value (atom, binary, or integer) that exists in the
%% enum mappings, encoding then decoding should produce an equivalent value.
prop_enum8_roundtrip() ->
    ?FORALL(
        {Value, Mappings},
        enum8_value_and_mappings(),
        begin
            case clickhouse_erl_types_enum:encode_enum8(Value, Mappings) of
                {ok, Encoded} ->
                    case clickhouse_erl_types_enum:decode_enum8(Encoded, Mappings) of
                        {ok, Decoded, <<>>} ->
                            % Decoded value should match the original
                            values_equivalent(Value, Decoded, Mappings);
                        {error, _} ->
                            false
                    end;
                {error, _} ->
                    false
            end
        end
    ).

%% Property 11: Enum encode-decode roundtrip (Enum16)
%% Validates: Requirements 3.1, 3.2, 3.3, 3.4
prop_enum16_roundtrip() ->
    ?FORALL(
        {Value, Mappings},
        enum16_value_and_mappings(),
        begin
            case clickhouse_erl_types_enum:encode_enum16(Value, Mappings) of
                {ok, Encoded} ->
                    case clickhouse_erl_types_enum:decode_enum16(Encoded, Mappings) of
                        {ok, Decoded, <<>>} ->
                            % Decoded value should match the original
                            values_equivalent(Value, Decoded, Mappings);
                        {error, _} ->
                            false
                    end;
                {error, _} ->
                    false
            end
        end
    ).

%% Property 12: Enum underlying encoding
%% Validates: Requirements 3.5, 3.6
%%
%% For any enum value, the encoded binary should use Int8 for Enum8 (1 byte)
%% or Int16 for Enum16 (2 bytes, little-endian).
prop_enum8_underlying_encoding() ->
    ?FORALL(
        {Value, Mappings},
        enum8_value_and_mappings(),
        begin
            case clickhouse_erl_types_enum:encode_enum8(Value, Mappings) of
                {ok, Encoded} ->
                    % Should be exactly 1 byte
                    byte_size(Encoded) =:= 1 andalso
                        % Should match Int8 encoding
                        begin
                            IntValue = get_int_value(Value, Mappings),
                            ExpectedEncoded = clickhouse_erl_types_integer:encode_int8(IntValue),
                            Encoded =:= ExpectedEncoded
                        end;
                {error, _} ->
                    false
            end
        end
    ).

prop_enum16_underlying_encoding() ->
    ?FORALL(
        {Value, Mappings},
        enum16_value_and_mappings(),
        begin
            case clickhouse_erl_types_enum:encode_enum16(Value, Mappings) of
                {ok, Encoded} ->
                    % Should be exactly 2 bytes
                    byte_size(Encoded) =:= 2 andalso
                        % Should match Int16 encoding
                        begin
                            IntValue = get_int_value(Value, Mappings),
                            ExpectedEncoded = clickhouse_erl_types_integer:encode_int16(IntValue),
                            Encoded =:= ExpectedEncoded
                        end;
                {error, _} ->
                    false
            end
        end
    ).

%% Property 13: Enum value validation
%% Validates: Requirements 3.10
%%
%% For any enum value not present in the defined mappings, encoding should
%% return an error tuple.
prop_enum8_value_validation() ->
    ?FORALL(
        Mappings,
        enum8_mappings(),
        ?FORALL(
            InvalidValue,
            invalid_enum_value(Mappings),
            begin
                Result = clickhouse_erl_types_enum:encode_enum8(InvalidValue, Mappings),
                case Result of
                    {error, _} -> true;
                    {ok, _} -> false
                end
            end
        )
    ).

prop_enum16_value_validation() ->
    ?FORALL(
        Mappings,
        enum16_mappings(),
        ?FORALL(
            InvalidValue,
            invalid_enum_value(Mappings),
            begin
                Result = clickhouse_erl_types_enum:encode_enum16(InvalidValue, Mappings),
                case Result of
                    {error, _} -> true;
                    {ok, _} -> false
                end
            end
        )
    ).

%% Property 14: Enum type parsing
%% Validates: Requirements 3.9, 3.11, 3.12
%%
%% For any valid enum type string like "Enum8('name1' = 1, 'name2' = 2)",
%% parsing should extract the correct name-value mappings including negative values.
prop_enum8_type_parsing() ->
    ?FORALL(
        Mappings,
        enum8_mappings(),
        begin
            % Generate type string from mappings
            TypeString = generate_enum8_type_string(Mappings),
            % Parse it back
            case clickhouse_erl_types_enum:parse_enum_type(TypeString) of
                {ok, {enum8, ParsedMappings}} ->
                    % Parsed mappings should match original
                    maps_equivalent(Mappings, ParsedMappings);
                {error, _} ->
                    false
            end
        end
    ).

prop_enum16_type_parsing() ->
    ?FORALL(
        Mappings,
        enum16_mappings(),
        begin
            % Generate type string from mappings
            TypeString = generate_enum16_type_string(Mappings),
            % Parse it back
            case clickhouse_erl_types_enum:parse_enum_type(TypeString) of
                {ok, {enum16, ParsedMappings}} ->
                    % Parsed mappings should match original
                    maps_equivalent(Mappings, ParsedMappings);
                {error, _} ->
                    false
            end
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% Generate Enum8 value and mappings
enum8_value_and_mappings() ->
    ?LET(
        Mappings,
        enum8_mappings(),
        ?LET(
            Value,
            enum_value(Mappings),
            {Value, Mappings}
        )
    ).

%% Generate Enum16 value and mappings
enum16_value_and_mappings() ->
    ?LET(
        Mappings,
        enum16_mappings(),
        ?LET(
            Value,
            enum_value(Mappings),
            {Value, Mappings}
        )
    ).

%% Generate Enum8 mappings (Int8 range: -128 to 127)
enum8_mappings() ->
    ?LET(
        Size,
        range(1, 10),
        ?LET(
            Pairs,
            unique_enum_pairs(Size, fun int8_value/0),
            maps:from_list(Pairs)
        )
    ).

%% Generate Enum16 mappings (Int16 range: -32768 to 32767)
enum16_mappings() ->
    ?LET(
        Size,
        range(1, 10),
        ?LET(
            Pairs,
            unique_enum_pairs(Size, fun int16_value/0),
            maps:from_list(Pairs)
        )
    ).

%% Generate enum name (atom or binary)
enum_name() ->
    oneof([
        ?LET(
            Name,
            non_empty(list(choose($a, $z))),
            list_to_atom(Name)
        ),
        ?LET(
            Name,
            non_empty(list(choose($a, $z))),
            list_to_binary(Name)
        )
    ]).

%% Generate Int8 value
int8_value() ->
    integer(-128, 127).

%% Generate Int16 value
int16_value() ->
    integer(-32768, 32767).

%% Generate enum value from mappings (atom, binary, or integer)
enum_value(Mappings) ->
    Keys = maps:keys(Mappings),
    Values = maps:values(Mappings),
    oneof([
        % Pick a random key (atom or binary)
        oneof(Keys),
        % Pick a random value (integer)
        oneof(Values)
    ]).

%% Generate invalid enum value (not in mappings)
invalid_enum_value(Mappings) ->
    Keys = maps:keys(Mappings),
    Values = maps:values(Mappings),
    oneof([
        % Generate an atom not in keys
        ?SUCHTHAT(
            Name,
            ?LET(N, non_empty(list(choose($a, $z))), list_to_atom(N)),
            not lists:member(Name, Keys)
        ),
        % Generate a binary not in keys
        ?SUCHTHAT(
            Name,
            ?LET(N, non_empty(list(choose($a, $z))), list_to_binary(N)),
            not lists:member(Name, Keys)
        ),
        % Generate an integer not in values
        ?SUCHTHAT(
            Value,
            integer(-128, 127),
            not lists:member(Value, Values)
        )
    ]).

%% Generate unique enum pairs (unique values, unique names)
unique_enum_pairs(Size, ValueGen) ->
    ?LET(
        Pairs,
        vector(Size, {enum_name(), ValueGen()}),
        make_unique_pairs(Pairs, #{}, [])
    ).

%% Make pairs unique by both name and value
make_unique_pairs([], _Seen, Acc) ->
    lists:reverse(Acc);
make_unique_pairs([{Name, Value} | Rest], Seen, Acc) ->
    % Normalize name to atom to detect collisions (e.g., atom 'a' and binary <<"a">>)
    NormalizedName = normalize_key(Name),
    NameKey = {name, NormalizedName},
    ValueKey = {value, Value},
    case maps:is_key(NameKey, Seen) orelse maps:is_key(ValueKey, Seen) of
        true ->
            % Skip duplicate name or value
            make_unique_pairs(Rest, Seen, Acc);
        false ->
            % Add to result and mark as seen
            NewSeen = maps:put(NameKey, true, maps:put(ValueKey, true, Seen)),
            make_unique_pairs(Rest, NewSeen, [{Name, Value} | Acc])
    end.

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% Check if two enum values are equivalent
values_equivalent(Value, Decoded, Mappings) when is_integer(Value) ->
    % If input was integer, decoded should be the name for that integer
    case maps:get(Decoded, Mappings, undefined) of
        Value -> true;
        _ -> false
    end;
values_equivalent(Value, Decoded, _Mappings) ->
    % If input was atom or binary, decoded should match exactly
    Value =:= Decoded.

%% Get integer value from enum value (atom, binary, or integer)
get_int_value(Value, _Mappings) when is_integer(Value) ->
    Value;
get_int_value(Value, Mappings) when is_atom(Value) orelse is_binary(Value) ->
    maps:get(Value, Mappings).

%% Generate Enum8 type string from mappings
generate_enum8_type_string(Mappings) ->
    Pairs = maps:to_list(Mappings),
    PairStrings = [format_enum_pair(Name, Value) || {Name, Value} <- Pairs],
    iolist_to_binary([<<"Enum8(">>, lists:join(<<", ">>, PairStrings), <<")">>]).

%% Generate Enum16 type string from mappings
generate_enum16_type_string(Mappings) ->
    Pairs = maps:to_list(Mappings),
    PairStrings = [format_enum_pair(Name, Value) || {Name, Value} <- Pairs],
    iolist_to_binary([<<"Enum16(">>, lists:join(<<", ">>, PairStrings), <<")">>]).

%% Format a single enum pair as 'name' = value
format_enum_pair(Name, Value) when is_atom(Name) ->
    iolist_to_binary([<<"'">>, atom_to_binary(Name, utf8), <<"' = ">>, integer_to_binary(Value)]);
format_enum_pair(Name, Value) when is_binary(Name) ->
    iolist_to_binary([<<"'">>, Name, <<"' = ">>, integer_to_binary(Value)]).

%% Check if two maps are equivalent
maps_equivalent(Map1, Map2) ->
    maps:size(Map1) =:= maps:size(Map2) andalso
        maps:fold(
            fun(Key, Value, Acc) ->
                % Parser converts all names to atoms, so we need to normalize keys
                NormalizedKey = normalize_key(Key),
                Acc andalso maps:get(NormalizedKey, Map2, undefined) =:= Value
            end,
            true,
            Map1
        ).

%% Normalize key to atom (parser always returns atoms)
normalize_key(Key) when is_atom(Key) -> Key;
normalize_key(Key) when is_binary(Key) -> binary_to_atom(Key, utf8).
