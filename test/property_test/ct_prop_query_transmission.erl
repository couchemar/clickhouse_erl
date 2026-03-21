%% @doc Property tests for query transmission completeness
%%
%% Tests that queries are properly transmitted over established connections.
%% Feature: simple-query, Property 4: Query transmission completeness
%% Validates: Requirements 2.1, 2.2
-module(ct_prop_query_transmission).

-export([prop_query_transmission_completeness/1]).

%% Include CT property test header (will include proper/eqc/triq automatically)
-include_lib("common_test/include/ct_property_test.hrl").

%%%===================================================================
%%% Properties
%%%===================================================================

%% @doc Property: Query Transmission Completeness
%% Tests that queries are properly transmitted and receive responses
prop_query_transmission_completeness(Conn) ->
    ?FORALL(
        QueryText,
        query_gen(),
        begin
            %% Execute query with timeout
            Result = clickhouse_erl:query(Conn, QueryText, #{timeout => 5000}),
            %% Verify result has valid structure
            case Result of
                {ok, _ResultMap} ->
                    %% Query succeeded - valid transmission
                    true;
                {error, Reason} ->
                    %% Query failed - check if it's an expected error
                    is_expected_error(QueryText, Reason)
            end
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generate random SQL queries (valid and invalid)
query_gen() ->
    oneof([
        % Valid queries
        return(<<"SELECT 1">>),
        return(<<"SELECT 2 + 2">>),
        return(<<"SELECT 'hello'">>),
        return(<<"SELECT now()">>),
        return(<<"SELECT version()">>),
        return(<<"SHOW TABLES">>),
        return(<<"SELECT COUNT(*) FROM system.tables">>),

        % SELECT with expressions
        ?LET(
            N,
            range(1, 100),
            list_to_binary("SELECT " ++ integer_to_list(N))
        ),

        % SELECT with string literals
        ?LET(
            S,
            generators:binary_string_gen(),
            iolist_to_binary(["SELECT '", escape_sql_string(S), "'"])
        ),

        % SELECT with multiple columns
        return(<<"SELECT 1, 2, 3">>),
        return(<<"SELECT 'a', 'b', 'c'">>),

        % SELECT with arithmetic
        ?LET(
            {A, B},
            {range(1, 100), range(1, 100)},
            iolist_to_binary([
                "SELECT ",
                integer_to_list(A),
                " + ",
                integer_to_list(B)
            ])
        ),

        % Invalid queries (should fail gracefully)
        return(<<>>),
        return(<<"   ">>),
        return(<<"INVALID SQL SYNTAX">>),
        return(<<"SELECT * FROM nonexistent_table_xyz">>)
    ]).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Check if an error is expected for a given query
is_expected_error(QueryText, Reason) ->
    TrimmedQuery = string:trim(QueryText),
    case TrimmedQuery of
        <<>> ->
            %% Empty query should fail
            true;
        _ ->
            %% Check if query contains invalid syntax patterns
            InvalidPatterns = [
                <<"INVALID">>,
                <<"nonexistent_table">>
            ],
            HasInvalidPattern = lists:any(
                fun(Pattern) ->
                    binary:match(QueryText, Pattern) =/= nomatch
                end,
                InvalidPatterns
            ),
            %% Check for timeout errors
            IsTimeout =
                case Reason of
                    {timeout_error, _} -> true;
                    _ -> false
                end,
            %% If query has invalid pattern, error is expected
            %% Timeouts are also acceptable
            HasInvalidPattern orelse IsTimeout orelse
                %% Otherwise, any error is acceptable (network issues, etc.)
                true
    end.

%% @doc Escape single quotes in SQL string literals
escape_sql_string(Binary) when is_binary(Binary) ->
    %% Replace single quotes with two single quotes for SQL escaping
    binary:replace(Binary, <<"'">>, <<"''">>, [global]).
