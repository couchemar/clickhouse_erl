-module(clickhouse_erl_protocol_client_hello_tests).

-include_lib("eunit/include/eunit.hrl").

%% Unit tests for Client_Hello encoding edge cases
%% Requirements: 2.5

%% Test empty strings in all string fields
client_hello_empty_strings_test() ->
    ClientHello = #{
        client_name => "",
        version_major => 0,
        version_minor => 1,
        protocol_version => 54451,
        database => "",
        username => "",
        password => ""
    },
    {ok, EncodedMessage} = clickhouse_erl_protocol:encode_client_hello(ClientHello),
    ?assert(is_binary(EncodedMessage)),
    ?assert(byte_size(EncodedMessage) > 0),

    %% Verify we can decode the fields back correctly
    {ok, ClientName, Rest1} = clickhouse_erl_types_primitive:decode_string(EncodedMessage),
    ?assertEqual(<<"">>, ClientName),
    {ok, VersionMajor, Rest2} = clickhouse_erl_types_primitive:decode_varint(Rest1),
    ?assertEqual(0, VersionMajor),
    {ok, VersionMinor, Rest3} = clickhouse_erl_types_primitive:decode_varint(Rest2),
    ?assertEqual(1, VersionMinor),
    {ok, ProtocolVersion, Rest4} = clickhouse_erl_types_primitive:decode_varint(Rest3),
    ?assertEqual(54451, ProtocolVersion),
    {ok, Database, Rest5} = clickhouse_erl_types_primitive:decode_string(Rest4),
    ?assertEqual(<<"">>, Database),
    {ok, Username, Rest6} = clickhouse_erl_types_primitive:decode_string(Rest5),
    ?assertEqual(<<"">>, Username),
    {ok, Password, <<>>} = clickhouse_erl_types_primitive:decode_string(Rest6),
    ?assertEqual(<<"">>, Password).

%% Test special characters and Unicode in string fields
client_hello_special_characters_test() ->
    ClientHello = #{
        client_name => "test-client_123",
        version_major => 1,
        version_minor => 0,
        protocol_version => 54451,
        database => "test_db-123",
        username => "user@domain.com",
        password => "p@ssw0rd!#$%"
    },
    {ok, EncodedMessage} = clickhouse_erl_protocol:encode_client_hello(ClientHello),
    ?assert(is_binary(EncodedMessage)),
    ?assert(byte_size(EncodedMessage) > 0).

%% Test Unicode characters in string fields
client_hello_unicode_test() ->
    ClientHello = #{
        % Russian text
        client_name => "тест-клиент",
        version_major => 1,
        version_minor => 0,
        protocol_version => 54451,
        % Chinese text
        database => "数据库",
        % Chinese text
        username => "用户",
        % Russian text
        password => "пароль"
    },
    {ok, EncodedMessage} = clickhouse_erl_protocol:encode_client_hello(ClientHello),
    ?assert(is_binary(EncodedMessage)),
    ?assert(byte_size(EncodedMessage) > 0),

    %% Verify Unicode strings are preserved
    {ok, ClientName, _Rest1} = clickhouse_erl_types_primitive:decode_string(EncodedMessage),
    ?assertEqual(<<"тест-клиент"/utf8>>, ClientName).

%% Test boundary values for integer fields
client_hello_boundary_values_test() ->
    %% Test with maximum reasonable values
    ClientHello = #{
        client_name => "test",
        % Max safe integer for varint
        version_major => 16#7FFFFFFFFFFFFFFF,
        version_minor => 16#7FFFFFFFFFFFFFFF,
        protocol_version => 16#7FFFFFFFFFFFFFFF,
        database => "test",
        username => "test",
        password => "test"
    },
    {ok, EncodedMessage} = clickhouse_erl_protocol:encode_client_hello(ClientHello),
    ?assert(is_binary(EncodedMessage)),
    ?assert(byte_size(EncodedMessage) > 0).

%% Test zero values for integer fields
client_hello_zero_values_test() ->
    ClientHello = #{
        client_name => "test",
        version_major => 0,
        version_minor => 0,
        protocol_version => 0,
        database => "test",
        username => "test",
        password => "test"
    },
    {ok, EncodedMessage} = clickhouse_erl_protocol:encode_client_hello(ClientHello),
    ?assert(is_binary(EncodedMessage)),
    ?assert(byte_size(EncodedMessage) > 0).

%% Test very long strings
client_hello_long_strings_test() ->
    % 1000 character string
    LongString = lists:duplicate(1000, $a),
    ClientHello = #{
        client_name => LongString,
        version_major => 1,
        version_minor => 0,
        protocol_version => 54451,
        database => LongString,
        username => LongString,
        password => LongString
    },
    {ok, EncodedMessage} = clickhouse_erl_protocol:encode_client_hello(ClientHello),
    ?assert(is_binary(EncodedMessage)),
    ?assert(byte_size(EncodedMessage) > 0).

%% Test with missing optional fields (should use defaults)
client_hello_missing_fields_test() ->
    %% Only provide required fields, others should use defaults
    ClientHello = #{
        version_major => 2,
        version_minor => 1
    },
    {ok, EncodedMessage} = clickhouse_erl_protocol:encode_client_hello(ClientHello),
    ?assert(is_binary(EncodedMessage)),
    ?assert(byte_size(EncodedMessage) > 0),

    %% Verify defaults are used
    {ok, ClientName, Rest1} = clickhouse_erl_types_primitive:decode_string(EncodedMessage),
    % Default client name
    ?assertEqual(<<"clickhouse_erl">>, ClientName),
    {ok, VersionMajor, Rest2} = clickhouse_erl_types_primitive:decode_varint(Rest1),
    % Provided value
    ?assertEqual(2, VersionMajor),
    {ok, VersionMinor, Rest3} = clickhouse_erl_types_primitive:decode_varint(Rest2),
    % Provided value
    ?assertEqual(1, VersionMinor),
    {ok, ProtocolVersion, Rest4} = clickhouse_erl_types_primitive:decode_varint(Rest3),
    % Default protocol version
    ?assertEqual(54460, ProtocolVersion),
    {ok, Database, Rest5} = clickhouse_erl_types_primitive:decode_string(Rest4),
    % Default database
    ?assertEqual(<<"default">>, Database),
    {ok, Username, Rest6} = clickhouse_erl_types_primitive:decode_string(Rest5),
    % Default username
    ?assertEqual(<<"default">>, Username),
    {ok, Password, <<>>} = clickhouse_erl_types_primitive:decode_string(Rest6),
    % Default password
    ?assertEqual(<<"">>, Password).

%% Test empty map (should use all defaults)
client_hello_empty_map_test() ->
    ClientHello = #{},
    {ok, EncodedMessage} = clickhouse_erl_protocol:encode_client_hello(ClientHello),
    ?assert(is_binary(EncodedMessage)),
    ?assert(byte_size(EncodedMessage) > 0),

    %% Verify all defaults are used
    {ok, ClientName, Rest1} = clickhouse_erl_types_primitive:decode_string(EncodedMessage),
    ?assertEqual(<<"clickhouse_erl">>, ClientName),
    {ok, VersionMajor, Rest2} = clickhouse_erl_types_primitive:decode_varint(Rest1),
    ?assertEqual(0, VersionMajor),
    {ok, VersionMinor, Rest3} = clickhouse_erl_types_primitive:decode_varint(Rest2),
    ?assertEqual(1, VersionMinor),
    {ok, ProtocolVersion, Rest4} = clickhouse_erl_types_primitive:decode_varint(Rest3),
    ?assertEqual(54460, ProtocolVersion),
    {ok, Database, Rest5} = clickhouse_erl_types_primitive:decode_string(Rest4),
    ?assertEqual(<<"default">>, Database),
    {ok, Username, Rest6} = clickhouse_erl_types_primitive:decode_string(Rest5),
    ?assertEqual(<<"default">>, Username),
    {ok, Password, <<>>} = clickhouse_erl_types_primitive:decode_string(Rest6),
    ?assertEqual(<<"">>, Password).
