# Fundamental Pipeline Control

Assume a pipeline P1 -> P2 -> P3 -> P4

With a continuous flow of data, life is simple and fast.  However,
allowing for disruptions we will qualify outputs of each stage with a
"valid" bit, negation of which means that all outputs should be
treated as invalid, and the stage is producing a bubble.

More complex control is needed and any stage might request that the
pipeline "restart" (say, from a different PC).  A pipeline restart
implies a flush of everything that preceeds the restarting stage, and
may or may not include the stage itself (eg. an illegal instruction
vs. a branch).  Note, when there are competing restart requests, the
oldest (that is, the later stage) must be given priority as the
younger would never have happened without pipelining.

The other classic pipeline control is stalls.  YARVI currently doesn't
use stalls, but stalling vs. restarting is a trade off between cycle
time and IPC; stalling adds another high-fanout control signal that
becomes a critical path, especially when the control decision is
complex.  Restarting generally only touches valid bits and the head
stage, but can incur overhead as the stalled stage is restarted and
propagates through the pipeline.

## The Big Control Question

Can (and should) we factor out some of this pipeline control?

```
P1 -> P2 -> P3

  input p1p2_valid_in
  input p1p2_valid_data_in

  output p2p3_valid_out
  output p2p3_valid_data_out

  output p2p1_restart_out
  output p2p1_restart_data_out



  P1:

  if (p2p1_restart_in)
    p1_data = p2p1_restart_data_in;
  else if (p3p1_restart_in)
    p1_data = p3p1_restart_data_in;

  p1_restart = p2p1_restart_in | p3p1_restart_in;


  P2

  p2p1_restart_out <= 0;
  if (the need arises) begin
    p2p1_restart_out <= 1;
    ....
  end

  p1_restart = p2p1_restart_in | p3p1_restart_in;
    P2(.valid_in(p1_valid_out & !p1_restart)

```
