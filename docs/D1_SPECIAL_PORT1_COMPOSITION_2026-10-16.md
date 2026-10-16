# D1 admission and special port 1 composition

This is a prepared two-cut experiment against accepted `bfd023cf702e653a74a9989856f935bcf971045b`. It includes the D1 admission change from `133dd4c` and only the special-port1 offer changes and adapters from `f2f4162`. It does not include rename payload transposition, CR capture, no-recovery prediction, IU flag, or instruction-page projection changes.

The actual combined core is `c6e1730703054c274fe4f08e79350e1457608d1adeebe2d0c9559444e48bd6a6`; special is `dc1750ae0e67cdd50da76c3903a33ba2e77020f02059ebe7267e93d74c3b6ca0`. The strict portable normalizer checks those whole sources and package `d2f9ebdc165a880507bead0c791f3fdabffc38a2dcef7e98f0338882e61dc7b6` before exposing either proof view. It removes only four special-port1 core fragments to recover D1 core `91c2f994a1abb5b207e7c2d1e91aea494b98a9b78630620851da611be9046a95`. Removing only the eight D1 fragments instead recovers special-port1 core `7d07b701c6c9ef7b372c6df3f021b03f520cbce4dfacafa22670ed2606efea47`. Both inverse orders recover accepted core `8a717edfb0feea9cb3985613ea7e6ec79f8c7d0576e84b55bec3894ed979b8e4`. The special source inverse recovers `1d8c5e51a6ccfc4285b6855c56c7c1b56196766882431afb8b5a9a93b455aef5`.

Before using normalized views, the guard compares actual D1 helper/types, all three calls, 15 bindings, selector, priority, branch, dispatch and rename enables. It also checks the complete actual cancellation block and seven-writer inventory, full arbiter/ready/offer/payload/wake context, complete special instance and unchanged original special result procedure. The special-port1 proof owns the changed complete eligible-offer product. It does not relax readiness, select another payload or permit canceled MMU results on port 1. The D1 proof owns the three admission factors; neither creates state, another hazard authority, or a new pipeline edge.

Source-only preparation passed exact inverses, six composed-source rejection checks, nine D1 source-negative checks and the three original special source-negative checks. All three fixtures remain byte-identical: D1 admission `618cc3c52672d00e3b4ad8ad4b56be233806ee1dcedea69dbadce3cc1db7a820`, D1 composition `a80ba69376cf43db1bc5029ba4d8a44d542e62fa782a8c06736128f85bb27c6a`, and special product `1718f6d1c2391773ad42a84a0f865ad72d380649d5b9fc71aedcd99091846a8c`. These are source-preparation results, not fresh HDL results. Source-rejection checks are distinct from the D1 fixture's three behavioral counterexamples.

Run the optional finite proofs serially:

```sh
make -C sim -j1 test-d1-alignment-admission-equivalence test-special-port1-offer-proof
```

The expected runtime corpora are 851,968 D1 admission/priority observations, 196,608 D1 complete dispatch/rename composition observations and three D1 behavioral counterchecks; the independent special product fixture checks 983,040 four-state observations. Their existing finite opcode, correlated-input and conditional scope limits remain. No whole-core temporal theorem follows from these counts.

The optional special temporal bench is byte-identical to the historical 1,099-packet extension, SHA256 `7f34a6f1d0e8797d6a2daf471c3a4e454b0052a391d7d7f4ee2603016fdf0827`. Its default PORT1_STRESS=0 retains the original program and oracle. The paired profile uses DW2/LSU1 and the normal unique-initialization wrapper:

```sh
OBJCACHE= make -C sim -j1 test-core-special-port1-temporal XRAND=1 XRAND_SEED=1
```

The parent reports a fresh accepted-bfd run of this exact extension passed 1,099 retired packets in 5,096 cycles (215 dispatch and 180 retirement overlap observations). The composed model must still run and match that fresh baseline trace; no combined temporal agreement is claimed. The preparing agent ran no HDL models. The separate constrained-capacity D1 witness, existing alignment/native/pipe/dual/recovery/precise-fault/manual-cycle tests, strict lint/spec, Quartus acceptance and one matched fit remain required. Neither a timing gain nor 66 MHz is claimed. The independent cold IU-to-EA/translation path may remain limiting even if this changes the measured hot cancellation-to-port1-to-DQ1 path.
