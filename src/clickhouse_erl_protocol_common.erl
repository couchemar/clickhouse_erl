-module(clickhouse_erl_protocol_common).

-export([format_decode_error/1]).

%% @doc Format decode error for better error messages
-spec format_decode_error(term()) -> string().
format_decode_error(truncated_varint) ->
    "Truncated varint in message";
format_decode_error(varint_overflow) ->
    "Varint overflow - value too large";
format_decode_error(truncated_string) ->
    "Truncated string in message";
format_decode_error(invalid_utf8) ->
    "Invalid UTF-8 encoding in string";
format_decode_error(incomplete_utf8) ->
    "Incomplete UTF-8 sequence in string";
format_decode_error({badmatch, _}) ->
    "Unexpected data format in message";
format_decode_error(Reason) ->
    io_lib:format("~p", [Reason]).
