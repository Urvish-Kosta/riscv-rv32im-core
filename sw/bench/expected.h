/* expected.h -- golden results for the benchmark kernels.
 *
 * These constants were derived independently of the core: each kernel was
 * mirrored in Python on the host and its result computed there (see the
 * derivation in docs/benchmarks.md). They are the oracle that makes every
 * benchmark self-checking -- a performance number is only reported for a run
 * that produced the correct architectural result.
 */
#ifndef EXPECTED_H
#define EXPECTED_H
#define EXPECT_CRC    0x0ca3f083u
#define EXPECT_COUNT  303u
#define EXPECT_SUM    277050u
#define EXPECT_CHK_MM 0xe959107du
#define EXPECT_CHK_SO 0x069c220du
#define EXPECT_FIB    2584u
#endif
