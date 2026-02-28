%% @doc ClickHouse protocol features and version compatibility.
%%
%% This module provides functions to check which features are available
%% in different protocol versions, based on the ClickHouse protocol.
%% Derived from ch-go/proto/feature.go
-module(clickhouse_erl_protocol_features).

%% Public API
-export([
    has_feature/2,
    feature_version/1,

    % Feature names for convenience
    feature_temp_tables/0,
    feature_block_info/0,
    feature_timezone/0,
    feature_quota_key_in_client_info/0,
    feature_display_name/0,
    feature_version_patch/0,
    feature_server_logs/0,
    feature_column_defaults_metadata/0,
    feature_client_write_info/0,
    feature_settings_serialized_as_strings/0,
    feature_inter_server_secret/0,
    feature_open_telemetry/0,
    feature_x_forwarded_for_in_client_info/0,
    feature_referer_in_client_info/0,
    feature_distributed_depth/0,
    feature_query_start_time/0,
    feature_profile_events/0,
    feature_parallel_replicas/0,
    feature_custom_serialization/0,
    feature_quota_key/0,
    feature_parameters/0,
    feature_server_query_time_in_progress/0,
    feature_json_strings/0
]).

%% Feature version constants
%% From ch-go/proto/feature.go

-define(FEATURE_TEMP_TABLES, 50264).
-define(FEATURE_BLOCK_INFO, 51903).
-define(FEATURE_TIMEZONE, 54058).
-define(FEATURE_QUOTA_KEY_IN_CLIENT_INFO, 54060).
-define(FEATURE_DISPLAY_NAME, 54372).
-define(FEATURE_VERSION_PATCH, 54401).
-define(FEATURE_SERVER_LOGS, 54406).
-define(FEATURE_COLUMN_DEFAULTS_METADATA, 54410).
-define(FEATURE_CLIENT_WRITE_INFO, 54420).
-define(FEATURE_SETTINGS_SERIALIZED_AS_STRINGS, 54429).
-define(FEATURE_INTER_SERVER_SECRET, 54441).
-define(FEATURE_OPEN_TELEMETRY, 54442).
-define(FEATURE_X_FORWARDED_FOR_IN_CLIENT_INFO, 54443).
-define(FEATURE_REFERER_IN_CLIENT_INFO, 54447).
-define(FEATURE_DISTRIBUTED_DEPTH, 54448).
-define(FEATURE_QUERY_START_TIME, 54449).
-define(FEATURE_PROFILE_EVENTS, 54451).
-define(FEATURE_PARALLEL_REPLICAS, 54453).
-define(FEATURE_CUSTOM_SERIALIZATION, 54454).
-define(FEATURE_QUOTA_KEY, 54458).
-define(FEATURE_PARAMETERS, 54459).
-define(FEATURE_SERVER_QUERY_TIME_IN_PROGRESS, 54460).
-define(FEATURE_JSON_STRINGS, 54475).

%% @doc Check if a feature is available in the given protocol version.
%%
%% Returns true if the protocol version is >= the version when the feature was introduced.
-spec has_feature(Feature :: atom() | non_neg_integer(), Version :: non_neg_integer()) -> boolean().
has_feature(Feature, Version) when is_atom(Feature) ->
    FeatureVersion = feature_version(Feature),
    Version >= FeatureVersion;
has_feature(FeatureVersion, Version) when is_integer(FeatureVersion) ->
    Version >= FeatureVersion.

%% @doc Get the protocol version when a feature was introduced.
-spec feature_version(Feature :: atom()) -> non_neg_integer().
feature_version(temp_tables) -> ?FEATURE_TEMP_TABLES;
feature_version(block_info) -> ?FEATURE_BLOCK_INFO;
feature_version(timezone) -> ?FEATURE_TIMEZONE;
feature_version(quota_key_in_client_info) -> ?FEATURE_QUOTA_KEY_IN_CLIENT_INFO;
feature_version(display_name) -> ?FEATURE_DISPLAY_NAME;
feature_version(version_patch) -> ?FEATURE_VERSION_PATCH;
feature_version(server_logs) -> ?FEATURE_SERVER_LOGS;
feature_version(column_defaults_metadata) -> ?FEATURE_COLUMN_DEFAULTS_METADATA;
feature_version(client_write_info) -> ?FEATURE_CLIENT_WRITE_INFO;
feature_version(settings_serialized_as_strings) -> ?FEATURE_SETTINGS_SERIALIZED_AS_STRINGS;
feature_version(inter_server_secret) -> ?FEATURE_INTER_SERVER_SECRET;
feature_version(open_telemetry) -> ?FEATURE_OPEN_TELEMETRY;
feature_version(x_forwarded_for_in_client_info) -> ?FEATURE_X_FORWARDED_FOR_IN_CLIENT_INFO;
feature_version(referer_in_client_info) -> ?FEATURE_REFERER_IN_CLIENT_INFO;
feature_version(distributed_depth) -> ?FEATURE_DISTRIBUTED_DEPTH;
feature_version(query_start_time) -> ?FEATURE_QUERY_START_TIME;
feature_version(profile_events) -> ?FEATURE_PROFILE_EVENTS;
feature_version(parallel_replicas) -> ?FEATURE_PARALLEL_REPLICAS;
feature_version(custom_serialization) -> ?FEATURE_CUSTOM_SERIALIZATION;
feature_version(quota_key) -> ?FEATURE_QUOTA_KEY;
feature_version(parameters) -> ?FEATURE_PARAMETERS;
feature_version(server_query_time_in_progress) -> ?FEATURE_SERVER_QUERY_TIME_IN_PROGRESS;
feature_version(json_strings) -> ?FEATURE_JSON_STRINGS.

%% Convenience functions that return the feature version
feature_temp_tables() -> ?FEATURE_TEMP_TABLES.
feature_block_info() -> ?FEATURE_BLOCK_INFO.
feature_timezone() -> ?FEATURE_TIMEZONE.
feature_quota_key_in_client_info() -> ?FEATURE_QUOTA_KEY_IN_CLIENT_INFO.
feature_display_name() -> ?FEATURE_DISPLAY_NAME.
feature_version_patch() -> ?FEATURE_VERSION_PATCH.
feature_server_logs() -> ?FEATURE_SERVER_LOGS.
feature_column_defaults_metadata() -> ?FEATURE_COLUMN_DEFAULTS_METADATA.
feature_client_write_info() -> ?FEATURE_CLIENT_WRITE_INFO.
feature_settings_serialized_as_strings() -> ?FEATURE_SETTINGS_SERIALIZED_AS_STRINGS.
feature_inter_server_secret() -> ?FEATURE_INTER_SERVER_SECRET.
feature_open_telemetry() -> ?FEATURE_OPEN_TELEMETRY.
feature_x_forwarded_for_in_client_info() -> ?FEATURE_X_FORWARDED_FOR_IN_CLIENT_INFO.
feature_referer_in_client_info() -> ?FEATURE_REFERER_IN_CLIENT_INFO.
feature_distributed_depth() -> ?FEATURE_DISTRIBUTED_DEPTH.
feature_query_start_time() -> ?FEATURE_QUERY_START_TIME.
feature_profile_events() -> ?FEATURE_PROFILE_EVENTS.
feature_parallel_replicas() -> ?FEATURE_PARALLEL_REPLICAS.
feature_custom_serialization() -> ?FEATURE_CUSTOM_SERIALIZATION.
feature_quota_key() -> ?FEATURE_QUOTA_KEY.
feature_parameters() -> ?FEATURE_PARAMETERS.
feature_server_query_time_in_progress() -> ?FEATURE_SERVER_QUERY_TIME_IN_PROGRESS.
feature_json_strings() -> ?FEATURE_JSON_STRINGS.
