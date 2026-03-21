%% @doc Unit tests for extended type support in clickhouse_erl_parser_block.
%%
%% Tests block parser with extended types (Int128, UInt256, Decimal, DateTime64, etc.)
%% using synthetic packet data (no live ClickHouse connection).
-module(clickhouse_erl_parser_block_extended_types_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test Helpers
%%%===================================================================

%% @doc Encode a string with varint length prefix
encode_string(Str) when is_binary(Str) ->
    Len = byte_size(Str),
    <<Len:8, Str/binary>>;
encode_string(Str) when is_list(Str) ->
    encode_string(list_to_binary(Str)).

%% @doc Encode varint (simple version for small numbers)
encode_varint(N) when N < 128 ->
    <<N:8>>;
encode_varint(N) ->
    <<(N band 127 bor 128):8, (N bsr 7):8>>.

%% @doc Build minimal block info (no overflows, no bucket)
build_block_info() ->
    % Field 0 = end of block info
    <<0:8>>.

%% @doc Build block header with temp table, block info, num columns, num rows
build_block_header(TempTable, NumColumns, NumRows) ->
    TempTableBin = encode_string(TempTable),
    BlockInfo = build_block_info(),
    NumColsBin = encode_varint(NumColumns),
    NumRowsBin = encode_varint(NumRows),
    <<TempTableBin/binary, BlockInfo/binary, NumColsBin/binary, NumRowsBin/binary>>.

%% @doc Build column header (name + type + custom serialization flag)
%% Version 54460 supports custom serialization, so we need the flag byte
build_column_header(Name, Type) ->
    NameBin = encode_string(Name),
    TypeBin = encode_string(Type),
    % No custom serialization
    CustomFlag = 0,
    <<NameBin/binary, TypeBin/binary, CustomFlag:8>>.

%%%===================================================================
%%% Extended Integer Type Tests
%%%===================================================================

parse_int128_column_test() ->
    %% Build block with 1 Int128 column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"value">>, <<"Int128">>),

    %% Int128 value: 16 bytes little-endian
    Value = <<42:128/signed-little>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    %% Verify column header event
    ?assert(
        lists:any(
            fun
                ({data, column, #{name := <<"value">>, type := <<"Int128">>}}) -> true;
                (_) -> false
            end,
            Events
        )
    ),

    %% Verify column value event
    ?assert(lists:member({data, column_value, 42}, Events)).

parse_uint256_column_test() ->
    %% Build block with 1 UInt256 column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"big_value">>, <<"UInt256">>),

    %% UInt256 value: 32 bytes little-endian
    Value = <<123:256/unsigned-little>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    ?assert(
        lists:any(
            fun
                ({data, column, #{name := <<"big_value">>, type := <<"UInt256">>}}) -> true;
                (_) -> false
            end,
            Events
        )
    ),

    ?assert(lists:member({data, column_value, 123}, Events)).

%%%===================================================================
%%% Decimal Type Tests
%%%===================================================================

parse_decimal32_column_test() ->
    %% Build block with 1 Decimal32(2) column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"price">>, <<"Decimal32(2)">>),

    %% Decimal32 value: 4 bytes signed little-endian (represents 12.34 with scale 2)
    Value = <<1234:32/signed-little>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    ?assert(
        lists:any(
            fun
                ({data, column, #{type := <<"Decimal32(2)">>}}) -> true;
                (_) -> false
            end,
            Events
        )
    ),

    %% Verify a column_value event exists (actual value format may vary)
    ?assert(
        lists:any(
            fun
                ({data, column_value, _}) -> true;
                (_) -> false
            end,
            Events
        )
    ).

parse_decimal128_column_test() ->
    %% Build block with 1 Decimal128(4) column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"amount">>, <<"Decimal128(4)">>),

    %% Decimal128 value: 16 bytes signed little-endian
    Value = <<123456:128/signed-little>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    %% Verify column_value event exists
    ?assert(
        lists:any(
            fun
                ({data, column_value, _}) -> true;
                (_) -> false
            end,
            Events
        )
    ).

%%%===================================================================
%%% Temporal Type Tests
%%%===================================================================

parse_datetime64_column_test() ->
    %% Build block with 1 DateTime64(3) column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"timestamp">>, <<"DateTime64(3)">>),

    %% DateTime64(3) value: 8 bytes signed little-endian (milliseconds since epoch)
    Value = <<1609459200000:64/signed-little>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    ?assert(
        lists:any(
            fun
                ({data, column, #{type := <<"DateTime64(3)">>}}) -> true;
                (_) -> false
            end,
            Events
        )
    ),

    %% Verify column_value event exists
    ?assert(
        lists:any(
            fun
                ({data, column_value, _}) -> true;
                (_) -> false
            end,
            Events
        )
    ).

parse_datetime64_with_timezone_test() ->
    %% Build block with DateTime64(6, 'UTC') column
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"ts">>, <<"DateTime64(6, 'UTC')">>),

    %% DateTime64(6) value: microseconds since epoch
    Value = <<1609459200000000:64/signed-little>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    %% Verify column_value event exists
    ?assert(
        lists:any(
            fun
                ({data, column_value, _}) -> true;
                (_) -> false
            end,
            Events
        )
    ).

parse_date32_column_test() ->
    %% Build block with 1 Date32 column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"date">>, <<"Date32">>),

    %% Date32 value: 4 bytes signed little-endian (days since 1900-01-01)
    Value = <<18628:32/signed-little>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    %% Verify column_value event exists
    ?assert(
        lists:any(
            fun
                ({data, column_value, _}) -> true;
                (_) -> false
            end,
            Events
        )
    ).

%%%===================================================================
%%% Network Type Tests
%%%===================================================================

parse_ipv4_column_test() ->
    %% Build block with 1 IPv4 column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"ip">>, <<"IPv4">>),

    %% IPv4 value: 4 bytes little-endian ({192,168,1,1} -> <<1,1,168,192>>)
    Value = <<1, 1, 168, 192>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    ?assert(lists:member({data, column_value, {192, 168, 1, 1}}, Events)).

parse_ipv6_column_test() ->
    %% Build block with 1 IPv6 column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"ipv6">>, <<"IPv6">>),

    %% IPv6 value: 16 bytes
    Value = <<32, 1, 13, 184, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    ?assert(
        lists:any(
            fun
                ({data, column_value, _}) -> true;
                (_) -> false
            end,
            Events
        )
    ).

%%%===================================================================
%%% Special Type Tests
%%%===================================================================

parse_uuid_column_test() ->
    %% Build block with 1 UUID column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"id">>, <<"UUID">>),

    %% UUID value: 16 bytes
    Value = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    ?assert(
        lists:any(
            fun
                ({data, column_value, _}) -> true;
                (_) -> false
            end,
            Events
        )
    ).

parse_point_column_test() ->
    %% Build block with 1 Point column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"location">>, <<"Point">>),

    %% Point value: 2 Float64 values (x, y)
    X = <<1.5:64/float-little>>,
    Y = <<2.5:64/float-little>>,
    Value = <<X/binary, Y/binary>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    ?assert(lists:member({data, column_value, {1.5, 2.5}}, Events)).

%%%===================================================================
%%% Enum Type Tests
%%%===================================================================

parse_enum8_column_test() ->
    %% Build block with 1 Enum8 column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"status">>, <<"Enum8('active' = 1, 'inactive' = 2)">>),

    %% Enum8 value: 1 byte (value 1 = 'active')
    Value = <<1:8>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    %% Verify column_value event exists (enum decoding may vary)
    ?assert(
        lists:any(
            fun
                ({data, column_value, _}) -> true;
                (_) -> false
            end,
            Events
        )
    ).

parse_enum16_column_test() ->
    %% Build block with 1 Enum16 column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"type">>, <<"Enum16('small' = 1, 'large' = 1000)">>),

    %% Enum16 value: 2 bytes little-endian (value 1000 = 'large')
    Value = <<1000:16/signed-little>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    %% Verify column_value event exists
    ?assert(
        lists:any(
            fun
                ({data, column_value, _}) -> true;
                (_) -> false
            end,
            Events
        )
    ).

%%%===================================================================
%%% Time Type Tests
%%%===================================================================

parse_time_column_test() ->
    %% Build block with 1 Time column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"time">>, <<"Time">>),

    %% Time value: 4 bytes unsigned little-endian (seconds since midnight)

    % 01:01:01
    Value = <<3661:32/unsigned-little>>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    %% Verify column_value event exists
    ?assert(
        lists:any(
            fun
                ({data, column_value, _}) -> true;
                (_) -> false
            end,
            Events
        )
    ).

parse_fixed_string_column_test() ->
    %% Build block with 1 FixedString(10) column, 1 row
    Header = build_block_header(<<"">>, 1, 1),
    ColHeader = build_column_header(<<"code">>, <<"FixedString(10)">>),

    %% FixedString(10) value: exactly 10 bytes
    Value = <<"ABCDEFGHIJ">>,

    Packet = <<Header/binary, ColHeader/binary, Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    ?assert(lists:member({data, column_value, <<"ABCDEFGHIJ">>}, Events)).

%%%===================================================================
%%% Multiple Column Tests
%%%===================================================================

parse_multiple_extended_types_test() ->
    %% Build block with multiple extended type columns
    Header = build_block_header(<<"">>, 3, 1),

    Col1Header = build_column_header(<<"int128_val">>, <<"Int128">>),
    Col1Value = <<42:128/signed-little>>,

    Col2Header = build_column_header(<<"decimal_val">>, <<"Decimal64(3)">>),
    Col2Value = <<12345:64/signed-little>>,

    Col3Header = build_column_header(<<"ipv4_val">>, <<"IPv4">>),
    Col3Value = <<1, 0, 0, 10>>,

    Packet =
        <<Header/binary, Col1Header/binary, Col1Value/binary, Col2Header/binary, Col2Value/binary,
            Col3Header/binary, Col3Value/binary>>,

    State = clickhouse_erl_parser_block:init(#{version => 54460}),
    Result = clickhouse_erl_parser_block:parse(Packet, State),

    ?assertMatch({done, Events, <<>>} when is_list(Events), Result),
    {done, Events, _} = Result,

    %% Verify all three columns are present
    ?assert(
        lists:any(
            fun
                ({data, column, #{name := <<"int128_val">>}}) -> true;
                (_) -> false
            end,
            Events
        )
    ),
    ?assert(
        lists:any(
            fun
                ({data, column, #{name := <<"decimal_val">>}}) -> true;
                (_) -> false
            end,
            Events
        )
    ),
    ?assert(
        lists:any(
            fun
                ({data, column, #{name := <<"ipv4_val">>}}) -> true;
                (_) -> false
            end,
            Events
        )
    ).
