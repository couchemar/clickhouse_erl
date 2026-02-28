-module(clickhouse_erl_utils).

%% Public API
-export([generate_query_id/0]).

-spec generate_query_id() -> binary().
generate_query_id() ->
    list_to_binary(uuid:uuid_to_string(uuid:get_v4())).
