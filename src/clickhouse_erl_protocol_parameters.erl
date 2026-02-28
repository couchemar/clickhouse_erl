-module(clickhouse_erl_protocol_parameters).

-export([decode/1, encode/1, encode_parameter/1, encode_parameters/1]).

-export_type([parameter/0, parameter_list/0]).

-type parameter() :: {Key :: binary(), Value :: binary()}.
-type parameter_list() :: [parameter()].

%% @doc Decode parameters list (terminated by empty string)
-spec decode(binary()) -> {ok, [map()], binary()} | {error, term()}.
decode(Binary) ->
    decode(Binary, []).

decode(Binary, Acc) ->
    case clickhouse_erl_types_primitive:decode_string(Binary) of
        {ok, <<"">>, Rest} ->
            %% Empty string marks end of parameters
            {ok, lists:reverse(Acc), Rest};
        {ok, Key, Rest1} ->
            %% Decode flags (usually Custom flag = 0x02 for parameters)
            {ok, _Flags, Rest2} = clickhouse_erl_types_primitive:decode_varint(Rest1),
            %% Decode value
            {ok, Value, Rest3} = clickhouse_erl_types_primitive:decode_string(Rest2),

            Parameter = #{
                key => Key,
                value => Value
            },
            decode(Rest3, [Parameter | Acc]);
        {error, Reason} ->
            {error, {decode_parameters_failed, Reason}}
    end.

%% @doc Encode single parameter as: Key (string) + Flags (UVarInt 0x02) + Value (string)
%% Requirements: 3.1, 3.2, 3.5
%% CRITICAL: Parameter values must be quoted with single quotes (SQL literal format)
%% This matches ch-go behavior: fmt.Sprintf("'%v'", v)
-spec encode_parameter(parameter()) -> binary().
encode_parameter({Key, Value}) when is_binary(Key), is_binary(Value) ->
    EncodedKey = clickhouse_erl_types_primitive:encode_string(Key),
    % Custom flag
    Flags = clickhouse_erl_types_primitive:encode_varint(16#02),
    % Quote the value with single quotes (SQL literal format)
    QuotedValue = <<"'", Value/binary, "'">>,
    EncodedValue = clickhouse_erl_types_primitive:encode_string(QuotedValue),
    <<EncodedKey/binary, Flags/binary, EncodedValue/binary>>.

%% @doc Encode list of parameters using encode_parameter/1
%% Appends empty string terminator
%% Handle empty list: return only terminator
%% Requirements: 3.3, 3.4
-spec encode_parameters(parameter_list()) -> binary().
encode_parameters([]) ->
    % Empty list: just the terminator
    clickhouse_erl_types_primitive:encode_string(<<>>);
encode_parameters(Parameters) when is_list(Parameters) ->
    % Encode each parameter, then add terminator
    Encoded = lists:map(fun encode_parameter/1, Parameters),
    Terminator = clickhouse_erl_types_primitive:encode_string(<<>>),
    iolist_to_binary([Encoded, Terminator]).

%% @doc Encode parameters as settings with Custom flag (legacy map-based interface)
-spec encode([map()]) -> binary().
encode(Parameters) ->
    lists:foldl(
        fun(Parameter, Acc) ->
            Key = maps:get(key, Parameter),
            Value = maps:get(value, Parameter),

            %% Parameters are encoded as settings with Custom flag (0x02)
            EncodedParameter = <<
                (clickhouse_erl_types_primitive:encode_string(Key))/binary,
                % Custom flag
                (clickhouse_erl_types_primitive:encode_varint(16#02))/binary,
                (clickhouse_erl_types_primitive:encode_string(Value))/binary
            >>,

            <<Acc/binary, EncodedParameter/binary>>
        end,
        <<>>,
        Parameters
    ).
