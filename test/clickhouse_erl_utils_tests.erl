-module(clickhouse_erl_utils_tests).
-include_lib("eunit/include/eunit.hrl").

generate_query_id_test() ->
    Id = clickhouse_erl_utils:generate_query_id(),
    ?assert(is_binary(Id)),
    ?assert(byte_size(Id) > 0),
    %% Basic UUID v4 format verification (8-4-4-4-12)
    ?assertEqual(36, byte_size(Id)),
    ?assertEqual($-, binary:at(Id, 8)),
    ?assertEqual($-, binary:at(Id, 13)),
    ?assertEqual($-, binary:at(Id, 18)),
    ?assertEqual($-, binary:at(Id, 23)).

uniqueness_test() ->
    Id1 = clickhouse_erl_utils:generate_query_id(),
    Id2 = clickhouse_erl_utils:generate_query_id(),
    ?assertNotEqual(Id1, Id2).
