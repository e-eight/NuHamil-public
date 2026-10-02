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
  ~35 min run, so the Jacobi construction looks like a small share of the wall
  time at that ramp. Confirmation pending.
- **[inferred]** Prime suspect for the constant 1.6 GB/rank: lab-space operator
  matrices at single precision (dim^2 x 4 B; one channel printed 17010 states,
  giving ~1.2 GB). Unconfirmed.

## Cluster environment

- **[measured]** `IllinoisComputes`: 22 nodes x 128 cores, 512 GB, 3.8 GB/core,
  3-day limit. **Badly contended** — 473 jobs pending when observed, so short jobs
  should go to `scavenger`, which started a 32-CPU job in ~25 s.
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

## Corrections log

1. **"The Jacobi space dominates memory."** *Retracted.* Peak RSS holds at
   ~1.61 GB/rank from e3max 6 to 9 while `cfp/` changes 17x between ramps, so the
   Jacobi space is not what sets the peak. The original claim came from reading
   ramplarge *disk* sizes as if they were the resident footprint.
2. **"Tail-only trimming has a ~22 % ceiling."** *Invalid, not merely imprecise.*
   It was computed from the ramplarge e3max=8 `cfp/` directory, which contains
   **27 files instead of the 40 the ramp implies** — that run (`11108627`) was
   cancelled at 28:51, so the directory is partial. The Nmax=24 tail tier was the
   worst affected (8 files of 16), meaning the true tail share is *higher*; a crude
   per-file extrapolation suggests roughly 30 %, but this must be re-measured on a
   complete directory (job C, ramplarge e3max6) before it is quoted.

   *Lesson:* check that a result directory is complete before aggregating it.
   The complete rampsmall directory happens to have exactly its expected 40 files,
   which is now a useful sanity check.

## Open hypotheses

- H1: the 1.6 GB/rank peak is lab-space operator matrices, not the Jacobi space.
- H2: the ramp's effect on wall time is dominated by the lab-space dimension rather
  than the `cfp/` construction.
- H3: the `InitThreeBodyJacIsoSpace` channel loop is serial and not work-shared, so
  every rank reads all channels (`src/ThreeBody/ThreeBodyJacobiSpaceIso.F90:137-163`).
