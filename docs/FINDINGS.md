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

## OpenMP works, and it is where the speed is — measured 2026-10-02

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
  Tuned ILP64 alternatives are installed (MKL 2025 `libmkl_*_ilp64`, AOCL 5.0).
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
2. **Then attack the 25 % barrier time** — that is the real P3 target, and it is a
   scheduling/parallel-structure problem, not an arithmetic one.
3. GSL Bessel (~3.3 %) is a smaller, independent candidate.

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
