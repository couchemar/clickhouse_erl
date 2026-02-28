%%%-------------------------------------------------------------------
%% @doc Property-based tests for query parameter validation
%%
%% This module contains property-based tests that validate the correctness
%% of parameter validation in the connection module.
%% @end
%%%-------------------------------------------------------------------

-module(prop_clickhouse_erl_connection_parameter).

-include_lib("proper/include/proper.hrl").

-import(generators, [binary_string_gen/0]).

%%%===================================================================
%%% Property Tests
%%%===================================================================

%% @doc Property 1: Parameter Format Validation
%% **Feature: query-parameters, Property 1: Parameter Format Validation**
%% **Validates: Requirements 1.3, 1.4, 7.1, 7.2, 7.3**
prop_parameter_format_validation() ->
    ?FORALL(
        Params,
        parameter_list_gen(),
        begin
            Result = clickhouse_erl_connection:validate_parameters(Params),

            %% Verify the result matches expectations
            case all_valid_format(Params) of
                true ->
                    %% All parameters are valid format - should return ok
                    Result =:= ok;
                false ->
                    %% At least one parameter is invalid - should return error
                    case Result of
                        {error, {invalid_parameter_key, _}} -> true;
                        {error, {invalid_parameter_value, _}} -> true;
                        {error, {invalid_parameter_format, _}} -> true;
                        _ -> false
                    end
            end
        end
    ).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generate a list of parameters (mix of valid and invalid)
parameter_list_gen() ->
    oneof([
        % Empty list (valid)
        return([]),
        % List of only valid parameters
        list(valid_parameter_gen()),
        % List with at least one invalid parameter
        ?LET(
            {Valid, Invalid},
            {list(valid_parameter_gen()), invalid_parameter_gen()},
            Valid ++ [Invalid]
        ),
        % List with multiple invalid parameters
        list(invalid_parameter_gen())
    ]).

%% @doc Generate a valid parameter tuple
valid_parameter_gen() ->
    ?LET(
        {Key, Value},
        {binary_string_gen(), binary_string_gen()},
        {Key, Value}
    ).

%% @doc Generate an invalid parameter
invalid_parameter_gen() ->
    oneof([
        % Non-binary keys
        invalid_key_gen(),
        % Non-binary values
        invalid_value_gen(),
        % Not a tuple
        binary_string_gen(),
        return(not_a_tuple),
        return(123),
        % Wrong tuple arity
        ?LET(
            {Key, Value, Extra},
            {binary_string_gen(), binary_string_gen(), binary_string_gen()},
            {Key, Value, Extra}
        ),
        ?LET(Key, binary_string_gen(), {Key})
    ]).

%% @doc Generate parameter with invalid (non-binary) key
invalid_key_gen() ->
    ?LET(
        {InvalidKey, Value},
        {oneof([atom_key, "string_key", 123]), binary_string_gen()},
        {InvalidKey, Value}
    ).

%% @doc Generate parameter with invalid (non-binary) value
invalid_value_gen() ->
    ?LET(
        {Key, InvalidValue},
        {binary_string_gen(), oneof([atom_value, "string_value", 456])},
        {Key, InvalidValue}
    ).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Check if all parameters in the list are valid format
all_valid_format([]) ->
    true;
all_valid_format([{Key, Value} | Rest]) when is_binary(Key), is_binary(Value) ->
    all_valid_format(Rest);
all_valid_format(_) ->
    false.
