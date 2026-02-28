-module(generators).

-include_lib("proper/include/proper.hrl").

-export([
    % Character and string generators
    char_gen/0,
    string_gen/0,
    non_empty_string_gen/0,
    binary_string_gen/0,
    non_empty_binary_string_gen/0,
    % Integer generators
    int8_gen/0,
    int16_gen/0,
    int32_gen/0,
    int64_gen/0,
    uint16_gen/0,
    uint32_gen/0,
    uint64_gen/0,
    varint_gen/0,
    % Float generators
    float32_gen/0,
    float64_gen/0,
    normal_float64_gen/0,
    % Temporal generators
    date_gen/0,
    datetime_gen/0,
    % Composite generators
    map_gen/2
]).

%%%===================================================================
%%% Character and String Generators
%%%===================================================================

%% Generator for valid UTF-8 characters
char_gen() ->
    oneof([
        % ASCII printable characters
        range(32, 126),
        % Extended ASCII
        range(160, 255),
        % Euro symbol
        16#20AC,
        % Emoji (smiley face)
        16#1F600
    ]).

%% Generator for valid UTF-8 strings (as character lists)
string_gen() ->
    ?LET(Chars, list(char_gen()), Chars).

%% Generator for non-empty UTF-8 strings (as character lists)
non_empty_string_gen() ->
    ?SUCHTHAT(S, string_gen(), S =/= "").

%% Generator for strings as binaries
binary_string_gen() ->
    ?LET(S, string_gen(), unicode:characters_to_binary(S)).

%% Generator for non-empty strings as binaries
non_empty_binary_string_gen() ->
    ?LET(S, non_empty_string_gen(), unicode:characters_to_binary(S)).

%%%===================================================================
%%% Integer Generators
%%%===================================================================

%% Generator for valid Int8 values
int8_gen() -> range(-128, 127).

%% Generator for valid Int16 values
int16_gen() -> range(-32768, 32767).

%% Generator for valid Int32 values
int32_gen() -> range(-2147483648, 2147483647).

%% Generator for valid Int64 values
int64_gen() -> range(-9223372036854775808, 9223372036854775807).

%% Generator for valid UInt16 values
uint16_gen() -> range(0, 65535).

%% Generator for valid UInt32 values
uint32_gen() -> range(0, 4294967295).

%% Generator for valid UInt64 values
uint64_gen() -> range(0, 18446744073709551615).

%% Generator for valid varints (0 to 2^63-1 to avoid overflow)
varint_gen() ->
    ?LET(N, range(0, 16#7FFFFFFFFFFFFFFF), N).

%% Generator for normal float64 values (excluding infinity and nan)
normal_float64_gen() ->
    ?SUCHTHAT(F, float(), is_number(F) andalso F == F andalso abs(F) < 1.0e308).

%% Generator for maps with random key-value pairs
map_gen(KeyGen, ValueGen) ->
    ?LET(
        Pairs,
        list({KeyGen, ValueGen}),
        maps:from_list(Pairs)
    ).

%%%===================================================================
%%% Float Generators
%%%===================================================================

%% Generator for valid Float32 values
float32_gen() ->
    oneof([
        float(),
        return(0.0),
        return(1.0),
        return(-1.0),
        return(infinity),
        return('-infinity'),
        return(nan)
    ]).

%% Generator for valid Float64 values
float64_gen() ->
    oneof([
        float(),
        return(0.0),
        return(1.0),
        return(-1.0),
        return(infinity),
        return('-infinity'),
        return(nan)
    ]).

%%%===================================================================
%%% Temporal Generators
%%%===================================================================

%% Generator for valid Date values (1970-01-01 to 2149-06-06)
%% Date: 0 to 65535 days from 1970-01-01
date_gen() ->
    ?LET(Days, range(0, 65535), calendar:gregorian_days_to_date(Days + 719528)).

%% Generator for valid DateTime values (1970-01-01 00:00:00 to 2106-02-07 06:28:15)
%% DateTime: 0 to 4294967295 seconds from 1970-01-01
datetime_gen() ->
    ?LET(
        Seconds, range(0, 4294967295), calendar:gregorian_seconds_to_datetime(Seconds + 62167219200)
    ).
