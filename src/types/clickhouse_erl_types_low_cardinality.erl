%% @doc ClickHouse LowCardinality type support.
%%
%% This module implements support for the ClickHouse LowCardinality type, which
%% uses dictionary encoding to reduce storage for columns with limited unique values.
%% Values are stored transparently (same as underlying type) but encoded efficiently.
%%
%% == Erlang Data Structure Mapping ==
%%
%% LowCardinality values are represented transparently (same as underlying type):
%% ```
%% LowCardinality(String) -> <<"foo">>  % Same as String
%% LowCardinality(Int64) -> 42          % Same as Int64
%% '''
%%
%% The dictionary encoding is handled internally during encoding/decoding.
%%
%% == Usage Examples ==
%%
%% === Parsing LowCardinality Types ===
%% ```
%% % LowCardinality string (most common use case)
%% Type1 = clickhouse_erl_types_low_cardinality:parse_low_cardinality_type(
%%     <<"LowCardinality(String)">>
%% ).
%% % Returns: string
%%
%% % LowCardinality with other types
%% Type2 = clickhouse_erl_types_low_cardinality:parse_low_cardinality_type(
%%     <<"LowCardinality(Int64)">>
%% ).
%% % Returns: int64
%% '''
%%
%% === Encoding LowCardinality Values ===
%% ```
%% % High cardinality data (many unique values)
%% Data1 = [<<"foo">>, <<"bar">>, <<"baz">>, <<"qux">>, <<"foo">>, <<"bar">>],
%% {ok, Binary1} = clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(
%%     Data1, string
%% ).
%%
%% % Low cardinality data (few unique values - optimal case)
%% Data2 = [<<"A">>, <<"A">>, <<"B">>, <<"B">>, <<"B">>, <<"A">>],
%% {ok, Binary2} = clickhouse_erl_types_low_cardinality:encode_low_cardinality_column(
%%     Data2, string
%% ).
%% '''
%%
%% === Decoding LowCardinality Values ===
%% ```
%% {ok, Values, Rest} = clickhouse_erl_types_low_cardinality:decode_low_cardinality_column(
%%     Binary, string, 6
%% ).
%% % Returns: {ok, [<<"foo">>, <<"foo">>, <<"bar">>, <<"bar">>, <<"bar">>, <<"foo">>], <<>>}
%% '''
%%
%% == Protocol Details ==
%%
%% LowCardinality columns use dictionary encoding:
%% 1. Metadata (Int64): Flags + key type (UInt8/16/32/64)
%% 2. Dictionary size (Int64)
%% 3. Dictionary column: Unique values
%% 4. Keys size (Int64)
%% 5. Keys column: Indexes into dictionary
%%
%% The key type is automatically selected based on dictionary size:
%% - UInt8: Dictionary size <= 256
%% - UInt16: Dictionary size <= 65,536
%% - UInt32: Dictionary size <= 4,294,967,296
%% - UInt64: Larger dictionaries
%%
%% Example: [<<"foo">>, <<"foo">>, <<"bar">>, <<"bar">>, <<"bar">>, <<"foo">>]
%% - Dictionary: [<<"foo">>, <<"bar">>]
%% - Keys: [0, 0, 1, 1, 1, 0] (as UInt8)
%%
%% == Performance Considerations ==
%%
%% LowCardinality is most effective for columns with:
%% - Limited unique values (< 10,000)
%% - High repetition of values
%% - String data (primary use case)
%%
%% For high-cardinality columns, the overhead of dictionary encoding may
%% outweigh the benefits.
%%
%% @see clickhouse_erl_types_composite
-module(clickhouse_erl_types_low_cardinality).

-include_lib("kernel/include/logger.hrl").

%% Public API
-export([
    % Type parsing
    parse_low_cardinality_type/1,
    % Column encoding/decoding
    encode_low_cardinality_column/2,
    decode_low_cardinality_column/3,
    decode_low_cardinality_column_nested/3,
    % Dictionary building (exported for testing)
    build_dictionary/1,
    build_key_mapping/2,
    select_key_type/1
]).

%% Type definitions
-type key_type() :: uint8 | uint16 | uint32 | uint64.
-type low_cardinality_error() ::
    {invalid_dictionary_metadata, term()}
    | {dictionary_index_out_of_range, integer(), pos_integer()}
    | {unsupported_key_type, integer()}.

-export_type([key_type/0, low_cardinality_error/0]).

%% Key type constants (for metadata encoding)
-define(KEY_TYPE_UINT8, 0).
-define(KEY_TYPE_UINT16, 1).
-define(KEY_TYPE_UINT32, 2).
-define(KEY_TYPE_UINT64, 3).

%% Cardinality flags (for metadata encoding)
-define(CARDINALITY_KEY_MASK, 16#FF).
%% Need to read additional keys
-define(CARDINALITY_HAS_ADDITIONAL_KEYS_BIT, (1 bsl 9)).
%% Need to update dictionary
-define(CARDINALITY_NEED_UPDATE_DICTIONARY, (1 bsl 10)).
%% Update all (both flags set)
-define(CARDINALITY_UPDATE_ALL,
    (?CARDINALITY_HAS_ADDITIONAL_KEYS_BIT bor ?CARDINALITY_NEED_UPDATE_DICTIONARY)
).

%% Key serialization version
-define(SHARED_DICTIONARIES_WITH_ADDITIONAL_KEYS, 1).

%%%===================================================================
%%% Type Parsing
%%%===================================================================

%% @doc Parse a LowCardinality type definition string.
%%
%% Examples:
%% "LowCardinality(String)" -> string
%% "LowCardinality(Int64)" -> int64
-spec parse_low_cardinality_type(binary() | string()) ->
    clickhouse_erl_types_composite:column_type().
parse_low_cardinality_type(Type) when is_list(Type) ->
    parse_low_cardinality_type(list_to_binary(Type));
parse_low_cardinality_type(Type) when is_binary(Type) ->
    %% Remove "LowCardinality(" and closing ")"
    case binary:split(Type, <<"(">>) of
        [<<"LowCardinality">>, Rest] ->
            %% Extract inner type (remove trailing ")")
            InnerTypeStr = binary:part(Rest, 0, byte_size(Rest) - 1),
            %% Parse the inner type recursively
            clickhouse_erl_types_composite:parse_column_type(InnerTypeStr);
        _ ->
            error({invalid_low_cardinality_type, Type})
    end.

%%%===================================================================
%%% Dictionary Building
%%%===================================================================

%% @doc Extract unique values from a list to build a dictionary.
%%
%% Returns a list of unique values in the order they first appear.
%% No default value is added - the dictionary contains only values from the input.
-spec build_dictionary([term()]) -> [term()].
build_dictionary(Values) ->
    %% Use a map to track seen values and maintain order
    {Dict, _Seen} = lists:foldl(
        fun(Value, {DictAcc, SeenAcc}) ->
            case maps:is_key(Value, SeenAcc) of
                true ->
                    {DictAcc, SeenAcc};
                false ->
                    {DictAcc ++ [Value], maps:put(Value, true, SeenAcc)}
            end
        end,
        {[], #{}},
        Values
    ),
    Dict.

%% @doc Build a mapping from values to dictionary indexes.
%%
%% Returns a map where keys are values and values are indexes.
%% Indexes start from 0 for the first unique value.
-spec build_key_mapping([term()], [term()]) -> #{term() => non_neg_integer()}.
build_key_mapping(Dictionary, _Values) ->
    %% Create a map from value to index
    {Mapping, _} = lists:foldl(
        fun(DictValue, {MapAcc, Index}) ->
            {maps:put(DictValue, Index, MapAcc), Index + 1}
        end,
        {#{}, 0},
        Dictionary
    ),
    Mapping.

%% @doc Select the appropriate key type based on dictionary size.
%%
%% Uses the smallest type that can represent all indexes.
%% Note: Dictionary size includes the default value at index 0.
-spec select_key_type(pos_integer()) -> key_type().
select_key_type(DictSize) when DictSize =< 256 ->
    uint8;
select_key_type(DictSize) when DictSize =< 65536 ->
    uint16;
select_key_type(DictSize) when DictSize =< 4294967296 ->
    uint32;
select_key_type(_DictSize) ->
    uint64.

%%%===================================================================
%%% Column Encoding
%%%===================================================================

%% @doc Encode a low cardinality column.
%%
%% Transforms a list of values into:
%% 1. Meta (Int64): flags + key type
%% 2. Dictionary size (Int64)
%% 3. Dictionary column: unique values
%% 4. Keys size (Int64)
%% 5. Keys column: indexes into dictionary (UInt8/16/32/64)
-spec encode_low_cardinality_column([term()], clickhouse_erl_types_composite:column_type()) ->
    {ok, binary()} | {error, term()}.
encode_low_cardinality_column(Values, InnerType) ->
    %% Build dictionary from unique values
    Dictionary = build_dictionary(Values),
    DictSize = length(Dictionary),

    %% Select appropriate key type
    KeyType = select_key_type(DictSize),

    %% Build key mapping
    KeyMapping = build_key_mapping(Dictionary, Values),

    %% Build keys column (indexes into dictionary)
    Keys = [maps:get(V, KeyMapping) || V <- Values],

    %% Encode metadata (Int64): flags + key type
    %% Use CARDINALITY_UPDATE_ALL flags as per ch-go implementation
    KeyTypeCode = key_type_to_code(KeyType),
    MetaValue = ?CARDINALITY_UPDATE_ALL bor KeyTypeCode,
    Metadata = clickhouse_erl_types_integer:encode_int64(MetaValue),

    %% Encode dictionary size (Int64)
    DictSizeEncoded = clickhouse_erl_types_integer:encode_int64(DictSize),

    %% Encode dictionary column
    case clickhouse_erl_types_column:encode_column(InnerType, Dictionary) of
        {ok, DictEncoded} ->
            %% Encode keys size (Int64)
            KeysSize = length(Keys),
            KeysSizeEncoded = clickhouse_erl_types_integer:encode_int64(KeysSize),

            %% Encode keys column
            KeysEncoded = encode_keys_column(Keys, KeyType),

            %% Combine all parts
            {ok,
                iolist_to_binary([
                    Metadata,
                    DictSizeEncoded,
                    DictEncoded,
                    KeysSizeEncoded,
                    KeysEncoded
                ])};
        Error ->
            Error
    end.

%% @doc Encode keys column based on key type.
-spec encode_keys_column([non_neg_integer()], key_type()) -> binary().
encode_keys_column(Keys, uint8) ->
    <<<<K:8>> || K <- Keys>>;
encode_keys_column(Keys, uint16) ->
    <<<<K:16/little-unsigned-integer>> || K <- Keys>>;
encode_keys_column(Keys, uint32) ->
    <<<<K:32/little-unsigned-integer>> || K <- Keys>>;
encode_keys_column(Keys, uint64) ->
    <<<<K:64/little-unsigned-integer>> || K <- Keys>>.

%% @doc Convert key type atom to code for metadata.
-spec key_type_to_code(key_type()) -> integer().
key_type_to_code(uint8) -> ?KEY_TYPE_UINT8;
key_type_to_code(uint16) -> ?KEY_TYPE_UINT16;
key_type_to_code(uint32) -> ?KEY_TYPE_UINT32;
key_type_to_code(uint64) -> ?KEY_TYPE_UINT64.

%%%===================================================================
%%% Column Decoding
%%%===================================================================

%% @doc Decode a low cardinality column.
%%
%% The binary data for a low cardinality column consists of:
%% 1. State version (Int64): should be 1
%% 2. Meta (Int64): flags + key type
%% 3. Dictionary size (Int64)
%% 4. Dictionary column: unique values
%% 5. Keys size (Int64)
%% 6. Keys column: indexes into dictionary
-spec decode_low_cardinality_column(
    binary(), clickhouse_erl_types_composite:column_type(), non_neg_integer()
) ->
    {ok, [term()], binary()} | {error, term()}.
decode_low_cardinality_column(Binary, InnerType, RowCount) ->
    maybe
        %% Decode and validate state version
        {ok, 1, RestAfterState} ?= clickhouse_erl_types_integer:decode_int64(Binary),
        %% Decode metadata and extract key type
        {ok, Meta, RestAfterMetadata} ?=
            clickhouse_erl_types_integer:decode_int64(
                RestAfterState
            ),
        KeyTypeCode = Meta band ?CARDINALITY_KEY_MASK,
        {ok, KeyType} ?= code_to_key_type(KeyTypeCode),
        %% Decode dictionary
        {ok, DictSize, RestAfterDictSize} ?=
            clickhouse_erl_types_integer:decode_int64(
                RestAfterMetadata
            ),
        {ok, Dictionary, RestAfterDict} ?=
            decode_dictionary_column(
                RestAfterDictSize, InnerType, DictSize
            ),
        %% Decode keys
        {ok, KeysSize, RestAfterKeysSize} ?=
            clickhouse_erl_types_integer:decode_int64(
                RestAfterDict
            ),
        true ?= (KeysSize =:= RowCount),
        {ok, Keys, Rest} ?= decode_keys_column(RestAfterKeysSize, KeyType, KeysSize),
        %% Lookup values
        {ok, Values} ?= lookup_values(Keys, Dictionary),
        {ok, Values, Rest}
    else
        {ok, BadVersion, _} when BadVersion =/= 1 ->
            {error, {invalid_state_version, BadVersion}};
        {error, _} = Error ->
            Error;
        false ->
            %% Handle validation failures - determine which one failed
            case clickhouse_erl_types_integer:decode_int64(Binary) of
                {ok, 1, RestAfterState2} ->
                    case clickhouse_erl_types_integer:decode_int64(RestAfterState2) of
                        {ok, Meta2, _} ->
                            HasAdditionalKeys2 =
                                (Meta2 band ?CARDINALITY_HAS_ADDITIONAL_KEYS_BIT) =/= 0,
                            case HasAdditionalKeys2 of
                                false ->
                                    {error,
                                        {invalid_dictionary_metadata, missing_additional_keys_bit}};
                                true ->
                                    %% Must be keys size mismatch
                                    {error, keys_size_mismatch}
                            end;
                        _ ->
                            {error, invalid_metadata}
                    end;
                _ ->
                    {error, decode_failed}
            end
    end.

%% @doc Decode a low cardinality column in nested context (no state version).
%%
%% This function is used when LowCardinality is nested inside another composite type
%% (Array, Nullable, Tuple, Map). In nested contexts, the state version is not included.
%%
%% The binary data consists of:
%% 1. Meta (Int64): flags + key type
%% 2. Dictionary size (Int64)
%% 3. Dictionary column: unique values
%% 4. Keys size (Int64)
%% 5. Keys column: indexes into dictionary
-spec decode_low_cardinality_column_nested(
    binary(), clickhouse_erl_types_composite:column_type(), non_neg_integer()
) ->
    {ok, [term()], binary()} | {error, term()}.
decode_low_cardinality_column_nested(Binary, InnerType, RowCount) ->
    maybe
        %% Decode metadata and extract key type (no state version in nested context)
        {ok, Meta, RestAfterMetadata} ?=
            clickhouse_erl_types_integer:decode_int64(Binary),
        KeyTypeCode = Meta band ?CARDINALITY_KEY_MASK,
        {ok, KeyType} ?= code_to_key_type(KeyTypeCode),
        %% Decode dictionary
        {ok, DictSize, RestAfterDictSize} ?=
            clickhouse_erl_types_integer:decode_int64(
                RestAfterMetadata
            ),
        {ok, Dictionary, RestAfterDict} ?=
            decode_dictionary_column(
                RestAfterDictSize, InnerType, DictSize
            ),
        %% Decode keys
        {ok, KeysSize, RestAfterKeysSize} ?=
            clickhouse_erl_types_integer:decode_int64(
                RestAfterDict
            ),
        true ?= (KeysSize =:= RowCount),
        {ok, Keys, Rest} ?= decode_keys_column(RestAfterKeysSize, KeyType, KeysSize),
        %% Lookup values
        {ok, Values} ?= lookup_values(Keys, Dictionary),
        {ok, Values, Rest}
    else
        {error, _} = Error ->
            Error;
        false ->
            {error, keys_size_mismatch}
    end.

%% @doc Decode the dictionary column.
-spec decode_dictionary_column(
    binary(), clickhouse_erl_types_composite:column_type(), non_neg_integer()
) ->
    {ok, [term()], binary()} | {error, term()}.
decode_dictionary_column(Binary, InnerType, DictSize) ->
    %% Convert type to binary string for data block decoder
    TypeStr = type_to_binary(InnerType),
    clickhouse_erl_protocol_data_block:decode_column_data(TypeStr, DictSize, Binary).

%% @doc Decode keys column based on key type.
-spec decode_keys_column(binary(), key_type(), non_neg_integer()) ->
    {ok, [non_neg_integer()], binary()} | {error, term()}.
decode_keys_column(Binary, uint8, KeysSize) ->
    ExpectedBytes = KeysSize,
    case byte_size(Binary) >= ExpectedBytes of
        true ->
            <<KeysBin:ExpectedBytes/binary, Rest/binary>> = Binary,
            Keys = [K || <<K:8>> <= KeysBin],
            {ok, Keys, Rest};
        false ->
            {error,
                {truncated_data, #{
                    expected_bytes => ExpectedBytes,
                    actual_bytes => byte_size(Binary),
                    type => keys_uint8
                }}}
    end;
decode_keys_column(Binary, uint16, KeysSize) ->
    ExpectedBytes = KeysSize * 2,
    case byte_size(Binary) >= ExpectedBytes of
        true ->
            <<KeysBin:ExpectedBytes/binary, Rest/binary>> = Binary,
            Keys = [K || <<K:16/little-unsigned-integer>> <= KeysBin],
            {ok, Keys, Rest};
        false ->
            {error,
                {truncated_data, #{
                    expected_bytes => ExpectedBytes,
                    actual_bytes => byte_size(Binary),
                    type => keys_uint16
                }}}
    end;
decode_keys_column(Binary, uint32, KeysSize) ->
    ExpectedBytes = KeysSize * 4,
    case byte_size(Binary) >= ExpectedBytes of
        true ->
            <<KeysBin:ExpectedBytes/binary, Rest/binary>> = Binary,
            Keys = [K || <<K:32/little-unsigned-integer>> <= KeysBin],
            {ok, Keys, Rest};
        false ->
            {error,
                {truncated_data, #{
                    expected_bytes => ExpectedBytes,
                    actual_bytes => byte_size(Binary),
                    type => keys_uint32
                }}}
    end;
decode_keys_column(Binary, uint64, KeysSize) ->
    ExpectedBytes = KeysSize * 8,
    case byte_size(Binary) >= ExpectedBytes of
        true ->
            <<KeysBin:ExpectedBytes/binary, Rest/binary>> = Binary,
            Keys = [K || <<K:64/little-unsigned-integer>> <= KeysBin],
            {ok, Keys, Rest};
        false ->
            {error,
                {truncated_data, #{
                    expected_bytes => ExpectedBytes,
                    actual_bytes => byte_size(Binary),
                    type => keys_uint64
                }}}
    end.

%% @doc Lookup dictionary values using keys (indexes).
-spec lookup_values([non_neg_integer()], [term()]) -> {ok, [term()]} | {error, term()}.
lookup_values(Keys, Dictionary) ->
    DictSize = length(Dictionary),
    lookup_values_fold(Keys, Dictionary, DictSize, []).

%% @doc Helper function to lookup values with proper error handling.
-spec lookup_values_fold([non_neg_integer()], [term()], non_neg_integer(), [term()]) ->
    {ok, [term()]} | {error, term()}.
lookup_values_fold([], _Dictionary, _DictSize, Acc) ->
    {ok, lists:reverse(Acc)};
lookup_values_fold([Key | Rest], Dictionary, DictSize, Acc) ->
    case Key < DictSize of
        true ->
            Value = lists:nth(Key + 1, Dictionary),
            lookup_values_fold(Rest, Dictionary, DictSize, [Value | Acc]);
        false ->
            {error, {dictionary_index_out_of_range, Key, DictSize}}
    end.

%% @doc Convert metadata code to key type.
-spec code_to_key_type(integer()) -> {ok, key_type()} | {error, term()}.
code_to_key_type(?KEY_TYPE_UINT8) -> {ok, uint8};
code_to_key_type(?KEY_TYPE_UINT16) -> {ok, uint16};
code_to_key_type(?KEY_TYPE_UINT32) -> {ok, uint32};
code_to_key_type(?KEY_TYPE_UINT64) -> {ok, uint64};
code_to_key_type(Code) -> {error, {unsupported_key_type, Code}}.

%% @doc Convert parsed type back to binary string for decoding.
-spec type_to_binary(clickhouse_erl_types_composite:column_type()) -> binary().
type_to_binary(uint8) ->
    <<"UInt8">>;
type_to_binary(uint16) ->
    <<"UInt16">>;
type_to_binary(uint32) ->
    <<"UInt32">>;
type_to_binary(uint64) ->
    <<"UInt64">>;
type_to_binary(int8) ->
    <<"Int8">>;
type_to_binary(int16) ->
    <<"Int16">>;
type_to_binary(int32) ->
    <<"Int32">>;
type_to_binary(int64) ->
    <<"Int64">>;
type_to_binary(float32) ->
    <<"Float32">>;
type_to_binary(float64) ->
    <<"Float64">>;
type_to_binary(string) ->
    <<"String">>;
type_to_binary(date) ->
    <<"Date">>;
type_to_binary(date32) ->
    <<"Date32">>;
type_to_binary(datetime) ->
    <<"DateTime">>;
type_to_binary(datetime64) ->
    <<"DateTime64">>;
type_to_binary({tuple, ElementTypes}) ->
    %% Reconstruct tuple type string
    ElementStrs = [type_to_binary(T) || T <- ElementTypes],
    <<"Tuple(", (iolist_to_binary(lists:join(<<", ">>, ElementStrs)))/binary, ")">>;
type_to_binary({array, ElemType}) ->
    <<"Array(", (type_to_binary(ElemType))/binary, ")">>;
type_to_binary({map, KeyType, ValueType}) ->
    <<"Map(", (type_to_binary(KeyType))/binary, ", ", (type_to_binary(ValueType))/binary, ")">>;
type_to_binary(Type) ->
    %% Fallback for unknown types
    atom_to_binary(Type).
