# YARVI2

YARVI2 is an FPGA-focused in-order scalar RISC-V softcore with branch
prediction.  The original, YARVI, was the first non-Berkely freely
available RISC-V softcore implementation.  YARVI2 is a complete
rewrite for better performance.

YARVI2 is free and open hardware licensed under the
[ISC license](http://en.wikipedia.org/wiki/ISC_license)
(a license that is similar in terms to the MIT license or the 2-clause
BSD license).


## Status

- RV32I implemented and tested (regress with `make comply test`)

- Eight stage pipeline

- YAGS branch predictor, jump, call, and return address predictor

- Current performance

   - 98.1 Dhrystones MIPS
   - 0.904 instructions/cycle (on Dhrystones)

   On a Lattice Semi ECP5 85F, speed grade 6 (as per `make fmax ipc`):
   - 56.6 MHz (128/128 KiB configuration)

   On an Altera Cyclone-V A9 C8
   - 100+ MHz (128/128 KiB configuration)

- loads have a two cycle latency and use will stall as needed (known
  as a load-use hazard)

- loads that execute before a prior store to the same address has
  completed will be restarted (known as a load-hit-store hazard, has a
  7 cycle penalty, needs two instruction separation to avoid)

## Pipeline details

We have eight stages:
```

                          result forwarding
                        v---+----+----+----+

 s0   s1    s2    s3   s4   s5   s6   s7   s8
 PC | IF1 | IF2 | RF | DE | EX | CM | WB | -

  ^--- stall -----/
  ^----- pipeline restarts ------/
```

Showing the data loop and the two control loops.  There is a 7 cycle
mispredict penalty, same for load-hit-store.  Load has a 2 cycle
latency and can incur up to 2 stall cycles.

- PC: PC generation/branch prediction
- IF1: start instruction fetch
- IF2: register fetched instruction
- RF: read registers (and pre-decode)
- DE: decode instruction and forward registers from later stages
- EX: execute ALU instruction, compute branch conditions, load/store address
- CM: Commit to the instruction or restart, start memory load
- WB: write rf, store to memory,
    load way selection and data alignment/sign-extension

S8 isn't really a stage, but as we read registers in s3 any writes
happening in s7 wouldn't be visible yet so we'll have to forward from
s8.

Currently the pipeline can be restarted (and flushed) only from s6 and
causes the clear of all valid bits.

The pipeline might be invalidated or restarted for several reasons:
 - fetch mispredicted a branch and fed us the wrong instructions.
 - we need a value that is still being loaded from memory
 - instruction traps, like misaligned loads/stores
 - interrupts (which are taken in CM)

## Coming soon

Expect more performance, more features

High priority:
- continuous timing improvement (Fmax)
- converting data memories to caches + external memory interface (features)

Planned:
- multiplier and atomics (RVAM)

Considering:
- virtual memory
- 64-bit (RV64)
- compressed instructions (RVC)
- floating point (RVFD)

and more
