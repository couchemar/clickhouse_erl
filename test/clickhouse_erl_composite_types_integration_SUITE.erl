-module(clickhouse_erl_composite_types_integration_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([
    all_types_together/1,
    deeply_nested/1,
    empty_collections/1,
    large_dataset/1,
    acceptance_criteria/1,
    bool_and_extended_types_in_composites/1
]).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [
        all_types_together,
        deeply_nested,
        empty_collections,
        large_dataset,
        acceptance_criteria,
        bool_and_extended_types_in_composites
    ].

init_per_suite(Config) ->
    test_helpers:setup(),
    Config.

end_per_suite(_Config) ->
    test_helpers:cleanup(),
    ok.

%% Test all composite types together in a single table
all_types_together(_Config) ->
    {ok, Conn} = test_helpers:connect(),

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

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT * FROM test_all_composite_types ORDER BY id">>
    ),

    #{data := #{rows := Rows}} = Result,
    3 = length(Rows),
    [Row1, Row2, Row3] = Rows,

    [1, {<<"Alice">>, 25, 95.5}, [<<"tag1">>, <<"tag2">>], Map1, <<"foo">>, <<"A">>] = Row1,
    #{<<"a">> := 1, <<"b">> := 2} = Map1,

    [2, {<<"Bob">>, 30, 87.2}, [<<"tag3">>], Map2, null, <<"B">>] = Row2,
    #{<<"c">> := 3} = Map2,

    [3, {<<"Charlie">>, 35, 92.8}, [], Map3, <<"bar">>, <<"A">>] = Row3,
    #{} = Map3,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_all_composite_types">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test deeply nested composite types (4 levels)
deeply_nested(_Config) ->
    {ok, Conn} = test_helpers:connect(),

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

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM test_deeply_nested ORDER BY id">>),

    #{data := #{rows := Rows}} = Result,
    2 = length(Rows),
    [Row1, Row2] = Rows,

    [1, Nested1] = Row1,
    3 = length(Nested1),
    [[{<<"name1">>, Tags1}], [], [{<<"name2">>, Tags2}]] = Nested1,
    [<<"tag1">>, <<"tag2">>] = Tags1,
    [] = Tags2,

    [2, Nested2] = Row2,
    1 = length(Nested2),
    [[{<<"name3">>, Tags3}]] = Nested2,
    [<<"tag3">>] = Tags3,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_deeply_nested">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test empty collections
empty_collections(_Config) ->
    {ok, Conn} = test_helpers:connect(),

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

    InsertData = [
        #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2]},
        #{name => <<"empty_array">>, type => <<"Array(String)">>, data => [[], []]},
        #{name => <<"empty_map">>, type => <<"Map(String, Int64)">>, data => [#{}, #{}]}
    ],
    InsertSQL = <<"INSERT INTO test_empty_collections VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT * FROM test_empty_collections ORDER BY id">>
    ),

    #{data := #{rows := Rows}} = Result,
    2 = length(Rows),
    lists:foreach(
        fun(Row) ->
            [_, [], #{}] = Row
        end,
        Rows
    ),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_empty_collections">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test large dataset with composite types
large_dataset(_Config) ->
    {ok, Conn} = test_helpers:connect(),

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

    true = Duration < 5000,

    {ok, CountResult} = clickhouse_erl:query(Conn, <<"SELECT count() FROM test_large_dataset">>),
    #{data := #{rows := [[Count]]}} = CountResult,
    RowCount = Count,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_large_dataset">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test all acceptance criteria from requirements.md
acceptance_criteria(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_acceptance_criteria">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "\n"
            "        CREATE TABLE test_acceptance_criteria (\n"
            "            id UInt64,\n"
            "            tuple_unnamed Tuple(String, Int64),\n"
            "            tuple_named Tuple(name String, age Int64),\n"
            "            tuple_nested Tuple(Tuple(Int64, Int64), String),\n"
            "            array_primitive Array(Int64),\n"
            "            array_nested Array(Array(Int64)),\n"
            "            array_tuples Array(Tuple(String, Int64)),\n"
            "            array_empty Array(String),\n"
            "            map_simple Map(String, Int64),\n"
            "            map_complex Map(String, Array(Int64)),\n"
            "            map_empty Map(String, String),\n"
            "            nullable_primitive Nullable(Int64),\n"
            "            nullable_string Nullable(String),\n"
            "            low_card_string LowCardinality(String),\n"
            "            low_card_string2 LowCardinality(String),\n"
            "            array_nullable Array(Nullable(String)),\n"
            "            array_tuple Array(Tuple(String, Int64)),\n"
            "            map_array Map(String, Array(Int64)),\n"
            "            tuple_composite Tuple(Array(String), Map(String, Int64))\n"
            "        ) ENGINE = Memory\n"
            "    "
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt64">>, data => [1]},
        #{
            name => <<"tuple_unnamed">>,
            type => <<"Tuple(String, Int64)">>,
            data => [{<<"Alice">>, 25}]
        },
        #{name => <<"tuple_named">>, type => <<"Tuple(String, Int64)">>, data => [{<<"Bob">>, 30}]},
        #{
            name => <<"tuple_nested">>,
            type => <<"Tuple(Tuple(Int64, Int64), String)">>,
            data => [{{100, 200}, <<"desc">>}]
        },
        #{name => <<"array_primitive">>, type => <<"Array(Int64)">>, data => [[1, 2, 3]]},
        #{name => <<"array_nested">>, type => <<"Array(Array(Int64))">>, data => [[[1, 2], [3]]]},
        #{
            name => <<"array_tuples">>,
            type => <<"Array(Tuple(String, Int64))">>,
            data => [[{<<"Alice">>, 25}, {<<"Bob">>, 30}]]
        },
        #{name => <<"array_empty">>, type => <<"Array(String)">>, data => [[]]},
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
        #{name => <<"nullable_primitive">>, type => <<"Nullable(Int64)">>, data => [{value, 42}]},
        #{
            name => <<"nullable_string">>,
            type => <<"Nullable(String)">>,
            data => [{value, <<"test">>}]
        },
        #{name => <<"low_card_string">>, type => <<"LowCardinality(String)">>, data => [<<"A">>]},
        #{name => <<"low_card_string2">>, type => <<"LowCardinality(String)">>, data => [<<"B">>]},
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

    {ok, Result} = clickhouse_erl:query(Conn, <<"SELECT * FROM test_acceptance_criteria">>),

    #{data := #{rows := [Row]}} = Result,

    [
        1,
        {<<"Alice">>, 25},
        {<<"Bob">>, 30},
        {{100, 200}, <<"desc">>},
        [1, 2, 3],
        [[1, 2], [3]],
        [{<<"Alice">>, 25}, {<<"Bob">>, 30}],
        [],
        MapSimple,
        MapComplex,
        MapEmpty,
        42,
        <<"test">>,
        <<"A">>,
        <<"B">>,
        [{value, <<"a">>}, {null}, {value, <<"b">>}],
        [{<<"Alice">>, 25}, {<<"Bob">>, 30}],
        MapArray,
        {[<<"tag1">>, <<"tag2">>], MapInTuple}
    ] = Row,

    #{<<"a">> := 1, <<"b">> := 2} = MapSimple,
    #{<<"x">> := [1, 2], <<"y">> := [3]} = MapComplex,
    #{} = MapEmpty,
    #{<<"a">> := [1, 2], <<"b">> := [3]} = MapArray,
    #{<<"count">> := 100} = MapInTuple,

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_acceptance_criteria">>),
    test_helpers:disconnect(Conn),
    ok.

%% Test Bool and extended integer types inside composite types
%% Validates fix for {unknown_type, <<"Bool">>} in parse_column_type/1
bool_and_extended_types_in_composites(_Config) ->
    {ok, Conn} = test_helpers:connect(),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE IF EXISTS test_bool_extended">>),
    {ok, _} = clickhouse_erl:query(
        Conn,
        <<
            "CREATE TABLE test_bool_extended ("
            "id UInt64, "
            "bool_col Bool, "
            "nullable_bool Nullable(Bool), "
            "tuple_with_bool Tuple(Int64, Bool), "
            "array_of_bool Array(Bool), "
            "int128_col Int128, "
            "uint256_col UInt256"
            ") ENGINE = Memory"
        >>
    ),

    InsertData = [
        #{name => <<"id">>, type => <<"UInt64">>, data => [1, 2]},
        #{name => <<"bool_col">>, type => <<"Bool">>, data => [true, false]},
        #{
            name => <<"nullable_bool">>,
            type => <<"Nullable(Bool)">>,
            data => [{value, true}, {null}]
        },
        #{
            name => <<"tuple_with_bool">>,
            type => <<"Tuple(Int64, Bool)">>,
            data => [{42, true}, {0, false}]
        },
        #{
            name => <<"array_of_bool">>,
            type => <<"Array(Bool)">>,
            data => [[true, false, true], [false]]
        },
        #{
            name => <<"int128_col">>,
            type => <<"Int128">>,
            data => [123456789012345678, -987654321]
        },
        #{
            name => <<"uint256_col">>,
            type => <<"UInt256">>,
            data => [99999999999999, 1]
        }
    ],

    InsertSQL = <<"INSERT INTO test_bool_extended VALUES">>,
    {ok, _} = clickhouse_erl:insert(Conn, InsertSQL, InsertData),

    {ok, Result} = clickhouse_erl:query(
        Conn, <<"SELECT * FROM test_bool_extended ORDER BY id">>
    ),

    #{data := #{rows := Rows}} = Result,
    2 = length(Rows),

    [Row1, Row2] = Rows,
    %% Row 1: id=1, bool=true, nullable_bool=true(1), tuple={42,1}, array=[1,0,1]
    [1, true, 1, {42, 1}, [1, 0, 1], Int128Val1, UInt256Val1] = Row1,
    true = (Int128Val1 =:= 123456789012345678),
    true = (UInt256Val1 =:= 99999999999999),

    %% Row 2: id=2, bool=false, nullable_bool=null, tuple={0,0}, array=[0]
    [2, false, null, {0, 0}, [0], Int128Val2, UInt256Val2] = Row2,
    true = (Int128Val2 =:= -987654321),
    true = (UInt256Val2 =:= 1),

    {ok, _} = clickhouse_erl:query(Conn, <<"DROP TABLE test_bool_extended">>),
    test_helpers:disconnect(Conn),
    ok.
