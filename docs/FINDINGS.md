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
- **[measured]** `-fdefault-integer-8` is mandatory; LAPACK/BLAS must match ILP64.
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

## Cluster environment

- **[measured]** `IllinoisComputes`: 22 nodes x 128 cores, 512 GB, 3.8 GB/core,
  3-day limit. **Badly contended** — 473 jobs pending when observed, so short jobs
  should go to `scavenger`, which started a 32-CPU job in ~25 s.
- **[measured]** **Partition choice matters more than expected.** On 2026-10-02
  evening `scavenger` held four jobs at `(Priority)` for 20+ minutes despite an idle
  node, while the same 32-CPU build submitted to **`ic-express` ran in 74 s**. Use
  `ic-express` for short jobs and builds; keep long sweeps on one partition so that
  run-to-run comparisons are not confounded by node/partition differences (a +10 %
  spread has already been observed between identical configurations).
- **[measured]** `scavenger` timelimit is 1 day; `secondary` is 4 h, which is too
  short for the OpenMP sweep's worst case (a 1-rank run that gets no threading help
  is ~4.3 h).
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
