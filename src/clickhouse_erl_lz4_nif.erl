%% @doc LZ4 compression NIF wrapper for ClickHouse native protocol.
%% Minimal NIF wrapper around official lz4 library.
-module(clickhouse_erl_lz4_nif).

%% API exports
-export([compress/1, compress_hc/2, decompress/2]).
-export([load/0]).

-on_load(init/0).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Compress data using standard LZ4 (fast mode).
-spec compress(binary()) -> {ok, binary()} | {error, term()}.
compress(_Data) ->
    erlang:nif_error({nif_not_loaded, ?MODULE}).

%% @doc Compress data using LZ4HC with compression level (0-12).
-spec compress_hc(binary(), 0..12) -> {ok, binary()} | {error, term()}.
compress_hc(_Data, _Level) ->
    erlang:nif_error({nif_not_loaded, ?MODULE}).

%% @doc Decompress LZ4 data with known original size.
-spec decompress(binary(), pos_integer()) -> {ok, binary()} | {error, term()}.
decompress(_CompressedData, _OriginalSize) ->
    erlang:nif_error({nif_not_loaded, ?MODULE}).

%% @doc Explicitly load the NIF (called automatically via on_load).
-spec load() -> ok | {error, term()}.
load() ->
    SoName =
        case code:priv_dir(clickhouse_erl) of
            {error, bad_name} ->
                case filelib:is_dir(filename:join(["..", priv])) of
                    true ->
                        filename:join(["..", priv, clickhouse_erl_lz4_nif]);
                    false ->
                        filename:join([priv, clickhouse_erl_lz4_nif])
                end;
            Dir ->
                filename:join(Dir, clickhouse_erl_lz4_nif)
        end,
    erlang:load_nif(SoName, 0).

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @doc Initialize NIF on module load.
-spec init() -> ok | {error, term()}.
init() ->
    load().
