/* bench_sort.c -- insertion sort of a pseudo-random array. Data-dependent
 * inner-loop branches: the hardest case for a branch predictor here.
 */
#include "bench.h"
#include "expected.h"
#define N 256
static u32 arr[N];

int main(void) {
    u32 st = 0xABCDEF01u;
    for (int i = 0; i < N; i++) arr[i] = rnd_next(&st) & 0xFFFF;
    for (int i = 1; i < N; i++) {
        u32 key = arr[i]; int j = i - 1;
        while (j >= 0 && arr[j] > key) { arr[j + 1] = arr[j]; j--; }
        arr[j + 1] = key;
    }
    for (int i = 1; i < N; i++) if (arr[i - 1] > arr[i]) return 1;   /* sorted? */
    u32 chk = 0;
    for (int i = 0; i < N; i++) chk = chk * 33u + arr[i];
    return (chk == EXPECT_CHK_SO) ? 0 : 2;
}
