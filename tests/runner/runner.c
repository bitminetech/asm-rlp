/*
 * asm-rlp vector runner. Test code: the library itself is assembly.
 *
 * Usage: runner VECTOR_DIR FILE ...
 *
 * Reads the case files that tests/generator/ writes (format in its README),
 * calls the library for every case and compares the results. It exits with
 * status 0 only when every case of every file passes.
 *
 * Every buffer is allocated at the exact size the case needs, with guard
 * bytes after it, and output buffers start filled with 0xA5, so a write out of
 * bounds or a read of old output contents shows up as a failure.
 *
 * Every library call goes through abi_call (tests/runner/abi_<ISA>.s). The
 * runner prints the most stack each function used, and fails when a call uses
 * more than the README cap or changes state that the ABI says it must keep.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32) && defined(__x86_64__)
#define RLP_ABI __attribute__((sysv_abi))
#else
#define RLP_ABI
#endif

/* C view of include/rlp.inc and docs/reference/rlp.md. */
RLP_ABI uint64_t rlp_decode(const void *encoded, void *items);
RLP_ABI uint64_t rlp_encode_size(const void *items, const void *data, void *scratch, void *size);
RLP_ABI uint64_t rlp_encode(const void *items, const void *data, void *scratch, void *encoded);

enum { RLP_OK = 0, RLP_BUFFER_TOO_SMALL = 1 };
enum { KIND_BYTES = 1, KIND_LIST = 2 };

#define GUARD 64
#define FILL 0xA5

/*
 * ABI and stack check. abi_call sets every register the callee must keep to a
 * known value and paints PAINT_BYTES of stack below the call. Afterwards it
 * reports the kept state that changed, and the bytes of stack the call used,
 * its return address included on x86-64.
 */
#define STACK_CAP 128 /* README: stack per call */
#define PAINT_BYTES (STACK_CAP + 4096)

/* The record that abi_call reads and writes. The layout is in README.md. */
typedef struct {
    uint64_t fn, arg[5], paint, status, fault, stack, scratch[4];
} abi_ctx;
RLP_ABI void abi_call(abi_ctx *ctx);

enum { F_DECODE, F_ENCODE_SIZE, F_ENCODE, F_COUNT };
static const char *const fn_name[F_COUNT] = {"rlp_decode", "rlp_encode_size", "rlp_encode"};
static uint64_t stack_peak[F_COUNT], stack_calls[F_COUNT], abi_fault[F_COUNT];

/* The functions that the cases of each file kind test, and the files that tested each function. */
static const int kind_tests[3][F_COUNT] = {{0}, {1, 1, 1}, {1, 0, 0}};
static uint64_t fn_files[F_COUNT], fn_failed_files[F_COUNT];

/* Call the library function f with its pointer arguments, through abi_call. */
static uint64_t checked_call(int fn, uint64_t f, const void *const *args, size_t n) {
    abi_ctx c;
    memset(&c, 0, sizeof c);
    c.fn = f;
    for (size_t i = 0; i < n; i++) c.arg[i] = (uint64_t)(uintptr_t)args[i];
    c.paint = PAINT_BYTES;
    abi_call(&c);
    if (c.stack > stack_peak[fn]) stack_peak[fn] = c.stack;
    stack_calls[fn]++;
    abi_fault[fn] |= c.fault;
    return c.status;
}

#define CALL(fn, f, ...)                                                                                       \
    checked_call(fn, (uint64_t)(uintptr_t)(f), (const void *const[]){__VA_ARGS__},                             \
                 sizeof((const void *const[]){__VA_ARGS__}) / sizeof(const void *))

static uint64_t rd64(const uint8_t *p) {
    uint64_t v = 0;
    for (int i = 7; i >= 0; i--) v = (v << 8) | p[i];
    return v;
}

static void wr64(uint8_t *p, uint64_t v) {
    for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (8 * i));
}

typedef struct {
    const uint8_t *p, *end;
    const char *file;
} cursor;

static const uint8_t *take(cursor *c, uint64_t n) {
    if ((uint64_t)(c->end - c->p) < n) {
        fprintf(stderr, "%s: file ends early\n", c->file);
        exit(2);
    }
    const uint8_t *r = c->p;
    c->p += n;
    return r;
}

static uint64_t take64(cursor *c) { return rd64(take(c, 8)); }

/* A buffer of n bytes, 8-aligned, filled, with GUARD guard bytes after it. */
static uint8_t *buffer(uint64_t n) {
    uint8_t *b = malloc((size_t)(n + GUARD));
    if (!b) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    memset(b, FILL, (size_t)(n + GUARD));
    return b;
}

static int guard_ok(const uint8_t *b, uint64_t n) {
    for (uint64_t i = 0; i < GUARD; i++)
        if (b[n + i] != FILL) return 0;
    return 1;
}

/* A ByteList holding len bytes at offset off, with room spare bytes after them. */
static uint8_t *bytelist(const uint8_t *bytes, uint64_t len, uint64_t off, uint64_t room, uint64_t *size) {
    *size = off + len + room;
    uint8_t *b = buffer(*size);
    wr64(b, *size);
    wr64(b + 8, off);
    wr64(b + 16, len);
    memcpy(b + off, bytes, (size_t)len);
    return b;
}

/* An Items value of n records, with only its size field set. */
static uint8_t *items_buffer(uint64_t n, uint64_t *size) {
    *size = 24 + 32 * n;
    uint8_t *b = buffer(*size);
    wr64(b, *size);
    return b;
}

static uint8_t *scratch_buffer(uint64_t n, uint64_t *size) {
    *size = 8 + 8 * n;
    uint8_t *b = buffer(*size);
    wr64(b, *size);
    return b;
}

static char why_text[160];

/* Encode items over data and compare with enc. Returns 1 on a match. */
static int check_encode(const uint8_t *items, uint64_t n, const uint8_t *data, const uint8_t *enc, uint64_t len,
                        const char *variant, const char **why) {
    uint64_t ssize, size = 0, st;
    uint8_t *scr = scratch_buffer(n, &ssize);
    int ok = 0;
    st = CALL(F_ENCODE_SIZE, rlp_encode_size, items, data, scr, &size);
    if (st != RLP_OK) snprintf(why_text, sizeof why_text, "%s: encode_size status %llu", variant, (unsigned long long)st);
    else if (size != 24 + len) snprintf(why_text, sizeof why_text, "%s: encode_size gave %llu, expected %llu", variant,
                                        (unsigned long long)size, (unsigned long long)(24 + len));
    else if (!guard_ok(scr, ssize)) snprintf(why_text, sizeof why_text, "%s: encode_size wrote past scratch", variant);
    else {
        uint8_t *out = buffer(size);
        wr64(out, size);
        st = CALL(F_ENCODE, rlp_encode, items, data, scr, out);
        if (st != RLP_OK) snprintf(why_text, sizeof why_text, "%s: encode status %llu", variant, (unsigned long long)st);
        else if (rd64(out) != size || rd64(out + 8) != 24 || rd64(out + 16) != len)
            snprintf(why_text, sizeof why_text, "%s: encode header", variant);
        else if (memcmp(out + 24, enc, (size_t)len)) snprintf(why_text, sizeof why_text, "%s: encode bytes", variant);
        else if (!guard_ok(out, size) || !guard_ok(scr, ssize))
            snprintf(why_text, sizeof why_text, "%s: encode wrote out of bounds", variant);
        else ok = 1;
        free(out);
    }
    free(scr);
    if (!ok) *why = why_text;
    return ok;
}

/* The capacity checks: one byte or one record short gives RLP_BUFFER_TOO_SMALL. */
static int check_small(const uint8_t *items, uint64_t n, const uint8_t *data, uint64_t len, const char **why) {
    uint64_t ssize, size = 0, st;
    uint8_t *scr = scratch_buffer(n - 1, &ssize);
    st = CALL(F_ENCODE_SIZE, rlp_encode_size, items, data, scr, &size);
    if (st != RLP_BUFFER_TOO_SMALL) *why = "encode_size with a short scratch did not refuse";
    else if (!guard_ok(scr, ssize)) *why = "encode_size wrote past a short scratch";
    else {
        uint64_t osize = 24 + len;
        uint8_t *out = buffer(osize);
        wr64(out, osize);
        st = CALL(F_ENCODE, rlp_encode, items, data, scr, out);
        if (st != RLP_BUFFER_TOO_SMALL) *why = "encode with a short scratch did not refuse";
        else if (!guard_ok(scr, ssize) || !guard_ok(out, osize)) *why = "encode wrote past a short scratch";
        free(out);
    }
    free(scr);
    if (*why) return 0;

    scr = scratch_buffer(n, &ssize);
    uint64_t osize = 24 + len - 1;
    uint8_t *out = buffer(osize);
    wr64(out, osize);
    st = CALL(F_ENCODE, rlp_encode, items, data, scr, out);
    if (st != RLP_BUFFER_TOO_SMALL) *why = "encode with a short output did not refuse";
    else if (!guard_ok(out, osize) || !guard_ok(scr, ssize)) *why = "encode wrote past a short output";
    free(out);
    free(scr);
    return *why == NULL;
}

static int run_valid(const uint8_t *enc, uint64_t len, const uint8_t *want, uint64_t n, const char **why) {
    uint64_t esize, isize;
    uint8_t *bl = bytelist(enc, len, 32, 7, &esize);
    uint8_t *items = items_buffer(n, &isize);
    int ok = 0;
    uint64_t st = CALL(F_DECODE, rlp_decode, bl, items);
    if (st != RLP_OK) {
        snprintf(why_text, sizeof why_text, "decode status %llu", (unsigned long long)st);
        *why = why_text;
    } else if (rd64(items) != isize || rd64(items + 8) != 24 || rd64(items + 16) != n) *why = "decode header";
    else if (memcmp(items + 24, want, (size_t)(32 * n))) *why = "decode records";
    else if (!guard_ok(items, isize) || !guard_ok(bl, esize)) *why = "decode wrote out of bounds";
    else ok = 1;

    /* One record short. */
    if (ok) {
        uint64_t ssize;
        uint8_t *small = items_buffer(n - 1, &ssize);
        st = CALL(F_DECODE, rlp_decode, bl, small);
        if (st != RLP_BUFFER_TOO_SMALL) ok = 0, *why = "decode with one record short did not refuse";
        else if (!guard_ok(small, ssize)) ok = 0, *why = "decode wrote past a short value";
        free(small);
    }

    /* Encode the decoded records over the encoding itself. */
    if (ok) ok = check_encode(items, n, bl, enc, len, "same data", why);
    if (ok) ok = check_small(items, n, bl, len, why);

    /*
     * Encode again from a different layout: records at offset 32, each byte
     * string's bytes copied to a new place with gaps, and junk in the offset
     * and length of every list, which encode must not read.
     */
    if (ok) {
        uint64_t payload = 0;
        for (uint64_t i = 0; i < n; i++)
            if (rd64(want + 32 * i) == KIND_BYTES) payload += rd64(want + 32 * i + 16) + 3;
        uint64_t dsize;
        uint8_t *data = bytelist(NULL, 0, 40, payload, &dsize);
        wr64(data + 16, payload);
        uint64_t vsize = 32 + 32 * n;
        uint8_t *value = buffer(vsize);
        wr64(value, vsize);
        wr64(value + 8, 32);
        wr64(value + 16, n);
        uint64_t at = 0;
        for (uint64_t i = 0; i < n; i++) {
            const uint8_t *r = want + 32 * i;
            uint8_t *w = value + 32 + 32 * i;
            memcpy(w, r, 32);
            if (rd64(r) == KIND_BYTES) {
                uint64_t l = rd64(r + 16);
                memcpy(data + 40 + at + 3, enc + rd64(r + 8), (size_t)l);
                memset(data + 40 + at, 0xEE, 3);
                wr64(w + 8, at + 3);
                at += l + 3;
            } else {
                wr64(w + 8, 0xDEADBEEFDEADBEEFULL);
                wr64(w + 16, 0xFEEDFACEFEEDFACEULL);
            }
        }
        ok = check_encode(value, n, data, enc, len, "other layout", why);
        free(value);
        free(data);
    }
    free(items);
    free(bl);
    return ok;
}

static int run_reject(const uint8_t *enc, uint64_t len, uint64_t want, const char **why) {
    uint64_t esize, isize;
    uint8_t *bl = bytelist(enc, len, 24, 0, &esize);
    uint8_t *items = items_buffer(len ? len : 1, &isize);
    uint64_t st = CALL(F_DECODE, rlp_decode, bl, items);
    int ok = 0;
    if (st != want) {
        snprintf(why_text, sizeof why_text, "decode status %llu, expected %llu", (unsigned long long)st,
                 (unsigned long long)want);
        *why = why_text;
    } else if (!guard_ok(items, isize) || !guard_ok(bl, esize)) *why = "decode wrote out of bounds";
    else ok = 1;
    free(items);
    free(bl);
    return ok;
}

static uint8_t *read_file(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *data = malloc(n > 0 ? (size_t)n : 1);
    if (!data || fread(data, 1, (size_t)n, f) != (size_t)n) {
        fclose(f);
        free(data);
        return NULL;
    }
    fclose(f);
    *len = (size_t)n;
    return data;
}

static int run_file(const char *dir, const char *name) {
    char path[4096];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    size_t len = 0;
    uint8_t *data = read_file(path, &len);
    if (!data) {
        fprintf(stderr, "%s: cannot read\n", path);
        return 1;
    }
    cursor c = {data, data + len, name};
    if (memcmp(take(&c, 8), "RLPVEC01", 8) != 0) {
        fprintf(stderr, "%s: wrong magic\n", name);
        exit(2);
    }
    uint64_t kind = take64(&c), ncases = take64(&c), bad = 0;
    if (kind != 1 && kind != 2) {
        fprintf(stderr, "%s: unknown kind\n", name);
        exit(2);
    }
    for (uint64_t k = 0; k < ncases; k++) {
        uint64_t nlen = take64(&c);
        const char *cname = (const char *)take(&c, nlen);
        uint64_t elen = take64(&c);
        const uint8_t *enc = take(&c, elen);
        const char *why = NULL;
        int ok;
        if (kind == 1) {
            uint64_t n = take64(&c);
            ok = run_valid(enc, elen, take(&c, 32 * n), n, &why);
        } else if (kind == 2) {
            ok = run_reject(enc, elen, take64(&c), &why);
        } else {
            fprintf(stderr, "%s: unknown kind\n", name);
            exit(2);
        }
        if (!ok) {
            if (bad < 10) fprintf(stderr, "%s: %.*s: %s\n", name, (int)nlen, cname, why);
            bad++;
        }
    }
    if (c.p != c.end) {
        fprintf(stderr, "%s: bytes left after the last case\n", name);
        exit(2);
    }
    printf("%s %s: %llu cases, %llu failed\n", bad ? "FAIL" : "PASS", name, (unsigned long long)ncases,
           (unsigned long long)bad);
    for (int fn = 0; fn < F_COUNT; fn++) {
        if (!kind_tests[kind][fn]) continue;
        fn_files[fn]++;
        if (bad) fn_failed_files[fn]++;
    }
    free(data);
    return bad != 0;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: runner VECTOR_DIR FILE ...\n");
        return 2;
    }
    int failed = 0;
    for (int i = 2; i < argc; i++) failed |= run_file(argv[1], argv[i]);
    for (int fn = 0; fn < F_COUNT; fn++) {
        if (!stack_calls[fn]) continue;
        int over = stack_peak[fn] > STACK_CAP;
        printf("%s stack %s: %llu bytes, cap %d\n", over ? "FAIL" : "PASS", fn_name[fn],
               (unsigned long long)stack_peak[fn], STACK_CAP);
        failed |= over;
        if (over) fn_failed_files[fn]++;
    }
    for (int fn = 0; fn < F_COUNT; fn++) {
        if (!stack_calls[fn]) continue;
        if (abi_fault[fn])
            printf("FAIL abi %s: kept state changed, mask 0x%016llx\n", fn_name[fn], (unsigned long long)abi_fault[fn]);
        else
            printf("PASS abi %s: kept registers, stack pointer and flags\n", fn_name[fn]);
        failed |= abi_fault[fn] != 0;
        if (abi_fault[fn]) fn_failed_files[fn]++;
    }
    /* One verdict for each function: every file that tests it passed, within the stack cap and the ABI. */
    for (int fn = 0; fn < F_COUNT; fn++)
        printf("FUNCTION %s %s\n", fn_name[fn], fn_files[fn] && !fn_failed_files[fn] ? "PASS" : "FAIL");
    return failed;
}
