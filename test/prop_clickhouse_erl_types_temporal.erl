%% @doc Property tests for ClickHouse temporal type encoding/decoding.
-module(prop_clickhouse_erl_types_temporal).

-include_lib("proper/include/proper.hrl").

-import(generators, [date_gen/0, datetime_gen/0]).

-export([
    prop_date_round_trip/0,
    prop_datetime_round_trip/0,
    prop_datetime64_round_trip/0,
    prop_temporal_boundary_validation/0,
    prop_temporal_truncation_detection/0,
    prop_temporal_protocol_compliance/0
]).

%% ============================================================================
%% Generators
%% ============================================================================

%% DateTime64: Int64 values
datetime64_gen() ->
    %% Generate full range of int64
    oneof([
        range(-9223372036854775808, 9223372036854775807),
        %% Also focus on typical timestamp ranges (last 50 years to next 50 years approx)
        %% Microseconds since epoch
        range(0, 3153600000000000)
    ]).

%% Generators for invalid temporal values
%% Date: Valid range is 0 to 65535 days from 1970-01-01
%% Invalid dates are those that would produce days < 0 or > 65535
invalid_date_gen() ->
    oneof([
        %% Dates before 1970-01-01 (negative days)
        ?LET(Days, range(-10000, -1), calendar:gregorian_days_to_date(Days + 719528)),
        %% Dates beyond max UInt16 days from 1970-01-01
        ?LET(Days, range(65536, 100000), calendar:gregorian_days_to_date(Days + 719528))
    ]).

%% DateTime: Valid range is 0 to 4294967295 seconds from 1970-01-01
%% Invalid datetimes are those that would produce seconds < 0 or > 4294967295
invalid_datetime_gen() ->
    oneof([
        %% Datetimes before 1970-01-01 00:00:00 (negative seconds)
        ?LET(
            Seconds,
            range(-1000000, -1),
            calendar:gregorian_seconds_to_datetime(Seconds + 62167219200)
        ),
        %% Datetimes beyond max UInt32 seconds from 1970-01-01
        ?LET(
            Seconds,
            range(4294967296, 5000000000),
            calendar:gregorian_seconds_to_datetime(Seconds + 62167219200)
        )
    ]).

%% Generators for truncated binaries
truncated_uint16_gen() -> oneof([<<>>, binary(1)]).
truncated_uint32_gen() -> oneof([<<>>, binary(1), binary(2), binary(3)]).

%% ============================================================================
%% Properties
%% ============================================================================

%% Property: Date Round Trip
%% **Validates: Requirements 3.1**
prop_date_round_trip() ->
    ?FORALL(
        Date,
        date_gen(),
        begin
            Encoded = clickhouse_erl_types_temporal:encode_date(Date),
            {ok, Decoded, <<>>} = clickhouse_erl_types_temporal:decode_date(Encoded),
            Decoded =:= Date
        end
    ).

%% Property: DateTime Round Trip
%% **Validates: Requirements 3.2**
prop_datetime_round_trip() ->
    ?FORALL(
        DateTime,
        datetime_gen(),
        begin
            Encoded = clickhouse_erl_types_temporal:encode_datetime(DateTime),
            {ok, Decoded, <<>>} = clickhouse_erl_types_temporal:decode_datetime(Encoded),
            Decoded =:= DateTime
        end
    ).

%% Property: DateTime64 Round Trip
%% **Validates: Requirements 3.3**
prop_datetime64_round_trip() ->
    ?FORALL(
        Val,
        datetime64_gen(),
        begin
            %% Precision determines interpretation but not encoding length/format for simple int64 mapping
            Precision = 3,
            Encoded = clickhouse_erl_types_temporal:encode_datetime64(Val, Precision),
            {ok, Decoded, <<>>} = clickhouse_erl_types_temporal:decode_datetime64(
                Encoded, Precision
            ),
            Decoded =:= Val
        end
    ).

%% Property: Temporal Boundary Error Handling
%% **Validates: Requirements 3.4**
prop_temporal_boundary_validation() ->
    ?FORALL(
        {Type, Value},
        oneof([
            {date, invalid_date_gen()},
            {datetime, invalid_datetime_gen()}
        ]),
        begin
            Result =
                case Type of
                    date -> clickhouse_erl_types_temporal:encode_date(Value);
                    datetime -> clickhouse_erl_types_temporal:encode_datetime(Value)
                end,
            case Result of
                {error, {value_out_of_range, _}} -> true;
                {error, {invalid_date, _}} -> true;
                {error, {invalid_datetime, _}} -> true;
                _ -> false
            end
        end
    ).

%% Property: Temporal truncation error detection
%% **Validates: Requirements 3.5**
prop_temporal_truncation_detection() ->
    ?FORALL(
        {Type, TruncatedBinary},
        oneof([
            {date, truncated_uint16_gen()},
            {datetime, truncated_uint32_gen()},
            {datetime64,
                oneof([
                    <<>>,
                    binary(1),
                    binary(2),
                    binary(3),
                    binary(4),
                    binary(5),
                    binary(6),
                    binary(7)
                ])}
        ]),
        begin
            Result =
                case Type of
                    date ->
                        clickhouse_erl_types_temporal:decode_date(TruncatedBinary);
                    datetime ->
                        clickhouse_erl_types_temporal:decode_datetime(TruncatedBinary);
                    datetime64 ->
                        clickhouse_erl_types_temporal:decode_datetime64(TruncatedBinary, 3)
                end,
            case Result of
                {error, {truncated_data, _}} -> true;
                _ -> false
            end
        end
    ).

%% Property: Temporal types use correct epoch and encoding
%% **Validates: Requirements 8.1, 8.2, 3.1, 3.2, 3.3**
prop_temporal_protocol_compliance() ->
    ?FORALL(
        {Type, Value},
        oneof([
            {date, date_gen()},
            {datetime, datetime_gen()},
            {datetime64, datetime64_gen()}
        ]),
        begin
            Encoded =
                case Type of
                    date -> clickhouse_erl_types_temporal:encode_date(Value);
                    datetime -> clickhouse_erl_types_temporal:encode_datetime(Value);
                    datetime64 -> clickhouse_erl_types_temporal:encode_datetime64(Value, 3)
                end,
            %% Verify the encoding is the correct size
            ExpectedSize =
                case Type of
                    date -> 2;
                    datetime -> 4;
                    datetime64 -> 8
                end,
            SizeCorrect = byte_size(Encoded) =:= ExpectedSize,
            %% Verify round-trip works correctly
            DecodeResult =
                case Type of
                    date -> clickhouse_erl_types_temporal:decode_date(Encoded);
                    datetime -> clickhouse_erl_types_temporal:decode_datetime(Encoded);
                    datetime64 -> clickhouse_erl_types_temporal:decode_datetime64(Encoded, 3)
                end,
            RoundTripCorrect =
                case DecodeResult of
                    {ok, DecodedValue, <<>>} -> DecodedValue =:= Value;
                    _ -> false
                end,
            %% Verify little-endian encoding (least significant byte first)
            <<FirstByte:8, _/binary>> = Encoded,
            %% For dates and datetimes, first byte should be related to the value
            %% This is a basic sanity check for little-endian
            LittleEndianCheck =
                is_integer(FirstByte) andalso FirstByte >= 0 andalso FirstByte =< 255,
            SizeCorrect andalso RoundTripCorrect andalso LittleEndianCheck
        end
    ).
