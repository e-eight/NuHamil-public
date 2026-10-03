# NuHamil-faster — work plan

Living document. Update the checkboxes as work lands; keep durable technical
knowledge in [`FINDINGS.md`](FINDINGS.md) instead of here.

GitHub tracker: [#1](https://github.com/e-eight/NuHamil-public/issues/1) P1 ·
[#2](https://github.com/e-eight/NuHamil-public/issues/2) P2 ·
[#3](https://github.com/e-eight/NuHamil-public/issues/3) P3 ·
[#4](https://github.com/e-eight/NuHamil-public/issues/4) P3b ·
[#5](https://github.com/e-eight/NuHamil-public/issues/5) P4 ·
[#6](https://github.com/e-eight/NuHamil-public/issues/6) P5

This file and the issues are deliberately kept in step: issues carry *state*,
this file carries the same state next to the code, and `FINDINGS.md` carries the
*knowledge* that should outlive both.

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
  - [x] First MPI rank sweep (e3max6 rampsmall): 8 ranks 1947 s, 32 ranks 2294 s
        — **negative scaling**, see `FINDINGS.md`
  - [x] Cold-start guarantee — warm re-runs were measuring cache reads, not compute
  - [ ] Repeat runs to bound run-to-run spread (+10 % observed between identical
        configurations) before quoting small deltas
  - [ ] OpenMP sweep, and 2-node MPI
- *Exit:* reproducible numbers, serial-vs-MPI curve, "where the time goes"

### P2 — Portable, non-rigid build

- [x] **A.1** Site-fragment mechanism: `config/site.mk` selects
      `config/sites/<SITE>.mk` from `SITE=` → `NUHAMIL_SITE` → hostname fallback,
      warning on an unknown site instead of silently using the wrong toolchain
- [x] **A.2** ICC converted to the first fragment (`config/sites/icc.mk`, extracted
      verbatim); the Makefile no longer special-cases ICC
- [x] **A.3** `.gitignore` for `obj/`, `mod/`, `exe/*.exe`, `__pycache__/`
- [x] **A.4** Inert-refactor proof: 132 compile commands identical, both binaries
      bit-identical (`ad7fe067…`), deuteron result unchanged
- [x] **A.5** All six remaining host blocks converted to fragments; the hostname
      table now lives in `config/detect-site.sh` and the Makefile has **no hostname
      reference at all** (472 -> 309 lines). Verified inert again: 132 commands and
      both binaries identical
- [ ] **A.6** Compiler-family fragments (`gnu`/`intel`/`aocc`/`nvhpc`) replacing the
      `findstring $(FC)` string-matching for `MODOUT`/`FLINES`/`LINT`
- [ ] **A.7** Dependency probing (`makedepf90` is absent on ICC); optional HDF5
      (one file, `src/ThreeBody/NNNFFromFile.F90`); `PRECISION=` selector
- [ ] **A.8** `EXEDIR`/`INSTLDIR` overridable and never defaulting to `$HOME`;
      `make print-config` / `check-deps`
- [ ] **Track B** thin CMake + `CMakePresets.json` (carrier for GPU targets later)
- [ ] Validate a second toolchain: AOCC/flang + AOCL (already installed)
- *Exit:* clean-checkout build on ICC + one other toolchain, comparable to golden

Each step is rebuilt on `scavenger` (57 s) and re-checked against the deuteron
result, so a regression can't invalidate the baseline.

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
- [x] Peak memory measured: rampsmall 1.65 GB/rank vs ramplarge **~20.5 GiB/rank**
      (OOM-killed at 32 ranks) — the ramp is a memory knob first
- [x] Complete `cfp/` distribution: the Nmax24 tail is 9.2 % of bytes at e3max6
- [ ] Ramp comparison at a fixed rank count: rampsmall @8 = 32:34 vs ramplarge @8
      (job `11117512` running). 32 ranks is infeasible at ramplarge — ~656 GiB
      against a 515 GB node
- [ ] Recommend a production ramp
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

- ~~What actually drives the peak, if not the Jacobi space?~~ **Answered:** the
  lab-space operator matrices. Lab dims reach 34020 states, and one single-precision
  `dim × dim` matrix is 4.6 GB, so a handful of live matrices accounts for the
  20.5 GiB/rank peak seen at ramplarge. See `FINDINGS.md`.
- ~~Is the `cfp/` build really a small share of the wall time?~~ **Answered:** yes —
  the three-body force construction is ~97 %, the Jacobi build ~2.9 %.
- Does the ramp need to become a runtime parameter rather than a namelist string?
  *(still open)*
