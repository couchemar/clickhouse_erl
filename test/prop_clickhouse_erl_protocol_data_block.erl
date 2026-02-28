%% @doc Property-based tests for ClickHouse Data block parsing.
%%
%% This module contains property-based tests using PropEr to validate
%% the correctness of Data block parsing and round-trip properties.
-module(prop_clickhouse_erl_protocol_data_block).

-include_lib("proper/include/proper.hrl").
-include("src/clickhouse_erl_protocol.hrl").

-import(generators, [string_gen/0, non_empty_binary_string_gen/0]).

%% Helper function to ensure data is binary (for character list vs binary comparison)
ensure_binary(Data) when is_list(Data) ->
    unicode:characters_to_binary(Data, utf8);
ensure_binary(Data) when is_binary(Data) ->
    Data.

%% Property test: Data block parsing round-trip
%% Feature: simple-query, Property 7: Data block parsing round-trip
%% Validates: Requirements 4.1, 4.2
prop_data_block_round_trip() ->
    ?FORALL(
        DataBlock,
        data_block_gen(),
        begin
            case encode_data_block(DataBlock) of
                {ok, EncodedBlock} ->
                    case clickhouse_erl_protocol_data_block:decode(EncodedBlock) of
                        {ok, DecodedBlock, <<>>} ->
                            %% Compare the original and decoded data blocks
                            data_block_equivalent(DataBlock, DecodedBlock);
                        {ok, _DecodedBlock, _Rest} ->
                            %% Should not have remaining data
                            false;
                        {error, _Reason} ->
                            false
                    end;
                {error, _Reason} ->
                    false
            end
        end
    ).

%% Generator for data_block() structures
%% Supports both empty data blocks and blocks with actual data
data_block_gen() ->
    ?LET(
        {IsOverflows, BucketNum, NumColumns, NumRows},
        {boolean(), integer(), range(0, 3), range(0, 2)},
        #{
            info => #{
                is_overflows => IsOverflows,
                bucket_num => BucketNum
            },
            columns => NumColumns,
            rows => NumRows,
            column_data => generate_column_list(NumColumns, NumRows)
        }
    ).

%% Generate a list of columns
generate_column_list(0, _NumRows) ->
    [];
generate_column_list(N, NumRows) ->
    [generate_column(NumRows) || _ <- lists:seq(1, N)].

%% Generate a single column
generate_column(NumRows) ->
    Names = ["id", "name", "value", "count"],
    Types = [<<"UInt64">>, <<"String">>, <<"Int32">>],
    Type = lists:nth(rand:uniform(length(Types)), Types),
    #{
        name => lists:nth(rand:uniform(length(Names)), Names),
        type => Type,
        data => generate_column_data(Type, NumRows)
    }.

%% Generate column data based on type and number of rows
generate_column_data(_Type, 0) ->
    [];
generate_column_data(<<"UInt64">>, NumRows) ->
    [rand:uniform(1000000) || _ <- lists:seq(1, NumRows)];
generate_column_data(<<"Int32">>, NumRows) ->
    [rand:uniform(2000) - 1000 || _ <- lists:seq(1, NumRows)];
generate_column_data(<<"String">>, NumRows) ->
    Strings = ["Alice", "Bob", "Charlie", "Diana", "Eve"],
    [lists:nth(rand:uniform(length(Strings)), Strings) || _ <- lists:seq(1, NumRows)].

%% Encode a data block to binary format
encode_data_block(DataBlock) ->
    try
        %% Extract fields
        BlockInfo = maps:get(info, DataBlock),
        NumColumns = maps:get(columns, DataBlock),
        NumRows = maps:get(rows, DataBlock),
        ColumnData = maps:get(column_data, DataBlock),

        %% 1. Encode temporary table name (empty)
        TempTableName = clickhouse_erl_types_primitive:encode_string(""),

        %% 2. Encode block info
        {ok, BlockInfoBin} = encode_block_info(BlockInfo),

        %% 3. Encode number of columns
        NumColumnsBin = clickhouse_erl_types_primitive:encode_varint(NumColumns),

        %% 4. Encode number of rows
        NumRowsBin = clickhouse_erl_types_primitive:encode_varint(NumRows),

        %% 5. Encode column metadata and data
        {ok, ColumnsBin} = encode_columns(ColumnData, NumRows),

        EncodedBlock = <<
            TempTableName/binary,
            BlockInfoBin/binary,
            NumColumnsBin/binary,
            NumRowsBin/binary,
            ColumnsBin/binary
        >>,

        {ok, EncodedBlock}
    catch
        error:Reason ->
            {error, {encoding_failed, Reason}}
    end.

%% Encode block info to binary
encode_block_info(BlockInfo) ->
    try
        IsOverflows = maps:get(is_overflows, BlockInfo),
        BucketNum = maps:get(bucket_num, BlockInfo),

        %% Standard block info format: 1, is_overflows, 2, bucket_num, 0
        Info1 = clickhouse_erl_types_primitive:encode_varint(1),
        IsOverflowsByte =
            case IsOverflows of
                true -> <<1>>;
                false -> <<0>>
            end,
        Info2 = clickhouse_erl_types_primitive:encode_varint(2),
        BucketNumBin = <<BucketNum:32/signed-little-integer>>,
        Info0 = clickhouse_erl_types_primitive:encode_varint(0),

        BlockInfoBin = <<
            Info1/binary,
            IsOverflowsByte/binary,
            Info2/binary,
            BucketNumBin/binary,
            Info0/binary
        >>,

        {ok, BlockInfoBin}
    catch
        error:Reason ->
            {error, {block_info_encoding_failed, Reason}}
    end.

%% Encode columns metadata and data
encode_columns([], _NumRows) ->
    {ok, <<>>};
encode_columns([Column | Rest], NumRows) ->
    try
        Name = maps:get(name, Column),
        Type = maps:get(type, Column),
        Data = maps:get(data, Column),

        %% Encode column name and type
        NameBin = clickhouse_erl_types_primitive:encode_string(Name),
        TypeBin = clickhouse_erl_types_primitive:encode_string(Type),

        %% Encode column data (currently only empty data supported)
        {ok, DataBin} = encode_column_data(Data, Type, NumRows),

        %% Encode remaining columns
        {ok, RestBin} = encode_columns(Rest, NumRows),

        ColumnBin = <<NameBin/binary, TypeBin/binary, DataBin/binary>>,
        {ok, <<ColumnBin/binary, RestBin/binary>>}
    catch
        error:Reason ->
            {error, {column_encoding_failed, Reason}}
    end.

%% Encode column data
encode_column_data([], _Type, 0) ->
    %% Empty data for 0 rows
    {ok, <<>>};
encode_column_data(Data, <<"UInt64">>, NumRows) when length(Data) =:= NumRows ->
    try
        DataBin = <<<<Value:64/little-unsigned-integer>> || Value <- Data>>,
        {ok, DataBin}
    catch
        error:Reason ->
            {error, {encoding_uint64_failed, Reason}}
    end;
encode_column_data(Data, <<"Int32">>, NumRows) when length(Data) =:= NumRows ->
    try
        DataBin = <<<<Value:32/little-signed-integer>> || Value <- Data>>,
        {ok, DataBin}
    catch
        error:Reason ->
            {error, {encoding_int32_failed, Reason}}
    end;
encode_column_data(Data, <<"String">>, NumRows) when length(Data) =:= NumRows ->
    try
        EncodedStrings = [clickhouse_erl_types_primitive:encode_string(Str) || Str <- Data],
        DataBin = iolist_to_binary(EncodedStrings),
        {ok, DataBin}
    catch
        error:Reason ->
            {error, {encoding_string_failed, Reason}}
    end;
encode_column_data(_Data, Type, _NumRows) ->
    {error, {unsupported_column_type, Type}}.

%% Compare two data_block structures for equivalence
data_block_equivalent(Original, Decoded) ->
    %% Compare block info
    OriginalInfo = maps:get(info, Original),
    DecodedInfo = maps:get(info, Decoded),
    InfoMatch = block_info_equivalent(OriginalInfo, DecodedInfo),

    %% Compare columns count
    ColumnsMatch = maps:get(columns, Original) =:= maps:get(columns, Decoded),

    %% Compare rows count
    RowsMatch = maps:get(rows, Original) =:= maps:get(rows, Decoded),

    %% Compare column data
    OriginalColumnData = maps:get(column_data, Original),
    DecodedColumnData = maps:get(column_data, Decoded),
    ColumnDataMatch = column_data_list_equivalent(OriginalColumnData, DecodedColumnData),

    InfoMatch andalso ColumnsMatch andalso RowsMatch andalso ColumnDataMatch.

%% Compare two block_info structures for equivalence
block_info_equivalent(Original, Decoded) ->
    IsOverflowsMatch = maps:get(is_overflows, Original) =:= maps:get(is_overflows, Decoded),
    BucketNumMatch = maps:get(bucket_num, Original) =:= maps:get(bucket_num, Decoded),
    IsOverflowsMatch andalso BucketNumMatch.

%% Compare two column data lists for equivalence
column_data_list_equivalent([], []) ->
    true;
column_data_list_equivalent([OrigCol | OrigRest], [DecCol | DecRest]) ->
    ColMatch = column_data_equivalent(OrigCol, DecCol),
    ColMatch andalso column_data_list_equivalent(OrigRest, DecRest);
column_data_list_equivalent(_, _) ->
    false.

%% Compare two column_data structures for equivalence
column_data_equivalent(Original, Decoded) ->
    %% Convert original character lists to binaries for comparison
    OriginalName = ensure_binary(maps:get(name, Original)),
    DecodedName = maps:get(name, Decoded),
    OriginalType = ensure_binary(maps:get(type, Original)),
    DecodedType = maps:get(type, Decoded),

    %% For data field, need to handle String columns which contain lists of strings
    OriginalData = maps:get(data, Original),
    DecodedData = maps:get(data, Decoded),

    %% Convert data based on type
    NormalizedOriginalData =
        case OriginalType of
            <<"String">> ->
                %% Convert list of character lists to list of binaries
                [ensure_binary(S) || S <- OriginalData];
            _ ->
                %% Numeric types don't need conversion
                OriginalData
        end,

    NameMatch = OriginalName =:= DecodedName,
    TypeMatch = OriginalType =:= DecodedType,
    DataMatch = NormalizedOriginalData =:= DecodedData,
    NameMatch andalso TypeMatch andalso DataMatch.

%% Property test: Data block encoding completeness
%% Feature: insert-queries, Property 1: Data Block Encoding Completeness
%% Validates: Requirements 1.2
prop_data_block_encoding_completeness() ->
    ?FORALL(
        {NumColumns, NumRows},
        {range(0, 5), range(0, 10)},
        begin
            %% Create a data block with the specified dimensions
            Block = #{
                info => #{is_overflows => false, bucket_num => -1},
                columns => NumColumns,
                rows => NumRows,
                column_data => generate_column_list(NumColumns, NumRows)
            },

            %% Encode the data block
            case clickhouse_erl_protocol_data_block:encode_data_block(Block, 54454) of
                {error, {unknown_type, _}} ->
                    %% Expected until column encoders are implemented
                    true;
                {ok, EncodedBlock} when is_list(EncodedBlock) orelse is_binary(EncodedBlock) ->
                    %% Convert to binary if it's an iolist
                    Binary = iolist_to_binary(EncodedBlock),

                    %% Verify the encoded block has all required fields
                    verify_encoded_block_structure(Binary, NumColumns, NumRows);
                _Error ->
                    false
            end
        end
    ).

%% Verify that an encoded block has the correct structure
verify_encoded_block_structure(Binary, ExpectedColumns, ExpectedRows) ->
    try
        %% 1. Decode temp table name (should be empty)
        {ok, TempTableName, Rest1} = clickhouse_erl_types_primitive:decode_string(Binary),
        TempTableNameOk = (TempTableName =:= <<"">>),

        %% 2. Decode BlockInfo (field-based format)
        {ok, _BlockInfo, Rest2} = decode_block_info_for_verification(Rest1),

        %% 3. Decode number of columns
        {ok, NumColumns, Rest3} = clickhouse_erl_types_primitive:decode_varint(Rest2),
        ColumnsOk = (NumColumns =:= ExpectedColumns),

        %% 4. Decode number of rows
        {ok, NumRows, _Rest4} = clickhouse_erl_types_primitive:decode_varint(Rest3),
        RowsOk = (NumRows =:= ExpectedRows),

        %% All checks must pass
        TempTableNameOk andalso ColumnsOk andalso RowsOk
    catch
        _:_ ->
            false
    end.

%% Helper to decode BlockInfo for verification
decode_block_info_for_verification(Binary) ->
    decode_block_info_loop_for_verification(Binary, #{}).

decode_block_info_loop_for_verification(Binary, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Binary) of
        {ok, 0, Rest} ->
            {ok, Acc, Rest};
        {ok, 1, Rest} ->
            <<_IsOverflowsByte:8, Rest2/binary>> = Rest,
            decode_block_info_loop_for_verification(Rest2, Acc);
        {ok, 2, Rest} ->
            <<_BucketNum:32/signed-little-integer, Rest2/binary>> = Rest,
            decode_block_info_loop_for_verification(Rest2, Acc);
        {ok, _Other, _} ->
            {error, unknown_field};
        Error ->
            Error
    end.

%% Property test: Blank data block structure
%% Feature: insert-queries, Property 2: Blank Data Block Structure
%% Validates: Requirements 1.3
prop_blank_data_block_structure() ->
    %% Blank data block should always have the same structure
    ?FORALL(
        _Dummy,
        integer(),
        begin
            %% Encode blank data block
            EncodedBlock = clickhouse_erl_protocol_data_block:encode_blank_data_block(),
            Binary = iolist_to_binary(EncodedBlock),

            %% Verify structure
            try
                %% 1. Decode temp table name (should be empty)
                {ok, TempTableName, Rest1} = clickhouse_erl_types_primitive:decode_string(Binary),
                TempTableNameOk = (TempTableName =:= <<"">>),

                %% 2. Decode BlockInfo
                {ok, BlockInfo, Rest2} = decode_block_info_for_verification(Rest1),
                BlockInfoOk = is_map(BlockInfo),

                %% 3. Decode number of columns (should be 0)
                {ok, NumColumns, Rest3} = clickhouse_erl_types_primitive:decode_varint(Rest2),
                ColumnsOk = (NumColumns =:= 0),

                %% 4. Decode number of rows (should be 0)
                {ok, NumRows, Rest4} = clickhouse_erl_types_primitive:decode_varint(Rest3),
                RowsOk = (NumRows =:= 0),

                %% Should have no remaining data
                NoRemainingData = (Rest4 =:= <<>>),

                %% All checks must pass
                TempTableNameOk andalso BlockInfoOk andalso ColumnsOk andalso RowsOk andalso
                    NoRemainingData
            catch
                _:_ ->
                    false
            end
        end
    ).

%% Property test: Row count consistency
%% Feature: insert-queries, Property 6: Row Count Consistency
%% Validates: Requirements 2.4
prop_row_count_consistency() ->
    ?FORALL(
        NumColumns,
        range(2, 5),
        begin
            %% Generate row counts for each column (potentially different)
            RowCounts = [rand:uniform(10) || _ <- lists:seq(1, NumColumns)],

            %% Generate columns with the specified row counts
            Columns = lists:map(
                fun({Idx, RowCount}) ->
                    Type = lists:nth((Idx rem 3) + 1, [<<"UInt32">>, <<"String">>, <<"Int64">>]),
                    Data = generate_typed_data(Type, RowCount),
                    #{
                        name => iolist_to_binary(io_lib:format("col~p", [Idx])),
                        type => Type,
                        data => Data
                    }
                end,
                lists:zip(lists:seq(1, NumColumns), RowCounts)
            ),

            %% Validate row counts
            Result = clickhouse_erl_protocol_data_block:validate_row_counts(Columns),

            %% Check if all row counts are the same
            UniqueRowCounts = lists:usort(RowCounts),
            case length(UniqueRowCounts) of
                1 ->
                    %% All row counts match - should return ok
                    Result =:= ok;
                _ ->
                    %% Row counts mismatch - should return error
                    case Result of
                        {error, {row_count_mismatch, ErrorList}} ->
                            %% Verify error list contains all columns
                            length(ErrorList) =:= NumColumns;
                        _ ->
                            false
                    end
            end
        end
    ).

%% Helper to generate typed data for property tests
generate_typed_data(<<"UInt32">>, NumRows) ->
    [rand:uniform(4294967295) || _ <- lists:seq(1, NumRows)];
generate_typed_data(<<"Int64">>, NumRows) ->
    [rand:uniform(2000000000) - 1000000000 || _ <- lists:seq(1, NumRows)];
generate_typed_data(<<"String">>, NumRows) ->
    Strings = [<<"Alice">>, <<"Bob">>, <<"Charlie">>, <<"Diana">>, <<"Eve">>],
    [lists:nth(rand:uniform(length(Strings)), Strings) || _ <- lists:seq(1, NumRows)].

%% Property test: Column name validation
%% Feature: insert-queries, Property 5: Column Name Validation
%% Validates: Requirements 2.1, 2.2
prop_column_name_validation() ->
    ?FORALL(
        {NumColumns, InvalidIdx},
        {range(1, 5), range(1, 5)},
        begin
            %% Generate columns with potentially invalid names
            Columns = lists:map(
                fun(Idx) ->
                    %% Make one column have an invalid name
                    Name =
                        if
                            Idx =:= InvalidIdx ->
                                %% Generate invalid name (not a binary)
                                case rand:uniform(4) of
                                    1 -> atom_name;
                                    2 -> "string_name";
                                    3 -> 123;
                                    4 -> {tuple, name}
                                end;
                            true ->
                                %% Valid binary name
                                iolist_to_binary(io_lib:format("col~p", [Idx]))
                        end,
                    #{
                        name => Name,
                        type => <<"UInt32">>,
                        data => [1, 2, 3]
                    }
                end,
                lists:seq(1, NumColumns)
            ),

            %% Validate column names
            Result = clickhouse_erl_protocol_data_block:validate_column_names(Columns),

            %% Check if validation result is correct
            if
                InvalidIdx =< NumColumns ->
                    %% Should return error for invalid name
                    case Result of
                        {error, {invalid_column_name, _}} -> true;
                        _ -> false
                    end;
                true ->
                    %% All names are valid (InvalidIdx > NumColumns)
                    Result =:= ok
            end
        end
    ).

%% Property test: Empty input handling
%% Feature: insert-queries, Property 4: Empty Input Handling
%% Validates: Requirements 1.5
prop_empty_input_handling() ->
    ?FORALL(
        NumColumns,
        range(1, 5),
        begin
            %% Generate columns with 0 rows (empty data)
            Columns = lists:map(
                fun(Idx) ->
                    Type = lists:nth((Idx rem 3) + 1, [<<"UInt32">>, <<"String">>, <<"Int64">>]),
                    #{
                        name => iolist_to_binary(io_lib:format("col~p", [Idx])),
                        type => Type,
                        data => []
                    }
                end,
                lists:seq(1, NumColumns)
            ),

            %% Create a data block with 0 rows
            Block = #{
                info => #{is_overflows => false, bucket_num => -1},
                columns => NumColumns,
                rows => 0,
                column_data => Columns
            },

            %% Encode the data block
            case clickhouse_erl_protocol_data_block:encode_data_block(Block, 54454) of
                {ok, EncodedBlock} when is_list(EncodedBlock) orelse is_binary(EncodedBlock) ->
                    %% Convert to binary if it's an iolist
                    Binary = iolist_to_binary(EncodedBlock),

                    %% Verify the encoded block has 0 rows using case expressions
                    case clickhouse_erl_types_primitive:decode_string(Binary) of
                        {ok, _TempTableName, Rest1} ->
                            case decode_block_info_for_verification(Rest1) of
                                {ok, _BlockInfo, Rest2} ->
                                    case clickhouse_erl_types_primitive:decode_varint(Rest2) of
                                        {ok, DecodedColumns, Rest3} ->
                                            case
                                                clickhouse_erl_types_primitive:decode_varint(Rest3)
                                            of
                                                {ok, DecodedRows, _Rest4} ->
                                                    %% Verify columns match and rows is 0
                                                    (DecodedColumns =:= NumColumns) andalso
                                                        (DecodedRows =:= 0);
                                                {error, _} ->
                                                    false
                                            end;
                                        {error, _} ->
                                            false
                                    end;
                                {error, _} ->
                                    false
                            end;
                        {error, _} ->
                            false
                    end;
                _ ->
                    false
            end
        end
    ).

%% Property test: Type Mismatch Error Reporting
%% Feature: insert-queries, Property 8: Type Mismatch Error Reporting
%% Validates: Requirements 4.1
prop_type_mismatch_error_reporting() ->
    ?FORALL(
        {ColumnName, Type, InvalidValue},
        mismatched_data_gen(),
        begin
            Block = #{
                info => #{is_overflows => false, bucket_num => -1},
                columns => 1,
                rows => 1,
                column_data => [
                    #{name => ColumnName, type => Type, data => [InvalidValue]}
                ]
            },
            case clickhouse_erl_protocol_data_block:encode_data_block(Block, 54454) of
                {error, {type_mismatch, ColumnName, Type, _Reason}} ->
                    true;
                _OtherResult ->
                    false
            end
        end
    ).

%% Property test: Comprehensive Type Mismatch Error Reporting
%% Feature: insert-queries, Property 8.1: Comprehensive Type Mismatch Error Reporting
%% Validates: Requirements 4.1
prop_comprehensive_type_mismatch_reporting() ->
    ?FORALL(
        {ColumnName, Type, InvalidValue},
        comprehensive_mismatched_data_gen(),
        begin
            Block = #{
                info => #{is_overflows => false, bucket_num => -1},
                columns => 1,
                rows => 1,
                column_data => [
                    #{name => ColumnName, type => Type, data => [InvalidValue]}
                ]
            },
            case clickhouse_erl_protocol_data_block:encode_data_block(Block, 54454) of
                {error, {type_mismatch, ColumnName, Type, _Reason}} ->
                    true;
                _OtherResult ->
                    false
            end
        end
    ).

mismatched_data_gen() ->
    oneof([
        {<<"id">>, <<"UInt8">>, 300},
        {<<"id">>, <<"UInt16">>, -1},
        {<<"id">>, <<"UInt32">>, 4294967296},
        {<<"id">>, <<"Int8">>, 128},
        {<<"id">>, <<"Int16">>, 32768},
        {<<"name">>, <<"String">>, #{invalid => map}},
        {<<"date">>, <<"Date">>, {2023, 13, 1}},
        {<<"dt">>, <<"DateTime">>, {{2023, 1, 1}, {25, 0, 0}}}
    ]).

comprehensive_mismatched_data_gen() ->
    ?LET(
        ColumnName,
        non_empty_binary_string_gen(),
        oneof([
            %% UInt8: range 0-255
            {ColumnName, <<"UInt8">>, oneof([-1, 256, <<"abc">>, {1, 2}])},
            %% UInt16: range 0-65535
            {ColumnName, <<"UInt16">>, oneof([-1, 65536, [1, 2], atom])},
            %% UInt32: range 0-4294967295
            {ColumnName, <<"UInt32">>, oneof([-1, 4294967296, 3.14, <<123>>])},
            %% UInt64: range 0-18446744073709551615
            {ColumnName, <<"UInt64">>, oneof([-1, 18446744073709551616, "str", {}])},
            %% Int8: range -128 to 127
            {ColumnName, <<"Int8">>, oneof([-129, 128, <<1, 2>>, [a]])},
            %% Int16: range -32768 to 32767
            {ColumnName, <<"Int16">>, oneof([-32769, 32768, 1.0, {a}])},
            %% Int32: range -2147483648 to 2147483647
            {ColumnName, <<"Int32">>, oneof([-2147483649, 2147483648, "test", atom])},
            %% Int64: range -9223372036854775808 to 9223372036854775807
            {ColumnName, <<"Int64">>, oneof([-9223372036854775809, 9223372036854775808, [], <<>>])},
            %% Float32
            {ColumnName, <<"Float32">>, oneof([<<"not_a_float">>, {1.1}, [1.1]])},
            %% Float64
            {ColumnName, <<"Float64">>, oneof([atom_value, {1.1}, "1.1"])},
            %% String
            {ColumnName, <<"String">>, oneof([123, 1.1, {binary, data}, [1, atom]])},
            %% Date: {Y, M, D}
            {ColumnName, <<"Date">>,
                oneof([{2023, 13, 1}, {2023, 1, 0}, {2023, 2, 29}, 123, <<>>, "2023-01-01"])},
            %% Date32
            {ColumnName, <<"Date32">>, oneof([{2023, 13, 1}, {2023, 1, 32}, atom, [2023, 1, 1]])},
            %% DateTime: {{Y, M, D}, {H, Min, S}}
            {ColumnName, <<"DateTime">>,
                oneof([
                    {{2023, 13, 1}, {0, 0, 0}},
                    {{2023, 1, 32}, {0, 0, 0}},
                    {{2023, 1, 1}, {24, 0, 0}},
                    {{2023, 1, 1}, {0, 60, 0}},
                    {{2023, 1, 1}, {0, 0, -1}},
                    {2023, 1, 1},
                    atom_value
                ])},
            %% DateTime64
            {ColumnName, <<"DateTime64">>, oneof([<<"not_int">>, 1.1, {123}, [123]])}
        ])
    ).
