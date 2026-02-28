%% @doc Property tests for ClickHouse query parameters encoding.
-module(prop_clickhouse_erl_protocol_parameters).

-include_lib("proper/include/proper.hrl").

-import(generators, [
    non_empty_binary_string_gen/0,
    binary_string_gen/0
]).

%%%===================================================================
%%% Generators
%%%===================================================================

%% Generator for valid parameter (tuple of two binaries)
valid_parameter_gen() ->
    {non_empty_binary_string_gen(), binary_string_gen()}.

%% Generator for list of valid parameters
parameter_list_gen() ->
    list(valid_parameter_gen()).

%% Generator for protocol versions (both below and above parameters feature threshold)
version_gen() ->
    oneof([
        %% Versions below parameters feature (54459)
        range(54000, 54458),
        %% Versions at and above parameters feature
        range(54459, 54500)
    ]).

%%%===================================================================
%%% Properties
%%%===================================================================

%% Property 6: Parameter Encoding Format
%% **Validates: Requirements 3.1, 3.2, 3.3, 3.5**
%% Verify each encoded parameter has correct format: Key + Flags(0x02) + Value
%% Verify list ends with single empty string terminator
prop_parameter_encoding_format() ->
    ?FORALL(
        Parameters,
        parameter_list_gen(),
        begin
            Encoded = clickhouse_erl_protocol_parameters:encode_parameters(Parameters),

            case Parameters of
                [] ->
                    %% Empty list: should be only terminator (empty string)
                    %% Empty string is encoded as: varint(0) = <<0>>
                    Encoded =:= <<0>>;
                _ ->
                    %% Non-empty list: verify format
                    verify_parameter_list_format(Parameters, Encoded)
            end
        end
    ).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% Verify that encoded parameter list has correct format
verify_parameter_list_format(Parameters, Encoded) ->
    %% Decode and verify each parameter
    case verify_parameters(Parameters, Encoded) of
        {ok, Remainder} ->
            %% After all parameters, should have exactly one empty string terminator
            %% Empty string is encoded as: varint(0) = <<0>>
            Remainder =:= <<0>>;
        {error, _Reason} ->
            false
    end.

%% Verify each parameter in the list
verify_parameters([], Binary) ->
    {ok, Binary};
verify_parameters([{Key, Value} | Rest], Binary) ->
    case verify_single_parameter(Key, Value, Binary) of
        {ok, Remainder} ->
            verify_parameters(Rest, Remainder);
        {error, Reason} ->
            {error, Reason}
    end.

%% Verify single parameter encoding: Key (string) + Flags (0x02) + Value (string)
%% CRITICAL: Values are quoted with single quotes (SQL literal format)
verify_single_parameter(Key, Value, Binary) ->
    try
        %% Decode key
        {ok, DecodedKey, Rest1} = clickhouse_erl_types_primitive:decode_string(Binary),

        %% Verify key matches
        case DecodedKey =:= Key of
            false ->
                {error, {key_mismatch, DecodedKey, Key}};
            true ->
                %% Decode flags
                {ok, Flags, Rest2} = clickhouse_erl_types_primitive:decode_varint(Rest1),

                %% Verify flags is 0x02 (Custom flag)
                case Flags =:= 16#02 of
                    false ->
                        {error, {invalid_flags, Flags}};
                    true ->
                        %% Decode value
                        {ok, DecodedValue, Rest3} = clickhouse_erl_types_primitive:decode_string(
                            Rest2
                        ),

                        %% Verify value matches (with single quotes around it)
                        %% Special case: empty value becomes ''
                        ExpectedValue =
                            case Value of
                                <<>> -> <<"''">>;
                                _ -> <<"'", Value/binary, "'">>
                            end,
                        case DecodedValue =:= ExpectedValue of
                            false -> {error, {value_mismatch, DecodedValue, ExpectedValue}};
                            true -> {ok, Rest3}
                        end
                end
        end
    catch
        _:Err -> {error, {decode_failed, Err}}
    end.

%% Verify parameters field inclusion based on version and parameter list
verify_parameters_field_inclusion(EncodedPacket, Version, Parameters) ->
    %% Decode the query packet to check if parameters field is present
    case clickhouse_erl_protocol_query_packet:decode(skip_packet_type(EncodedPacket), Version) of
        {ok, DecodedQuery} ->
            DecodedParams = maps:get(parameters, DecodedQuery, []),

            case clickhouse_erl_protocol_features:has_feature(parameters, Version) of
                true ->
                    %% Version >= 54459: parameters should be present
                    %% Decoded parameters are maps with quoted values, convert to tuples for comparison
                    DecodedTuples = lists:map(
                        fun(#{key := K, value := V}) ->
                            %% Remove quotes from decoded value for comparison
                            UnquotedValue = unquote_value(V),
                            {K, UnquotedValue}
                        end,
                        DecodedParams
                    ),
                    DecodedTuples =:= Parameters;
                false ->
                    %% Version < 54459: parameters should be empty list
                    %% (field omitted, so decoder returns empty list)
                    DecodedParams =:= []
            end;
        {error, _Reason} ->
            %% Decoding failed - property fails
            false
    end.

%% Remove single quotes from parameter value
unquote_value(<<"''">>) ->
    %% Empty string literal
    <<>>;
unquote_value(<<"'", Rest/binary>>) ->
    %% Remove leading and trailing quotes
    Size = byte_size(Rest) - 1,
    case Size >= 0 of
        true -> binary:part(Rest, 0, Size);
        false -> Rest
    end;
unquote_value(V) ->
    V.

%% Skip the packet type byte (first byte) to get to the query packet data
skip_packet_type(<<_PacketType:8, Rest/binary>>) ->
    Rest.

%% Property 4: Version-Based Parameters Field Inclusion
%% **Validates: Requirements 2.1, 2.3, 2.5**
%% Verify Parameters field present when version >= 54459 and params non-empty
%% Verify Parameters field omitted when version < 54459
prop_version_based_field_inclusion() ->
    ?FORALL(
        {Version, Parameters},
        {version_gen(), parameter_list_gen()},
        begin
            %% Create minimal query info with parameters
            QueryInfo = #{
                query_body => <<"SELECT 1">>,
                parameters => Parameters
            },

            %% Encode query packet
            {ok, EncodedPacket} = clickhouse_erl_protocol_query_packet:encode(QueryInfo, Version),

            %% Verify parameters field inclusion based on version
            verify_parameters_field_inclusion(EncodedPacket, Version, Parameters)
        end
    ).
