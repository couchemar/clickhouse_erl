%% @doc Test helper utilities for integration tests
%%
%% Provides common setup/teardown and connection management for tests.
-module(test_helpers).

-export([
    setup/0,
    cleanup/0,
    connect/0,
    disconnect/1,
    clickhouse_host/0,
    clickhouse_port/0,
    test_database/0,
    test_username/0,
    test_password/0
]).

%% Test configuration
-define(CLICKHOUSE_HOST, "localhost").
-define(CLICKHOUSE_PORT, 9000).
-define(TEST_DATABASE, "db").
-define(TEST_USERNAME, "user").
-define(TEST_PASSWORD, "password").

%%%===================================================================
%%% Setup and Teardown
%%%===================================================================

%% @doc Setup test environment - start application
-spec setup() -> ok.
setup() ->
    {ok, _} = application:ensure_all_started(clickhouse_erl),
    ok.

%% @doc Cleanup test environment - stop application
-spec cleanup() -> ok.
cleanup() ->
    application:stop(clickhouse_erl),
    ok.

%%%===================================================================
%%% Connection Management
%%%===================================================================

%% @doc Connect to ClickHouse with default test configuration
-spec connect() -> {ok, pid()} | {error, term()}.
connect() ->
    Options = #{
        username => test_username(),
        password => test_password(),
        database => test_database()
    },
    clickhouse_erl:connect(clickhouse_host(), clickhouse_port(), Options).

%% @doc Disconnect from ClickHouse
-spec disconnect(pid()) -> ok.
disconnect(Conn) ->
    clickhouse_erl:disconnect(Conn).

%%%===================================================================
%%% Configuration Accessors
%%%===================================================================

%% @doc Get ClickHouse host
-spec clickhouse_host() -> string().
clickhouse_host() -> ?CLICKHOUSE_HOST.

%% @doc Get ClickHouse port
-spec clickhouse_port() -> pos_integer().
clickhouse_port() -> ?CLICKHOUSE_PORT.

%% @doc Get test database name
-spec test_database() -> binary().
test_database() -> ?TEST_DATABASE.

%% @doc Get test username
-spec test_username() -> binary().
test_username() -> ?TEST_USERNAME.

%% @doc Get test password
-spec test_password() -> binary().
test_password() -> ?TEST_PASSWORD.
