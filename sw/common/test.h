/* test.h -- check macros for self-checking directed tests.
 *
 * On mismatch, records the test number in gp and branches to _fail (crt.S),
 * which reports gp as the process exit code. Reserved registers (do not use in
 * test bodies): x1/ra, x3/gp, t5, t6, a0.
 */
#ifndef TEST_H
#define TEST_H

/* Check that register r holds immediate v. */
#define CHECK_I(n, r, v)     li gp, n; li t6, v; bne r, t6, _fail

/* Check that registers r1 and r2 are equal. */
#define CHECK_RR(n, r1, r2)  li gp, n; bne r1, r2, _fail

#endif /* TEST_H */
