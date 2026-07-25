/* bench_sieve.c -- Sieve of Eratosthenes below N; checks the prime count and
 * a checksum of the primes. Byte memory traffic + data-dependent branches.
 */
#include "bench.h"
#include "expected.h"
#define N 2000
static u8 composite[N];

int main(void) {
    bmemset(composite, 0, N);
    unsigned count = 0; u32 sum = 0;
    for (unsigned i = 2; i < N; i++) {
        if (!composite[i]) {
            count++; sum += i;
            for (unsigned j = i * i; j < N; j += i) composite[j] = 1;
        }
    }
    if (count != EXPECT_COUNT) return 1;
    if (sum != EXPECT_SUM) return 2;
    return 0;
}
