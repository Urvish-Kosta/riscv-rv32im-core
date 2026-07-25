/* bench_matmul.c -- 16x16 integer matrix multiply. Multiply-heavy: exercises
 * the multi-cycle MDU inside a nested-loop structure.
 */
#include "bench.h"
#include "expected.h"
#define M 16
static i32 a[M][M], b[M][M], c[M][M];

int main(void) {
    u32 st = 0xC0FFEEu;
    for (int i = 0; i < M; i++)
        for (int j = 0; j < M; j++) {
            a[i][j] = (i32)(rnd_next(&st) & 0xFF) - 128;
            b[i][j] = (i32)(rnd_next(&st) & 0xFF) - 128;
        }
    for (int i = 0; i < M; i++)
        for (int j = 0; j < M; j++) {
            i32 s = 0;
            for (int k = 0; k < M; k++) s += a[i][k] * b[k][j];
            c[i][j] = s;
        }
    u32 chk = 0;
    for (int i = 0; i < M; i++)
        for (int j = 0; j < M; j++) chk = chk * 31u + (u32)c[i][j];
    return (chk == EXPECT_CHK_MM) ? 0 : 1;
}
