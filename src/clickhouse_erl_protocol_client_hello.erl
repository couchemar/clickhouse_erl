-module(clickhouse_erl_protocol_client_hello).

-export([
    encode/1
]).

-include_lib("kernel/include/logger.hrl").
-include("clickhouse_erl_protocol.hrl").

%% Default values
-define(DEFAULT_DATABASE, "default").
-define(DEFAULT_USERNAME, "default").
-define(DEFAULT_PASSWORD, "").
-define(DEFAULT_CLIENT_NAME, "clickhouse_erl").
-define(DEFAULT_CLIENT_VERSION, {0, 1, 0}).

encode(ClientInfo) ->
    ClientName = maps:get(client_name, ClientInfo, ?DEFAULT_CLIENT_NAME),
    VersionMajor = maps:get(version_major, ClientInfo, 0),
    VersionMinor = maps:get(version_minor, ClientInfo, 1),
    ProtocolVersion = maps:get(protocol_version, ClientInfo, ?PROTOCOL_VERSION),
    Database = maps:get(database, ClientInfo, ?DEFAULT_DATABASE),
    Username = maps:get(username, ClientInfo, ?DEFAULT_USERNAME),
    Password = maps:get(password, ClientInfo, ?DEFAULT_PASSWORD),

    % Validate input types
    case
        validate_client_hello_fields(
            ClientName,
            VersionMajor,
            VersionMinor,
            ProtocolVersion,
            Database,
            Username,
            Password
        )
    of
        ok ->
            %% Encode all fields
            ClientNameBin = clickhouse_erl_types_primitive:encode_string(ClientName),
            VersionMajorBin = clickhouse_erl_types_primitive:encode_varint(VersionMajor),
            VersionMinorBin = clickhouse_erl_types_primitive:encode_varint(VersionMinor),
            ProtocolVersionBin = clickhouse_erl_types_primitive:encode_varint(ProtocolVersion),
            DatabaseBin = clickhouse_erl_types_primitive:encode_string(Database),
            UsernameBin = clickhouse_erl_types_primitive:encode_string(Username),
            PasswordBin = clickhouse_erl_types_primitive:encode_string(Password),

            %% Combine all fields
            Message =
                <<ClientNameBin/binary, VersionMajorBin/binary, VersionMinorBin/binary,
                    ProtocolVersionBin/binary, DatabaseBin/binary, UsernameBin/binary,
                    PasswordBin/binary>>,

            {ok, Message};
        {error, Field} ->
            {error, {encoding_error, Field}}
    end.

%% @doc Validate Client Hello message fields
-spec validate_client_hello_fields(
    ClientName,
    VersionMajor,
    VersionMinor,
    ProtocolVersion,
    Database,
    Username,
    Password
) ->
    ok | {error, atom()}
when
    ClientName :: term(),
    VersionMajor :: term(),
    VersionMinor :: term(),
    ProtocolVersion :: term(),
    Database :: term(),
    Username :: term(),
    Password :: term().
validate_client_hello_fields(
    ClientName,
    VersionMajor,
    VersionMinor,
    ProtocolVersion,
    Database,
    Username,
    Password
) ->
    maybe
        ok ?= validate_string_field(ClientName, client_name),
        ok ?= validate_non_negative_integer(VersionMajor, version_major),
        ok ?= validate_non_negative_integer(VersionMinor, version_minor),
        ok ?= validate_non_negative_integer(ProtocolVersion, protocol_version),
        ok ?= validate_string_field(Database, database),
        ok ?= validate_string_field(Username, username),
        ok ?= validate_string_field(Password, password),
        ok
    end.

%% @doc Validate that a field is a string (list or binary)
-spec validate_string_field(term(), atom()) -> ok | {error, atom()}.
validate_string_field(Value, _FieldName) when is_list(Value); is_binary(Value) ->
    ok;
validate_string_field(_Value, FieldName) ->
    {error, FieldName}.

%% @doc Validate that a field is a non-negative integer
-spec validate_non_negative_integer(term(), atom()) -> ok | {error, atom()}.
validate_non_negative_integer(Value, _FieldName) when is_integer(Value), Value >= 0 ->
    ok;
validate_non_negative_integer(_Value, FieldName) ->
    {error, FieldName}.
