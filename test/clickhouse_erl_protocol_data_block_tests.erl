%% @doc Unit tests for data block decoding with multiple packets
-module(clickhouse_erl_protocol_data_block_tests).

-include_lib("eunit/include/eunit.hrl").
-include("src/clickhouse_erl_protocol.hrl").

-define(TEST_MODULE, clickhouse_erl_protocol_data_block).

decode_empty_block_test() ->
    %% Construct binary for empty block
    %% 1. Temp Table Name (empty string) -> 0 length
    %% 2. Block Info -> 1 (custom), 0 (not overflow), 2 (bucket num custom), BucketNum (-1 or 0), 0
    %% 3. Num Columns -> 0
    %% 4. Num Rows -> 0

    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Block Info: 1, IsOverflow(0), 2, BucketNum(-1), 0
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),

    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(0),
    NumRows = clickhouse_erl_types_primitive:encode_varint(0),

    Binary = <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary>>,

    ?assertMatch(
        {ok,
            #{
                info := #{is_overflows := false, bucket_num := -1},
                columns := 0,
                rows := 0,
                column_data := []
            },
            <<>>},
        ?TEST_MODULE:decode(Binary)
    ).

encode_block_info_test() ->
    %% Field 1: IsOverflows (false)
    %% Field 2: BucketNum (-1) for data blocks
    %% End Marker: 0
    Expected = <<
        % Field 1 (varint)
        1,
        % false (uint8/bool)
        0,
        % Field 2 (varint)
        2,
        % -1 (int32 little endian) - used for data blocks with rows
        255,
        255,
        255,
        255,
        % End marker (varint)
        0
    >>,
    ?assertEqual(Expected, iolist_to_binary(?TEST_MODULE:encode_block_info())).

encode_blank_data_block_test() ->
    %% Structure:
    %% 1. Temp Table Name (empty string) -> 0 length
    %% 2. Block Info -> BucketNum = 0 for blank blocks (not -1)
    %% 3. Num Columns -> 0
    %% 4. Num Rows -> 0

    %% Blank blocks use BucketNum = 0 (not -1 like data blocks)
    BlankBlockInfo = <<
        % Field 1 (varint)
        1,
        % false (uint8/bool)
        0,
        % Field 2 (varint)
        2,
        % 0 (int32 little endian) - blank blocks use 0, not -1
        0,
        0,
        0,
        0,
        % End marker (varint)
        0
    >>,

    Expected = <<
        % Temp Table Name (empty string length)
        0,
        BlankBlockInfo/binary,
        % Num Columns
        0,
        % Num Rows
        0
    >>,

    ?assertEqual(Expected, iolist_to_binary(?TEST_MODULE:encode_blank_data_block())).

encode_data_block_empty_test() ->
    %% Empty data block (0 cols, 0 rows) uses BucketNum = -1
    %% This is different from blank blocks which use BucketNum = 0
    Block = #{
        info => #{is_overflows => false, bucket_num => -1},
        columns => 0,
        rows => 0,
        column_data => []
    },

    {ok, Result} = ?TEST_MODULE:encode_data_block(Block, 54454),

    %% Expected: data block with BucketNum = -1 (not 0 like blank blocks)
    Expected = <<
        % Temp Table Name (empty string)
        0,
        % Block Info with BucketNum = -1
        1,
        0,
        2,
        255,
        255,
        255,
        255,
        0,
        % Num Columns
        0,
        % Num Rows
        0
    >>,

    ?assertEqual(Expected, iolist_to_binary(Result)).

encode_data_block_with_column_test() ->
    %% 1 column, 0 rows
    Block = #{
        info => #{is_overflows => false, bucket_num => -1},
        columns => 1,
        rows => 0,
        column_data => [
            #{name => <<"col1">>, type => <<"UInt8">>, data => []}
        ]
    },

    %% Should return success now
    {ok, Result} = ?TEST_MODULE:encode_data_block(Block, 54454),
    ?assertMatch([_, _], Result),

    Binary = iolist_to_binary(Result),

    %% Verify Header parts
    NameBin = clickhouse_erl_types_primitive:encode_string("col1"),
    TypeBin = clickhouse_erl_types_primitive:encode_string("UInt8"),
    %% CustomSer(0) + Empty Data
    %% We just check that it contains the column info at the end
    ExpectedSuffix = <<NameBin/binary, TypeBin/binary, 0>>,
    ?assertEqual(
        binary:part(
            Binary, byte_size(Binary) - byte_size(ExpectedSuffix), byte_size(ExpectedSuffix)
        ),
        ExpectedSuffix
    ).

encode_data_block_single_column_with_rows_test() ->
    %% Test encoding a single column with multiple rows
    %% This test will pass once column encoders are implemented in Phase 2
    Block = #{
        info => #{is_overflows => false, bucket_num => -1},
        columns => 1,
        rows => 3,
        column_data => [
            #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3]}
        ]
    },

    %% Should return success now
    {ok, Result} = ?TEST_MODULE:encode_data_block(Block, 54454),
    ?assertMatch([_, _], Result),

    Binary = iolist_to_binary(Result),

    %% Verify Data: 1, 2, 3 as UInt32 little endian
    DataExpected = <<1:32/little, 2:32/little, 3:32/little>>,

    %% Verify Suffix: Name, Type, CustomSer, Data
    NameBin = clickhouse_erl_types_primitive:encode_string("id"),
    TypeBin = clickhouse_erl_types_primitive:encode_string("UInt32"),
    ExpectedSuffix = <<NameBin/binary, TypeBin/binary, 0, DataExpected/binary>>,

    ?assertEqual(
        binary:part(
            Binary, byte_size(Binary) - byte_size(ExpectedSuffix), byte_size(ExpectedSuffix)
        ),
        ExpectedSuffix
    ).

encode_type_mismatch_test() ->
    Block = #{
        info => #{is_overflows => false, bucket_num => -1},
        columns => 1,
        rows => 1,
        column_data => [
            %% Too large for UInt8
            #{name => <<"id">>, type => <<"UInt8">>, data => [300]}
        ]
    },
    Result = ?TEST_MODULE:encode_data_block(Block, 54454),
    ?assertMatch(
        {error, {type_mismatch, <<"id">>, <<"UInt8">>, {value_out_of_range, _}}},
        Result
    ).

encode_string_type_mismatch_test() ->
    Block = #{
        info => #{is_overflows => false, bucket_num => -1},
        columns => 1,
        rows => 1,
        column_data => [
            #{name => <<"name">>, type => <<"String">>, data => [#{invalid => map}]}
        ]
    },
    Result = ?TEST_MODULE:encode_data_block(Block, 54454),
    ?assertMatch(
        {error, {type_mismatch, <<"name">>, <<"String">>, {invalid_value, _}}},
        Result
    ).

encode_data_block_multiple_columns_test() ->
    %% Test encoding multiple columns with data
    %% This test will pass once column encoders are implemented in Phase 2
    Block = #{
        info => #{is_overflows => false, bucket_num => -1},
        columns => 2,
        rows => 2,
        column_data => [
            #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2]},
            #{name => <<"name">>, type => <<"String">>, data => [<<"Alice">>, <<"Bob">>]}
        ]
    },

    %% Should return success now
    {ok, Result} = ?TEST_MODULE:encode_data_block(Block, 54454),
    ?assertMatch([_, _], Result),

    Binary = iolist_to_binary(Result),

    %% Verify Header (simplified check for existence)
    Col1Name = clickhouse_erl_types_primitive:encode_string("id"),
    Col1Type = clickhouse_erl_types_primitive:encode_string("UInt32"),
    Col2Name = clickhouse_erl_types_primitive:encode_string("name"),
    Col2Type = clickhouse_erl_types_primitive:encode_string("String"),

    %% Verify Data
    %% Col1: 1, 2 (UInt32)
    Col1Data = <<1:32/little, 2:32/little>>,
    %% Col2: "Alice", "Bob" (String)
    %% Alice: len 5 (varint) + "Alice"
    %% Bob: len 3 (varint) + "Bob"
    AliceBin = clickhouse_erl_types_primitive:encode_string("Alice"),
    BobBin = clickhouse_erl_types_primitive:encode_string("Bob"),
    Col2Data = <<AliceBin/binary, BobBin/binary>>,

    %% Full expected suffix:
    %% Col1 Name, Col1 Type, CustomSer(0), Col1 Data
    %% Col2 Name, Col2 Type, CustomSer(0), Col2 Data
    ExpectedSuffix = <<
        Col1Name/binary,
        Col1Type/binary,
        0,
        Col1Data/binary,
        Col2Name/binary,
        Col2Type/binary,
        0,
        Col2Data/binary
    >>,

    ?assertEqual(
        binary:part(
            Binary, byte_size(Binary) - byte_size(ExpectedSuffix), byte_size(ExpectedSuffix)
        ),
        ExpectedSuffix
    ).

encode_data_block_version_custom_serialization_test() ->
    %% Test version-dependent custom serialization flag
    %% Version >= 54454 should include custom serialization flag
    Block = #{
        info => #{is_overflows => false, bucket_num => -1},
        columns => 1,
        rows => 0,
        column_data => [
            #{name => <<"col1">>, type => <<"UInt8">>, data => []}
        ]
    },

    %% Test with version >= 54454 (should include custom serialization flag)
    {ok, ResultNew} = ?TEST_MODULE:encode_data_block(Block, 54454),
    % Should succeed (list of lists)
    ?assertMatch([_, _], ResultNew),
    BinaryNew = iolist_to_binary(ResultNew),
    %% Check for existence of custom serialization byte (0) before column data
    %% Name(col1) + Type(UInt8) + CustomSer(0) + Data(empty)
    NameBin = clickhouse_erl_types_primitive:encode_string("col1"),
    TypeBin = clickhouse_erl_types_primitive:encode_string("UInt8"),
    ExpectedSuffixNew = <<NameBin/binary, TypeBin/binary, 0>>,
    %% We check if BinaryNew ends with this suffix (since data is empty)
    ?assertEqual(
        binary:part(
            BinaryNew,
            byte_size(BinaryNew) - byte_size(ExpectedSuffixNew),
            byte_size(ExpectedSuffixNew)
        ),
        ExpectedSuffixNew
    ),

    %% Test with version < 54454 (should NOT include custom serialization flag)
    {ok, ResultOld} = ?TEST_MODULE:encode_data_block(Block, 54450),
    ?assertMatch([_, _], ResultOld),
    BinaryOld = iolist_to_binary(ResultOld),
    ExpectedSuffixOld = <<NameBin/binary, TypeBin/binary>>,
    ?assertEqual(
        binary:part(
            BinaryOld,
            byte_size(BinaryOld) - byte_size(ExpectedSuffixOld),
            byte_size(ExpectedSuffixOld)
        ),
        ExpectedSuffixOld
    ).

encode_float_columns_test() ->
    %% Test encoding Float32 and Float64 columns
    Block = #{
        info => #{is_overflows => false, bucket_num => -1},
        columns => 2,
        rows => 3,
        column_data => [
            #{name => <<"val32">>, type => <<"Float32">>, data => [1.0, 0.5, -1.0]},
            #{name => <<"val64">>, type => <<"Float64">>, data => [3.141592653589793, 0.0, -100.0]}
        ]
    },

    {ok, Result} = ?TEST_MODULE:encode_data_block(Block, 54454),
    ?assertMatch([_, _], Result),

    Binary = iolist_to_binary(Result),

    %% Basic check: The binary should be large enough to contain the data
    %% Header ~ 11 bytes
    %% Col1 Name (~6) + Type (~8) + Custom (1) + Data (12) = 27
    %% Col2 Name (~6) + Type (~8) + Custom (1) + Data (24) = 39
    %% Total ~ 77 bytes
    ?assert(byte_size(Binary) > 70),

    %% Verify Float32 data segment
    %% 1.0, 0.5, -1.0
    F32Expected = <<1.0:32/little-float, 0.5:32/little-float, -1.0:32/little-float>>,
    ?assert(binary:match(Binary, F32Expected) /= nomatch),

    %% Verify Float64 data segment (partial match of 0.0)
    %% 3.14159... = 400921fb54442d18 (approx)
    F64Zero = <<0.0:64/little-float>>,
    ?assert(binary:match(Binary, F64Zero) /= nomatch).

encode_temporal_columns_test() ->
    %% Test encoding Date, Date32, DateTime, DateTime64
    Block = #{
        info => #{is_overflows => false, bucket_num => -1},
        columns => 4,
        rows => 1,
        column_data => [
            #{name => <<"d">>, type => <<"Date">>, data => [{2023, 1, 1}]},
            #{name => <<"d32">>, type => <<"Date32">>, data => [{2023, 1, 1}]},
            #{name => <<"dt">>, type => <<"DateTime">>, data => [{{2023, 1, 1}, {12, 0, 0}}]},
            #{name => <<"dt64">>, type => <<"DateTime64(3)">>, data => [1672574400000]}
        ]
    },

    {ok, Result} = ?TEST_MODULE:encode_data_block(Block, 54454),
    ?assertMatch([_, _], Result),
    Binary = iolist_to_binary(Result),

    %% 2023-01-01 is 19358 days since epoch
    %% Date (UInt16): 19358 = 0x4B9E
    DateExp = <<19358:16/little-unsigned>>,
    ?assert(binary:match(Binary, DateExp) /= nomatch),

    %% Date32 (Int32): 19358
    Date32Exp = <<19358:32/little-signed>>,
    ?assert(binary:match(Binary, Date32Exp) /= nomatch),

    %% 2023-01-01 12:00:00 UTC = 1672574400 seconds
    %% DateTime (UInt32)
    DTExp = <<1672574400:32/little-unsigned>>,
    ?assert(binary:match(Binary, DTExp) /= nomatch),

    %% DateTime64 (Int64)
    %% Value passed directly: 1672574400000
    DT64Exp = <<1672574400000:64/little-signed>>,
    ?assert(binary:match(Binary, DT64Exp) /= nomatch).

encode_data_block_zero_rows_test() ->
    %% Test encoding with zero rows (empty data)
    Block = #{
        info => #{is_overflows => false, bucket_num => -1},
        columns => 2,
        rows => 0,
        column_data => [
            #{name => <<"col1">>, type => <<"UInt32">>, data => []},
            #{name => <<"col2">>, type => <<"String">>, data => []}
        ]
    },

    %% Should return success now
    {ok, Result} = ?TEST_MODULE:encode_data_block(Block, 54454),
    ?assertMatch([_, _], Result),

    Binary = iolist_to_binary(Result),

    %% Verify Suffix for empty data
    Col1Name = clickhouse_erl_types_primitive:encode_string("col1"),
    Col1Type = clickhouse_erl_types_primitive:encode_string("UInt32"),
    Col2Name = clickhouse_erl_types_primitive:encode_string("col2"),
    Col2Type = clickhouse_erl_types_primitive:encode_string("String"),

    ExpectedSuffix = <<
        Col1Name/binary,
        Col1Type/binary,
        0,
        Col2Name/binary,
        Col2Type/binary,
        0
    >>,
    ?assertEqual(
        binary:part(
            Binary, byte_size(Binary) - byte_size(ExpectedSuffix), byte_size(ExpectedSuffix)
        ),
        ExpectedSuffix
    ).

decode_block_with_columns_no_rows_test() ->
    %% 1 column, 0 rows
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(1),
    NumRows = clickhouse_erl_types_primitive:encode_varint(0),

    %% Column 1: Name "id", Type "UInt64"
    ColName = clickhouse_erl_types_primitive:encode_string("id"),
    ColType = clickhouse_erl_types_primitive:encode_string("UInt64"),

    Binary =
        <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary, ColName/binary,
            ColType/binary>>,

    {ok, Result, Rest} = ?TEST_MODULE:decode(Binary),
    ?assertEqual(<<>>, Rest),
    ?assertEqual(1, maps:get(columns, Result)),
    ?assertEqual(0, maps:get(rows, Result)),

    [ColData] = maps:get(column_data, Result),
    ?assertEqual(<<"id">>, maps:get(name, ColData)),
    ?assertEqual(<<"UInt64">>, maps:get(type, ColData)),
    ?assertEqual([], maps:get(data, ColData)).

% The previous error assertion was correct when not implemented.
% Now it is implemented, but this test sends 1 row with Types that might be mocked or simple.
% The test called "decode_block_not_implemented_rows_test" should be replaced or updated if we support it now.
% Since we support UInt64, we can actually test success now, or rename this test.
% Let's REPLACE this test with actual data decoding tests as per plan.

decode_block_with_data_test() ->
    %% 1 column, 1 row
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(1),
    NumRows = clickhouse_erl_types_primitive:encode_varint(1),

    %% Column 1: Name "id", Type "UInt64", Value 42
    ColName = clickhouse_erl_types_primitive:encode_string("id"),
    ColType = clickhouse_erl_types_primitive:encode_string("UInt64"),
    ColValue = <<42:64/little-integer>>,

    Binary =
        <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary, ColName/binary,
            ColType/binary, ColValue/binary>>,

    {ok, Result, Rest} = ?TEST_MODULE:decode(Binary),
    ?assertEqual(<<>>, Rest),
    ?assertEqual(1, maps:get(columns, Result)),
    ?assertEqual(1, maps:get(rows, Result)),

    [ColData] = maps:get(column_data, Result),
    ?assertEqual(<<"id">>, maps:get(name, ColData)),
    ?assertEqual(<<"UInt64">>, maps:get(type, ColData)),
    ?assertEqual([42], maps:get(data, ColData)).

decode_multiple_rows_mixed_types_test() ->
    %% 2 columns, 2 rows
    %% Col 1: "id" (UInt64) -> 1, 2
    %% Col 2: "name" (String) -> "Alice", "Bob"

    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(2),
    NumRows = clickhouse_erl_types_primitive:encode_varint(2),

    %% Col 1 Metadata
    Col1Name = clickhouse_erl_types_primitive:encode_string("id"),
    Col1Type = clickhouse_erl_types_primitive:encode_string("UInt64"),

    %% Col 1 Data (2 rows)
    Col1Data = <<1:64/little-integer, 2:64/little-integer>>,

    %% Col 2 Metadata
    Col2Name = clickhouse_erl_types_primitive:encode_string("name"),
    Col2Type = clickhouse_erl_types_primitive:encode_string("String"),

    %% Col 2 Data (2 rows)
    Col2DataRow1 = clickhouse_erl_types_primitive:encode_string("Alice"),
    Col2DataRow2 = clickhouse_erl_types_primitive:encode_string("Bob"),
    Col2Data = <<Col2DataRow1/binary, Col2DataRow2/binary>>,

    %% Construct full binary. The format is:
    %% ... ColsMeta+Data ...
    %% Actually: ClickHouse block format sends columns sequentially.
    %% Col 1 Name, Col 1 Type, Col 1 Data (all rows)
    %% Col 2 Name, Col 2 Type, Col 2 Data (all rows)

    Binary =
        <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary,
            Col1Name/binary, Col1Type/binary, Col1Data/binary, Col2Name/binary, Col2Type/binary,
            Col2Data/binary>>,

    {ok, Result, Rest} = ?TEST_MODULE:decode(Binary),
    ?assertEqual(<<>>, Rest),
    ?assertEqual(2, maps:get(columns, Result)),
    ?assertEqual(2, maps:get(rows, Result)),

    [Col1, Col2] = maps:get(column_data, Result),

    ?assertEqual(<<"id">>, maps:get(name, Col1)),
    ?assertEqual(<<"UInt64">>, maps:get(type, Col1)),
    ?assertEqual([1, 2], maps:get(data, Col1)),

    ?assertEqual(<<"name">>, maps:get(name, Col2)),
    ?assertEqual(<<"String">>, maps:get(type, Col2)),
    ?assertEqual([<<"Alice">>, <<"Bob">>], maps:get(data, Col2)).

decode_int32_column_test() ->
    %% Test Int32 column type
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(1),
    NumRows = clickhouse_erl_types_primitive:encode_varint(2),

    %% Column: Name "count", Type "Int32", Values -42, 100
    ColName = clickhouse_erl_types_primitive:encode_string("count"),
    ColType = clickhouse_erl_types_primitive:encode_string("Int32"),
    ColValue = <<-42:32/signed-little-integer, 100:32/signed-little-integer>>,

    Binary =
        <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary, ColName/binary,
            ColType/binary, ColValue/binary>>,

    {ok, Result, Rest} = ?TEST_MODULE:decode(Binary),
    ?assertEqual(<<>>, Rest),
    ?assertEqual(1, maps:get(columns, Result)),
    ?assertEqual(2, maps:get(rows, Result)),

    [ColData] = maps:get(column_data, Result),
    ?assertEqual(<<"count">>, maps:get(name, ColData)),
    ?assertEqual(<<"Int32">>, maps:get(type, ColData)),
    ?assertEqual([-42, 100], maps:get(data, ColData)).

decode_unknown_column_type_test() ->
    %% Test handling of unknown column type
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(1),
    NumRows = clickhouse_erl_types_primitive:encode_varint(1),

    %% Column: Name "data", Type "UnknownType"
    ColName = clickhouse_erl_types_primitive:encode_string("data"),
    ColType = clickhouse_erl_types_primitive:encode_string("UnknownType"),

    Binary =
        <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary, ColName/binary,
            ColType/binary>>,

    Result = ?TEST_MODULE:decode(Binary),
    ?assertMatch({error, {unknown_column_type, <<"UnknownType">>}}, Result).

decode_truncated_column_data_test() ->
    %% Test handling of truncated column data
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(1),
    NumRows = clickhouse_erl_types_primitive:encode_varint(2),

    %% Column: Name "id", Type "UInt64", but only provide 1 value instead of 2
    ColName = clickhouse_erl_types_primitive:encode_string("id"),
    ColType = clickhouse_erl_types_primitive:encode_string("UInt64"),
    % Only 1 value, but NumRows is 2
    ColValue = <<42:64/little-integer>>,

    Binary =
        <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary, ColName/binary,
            ColType/binary, ColValue/binary>>,

    Result = ?TEST_MODULE:decode(Binary),
    ?assertMatch({error, truncated_data}, Result).

%% Additional unit tests for task 3.4 - column data decoding

decode_string_column_empty_strings_test() ->
    %% Test String column with empty strings
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(1),
    NumRows = clickhouse_erl_types_primitive:encode_varint(2),

    %% Column: Name "text", Type "String", Values "", "test"
    ColName = clickhouse_erl_types_primitive:encode_string("text"),
    ColType = clickhouse_erl_types_primitive:encode_string("String"),
    EmptyString = clickhouse_erl_types_primitive:encode_string(""),
    TestString = clickhouse_erl_types_primitive:encode_string("test"),
    ColValue = <<EmptyString/binary, TestString/binary>>,

    Binary =
        <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary, ColName/binary,
            ColType/binary, ColValue/binary>>,

    {ok, Result, Rest} = ?TEST_MODULE:decode(Binary),
    ?assertEqual(<<>>, Rest),
    ?assertEqual(1, maps:get(columns, Result)),
    ?assertEqual(2, maps:get(rows, Result)),

    [ColData] = maps:get(column_data, Result),
    ?assertEqual(<<"text">>, maps:get(name, ColData)),
    ?assertEqual(<<"String">>, maps:get(type, ColData)),
    ?assertEqual([<<"">>, <<"test">>], maps:get(data, ColData)).

decode_uint64_boundary_values_test() ->
    %% Test UInt64 column with boundary values (0, max value)
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(1),
    NumRows = clickhouse_erl_types_primitive:encode_varint(2),

    %% Column: Name "big_nums", Type "UInt64", Values 0, 18446744073709551615 (max uint64)
    ColName = clickhouse_erl_types_primitive:encode_string("big_nums"),
    ColType = clickhouse_erl_types_primitive:encode_string("UInt64"),
    MaxUInt64 = 18446744073709551615,
    ColValue = <<0:64/little-unsigned-integer, MaxUInt64:64/little-unsigned-integer>>,

    Binary =
        <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary, ColName/binary,
            ColType/binary, ColValue/binary>>,

    {ok, Result, Rest} = ?TEST_MODULE:decode(Binary),
    ?assertEqual(<<>>, Rest),
    ?assertEqual(1, maps:get(columns, Result)),
    ?assertEqual(2, maps:get(rows, Result)),

    [ColData] = maps:get(column_data, Result),
    ?assertEqual(<<"big_nums">>, maps:get(name, ColData)),
    ?assertEqual(<<"UInt64">>, maps:get(type, ColData)),
    ?assertEqual([0, MaxUInt64], maps:get(data, ColData)).

decode_int32_boundary_values_test() ->
    %% Test Int32 column with boundary values (min, max)
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(1),
    NumRows = clickhouse_erl_types_primitive:encode_varint(2),

    %% Column: Name "extremes", Type "Int32", Values -2147483648 (min), 2147483647 (max)
    ColName = clickhouse_erl_types_primitive:encode_string("extremes"),
    ColType = clickhouse_erl_types_primitive:encode_string("Int32"),
    MinInt32 = -2147483648,
    MaxInt32 = 2147483647,
    ColValue = <<MinInt32:32/signed-little-integer, MaxInt32:32/signed-little-integer>>,

    Binary =
        <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary, ColName/binary,
            ColType/binary, ColValue/binary>>,

    {ok, Result, Rest} = ?TEST_MODULE:decode(Binary),
    ?assertEqual(<<>>, Rest),
    ?assertEqual(1, maps:get(columns, Result)),
    ?assertEqual(2, maps:get(rows, Result)),

    [ColData] = maps:get(column_data, Result),
    ?assertEqual(<<"extremes">>, maps:get(name, ColData)),
    ?assertEqual(<<"Int32">>, maps:get(type, ColData)),
    ?assertEqual([MinInt32, MaxInt32], maps:get(data, ColData)).

decode_malformed_temp_table_name_test() ->
    %% Test malformed temp table name (truncated varint)

    % Incomplete varint (continuation bit set but no more bytes)
    Binary = <<255>>,

    Result = ?TEST_MODULE:decode(Binary),
    ?assertMatch({error, {decoding_failed, {temp_table_name, {truncated_data, _}}}}, Result).

decode_malformed_block_info_test() ->
    %% Test malformed block info
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Incomplete block info - truncated after first varint and overflow byte
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    % Missing rest of block info
    Binary = <<TempTableName/binary, Info1/binary, IsOverflow/binary>>,

    Result = ?TEST_MODULE:decode(Binary),
    ?assertMatch({error, {decoding_failed, {block_info, {truncated_data, _}}}}, Result).

decode_malformed_column_count_test() ->
    %% Test malformed column count
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Valid Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    %% Incomplete column count

    % Incomplete varint
    Binary = <<TempTableName/binary, BlockInfoBin/binary, 255>>,

    Result = ?TEST_MODULE:decode(Binary),
    ?assertMatch({error, {decoding_failed, {columns_count, {truncated_data, _}}}}, Result).

decode_malformed_row_count_test() ->
    %% Test malformed row count
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Valid Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(1),

    %% Incomplete row count

    % Incomplete varint
    Binary = <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, 255>>,

    Result = ?TEST_MODULE:decode(Binary),
    ?assertMatch({error, {decoding_failed, {rows_count, {truncated_data, _}}}}, Result).

decode_malformed_column_name_test() ->
    %% Test malformed column name
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Valid Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(1),
    NumRows = clickhouse_erl_types_primitive:encode_varint(1),

    %% Incomplete column name

    % Incomplete varint for string length
    Binary = <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary, 255>>,

    Result = ?TEST_MODULE:decode(Binary),
    ?assertMatch({error, {truncated_data, _}}, Result).

decode_malformed_column_type_test() ->
    %% Test malformed column type
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Valid Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(1),
    NumRows = clickhouse_erl_types_primitive:encode_varint(1),

    %% Valid column name but incomplete column type
    ColName = clickhouse_erl_types_primitive:encode_string("test"),
    % Incomplete varint for string length
    Binary =
        <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary, ColName/binary,
            255>>,

    Result = ?TEST_MODULE:decode(Binary),
    ?assertMatch({error, {truncated_data, _}}, Result).

decode_truncated_string_column_data_test() ->
    %% Test truncated string column data
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Block Info
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    NumCols = clickhouse_erl_types_primitive:encode_varint(1),
    NumRows = clickhouse_erl_types_primitive:encode_varint(2),

    %% Column: Name "text", Type "String", but provide incomplete string data
    ColName = clickhouse_erl_types_primitive:encode_string("text"),
    ColType = clickhouse_erl_types_primitive:encode_string("String"),
    % First string is complete, second string is incomplete (varint says 5 bytes but only 3 provided)
    FirstString = clickhouse_erl_types_primitive:encode_string("hello"),
    % Says 5 bytes but only provides 3
    IncompleteString = <<5, "hel">>,
    ColValue = <<FirstString/binary, IncompleteString/binary>>,

    Binary =
        <<TempTableName/binary, BlockInfoBin/binary, NumCols/binary, NumRows/binary, ColName/binary,
            ColType/binary, ColValue/binary>>,

    Result = ?TEST_MODULE:decode(Binary),
    ?assertMatch({error, {truncated_data, _}}, Result).

decode_invalid_block_info_field_test() ->
    %% Test invalid block info field values
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Invalid block info - wrong first field (should be 1)

    % Wrong value
    Info1 = clickhouse_erl_types_primitive:encode_varint(99),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    Binary = <<TempTableName/binary, BlockInfoBin/binary>>,

    Result = ?TEST_MODULE:decode(Binary),
    ?assertMatch(
        {error, {decoding_failed, {block_info, {unknown_block_info_field, 99}}}}, Result
    ).

decode_invalid_block_info_second_field_test() ->
    %% Test invalid block info second field
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Invalid block info - wrong second field (should be 2)
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    % Wrong value
    Info2 = clickhouse_erl_types_primitive:encode_varint(99),
    BucketNum = <<-1:32/signed-little-integer>>,
    Info0 = clickhouse_erl_types_primitive:encode_varint(0),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    Binary = <<TempTableName/binary, BlockInfoBin/binary>>,

    Result = ?TEST_MODULE:decode(Binary),
    ?assertMatch(
        {error, {decoding_failed, {block_info, {unknown_block_info_field, 99}}}}, Result
    ).

decode_invalid_block_info_terminator_test() ->
    %% Test invalid block info terminator
    TempTableName = clickhouse_erl_types_primitive:encode_string(""),

    %% Invalid block info - wrong terminator (should be 0)
    Info1 = clickhouse_erl_types_primitive:encode_varint(1),
    IsOverflow = <<0>>,
    Info2 = clickhouse_erl_types_primitive:encode_varint(2),
    BucketNum = <<-1:32/signed-little-integer>>,
    % Wrong value
    Info0 = clickhouse_erl_types_primitive:encode_varint(99),
    BlockInfoBin =
        <<Info1/binary, IsOverflow/binary, Info2/binary, BucketNum/binary, Info0/binary>>,

    Binary = <<TempTableName/binary, BlockInfoBin/binary>>,

    Result = ?TEST_MODULE:decode(Binary),
    ?assertMatch(
        {error, {decoding_failed, {block_info, {unknown_block_info_field, 99}}}}, Result
    ).

%% Unit tests for row count validation (Task 9)

validate_row_counts_empty_test() ->
    %% Empty column list should return ok
    ?assertEqual(ok, ?TEST_MODULE:validate_row_counts([])).

validate_row_counts_single_column_test() ->
    %% Single column should always be valid
    Columns = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],
    ?assertEqual(ok, ?TEST_MODULE:validate_row_counts(Columns)).

validate_row_counts_matching_test() ->
    %% Multiple columns with matching row counts should return ok
    Columns = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"col2">>, type => <<"String">>, data => [<<"a">>, <<"b">>, <<"c">>]}
    ],
    ?assertEqual(ok, ?TEST_MODULE:validate_row_counts(Columns)).

validate_row_counts_all_empty_test() ->
    %% Multiple columns with zero rows should return ok
    Columns = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => []},
        #{name => <<"col2">>, type => <<"String">>, data => []}
    ],
    ?assertEqual(ok, ?TEST_MODULE:validate_row_counts(Columns)).

validate_row_counts_mismatch_test() ->
    %% Columns with mismatched row counts should return error
    Columns = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"col2">>, type => <<"String">>, data => [<<"a">>, <<"b">>]}
    ],
    Result = ?TEST_MODULE:validate_row_counts(Columns),
    ?assertMatch({error, {row_count_mismatch, _}}, Result),
    {error, {row_count_mismatch, RowCounts}} = Result,
    ?assertEqual([{<<"col1">>, 3}, {<<"col2">>, 2}], RowCounts).

validate_row_counts_multiple_mismatch_test() ->
    %% Multiple columns with different row counts
    Columns = [
        #{name => <<"id">>, type => <<"UInt32">>, data => [1, 2, 3, 4]},
        #{name => <<"name">>, type => <<"String">>, data => [<<"a">>, <<"b">>]},
        #{name => <<"value">>, type => <<"Float64">>, data => [1.0]}
    ],
    Result = ?TEST_MODULE:validate_row_counts(Columns),
    ?assertMatch({error, {row_count_mismatch, _}}, Result),
    {error, {row_count_mismatch, RowCounts}} = Result,
    ?assertEqual([{<<"id">>, 4}, {<<"name">>, 2}, {<<"value">>, 1}], RowCounts).

validate_row_counts_one_empty_test() ->
    %% One column empty, others with data - should return error
    Columns = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2]},
        #{name => <<"col2">>, type => <<"String">>, data => []}
    ],
    Result = ?TEST_MODULE:validate_row_counts(Columns),
    ?assertMatch({error, {row_count_mismatch, _}}, Result),
    {error, {row_count_mismatch, RowCounts}} = Result,
    ?assertEqual([{<<"col1">>, 2}, {<<"col2">>, 0}], RowCounts).

%% Unit tests for column name validation (Task 10)

validate_column_names_empty_test() ->
    %% Empty column list should return ok
    ?assertEqual(ok, ?TEST_MODULE:validate_column_names([])).

validate_column_names_single_binary_test() ->
    %% Single column with binary name should return ok
    Columns = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]}
    ],
    ?assertEqual(ok, ?TEST_MODULE:validate_column_names(Columns)).

validate_column_names_multiple_binary_test() ->
    %% Multiple columns with all binary names should return ok
    Columns = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => <<"col2">>, type => <<"String">>, data => [<<"a">>, <<"b">>, <<"c">>]},
        #{name => <<"id">>, type => <<"UInt64">>, data => [100, 200]}
    ],
    ?assertEqual(ok, ?TEST_MODULE:validate_column_names(Columns)).

validate_column_names_atom_name_test() ->
    %% Column with atom name should return error
    Columns = [
        #{name => column1, type => <<"UInt32">>, data => [1, 2, 3]}
    ],
    Result = ?TEST_MODULE:validate_column_names(Columns),
    ?assertEqual({error, {invalid_column_name, column1}}, Result).

validate_column_names_string_name_test() ->
    %% Column with string (list) name should return error
    Columns = [
        #{name => "column1", type => <<"UInt32">>, data => [1, 2, 3]}
    ],
    Result = ?TEST_MODULE:validate_column_names(Columns),
    ?assertEqual({error, {invalid_column_name, "column1"}}, Result).

validate_column_names_integer_name_test() ->
    %% Column with integer name should return error
    Columns = [
        #{name => 123, type => <<"UInt32">>, data => [1, 2, 3]}
    ],
    Result = ?TEST_MODULE:validate_column_names(Columns),
    ?assertEqual({error, {invalid_column_name, 123}}, Result).

validate_column_names_mixed_valid_invalid_test() ->
    %% Multiple columns where one has non-binary name should return error
    Columns = [
        #{name => <<"col1">>, type => <<"UInt32">>, data => [1, 2, 3]},
        #{name => invalid_name, type => <<"String">>, data => [<<"a">>, <<"b">>]},
        #{name => <<"col3">>, type => <<"Float64">>, data => [1.0, 2.0]}
    ],
    Result = ?TEST_MODULE:validate_column_names(Columns),
    ?assertEqual({error, {invalid_column_name, invalid_name}}, Result).

validate_column_names_first_invalid_test() ->
    %% First column has invalid name - should return error immediately
    Columns = [
        #{name => bad_name, type => <<"UInt32">>, data => [1, 2]},
        #{name => <<"col2">>, type => <<"String">>, data => [<<"a">>, <<"b">>]}
    ],
    Result = ?TEST_MODULE:validate_column_names(Columns),
    ?assertEqual({error, {invalid_column_name, bad_name}}, Result).

%% Test that data block decode returns correct Rest bytes when followed by other packets
data_block_with_following_packets_test() ->
    %% This is actual data from a failing concurrent query test
    %% The binary contains: [SERVER_DATA type byte][DATA block][PROFILE_EVENTS][END_OF_STREAM]
    FullData =
        <<1, 0, 1, 0, 2, 255, 255, 255, 255, 0, 1, 1, 2, 50, 48, 5, 85, 73, 110, 116, 56, 0, 20, 6,
            1, 1, 136, 32, 0, 0, 1, 3, 1, 1, 1, 0, 0, 214, 161, 160, 1, 14, 0, 1, 0, 2, 255, 255,
            255, 255, 0, 6, 33, 9, 104, 111, 115, 116, 95, 110, 97, 109, 101, 6, 83, 116, 114, 105,
            110, 103, 0, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50,
            99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97,
            12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51,
            101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57,
            52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50,
            57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50,
            51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53,
            57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97,
            50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99,
            50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12,
            53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101,
            97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50,
            99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97,
            12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51,
            101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57,
            52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50,
            57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50,
            51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53,
            57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97,
            50, 57, 97, 12, 53, 57, 52, 50, 99, 50, 51, 101, 97, 50, 57, 97, 12, 99, 117, 114, 114,
            101, 110, 116, 95, 116, 105, 109, 101, 8, 68, 97, 116, 101, 84, 105, 109, 101, 0, 252,
            112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112,
            152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152,
            105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105,
            252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 252,
            112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112,
            152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152,
            105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105,
            252, 112, 152, 105, 252, 112, 152, 105, 252, 112, 152, 105, 9, 116, 104, 114, 101, 97,
            100, 95, 105, 100, 6, 85, 73, 110, 116, 54, 52, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 116, 121, 112,
            101, 35, 69, 110, 117, 109, 56, 40, 39, 105, 110, 99, 114, 101, 109, 101, 110, 116, 39,
            32, 61, 32, 49, 44, 32, 39, 103, 97, 117, 103, 101, 39, 32, 61, 32, 50, 41, 0, 1, 1, 1,
            1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2,
            2, 4, 110, 97, 109, 101, 6, 83, 116, 114, 105, 110, 103, 0, 5, 81, 117, 101, 114, 121,
            11, 83, 101, 108, 101, 99, 116, 81, 117, 101, 114, 121, 12, 73, 110, 105, 116, 105, 97,
            108, 81, 117, 101, 114, 121, 18, 73, 110, 105, 116, 105, 97, 108, 83, 101, 108, 101, 99,
            116, 81, 117, 101, 114, 121, 21, 81, 117, 101, 114, 105, 101, 115, 87, 105, 116, 104,
            83, 117, 98, 113, 117, 101, 114, 105, 101, 115, 27, 83, 101, 108, 101, 99, 116, 81, 117,
            101, 114, 105, 101, 115, 87, 105, 116, 104, 83, 117, 98, 113, 117, 101, 114, 105, 101,
            115, 33, 78, 101, 116, 119, 111, 114, 107, 82, 101, 99, 101, 105, 118, 101, 69, 108, 97,
            112, 115, 101, 100, 77, 105, 99, 114, 111, 115, 101, 99, 111, 110, 100, 115, 30, 78,
            101, 116, 119, 111, 114, 107, 83, 101, 110, 100, 69, 108, 97, 112, 115, 101, 100, 77,
            105, 99, 114, 111, 115, 101, 99, 111, 110, 100, 115, 19, 78, 101, 116, 119, 111, 114,
            107, 82, 101, 99, 101, 105, 118, 101, 66, 121, 116, 101, 115, 16, 78, 101, 116, 119,
            111, 114, 107, 83, 101, 110, 100, 66, 121, 116, 101, 115, 20, 71, 108, 111, 98, 97, 108,
            84, 104, 114, 101, 97, 100, 80, 111, 111, 108, 74, 111, 98, 115, 29, 81, 117, 101, 114,
            121, 80, 108, 97, 110, 79, 112, 116, 105, 109, 105, 122, 101, 77, 105, 99, 114, 111,
            115, 101, 99, 111, 110, 100, 115, 12, 83, 101, 108, 101, 99, 116, 101, 100, 82, 111,
            119, 115, 13, 83, 101, 108, 101, 99, 116, 101, 100, 66, 121, 116, 101, 115, 11, 67, 111,
            110, 116, 101, 120, 116, 76, 111, 99, 107, 23, 82, 87, 76, 111, 99, 107, 65, 99, 113,
            117, 105, 114, 101, 100, 82, 101, 97, 100, 76, 111, 99, 107, 115, 20, 82, 101, 97, 108,
            84, 105, 109, 101, 77, 105, 99, 114, 111, 115, 101, 99, 111, 110, 100, 115, 20, 85, 115,
            101, 114, 84, 105, 109, 101, 77, 105, 99, 114, 111, 115, 101, 99, 111, 110, 100, 115,
            22, 83, 121, 115, 116, 101, 109, 84, 105, 109, 101, 77, 105, 99, 114, 111, 115, 101, 99,
            111, 110, 100, 115, 28, 79, 83, 67, 80, 85, 86, 105, 114, 116, 117, 97, 108, 84, 105,
            109, 101, 77, 105, 99, 114, 111, 115, 101, 99, 111, 110, 100, 115, 11, 79, 83, 82, 101,
            97, 100, 67, 104, 97, 114, 115, 12, 79, 83, 87, 114, 105, 116, 101, 67, 104, 97, 114,
            115, 8, 76, 111, 103, 84, 114, 97, 99, 101, 8, 76, 111, 103, 68, 101, 98, 117, 103, 24,
            76, 111, 103, 103, 101, 114, 69, 108, 97, 112, 115, 101, 100, 78, 97, 110, 111, 115,
            101, 99, 111, 110, 100, 115, 24, 73, 110, 116, 101, 114, 102, 97, 99, 101, 78, 97, 116,
            105, 118, 101, 83, 101, 110, 100, 66, 121, 116, 101, 115, 27, 73, 110, 116, 101, 114,
            102, 97, 99, 101, 78, 97, 116, 105, 118, 101, 82, 101, 99, 101, 105, 118, 101, 66, 121,
            116, 101, 115, 30, 67, 111, 110, 99, 117, 114, 114, 101, 110, 99, 121, 67, 111, 110,
            116, 114, 111, 108, 83, 108, 111, 116, 115, 71, 114, 97, 110, 116, 101, 100, 43, 67,
            111, 110, 99, 117, 114, 114, 101, 110, 99, 121, 67, 111, 110, 116, 114, 111, 108, 83,
            108, 111, 116, 115, 65, 99, 113, 117, 105, 114, 101, 100, 78, 111, 110, 67, 111, 109,
            112, 101, 116, 105, 110, 103, 32, 65, 115, 121, 110, 99, 76, 111, 103, 103, 105, 110,
            103, 70, 105, 108, 101, 76, 111, 103, 84, 111, 116, 97, 108, 77, 101, 115, 115, 97, 103,
            101, 115, 32, 65, 115, 121, 110, 99, 76, 111, 103, 103, 105, 110, 103, 84, 101, 120,
            116, 76, 111, 103, 84, 111, 116, 97, 108, 77, 101, 115, 115, 97, 103, 101, 115, 18, 77,
            101, 109, 111, 114, 121, 84, 114, 97, 99, 107, 101, 114, 85, 115, 97, 103, 101, 22, 77,
            101, 109, 111, 114, 121, 84, 114, 97, 99, 107, 101, 114, 80, 101, 97, 107, 85, 115, 97,
            103, 101, 5, 118, 97, 108, 117, 101, 5, 73, 110, 116, 54, 52, 0, 1, 0, 0, 0, 0, 0, 0, 0,
            1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
            0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 20, 3, 0, 0, 0, 0, 0, 0, 74, 0, 0, 0, 0, 0, 0, 0, 12,
            0, 0, 0, 0, 0, 0, 0, 63, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 31, 0, 0, 0, 0, 0,
            0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 14, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0,
            0, 0, 0, 0, 0, 86, 0, 0, 0, 0, 0, 0, 0, 45, 0, 0, 0, 0, 0, 0, 0, 45, 0, 0, 0, 0, 0, 0,
            0, 89, 0, 0, 0, 0, 0, 0, 0, 164, 1, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0,
            0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 151, 86, 0, 0, 0, 0, 0, 0, 63, 0, 0, 0, 0, 0, 0,
            0, 12, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0,
            0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 56, 81, 1, 0, 0, 0, 0, 0, 120, 81, 1, 0, 0, 0, 0, 0,
            1, 0, 1, 0, 2, 255, 255, 255, 255, 0, 0, 0, 3, 0, 0, 0, 0, 0, 238, 240, 6, 5>>,

    %% Skip the SERVER_DATA packet type byte (first byte = 1)
    <<1:8, Data/binary>> = FullData,

    %% Decode the data block
    ProtocolVersion = 54460,
    {ok, _DataBlock, Rest} = clickhouse_erl_protocol_data_block:decode(Data, ProtocolVersion),

    %% The Rest should contain more packets after DATA block
    %% Check that Rest is not empty
    ?assert(byte_size(Rest) > 0),

    %% Check that the last byte of FullData is 5 (SERVER_END_OF_STREAM)
    FullDataSize = byte_size(FullData),
    <<_:(FullDataSize - 1)/binary, LastByte:8>> = FullData,
    ?assertEqual(5, LastByte),

    %% The Rest should start with the next packet type (SERVER_PROFILE = 6)
    <<FirstByte:8, _/binary>> = Rest,
    ?assertEqual(6, FirstByte).
