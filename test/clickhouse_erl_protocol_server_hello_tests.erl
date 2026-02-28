-module(clickhouse_erl_protocol_server_hello_tests).

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

-import(generators, [string_gen/0, char_gen/0]).

%% Generator for Server Hello messages
server_hello_gen() ->
    ?LET(
        {Name, VersionMajor, VersionMinor, Revision, Timezone, DisplayName, VersionPatch},
        {
            string_gen(),
            range(0, 16#7FFFFFFFFFFFFFFF),
            range(0, 16#7FFFFFFFFFFFFFFF),
            range(0, 16#7FFFFFFFFFFFFFFF),
            string_gen(),
            string_gen(),
            range(0, 16#7FFFFFFFFFFFFFFF)
        },
        #{
            name => Name,
            version_major => VersionMajor,
            version_minor => VersionMinor,
            revision => Revision,
            timezone => Timezone,
            display_name => DisplayName,
            version_patch => VersionPatch
        }
    ).

%% Property test: Server Hello Parsing Completeness
%% Feature: clickhouse-handshake, Property 4: Server Hello Parsing Completeness
%% Validates: Requirements 3.2
prop_server_hello_parsing_completeness() ->
    ?FORALL(
        ServerHello,
        server_hello_gen(),
        begin
            %% Manually encode a Server Hello message with the generated data
            Name = maps:get(name, ServerHello),
            VersionMajor = maps:get(version_major, ServerHello),
            VersionMinor = maps:get(version_minor, ServerHello),
            Revision = maps:get(revision, ServerHello),
            Timezone = maps:get(timezone, ServerHello),
            DisplayName = maps:get(display_name, ServerHello),
            VersionPatch = maps:get(version_patch, ServerHello),

            %% Encode the message manually using protocol functions
            NameBin = clickhouse_erl_types_primitive:encode_string(Name),
            VersionMajorBin = clickhouse_erl_types_primitive:encode_varint(VersionMajor),
            VersionMinorBin = clickhouse_erl_types_primitive:encode_varint(VersionMinor),
            RevisionBin = clickhouse_erl_types_primitive:encode_varint(Revision),
            TimezoneBin = clickhouse_erl_types_primitive:encode_string(Timezone),
            DisplayNameBin = clickhouse_erl_types_primitive:encode_string(DisplayName),
            VersionPatchBin = clickhouse_erl_types_primitive:encode_varint(VersionPatch),

            ServerHelloBinary =
                <<NameBin/binary, VersionMajorBin/binary, VersionMinorBin/binary,
                    RevisionBin/binary, TimezoneBin/binary, DisplayNameBin/binary,
                    VersionPatchBin/binary>>,

            %% Decode the message and verify all fields are extracted correctly
            case clickhouse_erl_protocol:decode_server_hello(ServerHelloBinary) of
                {ok, ParsedServerInfo} ->
                    %% Verify all required fields are present and match expected values
                    %% Convert expected strings to binaries for comparison
                    ExpectedName = unicode:characters_to_binary(Name, utf8),
                    ExpectedTimezone = unicode:characters_to_binary(Timezone, utf8),
                    ExpectedDisplayName = unicode:characters_to_binary(DisplayName, utf8),

                    maps:get(name, ParsedServerInfo) =:= ExpectedName andalso
                        maps:get(version_major, ParsedServerInfo) =:= VersionMajor andalso
                        maps:get(version_minor, ParsedServerInfo) =:= VersionMinor andalso
                        maps:get(revision, ParsedServerInfo) =:= Revision andalso
                        maps:get(timezone, ParsedServerInfo) =:= ExpectedTimezone andalso
                        maps:get(display_name, ParsedServerInfo) =:= ExpectedDisplayName andalso
                        maps:get(version_patch, ParsedServerInfo) =:= VersionPatch;
                {error, _} ->
                    %% Parsing should not fail for valid data
                    false
            end
        end
    ).

%% Unit tests for Server_Hello decoding
%% Requirements: 3.1, 3.2

%% Test successful Server_Hello decoding with typical values
server_hello_decode_success_test() ->
    %% Create a valid Server_Hello message manually
    Name = "ClickHouse",
    VersionMajor = 23,
    VersionMinor = 8,
    Revision = 54460,
    Timezone = "UTC",
    DisplayName = "ClickHouse server",
    VersionPatch = 1,

    %% Encode the message manually
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),
    VersionMajorBin = clickhouse_erl_types_primitive:encode_varint(VersionMajor),
    VersionMinorBin = clickhouse_erl_types_primitive:encode_varint(VersionMinor),
    RevisionBin = clickhouse_erl_types_primitive:encode_varint(Revision),
    TimezoneBin = clickhouse_erl_types_primitive:encode_string(Timezone),
    DisplayNameBin = clickhouse_erl_types_primitive:encode_string(DisplayName),
    VersionPatchBin = clickhouse_erl_types_primitive:encode_varint(VersionPatch),

    ServerHelloBinary =
        <<NameBin/binary, VersionMajorBin/binary, VersionMinorBin/binary, RevisionBin/binary,
            TimezoneBin/binary, DisplayNameBin/binary, VersionPatchBin/binary>>,

    %% Decode and verify
    {ok, ServerInfo} = clickhouse_erl_protocol:decode_server_hello(ServerHelloBinary),
    ?assertEqual(unicode:characters_to_binary(Name, utf8), maps:get(name, ServerInfo)),
    ?assertEqual(VersionMajor, maps:get(version_major, ServerInfo)),
    ?assertEqual(VersionMinor, maps:get(version_minor, ServerInfo)),
    ?assertEqual(Revision, maps:get(revision, ServerInfo)),
    ?assertEqual(unicode:characters_to_binary(Timezone, utf8), maps:get(timezone, ServerInfo)),
    ?assertEqual(
        unicode:characters_to_binary(DisplayName, utf8), maps:get(display_name, ServerInfo)
    ),
    ?assertEqual(VersionPatch, maps:get(version_patch, ServerInfo)).

%% Test Server_Hello decoding with empty strings
server_hello_empty_strings_test() ->
    %% Create a Server_Hello message with empty strings
    Name = "",
    VersionMajor = 0,
    VersionMinor = 0,
    Revision = 0,
    Timezone = "",
    DisplayName = "",
    VersionPatch = 0,

    %% Encode the message manually
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),
    VersionMajorBin = clickhouse_erl_types_primitive:encode_varint(VersionMajor),
    VersionMinorBin = clickhouse_erl_types_primitive:encode_varint(VersionMinor),
    RevisionBin = clickhouse_erl_types_primitive:encode_varint(Revision),
    TimezoneBin = clickhouse_erl_types_primitive:encode_string(Timezone),
    DisplayNameBin = clickhouse_erl_types_primitive:encode_string(DisplayName),
    VersionPatchBin = clickhouse_erl_types_primitive:encode_varint(VersionPatch),

    ServerHelloBinary =
        <<NameBin/binary, VersionMajorBin/binary, VersionMinorBin/binary, RevisionBin/binary,
            TimezoneBin/binary, DisplayNameBin/binary, VersionPatchBin/binary>>,

    %% Decode and verify
    {ok, ServerInfo} = clickhouse_erl_protocol:decode_server_hello(ServerHelloBinary),
    ?assertEqual(<<>>, maps:get(name, ServerInfo)),
    ?assertEqual(0, maps:get(version_major, ServerInfo)),
    ?assertEqual(0, maps:get(version_minor, ServerInfo)),
    ?assertEqual(0, maps:get(revision, ServerInfo)),
    ?assertEqual(<<>>, maps:get(timezone, ServerInfo)),
    ?assertEqual(<<>>, maps:get(display_name, ServerInfo)),
    ?assertEqual(0, maps:get(version_patch, ServerInfo)).

%% Test Server_Hello decoding with Unicode strings
server_hello_unicode_test() ->
    %% Create a Server_Hello message with Unicode strings
    Name = "ClickHouse数据库",
    VersionMajor = 23,
    VersionMinor = 8,
    Revision = 54460,
    Timezone = "Europe/Москва",
    DisplayName = "ClickHouse服务器",
    VersionPatch = 1,

    %% Encode the message manually
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),
    VersionMajorBin = clickhouse_erl_types_primitive:encode_varint(VersionMajor),
    VersionMinorBin = clickhouse_erl_types_primitive:encode_varint(VersionMinor),
    RevisionBin = clickhouse_erl_types_primitive:encode_varint(Revision),
    TimezoneBin = clickhouse_erl_types_primitive:encode_string(Timezone),
    DisplayNameBin = clickhouse_erl_types_primitive:encode_string(DisplayName),
    VersionPatchBin = clickhouse_erl_types_primitive:encode_varint(VersionPatch),

    ServerHelloBinary =
        <<NameBin/binary, VersionMajorBin/binary, VersionMinorBin/binary, RevisionBin/binary,
            TimezoneBin/binary, DisplayNameBin/binary, VersionPatchBin/binary>>,

    %% Decode and verify
    {ok, ServerInfo} = clickhouse_erl_protocol:decode_server_hello(ServerHelloBinary),
    ?assertEqual(unicode:characters_to_binary(Name, utf8), maps:get(name, ServerInfo)),
    ?assertEqual(unicode:characters_to_binary(Timezone, utf8), maps:get(timezone, ServerInfo)),
    ?assertEqual(
        unicode:characters_to_binary(DisplayName, utf8), maps:get(display_name, ServerInfo)
    ).

%% Test Server_Hello decoding error cases
%% Requirements: 3.3

%% Test truncated Server_Hello message
server_hello_truncated_test() ->
    %% Create a truncated message (only name field)
    Name = "ClickHouse",
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),

    %% Try to decode - should fail
    Result = clickhouse_erl_protocol:decode_server_hello(NameBin),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% Test completely empty binary
server_hello_empty_binary_test() ->
    Result = clickhouse_erl_protocol:decode_server_hello(<<>>),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% Test malformed varint in Server_Hello
server_hello_malformed_varint_test() ->
    %% Create a message with valid name but malformed varint
    Name = "ClickHouse",
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),
    %% Add invalid varint (all continuation bits set)
    MalformedBinary = <<NameBin/binary, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255>>,

    Result = clickhouse_erl_protocol:decode_server_hello(MalformedBinary),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% Test invalid UTF-8 in Server_Hello string
server_hello_invalid_utf8_test() ->
    %% Create a message with invalid UTF-8 in name field
    %% Length = 2, but invalid UTF-8 bytes
    InvalidUtf8Binary = <<2, 255, 254>>,

    Result = clickhouse_erl_protocol:decode_server_hello(InvalidUtf8Binary),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% Additional unit tests for Server_Hello decoding error cases
%% Requirements: 3.3

%% Test Server_Hello with truncated string length
server_hello_truncated_string_length_test() ->
    %% Create a message where string length is specified but data is missing
    Name = "ClickHouse",
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),
    VersionMajorBin = clickhouse_erl_types_primitive:encode_varint(23),
    VersionMinorBin = clickhouse_erl_types_primitive:encode_varint(8),
    RevisionBin = clickhouse_erl_types_primitive:encode_varint(54460),

    %% Create timezone with length 10 but only provide 5 bytes
    TruncatedTimezoneBin = <<10, "UTC12">>,

    TruncatedBinary =
        <<NameBin/binary, VersionMajorBin/binary, VersionMinorBin/binary, RevisionBin/binary,
            TruncatedTimezoneBin/binary>>,

    Result = clickhouse_erl_protocol:decode_server_hello(TruncatedBinary),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% Test Server_Hello with missing fields (only first 3 fields)
server_hello_missing_fields_test() ->
    %% Create a message with only name, version_major, version_minor
    Name = "ClickHouse",
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),
    VersionMajorBin = clickhouse_erl_types_primitive:encode_varint(23),
    VersionMinorBin = clickhouse_erl_types_primitive:encode_varint(8),

    PartialBinary = <<NameBin/binary, VersionMajorBin/binary, VersionMinorBin/binary>>,

    Result = clickhouse_erl_protocol:decode_server_hello(PartialBinary),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% Test Server_Hello with invalid varint sequence (incomplete)
server_hello_incomplete_varint_test() ->
    %% Create a message with valid name but incomplete varint for version_major
    Name = "ClickHouse",
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),
    %% Incomplete varint (continuation bit set but no following byte)
    IncompleteVarInt = <<128>>,

    InvalidBinary = <<NameBin/binary, IncompleteVarInt/binary>>,

    Result = clickhouse_erl_protocol:decode_server_hello(InvalidBinary),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% Test Server_Hello with string length exceeding available data
server_hello_string_length_overflow_test() ->
    %% Create a message where string claims to be longer than remaining data
    Name = "ClickHouse",
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),
    VersionMajorBin = clickhouse_erl_types_primitive:encode_varint(23),
    VersionMinorBin = clickhouse_erl_types_primitive:encode_varint(8),
    RevisionBin = clickhouse_erl_types_primitive:encode_varint(54460),

    %% Timezone claims length 100 but we only have a few bytes
    OversizedLengthBin = clickhouse_erl_types_primitive:encode_varint(100),
    ShortData = <<"UTC">>,

    InvalidBinary =
        <<NameBin/binary, VersionMajorBin/binary, VersionMinorBin/binary, RevisionBin/binary,
            OversizedLengthBin/binary, ShortData/binary>>,

    Result = clickhouse_erl_protocol:decode_server_hello(InvalidBinary),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% Test Server_Hello with zero-length string followed by insufficient data
server_hello_zero_length_string_insufficient_data_test() ->
    %% Create a message with zero-length name but missing subsequent fields
    ZeroLengthName = clickhouse_erl_types_primitive:encode_string(""),
    %% Only provide one more byte, not enough for version_major varint
    InsufficientData = <<1>>,

    InvalidBinary = <<ZeroLengthName/binary, InsufficientData/binary>>,

    Result = clickhouse_erl_protocol:decode_server_hello(InvalidBinary),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% Test Server_Hello with invalid UTF-8 in middle field (timezone)
server_hello_invalid_utf8_timezone_test() ->
    %% Create a valid message up to timezone, then invalid UTF-8 in timezone
    Name = "ClickHouse",
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),
    VersionMajorBin = clickhouse_erl_types_primitive:encode_varint(23),
    VersionMinorBin = clickhouse_erl_types_primitive:encode_varint(8),
    RevisionBin = clickhouse_erl_types_primitive:encode_varint(54460),

    %% Invalid UTF-8 in timezone field
    InvalidUtf8Timezone = <<3, 255, 254, 253>>,

    InvalidBinary =
        <<NameBin/binary, VersionMajorBin/binary, VersionMinorBin/binary, RevisionBin/binary,
            InvalidUtf8Timezone/binary>>,

    Result = clickhouse_erl_protocol:decode_server_hello(InvalidBinary),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% Test Server_Hello with varint overflow (too many bytes)
server_hello_varint_overflow_test() ->
    %% Create a message with valid name but varint that's too long
    Name = "ClickHouse",
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),

    %% Create a varint that exceeds 64 bits (10 bytes with continuation bits)
    OverflowVarInt = <<128, 128, 128, 128, 128, 128, 128, 128, 128, 128>>,

    InvalidBinary = <<NameBin/binary, OverflowVarInt/binary>>,

    Result = clickhouse_erl_protocol:decode_server_hello(InvalidBinary),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% Test Server_Hello with negative string length (invalid varint interpretation)
server_hello_negative_string_length_test() ->
    %% This test ensures that extremely large varints (that could be interpreted as negative)
    %% are handled properly. We'll use a very large varint for string length.
    Name = "ClickHouse",
    NameBin = clickhouse_erl_types_primitive:encode_string(Name),
    VersionMajorBin = clickhouse_erl_types_primitive:encode_varint(23),
    VersionMinorBin = clickhouse_erl_types_primitive:encode_varint(8),
    RevisionBin = clickhouse_erl_types_primitive:encode_varint(54460),

    %% Very large varint that would require more data than available
    LargeVarInt = clickhouse_erl_types_primitive:encode_varint(16#FFFFFFFFFFFFFFFF),

    InvalidBinary =
        <<NameBin/binary, VersionMajorBin/binary, VersionMinorBin/binary, RevisionBin/binary,
            LargeVarInt/binary>>,

    Result = clickhouse_erl_protocol:decode_server_hello(InvalidBinary),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% Test Server_Hello with partial field at end
server_hello_partial_final_field_test() ->
    %% Create a valid message up to display_name, then truncate version_patch
    Name = "ClickHouse",
    VersionMajor = 23,
    VersionMinor = 8,
    Revision = 54460,
    Timezone = "UTC",
    DisplayName = "ClickHouse server",

    NameBin = clickhouse_erl_types_primitive:encode_string(Name),
    VersionMajorBin = clickhouse_erl_types_primitive:encode_varint(VersionMajor),
    VersionMinorBin = clickhouse_erl_types_primitive:encode_varint(VersionMinor),
    RevisionBin = clickhouse_erl_types_primitive:encode_varint(Revision),
    TimezoneBin = clickhouse_erl_types_primitive:encode_string(Timezone),
    DisplayNameBin = clickhouse_erl_types_primitive:encode_string(DisplayName),

    %% Missing version_patch field entirely
    TruncatedBinary =
        <<NameBin/binary, VersionMajorBin/binary, VersionMinorBin/binary, RevisionBin/binary,
            TimezoneBin/binary, DisplayNameBin/binary>>,

    Result = clickhouse_erl_protocol:decode_server_hello(TruncatedBinary),
    ?assertMatch({error, {decoding_error, _}}, Result).

%% EUnit test wrapper for Server Hello parsing completeness property
server_hello_parsing_completeness_test() ->
    ?assert(proper:quickcheck(prop_server_hello_parsing_completeness(), [{numtests, 100}])).
