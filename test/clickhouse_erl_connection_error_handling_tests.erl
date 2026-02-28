%% @doc Unit tests for query parameter error handling.
%%
%% This module contains unit tests for error handling in the query parameters
%% feature, covering validation errors and version compatibility errors.
%% Task 6.1 - Requirements: 7.1, 7.2, 7.3, 7.4
-module(clickhouse_erl_connection_error_handling_tests).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Unit Tests - Error Handling
%%%===================================================================

%% Test invalid parameter key returns {error, {invalid_parameter_key, Key}}
%% Validates: Requirement 7.1
invalid_parameter_key_atom_test() ->
    Params = [{invalid_key, <<"value">>}],
    ?assertEqual(
        {error, {invalid_parameter_key, invalid_key}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

invalid_parameter_key_integer_test() ->
    Params = [{123, <<"value">>}],
    ?assertEqual(
        {error, {invalid_parameter_key, 123}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

invalid_parameter_key_list_test() ->
    Params = [{"key", <<"value">>}],
    ?assertEqual(
        {error, {invalid_parameter_key, "key"}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

%% Test invalid parameter value returns {error, {invalid_parameter_value, Value}}
%% Validates: Requirement 7.2
invalid_parameter_value_integer_test() ->
    Params = [{<<"key">>, 42}],
    ?assertEqual(
        {error, {invalid_parameter_value, 42}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

invalid_parameter_value_atom_test() ->
    Params = [{<<"key">>, value}],
    ?assertEqual(
        {error, {invalid_parameter_value, value}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

invalid_parameter_value_list_test() ->
    Params = [{<<"key">>, "value"}],
    ?assertEqual(
        {error, {invalid_parameter_value, "value"}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

invalid_parameter_value_map_test() ->
    Params = [{<<"key">>, #{value => 1}}],
    ?assertEqual(
        {error, {invalid_parameter_value, #{value => 1}}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

%% Test malformed parameter returns {error, {invalid_parameter_format, Param}}
%% Validates: Requirement 7.3
malformed_parameter_not_tuple_binary_test() ->
    Params = [<<"not_a_tuple">>],
    ?assertEqual(
        {error, {invalid_parameter_format, <<"not_a_tuple">>}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

malformed_parameter_not_tuple_atom_test() ->
    Params = [invalid],
    ?assertEqual(
        {error, {invalid_parameter_format, invalid}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

malformed_parameter_wrong_arity_three_test() ->
    Params = [{<<"key">>, <<"value">>, <<"extra">>}],
    ?assertEqual(
        {error, {invalid_parameter_format, {<<"key">>, <<"value">>, <<"extra">>}}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

malformed_parameter_wrong_arity_one_test() ->
    Params = [{<<"key">>}],
    ?assertEqual(
        {error, {invalid_parameter_format, {<<"key">>}}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

malformed_parameter_empty_tuple_test() ->
    Params = [{}],
    ?assertEqual(
        {error, {invalid_parameter_format, {}}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).

%% Test unsupported version returns {error, {parameters_unsupported, Version}}
%% Validates: Requirement 7.4
unsupported_version_below_threshold_test() ->
    Parameters = [{<<"key">>, <<"value">>}],
    % Just below 54459
    Version = 54458,
    ?assertEqual(
        {error, {parameters_unsupported, Version}},
        clickhouse_erl_connection:should_send_parameters(Parameters, Version)
    ).

unsupported_version_much_older_test() ->
    Parameters = [{<<"key">>, <<"value">>}],
    % Much older version
    Version = 50000,
    ?assertEqual(
        {error, {parameters_unsupported, Version}},
        clickhouse_erl_connection:should_send_parameters(Parameters, Version)
    ).

unsupported_version_zero_test() ->
    Parameters = [{<<"key">>, <<"value">>}],
    Version = 0,
    ?assertEqual(
        {error, {parameters_unsupported, Version}},
        clickhouse_erl_connection:should_send_parameters(Parameters, Version)
    ).

%% Test that empty parameters always succeed regardless of version
%% Validates: Requirement 7.4 (edge case)
empty_parameters_unsupported_version_test() ->
    Parameters = [],
    % Below threshold
    Version = 54458,
    ?assertEqual(
        ok,
        clickhouse_erl_connection:should_send_parameters(Parameters, Version)
    ).

%% Test error precedence - validation happens before version check
%% Validates: Requirements 7.1, 7.4
validation_error_before_version_check_test() ->
    %% Invalid parameter should fail validation before version check
    Parameters = [{invalid_key, <<"value">>}],
    ?assertEqual(
        {error, {invalid_parameter_key, invalid_key}},
        clickhouse_erl_connection:validate_parameters(Parameters)
    ).

%% Test multiple invalid parameters - should fail on first
%% Validates: Requirements 7.1, 7.2, 7.3
first_invalid_parameter_detected_test() ->
    Params = [
        {<<"valid">>, <<"value">>},
        % First invalid
        {invalid_key, <<"value">>},
        % Second invalid (not reached)
        {<<"another">>, 123}
    ],
    ?assertEqual(
        {error, {invalid_parameter_key, invalid_key}},
        clickhouse_erl_connection:validate_parameters(Params)
    ).
