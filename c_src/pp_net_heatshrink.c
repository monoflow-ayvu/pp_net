/*
 * Heatshrink source: https://github.com/atomicobject/heatshrink
 * Version: v0.4.1 (commit b9ac05e912e1184b55c5d815b280486de10f331f)
 */
#include <erl_nif.h>
#include <stdint.h>

#include "heatshrink_decoder.h"
#include "heatshrink_encoder.h"

#define WINDOW_SZ2 8
#define LOOKAHEAD_SZ2 4
#define DECODER_INPUT_BUFFER_SIZE 256
#define MIN_OUTPUT_CAPACITY 256

static int allocate_output(ErlNifBinary *output, size_t input_size) {
    size_t capacity = input_size < MIN_OUTPUT_CAPACITY ? MIN_OUTPUT_CAPACITY : input_size;
    return enif_alloc_binary(capacity, output);
}

static int ensure_output_capacity(ErlNifBinary *output, size_t produced) {
    if (produced < output->size) {
        return 1;
    }

    if (output->size > SIZE_MAX / 2) {
        return 0;
    }

    return enif_realloc_binary(output, output->size * 2);
}

static ERL_NIF_TERM make_ok_result(ErlNifEnv *env, ErlNifBinary *output, size_t produced) {
    ERL_NIF_TERM binary;

    if (produced == 0) {
        enif_release_binary(output);
        (void)enif_make_new_binary(env, 0, &binary);
    } else {
        if (produced < output->size && !enif_realloc_binary(output, produced)) {
            enif_release_binary(output);
            return enif_make_atom(env, "error");
        }

        binary = enif_make_binary(env, output);
    }

    return enif_make_tuple2(env, enif_make_atom(env, "ok"), binary);
}

static int drain_encoder(heatshrink_encoder *encoder, ErlNifBinary *output,
        size_t *produced, size_t *round_polled) {
    *round_polled = 0;

    for (;;) {
        size_t polled = 0;
        size_t available;
        HSE_poll_res result;

        if (!ensure_output_capacity(output, *produced)) {
            return 0;
        }

        available = output->size - *produced;
        result = heatshrink_encoder_poll(encoder, output->data + *produced,
            available, &polled);

        if ((result != HSER_POLL_EMPTY && result != HSER_POLL_MORE) || polled > available) {
            return 0;
        }

        *produced += polled;
        *round_polled += polled;

        if (result == HSER_POLL_EMPTY) {
            return 1;
        }

        if (polled == 0) {
            return 0;
        }
    }
}

static int drain_decoder(heatshrink_decoder *decoder, ErlNifBinary *output,
        size_t *produced, size_t *round_polled) {
    *round_polled = 0;

    for (;;) {
        size_t polled = 0;
        size_t available;
        HSD_poll_res result;

        if (!ensure_output_capacity(output, *produced)) {
            return 0;
        }

        available = output->size - *produced;
        result = heatshrink_decoder_poll(decoder, output->data + *produced,
            available, &polled);

        if ((result != HSDR_POLL_EMPTY && result != HSDR_POLL_MORE) || polled > available) {
            return 0;
        }

        *produced += polled;
        *round_polled += polled;

        if (result == HSDR_POLL_EMPTY) {
            return 1;
        }

        if (polled == 0) {
            return 0;
        }
    }
}

static ERL_NIF_TERM encode(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary input;
    ErlNifBinary output;
    heatshrink_encoder *encoder;
    size_t offset = 0;
    size_t produced = 0;
    int previous_finish_was_empty = 0;

    if (argc != 1 || !enif_inspect_binary(env, argv[0], &input)) {
        return enif_make_badarg(env);
    }

    encoder = heatshrink_encoder_alloc(WINDOW_SZ2, LOOKAHEAD_SZ2);
    if (encoder == NULL) {
        return enif_make_atom(env, "error");
    }

    if (!allocate_output(&output, input.size)) {
        heatshrink_encoder_free(encoder);
        return enif_make_atom(env, "error");
    }

    while (offset < input.size) {
        size_t remaining = input.size - offset;
        size_t sunk = 0;
        size_t polled = 0;
        HSE_sink_res sink_result = heatshrink_encoder_sink(encoder,
            input.data + offset, remaining, &sunk);

        if (sink_result != HSER_SINK_OK || sunk > remaining) {
            goto error;
        }

        offset += sunk;

        if (!drain_encoder(encoder, &output, &produced, &polled)) {
            goto error;
        }

        if (offset < input.size && sunk == 0 && polled == 0) {
            goto error;
        }
    }

    for (;;) {
        size_t polled = 0;
        HSE_finish_res finish_result = heatshrink_encoder_finish(encoder);

        if (finish_result == HSER_FINISH_DONE) {
            break;
        }

        if (finish_result != HSER_FINISH_MORE ||
                !drain_encoder(encoder, &output, &produced, &polled)) {
            goto error;
        }

        if (polled == 0) {
            if (previous_finish_was_empty) {
                goto error;
            }
            previous_finish_was_empty = 1;
        } else {
            previous_finish_was_empty = 0;
        }
    }

    heatshrink_encoder_free(encoder);
    return make_ok_result(env, &output, produced);

error:
    heatshrink_encoder_free(encoder);
    enif_release_binary(&output);
    return enif_make_atom(env, "error");
}

static ERL_NIF_TERM decode(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary input;
    ErlNifBinary output;
    heatshrink_decoder *decoder;
    size_t offset = 0;
    size_t produced = 0;
    int previous_finish_was_empty = 0;

    if (argc != 1 || !enif_inspect_binary(env, argv[0], &input)) {
        return enif_make_badarg(env);
    }

    decoder = heatshrink_decoder_alloc(DECODER_INPUT_BUFFER_SIZE,
        WINDOW_SZ2, LOOKAHEAD_SZ2);
    if (decoder == NULL) {
        return enif_make_atom(env, "error");
    }

    if (!allocate_output(&output, input.size)) {
        heatshrink_decoder_free(decoder);
        return enif_make_atom(env, "error");
    }

    while (offset < input.size) {
        size_t remaining = input.size - offset;
        size_t sunk = 0;
        size_t polled = 0;
        HSD_sink_res sink_result = heatshrink_decoder_sink(decoder,
            input.data + offset, remaining, &sunk);

        if ((sink_result != HSDR_SINK_OK && sink_result != HSDR_SINK_FULL) ||
                sunk > remaining) {
            goto error;
        }

        offset += sunk;

        if (!drain_decoder(decoder, &output, &produced, &polled)) {
            goto error;
        }

        if (offset < input.size && sunk == 0 && polled == 0) {
            goto error;
        }
    }

    for (;;) {
        size_t polled = 0;
        HSD_finish_res finish_result = heatshrink_decoder_finish(decoder);

        if (finish_result == HSDR_FINISH_DONE) {
            break;
        }

        if (finish_result != HSDR_FINISH_MORE ||
                !drain_decoder(decoder, &output, &produced, &polled)) {
            goto error;
        }

        if (polled == 0) {
            if (previous_finish_was_empty) {
                goto error;
            }
            previous_finish_was_empty = 1;
        } else {
            previous_finish_was_empty = 0;
        }
    }

    heatshrink_decoder_free(decoder);
    return make_ok_result(env, &output, produced);

error:
    heatshrink_decoder_free(decoder);
    enif_release_binary(&output);
    return enif_make_atom(env, "error");
}

static ErlNifFunc nif_functions[] = {
    {"encode", 1, encode, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"decode", 1, decode, ERL_NIF_DIRTY_JOB_CPU_BOUND}
};

ERL_NIF_INIT(Elixir.PPNet.Heatshrink, nif_functions, NULL, NULL, NULL, NULL)
