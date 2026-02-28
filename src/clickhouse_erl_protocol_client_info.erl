-module(clickhouse_erl_protocol_client_info).

-export([decode/2, encode/2, get_os_user/0, get_hostname/0, get_initial_address/0]).

-include_lib("kernel/include/logger.hrl").
-include("clickhouse_erl_protocol.hrl").

decode(Binary, Version) ->
    maybe
        {query_kind, {ok, QueryKind0, Rest0}} ?=
            {query_kind, clickhouse_erl_types_integer:decode_uint8(Binary)},
        {query_kind, {ok, QueryKind}} ?= {query_kind, get_query_kind(QueryKind0)},
        {initial_user, {ok, InitialUser, Rest1}} ?=
            {initial_user, clickhouse_erl_types_primitive:decode_string(Rest0)},
        {initial_query_id, {ok, InitialQueryId, Rest2}} ?=
            {initial_query_id, clickhouse_erl_types_primitive:decode_string(Rest1)},
        {initial_address, {ok, InitialAddress, Rest3}} ?=
            {initial_address, clickhouse_erl_types_primitive:decode_string(Rest2)},
        {initial_time, {ok, InitialTime, Rest4}} ?=
            {initial_time, maybe_decode_initial_time(Rest3, Version)},
        {interface, {ok, Interface0, Rest5}} ?=
            {interface, clickhouse_erl_types_integer:decode_uint8(Rest4)},
        {interface, {ok, Interface}} ?= {interface, get_interface(Interface0)},
        {os_user, {ok, OsUser, Rest6}} ?=
            {os_user, clickhouse_erl_types_primitive:decode_string(Rest5)},
        {client_hostname, {ok, ClientHostname, Rest7}} ?=
            {client_hostname, clickhouse_erl_types_primitive:decode_string(Rest6)},
        {client_name, {ok, ClientName, Rest8}} ?=
            {client_name, clickhouse_erl_types_primitive:decode_string(Rest7)},
        {major, {ok, Major, Rest9}} ?= {major, clickhouse_erl_types_primitive:decode_varint(Rest8)},
        {minor, {ok, Minor, Rest10}} ?=
            {minor, clickhouse_erl_types_primitive:decode_varint(Rest9)},
        {protocol, {ok, Protocol, Rest11}} ?=
            {protocol, clickhouse_erl_types_primitive:decode_varint(Rest10)},
        {quota_key, {ok, QuotaKey, Rest12}} ?= {quota_key, maybe_decode_quota_key(Rest11, Version)},
        {distributed_depth, {ok, DistributedDepth, Rest13}} ?=
            {distributed_depth, maybe_decode_distributed_depth(Rest12, Version)},
        {version_patch, {ok, VersionPatch, Rest14}} ?=
            {version_patch, maybe_decode_version_patch(Rest13, Version, Interface)},
        {otel_span, {ok, OtelSpan, Rest15}} ?= {otel_span, maybe_decode_otel_span(Rest14, Version)},
        {parallel_replicas, {ok, ParallelReplicas, Rest16}} ?=
            {parallel_replicas, maybe_decode_parallel_replicas(Rest15, Version)},
        {ok,
            #{
                query_kind => QueryKind,
                initial_user => InitialUser,
                initial_query_id => InitialQueryId,
                initial_address => InitialAddress,
                initial_time => InitialTime,
                interface => Interface,
                os_user => OsUser,
                client_hostname => ClientHostname,
                client_name => ClientName,
                major => Major,
                minor => Minor,
                protocol => Protocol,
                quota_key => QuotaKey,
                distributed_depth => DistributedDepth,
                patch => VersionPatch,
                span => OtelSpan,
                parallel_replicas => ParallelReplicas
            },
            Rest16}
    else
        {Field, Err} ->
            ?LOG_DEBUG("ClientInfo decode failed at ~p: ~p (Binary=~p)", [
                Field, Err, Binary
            ]),
            {error, {client_info_decode_error, {Field, Err}}}
    end.

get_query_kind(Kind) ->
    case Kind of
        0 -> {ok, none};
        1 -> {ok, initial};
        2 -> {ok, secondary};
        _ -> {error, {unknown_query_kind, Kind}}
    end.

maybe_decode_initial_time(Binary, Version) ->
    case clickhouse_erl_protocol_features:has_feature(query_start_time, Version) of
        true -> clickhouse_erl_types_integer:decode_int64(Binary);
        false -> {ok, 0, Binary}
    end.

get_interface(Interface) ->
    case Interface of
        1 -> {ok, tcp};
        2 -> {ok, http};
        _ -> {error, {unknown_interface, Interface}}
    end.

maybe_decode_quota_key(Binary, Version) ->
    case clickhouse_erl_protocol_features:has_feature(quota_key_in_client_info, Version) of
        true -> clickhouse_erl_types_primitive:decode_string(Binary);
        false -> {ok, <<>>, Binary}
    end.

maybe_decode_distributed_depth(Binary, Version) ->
    case clickhouse_erl_protocol_features:has_feature(distributed_depth, Version) of
        true -> clickhouse_erl_types_primitive:decode_varint(Binary);
        false -> {ok, 0, Binary}
    end.

maybe_decode_version_patch(Binary, Version, Interface) ->
    case
        clickhouse_erl_protocol_features:has_feature(version_patch, Version) andalso
            Interface == tcp
    of
        true -> clickhouse_erl_types_primitive:decode_varint(Binary);
        false -> {ok, 0, Binary}
    end.

maybe_decode_otel_span(Binary, Version) ->
    case clickhouse_erl_protocol_features:has_feature(open_telemetry, Version) of
        true -> decode_open_telemetry(Binary);
        false -> {ok, none, Binary}
    end.

decode_open_telemetry(Binary) ->
    maybe
        {ok, HasTrace, Rest0} ?= clickhouse_erl_types_integer:decode_bool(Binary),
        case HasTrace of
            false -> {ok, not_implemented, Rest0};
            true -> {error, {not_implemented, otel_span}}
        end
    end.

maybe_decode_parallel_replicas(Binary, Version) ->
    case clickhouse_erl_protocol_features:has_feature(parallel_replicas, Version) of
        true -> decode_parallel_replicas(Binary);
        false -> {ok, null, Binary}
    end.

decode_parallel_replicas(Binary) ->
    maybe
        {ok, CollaborateWithInitiator0, Rest1} ?=
            clickhouse_erl_types_primitive:decode_varint(Binary),
        CollaborateWithInitiator = CollaborateWithInitiator0 == 1,
        {ok, CountParticipatingReplicas, Rest2} ?=
            clickhouse_erl_types_primitive:decode_varint(Rest1),
        {ok, NumberOfCurrentReplica, Rest3} ?= clickhouse_erl_types_primitive:decode_varint(Rest2),
        {ok,
            #{
                collaborate_with_initiator => CollaborateWithInitiator,
                count_participating_replicas => CountParticipatingReplicas,
                number_of_current_replica => NumberOfCurrentReplica
            },
            Rest3}
    end.

%% @doc Encode client info following Go ClientInfo.EncodeAware exactly
-spec encode(map(), integer()) -> binary().
encode(ClientInfo, Version) ->
    %% Follow Go implementation order from client_info.go exactly

    %% Query kind
    QueryKindVal = maps:get(query_kind, ClientInfo, 1),
    QueryKind =
        case QueryKindVal of
            none -> 0;
            initial -> 1;
            secondary -> 2;
            K when is_integer(K) -> K
        end,

    InitialUser = maps:get(initial_user, ClientInfo, ""),
    InitialQueryId = maps:get(initial_query_id, ClientInfo, ""),
    InitialAddress = maps:get(initial_address, ClientInfo, "0.0.0.0:0"),
    InitialTime = maps:get(initial_time, ClientInfo, 0),

    %% Interface - Always TCP (1) for this client
    Interface = 1,

    OsUser = maps:get(os_user, ClientInfo, "root"),
    ClientHostname = maps:get(client_hostname, ClientInfo, "Andrejs-MacBook-Pro.local"),
    ClientName = maps:get(client_name, ClientInfo, "ClickHouse client"),
    VersionMajor = maps:get(version_major, ClientInfo, 25),
    VersionMinor = maps:get(version_minor, ClientInfo, 12),
    ProtocolVersion = maps:get(protocol_version, ClientInfo, Version),

    %% Encode exactly as in Go: b.PutByte(byte(c.Query))
    Part1 = <<QueryKind:8>>,

    %% b.PutString(c.InitialUser)
    Part2 = clickhouse_erl_types_primitive:encode_string(InitialUser),

    %% b.PutString(c.InitialQueryID)
    Part3 = clickhouse_erl_types_primitive:encode_string(InitialQueryId),

    %% b.PutString(c.InitialAddress)
    Part4 = clickhouse_erl_types_primitive:encode_string(InitialAddress),

    %% if FeatureQueryStartTime.In(version) { b.PutInt64(c.InitialTime) }
    Part5 =
        case clickhouse_erl_protocol_features:has_feature(query_start_time, Version) of
            true ->
                %% In Go: b.PutInt64() - this is 8 bytes little-endian
                <<InitialTime:64/little-signed-integer>>;
            false ->
                <<>>
        end,

    %% b.PutByte(byte(c.Interface))
    Part6 = <<Interface:8>>,

    %% b.PutString(c.OSUser)
    Part7 = clickhouse_erl_types_primitive:encode_string(OsUser),

    %% b.PutString(c.ClientHostname)
    Part8 = clickhouse_erl_types_primitive:encode_string(ClientHostname),

    %% b.PutString(c.ClientName)
    Part9 = clickhouse_erl_types_primitive:encode_string(ClientName),

    %% b.PutInt(c.Major)
    Part10 = clickhouse_erl_types_primitive:encode_varint(VersionMajor),

    %% b.PutInt(c.Minor)
    Part11 = clickhouse_erl_types_primitive:encode_varint(VersionMinor),

    %% b.PutInt(c.ProtocolVersion)
    Part12 = clickhouse_erl_types_primitive:encode_varint(ProtocolVersion),

    %% Version-dependent additional fields
    Part13 = encode_additional_fields(ClientInfo, Version, Interface),

    <<Part1/binary, Part2/binary, Part3/binary, Part4/binary, Part5/binary, Part6/binary,
        Part7/binary, Part8/binary, Part9/binary, Part10/binary, Part11/binary, Part12/binary,
        Part13/binary>>.

%% @doc Encode additional client info fields based on protocol version
encode_additional_fields(ClientInfo, Version, Interface) ->
    %% Quota key (if supported)
    QuotaKeyPart =
        case clickhouse_erl_protocol_features:has_feature(quota_key_in_client_info, Version) of
            true ->
                QuotaKey = maps:get(quota_key, ClientInfo, ""),
                clickhouse_erl_types_primitive:encode_string(QuotaKey);
            false ->
                <<>>
        end,

    %% Distributed depth (if supported)
    DistributedDepthPart =
        case clickhouse_erl_protocol_features:has_feature(distributed_depth, Version) of
            true ->
                DistributedDepth = maps:get(distributed_depth, ClientInfo, 0),
                clickhouse_erl_types_primitive:encode_varint(DistributedDepth);
            false ->
                <<>>
        end,

    %% Version patch (if supported AND interface is TCP)
    VersionPatchPart =
        case
            clickhouse_erl_protocol_features:has_feature(version_patch, Version) andalso
                Interface == 1
        of
            true ->
                VersionPatch = maps:get(version_patch, ClientInfo, 0),
                clickhouse_erl_types_primitive:encode_varint(VersionPatch);
            false ->
                <<>>
        end,

    %% OpenTelemetry fields (if supported) - just a single byte 0 for no OTEL data
    OpenTelemetryPart =
        case clickhouse_erl_protocol_features:has_feature(open_telemetry, Version) of
            true ->
                %% No OTEL data - just put byte 0
                <<0>>;
            false ->
                <<>>
        end,

    %% Parallel replicas fields (if supported)
    ParallelReplicasPart =
        case clickhouse_erl_protocol_features:has_feature(parallel_replicas, Version) of
            true ->
                CollaborateWithInitiator =
                    maps:get(collaborate_with_initiator, ClientInfo, 0),
                CountParticipatingReplicas =
                    maps:get(count_participating_replicas, ClientInfo, 0),
                NumberOfCurrentReplica =
                    maps:get(number_of_current_replica, ClientInfo, 0),
                <<
                    (clickhouse_erl_types_primitive:encode_varint(
                        CollaborateWithInitiator
                    ))/binary,
                    (clickhouse_erl_types_primitive:encode_varint(
                        CountParticipatingReplicas
                    ))/binary,
                    (clickhouse_erl_types_primitive:encode_varint(
                        NumberOfCurrentReplica
                    ))/binary
                >>;
            false ->
                <<>>
        end,

    <<QuotaKeyPart/binary, DistributedDepthPart/binary, VersionPatchPart/binary,
        OpenTelemetryPart/binary, ParallelReplicasPart/binary>>.

%% @doc Get the OS username
-spec get_os_user() -> string().
get_os_user() ->
    case os:getenv("USER") of
        false ->
            case os:getenv("USERNAME") of
                false -> "unknown";
                User -> User
            end;
        User ->
            User
    end.

%% @doc Get the hostname
-spec get_hostname() -> string().
get_hostname() ->
    {ok, Hostname} = inet:gethostname(),
    Hostname.

%% @doc Get the initial address (local IP and port)
-spec get_initial_address() -> string().
get_initial_address() ->
    %% Try to get local IP, fallback to 0.0.0.0:0
    case inet:getifaddrs() of
        {ok, Interfaces} ->
            case find_first_ipv4(Interfaces) of
                {ok, IP} -> format_address(IP);
                error -> "0.0.0.0:0"
            end;
        {error, _} ->
            "0.0.0.0:0"
    end.

%% @doc Find first non-loopback IPv4 address
-spec find_first_ipv4(list()) -> {ok, inet:ip4_address()} | error.
find_first_ipv4([]) ->
    error;
find_first_ipv4([{_Name, Opts} | Rest]) ->
    case proplists:get_value(addr, Opts) of
        {A, B, C, D} = Addr when is_integer(A), is_integer(B), is_integer(C), is_integer(D) ->
            %% IPv4 address - skip loopback
            case A of
                127 -> find_first_ipv4(Rest);
                _ -> {ok, Addr}
            end;
        _ ->
            find_first_ipv4(Rest)
    end.

%% @doc Format IP address as string with port 0
-spec format_address(inet:ip4_address()) -> string().
format_address({A, B, C, D}) ->
    lists:flatten(io_lib:format("~B.~B.~B.~B:0", [A, B, C, D])).
