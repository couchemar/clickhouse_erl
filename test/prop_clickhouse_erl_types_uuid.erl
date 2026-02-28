%% @doc Property-based tests for UUID type encoding and decoding.
%%
%% This module tests the correctness properties of UUID encoding and decoding:
%% - Property 19: UUID encode-decode roundtrip
%% - Property 20: UUID encoding format
%% - Property 21: UUID format validation
-module(prop_clickhouse_erl_types_uuid).

-include_lib("proper/include/proper.hrl").

%%%===================================================================
%%% Properties
%%%===================================================================

%% @doc Property 19: UUID encode-decode roundtrip
%%
%% For any valid UUID value (string with/without hyphens or 16-byte binary),
%% encoding then decoding should produce an equivalent canonical representation.
%%
%% Validates: Requirements 5.1, 5.2
prop_uuid_encode_decode_roundtrip() ->
    ?FORALL(
        UUID,
        uuid_gen(),
        begin
            % Encode the UUID
            {ok, Encoded} = clickhouse_erl_types_uuid:encode_uuid(UUID),
            % Decode it back
            {ok, Decoded, <<>>} = clickhouse_erl_types_uuid:decode_uuid(Encoded),
            % The decoded value should be in canonical format
            is_canonical_uuid(Decoded) andalso
                % Encoding the decoded value should produce the same binary
                case clickhouse_erl_types_uuid:encode_uuid(Decoded) of
                    {ok, Encoded} -> true;
                    _ -> false
                end
        end
    ).

%% @doc Property 20: UUID encoding format
%%
%% For any valid UUID, encoding should produce exactly 16 bytes
%% in RFC 4122 network byte order.
%%
%% Validates: Requirements 5.3, 5.8
prop_uuid_encoding_format() ->
    ?FORALL(
        UUID,
        uuid_gen(),
        begin
            case clickhouse_erl_types_uuid:encode_uuid(UUID) of
                {ok, Encoded} ->
                    % Must be exactly 16 bytes
                    byte_size(Encoded) =:= 16;
                {error, _} ->
                    false
            end
        end
    ).

%% @doc Property 21: UUID format validation
%%
%% For any invalid UUID format (wrong length, invalid hex digits,
%% incorrect hyphen positions), encoding should return an error tuple.
%%
%% Validates: Requirements 5.7
prop_uuid_format_validation() ->
    ?FORALL(
        InvalidUUID,
        invalid_uuid_gen(),
        begin
            case clickhouse_erl_types_uuid:encode_uuid(InvalidUUID) of
                {error, _} -> true;
                {ok, _} -> false
            end
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generate valid UUID values in various formats
uuid_gen() ->
    oneof([
        uuid_with_hyphens_gen(),
        uuid_without_hyphens_gen(),
        uuid_binary_gen()
    ]).

%% @doc Generate UUID string with hyphens (canonical format)
uuid_with_hyphens_gen() ->
    ?LET(
        {A, B, C, D, E},
        {
            hex_string_gen(8),
            hex_string_gen(4),
            hex_string_gen(4),
            hex_string_gen(4),
            hex_string_gen(12)
        },
        list_to_binary([A, "-", B, "-", C, "-", D, "-", E])
    ).

%% @doc Generate UUID string without hyphens
uuid_without_hyphens_gen() ->
    ?LET(Hex, hex_string_gen(32), list_to_binary(Hex)).

%% @doc Generate 16-byte UUID binary
uuid_binary_gen() ->
    ?LET(Bytes, vector(16, range(0, 255)), list_to_binary(Bytes)).

%% @doc Generate hexadecimal string of specified length
hex_string_gen(Length) ->
    ?LET(
        Chars,
        vector(Length, oneof(lists:seq($0, $9) ++ lists:seq($a, $f))),
        Chars
    ).

%% @doc Generate invalid UUID values for validation testing
invalid_uuid_gen() ->
    oneof([
        % Wrong length strings
        ?LET(Len, oneof([0, 10, 20, 31, 33, 37, 50]), binary:copy(<<"a">>, Len)),
        % Invalid characters in UUID string
        <<"550e8400-e29b-41d4-a716-44665544000g">>,
        % Wrong hyphen positions
        <<"550e8400e29b-41d4-a716-446655440000">>,
        % Non-hex characters
        <<"550e8400-e29b-41d4-a716-44665544000z">>,
        % Empty binary
        <<>>,
        % Wrong size binary (not 16 bytes)
        ?LET(Size, oneof([0, 8, 15, 17, 32]), binary:copy(<<0>>, Size))
    ]).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Check if a UUID string is in canonical format (lowercase with hyphens)
is_canonical_uuid(
    <<
        _:8/binary, $-, _:4/binary, $-, _:4/binary, $-, _:4/binary, $-, _:12/binary
    >> = UUID
) ->
    % Check that it's all lowercase hex
    is_lowercase_hex(UUID);
is_canonical_uuid(_) ->
    false.

%% @doc Check if a binary contains only lowercase hex and hyphens
is_lowercase_hex(<<>>) ->
    true;
is_lowercase_hex(<<C, Rest/binary>>) when
    (C >= $0 andalso C =< $9) orelse
        (C >= $a andalso C =< $f) orelse
        C =:= $-
->
    is_lowercase_hex(Rest);
is_lowercase_hex(_) ->
    false.
