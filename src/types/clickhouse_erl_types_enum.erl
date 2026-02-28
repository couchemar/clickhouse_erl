%% @doc Enum type encoding and decoding for ClickHouse.
%%
%% Supports Enum8 and Enum16 types with named value mappings.
%% Enums provide type-safe categorical data with efficient storage.
%%
%% Type Representations:
%% - Input: Atom, binary string, or integer
%% - Output: Atom (default) or binary string
%% - Mappings: #{name => value} where name is atom/binary, value is integer
%%
%% Encoding Format:
%% - Enum8: Int8 encoding (1 byte, signed -128 to 127)
%% - Enum16: Int16 encoding (2 bytes, little-endian, signed -32768 to 32767)
%%
%% Type Syntax:
%% - Enum8('name1' = 1, 'name2' = 2)
%% - Enum16('active' = 1, 'inactive' = 0, 'deleted' = -1)
%%
%% Usage Examples:
%%
%% ```
%% % Parse enum type string
%% {ok, {enum8, Mappings}} = parse_enum_type(<<"Enum8('active' = 1, 'inactive' = 0)">>).
%% % Mappings = #{active => 1, inactive => 0}
%%
%% % Encode enum value (atom)
%% {ok, Binary} = encode_enum8(active, Mappings).
%% % Binary = <<1>>
%%
%% % Encode enum value (binary string)
%% {ok, Binary2} = encode_enum8(<<"inactive">>, Mappings).
%% % Binary2 = <<0>>
%%
%% % Encode enum value (integer)
%% {ok, Binary3} = encode_enum8(1, Mappings).
%% % Binary3 = <<1>>
%%
%% % Decode enum value
%% {ok, active, Rest} = decode_enum8(Binary, Mappings).
%%
%% % Invalid enum value error
%% {error, {invalid_enum_value, _}} = encode_enum8(unknown, Mappings).
%%
%% % Enum16 with negative values
%% {ok, {enum16, StatusMap}} = parse_enum_type(<<"Enum16('active' = 1, 'suspended' = -1)">>).
%% {ok, <<255, 255>>} = encode_enum16(suspended, StatusMap).
%% '''
%%
%% Error Cases:
%% - {invalid_enum_value, Details} - Value not in defined mappings
%% - {invalid_enum_type, Type} - Invalid type string format
%% - {truncated_data, Details} - Binary too short for decoding
-module(clickhouse_erl_types_enum).

%% API exports
-export([encode_enum8/2, decode_enum8/2]).
-export([encode_enum16/2, decode_enum16/2]).
-export([parse_enum_type/1]).
-export([
    encode_enum8_column/2,
    decode_enum8_column/3,
    encode_enum16_column/2,
    decode_enum16_column/3
]).

%% Includes
-include_lib("kernel/include/logger.hrl").

%% Type definitions and exports
-export_type([enum_value/0, enum_mappings/0, enum_type/0]).

-type enum_value() :: atom() | binary() | integer().
-type enum_mappings() :: #{atom() | binary() => integer()}.
-type enum_type() :: {enum8, enum_mappings()} | {enum16, enum_mappings()}.

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Encode an Enum8 value.
%% Accepts atom, binary string, or integer value.
%% Returns 1-byte signed integer encoding.
-spec encode_enum8(enum_value(), enum_mappings()) -> {ok, binary()} | {error, term()}.
encode_enum8(Value, Mappings) when is_integer(Value) ->
    % Direct integer value - validate it exists in mappings
    case is_valid_enum_value(Value, Mappings) of
        true ->
            case clickhouse_erl_types_integer:encode_int8(Value) of
                Binary when is_binary(Binary) -> {ok, Binary};
                {error, Reason} -> {error, Reason}
            end;
        false ->
            {error, {invalid_enum_value, #{value => Value, mappings => Mappings}}}
    end;
encode_enum8(Value, Mappings) when is_atom(Value) orelse is_binary(Value) ->
    % Named value - look up in mappings
    case maps:get(Value, Mappings, undefined) of
        undefined ->
            {error, {enum_value_not_found, #{value => Value, mappings => Mappings}}};
        IntValue ->
            case clickhouse_erl_types_integer:encode_int8(IntValue) of
                Binary when is_binary(Binary) -> {ok, Binary};
                {error, Reason} -> {error, Reason}
            end
    end;
encode_enum8(Value, _Mappings) ->
    {error,
        {invalid_enum_value_type, #{value => Value, expected_types => [atom, binary, integer]}}}.

%% @doc Decode an Enum8 value.
%% Parses 1-byte signed integer and returns atom or binary.
-spec decode_enum8(binary(), enum_mappings()) ->
    {ok, atom() | binary(), binary()} | {error, term()}.
decode_enum8(Binary, Mappings) ->
    case clickhouse_erl_types_integer:decode_int8(Binary) of
        {ok, IntValue, Rest} ->
            case reverse_lookup_enum(IntValue, Mappings) of
                {ok, Name} -> {ok, Name, Rest};
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Encode an Enum16 value.
%% Accepts atom, binary string, or integer value.
%% Returns 2-byte little-endian signed integer encoding.
-spec encode_enum16(enum_value(), enum_mappings()) -> {ok, binary()} | {error, term()}.
encode_enum16(Value, Mappings) when is_integer(Value) ->
    % Direct integer value - validate it exists in mappings
    case is_valid_enum_value(Value, Mappings) of
        true ->
            case clickhouse_erl_types_integer:encode_int16(Value) of
                Binary when is_binary(Binary) -> {ok, Binary};
                {error, Reason} -> {error, Reason}
            end;
        false ->
            {error, {invalid_enum_value, #{value => Value, mappings => Mappings}}}
    end;
encode_enum16(Value, Mappings) when is_atom(Value) orelse is_binary(Value) ->
    % Named value - look up in mappings
    case maps:get(Value, Mappings, undefined) of
        undefined ->
            {error, {enum_value_not_found, #{value => Value, mappings => Mappings}}};
        IntValue ->
            case clickhouse_erl_types_integer:encode_int16(IntValue) of
                Binary when is_binary(Binary) -> {ok, Binary};
                {error, Reason} -> {error, Reason}
            end
    end;
encode_enum16(Value, _Mappings) ->
    {error,
        {invalid_enum_value_type, #{value => Value, expected_types => [atom, binary, integer]}}}.

%% @doc Decode an Enum16 value.
%% Parses 2-byte little-endian signed integer and returns atom or binary.
-spec decode_enum16(binary(), enum_mappings()) ->
    {ok, atom() | binary(), binary()} | {error, term()}.
decode_enum16(Binary, Mappings) ->
    case clickhouse_erl_types_integer:decode_int16(Binary) of
        {ok, IntValue, Rest} ->
            case reverse_lookup_enum(IntValue, Mappings) of
                {ok, Name} -> {ok, Name, Rest};
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Parse enum type string to extract name-value mappings.
%% Supports formats:
%%   - "Enum8('active' = 1, 'inactive' = 0)"
%%   - "Enum16('name1' = 1, 'name2' = 2, 'name3' = -1)"
%% Returns {ok, {enum8 | enum16, Mappings}} or {error, Reason}.
-spec parse_enum_type(binary()) -> {ok, enum_type()} | {error, term()}.
parse_enum_type(TypeString) when is_binary(TypeString) ->
    case parse_enum_header(TypeString) of
        {ok, EnumType, Rest} ->
            case parse_enum_mappings(Rest) of
                {ok, Mappings} ->
                    {ok, {EnumType, Mappings}};
                {error, Reason} ->
                    {error, {parse_mappings_failed, Reason}}
            end;
        {error, Reason} ->
            {error, {parse_header_failed, Reason}}
    end;
parse_enum_type(TypeString) ->
    {error, {invalid_type, TypeString}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Parse enum type header (Enum8 or Enum16).
-spec parse_enum_header(binary()) -> {ok, enum8 | enum16, binary()} | {error, term()}.
parse_enum_header(<<"Enum8(", Rest/binary>>) ->
    {ok, enum8, Rest};
parse_enum_header(<<"Enum16(", Rest/binary>>) ->
    {ok, enum16, Rest};
parse_enum_header(Other) ->
    {error, {invalid_enum_type, Other}}.

%% @doc Parse enum value mappings from type string.
%% Format: 'name1' = 1, 'name2' = 2, 'name3' = -1)
-spec parse_enum_mappings(binary()) -> {ok, enum_mappings()} | {error, term()}.
parse_enum_mappings(Binary) ->
    case parse_mappings_loop(Binary, #{}) of
        {ok, Mappings} ->
            {ok, Mappings};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Parse enum mappings in a loop.
-spec parse_mappings_loop(binary(), enum_mappings()) -> {ok, enum_mappings()} | {error, term()}.
parse_mappings_loop(<<$), _Rest/binary>>, Mappings) when map_size(Mappings) > 0 ->
    {ok, Mappings};
parse_mappings_loop(Binary, Mappings) ->
    case parse_single_mapping(Binary) of
        {ok, Name, Value, Rest} ->
            NewMappings = maps:put(Name, Value, Mappings),
            case Rest of
                <<$,, $\s, RestAfterComma/binary>> ->
                    parse_mappings_loop(RestAfterComma, NewMappings);
                <<$,, RestAfterComma/binary>> ->
                    parse_mappings_loop(RestAfterComma, NewMappings);
                <<$), _/binary>> ->
                    {ok, NewMappings};
                _ ->
                    {error, {unexpected_token, Rest}}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Parse a single enum mapping: 'name' = value
-spec parse_single_mapping(binary()) -> {ok, atom(), integer(), binary()} | {error, term()}.
parse_single_mapping(<<$', Rest/binary>>) ->
    case binary:split(Rest, <<"'">>) of
        [NameBin, AfterName] ->
            Name = binary_to_atom(NameBin, utf8),
            case parse_equals_and_value(AfterName) of
                {ok, Value, Remaining} ->
                    {ok, Name, Value, Remaining};
                {error, Reason} ->
                    {error, Reason}
            end;
        _ ->
            {error, missing_closing_quote}
    end;
parse_single_mapping(Other) ->
    {error, {expected_quote, Other}}.

%% @doc Parse " = value" part of mapping.
-spec parse_equals_and_value(binary()) -> {ok, integer(), binary()} | {error, term()}.
parse_equals_and_value(<<$\s, $=, $\s, Rest/binary>>) ->
    parse_integer_value(Rest);
parse_equals_and_value(<<$=, $\s, Rest/binary>>) ->
    parse_integer_value(Rest);
parse_equals_and_value(<<$\s, $=, Rest/binary>>) ->
    parse_integer_value(Rest);
parse_equals_and_value(<<$=, Rest/binary>>) ->
    parse_integer_value(Rest);
parse_equals_and_value(Other) ->
    {error, {expected_equals, Other}}.

%% @doc Parse integer value (supports negative numbers).
-spec parse_integer_value(binary()) -> {ok, integer(), binary()} | {error, term()}.
parse_integer_value(<<$-, Rest/binary>>) ->
    case parse_digits(Rest) of
        {ok, Digits, Remaining} ->
            Value = -binary_to_integer(Digits),
            {ok, Value, Remaining};
        {error, Reason} ->
            {error, Reason}
    end;
parse_integer_value(Binary) ->
    case parse_digits(Binary) of
        {ok, Digits, Remaining} ->
            Value = binary_to_integer(Digits),
            {ok, Value, Remaining};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Parse consecutive digits.
-spec parse_digits(binary()) -> {ok, binary(), binary()} | {error, term()}.
parse_digits(Binary) ->
    parse_digits_loop(Binary, <<>>).

%% @doc Parse digits in a loop.
-spec parse_digits_loop(binary(), binary()) -> {ok, binary(), binary()} | {error, term()}.
parse_digits_loop(<<Char, Rest/binary>>, Acc) when Char >= $0, Char =< $9 ->
    parse_digits_loop(Rest, <<Acc/binary, Char>>);
parse_digits_loop(Rest, Acc) when byte_size(Acc) > 0 ->
    {ok, Acc, Rest};
parse_digits_loop(_Rest, <<>>) ->
    {error, no_digits_found}.

%% @doc Check if an integer value exists in enum mappings.
-spec is_valid_enum_value(integer(), enum_mappings()) -> boolean().
is_valid_enum_value(Value, Mappings) ->
    lists:member(Value, maps:values(Mappings)).

%% @doc Reverse lookup: find name for integer value in enum mappings.
-spec reverse_lookup_enum(integer(), enum_mappings()) -> {ok, atom() | binary()} | {error, term()}.
reverse_lookup_enum(IntValue, Mappings) ->
    case
        maps:fold(
            fun(Name, Value, Acc) ->
                case Value =:= IntValue of
                    true -> {found, Name};
                    false -> Acc
                end
            end,
            not_found,
            Mappings
        )
    of
        {found, Name} ->
            {ok, Name};
        not_found ->
            {error, {enum_value_not_in_mappings, #{value => IntValue, mappings => Mappings}}}
    end.

%%%===================================================================
%%% Column Encoding/Decoding
%%%===================================================================

%% @doc Encode a column of Enum8 values.
-spec encode_enum8_column([enum_value()], enum_mappings()) -> {ok, iolist()} | {error, term()}.
encode_enum8_column(Values, Mappings) ->
    encode_enum_column_loop(Values, Mappings, fun encode_enum8/2, []).

%% @doc Decode a column of Enum8 values.
-spec decode_enum8_column(binary(), enum_mappings(), non_neg_integer()) ->
    {ok, [enum_value()], binary()} | {error, term()}.
decode_enum8_column(Binary, Mappings, NumRows) ->
    decode_enum_column_loop(Binary, Mappings, NumRows, fun decode_enum8/2, []).

%% @doc Encode a column of Enum16 values.
-spec encode_enum16_column([enum_value()], enum_mappings()) -> {ok, iolist()} | {error, term()}.
encode_enum16_column(Values, Mappings) ->
    encode_enum_column_loop(Values, Mappings, fun encode_enum16/2, []).

%% @doc Decode a column of Enum16 values.
-spec decode_enum16_column(binary(), enum_mappings(), non_neg_integer()) ->
    {ok, [enum_value()], binary()} | {error, term()}.
decode_enum16_column(Binary, Mappings, NumRows) ->
    decode_enum_column_loop(Binary, Mappings, NumRows, fun decode_enum16/2, []).

%%%===================================================================
%%% Internal Helper Functions
%%%===================================================================

%% @doc Helper to encode a column of enum values.
-spec encode_enum_column_loop(
    [enum_value()],
    enum_mappings(),
    fun((enum_value(), enum_mappings()) -> {ok, binary()} | {error, term()}),
    iolist()
) ->
    {ok, iolist()} | {error, term()}.
encode_enum_column_loop([], _Mappings, _EncodeFun, Acc) ->
    {ok, lists:reverse(Acc)};
encode_enum_column_loop([Value | Rest], Mappings, EncodeFun, Acc) ->
    case EncodeFun(Value, Mappings) of
        {ok, Encoded} ->
            encode_enum_column_loop(Rest, Mappings, EncodeFun, [Encoded | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Helper to decode a column of enum values.
-spec decode_enum_column_loop(
    binary(),
    enum_mappings(),
    non_neg_integer(),
    fun((binary(), enum_mappings()) -> {ok, enum_value(), binary()} | {error, term()}),
    [enum_value()]
) ->
    {ok, [enum_value()], binary()} | {error, term()}.
decode_enum_column_loop(Binary, _Mappings, 0, _DecodeFun, Acc) ->
    {ok, lists:reverse(Acc), Binary};
decode_enum_column_loop(Binary, Mappings, N, DecodeFun, Acc) ->
    case DecodeFun(Binary, Mappings) of
        {ok, Value, Rest} ->
            decode_enum_column_loop(Rest, Mappings, N - 1, DecodeFun, [Value | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.
