%% @doc Unit tests for query parameter validation.
%%
%% This module contains unit tests for the validate_parameters/1 function
%% in the connection module.
-module(clickhouse_erl_connection_parameter_validation_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Unit Tests - Parameter Validation
%%%===================================================================

%% Test valid empty parameter list
%% Validates: Requirements 1.5
validate_empty_parameters_test() ->
    ?assertEqual(ok, clickhouse_erl_connection:validate_parameters([])).

%% Test valid single parameter
%% Validates: Requirements 1.3, 1.4
validate_single_parameter_test() ->
    Params = [{<<"key">>, <<"value">>}],
    ?assertEqual(ok, clickhouse_erl_connection:validate_parameters(Params)).

%% Test valid multiple parameters
%% Validates: Requirements 1.3, 1.4
validate_multiple_parameters_test() ->
    Params = [
        {<<"user_id">>, <<"12345">>},
        {<<"name">>, <<"Alice">>},
        {<<"active">>, <<"1">>}
    ],
    ?assertEqual(ok, clickhouse_erl_connection:validate_parameters(Params)).

%% Test invalid parameter - non-binary key
%% Validates: Requirements 7.1
validate_non_binary_key_test() ->
    Params = [{user_id, <<"12345">>}],
    ?assertEqual(
        {error, {invalid_parameter_key, user_id}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

%% Test invalid parameter - non-binary value
%% Validates: Requirements 7.2
validate_non_binary_value_test() ->
    Params = [{<<"user_id">>, 12345}],
    ?assertEqual(
        {error, {invalid_parameter_value, 12345}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

%% Test invalid parameter - malformed tuple (not a tuple)
%% Validates: Requirements 7.3
validate_malformed_parameter_not_tuple_test() ->
    Params = [<<"not_a_tuple">>],
    ?assertEqual(
        {error, {invalid_parameter_format, <<"not_a_tuple">>}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

%% Test invalid parameter - malformed tuple (wrong arity)
%% Validates: Requirements 7.3
validate_malformed_parameter_wrong_arity_test() ->
    Params = [{<<"key">>, <<"value">>, <<"extra">>}],
    ?assertEqual(
        {error, {invalid_parameter_format, {<<"key">>, <<"value">>, <<"extra">>}}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

%% Test mixed valid and invalid parameters - should fail on first invalid
%% Validates: Requirements 1.3, 1.4, 7.1
validate_mixed_parameters_test() ->
    Params = [
        {<<"valid_key">>, <<"valid_value">>},
        {invalid_key, <<"value">>}
    ],
    ?assertEqual(
        {error, {invalid_parameter_key, invalid_key}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

%% Test parameter with empty binary key (valid)
%% Validates: Requirements 1.3, 1.4
validate_empty_binary_key_test() ->
    Params = [{<<>>, <<"value">>}],
    ?assertEqual(ok, clickhouse_erl_connection:validate_parameters(Params)).

%% Test parameter with empty binary value (valid)
%% Validates: Requirements 1.3, 1.4
validate_empty_binary_value_test() ->
    Params = [{<<"key">>, <<>>}],
    ?assertEqual(ok, clickhouse_erl_connection:validate_parameters(Params)).

%% Test parameter with UTF-8 strings
%% Validates: Requirements 1.3, 1.4
validate_utf8_parameters_test() ->
    Params = [
        {<<"名前"/utf8>>, <<"太郎"/utf8>>},
        {<<"город"/utf8>>, <<"Москва"/utf8>>}
    ],
    ?assertEqual(ok, clickhouse_erl_connection:validate_parameters(Params)).
