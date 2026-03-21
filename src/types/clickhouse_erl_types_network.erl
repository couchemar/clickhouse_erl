%% @doc Network type encoding and decoding for ClickHouse IPv4 and IPv6 types.
%%
%% This module handles encoding and decoding of network address types with
%% support for multiple input formats and efficient binary encoding.
%%
%% Type Representations:
%% - IPv4: {A, B, C, D} tuple, <<"A.B.C.D">> binary, or 32-bit integer
%% - IPv6: {A, B, C, D, E, F, G, H} tuple or <<"A:B:C:D:E:F:G:H">> binary
%%
%% Encoding Format:
%% - IPv4: 4 bytes, big-endian (network byte order)
%% - IPv6: 16 bytes, network byte order
%%
%% Usage Examples:
%%
%% ```
%% % Encode IPv4 from tuple
%% {ok, Binary} = encode_ipv4({192, 168, 1, 1}).
%% % Binary = <<192, 168, 1, 1>>
%%
%% % Encode IPv4 from string
%% {ok, Binary2} = encode_ipv4(<<"10.0.0.1">>).
%% % Binary2 = <<10, 0, 0, 1>>
%%
%% % Encode IPv4 from integer
%% {ok, Binary3} = encode_ipv4(3232235777).  % 192.168.1.1
%% % Binary3 = <<192, 168, 1, 1>>
%%
%% % Decode IPv4
%% {ok, {192, 168, 1, 1}, Rest} = decode_ipv4(Binary).
%%
%% % Encode IPv6 from tuple
%% {ok, Binary4} = encode_ipv6({8193, 3512, 0, 0, 0, 0, 0, 1}).
%% % Binary4 = <<32, 1, 13, 184, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1>>
%%
%% % Encode IPv6 from string (with :: compression)
%% {ok, Binary5} = encode_ipv6(<<"2001:db8::1">>).
%%
%% % Decode IPv6
%% {ok, {8193, 3512, 0, 0, 0, 0, 0, 1}, Rest} = decode_ipv6(Binary4).
%%
%% % Format IP addresses for display
%% <<"192.168.1.1">> = format_ipv4({192, 168, 1, 1}).
%% <<"2001:db8::1">> = format_ipv6({8193, 3512, 0, 0, 0, 0, 0, 1}).
%%
%% % Invalid IPv4 octet error
%% {error, {invalid_ipv4_octet, 256}} = encode_ipv4({192, 168, 1, 256}).
%%
%% % Invalid IPv4 format error
%% {error, {invalid_ipv4_format, _}} = encode_ipv4(<<"invalid">>).
%% '''
%%
%% Error Cases:
%% - {invalid_ipv4_octet, Octet} - Octet value outside 0-255 range
%% - {invalid_ipv4_format, Value} - Invalid IPv4 string format
%% - {invalid_ipv6_segment, Segment} - Segment value outside 0-65535 range
%% - {invalid_ipv6_format, Value} - Invalid IPv6 string format
%% - {truncated_data, Details} - Binary too short for decoding
-module(clickhouse_erl_types_network).

%% API exports
-export([
    encode_ipv4/1,
    decode_ipv4/1,
    encode_ipv6/1,
    decode_ipv6/1,
    encode_ipv4_column/1,
    decode_ipv4_column/2,
    encode_ipv6_column/1,
    decode_ipv6_column/2
]).

%% Helper function exports
-export([
    parse_ipv4/1,
    format_ipv4/1,
    parse_ipv6/1,
    format_ipv6/1
]).

-include_lib("kernel/include/logger.hrl").

%% Type definitions
-export_type([
    ipv4_value/0,
    ipv6_value/0,
    ipv4_tuple/0,
    ipv6_tuple/0
]).

-type ipv4_tuple() :: {byte(), byte(), byte(), byte()}.
-type ipv6_tuple() :: {
    0..65535, 0..65535, 0..65535, 0..65535, 0..65535, 0..65535, 0..65535, 0..65535
}.
-type ipv4_value() :: ipv4_tuple() | binary() | non_neg_integer().
-type ipv6_value() :: ipv6_tuple() | binary().

%%%===================================================================
%%% API - IPv4
%%%===================================================================

%% @doc Encode an IPv4 address to 4-byte binary (network byte order).
%%
%% Accepts:
%% - Tuple: {192, 168, 1, 1}
%% - Binary string: <<"192.168.1.1">>
%% - Integer: 3232235777
%%
%% Returns {ok, Binary} where Binary is 4 bytes in big-endian order,
%% or {error, Reason} if the input is invalid.
-spec encode_ipv4(ipv4_value()) -> {ok, binary()} | {error, term()}.
encode_ipv4({A, B, C, D} = Tuple) when
    is_integer(A),
    is_integer(B),
    is_integer(C),
    is_integer(D)
->
    case validate_ipv4_octets(Tuple) of
        ok ->
            {ok, <<D:8, C:8, B:8, A:8>>};
        {error, Reason} ->
            {error, Reason}
    end;
encode_ipv4(Binary) when is_binary(Binary) ->
    case parse_ipv4(Binary) of
        {ok, Tuple} ->
            encode_ipv4(Tuple);
        {error, Reason} ->
            {error, Reason}
    end;
encode_ipv4(Integer) when is_integer(Integer), Integer >= 0, Integer =< 4294967295 ->
    {ok, <<Integer:32/little>>};
encode_ipv4(Value) ->
    {error, {invalid_ipv4_format, Value}}.

%% @doc Decode a 4-byte binary to IPv4 tuple representation.
%%
%% Returns {ok, {A, B, C, D}, Rest} where each octet is 0-255,
%% or {error, Reason} if the binary is invalid.
-spec decode_ipv4(binary()) -> {ok, ipv4_tuple(), binary()} | {error, term()}.
decode_ipv4(<<D:8, C:8, B:8, A:8, Rest/binary>>) ->
    {ok, {A, B, C, D}, Rest};
decode_ipv4(Binary) when byte_size(Binary) < 4 ->
    {error,
        {truncated_data, #{
            expected_bytes => 4,
            actual_bytes => byte_size(Binary),
            type => ipv4
        }}};
decode_ipv4(_) ->
    {error, {invalid_ipv4_data, #{type => ipv4}}}.

%%%===================================================================
%%% API - IPv6
%%%===================================================================

%% @doc Encode an IPv6 address to 16-byte binary (network byte order).
%%
%% Accepts:
%% - Tuple: {8193, 3512, 0, 0, 0, 0, 0, 1}
%% - Binary string: <<"2001:db8::1">> (supports :: compression)
%%
%% Returns {ok, Binary} where Binary is 16 bytes in network byte order,
%% or {error, Reason} if the input is invalid.
-spec encode_ipv6(ipv6_value()) -> {ok, binary()} | {error, term()}.
encode_ipv6({A, B, C, D, E, F, G, H} = Tuple) when
    is_integer(A),
    is_integer(B),
    is_integer(C),
    is_integer(D),
    is_integer(E),
    is_integer(F),
    is_integer(G),
    is_integer(H)
->
    case validate_ipv6_segments(Tuple) of
        ok ->
            {ok,
                <<A:16/big, B:16/big, C:16/big, D:16/big, E:16/big, F:16/big, G:16/big, H:16/big>>};
        {error, Reason} ->
            {error, Reason}
    end;
encode_ipv6(Binary) when is_binary(Binary) ->
    case parse_ipv6(Binary) of
        {ok, Tuple} ->
            encode_ipv6(Tuple);
        {error, Reason} ->
            {error, Reason}
    end;
encode_ipv6(Value) ->
    {error, {invalid_ipv6_format, Value}}.

%% @doc Decode a 16-byte binary to IPv6 tuple representation.
%%
%% Returns {ok, {A, B, C, D, E, F, G, H}, Rest} where each segment is 0-65535,
%% or {error, Reason} if the binary is invalid.
-spec decode_ipv6(binary()) -> {ok, ipv6_tuple(), binary()} | {error, term()}.
decode_ipv6(
    <<A:16/big, B:16/big, C:16/big, D:16/big, E:16/big, F:16/big, G:16/big, H:16/big, Rest/binary>>
) ->
    {ok, {A, B, C, D, E, F, G, H}, Rest};
decode_ipv6(Binary) when byte_size(Binary) < 16 ->
    {error,
        {truncated_data, #{
            expected_bytes => 16,
            actual_bytes => byte_size(Binary),
            type => ipv6
        }}};
decode_ipv6(_) ->
    {error, {invalid_ipv6_data, #{type => ipv6}}}.

%%%===================================================================
%%% Helper Functions - IPv4
%%%===================================================================

%% @doc Parse an IPv4 address string to tuple representation.
%%
%% Accepts binary strings like <<"192.168.1.1">>.
%% Returns {ok, {A, B, C, D}} or {error, Reason}.
-spec parse_ipv4(binary()) -> {ok, ipv4_tuple()} | {error, term()}.
parse_ipv4(Binary) when is_binary(Binary) ->
    case binary:split(Binary, <<".">>, [global]) of
        [A, B, C, D] ->
            try
                Octets = {
                    binary_to_integer(A),
                    binary_to_integer(B),
                    binary_to_integer(C),
                    binary_to_integer(D)
                },
                case validate_ipv4_octets(Octets) of
                    ok -> {ok, Octets};
                    {error, Reason} -> {error, Reason}
                end
            catch
                _:_ ->
                    {error, {invalid_ipv4_string, Binary}}
            end;
        _ ->
            {error, {invalid_ipv4_string, Binary}}
    end.

%% @doc Format an IPv4 tuple to string representation.
%%
%% Converts {192, 168, 1, 1} to <<"192.168.1.1">>.
-spec format_ipv4(ipv4_tuple()) -> binary().
format_ipv4({A, B, C, D}) ->
    iolist_to_binary(io_lib:format("~B.~B.~B.~B", [A, B, C, D])).

%%%===================================================================
%%% Helper Functions - IPv6
%%%===================================================================

%% @doc Parse an IPv6 address string to tuple representation.
%%
%% Accepts binary strings like <<"2001:db8::1">> with :: compression.
%% Returns {ok, {A, B, C, D, E, F, G, H}} or {error, Reason}.
-spec parse_ipv6(binary()) -> {ok, ipv6_tuple()} | {error, term()}.
parse_ipv6(Binary) when is_binary(Binary) ->
    case inet:parse_address(binary_to_list(Binary)) of
        {ok, {A, B, C, D, E, F, G, H}} ->
            {ok, {A, B, C, D, E, F, G, H}};
        {error, einval} ->
            {error, {invalid_ipv6_string, Binary}}
    end.

%% @doc Format an IPv6 tuple to string representation.
%%
%% Converts {8193, 3512, 0, 0, 0, 0, 0, 1} to <<"2001:db8::1">>.
%% Uses :: compression for consecutive zero segments.
-spec format_ipv6(ipv6_tuple()) -> binary().
format_ipv6({A, B, C, D, E, F, G, H}) ->
    Address = {A, B, C, D, E, F, G, H},
    case inet:ntoa(Address) of
        String when is_list(String) ->
            list_to_binary(String);
        {error, einval} ->
            %% Fallback to manual formatting without compression
            iolist_to_binary(
                io_lib:format(
                    "~4.16.0B:~4.16.0B:~4.16.0B:~4.16.0B:~4.16.0B:~4.16.0B:~4.16.0B:~4.16.0B",
                    [A, B, C, D, E, F, G, H]
                )
            )
    end.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @doc Validate that all IPv4 octets are in range 0-255.
-spec validate_ipv4_octets(ipv4_tuple()) -> ok | {error, term()}.
validate_ipv4_octets({A, B, C, D}) ->
    case {in_byte_range(A), in_byte_range(B), in_byte_range(C), in_byte_range(D)} of
        {true, true, true, true} ->
            ok;
        _ ->
            {error,
                {invalid_ipv4_octet, #{
                    octets => {A, B, C, D},
                    valid_range => {0, 255}
                }}}
    end.

%% @doc Validate that all IPv6 segments are in range 0-65535.
-spec validate_ipv6_segments(ipv6_tuple()) -> ok | {error, term()}.
validate_ipv6_segments({A, B, C, D, E, F, G, H}) ->
    case
        {
            in_segment_range(A),
            in_segment_range(B),
            in_segment_range(C),
            in_segment_range(D),
            in_segment_range(E),
            in_segment_range(F),
            in_segment_range(G),
            in_segment_range(H)
        }
    of
        {true, true, true, true, true, true, true, true} ->
            ok;
        _ ->
            {error,
                {invalid_ipv6_segment, #{
                    segments => {A, B, C, D, E, F, G, H},
                    valid_range => {0, 65535}
                }}}
    end.

%% @doc Check if value is in byte range (0-255).
-spec in_byte_range(integer()) -> boolean().
in_byte_range(N) when is_integer(N), N >= 0, N =< 255 -> true;
in_byte_range(_) -> false.

%% @doc Check if value is in segment range (0-65535).
-spec in_segment_range(integer()) -> boolean().
in_segment_range(N) when is_integer(N), N >= 0, N =< 65535 -> true;
in_segment_range(_) -> false.

%%%===================================================================
%%% Column Encoding/Decoding
%%%===================================================================

%% @doc Encode a column of IPv4 values.
-spec encode_ipv4_column([ipv4_value()]) -> {ok, iolist()} | {error, term()}.
encode_ipv4_column(Values) ->
    encode_column_loop(Values, fun encode_ipv4/1, []).

%% @doc Decode a column of IPv4 values.
-spec decode_ipv4_column(binary(), non_neg_integer()) ->
    {ok, [ipv4_value()], binary()} | {error, term()}.
decode_ipv4_column(Binary, NumRows) ->
    decode_column_loop(Binary, NumRows, fun decode_ipv4/1, []).

%% @doc Encode a column of IPv6 values.
-spec encode_ipv6_column([ipv6_value()]) -> {ok, iolist()} | {error, term()}.
encode_ipv6_column(Values) ->
    encode_column_loop(Values, fun encode_ipv6/1, []).

%% @doc Decode a column of IPv6 values.
-spec decode_ipv6_column(binary(), non_neg_integer()) ->
    {ok, [ipv6_value()], binary()} | {error, term()}.
decode_ipv6_column(Binary, NumRows) ->
    decode_column_loop(Binary, NumRows, fun decode_ipv6/1, []).

%%%===================================================================
%%% Internal Helper Functions
%%%===================================================================

%% @doc Helper to encode a column of values using an encoder function.
-spec encode_column_loop([term()], fun((term()) -> {ok, binary()} | {error, term()}), iolist()) ->
    {ok, iolist()} | {error, term()}.
encode_column_loop([], _EncodeFun, Acc) ->
    {ok, lists:reverse(Acc)};
encode_column_loop([Value | Rest], EncodeFun, Acc) ->
    case EncodeFun(Value) of
        {ok, Encoded} ->
            encode_column_loop(Rest, EncodeFun, [Encoded | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Helper to decode a column of values using a decoder function.
-spec decode_column_loop(
    binary(),
    non_neg_integer(),
    fun((binary()) -> {ok, term(), binary()} | {error, term()}),
    [term()]
) ->
    {ok, [term()], binary()} | {error, term()}.
decode_column_loop(Binary, 0, _DecodeFun, Acc) ->
    {ok, lists:reverse(Acc), Binary};
decode_column_loop(Binary, N, DecodeFun, Acc) ->
    case DecodeFun(Binary) of
        {ok, Value, Rest} ->
            decode_column_loop(Rest, N - 1, DecodeFun, [Value | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.
