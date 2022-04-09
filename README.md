# YARVI2

YARVI2 is RISC-V implementation in rapid development.  The original,
YARVI, was the first non-Berkely freely available RISC-V softcore
implementation.  YARVI2 is a complete rewrite for better performance.


## Status

- RV32I implemented and tested (regress with `make test` and `make comply`)
- Bimodal branch predictor, jump, call, and return address predictor
- Current performance on a Lattice Semi ECP5 85F, speed grade 6 (as per `make fmax ipc`):
   - 61.8 MHz (128/128 KiB configuration)
   - 0.844 instructions/cycle (on Dhrystones)
   - 99.9 Dhrystones MIPS

## Coming soon

Expect more performance, more features

High priority:
- path sensitive branch prediction (IPC)
- continuous timing improvement (Fmax)
- converting data memories to caches + external memory interface (features)

Planned:
- multiplier and atomics (RV32AMI)

Considering
- virtual memory
- 64-bit (RV64)
- compressed instructions (RV-C)
and much more
