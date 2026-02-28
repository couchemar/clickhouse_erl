%% @doc Property-based tests for clickhouse_erl_query_manager
%% Tests settings normalization properties using PropEr
-module(prop_clickhouse_erl_query_manager).
-include_lib("proper/include/proper.hrl").

%% Export properties
-export([
    prop_format_conversion_equivalence/0,
    prop_backward_compatibility/0,
    prop_flag_preservation/0,
    prop_empty_settings_handling/0
]).

%%%===================================================================
%%% Generators
%%%===================================================================

%% @doc Generate non-empty binary keys
setting_key() ->
    ?SUCHTHAT(Key, binary(), byte_size(Key) > 0).

%% @doc Generate binary values (can be empty)
setting_value() ->
    binary().

%% @doc Generate protocol format settings
setting_protocol_format() ->
    list(
        ?LET(
            {Key, Value, Important, Custom, Obsolete},
            {setting_key(), setting_value(), boolean(), boolean(), boolean()},
            #{
                key => Key,
                value => Value,
                important => Important,
                custom => Custom,
                obsolete => Obsolete
            }
        )
    ).

%%%===================================================================
%%% Properties
%%%===================================================================

%% @doc Property 1: Format Conversion Equivalence
%% For any key-value pair, all three formats produce identical binary encoding
%% Validates: Requirements 1.1.2, 1.2.2
prop_format_conversion_equivalence() ->
    ?FORALL(
        {Key, Value},
        {setting_key(), setting_value()},
        begin
            %% Create settings in all three formats
            Map = #{Key => Value},
            KwList = [{Key, Value}],
            Protocol = [#{key => Key, value => Value}],

            %% Normalize all formats
            NormMap = clickhouse_erl_query_manager:normalize_settings(Map),
            NormKw = clickhouse_erl_query_manager:normalize_settings(KwList),
            NormProto = clickhouse_erl_query_manager:normalize_settings(Protocol),

            %% All should produce equivalent settings
            %% Check that all have same key and value
            [MapSetting] = NormMap,
            [KwSetting] = NormKw,
            [ProtoSetting] = NormProto,

            KeysMatch =
                maps:get(key, MapSetting) =:= Key andalso
                    maps:get(key, KwSetting) =:= Key andalso
                    maps:get(key, ProtoSetting) =:= Key,

            ValuesMatch =
                maps:get(value, MapSetting) =:= Value andalso
                    maps:get(value, KwSetting) =:= Value andalso
                    maps:get(value, ProtoSetting) =:= Value,

            %% All should have default flags
            DefaultFlags =
                maps:get(important, MapSetting) =:= false andalso
                    maps:get(custom, MapSetting) =:= false andalso
                    maps:get(obsolete, MapSetting) =:= false andalso
                    maps:get(important, KwSetting) =:= false andalso
                    maps:get(custom, KwSetting) =:= false andalso
                    maps:get(obsolete, KwSetting) =:= false andalso
                    maps:get(important, ProtoSetting) =:= false andalso
                    maps:get(custom, ProtoSetting) =:= false andalso
                    maps:get(obsolete, ProtoSetting) =:= false,

            KeysMatch andalso ValuesMatch andalso DefaultFlags
        end
    ).

%% @doc Property 2: Backward Compatibility
%% Protocol format settings preserve keys, values, and explicit flags
%% Validates: Requirements 1.3.1, 1.4.1
prop_backward_compatibility() ->
    ?FORALL(
        Settings,
        setting_protocol_format(),
        begin
            Normalized = clickhouse_erl_query_manager:normalize_settings(Settings),

            %% Should have same number of settings
            length(Settings) =:= length(Normalized) andalso
                %% All settings should preserve keys and values
                lists:all(
                    fun(OrigSetting) ->
                        Key = maps:get(key, OrigSetting),
                        Value = maps:get(value, OrigSetting),

                        %% Find corresponding normalized setting
                        lists:any(
                            fun(NormSetting) ->
                                maps:get(key, NormSetting) =:= Key andalso
                                    maps:get(value, NormSetting) =:= Value
                            end,
                            Normalized
                        )
                    end,
                    Settings
                )
        end
    ).

%% @doc Property 3: Flag Preservation
%% Explicit flags in protocol format are preserved after normalization
%% Validates: Requirements 1.3.1
prop_flag_preservation() ->
    ?FORALL(
        {Key, Value, Important, Custom, Obsolete},
        {setting_key(), setting_value(), boolean(), boolean(), boolean()},
        begin
            %% Create protocol format setting with explicit flags
            Setting = #{
                key => Key,
                value => Value,
                important => Important,
                custom => Custom,
                obsolete => Obsolete
            },

            %% Normalize
            [Normalized] = clickhouse_erl_query_manager:normalize_settings([Setting]),

            %% Verify all flags are preserved
            maps:get(key, Normalized) =:= Key andalso
                maps:get(value, Normalized) =:= Value andalso
                maps:get(important, Normalized) =:= Important andalso
                maps:get(custom, Normalized) =:= Custom andalso
                maps:get(obsolete, Normalized) =:= Obsolete
        end
    ).

%% @doc Property 4: Empty Settings Handling
%% Empty inputs produce empty output
%% Validates: Requirements 1.1.2, 1.2.2
prop_empty_settings_handling() ->
    ?FORALL(
        _X,
        integer(),
        begin
            %% Test empty map
            EmptyMapResult = clickhouse_erl_query_manager:normalize_settings(#{}),

            %% Test empty list
            EmptyListResult = clickhouse_erl_query_manager:normalize_settings([]),

            %% Both should return empty list
            EmptyMapResult =:= [] andalso EmptyListResult =:= []
        end
    ).
