%% @doc Property-based tests for special ClickHouse types
%%
%% Tests universal properties for Nothing, Point, Interval, and JSON types.
%% Uses PropEr for property-based testing without external dependencies.
-module(prop_clickhouse_erl_types_special).

-include_lib("proper/include/proper.hrl").

%%%===================================================================
%%% Properties - Nothing Type
%%%===================================================================

%% @doc Property 33: Nothing accepts any input
%% For any input value, encoding as Nothing should succeed and produce
%% a single zero byte.
%% Feature: extended-types-support
%% Property 33: Nothing accepts any input
%% Validates: Requirements 7.5
prop_nothing_accepts_any_input() ->
    ?FORALL(
        Value,
        any(),
        begin
            Result = clickhouse_erl_types_special:encode_nothing(Value),
            Result =:= {ok, <<0>>}
        end
    ).

%%%===================================================================
%%% Properties - Point Type
%%%===================================================================

%% @doc Property 26: Point encode-decode roundtrip
%% For any valid Point value {X, Y} where X and Y are valid Float64 values,
%% encoding then decoding should produce an equivalent value.
%% Feature: extended-types-support
%% Property 26: Point encode-decode roundtrip
%% Validates: Requirements 8.1, 8.2
prop_point_encode_decode_roundtrip() ->
    ?FORALL(
        Point,
        point_gen(),
        begin
            case clickhouse_erl_types_special:encode_point(Point) of
                {ok, Encoded} ->
                    case clickhouse_erl_types_special:decode_point(Encoded) of
                        {ok, Decoded, <<>>} ->
                            points_equal(Point, Decoded);
                        _ ->
                            false
                    end;
                _ ->
                    false
            end
        end
    ).

%% @doc Property 27: Point encoding format
%% For any Point value, the encoded binary should have exactly 16 bytes
%% (two Float64 values in little-endian).
%% Feature: extended-types-support
%% Property 27: Point encoding format
%% Validates: Requirements 8.3
prop_point_encoding_format() ->
    ?FORALL(
        Point,
        point_gen(),
        begin
            case clickhouse_erl_types_special:encode_point(Point) of
                {ok, Encoded} ->
                    byte_size(Encoded) =:= 16;
                _ ->
                    false
            end
        end
    ).

%%%===================================================================
%%% Properties - Interval Type
%%%===================================================================

%% @doc Property 28: Interval encode-decode roundtrip
%% For any valid Interval value {interval, Scale, Value} where Scale is
%% a supported interval type, encoding then decoding should produce an
%% equivalent value.
%% Feature: extended-types-support
%% Property 28: Interval encode-decode roundtrip
%% Validates: Requirements 9.1, 9.2
prop_interval_encode_decode_roundtrip() ->
    ?FORALL(
        {Scale, Value},
        {interval_scale_gen(), integer()},
        begin
            Interval = {interval, Scale, Value},
            case clickhouse_erl_types_special:encode_interval(Interval, Scale) of
                {ok, Encoded} ->
                    case clickhouse_erl_types_special:decode_interval(Encoded, Scale) of
                        {ok, Decoded, <<>>} ->
                            Decoded =:= Interval;
                        _ ->
                            false
                    end;
                _ ->
                    false
            end
        end
    ).

%% @doc Property 29: Interval type parsing
%% For any valid interval type string like "IntervalSecond" or "IntervalDay",
%% parsing should extract the correct scale.
%% Feature: extended-types-support
%% Property 29: Interval type parsing
%% Validates: Requirements 9.7
prop_interval_type_parsing() ->
    ?FORALL(
        Scale,
        interval_scale_gen(),
        begin
            TypeStr = interval_type_string(Scale),
            case clickhouse_erl_types_special:parse_interval_type(TypeStr) of
                {ok, {interval, ParsedScale}} ->
                    ParsedScale =:= Scale;
                _ ->
                    false
            end
        end
    ).

%% @doc Property 30: Interval scale validation
%% For any interval with an unsupported scale, encoding should return
%% an error tuple.
%% Feature: extended-types-support
%% Property 30: Interval scale validation
%% Validates: Requirements 9.8
prop_interval_scale_validation() ->
    ?FORALL(
        {InvalidScale, Value},
        {invalid_interval_scale_gen(), integer()},
        begin
            Interval = {interval, InvalidScale, Value},
            case clickhouse_erl_types_special:encode_interval(Interval, InvalidScale) of
                {error, {invalid_scale, _}} ->
                    true;
                _ ->
                    false
            end
        end
    ).

%%%===================================================================
%%% Properties - JSON Type
%%%===================================================================

%% @doc Property 31: JSON encode-decode roundtrip
%% For any valid JSON value (binary string, map, or list), encoding then
%% decoding should preserve the JSON structure.
%% Feature: extended-types-support
%% Property 31: JSON encode-decode roundtrip
%% Validates: Requirements 10.1, 10.2
prop_json_encode_decode_roundtrip() ->
    ?FORALL(
        JsonValue,
        json_value_gen(),
        begin
            case clickhouse_erl_types_special:encode_json(JsonValue) of
                {ok, Encoded} ->
                    case clickhouse_erl_types_special:decode_json(Encoded, #{parse => true}) of
                        {ok, Decoded, <<>>} ->
                            json_values_equal(JsonValue, Decoded);
                        _ ->
                            false
                    end;
                _ ->
                    false
            end
        end
    ).

%% @doc Property 32: JSON syntax validation
%% For any invalid JSON string, encoding should return an error tuple
%% indicating the syntax error.
%% Feature: extended-types-support
%% Property 32: JSON syntax validation
%% Validates: Requirements 10.6
prop_json_syntax_validation() ->
    ?FORALL(
        InvalidJson,
        invalid_json_gen(),
        begin
            case clickhouse_erl_types_special:encode_json(InvalidJson) of
                {error, {invalid_json, _}} ->
                    true;
                _ ->
                    false
            end
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generator for Point values
%% Generates {X, Y} tuples where X and Y are valid Float64 values
point_gen() ->
    ?LET(
        {X, Y},
        {float_gen(), float_gen()},
        {X, Y}
    ).

%% @doc Generator for Float64 values
%% Generates floats that are valid for Float64 encoding
float_gen() ->
    oneof([
        %% Normal floats
        float(),
        %% Small floats
        ?LET(N, integer(-1000, 1000), float(N)),
        %% Zero
        0.0,
        %% Negative zero
        -0.0,
        %% Small positive/negative
        ?LET(N, integer(1, 100), N / 100.0),
        ?LET(N, integer(1, 100), -N / 100.0)
    ]).

%% @doc Generator for interval scales
%% Generates valid interval scale atoms
interval_scale_gen() ->
    oneof([second, minute, hour, day, week, month, quarter, year]).

%% @doc Generator for invalid interval scales
%% Generates atoms that are not valid interval scales
invalid_interval_scale_gen() ->
    oneof([
        invalid,
        unknown,
        millisecond,
        microsecond,
        nanosecond,
        century,
        decade,
        fortnight,
        ?LET(N, integer(1, 1000), list_to_atom("invalid_" ++ integer_to_list(N)))
    ]).

%% @doc Generator for JSON values
%% Generates valid JSON values (maps, lists, or binary strings)
json_value_gen() ->
    oneof([
        %% Simple JSON objects (maps)
        json_map_gen(),
        %% JSON arrays (lists)
        json_list_gen(),
        %% Pre-encoded JSON strings
        json_string_gen()
    ]).

%% @doc Generator for JSON maps
json_map_gen() ->
    ?LET(
        Pairs,
        list({json_key_gen(), json_primitive_gen()}),
        %% Normalize keys to avoid collisions (atom 'a' and binary <<"a">> both become "a" in JSON)
        maps:from_list(normalize_key_pairs(Pairs))
    ).

%% @doc Normalize key pairs to avoid JSON key collisions
%% Convert all keys to binaries to prevent atom/binary key collisions
normalize_key_pairs(Pairs) ->
    lists:map(
        fun({Key, Value}) ->
            NormalizedKey =
                case Key of
                    K when is_atom(K) -> atom_to_binary(K);
                    K when is_binary(K) -> K;
                    K -> K
                end,
            {NormalizedKey, Value}
        end,
        Pairs
    ).

%% @doc Generator for JSON lists
json_list_gen() ->
    list(json_primitive_gen()).

%% @doc Generator for JSON keys (must be binaries or atoms)
json_key_gen() ->
    oneof([
        %% Binary keys
        ?LET(S, non_empty(list(choose($a, $z))), list_to_binary(S)),
        %% Atom keys
        ?LET(S, non_empty(list(choose($a, $z))), list_to_atom(S))
    ]).

%% @doc Generator for JSON primitive values
json_primitive_gen() ->
    oneof([
        %% Null
        null,
        %% Booleans
        true,
        false,
        %% Numbers
        integer(),
        float(),
        %% Strings
        ?LET(S, list(choose($a, $z)), list_to_binary(S))
    ]).

%% @doc Generator for pre-encoded JSON strings
json_string_gen() ->
    oneof([
        <<"{}">>,
        <<"[]">>,
        <<"{\"key\":\"value\"}">>,
        <<"[1,2,3]">>,
        <<"{\"name\":\"test\",\"value\":42}">>,
        <<"[\"a\",\"b\",\"c\"]">>,
        <<"{\"nested\":{\"key\":\"value\"}}">>,
        <<"[{\"id\":1},{\"id\":2}]">>
    ]).

%% @doc Generator for invalid JSON strings
invalid_json_gen() ->
    oneof([
        %% Unclosed braces
        <<"{\"key\":\"value\"">>,
        %% Unclosed brackets
        <<"[1,2,3">>,
        %% Missing quotes
        <<"{key:value}">>,
        %% Trailing comma
        <<"{\"key\":\"value\",}">>,
        %% Single quotes (not valid JSON)
        <<"{'key':'value'}">>,
        %% Unquoted strings
        <<"{\"key\":value}">>,
        %% Invalid escape sequences
        <<"{\"key\":\"\\x\"}">>,
        %% Empty string (not valid JSON)
        <<"">>,
        %% Just a comma
        <<",">>,
        %% Random text
        <<"not json at all">>,
        %% Incomplete object
        <<"{\"key\":">>
    ]).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Convert interval scale to type string
interval_type_string(second) -> <<"IntervalSecond">>;
interval_type_string(minute) -> <<"IntervalMinute">>;
interval_type_string(hour) -> <<"IntervalHour">>;
interval_type_string(day) -> <<"IntervalDay">>;
interval_type_string(week) -> <<"IntervalWeek">>;
interval_type_string(month) -> <<"IntervalMonth">>;
interval_type_string(quarter) -> <<"IntervalQuarter">>;
interval_type_string(year) -> <<"IntervalYear">>.

%% @doc Compare two points for equality
%% Handles floating point comparison with tolerance
points_equal({X1, Y1}, {X2, Y2}) ->
    floats_equal(X1, X2) andalso floats_equal(Y1, Y2).

%% @doc Compare two floats for equality with tolerance
%% Handles special cases like -0.0 and 0.0
floats_equal(F1, F2) when is_float(F1), is_float(F2) ->
    case {F1, F2} of
        {+0.0, -0.0} ->
            true;
        {-0.0, +0.0} ->
            true;
        _ ->
            %% Use relative tolerance for comparison
            case abs(F1) + abs(F2) of
                +0.0 ->
                    true;
                Sum ->
                    Diff = abs(F1 - F2),
                    Diff / Sum < 1.0e-10
            end
    end;
floats_equal(_, _) ->
    false.

%% @doc Compare two JSON values for equality
%% Handles the fact that encoding and decoding may normalize the representation
%% Note: Atom keys in maps become binary keys after JSON roundtrip
json_values_equal(V1, V2) when is_binary(V1), is_binary(V2) ->
    %% Both are binary strings - parse and compare
    try
        Parsed1 = json:decode(V1),
        Parsed2 = json:decode(V2),
        json_values_equal(Parsed1, Parsed2)
    catch
        _:_ ->
            V1 =:= V2
    end;
json_values_equal(V1, V2) when is_binary(V1) ->
    %% V1 is binary, V2 is parsed - parse V1 and compare
    try
        Parsed1 = json:decode(V1),
        json_values_equal(Parsed1, V2)
    catch
        _:_ ->
            false
    end;
json_values_equal(V1, V2) when is_binary(V2) ->
    %% V2 is binary, V1 is parsed - parse V2 and compare
    try
        Parsed2 = json:decode(V2),
        json_values_equal(V1, Parsed2)
    catch
        _:_ ->
            false
    end;
json_values_equal(V1, V2) when is_map(V1), is_map(V2) ->
    %% Both are maps - normalize keys to binaries and compare
    %% (JSON encoding converts atom keys to binary keys)
    Map1 = normalize_map_keys(V1),
    Map2 = normalize_map_keys(V2),
    Keys1 = lists:sort(maps:keys(Map1)),
    Keys2 = lists:sort(maps:keys(Map2)),
    case Keys1 =:= Keys2 of
        true ->
            lists:all(
                fun(Key) ->
                    json_values_equal(maps:get(Key, Map1), maps:get(Key, Map2))
                end,
                Keys1
            );
        false ->
            false
    end;
json_values_equal(V1, V2) when is_list(V1), is_list(V2) ->
    %% Both are lists - compare elements
    case length(V1) =:= length(V2) of
        true ->
            lists:all(
                fun({E1, E2}) -> json_values_equal(E1, E2) end,
                lists:zip(V1, V2)
            );
        false ->
            false
    end;
json_values_equal(V1, V2) ->
    %% Primitive values - direct comparison
    V1 =:= V2.

%% @doc Normalize map keys to binaries (for JSON comparison)
%% JSON encoding converts atom keys to binary keys
normalize_map_keys(Map) when is_map(Map) ->
    maps:fold(
        fun(Key, Value, Acc) ->
            NormalizedKey =
                case Key of
                    K when is_atom(K) -> atom_to_binary(K);
                    K when is_binary(K) -> K;
                    K -> K
                end,
            NormalizedValue =
                case Value of
                    V when is_map(V) -> normalize_map_keys(V);
                    V when is_list(V) -> normalize_list_values(V);
                    V -> V
                end,
            maps:put(NormalizedKey, NormalizedValue, Acc)
        end,
        #{},
        Map
    ).

%% @doc Normalize list values (for JSON comparison)
normalize_list_values(List) when is_list(List) ->
    lists:map(
        fun(Value) ->
            case Value of
                V when is_map(V) -> normalize_map_keys(V);
                V when is_list(V) -> normalize_list_values(V);
                V -> V
            end
        end,
        List
    ).
