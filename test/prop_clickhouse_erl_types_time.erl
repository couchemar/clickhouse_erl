%% @doc Property-based tests for Time and Time64 type encoding/decoding.
-module(prop_clickhouse_erl_types_time).

-include_lib("proper/include/proper.hrl").

%%%===================================================================
%%% Properties
%%%===================================================================

%% Property 22: Time encode-decode roundtrip
%% For any valid time value (tuple or integer seconds since midnight),
%% encoding then decoding should produce an equivalent {Hour, Minute, Second} tuple.
%% Validates: Requirements 6.1, 6.2
prop_time_roundtrip() ->
    ?FORALL(
        TimeValue,
        time_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_time:encode_time(TimeValue),
            {ok, Decoded, <<>>} = clickhouse_erl_types_time:decode_time(Encoded),
            Expected = normalize_time(TimeValue),
            Expected =:= Decoded
        end
    ).

%% Property 23: Time64 encode-decode roundtrip
%% For any valid time64 value (tuple or integer nanoseconds since midnight),
%% encoding then decoding should produce an equivalent {Hour, Minute, Second, Nanosecond} tuple.
%% Validates: Requirements 6.3, 6.4
prop_time64_roundtrip() ->
    ?FORALL(
        Time64Value,
        time64_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_time:encode_time64(Time64Value),
            {ok, Decoded, <<>>} = clickhouse_erl_types_time:decode_time64(Encoded),
            Expected = normalize_time64(Time64Value),
            Expected =:= Decoded
        end
    ).

%% Property 24: Time encoding format
%% For any time value, encoding should produce 4 bytes (Int32) for Time
%% or 8 bytes (Int64) for Time64, representing seconds or nanoseconds since midnight.
%% Validates: Requirements 6.5, 6.6
prop_time_encoding_format() ->
    ?FORALL(
        TimeValue,
        time_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_time:encode_time(TimeValue),
            % Time should be 4 bytes
            byte_size(Encoded) =:= 4 andalso
                % Verify it's a valid Int32 little-endian
                case Encoded of
                    <<Seconds:32/little-signed>> ->
                        Seconds >= 0 andalso Seconds =< 86399;
                    _ ->
                        false
                end
        end
    ).

prop_time64_encoding_format() ->
    ?FORALL(
        Time64Value,
        time64_gen(),
        begin
            {ok, Encoded} = clickhouse_erl_types_time:encode_time64(Time64Value),
            % Time64 should be 8 bytes
            byte_size(Encoded) =:= 8 andalso
                % Verify it's a valid Int64 little-endian
                case Encoded of
                    <<Nanoseconds:64/little-signed>> ->
                        Nanoseconds >= 0 andalso Nanoseconds =< 86399999999999;
                    _ ->
                        false
                end
        end
    ).

%% Property 25: Time range validation
%% For any time value outside the valid range (0-86399 seconds for Time,
%% 0-86399999999999 nanoseconds for Time64), encoding should return an error tuple.
%% Validates: Requirements 6.10
prop_time_range_validation() ->
    ?FORALL(
        InvalidSeconds,
        oneof([
            integer(-1000, -1),
            integer(86400, 100000)
        ]),
        begin
            Result = clickhouse_erl_types_time:encode_time(InvalidSeconds),
            case Result of
                {error, {value_out_of_range, _}} -> true;
                _ -> false
            end
        end
    ).

prop_time64_range_validation() ->
    ?FORALL(
        InvalidNanoseconds,
        oneof([
            integer(-1000000000, -1),
            integer(86400000000000, 100000000000000)
        ]),
        begin
            Result = clickhouse_erl_types_time:encode_time64(InvalidNanoseconds),
            case Result of
                {error, {value_out_of_range, _}} -> true;
                _ -> false
            end
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% Generate valid time values (both tuple and integer formats)
time_gen() ->
    oneof([
        time_tuple_gen(),
        time_seconds_gen()
    ]).

%% Generate time tuples {Hour, Minute, Second}
time_tuple_gen() ->
    {integer(0, 23), integer(0, 59), integer(0, 59)}.

%% Generate time as seconds since midnight
time_seconds_gen() ->
    integer(0, 86399).

%% Generate valid time64 values (both tuple and integer formats)
time64_gen() ->
    oneof([
        time64_tuple_gen(),
        time64_nanoseconds_gen()
    ]).

%% Generate time64 tuples {Hour, Minute, Second, Nanosecond}
time64_tuple_gen() ->
    {integer(0, 23), integer(0, 59), integer(0, 59), integer(0, 999999999)}.

%% Generate time64 as nanoseconds since midnight
time64_nanoseconds_gen() ->
    integer(0, 86399999999999).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% Normalize time value to tuple format
normalize_time({H, M, S}) ->
    {H, M, S};
normalize_time(Seconds) when is_integer(Seconds) ->
    clickhouse_erl_types_time:seconds_to_time(Seconds).

%% Normalize time64 value to tuple format
normalize_time64({H, M, S, N}) ->
    {H, M, S, N};
normalize_time64(Nanoseconds) when is_integer(Nanoseconds) ->
    clickhouse_erl_types_time:nanoseconds_to_time64(Nanoseconds).
