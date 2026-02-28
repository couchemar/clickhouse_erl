%% @doc Property-based tests for ClickHouse protocol constants.
%%
%% This module contains property-based tests using PropEr to validate
%% the consistency and correctness of protocol constants.
-module(prop_clickhouse_erl_protocol_constants).

-include_lib("proper/include/proper.hrl").
-include("src/clickhouse_erl_protocol.hrl").

%% Property test: Protocol constant consistency
%% Feature: simple-query, Property 1: Protocol constant consistency
%% Validates: Requirements 6.1
prop_protocol_constant_consistency() ->
    ?FORALL(
        ConstantType,
        constant_type_gen(),
        begin
            case ConstantType of
                packet_types ->
                    %% Test that packet type constants are within valid ranges and unique
                    ClientPacketTypes = [?CLIENT_QUERY, ?CLIENT_DATA, ?CLIENT_CANCEL, ?CLIENT_PING],
                    ServerPacketTypes = [
                        ?SERVER_DATA,
                        ?SERVER_EXCEPTION,
                        ?SERVER_PROGRESS,
                        ?SERVER_PONG,
                        ?SERVER_END_OF_STREAM
                    ],

                    %% All packet types should be positive integers
                    AllPacketTypes = ClientPacketTypes ++ ServerPacketTypes,
                    AllPositive = lists:all(
                        fun(Type) -> is_integer(Type) andalso Type >= 0 end, AllPacketTypes
                    ),

                    %% Client packet types should be unique
                    ClientUnique =
                        length(ClientPacketTypes) =:= length(lists:usort(ClientPacketTypes)),

                    %% Server packet types should be unique
                    ServerUnique =
                        length(ServerPacketTypes) =:= length(lists:usort(ServerPacketTypes)),

                    %% Packet types should be within reasonable bounds (0-255 for single byte)
                    WithinBounds = lists:all(
                        fun(Type) -> Type >= 0 andalso Type =< 255 end, AllPacketTypes
                    ),

                    AllPositive andalso ClientUnique andalso ServerUnique andalso WithinBounds;
                query_stages ->
                    %% Test that query stage constants are sequential and within valid range
                    QueryStages = [
                        ?STAGE_FETCH_COLUMNS, ?STAGE_WITH_MERGEABLE_STATE, ?STAGE_COMPLETE
                    ],

                    %% Should be sequential starting from 0
                    Sequential = QueryStages =:= [0, 1, 2],

                    %% All should be non-negative integers
                    NonNegative = lists:all(
                        fun(Stage) -> is_integer(Stage) andalso Stage >= 0 end, QueryStages
                    ),

                    %% Should be within reasonable bounds for UVarInt encoding
                    WithinBounds = lists:all(fun(Stage) -> Stage =< 255 end, QueryStages),

                    Sequential andalso NonNegative andalso WithinBounds;
                compression_modes ->
                    %% Test that compression mode constants are boolean-like (0 or 1)
                    CompressionModes = [?COMPRESSION_DISABLED, ?COMPRESSION_ENABLED],

                    %% Should be exactly [0, 1]
                    BooleanLike = CompressionModes =:= [0, 1],

                    %% All should be non-negative integers
                    NonNegative = lists:all(
                        fun(Mode) -> is_integer(Mode) andalso Mode >= 0 end, CompressionModes
                    ),

                    %% Should be within single byte range
                    WithinBounds = lists:all(fun(Mode) -> Mode =< 255 end, CompressionModes),

                    BooleanLike andalso NonNegative andalso WithinBounds;
                interface_types ->
                    %% Test that interface type constants are positive and unique
                    InterfaceTypes = [?INTERFACE_TCP, ?INTERFACE_HTTP],

                    %% Should be exactly [1, 2]
                    ExpectedValues = InterfaceTypes =:= [1, 2],

                    %% All should be positive integers
                    Positive = lists:all(
                        fun(Type) -> is_integer(Type) andalso Type > 0 end, InterfaceTypes
                    ),

                    %% Should be unique
                    Unique = length(InterfaceTypes) =:= length(lists:usort(InterfaceTypes)),

                    %% Should be within reasonable bounds
                    WithinBounds = lists:all(fun(Type) -> Type =< 255 end, InterfaceTypes),

                    ExpectedValues andalso Positive andalso Unique andalso WithinBounds;
                query_kinds ->
                    %% Test that query kind constants are sequential and within valid range
                    QueryKinds = [?QUERY_KIND_NONE, ?QUERY_KIND_INITIAL, ?QUERY_KIND_SECONDARY],

                    %% Should be sequential starting from 0
                    Sequential = QueryKinds =:= [0, 1, 2],

                    %% All should be non-negative integers
                    NonNegative = lists:all(
                        fun(Kind) -> is_integer(Kind) andalso Kind >= 0 end, QueryKinds
                    ),

                    %% Should be within reasonable bounds for UVarInt encoding
                    WithinBounds = lists:all(fun(Kind) -> Kind =< 255 end, QueryKinds),

                    Sequential andalso NonNegative andalso WithinBounds;
                type_consistency ->
                    %% Test that type definitions are consistent with constants
                    %% query_stage() type should match actual stage constants
                    ValidStages = [0, 1, 2],
                    StageTypeConsistent = lists:all(
                        fun(Stage) ->
                            Stage =:= ?STAGE_FETCH_COLUMNS orelse
                                Stage =:= ?STAGE_WITH_MERGEABLE_STATE orelse
                                Stage =:= ?STAGE_COMPLETE
                        end,
                        ValidStages
                    ),

                    %% compression_mode() type should match actual compression constants
                    ValidCompressionModes = [0, 1],
                    CompressionTypeConsistent = lists:all(
                        fun(Mode) ->
                            Mode =:= ?COMPRESSION_DISABLED orelse
                                Mode =:= ?COMPRESSION_ENABLED
                        end,
                        ValidCompressionModes
                    ),

                    %% interface_type() type should match actual interface constants
                    ValidInterfaceTypes = [1, 2],
                    InterfaceTypeConsistent = lists:all(
                        fun(Type) ->
                            Type =:= ?INTERFACE_TCP orelse
                                Type =:= ?INTERFACE_HTTP
                        end,
                        ValidInterfaceTypes
                    ),

                    %% query_kind() type should match actual query kind constants
                    ValidQueryKinds = [0, 1, 2],
                    QueryKindTypeConsistent = lists:all(
                        fun(Kind) ->
                            Kind =:= ?QUERY_KIND_NONE orelse
                                Kind =:= ?QUERY_KIND_INITIAL orelse
                                Kind =:= ?QUERY_KIND_SECONDARY
                        end,
                        ValidQueryKinds
                    ),

                    StageTypeConsistent andalso CompressionTypeConsistent andalso
                        InterfaceTypeConsistent andalso QueryKindTypeConsistent;
                protocol_compliance ->
                    %% Test that constants follow ClickHouse protocol specification requirements
                    %% All constants should be encodable as proper protocol values

                    %% Packet types should be encodable as UInt8
                    PacketTypesValid = lists:all(
                        fun(Type) ->
                            is_integer(Type) andalso Type >= 0 andalso Type =< 255
                        end,
                        [
                            ?CLIENT_QUERY,
                            ?CLIENT_DATA,
                            ?CLIENT_CANCEL,
                            ?CLIENT_PING,
                            ?SERVER_DATA,
                            ?SERVER_EXCEPTION,
                            ?SERVER_PROGRESS,
                            ?SERVER_PONG,
                            ?SERVER_END_OF_STREAM
                        ]
                    ),

                    %% Query stages should be encodable as UVarInt (non-negative)
                    QueryStagesValid = lists:all(
                        fun(Stage) ->
                            is_integer(Stage) andalso Stage >= 0
                        end,
                        [?STAGE_FETCH_COLUMNS, ?STAGE_WITH_MERGEABLE_STATE, ?STAGE_COMPLETE]
                    ),

                    %% Compression modes should be encodable as UVarInt (non-negative)
                    CompressionModesValid = lists:all(
                        fun(Mode) ->
                            is_integer(Mode) andalso Mode >= 0
                        end,
                        [?COMPRESSION_DISABLED, ?COMPRESSION_ENABLED]
                    ),

                    %% Interface types should be encodable as UVarInt (non-negative)
                    InterfaceTypesValid = lists:all(
                        fun(Type) ->
                            is_integer(Type) andalso Type >= 0
                        end,
                        [?INTERFACE_TCP, ?INTERFACE_HTTP]
                    ),

                    %% Query kinds should be encodable as UVarInt (non-negative)
                    QueryKindsValid = lists:all(
                        fun(Kind) ->
                            is_integer(Kind) andalso Kind >= 0
                        end,
                        [?QUERY_KIND_NONE, ?QUERY_KIND_INITIAL, ?QUERY_KIND_SECONDARY]
                    ),

                    PacketTypesValid andalso QueryStagesValid andalso CompressionModesValid andalso
                        InterfaceTypesValid andalso QueryKindsValid
            end
        end
    ).

%% Generator for different types of constant validation
constant_type_gen() ->
    oneof([
        packet_types,
        query_stages,
        compression_modes,
        interface_types,
        query_kinds,
        type_consistency,
        protocol_compliance
    ]).
