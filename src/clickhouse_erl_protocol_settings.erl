-module(clickhouse_erl_protocol_settings).

-export([decode/1, encode/1]).

%% Type exports
-export_type([setting/0]).

-include("clickhouse_erl_protocol.hrl").

%% @doc Decode settings list (terminated by empty string)
-spec decode(binary()) -> {ok, [setting()], binary()} | {error, term()}.
decode(Binary) ->
    decode(Binary, []).

decode(Binary, Acc) ->
    case clickhouse_erl_types_primitive:decode_string(Binary) of
        {ok, <<"">>, Rest} ->
            %% Empty string marks end of settings
            {ok, lists:reverse(Acc), Rest};
        {ok, Key, Rest1} ->
            %% Decode flags
            case clickhouse_erl_types_primitive:decode_varint(Rest1) of
                {ok, Flags, Rest2} ->
                    %% Decode value
                    case clickhouse_erl_types_primitive:decode_string(Rest2) of
                        {ok, Value, Rest3} ->
                            %% Parse flags
                            Important = (Flags band 16#01) =/= 0,
                            Custom = (Flags band 16#02) =/= 0,
                            Obsolete = (Flags band 16#04) =/= 0,

                            Setting = #{
                                key => Key,
                                value => Value,
                                important => Important,
                                custom => Custom,
                                obsolete => Obsolete
                            },
                            decode(Rest3, [Setting | Acc]);
                        {error, Reason} ->
                            {error, {setting_value_decode_failed, Reason}}
                    end;
                {error, Reason} ->
                    {error, {setting_flags_decode_failed, Reason}}
            end;
        {error, Reason} ->
            {error, {setting_key_decode_failed, Reason}}
    end.

%% @doc Encode settings following Go Setting.Encode
-spec encode([setting()]) -> binary().
encode(Settings) ->
    lists:foldl(
        fun(Setting, Acc) ->
            Key = maps:get(key, Setting),
            Value = maps:get(value, Setting),
            Important = maps:get(important, Setting, false),
            Custom = maps:get(custom, Setting, false),
            Obsolete = maps:get(obsolete, Setting, false),

            %% Calculate flags
            ImportantFlag =
                case Important of
                    true -> 16#01;
                    false -> 0
                end,
            CustomFlag =
                case Custom of
                    true -> 16#02;
                    false -> 0
                end,
            ObsoleteFlag =
                case Obsolete of
                    true -> 16#04;
                    false -> 0
                end,
            Flags = ImportantFlag bor CustomFlag bor ObsoleteFlag,

            EncodedSetting = <<
                (clickhouse_erl_types_primitive:encode_string(Key))/binary,
                (clickhouse_erl_types_primitive:encode_varint(Flags))/binary,
                (clickhouse_erl_types_primitive:encode_string(Value))/binary
            >>,

            <<Acc/binary, EncodedSetting/binary>>
        end,
        <<>>,
        Settings
    ).
