# NuHamil-faster — work plan

Living document. Update the checkboxes as work lands; keep durable technical
knowledge in [`FINDINGS.md`](FINDINGS.md) instead of here.

## Goal

Explore three directions on top of the third-party NuHamil code, without
breaking the existing working build:

1. **Build flexibility** — the build currently needs hand-editing per system.
2. **Parallelization** — assess whether the MPI scheme is optimal and whether
   thread parallelism can be added.
3. **GPU compatibility** — feasibility first; a rewrite is on the table but not
   the starting point.

## Constraints

- Never compute on login nodes — all builds and runs go through Slurm.
- Account `soham-ic`; partitions `IllinoisComputes` (CPU), `IllinoisComputes-GPU`,
  `scavenger` (pre-emptible, use `--requeue`).
- All artefacts under `/scratch/soham/NuHamil-faster`; nothing into `$HOME`.
- `~/NuHamil-public` is the user's original working copy — never modified.
- Upstream is third-party: `upstream` remote is fetch-only with push disabled.
  Work is pushed to `origin` (fork `e-eight/NuHamil-public`).

## Decisions locked

| Decision | Choice |
| --- | --- |
| Build system | Keep the Makefile (Track A) **and** add CMake (Track B) |
| GPU entry point | Time-boxed compiler bake-off before committing to any path |
| Parallelization scope | 3-body lab-frame only (the only mode MPI supports, and the dominant cost) |
| PR to open | After Phase 2, so the temporary ICC Makefile block is gone |

## Phases

### P0 — Sandbox & provenance ✅

- [x] Clone to `/u/soham/NuHamil-faster/upstream`, branch `faster/main`, tag `upstream-baseline`
- [x] Scratch tree `{build,bench,runs,golden,tmp}`
- [x] Golden baseline + `SHA256SUMS` + `PROVENANCE.txt`

### P1 — Measurement baseline & harness 🔄

- [x] **P1a** `bench/` harness: `cases.yaml`, `gen_cases.py`, `build_icc.sh`,
      `build_icc.sbatch`, `run_case.sbatch`, `collect.py`; per-rank profiling
- [x] **P1b** Build on a compute node + deuteron smoke test
- [x] **P1d** Harvest 3N `.me3j.gz` reference products into `golden/me3j/`
- [ ] **P1c** Scaling sweep: OpenMP {1..32} x MPI ranks {1..64}, 1→2 nodes;
      wall, peak RSS, rank imbalance, per-phase split
- *Exit:* reproducible numbers, serial-vs-MPI curve, "where the time goes"

### P2 — Portable, non-rigid build

- [ ] **Track A** site/compiler fragments (`SITE=`/env, not `hostname` sniffing),
      dependency probing, optional HDF5, `makedepf90` optional, `EXEDIR`/`INSTLDIR`
      never `$HOME`, `PRECISION=` selector, `make print-config` / `check-deps`
- [ ] Remove the temporary ICC block (commit `397b08e`) and add `.gitignore`
- [ ] **Track B** thin CMake + `CMakePresets.json` (carrier for GPU targets later)
- [ ] Validate a second toolchain: AOCC/flang + AOCL (already installed)
- *Exit:* clean-checkout build on ICC + one other toolchain, comparable to golden

Do Track A in small steps, rebuilding on `scavenger` (57 s) and re-checking the
deuteron result after each, so a regression can't invalidate the baseline.

### P3 — Parallelization (3-body lab-frame only)

- [ ] Attribution with `papi/7.1.0` + per-rank timers
- [ ] Re-architect the master–worker farm: cost-weighted tiles, decentralised
      queue, point-to-point result return, drop barriers, overlap comm/compute
- [ ] Fill OpenMP gaps, remove `!$omp critical` accumulators, tune affinity
- [ ] Per-channel checkpointing so `scavenger --requeue` resumes
- *Exit:* >= 2x on the medium case, numerics match golden, scaling to >= 2 nodes

### P3b — Jacobi-space / ramp cost

- [x] Ramp as an explicit sweep axis (`ramplarge`, `rampsmall`), recorded per run
- [x] Measure the existing `ramp20` sweep
- [ ] Ramp comparison A/B (job C) → what actually sets the 1.6 GB/rank peak
- [ ] Re-test the memory hypothesis; recommend a production ramp
- *Exit:* measured cost/memory vs ramp and a recommendation

### P4 — GPU feasibility, then staged offload

- [ ] **4.0** Bake-off on one A100: nvfortran (OpenACC/CUDA Fortran) vs `ifx`
      OpenMP-target vs C++/CUDA kernel extraction behind `ISO_C_BINDING`
- [ ] **Gate:** >= ~3–5x on one hot kernel with matching numerics
- [ ] **4.2** Staged per-kernel port; CPU path preserved; one MPI rank per GPU
- [ ] **4.3** If no-go, prototype the ported fraction in Kokkos/CuPy/JAX only
- *Exit:* written go/no-go memo

### P5 — Consolidate & hand off

- [ ] Single branch, documented build matrix, harness + golden data retained

## Open questions

- What actually drives the 1.6 GB/rank peak, if not the Jacobi space?
- Is the ~2.5 min `cfp/` build really a small share of the ~35 min wall time?
- Does the ramp need to become a runtime parameter rather than a namelist string?
