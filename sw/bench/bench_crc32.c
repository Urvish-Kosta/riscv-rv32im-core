/* bench_crc32.c -- CRC-32 (IEEE 802.3, reflected) over a generated buffer.
 * Bit-manipulation and branch heavy; no multiply. Self-checking.
 */
#include "bench.h"
#include "expected.h"
#define N 1024
static u8 buf[N];

static u32 crc32(const u8 *p, unsigned n) {
    u32 crc = 0xFFFFFFFFu;
    for (unsigned i = 0; i < n; i++) {
        crc ^= p[i];
        for (int b = 0; b < 8; b++)
            crc = (crc >> 1) ^ (0xEDB88320u & (u32)(-(i32)(crc & 1)));
    }
    return ~crc;
}

int main(void) {
    u32 st = 0x12345678u;
    for (unsigned i = 0; i < N; i++) buf[i] = (u8)(rnd_next(&st) >> 24);
    return (crc32(buf, N) == EXPECT_CRC) ? 0 : 1;
}
