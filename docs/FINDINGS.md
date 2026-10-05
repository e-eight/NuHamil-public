# Findings

Durable technical record. Every number here is tagged:

- **[measured]** — observed directly. Includes the command or artefact.
- **[inferred]** — reasoned from code or data, not yet confirmed by measurement.
- **[retracted]** — previously claimed and since disproven; see the log at the end.

Keep this file free of transient status; that belongs in [`PLAN.md`](PLAN.md).

---

## Build system

- **[measured]** A pristine upstream clone **cannot build on ICC**: the `Makefile`
  has no `icc` target and its `hostname` detection does not match `ccc`. The ICC
  block in `~/NuHamil-public` is a local, uncommitted patch (46 lines), preserved
  as `golden/icc-baseline/0001-icc-makefile.patch` and re-applied in commit `397b08e`.
- **[measured]** With that block, `build/base` compiles in **57 s** on `scavenger`
  (132 compile units serial, 132 MPI, zero errors), and the Makefile hash matches
  the golden build's (`bde8c694…`).
- **[measured]** `makedepf90` is **not installed** on ICC, so `make dep` cannot run.
  `makefile.d` is committed and already lists `obj/Profiler.o : … obj/MPIFunction.o`.
- **[measured]** HDF5 comes from a hack: the `.mod` from `/sw/apps/anaconda3/2024.10/include`,
  the runtime from the OS (`libhdf5_fortran.so.200 -> /lib64/…`). There is no
  `hdf5`, `lapack` or `openblas` module, and `/sw/apps/hdf5` contains only
  `src`/`test` (unbuilt). HDF5 is used by exactly one file, `src/ThreeBody/NNNFFromFile.F90`.
- **[measured, corrected 2026-10-03]** `-fdefault-integer-8` is mandatory **for the
  program**, but the **BLAS/LAPACK interface is LP64 (32-bit), not ILP64**. An
  earlier version of this line said "LAPACK/BLAS must match ILP64" and that is
  wrong — it cost a build and a debugging cycle. Evidence: `Renormalization.F90:45`
  declares `integer(4) :: n` for its `dgemm` arguments, and the cluster's
  `librefblas.a` reads each integer argument with `mov (%rax),%eax`, a 32-bit load.
  Linking ILP64 MKL makes it read 8-byte dimensions from 4-byte arguments and the
  binary segfaults (exit 139) with no output.
- **[measured]** The ICC build always emits `-ffree-line-length-0` (GCC >= 13 errors
  on the legacy >132-column lines).
- **[measured]** `make install` symlinks into `$HOME/bin`. Override `INSTLDIR=`.

## Parallelization

- **[inferred]** MPI is a master–worker task farm: rank 0 hands out unit IDs over
  `MPI_COMM_WORLD` with blocking `MPI_Send/Recv(..., tag=1)`, and every result is
  returned with `MPI_Bcast` plus barriers (`src/MPIFunction.F90`). No cost model,
  no non-blocking, no RMA.
- **[inferred]** Work units are whole `(J,P,T)` channels = `(e3max+2)*4`, whose cost
  spreads widely, so the schedule is unbalanced by construction.
- **[measured]** MPI is only accepted for `particle_rank==3 .and. trans2lab`;
  other modes `stop` when `nprocs>1` (`src/NuHamilMain.F90`).
- **[inferred]** OpenMP coverage is uneven — `ThreeBodyLabOpsIso.inc` has 33
  directives, while the NO2B/tensor includes have far fewer. Two `!$omp critical`
  accumulators exist in `ThreeBodyLabOpsIso.inc`.
- **[measured]** The in-code `Profiler` reported on rank 0 only, so rank imbalance
  was invisible. Fixed in commit `04968e6`; every rank now emits `#PROF_RANK`
  (and `#PROF_CAT` when `NUHAMIL_PROF_DUMP=1`). `timer%fin()` now runs **before**
  `mpi_finalize`, otherwise non-zero ranks lose their stdout.

## Jacobi space and the ramp

- **[measured]** `GetRampNmax()` (`src/ThreeBody/ThreeBodyJacobiSpaceIso.F90:167`)
  matches on **2J+1**, and it is the only control on the lab-frame 3N channel
  truncation (`src/ThreeBody/ThreeBodyManager.F90:107`).

  | ramp | 2J+1 <= 5 | <= 7 | <= 9 | <= 11 | > 11 |
  | --- | --- | --- | --- | --- | --- |
  | `ramplarge` = `ramp40-5-36-7-32-9-28-11-24` | 40 | 36 | 32 | 28 | 24 |
  | `rampsmall` = `ramp20-5-18-7-16` | 20 | 18 | – | – | 16 |

  Verified three ways: generated namelists are byte-identical to the hand-made
  `ramp20/` inputs, and the per-channel Nmax map reproduces exactly the values the
  code printed (`2J+1=7 -> 18`, `=9 -> 16`, `=3 -> 20`).
- **[measured]** `cfp/` = the Jacobi space; `ops/` = operators. Footprint per case
  on disk, e3max=8: **ramplarge cfp 1.6 GB vs rampsmall cfp 101 MB (≈17x)**, while
  ops moves the other way (4 KB vs 296 MB).
- **[measured]** The rampsmall e3max=8 `cfp/` holds exactly **40 files**, matching
  the schedule (12 x Nmax20, 4 x Nmax18, 24 x Nmax16).
- **[retracted]** The claim that per-Nmax byte shares show a **21.7 % tail ceiling**
  is invalid — see the corrections log.

## Measurements to date

Peak RSS is per rank, from `sacct` step `MaxRSS` (the `/usr/bin/time -v` value in
the runner measures `srun`, not the ranks).

| run | ranks x threads | wall | peak RSS/rank |
| --- | --- | --- | --- |
| deuteron | 1 x 4 | 3 s | 1.00 GB |
| rampsmall e3max6 | 32 x 1 | 34:55 | 1.61 GB |
| rampsmall e3max7 | 32 x 1 | 34:27 | 1.61 GB |
| rampsmall e3max8 | 32 x 1 | 37:35 | 1.61 GB |
| rampsmall e3max9 | 32 x 1 | 35:18 | 1.62 GB |
| rampsmall e3max10 | 32 x 1 | 44:15 | 1.94 GB |

- **[measured]** Deuterium correctness anchor: `E = -2.22434846` MeV against the
  reference `-2.22434870` (tolerance 1e-5).
- **[inferred]** At rampsmall the entire `cfp/` build finished in ~2.5 min of a
- **[measured]** The `cfp/` (Jacobi) build is **not** the runtime driver: at 8 ranks
  the three-body force construction is 1887 s of 1945 s (~97 %), while
  `set three-body Jacobi op` is 56 s (~2.9 %).
- **[inferred]** Prime suspect for the constant 1.6 GB/rank: lab-space operator
  matrices at single precision (dim^2 x 4 B; one channel printed 17010 states,
  giving ~1.2 GB). Unconfirmed.

## MPI scaling — measured 2026-10-02 (rampsmall, e3max6)

> **Superseded 2026-10-03 — see "MPI scaling, re-measured on one node" below.**
> These two points are not a valid comparison: they ran on different CPU vendors
> *and* concurrently in one shared run directory.

Same case, same binary, only the rank count differs:

| ranks | wall | speedup vs 8 | peak RSS/rank | imbalance (max/mean) | max/min |
| --- | --- | --- | --- | --- | --- |
| 8 | 1947 s (32:34) | 1.00 | 1652.6 MB | 1.249 | 1.984 |
| 32 | 2294 s (38:25) | **0.85** | 1657.9 MB | 1.522 | 1.996 |

- **[measured]** **More ranks is slower.** 4x the ranks runs 18 % *longer*; the
  parallel efficiency of 32 ranks relative to 8 is ~21 %.
- **[measured]** Peak RSS per rank is **independent of rank count**
  (1652.6 vs 1657.9 MB), so memory does not improve with MPI either.
- **[measured]** Imbalance *worsens* with more ranks: max/mean 1.249 -> 1.522.
- **[measured]** Rank 0 does no physics — its entire 2294 s sits inside
  `MPI parent-child, three-body force`.
- **[inferred]** Mechanism: a channel is an indivisible work unit and there are
  only `(e3max+2)*4 = 32` of them here. At 32 ranks (31 workers) the farm
  degenerates to about one channel per worker, so dynamic scheduling has nothing
  left to smooth and the wall becomes the slowest single channel. At 8 ranks each
  worker gets ~4 channels and the schedule self-balances. **The fix is finer work
  units, not more ranks.**
- **[measured]** Caveat — run-to-run spread is not negligible. The same case at
  32 ranks took 34:55 with the frozen binary on other nodes vs 38:25 here (+10 %).
  Causes not yet separated (scavenger node contention vs per-rank profiling
  overhead). **Repeat runs are needed before quoting small deltas.**
  **Update 2026-10-03: the cause is very likely node heterogeneity — the 8x1 and
  32x1 points above ran on different CPU vendors (Intel vs AMD). The negative
  scaling is therefore confounded and must be re-measured on one node. See
  "Benchmark methodology".**

## MPI scaling, re-measured on one node — the negative-scaling claim is refuted (2026-10-03)

The pair above cannot support its conclusion (different CPU vendors, plus the two
runs shared one run directory concurrently). Re-measured **cold, on one physical
node (ccc0497, EPYC 9555) with one binary** (`fix-nncache`, see "The NN cache
handoff had a race" below). Three jobs, every one `bench/accept.py` PASS:

| config | CPUs | job | wall | imbalance max/mean | peak RSS/rank | accept |
| --- | --- | --- | --- | --- | --- | --- |
| 8 ranks x 1 | 8 | 11140240 | 1360 s | 1.083 | 1652.6 MB | pass, 1.61e-06 |
| 32 ranks x 1 | 32 | 11140303 | **883 s** | 1.491 | 1653.0 MB | pass, 1.5e-07 |
| 8 ranks x 4 | 32 | 11140856 | **765 s** | 1.080 | 1655.9 MB | pass, 1.61e-06 |

- **[measured, refutes the earlier claim] More ranks is *faster*, not slower.**
  8 -> 32 ranks at 1 thread each gives **1.54x** (1360 -> 883 s) for 4x the CPUs,
  i.e. ~38 % parallel efficiency. That scaling is poor, but it is **positive**;
  the recorded 0.85x was an artefact of comparing two different nodes.
- **[measured] At a constant 32 CPUs, threads beat ranks by only 1.15x** on one
  node (8x4 = 765 s vs 32x1 = 883 s). The 2.9x previously recorded for this exact
  comparison was almost entirely the node gap (ccc0499 Zen 5 vs ccc0258 Zen 2).
  The OpenMP conclusion survives in **direction**, not in **size**.
- **[measured]** Reproduces the old *shape* while inverting the old *sign*: peak
  RSS/rank is still flat across rank count (1652.6 / 1653.0 / 1655.9 MB), and the
  imbalance still grows with rank count (1.083 -> 1.491).
- **[inferred] The mechanism stands; its size does not.** A channel is still an
  indivisible work unit, and at 32 ranks the wall is still set by the slowest
  single channel. That predicts *sub-linear* scaling, which is what we now
  measure — not *negative* scaling. Finer work units are still the lever; the
  earlier evidence simply did not show what it claimed.
- **[open]** 2-node MPI is still unmeasured. Each configuration also has a single
  sample here, so the ~3 % cross-node spread seen in the MKL section is not
  resolved for these points.

## OpenMP works — measured 2026-10-02 (magnitude corrected 2026-10-03)

First thread measurement in the project. rampsmall e3max6, constant 32 CPUs:

| ranks x threads | wall | imbalance max/mean |
| --- | --- | --- |
| 32 x 1 (job A) | 2294 s (38:25) | 1.522 |
| **8 x 4** | **784 s (13:04)** | **1.080** |

- **[measured]** 2.9x faster at the *same* CPU count, and it produced a complete
  result (32/32 `cfp`, 64 `ops`, a `.me3j.gz`), so the run is not merely fast.
- **[measured]** Imbalance collapses from 1.522 to 1.080: threads smooth the
  channel-to-channel spread *inside* a work unit, which is exactly what the
  coarse 32-unit farm cannot do. This is strong evidence for the P3 design —
  threading and finer units attack the same defect.
- **[inferred]** This also reframes the negative-scaling result: 32 ranks x 1 thread
  is the *worst* use of 32 CPUs here. The GPUs/threads argument is not "use fewer
  ranks" but "give each rank threads".
- **[measured, caveat — corrected 2026-10-03]** These points span nodes, and the
  **2.9x headline was largely the node difference, not threading.** Re-measured on
  one node with one binary: **8x4 765 s vs 32x1 883 s = 1.15x** (see "MPI scaling,
  re-measured on one node"). Threading still wins at a constant CPU count and still
  collapses the imbalance (1.080 vs 1.491), but the effect is modest. The direction
  of the P3 conclusion survives; its magnitude does not.

### Threading does not preserve bit-identical output (and neither does MPI)

`.me3j` files are **ASCII text** (header: `NNN int. calculated by NuHamil (Tokyo
code), :`), not raw binary. Comparing decompressed text line by line:

| comparison | max abs diff | max rel diff | lines differing |
| --- | --- | --- | --- |
| 32x1 vs 8x4 (identical binary, threading only) | 8.4e-07 | 5.3e-02 | 44269 / 45633 |
| 32x1 vs frozen golden (different binary + build) | 1.61e-06 | 5.0e-02 | 39486 / 45633 |

- **[measured]** Output is **not reproducible bit-for-bit across configurations**.
  Typical differences are ~1e-7 relative, i.e. the single-precision epsilon
  (`lab_3bme_precision` defaults to `single`); the worst *relative* deviations
  (~5 %) occur on small elements, which is the signature of cancellation in a
  reordered sum.
- **[measured]** The threading-induced deviation is **no larger than the deviation
  the code already exhibits** between an MPI run and the frozen reference
  (8.4e-07 vs 1.61e-06 absolute). OpenMP does not add error beyond the existing
  noise floor.
- **[measured]** **Therefore hashing `.me3j.gz` is the wrong correctness test.** It
  flags every configuration change as a failure. `golden/me3j/SHA256SUMS-me3j` is
  still valid for detecting file corruption or drift, but a real acceptance test
  needs a **numeric tolerance**. Until that exists, "numerics match golden" cannot
  be asserted by hash.

## The MPI farm, read from source (2026-10-02)

- **[measured]** `src/MPIFunction.F90` is a single-token ping-pong: a worker sends
  `idummy` to rank 0 and blocks on `mpi_recv`; rank 0 receives from `MPI_ANY_SOURCE`,
  records the owner in `slranks`, and replies with the unit number. Same tag (1) for
  everything, all blocking, no `Isend/Irecv`, no RMA, no cost model.
- **[measured]** Rank 0's dispatch loop is `do num_loops = 1, ntotal`, so the number
  of work units is **fixed at the call site** — the farm cannot be finer than its
  `ntotal`.
- **[measured]** The 97 % cost is the call at `src/ThreeBody/TMTransFunctions.inc:25`,
  `parent_child_procedure(calc_each_channel, nch, ...)` with
  **`nch = ((jmax3+1)/2)*4 = 32`** for e3max6 — one whole `(J,P,T)` channel per unit.
  The other call sites use `(e3max+2)*4`, `ch1dim`, `spmon%GetNumberChannels()`, etc.
- **[measured]** A work unit (`calc_each_channel`) does: (1) build the Jacobi space
  and write `cfp_*.bin`; (2) read it back; (3) `v3%InitNNNForce` / `U%init` /
  `v3%SetNNNForce` — the dominant step — writing `NNNint*.bin` and `UT_NNN*.bin`.
  So the unit's *result* is already a file.
- **[measured]** **Per-channel checkpointing already exists**: a unit returns early
  if `s%isfile(fv) .and. s%isfile(fut)`. The planned "per-channel checkpointing for
  `--requeue`" is therefore not new work — it is why `NUHAMIL_CLEAN=0` resumes.
- **[measured]** After the channel farm, results are redistributed by
  `ThreeBodyLabOpsIso.inc:922-939`: rank 0 broadcasts `slranks`, then **each rank in
  turn `mpi_bcast`s its full `MatCh(ch,ch)` (dim^2 elements) to all ranks**, serially.
  Every rank therefore ends up holding every channel's matrix — memory is
  O(sum over channels of dim^2), not O(1).
- **[inferred]** That redistribution explains two measurements at once: peak RSS is
  *flat across rank count* (every rank holds everything either way), and peak RSS
  grows strikingly with the ramp (dim^2). It also means adding ranks adds memory
  pressure without reducing it.
- **[measured]** Ranks then redundantly recompute the same results — the log shows
  every rank printing the same "Eigen values of 3-body H" for its channels.

**Design consequences for P3** (finer granularity alone would backfire):

1. Work units must be subdivided *inside* a channel (by bra-blocks of the Jacobi
   channel or by the `jpnl` partial-wave blocks), not by adding call sites.
2. Finer units multiply the handshake count, and every handshake is two blocking
   messages through rank 0. **The protocol must be replaced in the same change**,
   or granularity will make things worse.
3. The result redistribution — not the farm — is the memory wall. Since each unit
   already writes its result to a file, removing the all-to-all broadcast is the
   highest-leverage change.

## The NN cache handoff had a race — fixed 2026-10-03

Cold 32-rank runs of any case that builds the NN force **crashed 4/4 times** within
12-15 s:

```
Not found .//NNint_A2_rel_N3LO_EM500_bare_Nmax100_hw30.gz
Calculating NN interaction in relative coordinate:
At line 522 of file src/TwoBody/NNForce.F90
Fortran runtime error: End of file
srun: error: ccc0497: task 1: Exited with exit code 2
```

The `mpi/pmix_v6` lines srun printed around it are a **consequence, not the cause**.
`SetNNForceHO` (`src/TwoBody/NNForce.F90`) is a TOCTOU race on the relative NN cache:

- ~line 149 — **each rank decides for itself**: `if(.not. s%isfile(f))` -> compute,
  `else` -> `call this%readf(f)`
- ~line 197 — only the *writer* is serialised: `if(myrank == nprocs-1) call
  vnn_large%writef(f)`
- there is **no barrier** after the write, and `s%isfile` is a plain `inquire` — it
  is not a readiness signal, so a rank can observe the file after it is created but
  before it is complete
- `ReadNNForceHORelative` **never checked `gzip_readline`'s return code**, so a short
  read surfaced only as a bare "End of file" from the list-directed read

Because `SetNNForceHO` is reached through `NNNForceHOIsospin` from inside the
**per-channel farm**, ranks call it an *unequal* number of times. A collective fix
(broadcast the existence flag, or a barrier) is therefore **unsafe** — it would
deadlock or mismatch — which is presumably why the author used a per-rank `isfile`
test instead.

**Fix:** publish the cache atomically. The writer now writes `fn // '.tmp'` and
`rename(2)`s it into place, so `isfile(fn)` only ever becomes true for a complete
file; `gzip_readline` errors are also checked and reported now.

- **[measured]** Before: 4/4 cold 32-rank attempts crashed (ccc0499; ccc0496;
  ccc0497 twice). After: 32x1 cold on ccc0497 completed in **883 s** (32/32 `cfp`,
  a `.me3j.gz`).
- **[measured] The fix is numerically inert.** Deuteron `E = -2.22434846` MeV is
  identical to the pre-fix value, and all three same-node runs PASS `accept.py`
  against the golden product.
- **[measured] It is also timing-neutral:** 8x1 was 1398 s before the fix (old
  binary, ccc0499) and 1360 s after (ccc0497) — well inside the ~3 % cross-node
  spread.
- **[inferred]** This was a latent landmine independent of the scaling question:
  any cold run with enough ranks to spread the start times could hit it. The earlier
  32-rank runs likely escaped only because they were warm — their env files predate
  the cold-start guarantee and they shared one run directory.

## Where the time actually goes — perf profile, 2026-10-02

The in-code profiler can only time regions *it* wraps; it cannot see inside
statically-linked library code. A sampling profile closes that gap.

Method: one heavy channel (j3p+t1, Nmax20) left uncomputed in a copy of a finished
run with `cfp/` intact, so every other channel returned early and the profile
covers the force construction only. `perf record -e cycles:u` on the serial binary
with 4 threads, **6.5 M samples**:

| % cycles | symbol | note |
| --- | --- | --- |
| **40.1 %** | `dgemm_` | **reference BLAS** |
| **25.4 %** | `gomp_barrier_wait_end` | OpenMP threads idling at barriers |
| 6.4 % | `non_local_regulator_ho_mat` | |
| 2.8 % | `exp` | |
| 2.8 % | `__powidf2` | |
| 3.3 % | `gsl_sf_bessel_*` (j1_/j2_/CF1/jl_) | GSL Bessel, called per regulator |
| 1.3 % | `dcopy_` | reference BLAS |
| 2.0 % | `__nnnforcelocal_MOD_*` | the actual 3N physics, combined |

- **[measured]** **The single largest cost is `dgemm` at 40 %**, and it is Netlib
  *reference* BLAS: `nm` shows `dgemm_` as `T` (defined in the binary) because
  `/sw/apps/lapack/3.12.1/lib` holds only static `liblapack.a` / `librefblas.a`.
  Tuned alternatives are installed (MKL 2025, AOCL 5.0). Use MKL's **`lp64`**
  interface, not `ilp64` — see the corrected note under "Build system". Note also
  that the 3-body `sgemm` call sites pass plain `integer` (8 bytes under
  `-fdefault-integer-8`) while `Renormalization.F90` passes `integer(4)`; the
  working build satisfies both, so the mixture deserves care if the BLAS is
  swapped again.
- **[measured]** **Threads spend 25 % of cycles waiting at OpenMP barriers.** That
  is the missing explanation for the ~3.3x thread ceiling: it is not a serial
  fraction in the physics, it is synchronisation overhead. Implies the parallel
  regions are too fine-grained or badly balanced.
- **[inferred]** The two largest items are both **library/structure**, not physics —
  only ~2 % is in NuHamil's own 3N force routines. This inverts the earlier
  assumption that the win had to come from rewriting the physics.
- **[measured]** Caveat: profiled on the serial path (`nprocs==1`) with 4 threads,
  so it is not identical to the MPI runs. The physics code executed per channel is
  the same, but barrier behaviour would differ with more ranks.

### Consequence for priorities

1. **Relink against a tuned BLAS first.** 40 % of cycles in reference `dgemm` is
   the cheapest large win available: a link-line change in the site fragment, no
   source edits, and `bench/accept.py` verifies the numerics. This *should precede*
   both the P3 threading work and the P4 GPU port — a GPU port would spend its
   effort accelerating exactly this `dgemm`, which a library swap may largely fix.
   **Done and measured: MKL LP64 gives 1.98x, paired on one node — see the
   "Tuned BLAS relink" section. This also caps the P4 GPU prize: a GPU port would
   now be chasing a much smaller `dgemm` share.**
2. **Then attack the 25 % barrier time** — that is the real P3 target, and it is a
   scheduling/parallel-structure problem, not an arithmetic one.
3. GSL Bessel (~3.3 %) is a smaller, independent candidate.

## Tuned BLAS relink: MKL LP64 is ~2.0x — measured 2026-10-03

The profile above made relinking a tuned BLAS the top priority. It was tested as
a **pure link-line change**: `-llapack -lrefblas` replaced by MKL LP64. No source
file and no FFLAGS change — only LFLAGS. LP64 is required; ILP64 segfaults (see
"Build system"). The experiment is concluded: **`config/sites/icc.mk` now links
MKL LP64 by default**, and the former reference-BLAS link line is preserved as
`config/sites/icc-refblas.mk` (`SITE=icc-refblas`) so pre-change numbers remain
reproducible.

rampsmall e3max6, 8 ranks x 4 threads, cold start, checked against the golden
`.me3j` with `bench/accept.py`:

| job | node | CPU | BLAS | wall | three-body force | accept |
| --- | --- | --- | --- | --- | --- | --- |
| 11118101 | ccc0499 | EPYC 9555 (Zen 5) | reference | 784 s | — | pass, 1.61e-06 |
| 11138828 | ccc0499 | EPYC 9555 (Zen 5) | reference | 768 s | 748.1 s | pass, 1.61e-06 |
| 11125083 | ccc0386 | Xeon 8358 (Ice Lake) | **MKL LP64** | 654 s | — | pass, 2.17e-06 |
| 11138827 | ccc0499 | EPYC 9555 (Zen 5) | **MKL LP64** | **391 s** | 387.9 s | pass, 2.20e-06 |

- **[measured] Paired on one node (ccc0499), MKL LP64 is 1.98x**: 776 s (mean of
  784/768) -> 391 s. The two reference-BLAS runs agree to 2.1 %, so this is a
  real effect, not run-to-run noise.
- **[measured] Numerics PASS everywhere.** MKL moves the worst element from
  1.61e-06 to ~2.2e-06 absolute, well inside the 5.2e-06 noise floor and the
  1e-4 acceptance tolerance. The two reference-BLAS runs are *bit-identical* in
  that metric (1.61e-06 both), i.e. the code is deterministic; MKL's shift is a
  reordered summation, as expected. The change is a link-only A/B, so this is
  the cleanest correctness signal in the project so far.
- **[inferred] The 1.98x exceeds the naive Amdahl bound from the 40 % `dgemm`
  share** (which allows only 1.67x). Either the perf profile undercounted
  `dgemm` (it was taken on the serial path, 4 threads, on an Intel node with
  reference BLAS) or reference BLAS is relatively worse on EPYC. The direction
  is unambiguous though: **40 % of cycles in reference `dgemm` understated what
  a tuned BLAS buys.** Worth a re-profile on the paired node.
- **[measured] This supersedes the earlier 1.20x reading** of the same
  experiment (654 s vs 784 s) — that compared an Intel node against an AMD node.
  See node heterogeneity, below.

## Benchmark methodology: scavenger node heterogeneity is a first-order confound — 2026-10-03

`scavenger` is heterogeneous and the harness compares runs made on whatever node
the scheduler picked. Two runs of the *same binary* at the same configuration
show how large that is:

- MKL LP64, 8x4: **654 s on ccc0386 (Intel Xeon Platinum 8358)** vs **391 s on
  ccc0499 (AMD EPYC 9555)** — a **1.67x** node effect, same binary, same input.
- Two reference-BLAS 8x4 runs, both on ccc0499: 784 s and 768 s — **2.1 %**
  spread.

So repeat-to-repeat noise on one node is ~2 %, while the node changes the wall
by up to 67 %. **Any comparison drawn across nodes is uninterpretable below
~2x.**

- **[measured]** Node families in these runs. CPU models were confirmed with
  `lscpu` probes (jobs 11139439/11139440), not inferred from the Slurm feature
  tags:
  - **ccc0386 = Intel Xeon Platinum 8358**, Ice Lake-SP, launched 2021:
    32 cores/socket (64 CPUs), 2.6 GHz base, 80 MiB L2, 96 MiB L3, 8-ch DDR4.
  - **ccc0499 = AMD EPYC 9555**, Zen 5 "Turin", launched late 2024:
    64 cores/socket (128 CPUs), up to 4.41 GHz, 128 MiB L2, 512 MiB L3,
    12-ch DDR5. ccc0496/0498 carry an identical feature set (128 CPUs, same
    RTX-6000B layout, same memory) and are almost certainly the same part.
  - **ccc0258 = AMD EPYC 7702**, Zen 2, 2019 (256 GB). "AMD" is not one machine:
    Zen 2 (2019) and Zen 5 (2024) are three architecture steps apart.
- **[inferred] The 1.67x node gap is explained by hardware generation, and it
  means the ordering "AMD beats Intel" is not a conclusion.** EPYC 9555 is ~3.5
  years newer than the Ice Lake Xeon that it was compared against, with ~1.3x
  the clock (4.41 vs 3.4 GHz boost), 5x the L3, and DDR5 rather than DDR4 — for
  a workload whose live matrices (4.6 GB at ramplarge) dwarf any cache, the
  memory subsystem plausibly accounts for much of the gap. The comparison is
  also **not** evidence that Intel MKL favours AMD: MKL is the BLAS on *both*
  nodes, and there is no reference-BLAS run on ccc0386, so even the 1.98x MKL
  *speedup factor* is measured only on Zen 5.
- **[measured, caveat] The MPI negative-scaling result is confounded.** The 8x1
  point (1947 s) ran on **ccc0386 (Intel)** and the 32x1 point (2294 s) on
  **ccc0258 (AMD EPYC 7702)** — different vendors. The 0.85x "more ranks is
  slower" figure therefore entangles rank count with node speed and **must be
  re-measured with both points on one node** before it is quoted. The *source*
  argument (one channel per rank at 32 ranks leaves the scheduler no slack) still
  stands on its own; the wall-time evidence for it does not.
- **[measured]** The OpenMP sweep's points also span nodes: 1x32 ccc0498, 2x16
  ccc0496, 8x4 ccc0499 (all AMD EPYC); 16x2 and 32x1 ccc0258 (EPYC 7702). The
  trend (8x4 best by ~5x) is far larger than any node effect, so the conclusion
  survives, but the fine ordering between adjacent points does not, and the
  "+10 % run-to-run spread" recorded earlier is most likely this node effect.
- **[recommendation]** Pin comparisons to one node (`--nodelist`), or run each
  configuration on >= 2 nodes and report per-node, before quoting any delta
  below ~2x. The harness already records `nodelist` in `run-*.env`; the gap is
  in how comparisons are drawn, not in what is captured.

## Tuned BLAS is now the default — 2026-10-03

- **[measured]** `config/sites/icc.mk` (the ICC default) now links **MKL LP64**;
  the former Netlib reference link line is preserved verbatim in
  `config/sites/icc-refblas.mk` (`SITE=icc-refblas`), and the experimental
  `icc-mkl.mk` fragment is retired.
- **[measured]** Re-measured on one node (ccc0497), 8x4 cold, with the current
  binary (MKL + the NN-cache race fix, build tag `mkl-fix`): **361 s**, versus
  **765 s** for reference BLAS on the same node = **2.12x**. That agrees with the
  1.98x earlier measured on ccc0499, and confirms the win is not node-specific.
  Numerics PASS (`accept.py`, 2.2e-06) and the deuteron is unchanged at
  -2.22434846 MeV.
- **[measured] MKL's own threading is fine as-is.** With the app already running
  4 OpenMP threads per rank, forcing `MKL_NUM_THREADS=1` is *slower*: 389 s vs
  361 s (1.08x). So `mkl_gnu_thread` is not fighting libgomp, and no thread knob
  needs setting. (This was worth checking: nested threading would have been a
  free win or a silent disaster, depending on the sign.)
- **[measured]** `mkl-fix` is the first binary carrying both improvements; it
  should be the baseline for further work.

## Re-profile with MKL: the bottleneck moved to libm and barriers — 2026-10-03

Same method as the 2026-10-02 profile so the two are comparable: one heavy channel
(`j3p+t1 Nmax20`) left uncomputed in a copy of a completed run, serial binary,
4 threads, `perf record -e cycles:u`. Job **11141497**, ccc0497, wall 128 s.
`bench/reprofile.sbatch` now automates this (copy the run dir, delete one
channel's two `ops/` files, profile; `NUHAMIL_CLEAN=0` so the rest return early).

By shared object — this is where the old profile's `dgemm` share went:

| % cycles | object | note |
| --- | --- | --- |
| **31.3 %** | **libm.so.6** | `exp` + unnamed libm internals |
| **24.6 %** | **libgomp** | barrier idle |
| 18.2 % | NuHamil_serial.exe | our own physics |
| 10.6 % | libmkl_def.so.2 | `dgemm` kernel + `xdcopy` + `pst` |
| 8.4 % | libgsl.so.28 | Bessel |
| 4.8 % | libgcc_s.so.1 | `__powidf2` (software integer power) |

Top symbols: `gomp_barrier_wait_end` 18.1, `non_local_regulator_ho_mat` 10.0,
`exp` 7.2, libm `0x648a4` 6.3, `mkl_blas_def_dgemm_kernel_zen` 4.9,
`__powidf2` 4.8, `gomp_team_barrier_wait_end` 4.6, GSL `J_CF1`/`j2_e`/`j1_e`
1.9/1.9/1.7, `get_overlap_xis_ho` 1.6, `set_two_pion_exchange_c3` 0.9.

- **[measured] `dgemm` is solved: 40.1 % -> 10.6 %.** The MKL relink removed the
  dominant cost exactly as intended, which is why it was worth ~2x.
- **[measured] The largest remaining cost is elementary math, not physics:**
  libm 31.3 % + `__powidf2` 4.8 % ~= **36 %** in `exp`/`pow`/integer-power
  evaluation. This was invisible before — at 2.8 % `exp` and 2.8 % `__powidf2`
  in the old profile it looked negligible, and it only became the top item once
  `dgemm` stopped hiding it.
- **[measured] Barriers are unchanged and now co-dominant: ~24.6 %** (18.1 + 4.6).
  In absolute terms that is roughly two thirds of the old 25.4 % figure, but it is
  now the single largest *structural* item, and the one P3 already targets.
- **[measured] Only 18.2 % of cycles are in NuHamil's own code**, and GSL's Bessel
  functions are 8.4 % — much larger than the 3.3 % previously recorded.
- **[inferred] Compute vs bandwidth, resolved in favour of compute.** The open
  question raised by the nodecal `gemm1`/`triad1` disagreement is answered: the
  cost sits in scalar transcendental evaluation and barrier idle, not in a
  memory-stall symbol. Caveat: `cycles:u` attributes a stalled load to the symbol
  containing it, so this is suggestive rather than proof — but `exp`/`pow` on
  scalars is arithmetic, and the nodecal correlation was already known invalid.

### Consequence for priorities (revised 2026-10-03)

1. **Barriers (~25 %) — unchanged P3 target.** Structural, and the largest single
   item that is not arithmetic.
2. **libm + integer power (~36 %) — new, and now the biggest target.** Needs the
   call sites located (the non-local regulator and the 2-pion pieces are the
   suspects), then either invariant hoisting out of the inner loops or a
   vectorised path. Nothing in the plan anticipated this.
3. **GSL Bessel (8.4 %)** — recursions instead of per-call evaluation; the
   original 3.3 % estimate undersold it.
4. **`__powidf2` (4.8 %)** — software integer power, replaceable locally.
5. **P4 GPU: there is now no hot kernel to port.** The cost is diffuse (36 %
   library math, 25 % idle, 18 % physics spread over many small routines). That
   removes the premise of the bake-off, and P4 should fall back to a written memo.

### Where the ~36 % lives: three loop-invariant calls, all hoistable

Checked before writing any vectorisation or GPU code, because "36 % in libm" has
two very different remedies. The answer is **hoisting, not vectorisation** — the
elementary functions are being re-evaluated for arguments that never change.

**1. `non_local_regulator` — the dominant one**
(`src/ThreeBody/NNNForceHOIsospin.F90:372`)

```fortran
do i = 1, size(p)                              ! NMesh = 500
  do k = 1, size(p)                            ! 500
    ex = - ( 0.5d0*(pi**2 + pk**2)*hc**2/params%lambda_3nf_nonlocal**2 )**params%RegulatorPower
    f = f + wi*wk * Radial(i,n12,LL)*Radial(k,n3,l) * exp(ex) * Radial(i,n45,LL)*Radial(k,n6,l)
```

`ex` depends **only on (i,k)** — on none of the six quantum-number arguments. It
is still recomputed inside the innermost loop, and the function is called once per
`(ibra,iket)` matrix element from the enclosing `non_local_regulator_ho_mat`. So
`pow`+`exp` run `size(p)**2 = 250 000` times **per matrix element**, where 250 000
evaluations would cover the whole channel. Precompute
`W(i,k) = wi*wk*exp(ex(i,k))` once and the inner loop becomes four multiplies.
This single hoist should take most of `exp` (7.2 % plus part of the ~16 % unnamed
libm) and all of `__powidf2` (4.8 %).

**2. `local_regulator` — recomputed for a constant argument**
(`src/ThreeBody/NNNForceLocal.F90:1592`, called at :1530 and inside `f1_func`/`f2_func`)

```fortran
x = ( q / lambda )**n
f = exp( - x**2 )          ! two pow + one exp
```

It is always called as `local_regulator(p*hc, lambda, power)` — a pure function of
the p-mesh index `j` — but from inside the `x` and `i` loops, so it is recomputed
for every `(x,i)` pair. A length-`NMesh_p` table removes two `pow`s and an `exp`
per call site.

**3. `spherical_bessel` — a per-call constant threshold** (`src/MyLibrary.F90:1013`)

```fortran
a = exp(-200.d0/l*log(10.d0) + ...)   ! depends only on l
if(x < a) return
```

`a` is a function of `l` alone, yet an `exp` and two `log`s are evaluated on every
Bessel call — and this sits underneath `f1_func`/`f2_func`, which is where the GSL
Bessel traffic (8.4 %) comes from. Precompute per `l`.

**4. Integer powers.** `p**3`, `p**2`, `r**2`, `r1**2`, `x**2`, `(q/lambda)**n` and
`(...)**params%RegulatorPower` all reach `__powidf2`/`pow`. The hot ones disappear
with the hoists above; the rest are cheap to write as multiplications.

**Verdict: all hoistable — none of it needs vectorisation, and none of it needs a
GPU.** The changes are mechanical and numerically low-risk (reassociation only),
and they are verifiable with the deuteron anchor plus `bench/accept.py`.

### Done: the hoist is 1.34x, and bit-for-bit identical — 2026-10-03

H1 and H2 are implemented (commit); H3 (the Bessel threshold) is folded into the
GSL item below. The expressions were copied verbatim and the multiply order kept,
so the change was expected to be numerically *exact* — and it is:

| build, 8x4 cold on ccc0497 | wall |
| --- | --- |
| `mkl-fix` (before) | 361 s |
| `hoist` (after) | **269 s** |

- **[measured] 1.34x on the end-to-end run**, deuteron unchanged at
  -2.22434846 MeV, `accept.py` PASS with the same 2.2e-06 worst element.
- **[measured] The output `.me3j` is bit-for-bit identical** to the `mkl-fix`
  run — all 456 320 elements. This is the cleanest possible verification: the
  refactor changed only how many times the arithmetic is done, not the arithmetic.
  **See the correction further down:** bit-identity is not a stable property of this
  code (two same-configuration runs can differ by 2.8e-07), so read this as strong
  evidence rather than proof.
- **[measured] Combined with the relink, this case is now 2.84x faster than this
  morning**: 765 s (reference BLAS) -> 269 s (MKL + hoist), same node and config.

Re-profiled with the same method (job 11142055; phase wall 128 s -> 83 s, so the
absolute column below scales the percentages by that factor):

| object | before | after | note |
| --- | --- | --- | --- |
| libm.so.6 | 40.0 s (31.3 %) | 9.5 s (11.4 %) | `exp` no longer appears at all |
| **libgomp (barriers)** | 31.5 s (24.6 %) | **32.3 s (38.9 %)** | **unchanged in absolute terms** |
| libmkl_def.so.2 | 13.6 s (10.6 %) | 14.3 s (17.2 %) | |
| NuHamil_serial.exe | 23.3 s (18.2 %) | 13.2 s (15.9 %) | |
| libgsl.so.28 | 10.7 s (8.4 %) | 9.8 s (11.8 %) | |
| libgcc_s (`__powidf2`) | 6.1 s (4.8 %) | 1.0 s (1.2 %) | |

- **[measured] The hoist removed ~45 s, essentially all of it from libm and
  `__powidf2`** — exactly as predicted, and the phase is 1.54x faster.
- **[measured] Barrier time did not move.** It is the same ~32 s as before; it only
  became the largest share because everything around it shrank. That is worth
  stating plainly, because a rising percentage is easy to misread as a regression.
- **[inferred] The ranking is now unambiguous and there is no longer a big single
  target.** Barriers ~39 %, MKL ~17 %, our physics ~16 %, GSL Bessel ~12 %
  (~10 s), libm ~11 % (down from 40 s). The next move is the structural one P3
  already planned; the arithmetic is no longer where the time is.

## The OpenMP barrier idle is Amdahl serial time, not imbalanced scheduling — 2026-10-03

The re-profile left ~39 % of cycles in libgomp barrier wait (32 s of an 83 s
phase), the largest single item, so scheduling looked like the next target. Since
the profile runs the *serial* binary with 4 threads, that idle is intra-rank
OpenMP, not MPI.

Four hypotheses, three refuted by measurement. All four use the same phase
(one heavy channel, `bench/reprofile.sbatch`, ccc0497):

| hypothesis | change | wall | barrier |
| --- | --- | --- | --- |
| nested MKL teams spinning inside our threads | `MKL_NUM_THREADS=1` | 86 s | 34.7 % |
| static-schedule imbalance in the hot loops | `schedule(dynamic)` on 6 `init_*` loops | 82 s | 35.5 % |
| barrier cost from ~60 small regions | fuse the `x` loop, `collapse(2)`: 3 regions for `fkx`, 1 for `zx` | 82 s | 35.8 % |
| **idle is serial-section idle** | **run the same phase with 1 thread** | **159 s** | (none) |

Baseline for reference: 81-83 s wall, 38.9 % barrier.

- **[measured] The fourth row is the answer.** 4-thread speedup is
  159/82 = **1.94x**, i.e. 48 % parallel efficiency, which is exactly Amdahl's
  law for a **~35 % serial fraction** -- matching the ~36 % barrier idle. The
  other three fixes could not have worked, because none of them touches the
  serial fraction; they were all treating a symptom.
- **[measured] The 1-thread profile contains no barrier symbols at all**, so the
  idle is unambiguously a parallel-execution artefact and not a real cost.
- **[measured] Percentage shares move with the configuration, not only with the
  code.** Single-threaded, MKL `dgemm` is 14.1 % and `__powidf2` is 2.4 % (vs
  7.9 % and 1.2 % at 4 threads). Shares from one configuration should not be
  compared to another without care.

**Consequence.** OpenMP can contribute at most ~1.94x on 4 threads in this phase,
and the idle is *not* recoverable by scheduling tuning. The lever is more **MPI
ranks with finer work units**, which is consistent with the earlier measurement
that ranks beat threads by 1.15x at constant CPU count. The remaining P3 items
(the 32-unit farm, the O(sum dim^2) redistribution, rank 0 doing no physics) are
therefore the ones worth doing, and the OpenMP-side items are closed.

**Reverted.** Both the `schedule(dynamic)` and the region-fusion changes were
neutral (81/82/83 s across all variants, inside run-to-run noise) and are not
carried. They are described here so they are not re-tried. Note the fusion also
removed a dead `a = exp(...)` computation in `init_zx_function`.

## MPI side: what the run's own timers already say — 2026-10-03

Taken from the hoist 8x4 run's own `#PROF_CAT` table (rank 0), not from a
profiler, so these are the code's own numbers:

| timer | s | share of wall |
| --- | --- | --- |
| **MPI parent-child, three-body force** | **266.37** | **99.5 %** |
| MPI parent-child, set three-body Jacobi op | 0.53 | 0.2 % |
| `TMTransScalarIsospin` (the lab transform, **which contains the `mpi_bcast` redistribution loop**) | **0.031** | 0.01 % |
| Write to file | 0.32 | 0.1 % |
| (wall) | 267.8 | |

- **[measured] The O(sum dim^2) redistribution is NOT a time cost at this size.**
  The serial `do ich ... call mpi_bcast(this%MatCh(ch,ch)%m(1,1), n1d, ...)`
  loop at `ThreeBodyLabOpsIso.inc:923-939` sits inside `TMTransScalarIsospin`,
  which takes 0.031 s out of 267.8 s. The plan listed this redistribution as one
  of the "two concrete targets"; that was wrong for this case. It remains a
  *memory* concern for production sizes (every rank ends up holding every
  channel), but not a time one here, and it should not be optimised first.
- **[measured] The whole wall is the outer farm** (`TMTransFunctions.inc:25`,
  `parent_child_procedure(calc_each_channel, nch, ...)`), whose work unit is one
  whole channel's 3NF construction.
- **[inferred] Rank 0 never calls `Method`**, so only `nprocs-1` ranks compute.
  That bounds the recoverable gain from rank-0 participation at
  `nprocs/(nprocs-1)`: **14.3 % at 8 ranks, 3.2 % at 32**. It is not the dominant
  loss — if it were, `T` would scale as `1/(nprocs-1)`, and the measured
  8x1 -> 32x1 gain of 1.54x is far below the 4.43x that model predicts. So rank-0
  idleness is worth fixing only at low rank counts, and it cannot explain the
  scaling failure.

### Measurement caveat: the per-rank logs cannot show imbalance

All eight rank logs of the 8x4 run report the **same** farm time
(266.366-266.387 s, a spread of 0.008 %). This is structural, not a finding about
balance: a worker exits the farm only after the master's finalize sweep sends it
a zero, and the master only runs that sweep after every unit has been dispatched,
so every rank leaves at essentially the same instant. The farm time in the logs
therefore measures the makespan, not the per-rank workload. Deriving "imbalance"
from these logs would be a mistake; it needs unit-count data from the master's
`slranks` array or added per-rank timers.

## Thread-vs-rank at fixed 32 CPUs, after the hoist: 16x2 is now the optimum — 2026-10-03

The earlier "threads beat ranks by 1.15x" result was measured *before* MKL and
before the hoist. Re-measured with the `hoist` binary, same case, all three cold
on ccc0497 with exactly 32 CPUs, all `accept.py` PASS:

| ranks x threads | wall | notes |
| --- | --- | --- |
| 8 x 4 | 269 s | worst |
| **16 x 2** | **206 s** | **best** |
| 32 x 1 | 254 s | |

- **[measured] The optimum moved.** Everything is on one node with the same 32
  CPUs, so this is purely how the work is shaped, not hardware.
- **[inferred] The three configurations fail for three different reasons**, which
  is why the optimum is in the middle:
  - **8x4** is limited by the ~35 % serial fraction (`gomp_barrier_wait` analysis
    above): 4 threads give only ~1.94x, and only 7 of the 8 ranks compute.
  - **32x1** has no thread loss but only 32 work units, so the makespan is set by
    the single slowest channel; pre-hoist the imbalance at 32x1 was 1.491.
  - **16x2** sits between: 2 threads lose less to Amdahl
    (`1/(0.35 + 0.65/2) = 1.48`), and 32 units over 15 workers smooths the
    granularity.
- **[inferred] Superseded conclusion, with a mechanism.** The hoist removed
  parallel work, which *raised* the relative serial fraction, which made threads
  comparatively less attractive and pushed the optimum toward more ranks. This is
  the second time in this work that an optimisation changed the best
  *configuration* as a side effect — the first being MKL changing which node
  looked fastest.
- **Consequence for P3:** if units were finer, 32x1 would become the best
  configuration, because it avoids *both* the thread (Amdahl) loss and the
  granularity loss. Fine-grained units are therefore the MPI-side lever, and
  `16x2` is the configuration to use until that exists. Any further performance
  comparison must state the ranks x threads it used.

## Granularity costs 1.87x at 32 ranks, measured unit by unit — 2026-10-03

The farm previously could not report this at all (see the log caveat above), so
`#PROF_UNIT` lines were added to `MPIFunction.F90`: every rank prints the id and
wall time of each unit it computes. This is the instrumentation, running, and
answering the question.

Instrumented 32x1 run (`units` build), same case and node: **wall 254 s**, exactly
the uninstrumented 32x1 — the timing is free.

The heavy farm's 32 units, in one-thread seconds:

| quantity | value |
| --- | --- |
| total work | 4211.8 s |
| mean unit | 131.6 s |
| **max unit** | **249.4 s** |
| min unit | 88.8 s |
| **max / mean** | **1.895** |
| ideal makespan, perfect splitting, 31 workers | 135.9 s |
| **actual** | **254 s** = **1.87x** |

- **[measured] Unit costs span 2.8x (88.8 -> 249.4 s).** At 32 ranks each worker takes
  one unit, so the makespan *is* the heaviest channel: 249.4 s of the 254 s wall. The
  dynamic farm cannot help when ntotal ~ nworkers; it is not a scheduling failure.
- **[measured] Perfect splitting would give ~136 s**, so there is **~1.87-1.93x** of
  headroom at 32x1, which would also beat the current best configuration (16x2,
  206 s) by ~1.5x.
- **[measured] The other two farms in the same run total 10.7 s of unit time** —
  negligible, consistent with the timer table.
- **[inferred] `max/mean` rose from 1.491 pre-hoist to 1.895.** The hoist removed work
  (`exp`/`pow`) that had been spread fairly evenly across all channels, leaving the
  cost more unevenly distributed. That is the mechanism behind 8x4 and 32x1 swapping
  places in the thread-vs-rank table above.
- **[inferred] Cost-ordered dispatch would not help.** With 31 workers and 32 units
  every unit is dispatched on the first round, so no ordering can change the makespan.
  Only finer units can.

**Consequence.** Subdividing `calc_each_channel` (`TMTransFunctions.inc:70`) into
row-block units is the single highest-value MPI change, worth ~1.9x at 32 ranks and
~1.5x over the current best configuration. It is also the only P3 item that is.

## The output is NOT bit-reproducible, even at a fixed configuration — 2026-10-03

Found while checking whether the new `#PROF_UNIT` instrumentation perturbed
anything. Two runs of the **same binary at the same configuration** (32 ranks x 1
thread, cold, ccc0497, case `3bme_e3max6__rampsmall`) were compared directly:

| | |
| --- | --- |
| values compared | 456 320 |
| **values that differ** | **33 365 (7.3 %)** |
| max abs difference | 2.4e-07 |
| max abs value | 0.872 |
| **relative difference** | **2.8e-07** |
| wall time | 254 s vs 258 s (1.6 %) |

- **[measured] The two runs are not bit-identical.** 7.3 % of the elements differ at
  the 7th significant digit, and the wall time itself moves by 1.6 %. So neither the
  numbers nor the timings are reproducible to the bit at fixed configuration.
- **[inferred] The likely source is the nondeterministic dispatch order of the dynamic
  farm** interacting with state reused across units, or an accumulation order that
  varies. It is *not* isolated yet, and is worth isolating, because "reproducible" is
  load-bearing for this project's verification story.

### Correction: an earlier claim in this file was too strong

The hoist section above records that the hoisted `.me3j` was "bit-for-bit identical"
to the pre-hoist run across all 456 320 elements. **That observation was real, but it
was not the proof it was presented as.** Bit-identity is not a stable property of this
code: a same-configuration comparison can differ by 2.8e-07 (above), so a single
bit-match between two runs is partly luck of the FP draw and cannot establish that a
refactor is arithmetically exact.

The hoist remains well supported — the deuteron is unchanged, `accept.py` passes with
the same worst element, and the change was designed to preserve both values and
multiply order — but it should be read as *strong evidence*, not *proof*. The right
verification for this code is the tolerance-based `bench/accept.py` plus the deuteron
anchor, which is exactly why the project retired `.me3j` hashing. This finding
independently confirms that decision was correct.

## Inventory: redundant loop work and replaceable math — 2026-10-03

Taken before starting the row-block refactor, because the hoist was the best ROI so
far (1.34x for free) and this class of change is cheaper and safer than reshaping the
farm. Shares below are from the **1-thread** profile (159 s), which is the cleanest
view of *where the work is* — with no barrier time competing for cycles:

| group | share of work |
| --- | --- |
| GSL Bessel (`j2_e` 5.79, `j1_e` 5.39, `J_CF1` 5.85, `jl` 2.63, `jl_e` 1.29, `IJ_taylor_e` 0.30) | **21.3 %** |
| libm internals (`0x754c1` 10.45, `0x754c6` 5.13, others, `exp` 0.76) | 17.1 % |
| MKL (`dgemm_kernel` 14.14, `dgemm_pst` 3.67, `xdcopy` 2.33, pack/copy 0.86) | 21.5 % |
| our own physics | ~26 % |
| `__powidf2` | 2.43 % |

### Redundancy: calls invariant over a loop index

1. **`legendre_polynomial` is invariant over `i`** in `init_fkx_function`
   (`NNNForceLocal.F90:1600,1624`). It sits inside `do i` but takes `(x, costh)`,
   which depend only on the outer `x` and the inner `j` — so GSL's `Pl` is recomputed
   `size(xis)` times for each distinct `(x,j)`. Hoist to a `pl(j)` table per `x`.
   *(0.50 % self, plus call overhead.)*
2. **`r1**2 + r2**2` and `2*r1*r2` are invariant over `j`** in the same two loops
   (`:1602,1626`): they depend only on `i`. Hoisting them out of the inner loop also
   removes **two `__powidf2` calls per inner iteration**. *(Feeds the 2.43 %.)*
3. **`spherical_bessel`'s threshold** (`MyLibrary.F90:1019`) recomputes
   `exp(-200/l*log(10) + ...)` on every call although it depends only on `l`, and the
   function is called millions of times. Precompute per `l`. *(0.83 % self.)*
4. **`ho_radial_wf_norm`** (`MyLibrary.F90:750`) recomputes two `ln_gamma` calls and
   `sqrt(2*nu)` per point although they depend only on `(n,l)`; it is called
   `NMesh * (Nmax/2) * Nmax` ~ 10^5 times per channel from `store_radial_wf`.
   *(~0.6 %.)*
5. **`non_local_regulator_ho_mat`** (6.96 % self) still loads four `Radial` values per
   `(i,k)` iteration, two of which depend only on `i` and can be hoisted out of the `k`
   loop. This is the innermost loop of 250 000 iterations per matrix element, so it is
   about memory traffic rather than arithmetic.

### Replaceable math

6. **GSL Bessel is the single biggest target, and it is replaceable two ways.**
   - **[l = 1 and l = 2 have exact closed forms]** in sin/cos:
     `j1(x) = sin x/x^2 - cos x/x`,
     `j2(x) = (3/x^3 - 1/x) sin x - 3 cos x/x^2`.
     The profile's `j1_e` + `j2_e` = **11.2 %** comes precisely from these two orders
     (GSL's `jl_e` dispatches to them). Replacing them is a few flops instead of an
     error-checked recurrence. **Caveat:** catastrophic cancellation as `x -> 0`, so a
     small-`x` cutoff or series is required; the existing threshold already returns 0
     below a small `x`.
   - **[the order sweep repeats work]** `init_zx_function` and `init_fkx_function` k=0
     call `spherical_bessel(x, arg)` for `x = 0..L` at the *same* `arg` (`r1*p` or
     `p*r1`), and each call runs its own backward recurrence — `O(L^2)` per argument
     where one Miller ladder is `O(L)`. That is `J_CF1` + `jl` + `jl_e` = **9.8 %**.
     Fixing it means making `x` the innermost loop and building the ladder once.
7. **`__powidf2` (2.43 %)** is largely items 2 and 4; the rest is `x**2`-style
   integer powers.
8. **MKL spends 6.9 % outside the kernel** (`dgemm_pst` 3.67 + `xdcopy` 2.33 +
   `copybn`/`copyan` 0.86). Packing and copying at that scale suggests temporaries
   around the products, e.g. `work = cfp%T() * work * cfp`. Worth reading `DMat`'s
   operator implementations, but it needs care and is speculative.

**Recommended order:** item 6a (≈11 % of work, small and local), then 6b (≈10 %,
contained but needs a loop-nest change), then items 1-4 as a batch (≈2 %), and only
then the row-block farm refactor. All are verifiable with `accept.py` + the deuteron.

## Process bug found and fixed: profiles were overwriting each other

`bench/reprofile.sbatch` derived its output directory from the source run's name, so
repeated profiles of the same source silently replaced each other. That is why a
stale 4-thread table (libgomp 38.9 %) and the current 1-thread table (libgsl 24.1 %)
were both in play in this session, and the numbers were nearly read as current. The
directory now carries a timestamp (`NH_PROFILE_TAG` to override). **Any profile number
must be quoted with the run it came from.**

## Compiler flags are neutral, and the "serial fraction" is not serial code — 2026-10-03

Two questions raised before committing to the row-block refactor.

### `-march` (and friends): neutral

The ICC build had **no `-march` at all**, so gcc targeted the SSE2 baseline on
Zen 5 and Ice Lake-SP hardware. Tried `-march=x86-64-v3` (AVX2/FMA; safe on every
model in the pool — deliberately not `native`, since the pool is heterogeneous,
and not `v4`, since AVX-512 would exclude the Zen 2 nodes).

| 16x2, ccc0497, ramp small | wall |
| --- | --- |
| `ladder` (no `-march`) | 148 s |
| `optv3` (`-march=x86-64-v3`) | 150 s |

- **[measured] No benefit — inside the 1.6 % run-to-run noise. Reverted**, so the
  binary keeps no unnecessary ISA requirement. (Deuteron unchanged at
  -2.22434846 either way, so vectorisation did not perturb numerics.)
- **[inferred] Our hot loops are not limited by scalar-vs-vector codegen.** They
  are dominated by library calls (GSL/MKL) and memory access, and MKL selects its
  own kernels at run time regardless of `-march`. This is consistent with the
  bandwidth picture below.

### The ~50 % "serial fraction" has no serial block to fix

The phase is now 114 s at 1 thread vs 71 s at 4 — only **1.61x**, i.e. an apparent
serial fraction of ~50 %, *up* from ~35 % (removing parallel arithmetic raised the
relative serial share, as predicted). Per-component absolute times (`pct x wall`):

| component | 1 thread | 4 threads | speedup |
| --- | --- | --- | --- |
| NuHamil_serial.exe | 51.4 s | 14.2 s | 3.62 |
| libmkl_def | 35.8 s | 13.9 s | 2.58 |
| libm | 18.0 s | 5.8 s | 3.10 |
| libgcc | 3.9 s | 1.0 s | 3.90 |
| libgsl | 3.0 s | 0.8 s | 3.75 |
| **libgomp (idle)** | **0** | **32.5 s** | — |

- **[measured] Work scales 112 s -> 38.5 s = 2.91x** (73 % efficiency); the other
  **32.5 s of the 4-thread wall is thread idle at barriers**.
- **[measured] Nothing is serial.** Every component scales >= 2.58x. The weakest
  is MKL, and inside it `mkl_blas_def_xdcopy` scales only **1.25x** — the
  signature of a bandwidth-bound copy, not of serialisation.
- **[inferred] So the "serial fraction" is not a block of code that could be
  parallelised.** It is (a) sub-linear scaling spread across every component plus
  (b) barrier idle, and the most likely mechanism is **memory-bandwidth
  contention** — consistent with the earlier incidental observation that full-case
  node times tracked the triad benchmark rather than `gemm1`.
- **[inferred] This also explains why every OpenMP-side fix failed**: imbalance,
  region count and schedule tuning all address *distribution*, but the limit here
  is *supply*.

### Consequence for the plan

The **1.87x granularity figure was measured on the `hoist` binary**, before the
math work re-shaped the work distribution a second time. If the real limit is
bandwidth rather than granularity, then finer work units will not deliver 1.87x,
and the row-block refactor would be a large change bought on stale evidence.
**Re-measure the granularity and configuration picture with the current binary
before starting it** — a few runs, versus a rewrite.

## The "MKL copy path" is DMat's copy-heavy matrix algebra — 2026-10-03

Investigating the ~9 s (1-thread) MKL spends outside the multiply kernel, because
a bandwidth-limited workload pays twice for copies: they consume bandwidth and
they do not parallelise (`xdcopy` scales only 1.25x on 4 threads).

### What the algebra is doing

`DMat` comes from the `LinAlgf90` submodule. Reading it, every matrix operation
allocates and copies:

- `operator(*)` -> `MatrixProductD` (`MatrixDouble.f90:100`): **allocates a new
  DMat** and dgemms into it, so `a * b` never writes into a target.
- `assignment(=)` -> `MatrixCopyD` (`LinAlgLib.f90:114`, `MatrixDouble.f90:87`):
  a *defined assignment* that copies with a **column-by-column `dcopy` loop**
  (`do i = 1, n; call dcopy(m, a%m(:,i), 1, b%m(:,i), 1)`).
- `%T()` -> `Trans` (`MatrixDouble.f90:186`): materialises a transpose into a new
  matrix via `b%M = transpose(a%M)`.
- `MatrixSumD`, `MatrixSubtractD` and the `MatrixScale*` family all route through
  `MatrixCopyD` as well.

So in `multiply_non_local_regulator_hospace` the two expressions

```fortran
work = cfp%T() * work * cfp
this = work%T() * this * work
```

each cost a transpose copy, two allocations, two dgemms, **and a full nphys x
nphys copy in the assignment** — when two dgemms writing into the destination
would do. `dcopy` resolves to `mkl_blas_def_xdcopy`, which is the symbol the
profile shows.

### Why it matters beyond its own share

- **[measured]** `xdcopy` is 3.7 s of 114 s at 1 thread and 2.9 s of 71 s at 4 —
  i.e. it barely speeds up, which is exactly what a pure memory copy should do.
  `__matrixdouble_MOD_trans` (the transpose copies) behaves the same, 1.2 -> 0.6 s.
- **[inferred]** These copies are pure memory traffic on a workload that looks
  bandwidth-limited, so their cost is not limited to their own ~5 % — they also
  compete for the bandwidth everything else needs.

### The codebase already contains the better pattern

`ThreeBodyJacOpsChanIso.F90:1051-1068` calls `dgemm` **explicitly with a
preallocated temporary** instead of using the operators:

```fortran
call dgemm('n','n', l, n, m, 1.d0, Mat_NonAsym%m, l, cfp1%m, m, 0.d0, tmp%m, l)
call dgemm('t','n', k, n, l, 1.d0, cfp1%m, l, tmp%m,    l, 0.d0, this%DMat%m, k)
```

That form needs no transpose copy, no result allocation and no assignment copy.
Converting the few hot operator expressions to it is a **local change at the call
sites in `src/ThreeBody/`**, which is preferable to editing the third-party
submodule.

- **Do not** be tempted to make `MatrixCopyD` use `move_alloc`: a defined
  assignment cannot tell a temporary from a named argument, so it would silently
  steal the storage of a variable the caller still needs.
- A single contiguous `dcopy(m*n, ...)` instead of `n` column calls is *not* the
  fix: each column is already contiguous, so the copy volume is the cost, not the
  call count.

### Attribution (measured): it is ours, and 75 % of it is one routine

Followed up with a call-graph profile at 1 thread (`NH_CALLGRAPH=1`, so MKL is
single-threaded and the callers are unambiguous), then walked each `xdcopy`
sample up its stack.

Every one of the 779 `xdcopy` samples reached it through MKL's **public**
`mkl_blas__dcopy` -> `mkl_blas_dcopy`, i.e. from an explicit `call dcopy`, **not**
from dgemm's internal `dgemm_dcopy_*` paths. So the earlier caveat is resolved:
this is not MKL doing something to us.

| direct caller of `dcopy` | samples | share |
| --- | --- | --- |
| `__matrixdouble_MOD_matrixcopyd` (DMat defined assignment) | 587 | 75.4 % |
| `__vectordouble_MOD_vectorcopyd` | 72 | 9.2 % |
| `__vectordouble_MOD_vectorscalerd` | 61 | 7.8 % |
| `__vectordouble_MOD_vectorsumd` | 58 | 7.4 % |
| `__matrixdouble_MOD_matrixsumd` | 1 | 0.1 % |

- **[measured] 100 % of it is the `LinAlgf90` copy-based algebra** (`DMat` and
  `DVec` defined assignments), matching the source reading above. None is dgemm
  internals.
- **[measured] And 582 of the 587 `MatrixCopyD` samples -- 75 % of all copy time --
  come from a single routine**: `__nnnforcelocal_MOD_transform_xis_to_ho`
  (plus 2 from `set_two_pion_exchange_c3` and one each from three others).

That routine (`NNNForceLocal.F90:1034`) is exactly the predicted shape — four
`DMat` assignments, each a full copy:

```fortran
ovlp_bra = get_overlap_xis_ho(nxis, xis, chbra)   ! copy of a returned DMat
ovlp_ket = get_overlap_xis_ho(nxis, xis, chket)   ! copy of a returned DMat
m = ovlp_bra%t()                                  ! Trans copy + assignment copy
... m%m(:,i) = m%m(:,i) * c ...                   ! in-place scale (fine)
mat = m * ovlp_ket                                ! ProductD alloc+dgemm + assignment copy
```

- **Fix**: rewrite those expressions with explicit `dgemm` into preallocated
  buffers, as `ThreeBodyJacOpsChanIso.F90:1051` already does. Local to our source,
  no submodule edit.
- **Size**: `xdcopy` is 3.7 s of 114 s (1 thread) / 2.9 s of 71 s (4 threads), so
  ~75 % of that is ~3 % of wall directly, plus the `Trans` copy
  (`__matrixdouble_MOD_trans`, 1.2 s / 0.6 s) and the bandwidth relief.
- **[inferred] Modest but structural**: at ~3-4 % it is smaller than the Bessel
  work, but it is the clearest remaining piece of *waste* — pure memory traffic
  doing no arithmetic, in a routine we can name.

### Fixed, and the mechanism confirmed — 2026-10-03

`transform_xis_to_ho` and `get_overlap_xis_ho` now take caller-supplied matrices
and write into them, the transpose is taken straight into `m%m`, and the product
goes through an explicit `dgemm` into the caller's matrix. That removes the four
copies inside the routine plus the fifth at each of the 7 call sites. The dead
`transform_xis_to_ho_old` (unreferenced, and it would not have compiled against
the new `get_overlap_xis_ho`) was deleted along with an unreachable "norm check"
block after a `return`.

| 16x2, ccc0497, ramp small | wall |
| --- | --- |
| `ladder` | 148 s |
| **`copyfix`** | **141 s** (1.05x) |

- **[measured] Numerics clean**: deuteron -2.22434846 unchanged, `accept.py` PASS
  with the same 4.01e-06 worst element, and the output identical to the `ladder`
  run in all 456 320 values.
- **[measured] The copies really are gone** — 1-thread profile, before -> after:

  | symbol | `ladder` | `copyfix` |
  | --- | --- | --- |
  | `mkl_blas_def_xdcopy` | 3.21 % | **0.96 %** |
  | `__matrixdouble_MOD_matrixcopyd` | 0.25 % | **0.00 %** |
  | `__matrixdouble_MOD_trans` | 1.01 % | **0.01 %** |

  The residue is the `DVec` copy/scale/sum family — the other 25 % of the
  attribution, untouched.
- **[inferred] The 16x2 gain (4.7 %) exceeds the single-thread gain (2.7 %,
  113 -> 110 s under perf)**, which is what a bandwidth-bound cost should do: the
  copies hurt more when 16 ranks are contending for bandwidth than when one
  thread is running alone. That is a second, independent hint that the
  bandwidth reading is the right one.

### Second attempt, on `set_nnn_interaction_chEFT_n2lo`: NEGATIVE — reverted

The same copy-heavy pattern appears in the routine that dominates every work unit:

```fortran
cfp = jac%GetCFPMat()
call set_nnn_int_chEFT_n2lo_isospin(work, jac, LECs, ...)
this%DMat = cfp%T() * work * cfp        ! transpose + 2 temporaries + result copy
```

I recommended rewriting it as two explicit `dgemm`s writing into preallocated
storage, on the grounds that its share of the work is 91.5 % and so its copy
overhead should be "larger in absolute terms". **That reasoning was wrong, and the
evidence against it was already in hand**: the `dcopy` attribution had given this
routine exactly **1 sample out of 587**. Presence of a pattern is not evidence of
its cost.

- **[measured] Implemented and measured anyway rather than argued.** Same-node
  A/B on ccc0499, 16x2, cold: **139 s (before) vs 139 s (after) — no benefit.**
- **[measured] It was numerically exact**: deuteron unchanged, `accept.py` PASS,
  and the output identical in all 456 320 values, so the two-dgemm sequence does
  reproduce the operator form. The rewrite was *correct*, just worthless.
- **Reverted**, on the same principle as `-march`: a change with no measured
  benefit is not worth carrying, especially one that hand-rolls a `dgemm` the
  library already expressed.
- **[inferred] Why it is free here but not in `transform_xis_to_ho`:** there the
  copies were large relative to the arithmetic in that specific routine; here the
  same expression sits next to `set_nnn_int_chEFT_n2lo_isospin`, whose cost
  dwarfs it. The copy volume is set by `north x nphys`, while the surrounding
  work is `nphys^2 x north` — so the copies are asymptotically smaller.
- Note the identical expression also appears at `NNNForceHOIsospin.F90:296` in
  the `_n3lo` variant, unused for this case. Left alone.

**Lesson recorded**: two copy-heavy call sites, same source pattern, opposite
outcomes — 1.05x and 0.00x. Only measurement distinguishes them.

## Re-measurement with the current binary: the refactor's prize is 1.54x, and threads saturate at 2 — 2026-10-03

All three refactor-relevant measurements were taken on the `hoist` binary and had
to be re-taken after the math work. Redone with the current (`ladder`) binary,
every run cold on ccc0497, every run `accept.py` PASS.

### Configuration (fixed 32 CPUs)

| ranks x threads | wall | effective workers |
| --- | --- | --- |
| 8 x 4 | 214 s | 14.0 |
| **16 x 2** | **148 s** | **20.1** |
| 32 x 1 | 215 s | 13.8 |

- **[measured] 16x2 is still the optimum, and by a wider margin than before**
  (1.45x over its neighbours, against 1.31x previously). 32x2 could not be
  measured: it needs 64 CPUs on one node and ccc0497 had only 36 free.
- 32x1 is **granularity**-limited (44 % efficiency, matching `max/mean` below);
  8x4 is **thread**-limited. 16x2 is the better trade of the two.

### Unit histogram (instrumented 32x1)

| quantity | `hoist` | **`ladder`** |
| --- | --- | --- |
| total work | 4211.8 s | **2972.3 s** |
| mean unit | 131.6 s | **92.9 s** |
| max unit | 249.4 s | **210.5 s** |
| min unit | 88.8 s | **50.5 s** |
| **max/mean** | 1.895 | **2.266** |
| max/min | 2.8x | **4.17x** |
| perfect split, 31 workers | 135.9 s | **95.9 s** |

- **[measured] The math work removed 1.42x of work but made the distribution
  *less* uniform**: `max/mean` rose 1.895 -> 2.266 and the spread 2.8x -> 4.17x.
  The heavy channels shrank less than the light ones, which is the opposite of what
  I predicted when I assumed the Bessel work sat in the heavy channels.
- **[measured] So the granularity loss at 32x1 grew**, from 254/135.9 = 1.87x to
  215/95.9 = **2.24x**.

### The refactor's prize is ~1.5x, not 1.87x

The 1.87x was measured against the *current* 32x1 — but 32x1 is not the
configuration we use. Measured against the best configuration:

```
16x2 today            148 s
perfect split, 32x1    95.9 s      ->  1.54x
```

Perfect splitting does not help 16x2 (32 units over 15 workers already smooths
it), so the honest prize for a row-block rewrite is **~1.5x end-to-end**, on one
node, with a validated unit-cost model that reproduces all three measured
configurations to within ~1 %.

**Re-confirmed on the `copyfix` binary**, since every measurement above predates
the copy-path fix in the previous section:

| quantity | `ladder` | **`copyfix`** |
| --- | --- | --- |
| total work | 2972.3 s | **2845.9 s** |
| max unit | 210.5 s | **202.7 s** |
| max/mean | 2.266 | **2.279** |
| perfect split, 31 workers | 95.9 s | **91.8 s** |
| 32x1 wall | 215 s | **213 s** |
| prize vs the best config (16x2 = 141 s) | 1.54x | **1.54x** |

- **[measured] The prize is unchanged at 1.54x.** `max/mean` moved by 0.013, as
  expected: the removed copies were spread across all channels rather than
  concentrated in the heavy ones, so the distribution barely moved. The earlier
  caveat about the histogram being one binary stale is now closed.

### Threads saturate at 2 — this is not Amdahl

Phase wall for one channel, same node: **114 s (1 thread), 72 s (2), 71 s (4)**.

- **[measured] Four threads give 1.4 % over two.** The curve is not Amdahl-shaped:
  from 1->2 threads Amdahl implies `s = 0.26`, from 1->4 it implies `s = 0.50`, and
  no single `s` fits. It is a **saturation**, not a serial fraction.
- **[inferred] This supersedes the "~50 % serial fraction" framing.** The phase
  gains ~1.6x from threads and then stops; per unit there is nothing more to win
  from threads, and the way to use more CPUs is more *ranks*.
- That in turn makes the granularity work **better** motivated, not worse: with
  fine units, 32x1 would approach the 95.9 s ideal, i.e. ~1.5x over the best
  configuration available today, and it needs one node rather than two.

## What a work unit actually contains — and a correction — 2026-10-03

Before starting the granularity work I read the unit and instrumented it, because
the design depends entirely on what is inside a unit. **I had been describing the
unit as a loop over (bra,ket) blocks. It is not.** `set_nnn_force_ho_isospin`
(`NNNForceHOIsospin.F90:78`) builds whole-channel operators, forms
`h = T_jac + vnn_jac + v3n_jac`, **dense-diagonalises `h`**, and — for this case,
where `renorm = srg` — runs a **three-body SRG evolution** on it. Neither a dense
eigensolve nor an ODE integration is a trivially splittable loop, so the plan I
had been proposing for several turns rested on a wrong mental model.

### Measured composition (`#PROF_PHASE`, 32 units, 1 thread, ccc0497)

| phase | total | share |
| --- | --- | --- |
| operator construction | 2468.5 s | **91.5 %** |
| SRG evolution | 226.4 s | 8.4 % |
| dense diagonalisation | 4.5 s | **0.2 %** |

- **[measured] The thing I was most worried about is negligible.** The dense
  diagonalisation is 4.5 s across all 32 units; the largest single one is 0.79 s.
  A distributed eigensolver is not needed and was never going to be needed.
- **[measured] The dominant 91.5 % is the operator construction**, i.e.
  `set_nnn_int_chEFT_n2lo_isospin`, which fills an `nphys x nphys` matrix and
  whose local-3NF routines (`set_two_pion_exchange_c*`, `set_contact_ce`, ...)
  iterate over channel pairs. **This part is block-structured**, which is what the
  refactor needs.
- **[inferred] So the refactor is viable, but for the opposite reason to the one I
  gave.** Not "the unit is a block loop"; rather "the dominant phase is
  block-structured, and the parts that are not are cheap".
- **[inferred] The design constraint is the gather.** After `work` is filled,
  `set_nnn_interaction_chEFT_n2lo` does `this%DMat = cfp^T * work * cfp` and then
  `multiply_non_local_regulator_hospace` — both need the *full* `work`. A split
  unit therefore has to gather before those steps, and the gather + transform +
  SRG is ~9 % of a unit, capping the available speedup near 11x. That is well
  above the 1.54x target, so it does not threaten the plan.
- ~~Two side notes: the channel-independent two-body NN setup inside the unit is
  **0.00 %** (duplicating it per sub-unit costs nothing)~~ — **RETRACTED, see below.**
  That was the routine's *self* time; and `set_nnn_interaction_chEFT_n2lo` itself
  uses the very copy-heavy DMat pattern just fixed in `transform_xis_to_ho`
  (`cfp = jac%GetCFPMat()` then `this%DMat = cfp%T() * work * cfp`) — though that
  was later measured as worthless too (see "Second attempt").

## `ramplarge`'s per-phase profile differs materially from `rampsmall`'s — 2026-10-03

Side observation from the `ramplarge` probe (which OOM'd, see below). It carried the
`#PROF_PRE` and `#PROF_SPLIT` instrumentation, so we get a per-phase profile of a real
production-ramp channel for the first time.

**`#PROF_PRE`, seconds per channel:**

| part | `rampsmall` | `ramplarge` | |
| --- | --- | --- | --- |
| `ls12%init` | 0.569 | **8.64** | 15x |
| `ls3%init` | 0.233 | **3.55** | 15x |
| `init_zx_function` | 0.383 | 0.194 | |
| **`init_fkx_function`** | **16.642** | **0.634** | **26x *cheaper*** |
| everything else | <=0.03 each | <=0.27 each | |

**[inferred] The `init_fkx_function` reversal is not a scaling effect — a bigger space
cannot make a routine 26x cheaper.** The two runs used *different code paths*: the
`rampsmall` figure is from a pre-guard build with an **unconditional**
`gsl_sf_bessel_jl_array(L, x)`, the `ramplarge` figure from the **guarded** build that
truncates at the highest order passing `athr`. So this says the guard is not only a
crash fix but a large **performance** win: the unguarded ladder was computing orders
that the threshold then discarded.

**[measured] Confirmed on `rampsmall` itself, same case / same node / same
configuration — only the binary differs.** The guard build's `#PROF_PRE` was already on
disk, so no new run was needed:

| `rampsmall`, `#PROF_PRE` per channel | pre-guard | **guard** | |
| --- | --- | --- | --- |
| **`init_fkx_function`** | **16.642 s** | **1.250 s** | **13.3x less** |
| `ls12%init` | 0.569 s | 0.564 s | unchanged |
| `ls3%init` | 0.233 s | 0.231 s | unchanged |
| `init_zx_function` | 0.383 s | 0.384 s | unchanged |
| everything else | — | — | unchanged |

- **[measured] `init_fkx_function`'s share of `precalculations` falls from 93.1 % to
  39-51 %** (the spread is across channels; `precalculations` total drops from 17.87 s
  to 2.47-3.21 s per channel). The 93 % figure was therefore measuring work that was
  **computed and then discarded** by the `athr` threshold.
- **[inferred] This re-reads the 6b result.** 6b (the ladder) was measured as 1.13x
  against the *unconditional per-order* baseline, and the 1.35x fusion that followed
  was measured against a build whose `init_fkx_function` was still doing 16.6 s of
  mostly-discarded work. **Both need re-validation against the current (guarded)
  binary before they are quoted again** — they are not necessarily wrong, but their
  baselines contained work that no longer exists.
- **[measured] The wall-clock comparison is confounded and must NOT be quoted yet.**
  The guard build's rampsmall run took **120 s** and the pre-guard `fuse` build's took
  **103 s** — the wrong direction for a change that removes 15.4 s of per-channel work.
  The two ran on ccc0499 hours apart at different co-tenant load. A back-to-back
  same-node A/B is needed to state the guard's wall-time effect.
- **[inferred] Practical consequence:** the `init_fkx_function` line of investigation —
  "the largest single cost in the code, 19 % of the run" — is **closed**. It was an
  artifact of the unguarded ladder, and the honest description is that the guard fixed
  both a crash and a 13x inefficiency in the same routine.

**`#PROF_SPLIT`, per channel, seconds** (`init` / `set` / **`inside`** / `release`):

| ramp | init | set | **inside** | inside/set |
| --- | --- | --- | --- | --- |
| `rampsmall` | 22.5 | 6.1-7.2 | 0.14-0.18 | **2.3 %** |
| `ramplarge` | 13.3 | 59.5-223.6 | 6.9-32.0 | **11.6-14.3 %** |

**[measured] The element loop is ~10x more significant at the production ramp** — ~13 %
of `set` versus 2.3 %. The row-split was abandoned because that loop was ~1 % at
`rampsmall`; at `ramplarge` it is substantial enough to matter, though `set` as a whole
is still the target and the element loop is not its dominant part. **This is another
case of a `rampsmall`-derived conclusion not transferring to the production ramp.**

**The probe itself OOM'd — my error.** I requested `--mem=128G` for 8 ranks, i.e. 16 GB
per rank, when the case needs ~20-34 GiB/rank. Same class of mistake as the original
`--mem=200G` OOM already recorded above: **memory is a request, and I under-requested
it again.** No conclusion depends on the failed run; the two Nmax-40 channels it did
complete are the ones that refuted the 5.37 h.

## `ramplarge` re-measured: the 5.37 h was an artifact, and the case is now practical — 2026-10-03

The real `ramplarge` case, re-run with the current binary at **8 ranks x 4 threads on
ccc0499** — the *same node* and the same process shape as the original 5.37 h
observation:

| channel | original run | **current binary** | speedup |
| --- | --- | --- | --- |
| `j1p-t1` (Nmax 40) | 5.37 h | **~9.7 min** | **33x** |
| `j1p+t1` (Nmax 40) | 7.00 h | **~12.3 min** | **34x** |

Both heaviest channels completed inside the first 20 minutes of the job. **[measured]
The 5.37 h is NOT reproducible.** It was almost certainly an artifact of the shared run
directory (the case directory was reused across three failed attempts) or of the
original node's condition — not a property of the calculation. Two independent
explanations were tested and refuted first (thread contention; the `j3max_initial_3nf`
coupling), which is what moved the suspicion onto the observation.

**[measured] And the SRG is confirmed as the dominant component of a heavy channel:**

    j1p-t1:  construct 143.5 s   diag 4.6 s   srg 354.7 s   -> SRG 70.5 %
    j1p+t1:  construct 162.5 s   diag 5.8 s   srg 483.1 s   -> SRG 74.2 %

That agrees with the ladder's flat40 share (73.8 %) and with the n^3.11 law. So the
prediction I made early on — *the SRG becomes dominant on ramplarge* — was **right
about the share and wrong about the magnitude**: 70 % of a ~12 min channel, not 70 % of
5.4 h.

**This reverses the P3b verdict.** `ramplarge` was abandoned as "not practical at this
size" on the strength of 2/32 channels in 10:19:31. With today's binary it does the two
heaviest channels in 12 min. The case should be re-assessed as a candidate production
ramp rather than written off — and the accuracy/cost knee question in P3b (which ramp
to use) can now be asked again on measured cost rather than on a projection.

**Caveat to close out:** the original run's `ops/` timestamps were used for the 5.37 h,
and that method has now been shown to be unreliable on a reused directory. Any future
per-channel claim should come from `#PROF_*` timestamps inside a single clean run, not
from file mtimes on a shared case directory.

## Contention refuted, and a flaw in my own ladder: `j3max_initial_3nf` — 2026-10-03

### Threads help, and more ranks cost nothing

Same rung (flat32), same four channels, same CPU model, only the shape changed:

| config | wall | heaviest 3body flow (n=2280) |
| --- | --- | --- |
| ladder 4 ranks x **1 thread** | 469 s | **255.9 s** |
| contend 4 ranks x **4 threads** | **132 s** | **56.2 s** — **4.6x faster** |
| contend 8 ranks x 4 threads (8 channels) | — | **58.6 s** — no penalty |

- **[measured] The bandwidth-contention hypothesis is REFUTED, and reversed.** Four
  threads make a flow **4.6x faster**, and doubling the rank count at the same thread
  count costs nothing. So the original `ramplarge` run's thread configuration was
  *helping*, not hurting, and the ladder's 4x1 numbers are a pessimistic baseline.
- **[inferred] That widens the gap rather than closing it.** Correcting the observed
  5.37 h channel for the 4.6x that threads should have bought makes the unexplained
  factor ~35x, not ~7.7x. Also worth noting: DVODE `steps` differ between the 1-thread
  and 4-thread runs (98 vs 76) for the same n — MKL threading changes the summation
  order in the ODE right-hand side, so the adaptive integrator takes a different path.
  Same channel, same physics, different step count: worth remembering before comparing
  step counts across configurations.

### The flaw: `jmax3=1` silently set `j3max_initial_3nf=1`

`j3max_initial_3nf` defaults to `-1`, and `NuHamilInput.F90` sets it to
**`params%jmax3`** when it is unset. My ladder inputs set `jmax3 = 1` (to get 4
channels) and never set `j3max_initial_3nf`, so every ladder rung built the 3NF with
**`J3max_initial_3nf = 1`** — while production uses **15** (`jmax3 = 15`).

`J3max_initial_3nf` is passed into the local 3NF construction
(`NNNForceHOIsospin.F90:448,477,482`), so:

- **[inferred] The `construct` column of the ladder table — and therefore the SRG
  *share* derived from it — is NOT representative of the production case.** The share
  figures (3.1 % ... 73.8 %) were computed as `srg / (construct + diag + srg)`, and
  `construct` was measured under a smaller 3NF truncation than production uses.
- **[measured] The `srg` column itself is sound**, because the flow acts on `h`, and
  `h`'s dimension matched production exactly: the flat40 heaviest flow has n = 4263,
  identical to `ramplarge`'s `j1p+t1` orthonormal state count (4263).
- **[inferred] This is a plausible home for the missing ~35x.** `construct` was
  already known to dominate a `rampsmall` channel (42.2 % `init` + 56.8 % `set` in the
  abandoned row-split work). If `construct` at J3max = 15 is vastly more expensive than
  at J3max = 1, then `construct` — not the SRG — is where `ramplarge`'s hours went,
  which is consistent with every measurement made so far.

**Test done — REFUTED too.** The identical flat36 rung at 4 ranks x 1 thread, with
only `j3max_initial_3nf` changed from 1 to 15:

| flat36, 4r x 1t | construct | diag | srg | srg share |
| --- | --- | --- | --- | --- |
| `j3max_initial_3nf = 1` (ladder) | 683.39 s | 16.18 s | 1191.29 s | 63.0 % |
| `j3max_initial_3nf = 15` (production) | **668.20 s** | 15.65 s | **1193.99 s** | **63.6 %** |

**[measured] Identical within 2 %**, wall 1029 s vs 1044 s (1.4 % apart). So although
the flag really is set differently, it has **no measurable effect on this channel's
cost**, and the ladder's `construct` column and SRG shares stand as measured. The
coupling is a latent trap for anyone else building a reduced `jmax3` case, but it is
not the missing factor.

**Also now suspect — and after two refutations, it is the prime suspect: the observed
5.37 h itself.** Every measurement since is inconsistent with it by 27-35x, and it came
from an `ops/` file mtime on a run directory shared with two earlier attempts. Two
plausible explanations have now been tested and refuted (thread contention; the
`j3max_initial_3nf` coupling), which shifts the suspicion onto the original observation
rather than onto the code.

**And a reframing worth acting on:** with today's binary (2x+ from the MKL relink and
the redundancy fixes) plus the measured 4.6x from threads, a heavy `ramplarge` channel
should take **~10-20 min**, not 5.4 h. So the run that was abandoned as impractical may
now fit inside a backfill window. **Re-measuring one heavy `ramplarge` channel with the
current binary is the decisive next step** — it either reproduces the 5.37 h (and the
mystery is real) or it does not (and `ramplarge` becomes practical).

## Ladder complete: the SRG flow is 8 % of a `ramplarge` channel — the answer is NO — 2026-10-03

The ladder now reaches the top of the real ramp (the guard fix unblocked flat40).

| rung | 3body `n_max` | 3body flow sum | `construct` sum | NN-2body sum | NN/3body | **SRG share** |
| --- | --- | --- | --- | --- | --- | --- |
| flat16 | 351 | 1.18 s | 37.75 s | 4.432 s | 3.743 | 3.1 % |
| flat20 | 632 | 8.15 s | 64.00 s | 4.447 s | 0.546 | 11.5 % |
| flat24 | 1033 | 31.98 s | 113.51 s | 4.444 s | 0.139 | 22.2 % |
| flat28 | 1575 | 144.11 s | 205.21 s | 4.443 s | 0.031 | 41.3 % |
| flat32 | 2280 | 474.93 s | 369.57 s | 4.456 s | 0.009 | 56.2 % |
| flat36 | 3169 | 1176.27 s | 683.39 s | 4.524 s | 0.004 | 63.0 % |
| **flat40** | **4263** | **3355.50 s** | **1161.00 s** | 5.573 s | 0.002 | **73.8 %** |

- **[measured] Final exponent `p = 3.11`** over n = 351 -> 4263 (successive 3.16, 2.86,
  3.36, 3.39, 2.51, 3.43). The three-body flow is O(n^3) throughout, with DVODE steps
  rising only gently (76 -> 103). `construct` scales as n^1.8 in the upper range.
- **[measured] The extrapolation validated to 0.7 %.** From flat36 the law predicted
  **1625 s** for a heavy flat40 flow (n=4263). Measured: **1612.9 s** (ode 1573.4,
  diag 37.1, u 2.4; steps 103, nfe 169). The n^3.11 law is trustworthy over this range.
- **[measured] flat40 completed clean** — wall **2505 s**, exit 0, **zero GSL errors**,
  so the ladder-guard fix holds at the top of the ramp.

**The answer to P3b-i's question: NO, the three-body SRG flow is not the `ramplarge`
bottleneck.** The heaviest flat40 flow is 1612.9 s = **26.9 min**, against the observed
`ramplarge` `j1p+t1` channel wall of **5.37 h** — so the SRG is **8.3 %** of it.

That settles P3b-i stage 1-2 as a well-supported negative result. It also **refutes the
prediction I made** when the SRG was believed dominant ("a 300-430x n^3 term inside an
8.4 % share would make the SRG dominant on ramplarge"). The SRG *is* dominant as a
share of a channel's own compute — 73.8 % by flat40 — but a channel's compute is not
where the 5.37 h went.

### The ~7.7x that remains, and the experiment that would settle it

The comparison is now like-for-like in `n` and free of extrapolation:

| | heaviest channel, n=4263 | configuration |
| --- | --- | --- |
| ladder flat40 | ~2505 s wall for 4 channels (**~42 min**) | **4 ranks x 1 thread** |
| original `ramplarge` | **5.37 h = 322 min** | **8 ranks x 4 threads** |

**~7.7x.** The obvious difference is concurrency: the ladder ran 4 single-threaded
flows, while the original ran **8 heavy flows x 4 threads = 32 threads on one node**,
all executing large O(n^3) dgemm. Memory-bandwidth contention is the leading
hypothesis and it fits the shape of everything measured so far.

- [ ] **Decisive experiment: run flat40 at 8 ranks x 4 threads** — the same shape as
  the original — and compare the per-flow time against the 4x1 number just measured.
  If the flow inflates several-fold, the bottleneck is thread/bandwidth contention,
  not the algorithm, and the fix is a configuration choice rather than code.

This is the measurement to do before any fix proposal, and unlike the earlier attempts
it needs no extrapolation and no unaffordable run.

## `#PROF_FLOW`: a flow is the ODE, and the three-body flow is n^3.1 — 2026-10-03

`#PROF_FLOW` (stage 1 of P3b-i) reports per flow: `tag` (two- vs three-body), `n`,
DVODE `steps`/`nfe`, and the split **ode / diag / u**. First question it was built to
answer: is a flow's cost the ODE integration or the two dense diagonalisations that
follow it? **Decisively the ODE: 95-98.7 % of every flow, with diag+u at 1-5 %.**

**The ladder.** `ramp = "flat<NN>"` (all channels at one Nmax) with `jmax3 = 1`
(4 channels, J=1/2, Nmax varied), 4 ranks x 1 thread, ccc0499, cold:

| rung | 3body `n_max` | 3body flow sum | `construct` sum | NN-2body flow sum | NN/3body | **SRG share of channel** |
| --- | --- | --- | --- | --- | --- | --- |
| flat16 | 351 | 1.18 s | 37.75 s | **4.432 s** | 3.74 | 3.1 % |
| flat20 | 632 | 8.15 s | 64.00 s | **4.447 s** | 0.55 | 11.5 % |
| flat24 | 1033 | 31.98 s | 113.51 s | **4.444 s** | 0.139 | 22.2 % |
| flat28 | 1575 | 144.11 s | 205.21 s | **4.443 s** | 0.031 | 41.3 % |

- **[measured] The three-body flow cost scales as `n^3.12`.** Heaviest single flow:
  n=351 0.676 s, 632 4.332 s, 1033 17.677 s, 1575 72.891 s. Successive exponents
  3.16 / 2.86 / 3.36 over the whole range — i.e. the expected O(n^3) per right-hand
  side, very slightly steeper. **DVODE steps are essentially constant (75-89) and
  `nfe` 111-160, so the growth is arithmetic, not the integrator struggling** — there
  is no step-count explosion to fix.
- **[measured] `construct` scales far more gently**, ~`n^1.4` in sum (and n^0.9 to
  n^1.4 across successive rungs).
- **[measured] Therefore the SRG share rises monotonically and steeply:**
  **3.1 % -> 11.5 % -> 22.2 % -> 41.3 %** across Nmax 16 -> 28.
- **[measured] The two-body NN flow cost is constant — 4.432 / 4.447 / 4.444 /
  4.443 s — at every rung**, confirming directly that it depends only on
  `N2max`/`J2max_NNint` and not on the three-body ramp. It is called **26 times per
  three-body channel** (104 per rung). Its share of the flow cost falls from **3.74x
  the three-body flow at Nmax 16 to 0.031x at Nmax 28**. See the P3c issue: the
  redundancy is the *larger* flow cost at low Nmax and negligible at high Nmax.

### The extrapolation does NOT explain `ramplarge`, which refutes my own prediction

I predicted that a ~300-430x `n^3` term inside an 8.4 % share would make the SRG
**dominant** on `ramplarge`. Extrapolating the measured law from flat28 (n=1575,
72.891 s) to the `ramplarge` `j1p+t1` channel (n=4263):

    predicted heaviest three-body flow  ~ 1625 s  ~ 27 min

The observed `ramplarge` `j1p-t1` / `j1p+t1` channels took **5.37 h / 7.00 h**. So the
SRG accounts for **at most ~8 %** of that wall — the extrapolation misses by ~10x.
**[inferred] The three-body SRG is not the `ramplarge` bottleneck**; it becomes large
(41 % by Nmax 28) but does not explain 5.4 h.

**The ~10x remains unexplained, and none of the candidates is tested:**

- The 8x4 run had **8 heavy flows running concurrently on one node**, all executing
  large O(n^3) dgemm — the ladder ran 4 concurrent single-threaded flows. Bandwidth
  contention is a real possibility and would inflate the observed wall time.
- **Cache/working-set**: at n=4263 a matrix is ~145 MB and the ODE carries many of
  them, so the working set leaves cache and the effective flop rate can collapse
  well beyond the n^3 prediction. That would steepen the exponent above n=1575.
- DVODE `method_flag=10` (BDF) with `mxstep=50000`: step counts are flat to n=1575
  but that is not proof they stay flat.

**Next, and it is cheap:** extend the ladder to `flat32`/`flat36`/`flat40` with the
same 4x1 configuration. flat28 (n=1575) took only **178 s** wall, so flat40 is
~20-70 min at the measured exponent — affordable, and it settles whether the
extrapolation or the observation is wrong, without the 8-way concurrency of the
original run. Only then is a fix proposal worth writing.

## A latent GSL abort at large `l` + small `x`, and the guard that 6b bypassed — 2026-10-03

The flat40 rung **crashed** (task 3, core dumped) after 123 s:

    gsl: gamma.c:1454: ERROR: underflow
    Default GSL error handler invoked.

`gamma.c:1454` is inside **`gsl_sf_lngamma_complex_e`**, and the message is printed by
GSL's *default* error handler, which **aborts the process**.

**Which call reaches it.** A standalone C probe (on a compute node) installs a
non-aborting handler and sweeps every GSL binding our code uses over the argument
ranges `init_zx_function` / `init_fkx_function` / `precalculations` feed them at
Nmax up to 40 (`L = Nmax+2 = 42`):

| binding | result |
| --- | --- |
| `gsl_sf_bessel_jl_array(l, x)` | **underflow** for `l = 32..42` at `x = 1e-8`, `l = 40,42` at `1e-6` |
| `gsl_sf_bessel_jl(l, x)` | **the same errors at the same arguments** |
| `gsl_sf_legendre_Pl(l, x)` | no error |
| `gsl_sf_legendre_sphPlm(l, m, x)` | no error |
| `gsl_sf_lngamma(x)`, `gsl_sf_laguerre_n`, `gsl_sf_gegenpoly_n` | no error |

- **[measured] The GSL fragility is NOT new** — the per-order `gsl_sf_bessel_jl`
  raises the identical error at the identical arguments. So this is not a 6b
  regression in the sense of GSL behaviour.
- **[measured, source] `gsl_sf_legendre_Pl_e` uses a plain upward recurrence for
  `l < 100000`** (`legendre_poly.c`), so the Legendre path is safely ruled out despite
  `legendre_con.c` being a caller of `lngamma_complex`.

**What 6b did break: it bypassed the guard.** `spherical_bessel(l, x)` computed
`a = athr(l)` and **returned 0 before calling GSL** whenever `x < a`. The pre-6b
callers therefore never asked GSL about the underflowing `(l, x)` combinations —
the threshold doubled as protection. `spherical_bessel_ladder` calls
`gsl_sf_bessel_jl_array(L, x)` **unconditionally**, and the callers apply
`if (a < athr(x)) v = 0` *after* it, which zeroes the values but cannot prevent the
call. Since GSL's default handler aborts, the result is a core dump.

- **[inferred] Why flat32 survived and flat40 did not:** the smallest argument
  reached depends on the smallest `r` in the channel's coordinate list, which is not
  a simple function of Nmax. flat16/20/24/28/32 completed; flat40 aborted. The bug is
  therefore **latent and input-dependent**, not a clean Nmax threshold.
- **[inferred] This is a correctness bug, not just a benchmark one**: nothing bounds
  `x` from below in production either, so any case that reaches a small enough `r`
  with a large enough `lmax` will abort.

**Fix (not yet implemented).** Truncate the ladder at the highest order that passes
the threshold and zero the rest — which is exactly what the pre-6b guard produced — so
GSL is never asked for the underflowing orders:

    lmax1 = 0
    do x = L, 0, -1
      if( a1 >= athr(x) ) then; lmax1 = x; exit; end if
    end do
    lad1(:) = 0.d0
    if( lmax1 > 0 ) call spherical_bessel_ladder(lmax1, a1, lad1)

Installing a non-aborting GSL error handler is worth doing as defence in depth, but
on its own it would let GSL return garbage for orders the threshold does not cover —
so the truncation is the real fix and the handler is the belt to its braces.

**Status:** flat40 is blocked on this. flat32 completed (wall 469 s); flat36 was
still running when this was written.

## Operational: an over-long `--time` makes a job unstartable, reported as "Priority" — 2026-10-03

Three ladder jobs (flat32/36/40) sat `PENDING (Priority)` for over 40 minutes on
scavenger. The node they were pinned to had **74 of 128 CPUs idle and ~995 GB free**,
so neither capacity nor the pin was the cause.

**My first diagnosis was wrong.** I told the user the `--nodelist=ccc0499` pin was the
trap, on the reasoning that no *other* pending job targeted that node. A probe sweep
refuted it: a 1-CPU job pinned to ccc0499 ran in 6 seconds.

**The actual cause is the time limit.** Probes of identical shape (4 CPU, 96 G, pinned
to ccc0499, same 74 idle CPUs), varying only `--time`:

| request | outcome |
| --- | --- |
| 4 CPU / 96 G / 00:05:00 | ran immediately |
| 4 CPU / 96 G / 01:00:00 | ran immediately |
| 4 CPU / 96 G / 01:30:00 | ran immediately |
| 4 CPU / 96 G / 02:00:00 | **PENDING (Priority)** |
| 4 CPU / 96 G / 04:00:00 | **PENDING (Priority)** |
| 4 CPU / 64 G / 04:00:00 | PENDING (Priority) — memory size is irrelevant |
| 1 CPU / 96 G / 00:05:00 | ran immediately — CPU count is irrelevant once time is short |

- **[measured] Slurm's backfill will only start a job if it can finish before the
  resources are needed by higher-priority pending work.** ccc0499's idle CPUs are
  spoken for in the near future, so the backfill window is currently between 1.5 h and
  2 h. Any job whose `--time` exceeds that window cannot start — and Slurm reports the
  reason as **`Priority`**, which reads like "you are far down the queue" when it
  actually means "your own time limit is too long to fit".
- **[measured] The window moves.** `--time=02:00:00` ran the flat20/24/28 rungs
  earlier the same day and does not fit now. There is no fixed threshold to memorise.
- **[inferred] The operational rule: set `--time` as close to the expected runtime as
  you can justify.** A generous time limit is not free — on a busy preemptible
  partition it can make a job unschedulable. All three rungs started within seconds
  once resubmitted at `--time=01:30:00`.

This is the second time today a Slurm-level detail cost a measurement cycle rather
than the physics doing so; the first was `set -euo pipefail` plus a missing
`manifest.json` aborting `run_case.sbatch` with no diagnostic at all (now fixed).

## The memory hypothesis for `ramplarge` is REFUTED — 2026-10-03

Tested because the recorded explanation for `ramplarge` being ~770x slower per
channel was "memory", and because a physics problem and a resource-request problem
need different fixes. Three forms of the hypothesis, all unsupported.

### H1 — the runs were throttled by their cgroup limit: **refuted**

Slurm records for the three `ramplarge` attempts (`sacct`, step MaxRSS = max over
tasks):

| job | config | node | peak RSS/rank | total peak | request | used | outcome |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 11113167 | 32x1 | ccc0259 | 20.48 GiB | ~655 GiB | 200 G | **328 %** | **OUT_OF_MEMORY** |
| 11117512 | 8x1 | ccc0498 | 20.74 GiB | 166 GiB | 250 G | 66 % | cancelled at 3:04 |
| 11119503 | 8x4 | ccc0499 | 33.64 GiB | 269 GiB | 450 G | 60 % | cancelled at 10:19 |

- **[measured] Neither 8-rank run was near its limit** — 60 % and 66 %. Only the
  32-rank run exceeded, and that is the already-recorded `--mem=200G` request error
  (655 GiB needed), not a hardware ceiling.
- **[inferred] The mechanism does not fit either.** A cgroup memory limit produces
  **OOM-kill**, not gradual slowdown — and that is exactly what the one run that
  exceeded did. We have never observed the intermediate "slow because pressured"
  behaviour that the hypothesis requires.

### H2 — the large per-rank footprint is itself slow: **refuted, and the thread evidence points the other way**

| config | peak RSS/rank | |
| --- | --- | --- |
| 8x1 | 20.74 GiB | 1 thread |
| 8x4 | 33.64 GiB | 4 threads — **1.62x more memory** |

- **[measured] More threads cost more memory and *less* time.** On `rampsmall`,
  32x1 = 215 s vs 16x2 = 103 s. Going to threads increased peak RSS by ~1.6x and
  halved the wall time. Footprint is not the limiting factor in the observed range.

### H3 — memory grows during the run (all-to-all redistribution), so late channels suffer: **refuted**

- **[measured] Peak RSS is flat across rank count on `rampsmall`**: 1652.6 MB (8x1),
  1653.0 MB (32x1), 1655.9 MB (8x4). If every rank accumulated all other ranks'
  matrices, peak RSS would grow with the number of ranks. It does not.
- **[measured] And the redistribution is 0.031 s of 267.8 s** — negligible in time.

### Direct experiment: memory headroom, doubled, changes nothing

Same case, same node, same binary, same configuration (16x2, ccc0499), only the
allocation differs:

| `--mem` | headroom | wall |
| --- | --- | --- |
| 32 G | ~18 % (peak 1.63 GiB/rank x 16 = 26.1 GiB) | **108 s** |
| 64 G | ~59 % | **109 s** |

- **[measured] Doubling the available memory changes wall time by 1 %** — inside the
  usual run-to-run spread. There is no memory-headroom sensitivity to explain the
  `ramplarge` behaviour.

### Two corrections this test produced

1. **My own P3b-i plan's trap #1 was backwards.** I wrote that the 2/32 channels
   which completed in the 10:19 run "were almost certainly Nmax 24" (the cheapest).
   They were **Nmax 40 — the heaviest**, because the farm builds its unit list as
   `do t; do j = 1, jmax3; do p`, so **low J (largest Nmax) is dispatched first**.
   The `ops/` file times give 5.37 h and 7.00 h for `j1p-t1` and `j1p+t1`. That is
   the solid number for a heavy `ramplarge` channel.
2. **The recorded "~770x per channel" is not a like-for-like ratio** and should not
   be used as one: it compared `rampsmall` 32/32 in 13:04 against `ramplarge` 2/32
   in 10:19:31, i.e. different configurations *and* different channel mixes. The
   defensible statement is per-channel and same-configuration.

### What is left: the state dimension, and it fits

| channel | `rampsmall` orthonormal states | `ramplarge` | ratio | **cubed** |
| --- | --- | --- | --- | --- |
| `j1p+t1` | 632 | 4263 | 6.74 | **307x** |
| `j5p+_t1` (heaviest each ramp) | 1503 | 11340 | 7.54 | **429x** |

- **[measured]** The heaviest `rampsmall` channel (`j5p+_t1`, 4510 physical states,
  Nmax 20) takes **202.7 s** single-threaded; note the heaviest channel is **not**
  the lowest J — dimension grows with J faster than the ramp shrinks Nmax.
- **[inferred] The SRG flow is O(n^3) per ODE right-hand side**, and `n` grows by
  ~7x, so n^3 alone gives **300-430x** on that term while the rest of a channel
  scales more gently. On `rampsmall` the SRG was measured at **8.4 % of a unit**;
  a ~300-400x term inside that would make the SRG a **dominant** share of a
  `ramplarge` channel. **That is a prediction, and it is exactly what P3b-i stage 1
  is designed to test** — it is not established here.

## The two-body NN SRG flow is re-run in every three-body channel — 2026-10-03

Raised as: "the SRG flow for `ramplarge` was excruciatingly slow; I think we
discovered the flow was being repeated — did we ever address that?" **Answer: no,
it was never addressed, and neither `FINDINGS.md` nor `PLAN.md` contains any record
of the discovery.** The memory needs re-establishing from the code, which is what
follows.

**The repetition is real, and it is 32x.**

- `set_nnn_force_ho_isospin` (per three-body channel) builds the two-body pieces at
  `NNNForceHOIsospin.F90:104-116`, including
  `call vnn_sub_relspin%SetNNForceHOIsospin(U_sub_relspin, params)`.
- With `renorm = "srg"` and `renorm_space2 = "ho"` — our input sets the first and
  the second is the default — `NNForceIsospin.F90:215` takes the branch
  `call renorm_ho_space_isospin(...)`.
- That routine (`:317`) contains
  ```fortran
  do ich = 1, two%NChan
    call HOSRGChannel(vnn%MatCh(ich), Trs%MatCh(ich), vnn%ms%jpst(ich), alpha, hw, ...)
  end do
  ```
  and `HOSRGChannel` runs a full SRG H-flow via `Renormalization`'s `SRGSolver`
  (`sol%init(h, 'Hflow')` -> `SRGFlow` -> `SRGHflow` -> `dvode_f90`).
- **The two-body space does not depend on the three-body channel**: `relspin%init`
  uses `params%N2max` and `params%J2max_NNint`, not the channel's `Nmax`
  (`NNNForceHOIsospin.F90:105`). So all 32 repetitions compute **identical** results
  and are trivially cacheable.

**[inferred] Profile consistency**: exactly one SRG symbol family appears —
`__renormalization_MOD_srghflow` plus `dvode_f90_m` (dvstep 0.14 %, dvnlsd 0.13 %,
...) — and **no `srghuflow` / `srgomegaflow`**. That is consistent with
`HOSRGChannel` using mode `'Hflow'`, and it means the two-body and three-body flows
share the same symbol, so the flat profile cannot apportion them.
**[inferred]** Most of a flow's cost is inside its ODE right-hand side (a dgemm
commutator) and the two `DiagSym` calls at the end of `SRGHflow`, i.e. attributed
to MKL, not to an SRG symbol. **So neither the flat profile nor `#PROF_PHASE` sizes
this repetition — it must be timed directly.**

**Does it explain `ramplarge`? Not obviously.** The two-body space is fixed by
`N2max` / `J2max_NNint`, which do not scale with the three-body ramp, so the 32x NN
redundancy costs about the same at both ramps. The `ramplarge` blow-up
(770x per channel vs `rampsmall`) is more likely the **three-body** H-flow: its ODE
state is `n(n+1)/2` and each RHS evaluation is O(n^3), with two more O(n^3)
diagonalisations at the end, and `n` grows with the channel's `Nmax` — which the
ramp raises directly. Both remain to be measured; neither is established.

**Retraction.** The earlier note that the channel-independent two-body NN setup was
"0.00 %" used the routine's self time and is therefore wrong: the cost lives in its
callees. Recording it rather than deleting it, since it was used to justify a
design conclusion.

**Next:** instrument `renorm_ho_space_isospin` / `HOSRGChannel` inside
`set_nnn_force_ho_isospin` to size the 32x repetition on `rampsmall`, and time the
three-body `SRGHflow` on `ramplarge` to see whether that is where the ramp
blow-up actually lives.

`#PROF_PHASE` is left in place alongside `#PROF_UNIT`.

### Row-split stage 1 (guard `v`): kept as a prerequisite, but zero timing gain

`set_nnn_int_chEFT_n2lo_isospin_local` allocated `v(N(N+1)/2)` and stored every
matrix element into it, in all five LEC passes — but `v` is only ever read back by
five `write(50) v` dumps that run only when `save_3nf_before_lec` is set, which is
`.false.` by default and unset in our inputs. Allocation and store are now guarded;
a zero-size actual keeps the assumed-shape dummy legal.

- **[measured] No timing benefit.** Same-node A/B on ccc0499, 16x2, cold:
  **139 s before, 139 s after.** Numerically exact: deuteron unchanged,
  `accept.py` PASS, output identical in all 456 320 values.
- **[inferred] Why it is nil:** the store volume is `5 x N(N+1)/2` doubles per
  channel, which is small next to the rest of a channel even before the
  accumulation into `this`. Below the ~1.6 % noise floor for this case.
  The plan had listed a "candidate small win" here; that part did not materialise.
- **Kept anyway, on a design reason rather than a performance one**: it removes the
  `v` array from the row-split design entirely, so stage-2 block units need no
  scratch array or store at all. This is the case where "no measured benefit" does
  *not* mean revert — unlike `-march` and the `chEFT_n2lo` copy rewrite, which added
  a constraint or churn in exchange for nothing.

## The largest single cost in the code: `init_fkx_function` — 2026-10-03

Following the abandoned row-split, the lead was `precalculations`
(`NNNForceLocal.F90:1293`), which runs once per channel and costs ~20 s. I
suspected the eight coupling-coefficient store `%init`s, since most depend only on
`Nmax` and would be rebuilt 32 times. `#PROF_PRE` times every part of it.

Per channel (16x2, ccc0499), seconds:

| part | s | share |
| --- | --- | --- |
| **`init_fkx_function`** | **16.64** | **93.0 %** |
| `ls12%init` | 0.569 | 3.2 % |
| `init_zx_function` | 0.383 | 2.1 % |
| `ls3%init` | 0.233 | 1.3 % |
| `jjx%init` | 0.026 | 0.1 % |
| `CGs%init` | 0.010 | 0.06 % |
| `lsj12`, `lsj3`, `kkxy`, `spin12` `%init` | <=0.002 each | ~0 |
| meshes + `radial_ho_wf` table | 0.001 | ~0 |
| `init_p_mesh_tables`, `init_z0_function`, `init_fk_function` | 0.000 | ~0 |
| **total** | **17.9** | |

- **[measured] My suspicion was wrong by two orders of magnitude.** The coupling
  stores — the "rebuilt 32 times" hypothesis — are **0.84 s together (4.7 %)**,
  not the cost. `init_fkx_function` is 93 % of it.
- **[measured] Scaled up: 16.64 s x 32 channels = 533 s, about 19 % of the whole
  run** (2845.9 s of heavy-farm work). **This is the largest single cost anyone has
  identified on this project**, and it is one routine.
- **[measured, cross-check] The flat profile agrees**: `f1_func` 6.21 % +
  `f2_func` 5.47 % = 11.7 % of the run, and both are called from
  `init_fkx_function`'s Legendre mesh sums — ~62 % of its cost. The remainder is
  the Bessel-ladder part at k=0.
- **[inferred] The 6a/6b math work was aimed at the right place.** The `Pl` table
  hoist (items 1-2) and the Bessel ladder (6b) were both in
  `init_fkx_function`; the ladder's k=0 share is now the ~38 % that is *not*
  `f1_func`/`f2_func`.
- **[inferred] So the next target is `f1_func`/`f2_func` (11.7 % of the run)**, then
  the k=0 ladder residue. Neither is approachable by the row-split logic: this is
  per-channel arithmetic on fixed-size meshes, independent of the matrix
  dimensions, which is also why `precalculations` costs the same in every channel
  (18.0-22.9 s, 1.27x spread).

Note the shape of this: three times in this session a phase-level summary
("construct 91.5 %", "91.5 % of the work", "the coupling stores") pointed at the
wrong place, and only per-component timing settled it. Timing the smallest named
parts first would have been cheaper than reasoning about the largest.

## Fixed: a 19x redundancy in `init_fkx_function` — 1.35x, bit-identical — 2026-10-03

`f1_func` and `f2_func` are, between them, the single largest cost in the program
(11.7 % of the run). Both compute a 100-point p-mesh Bessel sum,
`sum_i w_i j_l(r p_i) / den_i`, with `l = 1` and `l = 2` respectively, and both are
called from the k=1 and k=2 blocks of `init_fkx_function`, which were shaped:

```fortran
do x = 0, L                                  ! x OUTER
  do i = 1, size(xis)
    do j = 1, NMesh_cos
      r = sqrt(rr_i - 2 r_i r_i' cos_j)      ! depends only on (i,j)
      s = s + wcosth * pl(x,j) * f1_func(r) / r
```

**`r`, and therefore `f1_func(r)` and `f2_func(r)`, do not depend on `x`** — yet
they were recomputed for every one of the `L+1` values of `x`. `L` is `Nmax+2`, so
this was a **19x redundancy on the hottest path in the program**.

The two blocks are now fused with `i` outermost and `j` next, so both Bessel sums
are evaluated once per `(i,j)` and reused across all `x`; `r**2` is hoisted too
(removing the per-`x` `__powidf2` call). `Pl` moves into a small `pltab(0:L,
NMesh_cos)` table computed once.

| 16x2, ccc0499, cold | wall |
| --- | --- |
| before | 139 s |
| **after** | **103 s** (1.35x) |

- **[measured] Bit-identical.** deuteron unchanged, `accept.py` PASS with the same
  4.01e-06 worst element, and the output identical to the previous binary in **all
  456 320 values**. The fusion preserves the term order exactly — for fixed `(i,x)`
  the `j` contributions still accumulate in ascending `j`, each still formed as
  `((wcosth*Pl)*f)/...` — so this is a pure speedup with provably unchanged physics.
  That is a stronger result than the 1.34x hoist earlier, which needed a
  same-binary repeat to establish its reproducibility limits.
- **[inferred] Why the 1.35x exceeds the ~1.12x the 11.7 % share predicted:** the
  share was measured on the pre-fusion profile, where the two functions were being
  called 19x too often. Removing 18/19 of a cost that large releases more than its
  nominal share, and the fusion also drops 19 parallel regions down to one.
- **Cumulative on this case at 16x2: 206 s -> 103 s = 2.00x.**

Next: re-profile. The bottleneck has certainly moved — `f1_func`/`f2_func` should
now be ~0.6 % rather than 11.7 %, and `init_zx_function`'s k=0 ladder (already
hoisted once, and genuinely `x`-dependent so not hoistable further) is the obvious
next candidate.

## Node calibration probe: built, and NOT validated — 2026-10-03

Idea: scavenger placement is a hidden variable worth up to 1.67x, and pairing
every experiment on one node is expensive because queue time is the real
bottleneck. `bench/nodecal.c` measures a fixed ~20 s of work — single-thread and
8-thread `dgemm`, and a streaming triad with a working set past L3 — to produce a
per-node normalisation factor.

It does **not** work, and the failure is instructive.

| node | CPU | gemm1 (v1 / best-of-5) | triad1 (v1 / best-of-5) | full-case 8x1 |
| --- | --- | --- | --- | --- |
| ccc0497 | EPYC 9555 | 64.8 / 66.5 | 45.5 / 49.6 | 1360 s |
| ccc0499 | EPYC 9555 | 49.3 / 56.1 | 12.9 / 18.9 | 1398 s |
| ccc0386 | Xeon 8358 | 83.3 / 94.4 | 15.8 / 15.9 | 1947 s |
| ccc0258 | EPYC 7702 | 24.9 / 42.4 | 20.8 / 23.3 | — (32x1: 2294 s) |

- **[measured] v1 (one sample each) is invalid.** ccc0497 and ccc0499 have the
  *same CPU model*, yet came out 1.31x apart on `gemm1` and **3.5x** apart on
  `triad1` — while their full-case times agreed to 2.8 %. Identical hardware
  cannot differ that much by capability, so the probe was measuring **co-tenant
  load**, not the node.
- **[measured] Best-of-5 helps but does not rescue it.** The identical-CPU gap
  narrows to 1.19x (`gemm1`) and 2.6x (`triad1`). Sampling for ~20 s does not
  find an uncontended moment when the co-tenant job runs for hours.
- **[inferred] Conclusion: do not use this as a normaliser.** Keep pairing
  configurations on one node. The probe stays in `bench/` as a diagnostic, but
  it is not a calibration factor, and no result should be divided by it.
- **[measured, and more interesting] It is not even clear what the full case is
  bound by.** `gemm1` ranks ccc0386 *best* (94.4) and `triad1` ranks it *worst*
  (15.9), and the full-case time agrees with `triad1` — the slowest node is the
  one with the weakest single-stream bandwidth, not the weakest GEMM. If the
  workload is memory-bandwidth-bound rather than flop-bound, that reframes both
  P3 (memory layout and the result redistribution matter more than arithmetic)
  and P4 (a GPU would be accelerating the wrong thing). **Open question; the
  next sampling profile should be read with it in mind.**

## GPU toolchain reconnaissance — 2026-10-02

- **[measured] `nvcc` is already available**: cuda/12.4, 12.6 and 12.8 all provide
  a working `nvcc`. **A CUDA C++ arm of the bake-off needs no installation at all.**
- **[measured] `gfortran` cannot offload to NVIDIA.** `-foffload=nvptx-none` fails
  with *"GCC is not configured to support 'nvptx-none'"*; the only valid arguments
  are `default` and `disable`. So the existing toolchain cannot be GPU-enabled by
  adding a flag — a different compiler or a non-Fortran kernel is unavoidable.
- **[measured] No `nvfortran`/`pgfortran` anywhere**, as previously established.
- **[measured] The network is reachable** (`developer.nvidia.com:443`,
  `github.com:443`), so the NVIDIA HPC SDK is obtainable — but it is several GB and
  must land under scratch, never `$HOME`.
- **[measured] Spack lives at `/sw/apps/spack/spack`**, not the path recorded
  earlier.
- **[measured] GPUs reachable from `scavenger`**: H100 x8 and x1/x3 nodes (sm_90),
  L40S x8 (sm_89), RTX 6000 x8 (sm_75), V100 x2 (sm_70). No A100/H200 appeared in
  the scavenger GPU list. **The bake-off target architecture therefore matters**:
  sm_75 and sm_90 are different optimisation targets, and code tuned on one is not
  automatically right for the other.

### Consequence for the P4 plan

The originally-planned three-way bake-off was
*nvfortran vs `ifx` OpenMP-target vs C++/CUDA*. Two corrections:

1. **`ifx` should be struck.** Intel's OpenMP offload targets Intel GPUs, not
   NVIDIA, and none of our nodes are Intel-GPU. It was never a viable arm here.
2. The bake-off is really **two arms**:
   - **A. CUDA C++** — already-installed `nvcc`, hot kernel extracted behind
     `ISO_C_BINDING`. No installation, no toolchain risk, but it means writing the
     kernel twice (C++ and Fortran) and keeping them in step.
   - **B. NVHPC `nvfortran`** — install the SDK under scratch; gives OpenACC /
     CUDA Fortran with far less code disruption, at the cost of a multi-GB
     install and a compiler ICC does not currently provide.

Recommendation: start with **A** for the bake-off, because it is the only arm
whose prerequisite already exists, and it answers the real question ("is this
kernel worth porting at all?") without betting on an install. Keep **B** as the
production path if A shows the speedup is real — OpenACC across many kernels beats
hand-written C++ for maintainability.

## Cluster environment

- **[measured]** `IllinoisComputes`: 22 nodes x 128 cores, 512 GB, 3.8 GB/core,
  3-day limit. **Badly contended** — 473 jobs pending when observed, so short jobs
  should go to `scavenger`, which started a 32-CPU job in ~25 s.
- **[measured]** On 2026-10-02 evening `scavenger` held four jobs at `(Priority)`
  for 20+ minutes despite an idle node. **Do not divert that work to `ic-express`.**
- **[measured] `ic-express` is not an appropriate partition for this project.** Its
  published policy is *short, interactive/debugging jobs needing rapid turnaround —
  not long-running production work — with a 2-hour maximum*. Slurm nonetheless
  advertises `MaxTime=08:00:00`, so a job violating the policy is accepted without
  complaint: **the enforced limit is not the policy.** It is also a *single* node
  (`TotalNodes=1, TotalCPUs=48`, `gres/gpu=16`), so anything substantial there blocks
  the entire express queue for everyone. Keep builds and sweeps on
  `scavenger`/`IllinoisComputes`, and use `ic-express` only if a genuinely short,
  interactive task ever needs it.
- **[measured]** Because `ic-express` is off-limits, long sweeps must stay on
  `scavenger` (1-day limit). `secondary` allows only 4 h, which is too short for the
  OpenMP sweep's worst case — a 1-rank run that gets no threading help is ~4.3 h.
  Keeping every point on one partition also avoids confounding run-to-run
  comparisons, where a +10 % spread has already been observed for identical
  configurations.
- **[measured]** `IllinoisComputes-GPU`: 4 x A100-80GB (sm_80, 128 cores, EPYC 7763)
  + 1 x H200-8GPU (sm_90, 64 cores, Emerald Rapids); 3-day limit.
- **[measured]** Modules: gcc 12.4/13.3, openmpi 5.0.1, gsl 2.8, cuda 12.4/12.6/12.8,
  nccl 2.25.1+cuda12.4, intel 2025 (needs `intel/tbb` loaded first), `papi/7.1.0`,
  fftw, boost, spack at `/sw/apps/spack/2025-02-12/spack`.
  **AOCC 5.0.0** (`amd/aocc-compiler`) provides clang-17 **and `flang`** plus AOCL —
  a ready-made second toolchain for P2 validation.
- **[measured]** **No `nvhpc`/`nvfortran`/`pgfortran` anywhere** — not in the module
  tree, not on disk. CUDA Fortran / OpenACC needs NVIDIA HPC SDK installed by us
  (Spack, or a tarball into scratch).
- **[measured]** `/scratch` filesystem is ~95 % full (14 TB free of 257 TB). Prefer
  `scavenger`; and note the temp dirs (`cfp/`, `ops/`) grow fast.
- **[measured]** `~/.github_pat` is an **invalid/expired token** — exporting it as
  `GH_TOKEN` breaks `gh`, which otherwise authenticates fine as `e-eight` via
  `~/.config/gh/hosts.yml` (scopes include `repo`).
- **[measured]** The fork `e-eight/NuHamil-public` has **Issues disabled** (inherited
  from the parent), so GitHub issues cannot be created there without enabling them.

## Golden data inventory

All under `/scratch/soham/NuHamil-faster/golden/`, with checksum manifests.
**Scratch is not backed up** — treat these as reproducible, not permanent.

| Path | Contents |
| --- | --- |
| `binaries/` | ICC serial+OpenMP and MPI+OpenMP builds |
| `inputs/` | cached `NNint_A2_rel_N3LO_EM500_bare_Nmax100_hw30.gz` |
| `logs/` | deuteron reference, full MPI build log, job snapshot |
| `icc-baseline/` | the ICC Makefile patch + the ad-hoc build wrappers |
| `toolchain/` | module sets, compiler versions, `ldd`, source hashes |
| `me3j/rampsmall/` | 5 x `.me3j.gz` (e3max 6–10) from the frozen binary |
| `me3j/provenance/` | inputs, run logs, timings, `sacct` records for those runs |
| `PROVENANCE.txt`, `SHA256SUMS`, `SHA256SUMS-me3j` | provenance + integrity |

## Memory: the ramp is a memory knob first — measured 2026-10-02

Job C (`ramplarge` e3max6 @ 32 ranks) was **OOM-killed** after 4:25:16:

```
11113167.0 | OUT_OF_MEMORY | MaxRSS 21477536K   (~20.5 GiB in one rank)
srun: error: ccc0259: task 5: Out Of Memory
```

| case | peak RSS / rank | note |
| --- | --- | --- |
| rampsmall e3max6 @ 8 and @ 32 | 1.65 GB | flat across rank count |
| ramplarge e3max6 @ 32 | **~20.5 GiB** | OOM-killed against a 200 GiB allocation |

- **[measured] The OOM was our request, not a hardware ceiling.** Total memory is
  `nranks x peak-per-rank`, so 32 ranks needed ~656 GiB — which would fit, because
  **the scavenger pool is heterogeneous**: it holds nodes from 94 GB up to **4031 GB**,
  including ~15 nodes at >= 1000 GB. Job C happened to land on a 257 GB node with a
  200 GiB cgroup limit. Memory here is a *request*, not a wall; size `--mem` to the
  need, or choose a smaller rank count. This retracts the earlier "ramplarge at 32
  ranks is infeasible" claim.
- **[inferred]** Peak *per rank* looks independent of rank count (rampsmall is flat at
  1.65 GB across 8 and 32 ranks), so total memory scales linearly with ranks. That is
  what makes a smaller rank count an effective memory lever if one is ever needed —
  but note it also costs workers, since rank 0 never computes.

- **[measured]** The ramp changes peak memory by **~13x** (1.65 GB -> 20.5 GiB).
  The earlier "peak RSS is flat" result was **rampsmall-specific** and must not be
  generalised: at rampsmall everything is small enough that the ramp barely moves
  the peak.
- **[inferred] H1 gains strong support.** The lab dims the code prints for the
  Nmax=40 channels are 24560, 28254, 30756, 31580 and 34020 states. At single
  precision one `dim x dim` matrix at dim=34020 is `34020^2 x 4 B = 4.6 GB`, so
  four or five live matrices reach ~20 GB. The ramp sets `dim`, hence the peak.
- **[measured]** Memory does **not** accumulate across channels: rampsmall @ 8 ranks
  (4 channels per rank) has the same peak as @ 32 ranks (1 channel per rank).
  So an 8-rank ramplarge run should peak near 20.5 GiB/rank, not 4x that.

### Complete ramplarge cfp distribution (e3max6, 32/32 files)

File counts match the ramp exactly, so this directory is complete.

| Nmax | channels | bytes | share |
| --- | --- | --- | --- |
| 40 (head) | 12 | 1052 MB | 40.9 % |
| 36 | 4 | 593 MB | 23.1 % |
| 32 | 4 | 435 MB | 16.9 % |
| 28 | 4 | 256 MB | 9.9 % |
| 24 (tail) | 8 | 236 MB | **9.2 %** |
| total | 32 | 2.57 GB | 100 % |

- **[measured]** Tail-only trimming can recover at most **~9 %** of `cfp/` bytes at
  e3max6 — weaker than even the invalid 21.7 % figure, not stronger.
- **[inferred]** This share is **e3max-dependent and must not be extrapolated**:
  the tail tier covers `2J+1 > 11`, i.e. j >= 13, which is 8 of 32 channels at
  e3max6 but 16 of 40 at e3max8 and roughly 48 of 60 at e3max16 — while the head
  (j <= 5) stays fixed at 12 channels. The production-case share has to be measured.
- **[measured]** The `cfp/` question is largely academic anyway: the Jacobi build is
  only ~2.9 % of wall time, and at ramplarge the peak memory is set by the
  lab-space operator matrices rather than by these files.

## Corrections log

1. **"The Jacobi space dominates memory."** *Retracted as stated, but the underlying
   intuition was right.* Peak RSS holds at ~1.61 GB/rank from e3max 6 to 9 at
   **rampsmall**, so the `cfp/` files are not what sets the peak. The original claim
   came from reading ramplarge *disk* sizes as if they were the resident footprint.
   However, the ramp **does** drive memory hard (~13x, see above) — just through the
   lab-space operator matrices, not the `cfp/` files.
2. **"Tail-only trimming has a ~22 % ceiling."** *Invalid, and the corrected answer
   is lower, not higher.* It was computed from the ramplarge e3max=8 `cfp/`
   directory, which contains **27 files instead of the 40 the ramp implies** — that
   run (`11108627`) was cancelled at 28:51, so the directory was partial. I first
   guessed the true share would be ~30 %; the complete e3max6 directory gives
   **9.2 %**. See the table above.

   *Lesson:* check that a result directory is complete before aggregating it, and
   state the extrapolation basis when generalising across e3max.
3. **"The MKL LP64 relink gives 1.20x."** *Too low — measured across two
   different nodes.* The first reading put MKL (654 s) on an Intel node against a
   reference-BLAS run (784 s) on an AMD node. A paired re-run on one node gives
   **1.98x** (776 s -> 391 s). *Lesson:* with a heterogeneous pool, one run per
   arm is not a measurement; pair the configurations on a node.
4. **"MPI scales negatively: 32 ranks is 0.85x of 8."** *Retracted — the sign was
   wrong, and the pair had two independent defects.* The 8x1 and 32x1 points ran on
   different CPU vendors (Intel vs AMD EPYC 7702) *and* concurrently in one shared
   run directory. Re-measured cold on a single node with one binary, 8 -> 32 ranks
   is **1.54x faster**, not slower (1360 -> 883 s). The mechanism (one channel per
   rank -> no scheduling slack) still predicts *sub-linear* scaling, which is what
   the clean measurement shows; it never predicted a *slowdown*. *Lessons:* record
   `nodelist` beside every timing; and never run two configurations in one run
   directory — the harness has enforced both since.
5. **"OpenMP gives 2.9x at constant CPU count."** *Badly overstated — that figure
   was a node comparison in disguise.* 8x4 ran on ccc0499 (Zen 5) and 32x1 on
   ccc0258 (Zen 2). On one node with one binary the same comparison is **1.15x**
   (765 s vs 883 s). Threads still win and still collapse the imbalance, but the
   P3 motivation should be sized at ~1.15x, not 2.9x. *Lesson:* "constant CPU
   count" is not "controlled experiment" when each point lands on a different node.

## Open hypotheses

- H1: the peak RSS is set by per-channel matrix storage, not the Jacobi space.
  *Source reading now points at the result redistribution in
  `ThreeBodyLabOpsIso.inc:922-939` (every rank receives every channel's `dim^2`
  matrix), which is consistent with RSS being flat across rank count and growing
  with the ramp. Still needs an allocation-level profile to confirm — note the
  printed dims (up to 34020) are the **non-antisymmetrised** `NAStates`, and the
  force is built in the smaller antisymmetrised basis (`AStates`, e.g. 11340), so
  the `dim^2 x 4 B` estimate must use the right one.*
- H2: ~~the ramp's effect on wall time is dominated by the lab-space dimension
  rather than the `cfp/` construction.~~ **Refuted** — the `cfp/` build is ~2.9 % of
  the run; the three-body force construction is ~97 %. The ramp's *runtime* effect
  therefore acts through the force/operator construction, not the Jacobi build.
- H4: the wall time is set by the most expensive channel, because a channel is an
  indivisible work unit. **Confirmed in source**: `nch = 32` for e3max6, one unit per
  rank at 32 ranks, so the dynamic scheduler has nothing to balance. Subdividing
  inside a channel should recover scaling past ~8 ranks — *but only together with a
  protocol change, since finer units multiply the blocking handshakes.*
- H5: the result redistribution (all-to-all `mpi_bcast` of every channel matrix) is
  a bigger scaling obstacle than the farm itself, because it is O(sum dim^2) memory
  per rank and serialises gigabytes of communication. Units already write results
  to files, so it may be removable without changing the numerics.
- H3: the `InitThreeBodyJacIsoSpace` channel loop is serial and not work-shared, so
  every rank reads all channels (`src/ThreeBody/ThreeBodyJacobiSpaceIso.F90:137-163`).
  *(Largely moot for runtime, given H2, but still a memory/IO concern.)*
