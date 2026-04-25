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
    map_gen/2,
    % Streaming insert generators
    column_defs_gen/0,
    column_data_gen/1,
    streaming_callback_sequence_gen/0,
    invalid_callback_return_gen/0
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

%%%===================================================================
%%% Streaming Insert Generators
%%%===================================================================

%% @doc Generator for column definitions with empty data lists.
%% Produces 1-5 columns with UInt32 or String types.
-spec column_defs_gen() -> proper_types:type().
column_defs_gen() ->
    ?LET(
        {N, Types},
        ?LET(
            Count,
            range(1, 5),
            {Count, vector(Count, oneof([<<"UInt32">>, <<"String">>]))}
        ),
        [
            #{
                name => list_to_binary("col_" ++ integer_to_list(I)),
                type => lists:nth(I, Types),
                data => []
            }
         || I <- lists:seq(1, N)
        ]
    ).

%% @doc Generator for column data matching given definitions with random row counts (1-50).
%% For UInt32 type, generates uint32 values. For String type, generates binary strings.
-spec column_data_gen([map()]) -> proper_types:type().
column_data_gen(ColumnDefs) ->
    ?LET(
        RowCount,
        range(1, 50),
        ?LET(
            Columns,
            proper_types:fixed_list(
                [column_values_gen(Col, RowCount) || Col <- ColumnDefs]
            ),
            Columns
        )
    ).

%% @doc Generator for a sequence of callback return values:
%% a sequence of {ok, Data, Acc} tuples followed by exactly one {done, Acc} or {error, Reason}.
-spec streaming_callback_sequence_gen() -> proper_types:type().
streaming_callback_sequence_gen() ->
    ?LET(
        {OkCount, Terminator},
        {range(0, 5), oneof([done, error])},
        begin
            OkEntries = [{ok, placeholder_data, I} || I <- lists:seq(1, OkCount)],
            Final =
                case Terminator of
                    done -> [{done, OkCount + 1}];
                    error -> [{error, {test_error, OkCount + 1}}]
                end,
            OkEntries ++ Final
        end
    ).

%% @doc Generator for terms that are NOT valid callback returns.
%% Valid returns are {ok, _, _}, {done, _}, or {error, _}.
-spec invalid_callback_return_gen() -> proper_types:type().
invalid_callback_return_gen() ->
    oneof([
        %% Atoms
        oneof([ok, done, error, undefined, true, false]),
        %% Plain integers
        integer(),
        %% Binaries
        binary(),
        %% Wrong-arity tuples
        ?LET(X, integer(), {ok, X}),
        ?LET(X, integer(), {done, X, X}),
        %% Tuples with wrong tag
        ?LET({X, Y}, {integer(), integer()}, {wrong, X, Y}),
        ?LET(X, integer(), {data, X}),
        %% Lists
        list(integer())
    ]).

%%%===================================================================
%%% Internal Helpers (Streaming Insert)
%%%===================================================================

%% @doc Generate a single column map with resolved values for the given row count.
-spec column_values_gen(map(), pos_integer()) -> proper_types:type().
column_values_gen(#{name := Name, type := Type}, RowCount) ->
    ?LET(
        Values,
        vector(RowCount, data_for_type(Type)),
        #{name => Name, type => Type, data => Values}
    ).

%% @doc Return a PropEr generator for a single value of the given ClickHouse type.
-spec data_for_type(binary()) -> proper_types:type().
data_for_type(<<"UInt32">>) ->
    uint32_gen();
data_for_type(<<"String">>) ->
    non_empty_binary_string_gen().
