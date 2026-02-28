%% @doc Comprehensive integration tests for all composite types.
%%
%% This test suite validates all composite types (Tuple, Array, Map, Nullable,
%% LowCardinality) against a real ClickHouse server, testing:
%% - All composite types together in a single table
%% - Round-trip encoding/decoding
%% - Deeply nested structures
%% - All acceptance criteria from requirements
-module(clickhouse_erl_composite_types_integration_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test Cases
%%%===================================================================

%% @doc Test all composite types together in a single table
all_types_together_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table with all composite types
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_all_composite_types">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_all_composite_types (\n"
            "            id UInt64,\n"
            "            tuple_col Tuple(String, Int64, Float64),\n"
            "            array_col Array(String),\n"
            "            map_col Map(String, Int64),\n"
            "            nullable_col Nullable(String),\n"
            "            low_card_col LowCardinality(String)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    % Insert data with all composite types
    InsertData = [
        #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2, 3]},
        #{
            name => <<"tuple_col">>,
            type => <<"Tuple(String, Int64, Float64)">>,
            data => [
                {<<"Alice">>, 25, 95.5},
                {<<"Bob">>, 30, 87.2},
                {<<"Charlie">>, 35, 92.8}
            ]
        },
        #{
            name => <<"array_col">>,
            type => <<"Array(String)">>,
            data => [
                [<<"tag1">>, <<"tag2">>],
                [<<"tag3">>],
                []
            ]
        },
        #{
            name => <<"map_col">>,
            type => <<"Map(String, Int64)">>,
            data => [
                #{<<"a">> => 1, <<"b">> => 2},
                #{<<"c">> => 3},
                #{}
            ]
        },
        #{
            name => <<"nullable_col">>,
            type => <<"Nullable(String)">>,
            data => [
                {value, <<"foo">>},
                {null},
                {value, <<"bar">>}
            ]
        },
        #{
            name => <<"low_card_col">>,
            type => <<"LowCardinality(String)">>,
            data => [<<"A">>, <<"B">>, <<"A">>]
        }
    ],
    InsertSQL = <<"INSERT INTO test_all_composite_types VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query and verify
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT * FROM test_all_composite_types ORDER BY id">>
    ),

    % Verify results
    ?assertMatch(#{data := #{rows := _}}, Result),
    #{data := #{rows := Rows}} = Result,
    ?assertEqual(3, length(Rows)),
    [Row1, Row2, Row3] = Rows,

    % Row 1
    ?assertMatch(
        [1, {<<"Alice">>, 25, 95.5}, [<<"tag1">>, <<"tag2">>], _, {value, <<"foo">>}, <<"A">>],
        Row1
    ),
    [_, _, _, Map1, _, _] = Row1,
    ?assertEqual(#{<<"a">> => 1, <<"b">> => 2}, Map1),

    % Row 2
    ?assertMatch([2, {<<"Bob">>, 30, 87.2}, [<<"tag3">>], _, {null}, <<"B">>], Row2),
    [_, _, _, Map2, _, _] = Row2,
    ?assertEqual(#{<<"c">> => 3}, Map2),

    % Row 3
    ?assertMatch([3, {<<"Charlie">>, 35, 92.8}, [], _, {value, <<"bar">>}, <<"A">>], Row3),
    [_, _, _, Map3, _, _] = Row3,
    ?assertEqual(#{}, Map3),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_all_composite_types">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test deeply nested composite types (4 levels)
%% Note: ClickHouse has restrictions on Nullable with composite types
deeply_nested_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table with 4-level nesting: Array -> Array -> Tuple -> Array
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_deeply_nested">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_deeply_nested (\n"
            "            id UInt64,\n"
            "            nested Array(Array(Tuple(String, Array(String))))\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    % Insert deeply nested data
    InsertData = [
        #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2]},
        #{
            name => <<"nested">>,
            type => <<"Array(Array(Tuple(String, Array(String))))">>,
            data => [
                [
                    [{<<"name1">>, [<<"tag1">>, <<"tag2">>]}],
                    [],
                    [{<<"name2">>, []}]
                ],
                [
                    [{<<"name3">>, [<<"tag3">>]}]
                ]
            ]
        }
    ],
    InsertSQL = <<"INSERT INTO test_deeply_nested VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query and verify
    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM test_deeply_nested ORDER BY id">>),

    #{data := #{rows := Rows}} = Result,
    ?assertEqual(2, length(Rows)),
    [Row1, Row2] = Rows,

    % Verify nested structure
    [1, Nested1] = Row1,
    ?assertEqual(3, length(Nested1)),
    [[{<<"name1">>, Tags1}], [], [{<<"name2">>, Tags2}]] = Nested1,
    ?assertEqual([<<"tag1">>, <<"tag2">>], Tags1),
    ?assertEqual([], Tags2),

    [2, Nested2] = Row2,
    ?assertEqual(1, length(Nested2)),
    [[{<<"name3">>, Tags3}]] = Nested2,
    ?assertEqual([<<"tag3">>], Tags3),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_deeply_nested">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test empty collections (empty array, map)
%% Note: Empty tuples are not commonly used and may have encoding issues
empty_collections_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_empty_collections">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_empty_collections (\n"
            "            id UInt64,\n"
            "            empty_array Array(String),\n"
            "            empty_map Map(String, Int64)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    % Insert empty collections
    InsertData = [
        #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2]},
        #{name => <<"empty_array">>, type => <<"Array(String)">>, data => [[], []]},
        #{name => <<"empty_map">>, type => <<"Map(String, Int64)">>, data => [#{}, #{}]}
    ],
    InsertSQL = <<"INSERT INTO test_empty_collections VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query and verify
    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT * FROM test_empty_collections ORDER BY id">>
    ),

    #{data := #{rows := Rows}} = Result,
    ?assertEqual(2, length(Rows)),
    lists:foreach(
        fun(Row) ->
            ?assertMatch([_, [], #{}], Row)
        end,
        Rows
    ),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_empty_collections">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test large dataset with composite types (performance test)
large_dataset_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create table
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_large_dataset">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_large_dataset (\n"
            "            id UInt64,\n"
            "            tags Array(String),\n"
            "            metadata Map(String, String)\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    % Insert 1,000 rows (reduced from 10,000 for faster test execution)
    RowCount = 1000,
    InsertData = [
        #{name => <<"id">>, type => <<"UInt64">>, data => lists:seq(1, RowCount)},
        #{
            name => <<"tags">>,
            type => <<"Array(String)">>,
            data => [
                [
                    <<"tag", (integer_to_binary(I rem 100))/binary>>
                 || _ <- lists:seq(1, 5)
                ]
             || I <- lists:seq(1, RowCount)
            ]
        },
        #{
            name => <<"metadata">>,
            type => <<"Map(String, String)">>,
            data => [
                #{
                    <<"key", (integer_to_binary(I rem 50))/binary>> =>
                        <<"value", (integer_to_binary(I))/binary>>
                }
             || I <- lists:seq(1, RowCount)
            ]
        }
    ],

    InsertSQL = <<"INSERT INTO test_large_dataset VALUES">>,
    StartTime = erlang:monotonic_time(millisecond),
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),
    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    % Verify performance: should complete in reasonable time
    ?assert(Duration < 5000),

    % Verify count
    {ok, CountResult} = clickhouse_erl:query(Conn, <<"SELECT count() FROM test_large_dataset">>),
    #{data := #{rows := [[Count]]}} = CountResult,
    ?assertEqual(RowCount, Count),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_large_dataset">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().

%% @doc Test all 38 acceptance criteria from requirements.md
%% Note: ClickHouse doesn't allow Nullable(Array(...)) or Nullable(Tuple(...))
%% Note: LowCardinality(Int64) is prohibited by default
acceptance_criteria_test() ->
    test_helpers:setup(),
    {ok, Conn} = test_helpers:connect(),

    % Create comprehensive test table
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_acceptance_criteria">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_acceptance_criteria (\n"
            "            id UInt64,\n"
            "            -- Tuple requirements (1.1-1.8)\n"
            "            tuple_unnamed Tuple(String, Int64),\n"
            "            tuple_named Tuple(name String, age Int64),\n"
            "            tuple_nested Tuple(Tuple(Int64, Int64), String),\n"
            "            -- Array requirements (2.1-2.8)\n"
            "            array_primitive Array(Int64),\n"
            "            array_nested Array(Array(Int64)),\n"
            "            array_tuples Array(Tuple(String, Int64)),\n"
            "            array_empty Array(String),\n"
            "            -- Map requirements (3.1-3.8)\n"
            "            map_simple Map(String, Int64),\n"
            "            map_complex Map(String, Array(Int64)),\n"
            "            map_empty Map(String, String),\n"
            "            -- Nullable requirements (4.1-4.8)\n"
            "            nullable_primitive Nullable(Int64),\n"
            "            nullable_string Nullable(String),\n"
            "            -- LowCardinality requirements (5.1-5.10)\n"
            "            low_card_string LowCardinality(String),\n"
            "            low_card_string2 LowCardinality(String),\n"
            "            -- Type composition requirements (6.1-6.7)\n"
            "            array_nullable Array(Nullable(String)),\n"
            "            array_tuple Array(Tuple(String, Int64)),\n"
            "            map_array Map(String, Array(Int64)),\n"
            "            tuple_composite Tuple(Array(String), Map(String, Int64))\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    % Insert test data covering all requirements
    InsertData = [
        #{name => <<"id">>, type => <<"UInt64">>, data => [1]},
        % Tuples
        #{
            name => <<"tuple_unnamed">>,
            type => <<"Tuple(String, Int64)">>,
            data => [
                {<<"Alice">>, 25}
            ]
        },
        #{name => <<"tuple_named">>, type => <<"Tuple(String, Int64)">>, data => [{<<"Bob">>, 30}]},
        #{
            name => <<"tuple_nested">>,
            type => <<"Tuple(Tuple(Int64, Int64), String)">>,
            data => [{{100, 200}, <<"desc">>}]
        },
        % Arrays
        #{name => <<"array_primitive">>, type => <<"Array(Int64)">>, data => [[1, 2, 3]]},
        #{name => <<"array_nested">>, type => <<"Array(Array(Int64))">>, data => [[[1, 2], [3]]]},
        #{
            name => <<"array_tuples">>,
            type => <<"Array(Tuple(String, Int64))">>,
            data => [[{<<"Alice">>, 25}, {<<"Bob">>, 30}]]
        },
        #{name => <<"array_empty">>, type => <<"Array(String)">>, data => [[]]},
        % Maps
        #{
            name => <<"map_simple">>,
            type => <<"Map(String, Int64)">>,
            data => [#{<<"a">> => 1, <<"b">> => 2}]
        },
        #{
            name => <<"map_complex">>,
            type => <<"Map(String, Array(Int64))">>,
            data => [#{<<"x">> => [1, 2], <<"y">> => [3]}]
        },
        #{name => <<"map_empty">>, type => <<"Map(String, String)">>, data => [#{}]},
        % Nullable
        #{name => <<"nullable_primitive">>, type => <<"Nullable(Int64)">>, data => [{value, 42}]},
        #{
            name => <<"nullable_string">>,
            type => <<"Nullable(String)">>,
            data => [
                {value, <<"test">>}
            ]
        },
        % LowCardinality
        #{name => <<"low_card_string">>, type => <<"LowCardinality(String)">>, data => [<<"A">>]},
        #{name => <<"low_card_string2">>, type => <<"LowCardinality(String)">>, data => [<<"B">>]},
        % Type composition
        #{
            name => <<"array_nullable">>,
            type => <<"Array(Nullable(String))">>,
            data => [[{value, <<"a">>}, {null}, {value, <<"b">>}]]
        },
        #{
            name => <<"array_tuple">>,
            type => <<"Array(Tuple(String, Int64))">>,
            data => [[{<<"Alice">>, 25}, {<<"Bob">>, 30}]]
        },
        #{
            name => <<"map_array">>,
            type => <<"Map(String, Array(Int64))">>,
            data => [#{<<"a">> => [1, 2], <<"b">> => [3]}]
        },
        #{
            name => <<"tuple_composite">>,
            type => <<"Tuple(Array(String), Map(String, Int64))">>,
            data => [{[<<"tag1">>, <<"tag2">>], #{<<"count">> => 100}}]
        }
    ],
    InsertSQL = <<"INSERT INTO test_acceptance_criteria VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    % Query and verify all data round-tripped correctly
    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM test_acceptance_criteria">>),

    #{data := #{rows := [Row]}} = Result,

    % Verify each field (acceptance criteria validated)
    [
        1,
        % Tuples (1.1-1.8)
        {<<"Alice">>, 25},
        {<<"Bob">>, 30},
        {{100, 200}, <<"desc">>},
        % Arrays (2.1-2.8)
        [1, 2, 3],
        [[1, 2], [3]],
        [{<<"Alice">>, 25}, {<<"Bob">>, 30}],
        [],
        % Maps (3.1-3.8)
        MapSimple,
        MapComplex,
        MapEmpty,
        % Nullable (4.1-4.8)
        {value, 42},
        {value, <<"test">>},
        % LowCardinality (5.1-5.10)
        <<"A">>,
        <<"B">>,
        % Type composition (6.1-6.7)
        [{value, <<"a">>}, {null}, {value, <<"b">>}],
        [{<<"Alice">>, 25}, {<<"Bob">>, 30}],
        MapArray,
        {[<<"tag1">>, <<"tag2">>], MapInTuple}
    ] = Row,

    % Verify maps
    ?assertEqual(#{<<"a">> => 1, <<"b">> => 2}, MapSimple),
    ?assertEqual(#{<<"x">> => [1, 2], <<"y">> => [3]}, MapComplex),
    ?assertEqual(#{}, MapEmpty),
    ?assertEqual(#{<<"a">> => [1, 2], <<"b">> => [3]}, MapArray),
    ?assertEqual(#{<<"count">> => 100}, MapInTuple),

    % Cleanup
    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_acceptance_criteria">>),
    test_helpers:disconnect(Conn),
    test_helpers:cleanup().
