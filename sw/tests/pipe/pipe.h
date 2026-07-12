/* pipe.h -- helpers for hazard-free pipeline tests (M2).
 * P inserts 3 NOPs so a dependent instruction is >= 3 after its producer,
 * which is the spacing the M2 pipeline needs with no forwarding/stalls.
 */
#ifndef PIPE_H
#define PIPE_H
#define P nop; nop; nop
#endif
