%% @doc Parser for SERVER_READ_TASK_REQUEST (13) packets.
%%
%% The READ_TASK_REQUEST packet contains a single UUID string that describes
%% a request for which the next task is needed. This is used in distributed
%% query coordination where the server requests tasks from the client.
%%
%% Emitted events:
%% - `{data, task_id, UUID}` - The UUID string identifying the task request
%%
%% Packet format:
%% - task_id (string) - UUID string with varint length prefix
-module(clickhouse_erl_parser_server_read_task_request).
-behaviour(clickhouse_erl_parser_behaviour).

-export([parse/2, init/1]).

-type parser_state() :: #{
    stage := task_id,
    version := non_neg_integer()
}.

-type parse_result() ::
    {done, list(), binary()}
    | {more, list(), binary(), parser_state()}
    | {error, term()}.

%% @doc Initialize parser state for READ_TASK_REQUEST packet.
-spec init(map()) -> parser_state().
init(#{version := Version}) ->
    #{stage => task_id, version => Version}.

%% @doc Parse READ_TASK_REQUEST packet payload.
%% Returns {done, Events, Rest} when complete, or {more, Events, Data, State} if incomplete.
-spec parse(binary(), parser_state()) -> parse_result().
parse(Data, #{stage := task_id} = State) ->
    case clickhouse_erl_types_primitive:decode_string(Data) of
        {ok, TaskID, Rest} ->
            {done, [{data, task_id, TaskID}], Rest};
        {error, {truncated_data, _}} ->
            {more, [], Data, State};
        {error, Reason} ->
            {error, Reason}
    end.
