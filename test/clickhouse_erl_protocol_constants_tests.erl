-module(clickhouse_erl_protocol_constants_tests).
-include_lib("eunit/include/eunit.hrl").
-include("src/clickhouse_erl_protocol.hrl").

constants_test() ->
    ?assertEqual(1, ?CLIENT_QUERY),
    ?assertEqual(2, ?CLIENT_DATA),
    ?assertEqual(3, ?CLIENT_CANCEL),
    ?assertEqual(4, ?CLIENT_PING),

    ?assertEqual(1, ?SERVER_DATA),
    ?assertEqual(2, ?SERVER_EXCEPTION),
    ?assertEqual(3, ?SERVER_PROGRESS),
    ?assertEqual(4, ?SERVER_PONG),
    ?assertEqual(5, ?SERVER_END_OF_STREAM),

    ?assertEqual(0, ?STAGE_FETCH_COLUMNS),
    ?assertEqual(1, ?STAGE_WITH_MERGEABLE_STATE),
    ?assertEqual(2, ?STAGE_COMPLETE),

    ?assertEqual(0, ?COMPRESSION_DISABLED),
    ?assertEqual(1, ?COMPRESSION_ENABLED),

    ?assertEqual(1, ?INTERFACE_TCP),
    ?assertEqual(2, ?INTERFACE_HTTP),

    ?assertEqual(0, ?QUERY_KIND_NONE),
    ?assertEqual(1, ?QUERY_KIND_INITIAL),
    ?assertEqual(2, ?QUERY_KIND_SECONDARY).
%% Test that packet type constants maintain expected relationships
packet_type_relationships_test() ->
    %% CLIENT_CANCEL should be 3
    ?assertEqual(3, ?CLIENT_CANCEL),
    %% CLIENT_PING should be 4
    ?assertEqual(4, ?CLIENT_PING).

%% Test that stage constants are properly ordered
stage_ordering_test() ->
    %% Stages should be in logical order: fetch columns < with mergeable state < complete
    ?assert(?STAGE_FETCH_COLUMNS < ?STAGE_WITH_MERGEABLE_STATE),
    ?assert(?STAGE_WITH_MERGEABLE_STATE < ?STAGE_COMPLETE),
    ?assert(?STAGE_FETCH_COLUMNS < ?STAGE_COMPLETE).

%% Test that compression modes are boolean-like
compression_modes_test() ->
    %% Disabled should be 0 (false-like)
    ?assertEqual(0, ?COMPRESSION_DISABLED),

    %% Enabled should be 1 (true-like)
    ?assertEqual(1, ?COMPRESSION_ENABLED),

    %% Should be different values
    ?assert(?COMPRESSION_DISABLED =/= ?COMPRESSION_ENABLED).

%% Test that interface types are distinct and positive
interface_types_test() ->
    %% TCP should be positive
    ?assert(?INTERFACE_TCP > 0),

    %% HTTP should be positive
    ?assert(?INTERFACE_HTTP > 0),

    %% Should be different values
    ?assert(?INTERFACE_TCP =/= ?INTERFACE_HTTP).

%% Test that query kinds are properly ordered
query_kinds_test() ->
    %% None should be 0 (default/unspecified)
    ?assertEqual(0, ?QUERY_KIND_NONE),

    %% Initial should be positive
    ?assert(?QUERY_KIND_INITIAL > 0),

    %% Secondary should be positive
    ?assert(?QUERY_KIND_SECONDARY > 0),

    %% Should be different values
    ?assert(?QUERY_KIND_NONE =/= ?QUERY_KIND_INITIAL),
    ?assert(?QUERY_KIND_INITIAL =/= ?QUERY_KIND_SECONDARY),
    ?assert(?QUERY_KIND_NONE =/= ?QUERY_KIND_SECONDARY).

%% Test that all constants are compile-time constants (not computed)
compile_time_constants_test() ->
    %% All constants should be integers (not computed values)
    ?assert(is_integer(?CLIENT_QUERY)),
    ?assert(is_integer(?CLIENT_DATA)),
    ?assert(is_integer(?CLIENT_CANCEL)),
    ?assert(is_integer(?CLIENT_PING)),

    ?assert(is_integer(?SERVER_DATA)),
    ?assert(is_integer(?SERVER_EXCEPTION)),
    ?assert(is_integer(?SERVER_PROGRESS)),
    ?assert(is_integer(?SERVER_PONG)),
    ?assert(is_integer(?SERVER_END_OF_STREAM)),

    ?assert(is_integer(?STAGE_FETCH_COLUMNS)),
    ?assert(is_integer(?STAGE_WITH_MERGEABLE_STATE)),
    ?assert(is_integer(?STAGE_COMPLETE)),

    ?assert(is_integer(?COMPRESSION_DISABLED)),
    ?assert(is_integer(?COMPRESSION_ENABLED)),

    ?assert(is_integer(?INTERFACE_TCP)),
    ?assert(is_integer(?INTERFACE_HTTP)),

    ?assert(is_integer(?QUERY_KIND_NONE)),
    ?assert(is_integer(?QUERY_KIND_INITIAL)),
    ?assert(is_integer(?QUERY_KIND_SECONDARY)).
