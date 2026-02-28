-module(clickhouse_erl_protocol_server_hello).

%% Include protocol type definitions
-include("clickhouse_erl_protocol.hrl").

-export([decode/1, decode/2]).

%% Type exports
-export_type([server_hello_info/0]).

%% @doc Decode a Server Hello message.
%%
%% Decodes according to ClickHouse protocol specification using feature detection.
-spec decode(binary()) -> {ok, server_hello_info()} | {error, term()}.
decode(Binary) ->
    decode(Binary, ?PROTOCOL_VERSION).

%% @doc Decode a Server Hello message with version-aware feature detection.
-spec decode(binary(), integer()) -> {ok, server_hello_info()} | {error, term()}.
decode(Binary, ClientVersion) ->
    maybe
        {ok, Name, Rest1} ?= clickhouse_erl_types_primitive:decode_string(Binary),
        {ok, VersionMajor, Rest2} ?= clickhouse_erl_types_primitive:decode_varint(Rest1),
        {ok, VersionMinor, Rest3} ?= clickhouse_erl_types_primitive:decode_varint(Rest2),
        {ok, Revision, Rest4} ?= clickhouse_erl_types_primitive:decode_varint(Rest3),
        ServerInfo = #{
            name => Name,
            version_major => VersionMajor,
            version_minor => VersionMinor,
            revision => Revision
        },
        {ok, FinalServerInfo} ?= decode_optional_fields(ServerInfo, Rest4, ClientVersion),
        {ok, FinalServerInfo}
    else
        {error, Reason} -> {error, {decoding_error, Reason}}
    end.

decode_optional_fields(ServerInfo, Rest, ClientVersion) ->
    %% Use feature detection like ch-go does
    %% Decode timezone if FeatureTimezone.In(ClientVersion)
    maybe
        {ok, ServerInfo1, Rest1} ?= decode_optional_timezone(ServerInfo, Rest, ClientVersion),
        {ok, ServerInfo2, Rest2} ?= decode_optional_display_name(ServerInfo1, Rest1, ClientVersion),
        {ok, ServerInfo3, _Rest3} ?=
            decode_optional_version_patch(ServerInfo2, Rest2, ClientVersion),
        {ok, ServerInfo3}
    else
        {error, Reason} -> {error, Reason}
    end.

decode_optional_timezone(ServerInfo, Rest, ClientVersion) ->
    case clickhouse_erl_protocol_features:has_feature(timezone, ClientVersion) of
        true ->
            case clickhouse_erl_types_primitive:decode_string(Rest) of
                {ok, Timezone, RestAfterTZ} ->
                    {ok, ServerInfo#{timezone => Timezone}, RestAfterTZ};
                {error, DecodeReason} ->
                    {error, DecodeReason}
            end;
        false ->
            {ok, ServerInfo, Rest}
    end.

decode_optional_display_name(ServerInfo, Rest, ClientVersion) ->
    case clickhouse_erl_protocol_features:has_feature(display_name, ClientVersion) of
        true ->
            case clickhouse_erl_types_primitive:decode_string(Rest) of
                {ok, DisplayName, RestAfterDN} ->
                    {ok, ServerInfo#{display_name => DisplayName}, RestAfterDN};
                {error, DecodeReason} ->
                    {error, DecodeReason}
            end;
        false ->
            {ok, ServerInfo, Rest}
    end.

decode_optional_version_patch(ServerInfo, Rest, ClientVersion) ->
    case clickhouse_erl_protocol_features:has_feature(version_patch, ClientVersion) of
        true ->
            case clickhouse_erl_types_primitive:decode_varint(Rest) of
                {ok, VersionPatch, RestAfterPatch} ->
                    {ok, ServerInfo#{version_patch => VersionPatch}, RestAfterPatch};
                {error, DecodeReason} ->
                    {error, DecodeReason}
            end;
        false ->
            {ok, ServerInfo, Rest}
    end.
