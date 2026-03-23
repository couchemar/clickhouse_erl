%% @doc Pure Erlang implementation of ClickHouse-specific CityHash128 algorithm.
%%
%% This module provides checksum computation and verification for compressed blocks
%% in the ClickHouse native protocol. It implements the CH128 variant, which is
%% ClickHouse's frozen version of CityHash 1.0.2 with modifications.
%%
%% == CRITICAL: ClickHouse-Specific Variant ==
%%
%% This implements the **CH128 variant** used by ClickHouse, NOT standard CityHash128.
%% ClickHouse uses frozen CityHash 1.0.2 with modified algorithm. Standard CityHash
%% and FarmHash produce different hash values and MUST NOT be used.
%%
%% **Test Vectors** (verify implementation correctness):
%% ```
%% % ClickHouse variant (CORRECT)
%% CH64(<<"Moscow">>) = 12507901496292878638
%%
%% % Standard CityHash (WRONG - do not use)
%% CityHash64(<<"Moscow">>) = 5992710078453357409
%% '''
%%
%% == Usage Examples ==
%%
%% === Computing Hash ===
%%
%% ```
%% Data = <<"Hello, ClickHouse!">>,
%% Hash = clickhouse_erl_cityhash:hash128(Data).
%% % Returns 16-byte binary (little-endian: low 64 bits, then high 64 bits)
%% '''
%%
%% === Verifying Checksum ===
%%
%% ```
%% Data = <<"test data">>,
%% ExpectedHash = clickhouse_erl_cityhash:hash128(Data),
%% case clickhouse_erl_cityhash:verify(Data, ExpectedHash) of
%%     true -> io:format("Checksum valid~n");
%%     false -> io:format("Checksum mismatch - data corrupted~n")
%% end.
%% '''
%%
%% === Encoding/Decoding Hash Values ===
%%
%% ```
%% % Encode 128-bit hash as 16-byte binary
%% Low = 16#0123456789abcdef,
%% High = 16#fedcba9876543210,
%% Binary = clickhouse_erl_cityhash:encode_hash(Low, High).
%%
%% % Decode 16-byte binary to 128-bit components
%% {Low, High} = clickhouse_erl_cityhash:decode_hash(Binary).
%% '''
%%
%% == Integration with Compression ==
%%
%% This module is used by `clickhouse_erl_compression` to compute and verify
%% checksums for compressed blocks:
%%
%% ```
%% % Checksum data format: method_byte + compressed_size + original_size + compressed_data
%% MethodByte = 16#82,  % LZ4
%% CompressedSize = byte_size(CompressedData),
%% OriginalSize = 1024,
%% ChecksumData = <<MethodByte:8, (CompressedSize + 9):32/little,
%%                  OriginalSize:32/little, CompressedData/binary>>,
%% Checksum = clickhouse_erl_cityhash:hash128(ChecksumData).
%% '''
%%
%% == Hash Format ==
%%
%% The 128-bit hash is represented as a 16-byte binary in little-endian format:
%% - Bytes 0-7: Low 64 bits (little-endian)
%% - Bytes 8-15: High 64 bits (little-endian)
%%
%% This matches the ClickHouse protocol specification for checksum encoding.
%%
%% == Algorithm Details ==
%%
%% The implementation follows the ClickHouse-specific CH128 algorithm:
%% - Uses frozen CityHash 1.0.2 constants
%% - Special handling for different input sizes (<16, 16-128, >128 bytes)
%% - Murmur-based mixing for strings < 128 bytes
%% - Iterative processing for strings >= 128 bytes
%%
%% **Constants**:
%% - k0 = 0xc3a5c85c97cb3127
%% - k1 = 0xb492b66fbe98f273
%% - k2 = 0x9ae16a3b2f90404f
%% - k3 = 0xc949d7c7509e6557
%%
%% == References ==
%%
%% - ClickHouse Protocol: https://clickhouse.com/docs/native-protocol/hash
%% - Reference Implementation: https://github.com/go-faster/city (ch_128.go)
%% - Test Vectors: https://clickhouse.com/docs/native-protocol/hash#test-vectors
%%
%% @see clickhouse_erl_compression
-module(clickhouse_erl_cityhash).

%% API exports
-export([hash128/1, verify/2, encode_hash/2, decode_hash/1, ch64/1]).

-ignore_xref([ch64/1, decode_hash/1, encode_hash/2, verify/2]).

-include_lib("kernel/include/logger.hrl").

%% Constants from CityHash
-define(K0, 16#c3a5c85c97cb3127).
-define(K1, 16#b492b66fbe98f273).
-define(K2, 16#9ae16a3b2f90404f).
-define(K3, 16#c949d7c7509e6557).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Compute CityHash128 of binary data.
%% Returns 16-byte binary (little-endian: low 64 bits, then high 64 bits).
-spec hash128(binary()) -> binary().
hash128(Data) ->
    {Low, High} = ch128(Data),
    encode_hash(Low, High).

%% @doc Verify checksum matches data.
-spec verify(binary(), binary()) -> boolean().
verify(Data, ExpectedHash) ->
    ActualHash = hash128(Data),
    ActualHash =:= ExpectedHash.

%% @doc Encode 128-bit hash components as 16-byte binary (little-endian).
-spec encode_hash(non_neg_integer(), non_neg_integer()) -> binary().
encode_hash(Low, High) ->
    <<Low:64/little, High:64/little>>.

%% @doc Decode 16-byte binary to 128-bit hash components.
-spec decode_hash(binary()) -> {Low :: non_neg_integer(), High :: non_neg_integer()}.
decode_hash(<<Low:64/little, High:64/little>>) ->
    {Low, High}.

%% @doc Compute ClickHouse variant of CityHash64.
-spec ch64(binary()) -> non_neg_integer().
ch64(Data) ->
    Length = byte_size(Data),
    Result =
        case Length of
            L when L =< 16 -> ch0to16(Data, Length);
            L when L =< 32 -> ch17to32(Data, Length);
            L when L =< 64 -> ch33to64(Data, Length);
            _ -> ch64_long(Data, Length)
        end,
    Result band 16#ffffffffffffffff.

%%%===================================================================
%%% Internal functions - ClickHouse-specific CH128 variant
%%%===================================================================

%% @doc ClickHouse-specific CH128 variant (NOT standard CityHash128).
-spec ch128(binary()) -> {Low :: non_neg_integer(), High :: non_neg_integer()}.
ch128(Data) when byte_size(Data) >= 16 ->
    <<Low0:64/little, High0:64/little, Rest/binary>> = Data,
    Seed = {Low0 bxor ?K3, High0},
    ch128_seed(Rest, Seed);
ch128(Data) when byte_size(Data) >= 8 ->
    Length = byte_size(Data),
    <<Low0:64/little, _/binary>> = Data,
    <<High0:64/little>> = binary:part(Data, Length - 8, 8),
    Seed = {Low0 bxor (Length * ?K0), High0 bxor ?K1},
    ch128_seed(<<>>, Seed);
ch128(Data) ->
    ch128_seed(Data, {?K0, ?K1}).

%% @doc CH128 with seed.
-spec ch128_seed(binary(), {non_neg_integer(), non_neg_integer()}) ->
    {Low :: non_neg_integer(), High :: non_neg_integer()}.
ch128_seed(Data, Seed) when byte_size(Data) < 128 ->
    ch_murmur(Data, Seed);
ch128_seed(Data, {SeedLow, SeedHigh}) ->
    %% Save initial input for tail hashing
    T = Data,
    Length = byte_size(Data),

    %% Initialize state: v, w, x, y, z
    X0 = SeedLow,
    Y0 = SeedHigh,
    Z0 = Length * ?K1,

    <<V0Low0:64/little, V0High0:64/little, _:72/binary, W0High0:64/little, _/binary>> = Data,
    V0Low = rot64(Y0 bxor ?K1, 49) * ?K1 + V0Low0,
    V0High = rot64(V0Low, 42) * ?K1 + V0High0,
    W0Low = rot64(Y0 + Z0, 35) * ?K1 + X0,
    W0High = rot64(X0 + W0High0, 53) * ?K1,

    %% Process 128-byte chunks
    {X1, Y1, Z1, V1, W1, _Rest} = ch128_loop(Data, X0, Y0, Z0, {V0Low, V0High}, {W0Low, W0High}),

    Y2 = Y1 + rot64(fst(W1), 37) * ?K0 + Z1,
    X2 = X1 + rot64(fst(V1) + Z1, 49) * ?K0,

    %% Process tail (up to 4 chunks of 32 bytes)
    {X3, Y3, V3, W3} = ch128_tail(T, Length, X2, Y2, V1, W1),

    %% Final mixing
    X4 = ch16(X3, fst(V3)),
    Y4 = ch16(Y3, fst(W3)),

    {ch16(X4 + snd(V3), snd(W3)) + Y4, ch16(X4 + snd(W3), Y4 + snd(V3))}.

%% @doc Main loop for CH128 - process 128-byte chunks.
-spec ch128_loop(
    binary(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    {non_neg_integer(), non_neg_integer()},
    {non_neg_integer(), non_neg_integer()}
) ->
    {
        non_neg_integer(),
        non_neg_integer(),
        non_neg_integer(),
        {non_neg_integer(), non_neg_integer()},
        {non_neg_integer(), non_neg_integer()},
        binary()
    }.
ch128_loop(Data, X, Y, Z, V, W) when byte_size(Data) >= 128 ->
    %% Roll 1
    {X2, Y2, Z1, V1, W1} = ch128_roll(Data, 0, X, Y, Z, V, W),
    {Z2, X3} = {X2, Z1},

    %% Roll 2
    {X5, Y4, Z3, V2, W2} = ch128_roll(Data, 64, X3, Y2, Z2, V1, W1),
    {Z4, X6} = {X5, Z3},

    ch128_loop(binary:part(Data, 128, byte_size(Data) - 128), X6, Y4, Z4, V2, W2);
ch128_loop(Data, X, Y, Z, V, W) ->
    {X, Y, Z, V, W, Data}.

%% @doc Single roll operation for CH128 loop.
-spec ch128_roll(
    binary(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    {non_neg_integer(), non_neg_integer()},
    {non_neg_integer(), non_neg_integer()}
) ->
    {
        non_neg_integer(),
        non_neg_integer(),
        non_neg_integer(),
        {non_neg_integer(), non_neg_integer()},
        {non_neg_integer(), non_neg_integer()}
    }.
ch128_roll(Data, Offset, X, Y, Z, V, W) ->
    RollData = binary:part(Data, Offset, byte_size(Data) - Offset),
    <<_:16/binary, RAt16:64/little, _:24/binary, RAt48:64/little, _/binary>> = RollData,
    X1 = rot64(X + Y + fst(V) + RAt16, 37) * ?K1,
    Y1 = rot64(Y + snd(V) + RAt48, 42) * ?K1,
    X2 = X1 bxor snd(W),
    Y2 = Y1 bxor fst(V),
    Z1 = rot64(Z bxor fst(W), 33),
    V1 = weak_hash32_seeds_byte(binary:part(Data, Offset, 32), snd(V) * ?K1, X2 + fst(W)),
    W1 = weak_hash32_seeds_byte(binary:part(Data, Offset + 32, 32), Z1 + snd(W), Y2),
    {X2, Y2, Z1, V1, W1}.

%% @doc Process tail for CH128 (up to 4 chunks of 32 bytes).
-spec ch128_tail(
    binary(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    {non_neg_integer(), non_neg_integer()},
    {non_neg_integer(), non_neg_integer()}
) ->
    {non_neg_integer(), non_neg_integer(), {non_neg_integer(), non_neg_integer()}, {
        non_neg_integer(), non_neg_integer()
    }}.
ch128_tail(T, TotalLen, X, Y, V, W) ->
    %% Calculate remaining bytes after 128-byte loop
    %% Remaining = TotalLen mod 128 (bytes left after processing 128-byte chunks)
    Remaining = TotalLen rem 128,
    ch128_tail_loop(T, TotalLen, 0, Remaining, X, Y, V, W).

-spec ch128_tail_loop(
    binary(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    {non_neg_integer(), non_neg_integer()},
    {non_neg_integer(), non_neg_integer()}
) ->
    {non_neg_integer(), non_neg_integer(), {non_neg_integer(), non_neg_integer()}, {
        non_neg_integer(), non_neg_integer()
    }}.
ch128_tail_loop(T, TotalLen, I, Remaining, X, Y, V, W) when I < Remaining ->
    %% Increment I first, like Go does: for i := 0; i < len(s); { i += 32; ... }
    I1 = I + 32,
    Y1 = (rot64(Y - X, 42) * ?K0 + snd(V)) band 16#ffffffffffffffff,
    %% Read from end of original input: t[len(t)-i+16:] where i is the NEW value (I1)
    WLowOffset = TotalLen - I1 + 16,
    WLowAdd =
        case WLowOffset >= 0 andalso WLowOffset + 8 =< TotalLen of
            true -> fetch64(T, WLowOffset);
            false -> 0
        end,
    X1 = (rot64(X, 49) * ?K0 + fst(W) + WLowAdd) band 16#ffffffffffffffff,
    W1 = {(fst(W) + WLowAdd + fst(V)) band 16#ffffffffffffffff, snd(W)},
    %% Read 32-byte chunk from end of original input: t[len(t)-i:] where i is the NEW value (I1)
    V1ChunkOffset = TotalLen - I1,
    V1 =
        case V1ChunkOffset >= 0 andalso V1ChunkOffset + 32 =< TotalLen of
            true ->
                V1Chunk = binary:part(T, V1ChunkOffset, 32),
                weak_hash32_seeds_byte(V1Chunk, fst(V), snd(V));
            false ->
                V
        end,
    %% Continue with I1 (not I+32) to match Go's post-increment behavior
    ch128_tail_loop(T, TotalLen, I1, Remaining, X1, Y1, V1, W1);
ch128_tail_loop(_T, _TotalLen, _I, _Remaining, X, Y, V, W) ->
    {X, Y, V, W}.

%% @doc A subroutine for CH128(). Returns a decent 128-bit hash for strings
%% of any length representable in signed long. Based on City and Murmur.
-spec ch_murmur(binary(), {non_neg_integer(), non_neg_integer()}) ->
    {Low :: non_neg_integer(), High :: non_neg_integer()}.
ch_murmur(Data, {SeedLow, SeedHigh}) ->
    Length = byte_size(Data),
    A0 = SeedLow,
    B0 = SeedHigh,
    L = Length - 16,

    {A, B, C, D} =
        case Length =< 16 of
            true ->
                A1 = shift_mix(A0 * ?K1) * ?K1,
                C1 = B0 * ?K1 + ch0to16(Data, Length),
                D1 =
                    case Length >= 8 of
                        true ->
                            <<Val:64/little, _/binary>> = Data,
                            shift_mix(A1 + Val);
                        false ->
                            shift_mix(A1 + C1)
                    end,
                {A1, B0, C1, D1};
            false ->
                CLast = fetch64(Data, Length - 8),
                DLast = fetch64(Data, Length - 16),
                C1 = ch16(CLast + ?K1, A0),
                D1 = ch16(B0 + Length, C1 + DLast),
                A1 = A0 + D1,

                %% First 16-byte chunk
                <<Val0:64/little, Val8:64/little, Rest0/binary>> = Data,
                A2 = A1 bxor (shift_mix(Val0 * ?K1) * ?K1),
                A3 = A2 * ?K1,
                B1 = B0 bxor A3,
                C2 = C1 bxor (shift_mix(Val8 * ?K1) * ?K1),
                C3 = C2 * ?K1,
                D2 = D1 bxor C3,

                %% Process remaining 16-byte chunks
                ch_murmur_loop(Rest0, L - 16, A3, B1, C3, D2)
        end,

    AFinal = ch16(A, C),
    BFinal = ch16(D, B),
    {AFinal bxor BFinal, ch16(BFinal, AFinal)}.

%% @doc Loop for ch_murmur processing 16-byte chunks.
-spec ch_murmur_loop(
    binary(),
    integer(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer()
) ->
    {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}.
ch_murmur_loop(Data, L, A, B, C, D) when L > 0, byte_size(Data) >= 16 ->
    <<Val0:64/little, Val8:64/little, Rest/binary>> = Data,
    A1 = A bxor (shift_mix(Val0 * ?K1) * ?K1),
    A2 = A1 * ?K1,
    B1 = B bxor A2,
    C1 = C bxor (shift_mix(Val8 * ?K1) * ?K1),
    C2 = C1 * ?K1,
    D1 = D bxor C2,
    ch_murmur_loop(Rest, L - 16, A2, B1, C2, D1);
ch_murmur_loop(_Data, _L, A, B, C, D) ->
    {A, B, C, D}.

%%%===================================================================
%%% Internal functions - CH64 (ClickHouse variant)
%%%===================================================================

%% @doc CH64 for long strings (> 64 bytes).
-spec ch64_long(binary(), non_neg_integer()) -> non_neg_integer().
ch64_long(Data, Length) ->
    <<X0:64/little, _/binary>> = Data,
    Y0 = (fetch64(Data, Length - 16) bxor ?K1) band 16#ffffffffffffffff,
    Z0 = (fetch64(Data, Length - 56) bxor ?K0) band 16#ffffffffffffffff,

    V0 = weak_hash32_seeds_byte(binary:part(Data, Length - 64, 32), Length, Y0),
    W0 = weak_hash32_seeds_byte(
        binary:part(Data, Length - 32, 32), (Length * ?K1) band 16#ffffffffffffffff, ?K0
    ),
    Z1 = (Z0 + (shift_mix(snd(V0)) * ?K1) band 16#ffffffffffffffff) band 16#ffffffffffffffff,
    X1 = (rot64((Z1 + X0) band 16#ffffffffffffffff, 39) * ?K1) band 16#ffffffffffffffff,
    Y1 = (rot64(Y0, 33) * ?K1) band 16#ffffffffffffffff,

    %% Process 64-byte chunks
    Chunks = (Length div 64) * 64,
    ChunkData = binary:part(Data, 0, Chunks),
    {XFinal, YFinal, ZFinal, VFinal, WFinal} =
        ch64_loop(ChunkData, X1, Y1, Z1, V0, W0),

    Part1 =
        (ch16(fst(VFinal), fst(WFinal)) + (shift_mix(YFinal) * ?K1) band 16#ffffffffffffffff +
            ZFinal) band 16#ffffffffffffffff,
    Part2 = (ch16(snd(VFinal), snd(WFinal)) + XFinal) band 16#ffffffffffffffff,
    ch16(Part1, Part2).

%% @doc Main loop for CH64.
-spec ch64_loop(
    binary(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    {non_neg_integer(), non_neg_integer()},
    {non_neg_integer(), non_neg_integer()}
) ->
    {
        non_neg_integer(),
        non_neg_integer(),
        non_neg_integer(),
        {non_neg_integer(), non_neg_integer()},
        {non_neg_integer(), non_neg_integer()}
    }.
ch64_loop(Data, X, Y, Z, V, W) when byte_size(Data) >= 64 ->
    Val16 = fetch64(Data, 16),
    Val48 = fetch64(Data, 48),
    X1 =
        (rot64((X + Y + fst(V) + Val16) band 16#ffffffffffffffff, 37) * ?K1) band
            16#ffffffffffffffff,
    Y1 = (rot64((Y + snd(V) + Val48) band 16#ffffffffffffffff, 42) * ?K1) band 16#ffffffffffffffff,
    X2 = (X1 bxor snd(W)) band 16#ffffffffffffffff,
    Y2 = (Y1 bxor fst(V)) band 16#ffffffffffffffff,
    Z1 = rot64(Z bxor fst(W), 33),
    V1 = weak_hash32_seeds_byte(
        Data, (snd(V) * ?K1) band 16#ffffffffffffffff, (X2 + fst(W)) band 16#ffffffffffffffff
    ),
    W1 = weak_hash32_seeds_byte(
        binary:part(Data, 32, 32), (Z1 + snd(W)) band 16#ffffffffffffffff, Y2
    ),
    {Z2, X3} = {X2, Z1},
    ch64_loop(binary:part(Data, 64, byte_size(Data) - 64), X3, Y2, Z2, V1, W1);
ch64_loop(_Data, X, Y, Z, V, W) ->
    {X, Y, Z, V, W}.

%% @doc Return an 8-byte hash for 33 to 64 bytes.
-spec ch33to64(binary(), non_neg_integer()) -> non_neg_integer().
ch33to64(Data, Length) ->
    Z = fetch64(Data, 24),
    <<A0:64/little, _/binary>> = Data,
    A1 = A0 + (Length + fetch64(Data, Length - 16)) * ?K0,
    B = rot64(A1 + Z, 52),
    C0 = rot64(A1, 37),
    A2Add = fetch64(Data, 8),
    A2 = A1 + A2Add,
    C1 = C0 + rot64(A2, 7),
    A3Add = fetch64(Data, 16),
    A3 = A2 + A3Add,

    Vf = A3 + Z,
    Vs = B + rot64(A3, 31) + C1,

    A40 = fetch64(Data, 16),
    A41 = fetch64(Data, Length - 32),
    A4 = A40 + A41,
    Z2 = fetch64(Data, Length - 8),
    B2 = rot64(A4 + Z2, 52),
    C2 = rot64(A4, 37),
    A5Add = fetch64(Data, Length - 24),
    A5 = A4 + A5Add,
    C3 = C2 + rot64(A5, 7),
    A6Add = fetch64(Data, Length - 16),
    A6 = A5 + A6Add,

    Wf = A6 + Z2,
    Ws = B2 + rot64(A6, 31) + C3,
    R = shift_mix((Vf + Ws) * ?K2 + (Wf + Vs) * ?K0),
    shift_mix(R * ?K0 + Vs) * ?K2.

%% @doc Return an 8-byte hash for 17 to 32 bytes.
-spec ch17to32(binary(), non_neg_integer()) -> non_neg_integer().
ch17to32(Data, Length) ->
    <<A0:64/little, _/binary>> = Data,
    A = A0 * ?K1,
    B = fetch64(Data, 8),
    C0 = fetch64(Data, Length - 8),
    C = C0 * ?K2,
    D0 = fetch64(Data, Length - 16),
    D = D0 * ?K0,
    hash16(
        rot64(A - B, 43) + rot64(C, 30) + D,
        A + rot64(B bxor ?K3, 20) - C + Length
    ).

%% @doc Return an 8-byte hash for 0 to 16 bytes.
-spec ch0to16(binary(), non_neg_integer()) -> non_neg_integer().
ch0to16(Data, Length) when Length > 8 ->
    <<A:64/little, _/binary>> = Data,
    B = fetch64(Data, Length - 8),
    ch16(A, rot64(B + Length, Length)) bxor B;
ch0to16(Data, Length) when Length >= 4 ->
    <<A:32/little, _/binary>> = Data,
    B = fetch32(Data, Length - 4),
    ch16(Length + (A bsl 3), B);
ch0to16(Data, Length) when Length > 0 ->
    <<A:8, _/binary>> = Data,
    B = fetch8(Data, Length bsr 1),
    C = fetch8(Data, Length - 1),
    Y = A + (B bsl 8),
    Z = Length + (C bsl 2),
    shift_mix(Y * ?K2 bxor Z * ?K3) * ?K2;
ch0to16(_Data, 0) ->
    ?K2.

%%%===================================================================
%%% Helper functions
%%%===================================================================

%% @doc Bitwise right rotate.
-spec rot64(non_neg_integer(), non_neg_integer()) -> non_neg_integer().
rot64(Val, Shift) ->
    Masked = Val band 16#ffffffffffffffff,
    ((Masked bsr Shift) bor (Masked bsl (64 - Shift))) band 16#ffffffffffffffff.

%% @doc Shift mix operation.
-spec shift_mix(non_neg_integer()) -> non_neg_integer().
shift_mix(Val) ->
    Masked = Val band 16#ffffffffffffffff,
    (Masked bxor (Masked bsr 47)) band 16#ffffffffffffffff.

%% @doc Hash 128-bit value to 64-bit.
-spec hash128_to_64({non_neg_integer(), non_neg_integer()}) -> non_neg_integer().
hash128_to_64({Low, High}) ->
    Mul = 16#9ddfea08eb382d69,
    A0 = ((Low bxor High) * Mul) band 16#ffffffffffffffff,
    A1 = (A0 bxor (A0 bsr 47)) band 16#ffffffffffffffff,
    B0 = ((High bxor A1) * Mul) band 16#ffffffffffffffff,
    B1 = (B0 bxor (B0 bsr 47)) band 16#ffffffffffffffff,
    (B1 * Mul) band 16#ffffffffffffffff.

%% @doc CH16 helper.
-spec ch16(non_neg_integer(), non_neg_integer()) -> non_neg_integer().
ch16(U, V) ->
    hash128_to_64({U band 16#ffffffffffffffff, V band 16#ffffffffffffffff}).

%% @doc Hash16 helper.
-spec hash16(non_neg_integer(), non_neg_integer()) -> non_neg_integer().
hash16(U, V) ->
    hash128_to_64({U band 16#ffffffffffffffff, V band 16#ffffffffffffffff}).

%% @doc Return a 16-byte hash for s[0] ... s[31], a, and b. Quick and dirty.
-spec weak_hash32_seeds_byte(binary(), non_neg_integer(), non_neg_integer()) ->
    {non_neg_integer(), non_neg_integer()}.
weak_hash32_seeds_byte(Data, A, B) when byte_size(Data) >= 32 ->
    <<W:64/little, X:64/little, Y:64/little, Z:64/little, _/binary>> = Data,
    weak_hash32_seeds(W, X, Y, Z, A, B);
weak_hash32_seeds_byte(_Data, A, B) ->
    {A, B}.

%% @doc Weak hash with 32-byte seeds.
-spec weak_hash32_seeds(
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer()
) ->
    {non_neg_integer(), non_neg_integer()}.
weak_hash32_seeds(W, X, Y, Z, A0, B0) ->
    A1 = (A0 + W) band 16#ffffffffffffffff,
    B1 = (rot64((B0 + A1 + Z) band 16#ffffffffffffffff, 21)) band 16#ffffffffffffffff,
    C = A1,
    A2 = (A1 + X) band 16#ffffffffffffffff,
    A3 = (A2 + Y) band 16#ffffffffffffffff,
    B2 = (B1 + rot64(A3, 44)) band 16#ffffffffffffffff,
    {(A3 + Z) band 16#ffffffffffffffff, (B2 + C) band 16#ffffffffffffffff}.

%% @doc Fetch 64-bit value at offset.
-spec fetch64(binary(), non_neg_integer()) -> non_neg_integer().
fetch64(Data, Offset) ->
    <<Val:64/little>> = binary:part(Data, Offset, 8),
    Val.

%% @doc Fetch 32-bit value at offset.
-spec fetch32(binary(), non_neg_integer()) -> non_neg_integer().
fetch32(Data, Offset) ->
    <<Val:32/little>> = binary:part(Data, Offset, 4),
    Val.

%% @doc Fetch 8-bit value at offset.
-spec fetch8(binary(), non_neg_integer()) -> non_neg_integer().
fetch8(Data, Offset) ->
    <<Val:8>> = binary:part(Data, Offset, 1),
    Val.

%% @doc First element of tuple.
-spec fst({term(), term()}) -> term().
fst({A, _B}) -> A.

%% @doc Second element of tuple.
-spec snd({term(), term()}) -> term().
snd({_A, B}) -> B.
