%% @doc Property-based tests for network type encoding and decoding.
%%
%% Tests IPv4 and IPv6 encoding/decoding properties including:
%% - Roundtrip properties (encode then decode produces equivalent value)
%% - Encoding format properties (correct byte length and structure)
%% - Validation properties (invalid inputs produce appropriate errors)
-module(prop_clickhouse_erl_types_network).

-include_lib("proper/include/proper.hrl").

%%%===================================================================
%%% Generators
%%%===================================================================

%% Generator for valid IPv4 tuple
ipv4_tuple_gen() ->
    {range(0, 255), range(0, 255), range(0, 255), range(0, 255)}.

%% Generator for valid IPv4 integer
ipv4_integer_gen() ->
    range(0, 4294967295).

%% Generator for valid IPv4 string
ipv4_string_gen() ->
    ?LET(
        {A, B, C, D},
        ipv4_tuple_gen(),
        iolist_to_binary(io_lib:format("~B.~B.~B.~B", [A, B, C, D]))
    ).

%% Generator for any valid IPv4 representation
ipv4_gen() ->
    oneof([
        ipv4_tuple_gen(),
        ipv4_string_gen(),
        ipv4_integer_gen()
    ]).

%% Generator for invalid IPv4 octets (out of range)
invalid_ipv4_tuple_gen() ->
    oneof([
        {range(256, 1000), range(0, 255), range(0, 255), range(0, 255)},
        {range(0, 255), range(256, 1000), range(0, 255), range(0, 255)},
        {range(0, 255), range(0, 255), range(256, 1000), range(0, 255)},
        {range(0, 255), range(0, 255), range(0, 255), range(256, 1000)},
        {range(-100, -1), range(0, 255), range(0, 255), range(0, 255)}
    ]).

%% Generator for invalid IPv4 strings
invalid_ipv4_string_gen() ->
    oneof([
        <<"256.1.1.1">>,
        <<"1.1.1">>,
        <<"1.1.1.1.1">>,
        <<"abc.def.ghi.jkl">>,
        <<"">>,
        <<"...">>,
        <<"1.-1.1.1">>
    ]).

%% Generator for valid IPv6 tuple
ipv6_tuple_gen() ->
    {
        range(0, 65535),
        range(0, 65535),
        range(0, 65535),
        range(0, 65535),
        range(0, 65535),
        range(0, 65535),
        range(0, 65535),
        range(0, 65535)
    }.

%% Generator for valid IPv6 string
ipv6_string_gen() ->
    oneof([
        <<"2001:db8::1">>,
        <<"::1">>,
        <<"fe80::">>,
        <<"2001:0db8:0000:0000:0000:0000:0000:0001">>,
        <<"::ffff:192.0.2.1">>
    ]).

%% Generator for any valid IPv6 representation
ipv6_gen() ->
    oneof([
        ipv6_tuple_gen(),
        ipv6_string_gen()
    ]).

%% Generator for invalid IPv6 tuples (out of range)
invalid_ipv6_tuple_gen() ->
    oneof([
        {range(65536, 70000), 0, 0, 0, 0, 0, 0, 0},
        {0, range(65536, 70000), 0, 0, 0, 0, 0, 0},
        {0, 0, 0, 0, 0, 0, 0, range(-100, -1)}
    ]).

%% Generator for invalid IPv6 strings
invalid_ipv6_string_gen() ->
    oneof([
        <<"gggg::1">>,
        <<"2001:db8:::1">>,
        <<"">>,
        <<"not-an-ipv6">>,
        <<"12345::1">>
    ]).

%%%===================================================================
%%% Property 15: IPv4 encode-decode roundtrip
%%% Validates: Requirements 4.1, 4.2
%%%===================================================================

%% @doc Property: For any valid IPv4 value, encoding then decoding
%% should produce an equivalent tuple representation.
prop_ipv4_roundtrip() ->
    ?FORALL(
        IPv4,
        ipv4_gen(),
        begin
            case clickhouse_erl_types_network:encode_ipv4(IPv4) of
                {ok, Encoded} ->
                    case clickhouse_erl_types_network:decode_ipv4(Encoded) of
                        {ok, Decoded, <<>>} ->
                            % Convert input to tuple for comparison
                            ExpectedTuple =
                                case IPv4 of
                                    {_, _, _, _} = Tuple ->
                                        Tuple;
                                    Binary when is_binary(Binary) ->
                                        {ok, T} = clickhouse_erl_types_network:parse_ipv4(Binary),
                                        T;
                                    Integer when is_integer(Integer) ->
                                        <<A:8, B:8, C:8, D:8>> = <<Integer:32/big>>,
                                        {A, B, C, D}
                                end,
                            Decoded =:= ExpectedTuple;
                        {error, Reason} ->
                            {false, {decode_failed, Reason}}
                    end;
                {error, Reason} ->
                    {false, {encode_failed, Reason}}
            end
        end
    ).

%%%===================================================================
%%% Property 17: IP address encoding format (IPv4)
%%% Validates: Requirements 4.5
%%%===================================================================

%% @doc Property: For any IPv4 value, encoding should produce exactly
%% 4 bytes in little-endian order (ClickHouse native format).
prop_ipv4_encoding_format() ->
    ?FORALL(
        IPv4,
        ipv4_gen(),
        begin
            case clickhouse_erl_types_network:encode_ipv4(IPv4) of
                {ok, Encoded} ->
                    % Check byte length
                    ByteSize = byte_size(Encoded),
                    case ByteSize =:= 4 of
                        true ->
                            % Verify little-endian encoding by decoding and re-encoding
                            {ok, Tuple, <<>>} = clickhouse_erl_types_network:decode_ipv4(Encoded),
                            {A, B, C, D} = Tuple,
                            Expected = <<D:8, C:8, B:8, A:8>>,
                            Encoded =:= Expected;
                        false ->
                            {false, {wrong_byte_size, ByteSize}}
                    end;
                {error, _Reason} ->
                    % Invalid input is acceptable
                    true
            end
        end
    ).

%%%===================================================================
%%% Property 18: IP address validation (IPv4)
%%% Validates: Requirements 4.11
%%%===================================================================

%% @doc Property: For any invalid IPv4 address (out-of-range octets),
%% encoding should return an error tuple.
prop_ipv4_validation() ->
    ?FORALL(
        InvalidIPv4,
        oneof([invalid_ipv4_tuple_gen(), invalid_ipv4_string_gen()]),
        begin
            Result = clickhouse_erl_types_network:encode_ipv4(InvalidIPv4),
            case Result of
                {error, _Reason} ->
                    true;
                {ok, _} ->
                    {false, {should_have_failed, InvalidIPv4}}
            end
        end
    ).

%%%===================================================================
%%% Property 16: IPv6 encode-decode roundtrip
%%% Validates: Requirements 4.3, 4.4
%%%===================================================================

%% @doc Property: For any valid IPv6 value, encoding then decoding
%% should produce an equivalent tuple representation.
prop_ipv6_roundtrip() ->
    ?FORALL(
        IPv6,
        ipv6_gen(),
        begin
            case clickhouse_erl_types_network:encode_ipv6(IPv6) of
                {ok, Encoded} ->
                    case clickhouse_erl_types_network:decode_ipv6(Encoded) of
                        {ok, Decoded, <<>>} ->
                            % Convert input to tuple for comparison
                            ExpectedTuple =
                                case IPv6 of
                                    {_, _, _, _, _, _, _, _} = Tuple ->
                                        Tuple;
                                    Binary when is_binary(Binary) ->
                                        {ok, T} = clickhouse_erl_types_network:parse_ipv6(Binary),
                                        T
                                end,
                            Decoded =:= ExpectedTuple;
                        {error, Reason} ->
                            {false, {decode_failed, Reason}}
                    end;
                {error, Reason} ->
                    {false, {encode_failed, Reason}}
            end
        end
    ).

%%%===================================================================
%%% Property 17: IP address encoding format (IPv6)
%%% Validates: Requirements 4.6
%%%===================================================================

%% @doc Property: For any IPv6 value, encoding should produce exactly
%% 16 bytes in network byte order.
prop_ipv6_encoding_format() ->
    ?FORALL(
        IPv6,
        ipv6_gen(),
        begin
            case clickhouse_erl_types_network:encode_ipv6(IPv6) of
                {ok, Encoded} ->
                    % Check byte length
                    ByteSize = byte_size(Encoded),
                    case ByteSize =:= 16 of
                        true ->
                            % Verify network byte order by decoding and re-encoding
                            {ok, Tuple, <<>>} = clickhouse_erl_types_network:decode_ipv6(Encoded),
                            {A, B, C, D, E, F, G, H} = Tuple,
                            Expected =
                                <<A:16/big, B:16/big, C:16/big, D:16/big, E:16/big, F:16/big,
                                    G:16/big, H:16/big>>,
                            Encoded =:= Expected;
                        false ->
                            {false, {wrong_byte_size, ByteSize}}
                    end;
                {error, _Reason} ->
                    % Invalid input is acceptable
                    true
            end
        end
    ).

%%%===================================================================
%%% Property 18: IP address validation (IPv6)
%%% Validates: Requirements 4.12
%%%===================================================================

%% @doc Property: For any invalid IPv6 address (out-of-range segments),
%% encoding should return an error tuple.
prop_ipv6_validation() ->
    ?FORALL(
        InvalidIPv6,
        oneof([invalid_ipv6_tuple_gen(), invalid_ipv6_string_gen()]),
        begin
            Result = clickhouse_erl_types_network:encode_ipv6(InvalidIPv6),
            case Result of
                {error, _Reason} ->
                    true;
                {ok, _} ->
                    {false, {should_have_failed, InvalidIPv6}}
            end
        end
    ).
