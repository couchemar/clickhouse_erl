%% @doc Special ClickHouse types encoding and decoding
%%
%% This module handles encoding and decoding of special ClickHouse types that don't
%% fit into standard categories. Each type serves a specific purpose in the ClickHouse
%% type system.
%%
%% Supported Types:
%% - Nothing: NULL placeholder type (single zero byte)
%% - Point: 2D geometric point (tuple of two Float64 values)
%% - Interval: Time interval with scale (Int64 with scale metadata)
%% - JSON: Structured JSON data (string encoding with optional parsing)
%%
%% Type Representations:
%% - Nothing: `null` or `undefined` atom
%% - Point: `{X :: float(), Y :: float()}` tuple
%% - Interval: `{interval, Scale :: atom(), Value :: integer()}` tuple or integer
%% - JSON: Binary string (raw JSON), map, or list
%%
%% Encoding Formats:
%% - Nothing: 1 byte (0x00)
%% - Point: 16 bytes (two Float64 values, little-endian)
%% - Interval: 8 bytes (Int64, little-endian)
%% - JSON: String encoding (varint length + UTF-8 bytes)
%%
%% JSON Serialization Modes:
%% - String Serialization (Version 1): Default and recommended
%%   * Stores JSON as UTF-8 string
%%   * Simple, reliable, widely compatible
%%   * Supported by all ClickHouse versions
%%   * Used by default in clickhouse_erl
%% - Object Serialization (Version 0): Advanced, not supported
%%   * Columnar storage of JSON structure
%%   * Requires Dynamic type support
%%   * Complex implementation (2300-3400 lines of code)
%%   * Not supported by ch-go reference implementation
%%   * Out of scope for clickhouse_erl
%%
%% Usage Examples:
%%
%% ```
%% % Nothing type - accepts any value
%% {ok, <<0>>} = encode_nothing(anything).
%% {ok, null, Rest} = decode_nothing(<<0>>).
%%
%% % Point type
%% {ok, Binary} = encode_point({1.5, 2.5}).
%% {ok, {1.5, 2.5}, Rest} = decode_point(Binary).
%%
%% % Interval type with scale
%% {ok, Binary2} = encode_interval({interval, second, 3600}, second).
%% {ok, {interval, second, 3600}, Rest} = decode_interval(Binary2, second).
%%
%% % Interval from integer
%% {ok, Binary3} = encode_interval(7200, second).
%%
%% % Parse interval type string
%% {ok, {interval, second}} = parse_interval_type(<<"IntervalSecond">>).
%% {ok, {interval, day}} = parse_interval_type(<<"IntervalDay">>).
%%
%% % JSON from string
%% {ok, Binary4} = encode_json(<<"{\"key\":\"value\"}">>).
%% {ok, <<"{\"key\":\"value\"}">>, Rest} = decode_json(Binary4).
%%
%% % JSON from map (auto-encoded)
%% {ok, Binary5} = encode_json(#{key => <<"value">>, count => 42}).
%%
%% % JSON from list (auto-encoded)
%% {ok, Binary6} = encode_json([{key, <<"value">>}, {count, 42}]).
%%
%% % Decode JSON with parsing
%% {ok, #{<<"key">> := <<"value">>}, Rest} = decode_json(Binary4, #{parse => true}).
%%
%% % Invalid JSON syntax error
%% {error, {invalid_json_syntax, _}} = encode_json(<<"{invalid json}">>).
%%
%% % Invalid interval scale error
%% {error, {invalid_interval_scale, _}} = encode_interval({interval, invalid, 100}, invalid).
%% '''
%%
%% Error Cases:
%% - {truncated_data, Details} - Binary too short for decoding
%% - {invalid_point_value, Value} - Invalid point format or non-float values
%% - {invalid_interval_scale, Scale} - Unsupported interval scale
%% - {invalid_interval_value, Value} - Invalid interval format
%% - {invalid_json_syntax, Value} - Invalid JSON syntax
%% - {json_encode_error, Reason} - JSON encoding failed
%% - {json_decode_error, Reason} - JSON decoding failed
%%
%% All functions follow the standard error tuple pattern:
%% {ok, Result} | {error, Reason}
-module(clickhouse_erl_types_special).

%% API exports
-export([
    %% Nothing type
    encode_nothing/1,
    decode_nothing/1,
    %% Point type
    encode_point/1,
    decode_point/1,
    %% Interval type
    encode_interval/2,
    decode_interval/2,
    parse_interval_type/1,
    %% JSON type
    encode_json/1,
    decode_json/1,
    decode_json/2,
    %% Column encoding/decoding
    encode_nothing_column/1,
    decode_nothing_column/2,
    encode_point_column/1,
    decode_point_column/2,
    encode_interval_column/2,
    decode_interval_column/3,
    encode_json_column/1,
    decode_json_column/2
]).

%% Includes
-include_lib("kernel/include/logger.hrl").

%% Type definitions
-export_type([
    nothing_value/0,
    point_value/0,
    interval_scale/0,
    interval_value/0,
    json_value/0
]).

-type nothing_value() :: null | undefined.
-type point_value() :: {X :: float(), Y :: float()}.
-type interval_scale() :: second | minute | hour | day | week | month | quarter | year.
-type interval_value() :: {interval, interval_scale(), integer()} | integer().
-type json_value() :: binary() | map() | list().

%%%===================================================================
%%% API - Nothing Type
%%%===================================================================

%% @doc Encode Nothing type value
%% Accepts any value (ignored) and encodes as single zero byte.
%% Nothing is primarily used with Nullable(Nothing) for NULL-only columns.
-spec encode_nothing(term()) -> {ok, binary()} | {error, term()}.
encode_nothing(_Value) ->
    {ok, <<0>>}.

%% @doc Decode Nothing type value
%% Parses single zero byte and returns null atom.
-spec decode_nothing(binary()) -> {ok, nothing_value(), binary()} | {error, term()}.
decode_nothing(<<0, Rest/binary>>) ->
    {ok, null, Rest};
decode_nothing(Binary) when byte_size(Binary) < 1 ->
    {error,
        {truncated_data, #{
            expected_bytes => 1,
            actual_bytes => byte_size(Binary),
            type => nothing
        }}};
decode_nothing(<<Byte, _/binary>>) ->
    {error,
        {invalid_value, #{
            value => Byte,
            expected => 0,
            type => nothing
        }}}.

%%%===================================================================
%%% API - Point Type
%%%===================================================================

%% @doc Encode Point type value
%% Accepts {X, Y} tuple where X and Y are floats.
%% Encodes as two Float64 values (16 bytes total, little-endian).
-spec encode_point(point_value()) -> {ok, binary()} | {error, term()}.
encode_point({X, Y}) when is_float(X), is_float(Y) ->
    {ok, <<X:64/float-little, Y:64/float-little>>};
encode_point({X, Y}) when is_number(X), is_number(Y) ->
    %% Convert integers to floats
    encode_point({float(X), float(Y)});
encode_point(Value) ->
    {error,
        {invalid_format, #{
            value => Value,
            expected_format => "{X, Y} where X and Y are numbers",
            type => point
        }}}.

%% @doc Decode Point type value
%% Parses 16 bytes (two Float64 values) and returns {X, Y} tuple.
-spec decode_point(binary()) -> {ok, point_value(), binary()} | {error, term()}.
decode_point(<<X:64/float-little, Y:64/float-little, Rest/binary>>) ->
    {ok, {X, Y}, Rest};
decode_point(Binary) when byte_size(Binary) < 16 ->
    {error,
        {truncated_data, #{
            expected_bytes => 16,
            actual_bytes => byte_size(Binary),
            type => point
        }}}.

%%%===================================================================
%%% API - Interval Type
%%%===================================================================

%% @doc Encode Interval type value
%% Accepts {interval, Scale, Value} tuple or integer.
%% Encodes as Int64 (8 bytes, little-endian).
%% Scale must be one of: second, minute, hour, day, week, month, quarter, year.
-spec encode_interval(interval_value(), interval_scale()) -> {ok, binary()} | {error, term()}.
encode_interval({interval, Scale, Value}, ExpectedScale) when is_integer(Value) ->
    case validate_interval_scale(Scale) of
        ok ->
            case Scale =:= ExpectedScale of
                true ->
                    {ok, <<Value:64/little-signed>>};
                false ->
                    {error,
                        {scale_mismatch, #{
                            provided_scale => Scale,
                            expected_scale => ExpectedScale,
                            type => interval
                        }}}
            end;
        {error, Reason} ->
            {error, Reason}
    end;
encode_interval(Value, Scale) when is_integer(Value) ->
    %% Accept plain integer with scale from type definition
    case validate_interval_scale(Scale) of
        ok ->
            {ok, <<Value:64/little-signed>>};
        {error, Reason} ->
            {error, Reason}
    end;
encode_interval(Value, _Scale) ->
    {error,
        {invalid_format, #{
            value => Value,
            expected_format => "{interval, Scale, Value} or integer",
            type => interval
        }}}.

%% @doc Decode Interval type value
%% Parses Int64 binary and returns {interval, Scale, Value} tuple.
-spec decode_interval(binary(), interval_scale()) ->
    {ok, interval_value(), binary()} | {error, term()}.
decode_interval(<<Value:64/little-signed, Rest/binary>>, Scale) ->
    case validate_interval_scale(Scale) of
        ok ->
            {ok, {interval, Scale, Value}, Rest};
        {error, Reason} ->
            {error, Reason}
    end;
decode_interval(Binary, _Scale) when byte_size(Binary) < 8 ->
    {error,
        {truncated_data, #{
            expected_bytes => 8,
            actual_bytes => byte_size(Binary),
            type => interval
        }}}.

%% @doc Parse interval type string to extract scale
%% Examples: "IntervalSecond" -> {ok, {interval, second}}
%%           "IntervalDay" -> {ok, {interval, day}}
-spec parse_interval_type(binary()) -> {ok, {interval, interval_scale()}} | {error, term()}.
parse_interval_type(<<"IntervalSecond">>) ->
    {ok, {interval, second}};
parse_interval_type(<<"IntervalMinute">>) ->
    {ok, {interval, minute}};
parse_interval_type(<<"IntervalHour">>) ->
    {ok, {interval, hour}};
parse_interval_type(<<"IntervalDay">>) ->
    {ok, {interval, day}};
parse_interval_type(<<"IntervalWeek">>) ->
    {ok, {interval, week}};
parse_interval_type(<<"IntervalMonth">>) ->
    {ok, {interval, month}};
parse_interval_type(<<"IntervalQuarter">>) ->
    {ok, {interval, quarter}};
parse_interval_type(<<"IntervalYear">>) ->
    {ok, {interval, year}};
parse_interval_type(TypeStr) ->
    {error,
        {invalid_interval_type, #{
            type_string => TypeStr,
            supported_types => [
                <<"IntervalSecond">>,
                <<"IntervalMinute">>,
                <<"IntervalHour">>,
                <<"IntervalDay">>,
                <<"IntervalWeek">>,
                <<"IntervalMonth">>,
                <<"IntervalQuarter">>,
                <<"IntervalYear">>
            ]
        }}}.

%%%===================================================================
%%% API - JSON Type
%%%===================================================================

%% @doc Encode JSON type value
%% Accepts binary string, map, or list.
%% Maps and lists are auto-encoded to JSON using json:encode/1.
%% Uses string encoding (varint length + UTF-8 bytes).
-spec encode_json(json_value()) -> {ok, binary()} | {error, term()}.
encode_json(Value) when is_binary(Value) ->
    %% Validate JSON syntax by attempting to decode
    try json:decode(Value) of
        _ ->
            encode_json_string(Value)
    catch
        error:Reason ->
            {error, {invalid_json, #{reason => Reason}}}
    end;
encode_json(Value) when is_map(Value); is_list(Value) ->
    %% Convert map/list to JSON binary using stdlib json module
    try json:encode(Value) of
        JsonIolist ->
            %% json:encode/1 returns an iolist, convert to binary
            JsonBinary = iolist_to_binary(JsonIolist),
            encode_json_string(JsonBinary)
    catch
        error:Reason ->
            {error, {json_encoding_failed, #{reason => Reason}}}
    end;
encode_json(Value) ->
    {error,
        {invalid_format, #{
            value => Value,
            expected_format => "binary, map, or list",
            type => json
        }}}.

%% @doc Decode JSON type value (returns raw JSON binary)
%% Parses string encoding and returns JSON as binary string.
-spec decode_json(binary()) -> {ok, binary(), binary()} | {error, term()}.
decode_json(Binary) ->
    decode_json(Binary, #{parse => false}).

%% @doc Decode JSON type value with options
%% Options:
%%   - parse: true to parse JSON to Erlang terms, false for raw binary (default: false)
-spec decode_json(binary(), map()) -> {ok, json_value(), binary()} | {error, term()}.
decode_json(Binary, Opts) ->
    case decode_json_string(Binary) of
        {ok, JsonBinary, Rest} ->
            case maps:get(parse, Opts, false) of
                true ->
                    try json:decode(JsonBinary) of
                        Parsed ->
                            {ok, Parsed, Rest}
                    catch
                        error:Reason ->
                            {error, {json_parse_failed, #{reason => Reason}}}
                    end;
                false ->
                    {ok, JsonBinary, Rest}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Validate interval scale
-spec validate_interval_scale(interval_scale()) -> ok | {error, term()}.
validate_interval_scale(Scale) when
    Scale =:= second;
    Scale =:= minute;
    Scale =:= hour;
    Scale =:= day;
    Scale =:= week;
    Scale =:= month;
    Scale =:= quarter;
    Scale =:= year
->
    ok;
validate_interval_scale(Scale) ->
    {error,
        {invalid_scale, #{
            scale => Scale,
            supported_scales => [second, minute, hour, day, week, month, quarter, year],
            type => interval
        }}}.

%% @doc Encode string with varint length prefix
-spec encode_json_string(binary()) -> {ok, binary()}.
encode_json_string(Str) when is_binary(Str) ->
    Length = byte_size(Str),
    {ok, LengthBin} = encode_varint(Length),
    {ok, <<LengthBin/binary, Str/binary>>}.

%% @doc Decode string with varint length prefix
-spec decode_json_string(binary()) -> {ok, binary(), binary()} | {error, term()}.
decode_json_string(Binary) ->
    case decode_varint(Binary) of
        {ok, Length, Rest} ->
            case Rest of
                <<Str:Length/binary, Remaining/binary>> ->
                    {ok, Str, Remaining};
                _ ->
                    {error,
                        {truncated_data, #{
                            expected_bytes => Length,
                            actual_bytes => byte_size(Rest),
                            type => json
                        }}}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Encode varint (variable-length integer)
-spec encode_varint(non_neg_integer()) -> {ok, binary()}.
encode_varint(N) when N >= 0 ->
    {ok, encode_varint_loop(N, <<>>)}.

encode_varint_loop(N, Acc) when N < 128 ->
    <<Acc/binary, N>>;
encode_varint_loop(N, Acc) ->
    Byte = (N band 16#7F) bor 16#80,
    encode_varint_loop(N bsr 7, <<Acc/binary, Byte>>).

%% @doc Decode varint (variable-length integer)
-spec decode_varint(binary()) -> {ok, non_neg_integer(), binary()} | {error, term()}.
decode_varint(Binary) ->
    decode_varint_loop(Binary, 0, 0).

decode_varint_loop(<<Byte, Rest/binary>>, Acc, Shift) when Byte < 128 ->
    Value = Acc bor (Byte bsl Shift),
    {ok, Value, Rest};
decode_varint_loop(<<Byte, Rest/binary>>, Acc, Shift) ->
    Value = Acc bor ((Byte band 16#7F) bsl Shift),
    decode_varint_loop(Rest, Value, Shift + 7);
decode_varint_loop(<<>>, _Acc, _Shift) ->
    {error, {truncated_data, #{type => varint}}}.

%%%===================================================================
%%% Column Encoding/Decoding
%%%===================================================================

%% @doc Encode a column of Nothing values.
-spec encode_nothing_column([term()]) -> {ok, iolist()} | {error, term()}.
encode_nothing_column(Values) ->
    encode_column_loop(Values, fun encode_nothing/1, []).

%% @doc Decode a column of Nothing values.
-spec decode_nothing_column(binary(), non_neg_integer()) ->
    {ok, [term()], binary()} | {error, term()}.
decode_nothing_column(Binary, NumRows) ->
    decode_column_loop(Binary, NumRows, fun decode_nothing/1, []).

%% @doc Encode a column of Point values.
-spec encode_point_column([point_value()]) -> {ok, iolist()} | {error, term()}.
encode_point_column(Values) ->
    encode_column_loop(Values, fun encode_point/1, []).

%% @doc Decode a column of Point values.
-spec decode_point_column(binary(), non_neg_integer()) ->
    {ok, [point_value()], binary()} | {error, term()}.
decode_point_column(Binary, NumRows) ->
    decode_column_loop(Binary, NumRows, fun decode_point/1, []).

%% @doc Encode a column of Interval values.
-spec encode_interval_column([interval_value()], interval_scale()) ->
    {ok, iolist()} | {error, term()}.
encode_interval_column(Values, Scale) ->
    encode_interval_column_loop(Values, Scale, []).

%% @doc Decode a column of Interval values.
-spec decode_interval_column(binary(), interval_scale(), non_neg_integer()) ->
    {ok, [interval_value()], binary()} | {error, term()}.
decode_interval_column(Binary, Scale, NumRows) ->
    decode_interval_column_loop(Binary, Scale, NumRows, []).

%% @doc Encode a column of JSON values.
-spec encode_json_column([json_value()]) -> {ok, iolist()} | {error, term()}.
encode_json_column(Values) ->
    encode_column_loop(Values, fun encode_json/1, []).

%% @doc Decode a column of JSON values.
-spec decode_json_column(binary(), non_neg_integer()) ->
    {ok, [json_value()], binary()} | {error, term()}.
decode_json_column(Binary, NumRows) ->
    decode_column_loop(Binary, NumRows, fun decode_json/1, []).

%%%===================================================================
%%% Internal Helper Functions
%%%===================================================================

%% @doc Helper to encode a column of values using an encoder function.
-spec encode_column_loop([term()], fun((term()) -> {ok, binary()} | {error, term()}), iolist()) ->
    {ok, iolist()} | {error, term()}.
encode_column_loop([], _EncodeFun, Acc) ->
    {ok, lists:reverse(Acc)};
encode_column_loop([Value | Rest], EncodeFun, Acc) ->
    case EncodeFun(Value) of
        {ok, Encoded} ->
            encode_column_loop(Rest, EncodeFun, [Encoded | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Helper to decode a column of values using a decoder function.
-spec decode_column_loop(
    binary(),
    non_neg_integer(),
    fun((binary()) -> {ok, term(), binary()} | {error, term()}),
    [term()]
) ->
    {ok, [term()], binary()} | {error, term()}.
decode_column_loop(Binary, 0, _DecodeFun, Acc) ->
    {ok, lists:reverse(Acc), Binary};
decode_column_loop(Binary, N, DecodeFun, Acc) ->
    case DecodeFun(Binary) of
        {ok, Value, Rest} ->
            decode_column_loop(Rest, N - 1, DecodeFun, [Value | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Helper to encode a column of interval values with scale.
-spec encode_interval_column_loop([interval_value()], interval_scale(), iolist()) ->
    {ok, iolist()} | {error, term()}.
encode_interval_column_loop([], _Scale, Acc) ->
    {ok, lists:reverse(Acc)};
encode_interval_column_loop([Value | Rest], Scale, Acc) ->
    case encode_interval(Value, Scale) of
        {ok, Encoded} ->
            encode_interval_column_loop(Rest, Scale, [Encoded | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Helper to decode a column of interval values with scale.
-spec decode_interval_column_loop(
    binary(),
    interval_scale(),
    non_neg_integer(),
    [interval_value()]
) ->
    {ok, [interval_value()], binary()} | {error, term()}.
decode_interval_column_loop(Binary, _Scale, 0, Acc) ->
    {ok, lists:reverse(Acc), Binary};
decode_interval_column_loop(Binary, Scale, N, Acc) ->
    case decode_interval(Binary, Scale) of
        {ok, Value, Rest} ->
            decode_interval_column_loop(Rest, Scale, N - 1, [Value | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.
