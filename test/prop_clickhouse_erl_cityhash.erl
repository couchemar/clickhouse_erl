%% @doc Property-based tests for CityHash128 checksum module
-module(prop_clickhouse_erl_cityhash).
-include_lib("proper/include/proper.hrl").

-import(generators, [uint64_gen/0]).

%%%===================================================================
%%% Property Tests
%%%===================================================================

%% @doc Property 5: Checksum Serialization Round-Trip
%% Validates: Requirements 7.3, 7.4
%%
%% For any 128-bit hash value, encoding as 16 bytes (low 64 bits then high 64 bits,
%% little-endian) then decoding should produce the original hash value.
prop_checksum_serialization_roundtrip() ->
    ?FORALL(
        {Low, High},
        {uint64_gen(), uint64_gen()},
        begin
            %% Encode the hash components
            Encoded = clickhouse_erl_cityhash:encode_hash(Low, High),

            %% Verify encoded format
            16 = byte_size(Encoded),

            %% Decode back to components
            {DecodedLow, DecodedHigh} = clickhouse_erl_cityhash:decode_hash(Encoded),

            %% Verify round-trip consistency
            (Low =:= DecodedLow) andalso (High =:= DecodedHigh)
        end
    ).
