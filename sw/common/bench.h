/* bench.h -- freestanding helpers for the benchmark kernels.
 *
 * There is no libc in this environment, so the few routines the kernels need
 * are provided here. They are deliberately simple and are themselves part of
 * what the benchmarks exercise.
 */
#ifndef BENCH_H
#define BENCH_H

typedef unsigned int   u32;
typedef signed   int   i32;
typedef unsigned short u16;
typedef unsigned char  u8;

static inline void *bmemset(void *d, int c, unsigned n) {
    u8 *p = (u8 *)d;
    while (n--) *p++ = (u8)c;
    return d;
}

static inline void *bmemcpy(void *d, const void *s, unsigned n) {
    u8 *dp = (u8 *)d; const u8 *sp = (const u8 *)s;
    while (n--) *dp++ = *sp++;
    return d;
}

static inline unsigned bstrlen(const char *s) {
    unsigned n = 0;
    while (s[n]) n++;
    return n;
}

/* Deterministic 32-bit PRNG (xorshift) so benchmark inputs are reproducible
   without needing any host support. */
static inline u32 rnd_next(u32 *state) {
    u32 x = *state;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    *state = x;
    return x;
}

#endif /* BENCH_H */
