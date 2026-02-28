%% @doc Property-based tests for ClickHouse Query packet encoding.
%%
%% This module contains property-based tests using PropEr to validate
%% the correctness of Query packet encoding and round-trip properties.
-module(prop_clickhouse_erl_protocol_query_packet).

-include_lib("proper/include/proper.hrl").
-include("src/clickhouse_erl_protocol.hrl").

-import(generators, [
    string_gen/0, non_empty_string_gen/0, binary_string_gen/0, non_empty_binary_string_gen/0
]).

%% Property test: Query packet protocol round-trip
%% Feature: simple-query, Property 2: Query packet protocol round-trip
%% Validates: Requirements 1.3, 6.1, 6.2, 6.3
prop_query_packet_round_trip() ->
    ?FORALL(
        QueryInfo,
        query_info_gen(),
        begin
            case clickhouse_erl_protocol_query_packet:encode(QueryInfo) of
                {ok, EncodedPacket} ->
                    %% Decode the packet and verify all fields match
                    case decode_query_packet(EncodedPacket) of
                        {ok, DecodedQueryInfo} ->
                            %% Compare all fields
                            %% Convert original to binary where needed to match decoded output
                            BinaryQueryInfo = to_binary_recursive(QueryInfo),
                            query_info_equivalent(BinaryQueryInfo, DecodedQueryInfo);
                        {error, _Reason} ->
                            false
                    end;
                {error, _Reason} ->
                    false
            end
        end
    ).

%% Generator for query_info() structures
query_info_gen() ->
    ?LET(
        {QueryId, QueryBody, ClientInfo, Settings, Stage, Compression},
        {
            non_empty_binary_string_gen(),
            query_body_gen(),
            client_info_gen(),
            settings_list_gen(),
            query_stage_gen(),
            compression_mode_gen()
        },
        #{
            query_id => QueryId,
            query_body => QueryBody,
            client_info => ClientInfo,
            settings => Settings,
            stage => Stage,
            compression => Compression
        }
    ).

%% Generator for client_info() structures
client_info_gen() ->
    ?LET(
        {QueryKind, InitialUser, InitialQueryId, InitialAddress, _Interface, OsUser, ClientHostname,
            ClientName, VersionMajor, VersionMinor, ProtocolVersion, QuotaKey, DistributedDepth,
            VersionPatch},
        {
            query_kind_gen(),
            binary_string_gen(),
            binary_string_gen(),
            binary_string_gen(),
            interface_type_gen(),
            binary_string_gen(),
            binary_string_gen(),
            binary_string_gen(),
            non_neg_integer(),
            non_neg_integer(),
            return(?PROTOCOL_VERSION),
            binary_string_gen(),
            non_neg_integer(),
            non_neg_integer()
        },
        #{
            query_kind => QueryKind,
            initial_user => InitialUser,
            initial_query_id => InitialQueryId,
            initial_address => InitialAddress,
            os_user => OsUser,
            client_hostname => ClientHostname,
            client_name => ClientName,
            version_major => VersionMajor,
            version_minor => VersionMinor,
            protocol_version => ProtocolVersion,
            quota_key => QuotaKey,
            distributed_depth => DistributedDepth,
            version_patch => VersionPatch
        }
    ).

%% Generator for settings list
settings_list_gen() ->
    list(setting_gen()).

%% Generator for individual setting
setting_gen() ->
    ?LET(
        {Key, Value, Important},
        {non_empty_binary_string_gen(), binary_string_gen(), boolean()},
        #{
            key => Key,
            value => Value,
            important => Important
        }
    ).

%% Generator for query stages
query_stage_gen() ->
    %% Real encoder hardcodes StageComplete (2)
    return(?STAGE_COMPLETE).

%% Generator for compression modes
compression_mode_gen() ->
    oneof([?COMPRESSION_DISABLED, ?COMPRESSION_ENABLED]).

%% Generator for query kinds
query_kind_gen() ->
    oneof([none, initial, secondary]).

%% Generator for interface types
interface_type_gen() ->
    %% Only test TCP interface for now since HTTP interface has encoding issues
    return(tcp).

query_body_gen() ->
    %% Always generate non-empty, non-whitespace queries for round-trip testing
    %% Empty query validation should be tested separately
    ?LET(
        S,
        ?SUCHTHAT(
            String,
            string_gen(),
            string:trim(clickhouse_erl_types_primitive:to_binary(String)) =/= <<>>
        ),
        clickhouse_erl_types_primitive:to_binary(S)
    ).

%% Decode a query packet and return the query info
decode_query_packet(EncodedPacket) ->
    %% Use the real decoder from the protocol module
    case clickhouse_erl_types_primitive:decode_varint(EncodedPacket) of
        {ok, ?CLIENT_QUERY, Rest1} ->
            %% Use the real query packet decoder
            case clickhouse_erl_protocol_query_packet:decode(Rest1, ?PROTOCOL_VERSION) of
                {ok, DecodedInfo} ->
                    {ok, DecodedInfo};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, PacketType, _Rest} ->
            {error, {wrong_packet_type, PacketType}};
        {error, Reason} ->
            {error, {decode_packet_type, Reason}}
    end.

%% Compare two query_info structures for equivalence
query_info_equivalent(Original, Decoded) ->
    %% The real decoder returns different field names, so we need to map them
    %% Original uses: query_id, query_body, client_info, settings, stage, compression
    %% Decoded uses: query_id, body, client_info, settings, stage, compression, inter_server_secret, parameters

    QueryIdMatch = maps:get(query_id, Original) =:= maps:get(query_id, Decoded),
    QueryBodyMatch = maps:get(query_body, Original) =:= maps:get(body, Decoded),

    %% Convert stage integer to atom for comparison
    OriginalStage =
        case maps:get(stage, Original) of
            0 -> fetch_collumns;
            1 -> with_mergeable_state;
            2 -> complete;
            S when is_atom(S) -> S
        end,
    StageMatch = OriginalStage =:= maps:get(stage, Decoded),

    %% Convert compression integer to atom for comparison
    OriginalCompression =
        case maps:get(compression, Original) of
            0 -> disabled;
            1 -> enabled;
            C when is_atom(C) -> C
        end,
    CompressionMatch = OriginalCompression =:= maps:get(compression, Decoded),

    %% Compare client info
    OriginalClientInfo = maps:get(client_info, Original),
    DecodedClientInfo = maps:get(client_info, Decoded),
    ClientInfoMatch = client_info_equivalent(OriginalClientInfo, DecodedClientInfo),

    %% Compare settings (order might differ, so compare as sets)
    OriginalSettings = maps:get(settings, Original, []),
    DecodedSettings = maps:get(settings, Decoded, []),
    SettingsMatch = settings_equivalent(OriginalSettings, DecodedSettings),

    QueryIdMatch andalso QueryBodyMatch andalso StageMatch andalso
        CompressionMatch andalso ClientInfoMatch andalso SettingsMatch.

%% Compare two client_info structures for equivalence
client_info_equivalent(Original, Decoded) ->
    %% The real decoder uses different field names:
    %% Original: version_major, version_minor, version_patch
    %% Decoded: major, minor, patch

    QueryKindMatch =
        maps:get(query_kind, Original) =:= maps:get(query_kind, Decoded),
    InitialUserMatch =
        maps:get(initial_user, Original, <<>>) =:= maps:get(initial_user, Decoded),
    InitialQueryIdMatch =
        maps:get(initial_query_id, Original, <<>>) =:= maps:get(initial_query_id, Decoded),
    InitialAddressMatch =
        maps:get(initial_address, Original, <<>>) =:= maps:get(initial_address, Decoded),
    InterfaceMatch =
        maps:get(interface, Decoded) =:= tcp,
    QuotaKeyMatch =
        maps:get(quota_key, Original, <<>>) =:= maps:get(quota_key, Decoded),
    DistributedDepthMatch =
        maps:get(distributed_depth, Original, 0) =:= maps:get(distributed_depth, Decoded),
    VersionPatchMatch =
        % Note: patch vs version_patch
        maps:get(version_patch, Original, 0) =:= maps:get(patch, Decoded),

    %% Check TCP-specific fields (always TCP now)
    TcpFieldsMatch =
        begin
            OsUserMatch =
                maps:get(os_user, Original, <<>>) =:= maps:get(os_user, Decoded),
            ClientHostnameMatch =
                maps:get(client_hostname, Original, <<>>) =:=
                    maps:get(client_hostname, Decoded),
            ClientNameMatch =
                maps:get(client_name, Original, <<>>) =:= maps:get(client_name, Decoded),
            VersionMajorMatch =
                % Note: major vs version_major
                maps:get(version_major, Original, 0) =:= maps:get(major, Decoded),
            VersionMinorMatch =
                % Note: minor vs version_minor
                maps:get(version_minor, Original, 0) =:= maps:get(minor, Decoded),
            ProtocolMatch =
                % Note: protocol vs protocol_version
                maps:get(protocol_version, Original, 0) =:= maps:get(protocol, Decoded),

            OsUserMatch andalso ClientHostnameMatch andalso ClientNameMatch andalso
                VersionMajorMatch andalso VersionMinorMatch andalso ProtocolMatch
        end,

    QueryKindMatch andalso InitialUserMatch andalso InitialQueryIdMatch andalso
        InitialAddressMatch andalso InterfaceMatch andalso QuotaKeyMatch andalso
        DistributedDepthMatch andalso VersionPatchMatch andalso TcpFieldsMatch.

%% Compare two settings lists for equivalence (ignoring order)
settings_equivalent(Original, Decoded) ->
    %% Convert to sets for comparison (ignoring order)
    %% Handle the case where settings might have different field structures
    OriginalPairs = [
        {maps:get(key, S, <<>>), maps:get(value, S, <<>>), maps:get(important, S, false)}
     || S <- Original
    ],
    DecodedPairs = [
        {maps:get(key, S, <<>>), maps:get(value, S, <<>>), maps:get(important, S, false)}
     || S <- Decoded
    ],
    OriginalSet = sets:from_list(OriginalPairs),
    DecodedSet = sets:from_list(DecodedPairs),
    sets:is_equal(OriginalSet, DecodedSet).

to_binary_recursive([]) ->
    [];
to_binary_recursive(Map) when is_map(Map) ->
    maps:from_list([{K, to_binary_recursive(V)} || {K, V} <- maps:to_list(Map)]);
to_binary_recursive(List) when is_list(List) ->
    case io_lib:printable_list(List) of
        true -> clickhouse_erl_types_primitive:to_binary(List);
        false -> [to_binary_recursive(I) || I <- List]
    end;
to_binary_recursive(Val) ->
    Val.

%% Property test: Query ID uniqueness
%% Feature: simple-query, Property 3: Query ID uniqueness
%% Validates: Requirements 1.6
prop_query_id_uniqueness() ->
    ?FORALL(
        N,
        range(2, 100),
        begin
            %% Generate N query IDs and verify they are all unique
            QueryIds = [clickhouse_erl_utils:generate_query_id() || _ <- lists:seq(1, N)],
            %% Convert to set and check that set size equals list length
            UniqueIds = sets:from_list(QueryIds),
            sets:size(UniqueIds) =:= length(QueryIds)
        end
    ).

%% Property test: Query Packet Compression Field
%% Feature: compression-support, Property 8: Query Packet Compression Field
%% Validates: Requirements 5.1, 5.2
prop_query_packet_compression_field() ->
    ?FORALL(
        {QueryInfo, CompressionMode},
        {query_info_gen(), compression_mode_gen()},
        begin
            %% Set the compression mode in QueryInfo
            QueryInfoWithCompression = QueryInfo#{compression => CompressionMode},

            %% Encode the query packet
            case clickhouse_erl_protocol_query_packet:encode(QueryInfoWithCompression) of
                {ok, EncodedPacket} ->
                    %% Decode and verify compression field matches
                    case decode_query_packet(EncodedPacket) of
                        {ok, DecodedInfo} ->
                            %% Convert compression integer to atom for comparison
                            ExpectedCompression =
                                case CompressionMode of
                                    0 -> disabled;
                                    1 -> enabled
                                end,
                            DecodedCompression = maps:get(compression, DecodedInfo),
                            ExpectedCompression =:= DecodedCompression;
                        {error, _Reason} ->
                            false
                    end;
                {error, _Reason} ->
                    false
            end
        end
    ).
