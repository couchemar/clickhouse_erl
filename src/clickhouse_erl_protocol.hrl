%% @doc ClickHouse protocol type definitions and constants.
%%
%% This header file contains shared type definitions and constants used
%% across the ClickHouse protocol implementation modules.

%% Type definitions
-type server_hello_info() :: #{
    name => binary(),
    version_major => non_neg_integer(),
    version_minor => non_neg_integer(),
    revision => non_neg_integer(),
    timezone => binary(),
    display_name => binary(),
    version_patch => non_neg_integer()
}.

%% Exception handling types
-record(exception_info, {
    error_code :: integer(),
    exception_name :: binary(),
    message :: binary(),
    stack_trace :: binary(),
    nested :: boolean(),
    nested_exceptions :: [#exception_info{}]
}).

-type exception_info() :: #exception_info{}.

-define(PROTOCOL_VERSION, 54460).

%% Client packet types
-define(CLIENT_QUERY, 1).
-define(CLIENT_DATA, 2).
-define(CLIENT_CANCEL, 3).
-define(CLIENT_PING, 4).

%% Server packet types
-define(SERVER_HELLO, 0).
-define(SERVER_DATA, 1).
-define(SERVER_EXCEPTION, 2).
-define(SERVER_PROGRESS, 3).
-define(SERVER_PONG, 4).
-define(SERVER_END_OF_STREAM, 5).
-define(SERVER_PROFILE, 6).
-define(SERVER_TOTALS, 7).
-define(SERVER_EXTREMES, 8).
-define(SERVER_TABLES_STATUS, 9).
-define(SERVER_LOG, 10).
-define(SERVER_TABLE_COLUMNS, 11).
-define(SERVER_PART_UUIDS, 12).
-define(SERVER_READ_TASK_REQUEST, 13).
-define(SERVER_PROFILE_EVENTS, 14).

%% Query stages
-define(STAGE_FETCH_COLUMNS, 0).
-define(STAGE_WITH_MERGEABLE_STATE, 1).
-define(STAGE_COMPLETE, 2).

%% Compression modes
-define(COMPRESSION_DISABLED, 0).
-define(COMPRESSION_ENABLED, 1).

%% Interface types
-define(INTERFACE_TCP, 1).
-define(INTERFACE_HTTP, 2).

%% Query kinds
-define(QUERY_KIND_NONE, 0).
-define(QUERY_KIND_INITIAL, 1).
-define(QUERY_KIND_SECONDARY, 2).

%% Protocol Revision Markers
-define(DBMS_MIN_REVISION_WITH_SERVER_TIMEZONE, 54197).
-define(DBMS_MIN_REVISION_WITH_SERVER_DISPLAY_NAME, 54237).
-define(DBMS_MIN_REVISION_WITH_VERSION_PATCH, 54442).
-define(DBMS_MIN_REVISION_WITH_CLIENT_PORT, 54453).
-define(DBMS_MIN_REVISION_WITH_SCRIPTS, 54467).
-define(DBMS_MIN_REVISION_WITH_PUBLIC_HOST, 54451).

-type query_stage() :: 0 | 1 | 2.
-type compression_mode() :: 0 | 1.
-type interface_type() :: 1 | 2.
-type query_kind() :: 0 | 1 | 2.

-type setting() :: #{
    key => binary(),
    value => binary(),
    important => boolean(),
    custom => boolean(),
    obsolete => boolean()
}.

%% Settings input format types
-type setting_simple_map() :: #{binary() => binary()}.
-type setting_keyword_list() :: [{binary(), binary()}].
-type setting_protocol_format() :: #{
    key := binary(),
    value := binary(),
    important => boolean(),
    custom => boolean(),
    obsolete => boolean()
}.
-type settings_input() ::
    setting_simple_map()
    | setting_keyword_list()
    | [setting_protocol_format()].

-type client_info() :: #{
    query_kind => query_kind(),
    initial_user => binary(),
    initial_query_id => binary(),
    initial_address => binary(),
    initial_time => integer(),
    os_user => binary(),
    client_hostname => binary(),
    client_name => binary(),
    version_major => non_neg_integer(),
    version_minor => non_neg_integer(),
    protocol_version => non_neg_integer(),
    quota_key => binary(),
    distributed_depth => non_neg_integer(),
    version_patch => non_neg_integer(),
    collaborate_with_initiator => non_neg_integer(),
    count_participating_replicas => non_neg_integer(),
    number_of_current_replica => non_neg_integer()
}.

-type query_info() :: #{
    query_id => binary(),
    query_body => binary(),
    client_info => client_info(),
    settings => [setting()],
    stage => query_stage(),
    compression => compression_mode(),
    secret => binary(),
    parameters => [{Key :: binary(), Value :: binary()}]
}.

-type column_type() :: binary().
-type column_values() :: [term()].

-type column_data() :: #{
    name => binary(),
    type => column_type(),
    data => column_values()
}.

-type block_info() :: #{
    is_overflows => boolean(),
    bucket_num => integer()
}.

-type data_block() :: #{
    info => block_info(),
    columns => non_neg_integer(),
    rows => non_neg_integer(),
    column_data => [column_data()]
}.

-type column_metadata() :: #{
    name => binary(),
    type => binary()
}.

-type row_data() :: [term()].

-type query_statistics() :: #{
    rows_read => non_neg_integer(),
    bytes_read => non_neg_integer(),
    elapsed_time => non_neg_integer()
}.

-type query_result() :: #{
    columns => [column_metadata()],
    rows => [row_data()],
    statistics => query_statistics()
}.

%% Query request type for API
-type query_request() :: #{
    sql => binary(),
    query_id => binary() | undefined,
    settings => settings_input(),
    parameters => [{binary(), binary()}],
    timeout => timeout()
}.

%% Query state management records
-record(query_state, {
    query_id :: binary(),
    query_ref :: reference(),
    caller :: {pid(), term()},
    start_time :: integer(),
    timeout :: timeout(),
    result_accumulator :: result_accumulator(),
    column_metadata :: [column_metadata()] | undefined,
    cancelled :: boolean()
}).

-record(result_accumulator, {
    columns :: [column_metadata()],
    rows :: [row_data()],
    total_rows :: non_neg_integer(),
    statistics :: query_statistics()
}).

-type query_state() :: #query_state{}.
-type result_accumulator() :: #result_accumulator{}.

-type client_hello_info() :: #{
    client_name => string(),
    version_major => non_neg_integer(),
    version_minor => non_neg_integer(),
    protocol_version => non_neg_integer(),
    database => string(),
    username => string(),
    password => string()
}.

-type server_exception_error() :: {server_exception, exception_info()}.

-type exception_parsing_error() ::
    {exception_parsing_error, Details :: string()}
    | {nested_exception_limit_exceeded, Depth :: integer()}
    | {exception_field_truncated, Field :: atom(), Length :: non_neg_integer(),
        MaxLength :: non_neg_integer()}
    | {invalid_exception_format, Details :: string()}
    | {protocol_violation, Details :: string()}
    | {invalid_field_order, Expected :: atom(), Found :: atom()}
    | {invalid_integer_encoding, Field :: atom(), Details :: string()}
    | {invalid_string_encoding, Field :: atom(), Details :: string()}.
