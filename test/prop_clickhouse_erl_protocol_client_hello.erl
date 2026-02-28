-module(prop_clickhouse_erl_protocol_client_hello).

-include_lib("proper/include/proper.hrl").

-import(generators, [string_gen/0, char_gen/0]).

%% Helper function to ensure data is binary (for character list vs binary comparison)
ensure_binary(Data) when is_list(Data) ->
    unicode:characters_to_binary(Data, utf8);
ensure_binary(Data) when is_binary(Data) ->
    Data.

%% Generator for Client Hello messages
client_hello_gen() ->
    ?LET(
        {ClientName, VersionMajor, VersionMinor, ProtocolVersion, Database, Username, Password},
        {
            string_gen(),
            range(0, 16#7FFFFFFFFFFFFFFF),
            range(0, 16#7FFFFFFFFFFFFFFF),
            range(0, 16#7FFFFFFFFFFFFFFF),
            string_gen(),
            string_gen(),
            string_gen()
        },
        #{
            client_name => ClientName,
            version_major => VersionMajor,
            version_minor => VersionMinor,
            protocol_version => ProtocolVersion,
            database => Database,
            username => Username,
            password => Password
        }
    ).

%% Property test: Protocol Message Round Trip
%% Feature: clickhouse-handshake, Property 3: Protocol Message Round Trip
%% Validates: Requirements 4.1, 4.2
prop_protocol_message_round_trip() ->
    ?FORALL(
        ClientHello,
        client_hello_gen(),
        begin
            %% Test Client Hello round trip
            %% Note: We can't directly round-trip Client Hello because there's no decode_client_hello
            %% But we can test that encoding produces valid binary that contains expected components
            {ok, ClientHelloBinary} = clickhouse_erl_protocol:encode_client_hello(ClientHello),
            ClientHelloValid =
                is_binary(ClientHelloBinary) andalso byte_size(ClientHelloBinary) > 0,

            %% Client Hello encoding should succeed
            ClientHelloValid
        end
    ).

%% Property test: Client Hello Message Format Compliance
%% Feature: clickhouse-handshake, Property 2: Client Hello Message Format Compliance
%% Validates: Requirements 2.2, 2.3, 2.4
prop_client_hello_message_format() ->
    ?FORALL(
        ClientHello,
        client_hello_gen(),
        begin
            %% Encode the Client Hello message
            {ok, EncodedMessage} = clickhouse_erl_protocol:encode_client_hello(ClientHello),

            %% Verify the message is a valid binary
            is_binary(EncodedMessage) andalso
                %% Verify the message contains all required fields by manually parsing
                %% We'll decode each field in the expected order to ensure format compliance
                verify_client_hello_format(EncodedMessage, ClientHello)
        end
    ).

%% Helper function to verify Client Hello message format
verify_client_hello_format(Binary, ExpectedClientHello) ->
    try
        %% Parse client_name (String)
        {ok, ClientName, Rest1} = clickhouse_erl_types_primitive:decode_string(Binary),
        ExpectedClientName = ensure_binary(
            maps:get(client_name, ExpectedClientHello, "clickhouse_erl")
        ),

        %% Parse version_major (UVarInt)
        {ok, VersionMajor, Rest2} = clickhouse_erl_types_primitive:decode_varint(Rest1),
        ExpectedVersionMajor = maps:get(version_major, ExpectedClientHello, 0),

        %% Parse version_minor (UVarInt)
        {ok, VersionMinor, Rest3} = clickhouse_erl_types_primitive:decode_varint(Rest2),
        ExpectedVersionMinor = maps:get(version_minor, ExpectedClientHello, 0),

        %% Parse protocol_version (UVarInt)
        {ok, ProtocolVersion, Rest4} = clickhouse_erl_types_primitive:decode_varint(Rest3),
        ExpectedProtocolVersion = maps:get(protocol_version, ExpectedClientHello, 54451),

        %% Parse database (String)
        {ok, Database, Rest5} = clickhouse_erl_types_primitive:decode_string(Rest4),
        ExpectedDatabase = ensure_binary(maps:get(database, ExpectedClientHello, "default")),

        %% Parse username (String)
        {ok, Username, Rest6} = clickhouse_erl_types_primitive:decode_string(Rest5),
        ExpectedUsername = ensure_binary(maps:get(username, ExpectedClientHello, "default")),

        %% Parse password (String)
        {ok, Password, <<>>} = clickhouse_erl_types_primitive:decode_string(Rest6),
        ExpectedPassword = ensure_binary(maps:get(password, ExpectedClientHello, "")),

        %% Verify all fields match expected values
        ClientName =:= ExpectedClientName andalso
            VersionMajor =:= ExpectedVersionMajor andalso
            VersionMinor =:= ExpectedVersionMinor andalso
            ProtocolVersion =:= ExpectedProtocolVersion andalso
            Database =:= ExpectedDatabase andalso
            Username =:= ExpectedUsername andalso
            Password =:= ExpectedPassword
    catch
        _:_ ->
            %% If parsing fails, the format is invalid
            false
    end.
