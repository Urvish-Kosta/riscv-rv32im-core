/* bench_fib.c -- naive recursive Fibonacci: call/return dominated, so it
 * stresses JALR (function return) prediction and the stack path.
 */
#include "bench.h"
#include "expected.h"
static u32 fib(u32 n) { return (n < 2) ? n : fib(n - 1) + fib(n - 2); }
int main(void) { return (fib(18) == EXPECT_FIB) ? 0 : 1; }
