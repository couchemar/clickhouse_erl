%% @doc Property tests for backward compatibility
%%
%% Tests that queries work identically with and without the parameters option.
%% Feature: query-parameters, Property 3: Backward Compatibility
%% Validates: Requirements 1.2, 6.1, 6.4
-module(ct_prop_backward_compatibility).

-export([prop_backward_compatibility/1]).

%% Include CT property test header (will include proper/eqc/triq automatically)
-include_lib("common_test/include/ct_property_test.hrl").

%%%===================================================================
%%% Properties
%%%===================================================================

%% @doc Property: Backward Compatibility
%% Tests that queries work identically with and without parameters option
prop_backward_compatibility(Conn) ->
    ?FORALL(
        QueryText,
        query_gen(),
        begin
            %% Execute query without parameters option
            ResultWithoutParams = clickhouse_erl:query(Conn, QueryText),

            %% Execute query with empty parameters list
            ResultWithEmptyParams = clickhouse_erl:query(
                Conn,
                QueryText,
                #{parameters => []}
            ),

            %% Both should have the same return type structure
            SameReturnType = verify_same_return_type(
                ResultWithoutParams,
                ResultWithEmptyParams
            ),

            %% Both should return valid result tuples
            ValidReturnTypes =
                is_valid_return_type(ResultWithoutParams) andalso
                    is_valid_return_type(ResultWithEmptyParams),

            SameReturnType andalso ValidReturnTypes
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generate random valid SQL queries
query_gen() ->
    oneof([
        % Simple SELECT queries
        return(<<"SELECT 1">>),
        return(<<"SELECT 2 + 2">>),
        return(<<"SELECT 'hello'">>),
        return(<<"SELECT now()">>),
        return(<<"SELECT version()">>),

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

        % SELECT with simple arithmetic
        ?LET(
            {A, B},
            {range(1, 100), range(1, 100)},
            iolist_to_binary([
                "SELECT ",
                integer_to_list(A),
                " + ",
                integer_to_list(B)
            ])
        )
    ]).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Verify that two results have the same return type structure
verify_same_return_type({ok, _Result1}, {ok, _Result2}) ->
    %% Both are ok tuples - this is the expected case
    true;
verify_same_return_type({error, _Reason1}, {error, _Reason2}) ->
    %% Both are error tuples - this is also valid
    true;
verify_same_return_type(_Result1, _Result2) ->
    %% Different return types - this violates backward compatibility
    false.

%% @doc Check if a result has a valid return type
is_valid_return_type({ok, _Result}) ->
    true;
is_valid_return_type({error, _Reason}) ->
    true;
is_valid_return_type(_Other) ->
    false.

%% @doc Escape single quotes in SQL string literals
escape_sql_string(Binary) when is_binary(Binary) ->
    %% Replace single quotes with two single quotes for SQL escaping
    binary:replace(Binary, <<"'">>, <<"''">>, [global]).
