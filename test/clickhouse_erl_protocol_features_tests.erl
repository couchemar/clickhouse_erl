-module(clickhouse_erl_protocol_features_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test feature version lookups
feature_version_test() ->
    ?assertEqual(54420, clickhouse_erl_protocol_features:feature_version(client_write_info)),
    ?assertEqual(
        54429, clickhouse_erl_protocol_features:feature_version(settings_serialized_as_strings)
    ),
    ?assertEqual(54441, clickhouse_erl_protocol_features:feature_version(inter_server_secret)),
    ?assertEqual(54442, clickhouse_erl_protocol_features:feature_version(open_telemetry)),
    ?assertEqual(54448, clickhouse_erl_protocol_features:feature_version(distributed_depth)),
    ?assertEqual(54449, clickhouse_erl_protocol_features:feature_version(query_start_time)),
    ?assertEqual(54401, clickhouse_erl_protocol_features:feature_version(version_patch)),
    ?assertEqual(54060, clickhouse_erl_protocol_features:feature_version(quota_key_in_client_info)),
    ?assertEqual(54453, clickhouse_erl_protocol_features:feature_version(parallel_replicas)),
    ?assertEqual(54459, clickhouse_erl_protocol_features:feature_version(parameters)).

%% Test has_feature with atom
has_feature_atom_test() ->
    % Version 54450
    ?assert(clickhouse_erl_protocol_features:has_feature(client_write_info, 54450)),
    ?assert(clickhouse_erl_protocol_features:has_feature(settings_serialized_as_strings, 54450)),
    ?assert(clickhouse_erl_protocol_features:has_feature(inter_server_secret, 54450)),
    ?assert(clickhouse_erl_protocol_features:has_feature(open_telemetry, 54450)),
    ?assert(clickhouse_erl_protocol_features:has_feature(distributed_depth, 54450)),
    ?assert(clickhouse_erl_protocol_features:has_feature(query_start_time, 54450)),
    ?assert(clickhouse_erl_protocol_features:has_feature(version_patch, 54450)),
    ?assert(clickhouse_erl_protocol_features:has_feature(quota_key_in_client_info, 54450)),

    % Features not in 54450
    ?assertNot(clickhouse_erl_protocol_features:has_feature(parallel_replicas, 54450)),
    ?assertNot(clickhouse_erl_protocol_features:has_feature(parameters, 54450)).

%% Test has_feature with integer
has_feature_integer_test() ->
    ?assert(clickhouse_erl_protocol_features:has_feature(54420, 54450)),
    ?assert(clickhouse_erl_protocol_features:has_feature(54449, 54450)),
    ?assertNot(clickhouse_erl_protocol_features:has_feature(54453, 54450)),
    ?assertNot(clickhouse_erl_protocol_features:has_feature(54459, 54450)).

%% Test convenience functions
convenience_functions_test() ->
    ?assertEqual(54420, clickhouse_erl_protocol_features:feature_client_write_info()),
    ?assertEqual(54429, clickhouse_erl_protocol_features:feature_settings_serialized_as_strings()),
    ?assertEqual(54441, clickhouse_erl_protocol_features:feature_inter_server_secret()),
    ?assertEqual(54442, clickhouse_erl_protocol_features:feature_open_telemetry()),
    ?assertEqual(54448, clickhouse_erl_protocol_features:feature_distributed_depth()),
    ?assertEqual(54449, clickhouse_erl_protocol_features:feature_query_start_time()),
    ?assertEqual(54401, clickhouse_erl_protocol_features:feature_version_patch()),
    ?assertEqual(54060, clickhouse_erl_protocol_features:feature_quota_key_in_client_info()),
    ?assertEqual(54453, clickhouse_erl_protocol_features:feature_parallel_replicas()),
    ?assertEqual(54459, clickhouse_erl_protocol_features:feature_parameters()).

%% Test boundary conditions
boundary_conditions_test() ->
    % Exactly at the feature version
    ?assert(clickhouse_erl_protocol_features:has_feature(client_write_info, 54420)),
    ?assert(clickhouse_erl_protocol_features:has_feature(parameters, 54459)),

    % One below the feature version
    ?assertNot(clickhouse_erl_protocol_features:has_feature(client_write_info, 54419)),
    ?assertNot(clickhouse_erl_protocol_features:has_feature(parameters, 54458)).
