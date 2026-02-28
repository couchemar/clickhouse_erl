/*
 * LZ4 NIF wrapper for ClickHouse Erlang client
 * Minimal wrapper around official lz4 library
 */

#include <erl_nif.h>
#include <lz4.h>
#include <lz4hc.h>
#include <string.h>

/* Compress data using standard LZ4 */
static ERL_NIF_TERM
compress_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    ErlNifBinary input, output;
    int max_output_size, compressed_size;

    if (!enif_inspect_binary(env, argv[0], &input)) {
        return enif_make_badarg(env);
    }

    /* Calculate maximum output size */
    max_output_size = LZ4_compressBound(input.size);
    if (max_output_size == 0) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "input_too_large"));
    }

    /* Allocate output buffer */
    if (!enif_alloc_binary(max_output_size, &output)) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "alloc_failed"));
    }

    /* Compress */
    compressed_size = LZ4_compress_default(
        (const char*)input.data,
        (char*)output.data,
        input.size,
        max_output_size
    );

    if (compressed_size <= 0) {
        enif_release_binary(&output);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "compression_failed"));
    }

    /* Resize to actual compressed size */
    if (!enif_realloc_binary(&output, compressed_size)) {
        enif_release_binary(&output);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "realloc_failed"));
    }

    return enif_make_tuple2(env,
        enif_make_atom(env, "ok"),
        enif_make_binary(env, &output));
}

/* Compress data using LZ4HC with compression level */
static ERL_NIF_TERM
compress_hc_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    ErlNifBinary input, output;
    int max_output_size, compressed_size, level;

    if (!enif_inspect_binary(env, argv[0], &input)) {
        return enif_make_badarg(env);
    }

    if (!enif_get_int(env, argv[1], &level)) {
        return enif_make_badarg(env);
    }

    if (level < 0 || level > 12) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "invalid_level"));
    }

    /* Calculate maximum output size */
    max_output_size = LZ4_compressBound(input.size);
    if (max_output_size == 0) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "input_too_large"));
    }

    /* Allocate output buffer */
    if (!enif_alloc_binary(max_output_size, &output)) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "alloc_failed"));
    }

    /* Compress with HC */
    compressed_size = LZ4_compress_HC(
        (const char*)input.data,
        (char*)output.data,
        input.size,
        max_output_size,
        level
    );

    if (compressed_size <= 0) {
        enif_release_binary(&output);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "compression_failed"));
    }

    /* Resize to actual compressed size */
    if (!enif_realloc_binary(&output, compressed_size)) {
        enif_release_binary(&output);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "realloc_failed"));
    }

    return enif_make_tuple2(env,
        enif_make_atom(env, "ok"),
        enif_make_binary(env, &output));
}

/* Decompress LZ4 data with known original size */
static ERL_NIF_TERM
decompress_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    ErlNifBinary input, output;
    int original_size, decompressed_size;

    if (!enif_inspect_binary(env, argv[0], &input)) {
        return enif_make_badarg(env);
    }

    if (!enif_get_int(env, argv[1], &original_size)) {
        return enif_make_badarg(env);
    }

    if (original_size <= 0) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "invalid_size"));
    }

    /* Allocate output buffer */
    if (!enif_alloc_binary(original_size, &output)) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "alloc_failed"));
    }

    /* Decompress */
    decompressed_size = LZ4_decompress_safe(
        (const char*)input.data,
        (char*)output.data,
        input.size,
        original_size
    );

    if (decompressed_size < 0) {
        enif_release_binary(&output);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "decompression_failed"));
    }

    if (decompressed_size != original_size) {
        enif_release_binary(&output);
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_atom(env, "size_mismatch"));
    }

    return enif_make_tuple2(env,
        enif_make_atom(env, "ok"),
        enif_make_binary(env, &output));
}

static ErlNifFunc nif_funcs[] = {
    {"compress", 1, compress_nif, 0},
    {"compress_hc", 2, compress_hc_nif, 0},
    {"decompress", 2, decompress_nif, 0}
};

ERL_NIF_INIT(clickhouse_erl_lz4_nif, nif_funcs, NULL, NULL, NULL, NULL)
