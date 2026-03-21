%% @doc Parser for SERVER_HELLO (0) packets.
%%
%% The HELLO packet is sent by the server in response to CLIENT_HELLO.
%% It contains server identification and version information.
%%
%% Emitted events:
%% - `{data, name, Name}` - String server name (e.g., "ClickHouse")
%% - `{data, version_major, Major}` - Varint major version number
%% - `{data, version_minor, Minor}` - Varint minor version number
%% - `{data, revision, Revision}` - Varint revision number
%% - `{data, timezone, Timezone}` - String server timezone (version-dependent)
%% - `{data, display_name, DisplayName}` - String display name (version-dependent)
%% - `{data, version_patch, Patch}` - Varint patch version (version-dependent)
%%
%% The parser processes fields sequentially:
%% 1. name (varint-prefixed UTF-8 string)
%% 2. version_major (varint)
%% 3. version_minor (varint)
%% 4. revision (varint)
%% 5. timezone (varint-prefixed UTF-8 string) - if supported by client version
%% 6. display_name (varint-prefixed UTF-8 string) - if supported by client version
%% 7. version_patch (varint) - if supported by client version
%%
%% Version-dependent fields are determined by checking feature support
%% via `clickhouse_erl_protocol_features:has_feature/2`.
-module(clickhouse_erl_parser_server_hello).
-behaviour(clickhouse_erl_parser_behaviour).

-export([parse/2, init/1]).

-type parser_state() :: #{
    stage :=
        name | version_major | version_minor | revision | timezone | display_name | version_patch,
    version := non_neg_integer()
}.

-type parse_result() ::
    {done, list(), binary()}
    | {more, list(), binary(), parser_state()}
    | {error, term()}.

%% @doc Initialize parser state for HELLO packet.
%% Requires client version from state to determine which fields are present.
-spec init(map()) -> parser_state().
init(#{version := Version}) ->
    #{stage => name, version => Version}.

%% @doc Parse HELLO packet payload.
%% Processes fields sequentially, checking version features for optional fields.
%% Returns {done, Events, Rest} when complete, or {more, Events, Data, State} if incomplete.
-spec parse(binary(), parser_state()) -> parse_result().
parse(Data, State) ->
    do_parse(Data, State, []).

do_parse(Data, #{stage := name} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, Name, Rest} ->
            do_parse(Rest, State#{stage => version_major}, [{data, name, Name} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := version_major} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, Ver, Rest} ->
            do_parse(Rest, State#{stage => version_minor}, [{data, version_major, Ver} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := version_minor} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, Ver, Rest} ->
            do_parse(Rest, State#{stage => revision}, [{data, version_minor, Ver} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := revision} = State, Acc) ->
    case clickhouse_erl_types_primitive:decode_varint(Data) of
        {ok, Rev, Rest} ->
            do_parse(Rest, State#{stage => timezone}, [{data, revision, Rev} | Acc]);
        {error, {truncated_data, _}} ->
            {more, lists:reverse(Acc), Data, State};
        {error, Reason} ->
            {error, Reason}
    end;
do_parse(Data, #{stage := timezone, version := ClientVersion} = State, Acc) ->
    case clickhouse_erl_protocol_features:has_feature(timezone, ClientVersion) of
        true ->
            case clickhouse_erl_types_primitive:decode_string(Data) of
                {ok, Tz, Rest} ->
                    do_parse(Rest, State#{stage => display_name}, [{data, timezone, Tz} | Acc]);
                {error, {truncated_data, _}} ->
                    {more, lists:reverse(Acc), Data, State};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            do_parse(Data, State#{stage => display_name}, Acc)
    end;
do_parse(Data, #{stage := display_name, version := ClientVersion} = State, Acc) ->
    case clickhouse_erl_protocol_features:has_feature(display_name, ClientVersion) of
        true ->
            case clickhouse_erl_types_primitive:decode_string(Data) of
                {ok, Dn, Rest} ->
                    do_parse(Rest, State#{stage => version_patch}, [{data, display_name, Dn} | Acc]);
                {error, {truncated_data, _}} ->
                    {more, lists:reverse(Acc), Data, State};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            do_parse(Data, State#{stage => version_patch}, Acc)
    end;
do_parse(Data, #{stage := version_patch, version := ClientVersion} = State, Acc) ->
    case clickhouse_erl_protocol_features:has_feature(version_patch, ClientVersion) of
        true ->
            case clickhouse_erl_types_primitive:decode_varint(Data) of
                {ok, Vp, Rest} ->
                    {done, lists:reverse([{data, version_patch, Vp} | Acc]), Rest};
                {error, {truncated_data, _}} ->
                    {more, lists:reverse(Acc), Data, State};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            {done, lists:reverse(Acc), Data}
    end.
