# Result bus restructure

Each execution unit gets its own result bus and its own completion-queue (CQ)
finish port, as UM 6.3.3 describes. This removes dynamic port steering from
the post-execute cone and is the prerequisite for dispatching straight into
the unit input registers (TD-02, step B below).

## Current steering

With the pipelined load/store unit (`ENABLE_LSU_PIPE`, the MiSTer
configuration) two GPR finish ports are shared by four producers:

| Port | Capability | Producers, by priority |
|---|---|---|
| 0 | full: faults, CR fields, XER, update | LSU load; else SPECIAL or IU (registered `special_result_select`) |
| 1 | no fault, CR0/CA/OV/SO only | SRU; else SPECIAL or IU when a load holds port 0 |
| 2 | no register write | LSU store |

The selection terms (`lsu_port0`, `special_port1_sel`, `cq_iu_port1_offer`,
`iu_offer_ready`) feed the CQ wake outputs, then rename forwarding, the
station snoops and the LSU P1 base/data snoop. When a load holds port 0 and
the SRU holds port 1, the IU result waits a cycle. Without the LSU pipe there
is no load result on port 0, so the ports are already fixed per unit.

FP arithmetic has no GPR result: its CQ entry allocates finished and the
head waits on the FPU's ordered result FIFO. FP loads finish on the LSU or
SPECIAL port.

## New structure

One fixed bus per unit; payload selects are constants or registered state.

| Port | Unit | Capability |
|---|---|---|
| 0 | IU, SPECIAL | full (unchanged) |
| 1 | SRU | no fault, CR0/CA/OV/SO (unchanged) |
| 2 | LSU store | no register write (unchanged) |
| 3 | LSU load | full, plus the load-retire terms now on port 0 |

IU and SPECIAL share port 0 without arbitration: a SPECIAL op dispatches only
into an idle IU and blocks dispatch until it finishes, so the two are never
valid together and registered `special_result_select` steers the payload.
Port 3 is tied off without the LSU pipe and synthesises away. Every wake
consumer (rename, IU and SRU stations, LSU P1, SRU store-data snoop) gains a
third wake input. The IU never waits on another unit's result.

## Wake validity without cancel

A wake needs only its producer's own offer and CQ ownership (active, not
done, exact generation); it carries no recovery-kill or unit-cancel term.
This is safe because a recovery removes a contiguous younger suffix of the
CQ, and every consumer of a producer is younger than it:

- Stations, the IU/SRU input registers, LSU P1 and SPECIAL are cancelled by
  the same accepted kill vector (`rs_cancel`, `sru_rs_cancel`, `special_kill`
  and the LSU kill compare producer index and generation), so any consumer
  that sees a killed producer's wake dies on that edge.
- Rename rebuilds `valid`, `ready` and the map from CQ survivors on an
  accepted recovery; a killed producer's slot is not rebuilt, so its payload
  write is harmless. `owners` changes only on allocation, which recovery
  blocks.
- `redirect_kill_o` is zero unless a recovery is accepted, so an unaccepted
  redirect never drops a wake.

The CQ keeps the kill term in its own `done_q`/packet update only, where the
finish and the clear meet on one edge.

## Register files

Result buses write only rename slots; the architectural GPR file is written
at retirement through its existing ports (one, or two with dual dispatch), so
its write-port count is unchanged. The rename array gains a third payload
write port (five 32-bit slots in flops) and one more producer compare per slot.

## Area estimate

Order of magnitude, before a fit:

| Item | ALMs |
|---|---|
| CQ full finish port 3 (five-entry merge legs, fault capsule) | 300–400 |
| Rename: compare per slot, value leg per read port (six) | 150–250 |
| IU and SRU stations: snoop and select leg per operand | 150 |
| LSU P1 base/data snoop | 80 |
| Removed steering muxes | −50 |

About 600–850 ALMs, under 2 % of the device.

## Step B outline

1. Dispatch writes operands straight into the unit input register when ready
   (the station becomes the hold path for operands still waiting), so the
   ALU computes in E = D+1 as the manual's adjacent-stage reading.
2. Register every unit result at the end of E; the fixed buses carry flops,
   so wake, CR→branch, rename update and retire start from registers.
3. Feed-forward to a dependent in the next cycle comes from the registered
   bus; manual cycle counts hold without a combinational chain off the ALU.
4. Update TD-02 and the stage-timing checks to D, E=D+1, F=E+1 with the
   registered result; record the cycle deltas.
