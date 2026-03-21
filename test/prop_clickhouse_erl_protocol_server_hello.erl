-module(prop_clickhouse_erl_protocol_server_hello).

-include_lib("proper/include/proper.hrl").

-import(generators, [string_gen/0]).

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
                {ok, ParsedServerInfo, _Rest} ->
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
