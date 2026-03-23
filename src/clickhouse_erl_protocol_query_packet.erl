-module(clickhouse_erl_protocol_query_packet).

%% Public API
-export([encode/1, encode/2, decode/2, generate_query_id/1]).

-ignore_xref([encode/1, decode/2, generate_query_id/1]).

%% Export types
-export_type([query_info/0]).

-include("clickhouse_erl_protocol.hrl").
-include_lib("kernel/include/logger.hrl").

-spec encode(query_info()) -> {ok, binary()} | {error, term()}.
encode(QueryInfo) ->
    encode(QueryInfo, ?PROTOCOL_VERSION).

-spec encode(query_info(), integer()) -> {ok, binary()} | {error, term()}.
encode(QueryInfo, Version) ->
    QueryBody = maps:get(query_body, QueryInfo),

    %% Validate query body is not empty
    case string:trim(QueryBody) of
        <<>> ->
            {error, {validation_error, empty_query}};
        _ ->
            %% Follow exact Go implementation order from query.go EncodeAware
            Packet = encode_query_packet(QueryInfo, Version),
            {ok, Packet}
    end.

%% @doc Encode query packet following Go implementation exactly
encode_query_packet(QueryInfo, Version) ->
    QueryBody = maps:get(query_body, QueryInfo),
    ClientInfo = maps:get(client_info, QueryInfo, #{}),
    Settings = maps:get(settings, QueryInfo, []),
    Secret = maps:get(secret, QueryInfo, ""),
    Compression = maps:get(compression, QueryInfo, ?COMPRESSION_DISABLED),
    Parameters = maps:get(parameters, QueryInfo, []),

    %% 1. ClientCodeQuery (single byte)
    PacketType = <<?CLIENT_QUERY:8>>,

    %% 2. Query ID (string) - use provided or generate
    QueryId = generate_query_id(QueryInfo),
    EncodedQueryId = clickhouse_erl_types_primitive:encode_string(QueryId),

    %% 3. Client Info (if FeatureClientWriteInfo.In(version))
    EncodedClientInfo = maybe_encode_client_info(ClientInfo, Version),

    %% 4. Settings (if FeatureSettingsSerializedAsStrings.In(version))
    EncodedSettings = maybe_encode_settings(Settings, Version),

    %% 5. Settings terminator (empty string) - ALWAYS included if settings feature is enabled
    SettingsTerminator =
        case
            clickhouse_erl_protocol_features:has_feature(settings_serialized_as_strings, Version)
        of
            true -> clickhouse_erl_types_primitive:encode_string("");
            false -> <<>>
        end,

    %% 6. Secret (if FeatureInterServerSecret.In(version))
    EncodedSecret = maybe_encode_secret(Secret, Version),

    %% 7. Stage (always StageComplete)
    Stage = clickhouse_erl_types_primitive:encode_varint(?STAGE_COMPLETE),

    %% 8. Compression
    EncodedCompression = clickhouse_erl_types_primitive:encode_varint(Compression),

    %% 9. Query Body (string)
    EncodedQueryBody = clickhouse_erl_types_primitive:encode_string(QueryBody),

    %% 10. Parameters (if FeatureParameters.In(version))
    %% Note: encode_parameters already includes the terminator
    EncodedParameters = maybe_encode_parameters(Parameters, Version),

    <<
        PacketType/binary,
        EncodedQueryId/binary,
        EncodedClientInfo/binary,
        EncodedSettings/binary,
        SettingsTerminator/binary,
        EncodedSecret/binary,
        Stage/binary,
        EncodedCompression/binary,
        EncodedQueryBody/binary,
        EncodedParameters/binary
    >>.

%% @doc Generate or use provided query ID
%% If query_id is provided in QueryInfo, use it; otherwise generate a new UUID
-spec generate_query_id(query_info()) -> binary().
generate_query_id(QueryInfo) ->
    case maps:get(query_id, QueryInfo, undefined) of
        undefined ->
            clickhouse_erl_utils:generate_query_id();
        <<>> ->
            clickhouse_erl_utils:generate_query_id();
        "" ->
            clickhouse_erl_utils:generate_query_id();
        QueryId when is_binary(QueryId) ->
            QueryId;
        QueryId when is_list(QueryId) ->
            unicode:characters_to_binary(QueryId)
    end.

%% @doc Maybe encode client info based on protocol version
maybe_encode_client_info(ClientInfo, Version) ->
    case clickhouse_erl_protocol_features:has_feature(client_write_info, Version) of
        true -> clickhouse_erl_protocol_client_info:encode(ClientInfo, Version);
        false -> <<>>
    end.

%% @doc Maybe encode settings based on protocol version
maybe_encode_settings(Settings, Version) ->
    case clickhouse_erl_protocol_features:has_feature(settings_serialized_as_strings, Version) of
        true -> clickhouse_erl_protocol_settings:encode(Settings);
        %% Binary settings not implemented
        false -> <<>>
    end.

%% @doc Maybe encode secret based on protocol version
maybe_encode_secret(Secret, Version) ->
    case clickhouse_erl_protocol_features:has_feature(inter_server_secret, Version) of
        true -> clickhouse_erl_types_primitive:encode_string(Secret);
        false -> <<>>
    end.

%% @doc Maybe encode parameters based on protocol version
maybe_encode_parameters(Parameters, Version) ->
    case clickhouse_erl_protocol_features:has_feature(parameters, Version) of
        true -> clickhouse_erl_protocol_parameters:encode_parameters(Parameters);
        false -> <<>>
    end.

%% @doc Decode query packet from binary
%% Returns {ok, query_info()} or {error, term()}
-spec decode(binary(), integer()) -> {ok, query_info()} | {error, term()}.
decode(Binary, Version) ->
    ?LOG_DEBUG("Decoding query packet with version ~p", [Version]),

    maybe
        {query_id, {ok, QueryId, Rest0}} ?=
            {query_id, clickhouse_erl_types_primitive:decode_string(Binary)},
        {client_info, {ok, ClientInfo, Rest1}} ?=
            {client_info, maybe_decode_client_info(Rest0, Version)},
        {settings, {ok, Settings, Rest2}} ?= {settings, decode_settings(Rest1, Version)},
        {inter_server_secret, {ok, InterServerSecret, Rest3}} ?=
            {inter_server_secret, maybe_decode_inter_server_secret(Rest2, Version)},
        {stage, {ok, Stage0, Rest4}} ?=
            {stage, clickhouse_erl_types_primitive:decode_varint(Rest3)},
        {stage, {ok, Stage}} ?= {stage, get_stage(Stage0)},
        {compression, {ok, Compression0, Rest5}} ?=
            {compression, clickhouse_erl_types_primitive:decode_varint(Rest4)},
        {compression, {ok, Compression}} ?= {compression, get_compression(Compression0)},
        {body, {ok, Body, Rest6}} ?= {body, clickhouse_erl_types_primitive:decode_string(Rest5)},
        {parameters, {ok, Parameters, Rest7}} ?=
            {parameters, maybe_decode_parameters(Rest6, Version)},
        {ok, #{
            query_id => QueryId,
            client_info => ClientInfo,
            settings => Settings,
            inter_server_secret => InterServerSecret,
            stage => Stage,
            compression => Compression,
            body => Body,
            parameters => Parameters,
            additional_data => Rest7
        }}
    else
        {Field, {error, Err}} -> {error, {Field, Err}};
        {tail, Tail} -> {error, {unparsed_leftover, Tail}}
    end.

maybe_decode_client_info(Binary, Version) ->
    case clickhouse_erl_protocol_features:has_feature(client_write_info, Version) of
        true -> clickhouse_erl_protocol_client_info:decode(Binary, Version);
        false -> {ok, #{}, Binary}
    end.

decode_settings(Binary, Version) ->
    case clickhouse_erl_protocol_features:has_feature(settings_serialized_as_strings, Version) of
        false -> {ok, [], Binary};
        true -> clickhouse_erl_protocol_settings:decode(Binary)
    end.

maybe_decode_inter_server_secret(Binary, Version) ->
    case clickhouse_erl_protocol_features:has_feature(inter_server_secret, Version) of
        false -> {ok, <<>>, Binary};
        true -> clickhouse_erl_types_primitive:decode_string(Binary)
    end.

get_stage(Stage) ->
    case Stage of
        0 -> {ok, fetch_collumns};
        1 -> {ok, with_mergeable_state};
        2 -> {ok, complete};
        _ -> {error, {unknown_stage, Stage}}
    end.

get_compression(Compression) ->
    case Compression of
        0 -> {ok, disabled};
        1 -> {ok, enabled};
        _ -> {error, {unknown_compression, Compression}}
    end.

maybe_decode_parameters(Binary, Version) ->
    case clickhouse_erl_protocol_features:has_feature(parameters, Version) of
        false -> {ok, [], Binary};
        true -> clickhouse_erl_protocol_parameters:decode(Binary)
    end.
