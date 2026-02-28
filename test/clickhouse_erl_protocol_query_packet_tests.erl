-module(clickhouse_erl_protocol_query_packet_tests).
-include_lib("eunit/include/eunit.hrl").
-include("src/clickhouse_erl_protocol.hrl").

encode_query_packet_test() ->
    QueryId = "test_query_id",
    QueryBody = "SELECT 1",

    ClientInfo = #{
        query_kind => ?QUERY_KIND_INITIAL,
        initial_user => "default",
        initial_query_id => "init_qid",
        initial_address => "127.0.0.1:9000",
        % Add initial time for version 54460
        initial_time => 1640995200000000,
        %% TCP interface
        interface => 1,
        os_user => "user",
        client_hostname => "localhost",
        client_name => "ClickHouse Client",
        version_major => 1,
        version_minor => 1,
        % Use ch-go default version
        protocol_version => 54460,
        quota_key => "",
        distributed_depth => 0,
        version_patch => 0
    },

    Settings = [
        #{key => "max_threads", value => "1", important => false}
    ],

    QueryInfo = #{
        query_id => QueryId,
        query_body => QueryBody,
        client_info => ClientInfo,
        settings => Settings,
        stage => ?STAGE_COMPLETE,
        compression => ?COMPRESSION_DISABLED
    },

    %% Test encode/decode roundtrip with ch-go default version
    {ok, Encoded} = clickhouse_erl_protocol_query_packet:encode(QueryInfo, 54460),

    %% Remove the packet type byte for decoder (decoder expects packet without type)
    {ok, ?CLIENT_QUERY, PacketWithoutType} = clickhouse_erl_types_primitive:decode_varint(Encoded),

    %% Decode and verify
    {ok, Decoded} = clickhouse_erl_protocol_query_packet:decode(PacketWithoutType, 54460),

    %% Verify key fields
    ?assertEqual(list_to_binary(QueryId), maps:get(query_id, Decoded)),
    ?assertEqual(list_to_binary(QueryBody), maps:get(body, Decoded)),
    ?assertEqual(complete, maps:get(stage, Decoded)),
    ?assertEqual(disabled, maps:get(compression, Decoded)),
    ?assertEqual(1, length(maps:get(settings, Decoded))).

encode_query_defaults_test() ->
    QueryInfo = #{
        query_id => "q1",
        query_body => "SELECT 1",
        client_info => #{
            % Add initial time for version 54460
            initial_time => 1640995200000000
        },
        settings => []
    },

    %% Test encode/decode roundtrip with default version (54460)
    {ok, Encoded} = clickhouse_erl_protocol_query_packet:encode(QueryInfo),

    %% Remove the packet type byte for decoder
    {ok, ?CLIENT_QUERY, PacketWithoutType} = clickhouse_erl_types_primitive:decode_varint(Encoded),

    %% Decode and verify
    {ok, Decoded} = clickhouse_erl_protocol_query_packet:decode(PacketWithoutType, 54460),

    %% Verify key fields
    ?assertEqual(<<"q1">>, maps:get(query_id, Decoded)),
    ?assertEqual(<<"SELECT 1">>, maps:get(body, Decoded)).

%% Test query ID generation functionality
generate_query_id_with_provided_id_test() ->
    QueryInfo = #{query_id => "my_custom_id"},
    Result = clickhouse_erl_protocol_query_packet:generate_query_id(QueryInfo),
    ?assertEqual(<<"my_custom_id">>, Result).

generate_query_id_with_binary_id_test() ->
    QueryInfo = #{query_id => <<"binary_id">>},
    Result = clickhouse_erl_protocol_query_packet:generate_query_id(QueryInfo),
    ?assertEqual(<<"binary_id">>, Result).

generate_query_id_with_undefined_test() ->
    QueryInfo = #{},
    Result = clickhouse_erl_protocol_query_packet:generate_query_id(QueryInfo),
    %% Should be a UUID binary (36 characters with dashes)
    ?assert(is_binary(Result)),
    ?assertEqual(36, byte_size(Result)),
    ?assertEqual($-, binary:at(Result, 8)),
    ?assertEqual($-, binary:at(Result, 13)),
    ?assertEqual($-, binary:at(Result, 18)),
    ?assertEqual($-, binary:at(Result, 23)).

generate_query_id_with_empty_string_test() ->
    QueryInfo = #{query_id => ""},
    Result = clickhouse_erl_protocol_query_packet:generate_query_id(QueryInfo),
    %% Should generate a UUID when empty string is provided
    ?assert(is_binary(Result)),
    ?assertEqual(36, byte_size(Result)),
    ?assertEqual($-, binary:at(Result, 8)).

generate_query_id_uniqueness_test() ->
    QueryInfo = #{},
    Id1 = clickhouse_erl_protocol_query_packet:generate_query_id(QueryInfo),
    Id2 = clickhouse_erl_protocol_query_packet:generate_query_id(QueryInfo),
    ?assertNotEqual(Id1, Id2).

%% Test encoding with auto-generated query ID
encode_with_auto_generated_query_id_test() ->
    QueryInfo = #{
        query_body => "SELECT 1",
        client_info => #{},
        settings => []
        %% No query_id provided - should auto-generate
    },

    {ok, Encoded} = clickhouse_erl_protocol_query_packet:encode(QueryInfo),

    {ok, ?CLIENT_QUERY, Rest} = clickhouse_erl_types_primitive:decode_varint(Encoded),
    {ok, GeneratedId, _} = clickhouse_erl_types_primitive:decode_string(Rest),

    %% Should be a UUID binary
    ?assert(is_binary(GeneratedId)),
    ?assertEqual(36, byte_size(GeneratedId)),
    ?assertEqual($-, binary:at(GeneratedId, 8)),
    ?assertEqual($-, binary:at(GeneratedId, 13)),
    ?assertEqual($-, binary:at(GeneratedId, 18)),
    ?assertEqual($-, binary:at(GeneratedId, 23)).

encode_with_empty_query_id_test() ->
    QueryInfo = #{
        %% Empty string should trigger auto-generation
        query_id => "",
        query_body => "SELECT 1",
        client_info => #{},
        settings => []
    },

    {ok, Encoded} = clickhouse_erl_protocol_query_packet:encode(QueryInfo),

    {ok, ?CLIENT_QUERY, Rest} = clickhouse_erl_types_primitive:decode_varint(Encoded),
    {ok, GeneratedId, _} = clickhouse_erl_types_primitive:decode_string(Rest),

    %% Should be a UUID binary, not empty
    ?assert(is_binary(GeneratedId)),
    ?assertEqual(36, byte_size(GeneratedId)),
    ?assertNotEqual(<<>>, GeneratedId).

%%% ========================================================================
%%% Decode Tests
%%% ========================================================================

decode_query_create_database_test() ->
    %% Hex data from ch-go/proto/query_test.go - queryCreateDatabaseHex without first byte (01 -- query packet).
    Query = <<
        16#24,
        16#32,
        16#33,
        16#61,
        16#64,
        16#32,
        16#63,
        16#30,
        16#37,
        16#2d,
        16#32,
        16#66,
        16#36,
        16#38,
        16#2d,
        16#34,
        16#30,
        16#30,
        16#35,
        16#2d,
        16#39,
        16#62,
        16#61,
        16#63,
        16#2d,
        16#64,
        16#61,
        16#38,
        16#66,
        16#34,
        16#36,
        16#37,
        16#62,
        16#64,
        16#64,
        16#33,
        16#62,
        16#01,
        16#00,
        16#24,
        16#32,
        16#33,
        16#61,
        16#64,
        16#32,
        16#63,
        16#30,
        16#37,
        16#2d,
        16#32,
        16#66,
        16#36,
        16#38,
        16#2d,
        16#34,
        16#30,
        16#30,
        16#35,
        16#2d,
        16#39,
        16#62,
        16#61,
        16#63,
        16#2d,
        16#64,
        16#61,
        16#38,
        16#66,
        16#34,
        16#36,
        16#37,
        16#62,
        16#64,
        16#64,
        16#33,
        16#62,
        16#09,
        16#30,
        16#2e,
        16#30,
        16#2e,
        16#30,
        16#2e,
        16#30,
        16#3a,
        16#30,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#01,
        16#06,
        16#65,
        16#72,
        16#6e,
        16#61,
        16#64,
        16#6f,
        16#05,
        16#6e,
        16#65,
        16#78,
        16#75,
        16#73,
        16#0b,
        16#43,
        16#6c,
        16#69,
        16#63,
        16#6b,
        16#48,
        16#6f,
        16#75,
        16#73,
        16#65,
        16#20,
        16#15,
        16#0b,
        16#b2,
        16#a9,
        16#03,
        16#00,
        16#00,
        16#04,
        16#00,
        16#00,
        16#00,
        16#02,
        16#00,
        16#15,
        16#43,
        16#52,
        16#45,
        16#41,
        16#54,
        16#45,
        16#20,
        16#44,
        16#41,
        16#54,
        16#41,
        16#42,
        16#41,
        16#53,
        16#45,
        16#20,
        16#74,
        16#65,
        16#73,
        16#74,
        16#3b
    >>,

    {ok, QueryInfo} = clickhouse_erl_protocol_query_packet:decode(Query, 54450),
    ?assertEqual(
        #{
            client_info =>
                #{
                    major => 21,
                    minor => 11,
                    protocol => 54450,
                    interface => tcp,
                    patch => 4,
                    span => not_implemented,
                    query_kind => initial,
                    initial_user => <<>>,
                    initial_query_id =>
                        <<"23ad2c07-2f68-4005-9bac-da8f467bdd3b">>,
                    initial_address => <<"0.0.0.0:0">>,
                    initial_time => 0,
                    os_user => <<"ernado">>,
                    client_hostname => <<"nexus">>,
                    client_name => <<"ClickHouse ">>,
                    quota_key => <<>>,
                    distributed_depth => 0,
                    parallel_replicas => null
                },
            query_id => <<"23ad2c07-2f68-4005-9bac-da8f467bdd3b">>,
            settings => [],
            stage => complete,
            compression => disabled,
            body => <<"CREATE DATABASE test;">>,
            parameters => [],
            inter_server_secret => <<>>,
            additional_data => <<>>
        },
        QueryInfo
    ).

decode_working_packet_test() ->
    % Packet captured from clickhouse cli. Without first byte (01 -- packet type) and binary settings that we dont know how to parse.
    Query = <<
        16#00,
        16#01,
        16#00,
        16#00,
        16#09,
        16#30,
        16#2e,
        16#30,
        16#2e,
        16#30,
        16#2e,
        16#30,
        16#3a,
        16#30,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#01,
        16#04,
        16#72,
        16#6f,
        16#6f,
        16#74,
        16#19,
        16#41,
        16#6e,
        16#64,
        16#72,
        16#65,
        16#6a,
        16#73,
        16#2d,
        16#4d,
        16#61,
        16#63,
        16#42,
        16#6f,
        16#6f,
        16#6b,
        16#2d,
        16#50,
        16#72,
        16#6f,
        16#2e,
        16#6c,
        16#6f,
        16#63,
        16#61,
        16#6c,
        16#11,
        16#43,
        16#6c,
        16#69,
        16#63,
        16#6b,
        16#48,
        16#6f,
        16#75,
        16#73,
        16#65,
        16#20,
        16#63,
        16#6c,
        16#69,
        16#65,
        16#6e,
        16#74,
        16#19,
        16#0c,
        16#d3,
        16#a9,
        16#03,
        16#00,
        16#00,
        16#01,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#02,
        16#00,
        16#08,
        16#53,
        16#45,
        16#4c,
        16#45,
        16#43,
        16#54,
        16#20,
        16#31,
        16#00,
        16#02,
        16#00,
        16#01,
        16#00,
        16#02,
        16#ff,
        16#ff,
        16#ff,
        16#ff,
        16#03,
        16#00,
        16#00,
        16#00,
        16#00
    >>,

    {ok, QueryInfo} = clickhouse_erl_protocol_query_packet:decode(Query, 54483),

    ?assertEqual(
        #{
            client_info =>
                #{
                    major => 25,
                    minor => 12,
                    protocol => 54483,
                    interface => tcp,
                    patch => 1,
                    span => not_implemented,
                    query_kind => initial,
                    initial_user => <<>>,
                    initial_query_id => <<>>,
                    initial_address => <<"0.0.0.0:0">>,
                    initial_time => 0,
                    os_user => <<"root">>,
                    client_hostname => <<"Andrejs-MacBook-Pro.local">>,
                    client_name => <<"ClickHouse client">>,
                    quota_key => <<>>,
                    distributed_depth => 0,
                    parallel_replicas =>
                        #{
                            collaborate_with_initiator => false,
                            count_participating_replicas => 0,
                            number_of_current_replica => 0
                        }
                },
            query_id => <<>>,
            settings => [],
            stage => complete,
            compression => disabled,
            parameters => [],
            inter_server_secret => <<>>,
            body => <<"SELECT 1">>,
            additional_data => <<2, 0, 1, 0, 2, 255, 255, 255, 255, 3, 0, 0, 0, 0>>
        },
        QueryInfo
    ).

decode_ch_go_packet_test() ->
    Query = <<
        16#24,
        16#65,
        16#32,
        16#35,
        16#62,
        16#61,
        16#62,
        16#31,
        16#30,
        16#2d,
        16#36,
        16#61,
        16#38,
        16#65,
        16#2d,
        16#34,
        16#62,
        16#31,
        16#62,
        16#2d,
        16#62,
        16#61,
        16#66,
        16#30,
        16#2d,
        16#31,
        16#35,
        16#63,
        16#35,
        16#33,
        16#38,
        16#32,
        16#35,
        16#65,
        16#38,
        16#32,
        16#36,
        16#01,
        16#00,
        16#24,
        16#65,
        16#32,
        16#35,
        16#62,
        16#61,
        16#62,
        16#31,
        16#30,
        16#2d,
        16#36,
        16#61,
        16#38,
        16#65,
        16#2d,
        16#34,
        16#62,
        16#31,
        16#62,
        16#2d,
        16#62,
        16#61,
        16#66,
        16#30,
        16#2d,
        16#31,
        16#35,
        16#63,
        16#35,
        16#33,
        16#38,
        16#32,
        16#35,
        16#65,
        16#38,
        16#32,
        16#36,
        16#0f,
        16#31,
        16#32,
        16#37,
        16#2e,
        16#30,
        16#2e,
        16#30,
        16#2e,
        16#31,
        16#3a,
        16#35,
        16#35,
        16#33,
        16#36,
        16#31,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#01,
        16#00,
        16#00,
        16#10,
        16#63,
        16#6c,
        16#69,
        16#63,
        16#6b,
        16#68,
        16#6f,
        16#75,
        16#73,
        16#65,
        16#2f,
        16#63,
        16#68,
        16#2d,
        16#67,
        16#6f,
        16#00,
        16#3d,
        16#bc,
        16#a9,
        16#03,
        16#00,
        16#00,
        16#05,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#02,
        16#00,
        16#08,
        16#53,
        16#45,
        16#4c,
        16#45,
        16#43,
        16#54,
        16#20,
        16#31,
        16#00,
        16#02,
        16#00,
        16#01,
        16#00,
        16#02,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00
    >>,

    {ok, QueryInfo} = clickhouse_erl_protocol_query_packet:decode(Query, 54460),

    ?assertEqual(
        #{
            client_info =>
                #{
                    major => 0,
                    minor => 61,
                    protocol => 54460,
                    interface => tcp,
                    patch => 5,
                    span => not_implemented,
                    client_hostname => <<>>,
                    client_name => <<"clickhouse/ch-go">>,
                    distributed_depth => 0,
                    initial_address => <<"127.0.0.1:55361">>,
                    initial_query_id =>
                        <<"e25bab10-6a8e-4b1b-baf0-15c53825e826">>,
                    initial_time => 0,
                    initial_user => <<>>,
                    os_user => <<>>,
                    query_kind => initial,
                    quota_key => <<>>,
                    parallel_replicas =>
                        #{
                            collaborate_with_initiator => false,
                            count_participating_replicas => 0,
                            number_of_current_replica => 0
                        }
                },
            query_id => <<"e25bab10-6a8e-4b1b-baf0-15c53825e826">>,
            body => <<"SELECT 1">>,
            stage => complete,
            compression => disabled,
            settings => [],
            additional_data => <<2, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0>>,
            inter_server_secret => <<>>,
            parameters => []
        },
        QueryInfo
    ).

decode_debug_test() ->
    Query = <<
        16#24,
        16#37,
        16#32,
        16#63,
        16#30,
        16#61,
        16#32,
        16#61,
        16#62,
        16#2d,
        16#33,
        16#30,
        16#38,
        16#36,
        16#2d,
        16#34,
        16#64,
        16#65,
        16#31,
        16#2d,
        16#61,
        16#39,
        16#32,
        16#37,
        16#2d,
        16#64,
        16#63,
        16#64,
        16#39,
        16#30,
        16#65,
        16#63,
        16#33,
        16#33,
        16#61,
        16#30,
        16#38,
        16#00,
        16#00,
        16#24,
        16#37,
        16#32,
        16#63,
        16#30,
        16#61,
        16#32,
        16#61,
        16#62,
        16#2d,
        16#33,
        16#30,
        16#38,
        16#36,
        16#2d,
        16#34,
        16#64,
        16#65,
        16#31,
        16#2d,
        16#61,
        16#39,
        16#32,
        16#37,
        16#2d,
        16#64,
        16#63,
        16#64,
        16#39,
        16#30,
        16#65,
        16#63,
        16#33,
        16#33,
        16#61,
        16#30,
        16#38,
        16#09,
        16#30,
        16#2e,
        16#30,
        16#2e,
        16#30,
        16#2e,
        16#30,
        16#3a,
        16#30,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#01,
        16#04,
        16#72,
        16#6f,
        16#6f,
        16#74,
        16#19,
        16#41,
        16#6e,
        16#64,
        16#72,
        16#65,
        16#6a,
        16#73,
        16#2d,
        16#4d,
        16#61,
        16#63,
        16#42,
        16#6f,
        16#6f,
        16#6b,
        16#2d,
        16#50,
        16#72,
        16#6f,
        16#2e,
        16#6c,
        16#6f,
        16#63,
        16#61,
        16#6c,
        16#11,
        16#43,
        16#6c,
        16#69,
        16#63,
        16#6b,
        16#48,
        16#6f,
        16#75,
        16#73,
        16#65,
        16#20,
        16#63,
        16#6c,
        16#69,
        16#65,
        16#6e,
        16#74,
        16#19,
        16#0c,
        16#bc,
        16#a9,
        16#03,
        16#00,
        16#00,
        16#01,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#02,
        16#00,
        16#08,
        16#53,
        16#45,
        16#4c,
        16#45,
        16#43,
        16#54,
        16#20,
        16#31,
        16#00
    >>,

    {ok, QueryInfo} = clickhouse_erl_protocol_query_packet:decode(Query, 54460),

    ?assertEqual(
        #{
            client_info =>
                #{
                    major => 25,
                    minor => 12,
                    protocol => 54460,
                    interface => tcp,
                    patch => 1,
                    span => not_implemented,
                    query_kind => none,
                    initial_user => <<>>,
                    initial_query_id =>
                        <<"72c0a2ab-3086-4de1-a927-dcd90ec33a08">>,
                    initial_address => <<"0.0.0.0:0">>,
                    initial_time => 0,
                    os_user => <<"root">>,
                    client_hostname => <<"Andrejs-MacBook-Pro.local">>,
                    client_name => <<"ClickHouse client">>,
                    quota_key => <<>>,
                    distributed_depth => 0,
                    parallel_replicas =>
                        #{
                            collaborate_with_initiator => false,
                            count_participating_replicas => 0,
                            number_of_current_replica => 0
                        }
                },
            query_id => <<"72c0a2ab-3086-4de1-a927-dcd90ec33a08">>,
            settings => [],
            stage => complete,
            compression => disabled,
            body => <<"SELECT 1">>,
            parameters => [],
            inter_server_secret => <<>>,
            additional_data => <<>>
        },
        QueryInfo
    ).

%%%===================================================================
%%% Compression Field Tests
%%%===================================================================

%% Test query packet encoding with compression enabled
%% Feature: compression-support
%% Validates: Requirements 5.1, 5.2
encode_query_packet_compression_enabled_test() ->
    QueryInfo = #{
        query_id => <<"test_compression_enabled">>,
        query_body => <<"SELECT 1">>,
        client_info => #{
            initial_time => 1640995200000000
        },
        settings => [],
        compression => ?COMPRESSION_ENABLED
    },

    %% Encode the query packet
    {ok, Encoded} = clickhouse_erl_protocol_query_packet:encode(QueryInfo, 54460),

    %% Remove the packet type byte for decoder
    {ok, ?CLIENT_QUERY, PacketWithoutType} = clickhouse_erl_types_primitive:decode_varint(Encoded),

    %% Decode and verify compression field
    {ok, Decoded} = clickhouse_erl_protocol_query_packet:decode(PacketWithoutType, 54460),

    %% Verify compression is enabled
    ?assertEqual(enabled, maps:get(compression, Decoded)),
    ?assertEqual(<<"test_compression_enabled">>, maps:get(query_id, Decoded)),
    ?assertEqual(<<"SELECT 1">>, maps:get(body, Decoded)).

%% Test query packet encoding with compression disabled
%% Feature: compression-support
%% Validates: Requirements 5.1, 5.2
encode_query_packet_compression_disabled_test() ->
    QueryInfo = #{
        query_id => <<"test_compression_disabled">>,
        query_body => <<"SELECT 1">>,
        client_info => #{
            initial_time => 1640995200000000
        },
        settings => [],
        compression => ?COMPRESSION_DISABLED
    },

    %% Encode the query packet
    {ok, Encoded} = clickhouse_erl_protocol_query_packet:encode(QueryInfo, 54460),

    %% Remove the packet type byte for decoder
    {ok, ?CLIENT_QUERY, PacketWithoutType} = clickhouse_erl_types_primitive:decode_varint(Encoded),

    %% Decode and verify compression field
    {ok, Decoded} = clickhouse_erl_protocol_query_packet:decode(PacketWithoutType, 54460),

    %% Verify compression is disabled
    ?assertEqual(disabled, maps:get(compression, Decoded)),
    ?assertEqual(<<"test_compression_disabled">>, maps:get(query_id, Decoded)),
    ?assertEqual(<<"SELECT 1">>, maps:get(body, Decoded)).

%% Test query packet field order with compression
%% Feature: compression-support
%% Validates: Requirements 5.1, 5.2
encode_query_packet_compression_field_order_test() ->
    QueryInfo = #{
        query_id => <<"test_field_order">>,
        query_body => <<"SELECT 1">>,
        client_info => #{
            initial_time => 1640995200000000
        },
        settings => [],
        stage => ?STAGE_COMPLETE,
        compression => ?COMPRESSION_ENABLED
    },

    %% Encode the query packet
    {ok, Encoded} = clickhouse_erl_protocol_query_packet:encode(QueryInfo, 54460),

    %% Manually decode to verify field order
    %% Expected order: PacketType, QueryId, ClientInfo, Settings, SettingsTerminator,
    %% Secret (if supported), Stage, Compression, QueryBody, Parameters (if supported)

    {ok, ?CLIENT_QUERY, Rest1} = clickhouse_erl_types_primitive:decode_varint(Encoded),
    {ok, QueryId, Rest2} = clickhouse_erl_types_primitive:decode_string(Rest1),
    ?assertEqual(<<"test_field_order">>, QueryId),

    %% Skip client info (complex structure)
    {ok, _ClientInfo, Rest3} = clickhouse_erl_protocol_client_info:decode(Rest2, 54460),

    %% Skip settings (empty list terminated with empty string)
    {ok, SettingsTerminator, Rest4} = clickhouse_erl_types_primitive:decode_string(Rest3),
    ?assertEqual(<<>>, SettingsTerminator),

    %% Skip secret (empty string for version 54460)
    {ok, Secret, Rest5} = clickhouse_erl_types_primitive:decode_string(Rest4),
    ?assertEqual(<<>>, Secret),

    %% Decode stage (should be 2 for STAGE_COMPLETE)
    {ok, Stage, Rest6} = clickhouse_erl_types_primitive:decode_varint(Rest5),
    ?assertEqual(?STAGE_COMPLETE, Stage),

    %% Decode compression (should be 1 for COMPRESSION_ENABLED)
    {ok, Compression, Rest7} = clickhouse_erl_types_primitive:decode_varint(Rest6),
    ?assertEqual(?COMPRESSION_ENABLED, Compression),

    %% Decode query body
    {ok, QueryBody, _Rest8} = clickhouse_erl_types_primitive:decode_string(Rest7),
    ?assertEqual(<<"SELECT 1">>, QueryBody).
