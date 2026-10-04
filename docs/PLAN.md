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
- **`ic-express` is off-limits for this project.** Its policy is short
  interactive/debugging jobs with a 2-hour maximum, and it is a single 48-CPU node,
  so batch builds or sweeps there would block the express queue. Slurm advertises
  `MaxTime=08:00:00` for it and accepts violating jobs silently — the enforced limit
  is not the policy. Check a partition's *published* intended use.
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
| Benchmark comparison | Pair configurations on one node (`--nodelist`), or repeat across nodes: `scavenger` is heterogeneous and one node is up to 1.67x faster |
| Upstream bug fixes | Allowed when one blocks a measurement, if the change is minimal, documented, and numerically verified (deuteron anchor + `bench/accept.py`) |

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
        — ~~negative scaling~~ **retracted**: the two points were on different CPU
        vendors *and* ran concurrently in one run directory; see `FINDINGS.md`
  - [x] Cold-start guarantee — warm re-runs were measuring cache reads, not compute
  - [x] Run-to-run spread explained: **same-node repeats agree to ~2 %; the
        larger spread is node heterogeneity** (up to 1.67x, Intel vs AMD) — see
        `FINDINGS.md`
  - [x] OpenMP sweep (rampsmall e3max6): 8x4 best; 1x32 4185, 2x16 4267, 16x2
        1799, 32x1 2294 s — but those points span nodes, so only the ordering is
        usable; the one-node, one-binary comparison is **1.15x** — see `FINDINGS.md`
  - [x] Tuned-BLAS A/B (MKL LP64 vs Netlib reference, 8x4, link-line only):
        **1.98x** paired on one node, numerics PASS — see `FINDINGS.md`
  - [x] **Re-measured the MPI rank sweep on ONE node** (ccc0497, EPYC 9555, one
        binary, cold): 8x1 1360 s -> 32x1 883 s = **1.54x faster** — scaling is
        sub-linear but *positive*; at a constant 32 CPUs threads beat ranks by only
        **1.15x** (8x4 765 s vs 32x1 883 s), not the 2.9x first reported
  - [x] Fixed the NN-cache TOCTOU race that made cold >=32-rank runs crash (4/4
        before, clean after; deuteron + `accept.py` unchanged) — see `FINDINGS.md`
  - [x] MKL LP64 is now the ICC default: 8x4 cold on ccc0497 is **361 s** vs
        765 s for reference BLAS on the same node = **2.12x**, numerics PASS.
        `MKL_NUM_THREADS` needs no tuning (forcing 1 is 1.08x *slower*)
  - [x] Tried a node-speed calibration probe (`bench/nodecal.c`) so experiments
        would not need same-node pairing — **not validated**: nodes with the
        *same* CPU differ 1.3-3.5x on the probe while their full-case times agree
        to 2.8 %, i.e. it measures co-tenant load. **Keep pairing.**
  - [x] **Re-profiled** with MKL on one node (job 11141497): `dgemm` 40 % -> 10.6 %;
        the cost is now **libm 31.3 % + `__powidf2` 4.8 % ~= 36 %** elementary math,
        **libgomp barriers 24.6 %**, our own physics 18.2 %, GSL Bessel 8.4 %.
        Answers the question above in favour of **compute, not bandwidth**.
        `bench/reprofile.sbatch` automates the method — see `FINDINGS.md`
  - [x] ~~Determine what the full case is bound by~~ **Answered:** scalar
        transcendental evaluation and barrier idle, not a memory-stall symbol
  - [ ] 2-node MPI
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
- [x] Tuned BLAS is now the **ICC default**: `config/sites/icc.mk` links MKL
      **LP64** (measured **1.98x** on rampsmall 8x4, numerics PASS). The former
      reference-BLAS link line is kept as `config/sites/icc-refblas.mk`
      (`SITE=icc-refblas`) so pre-change numbers stay reproducible — see
      `FINDINGS.md`
- *Exit:* clean-checkout build on ICC + one other toolchain, comparable to golden

Each step is rebuilt on `scavenger` (57 s) and re-checked against the deuteron
result, so a regression can't invalidate the baseline.

### P3 — Parallelization (3-body lab-frame only)

*Sizing (revised 2026-10-03).* The thread-vs-rank gap is **1.15x** at a constant 32
CPUs on one node, not the 2.9x first reported — that figure was a node difference.
Scaling 8 -> 32 ranks is **1.54x** (sub-linear, ~38 % efficiency), so the coarse
32-unit farm is a real but not catastrophic limit.

The re-profile resets the target list. By cycles: **libm + integer power ~36 %**,
**OpenMP barriers ~24.6 %**, our own physics 18.2 %, MKL BLAS 10.6 %, GSL Bessel
8.4 %. The work is no longer "make the arithmetic faster" — MKL did that — but:

- [x] **Transcendental math — done, 1.34x, output bit-for-bit identical.** Hoisted
      three loop-invariant calls (`non_local_regulator`'s 500x500 `exp`/`pow`, the
      `local_regulator`/weight/denominator p-mesh factors, and the `f1_func`/
      `f2_func` mesh sums) into tables. 8x4 cold on ccc0497: **361 s -> 269 s**,
      deuteron unchanged, `.me3j` identical in all 456 320 elements. Combined
      with the relink that is **2.84x** on this case. See `FINDINGS.md`
- [x] **OpenMP barrier idle — investigated and CLOSED as Amdahl serial time.**
      The ~36-39 % of cycles spent in `gomp_barrier_wait` is not imbalanced
      scheduling: with 1 thread the same phase takes 159 s vs 82 s at 4 threads
      (**1.94x**, i.e. a ~35 % serial fraction). `MKL_NUM_THREADS=1`,
      `schedule(dynamic)`, and fusing ~60 regions into 4 all left it unchanged.
      **Do not retry these**; the OpenMP side has at most ~1.94x available and the
      idle is not recoverable by tuning. Changes were reverted as neutral.
- [ ] **Remaining P3 lever: finer work units — re-measured at 1.54x; plan in P3-rows
      below.** Unit costs re-taken on the current binary: 32 units span
      **49.2-202.7 s, max/mean 2.279**, ideal makespan on 31 workers **91.8 s**, and
      32x1 measures 213 s. The prize is measured *against the configuration we
      actually use* (16x2 = 141 s), not against 32x1, so it is **1.54x** — the earlier
      1.87x compared against a configuration we do not run. The unit decomposes as
      construction **91.5 %**, SRG 8.4 %, dense **diagonalisation 0.2 %**, so no
      distributed eigensolver is needed. See `FINDINGS.md`, "What a work unit
      actually contains".
- [x] ~~Drop the O(sum dim^2) redistribution~~ **Deprioritised by measurement.** It is
      0.031 s of a 267.8 s run — a memory concern for production sizes, not a time one.
- [x] ~~Give rank 0 work~~ **Bounded and small.** Rank 0 never calls `Method`, so only
      `nprocs-1` ranks compute; that is worth `nprocs/(nprocs-1)` = 14.3 % at 8 ranks and
      3.2 % at 32, and cannot explain the scaling loss (which would need `T ~ 1/(nprocs-1)`).
- **Configuration to use now: `16x2`.** At the same 32 CPUs on ccc0497: 206 s (16x2) vs
      254 s (32x1) vs 269 s (8x4). This *reverses* the pre-hoist result that threads beat
      ranks — see `FINDINGS.md`. Every performance claim must state ranks x threads.
- [ ] GSL Bessel (~11.8 %, ~10 s) — the largest remaining arithmetic item.
      Recursions instead of per-call `gsl_sf_bessel_jl`, plus the per-call `exp`
      /two `log`s in `spherical_bessel`'s threshold (`MyLibrary.F90:1013`), which
      depend only on `l`.
- [ ] Attribution with `papi/7.1.0` + per-rank timers
- [ ] Re-architect the master–worker farm: cost-weighted tiles, decentralised
      queue, point-to-point result return, drop barriers, overlap comm/compute
- [ ] Fill OpenMP gaps, remove `!$omp critical` accumulators, tune affinity
- [ ] Per-channel checkpointing so `scavenger --requeue` resumes
- [x] Prerequisite: fixed the NN-cache TOCTOU race that crashed cold runs at
      >=32 ranks (`src/TwoBody/NNForce.F90`, atomic publish) — see `FINDINGS.md`
- *Exit:* >= 2x on the medium case, numerics match golden, scaling to >= 2 nodes
  *(re-derive the 2x from the corrected baseline before treating it as a target)*
  *(the >= 2x target predates the corrected baseline — re-derive it first)*

### P3-rows — Row-split of the per-channel fill (plan, 2026-10-03)

*Status: planned, not started.*

**Goal.** Remove the granularity loss measured at **1.54x** end-to-end. With 32
whole-channel units on 31 workers the makespan *is* the heaviest channel (202.7 s
measured against a 91.8 s ideal), so 32x1 gives 213 s where ~92 s is reachable.

**The split axis is rows of the per-channel matrix.**
`set_nnn_int_chEFT_n2lo_isospin_local` (`NNNForceHOIsospin.F90:706`) fills
`this(N,N)`, `N = GetNumberNAStates()`, through five `set_inside` calls, one per
LEC, whose outer loop is `do ibra = 1, N` with `do iket = 1, ibra`. Row `ibra`
reads only `this%m(ibra,1:ibra)` — zero before the first LEC, then accumulated
from its own row — plus the bra/ket quantum numbers. **Rows are therefore
independent**, and a row range can be computed on its own.

Two properties make this safe to do:

- **Write-once.** Row `i` writes `m(i,j)` and `m(j,i)` for `j <= i`. Every element
  is written by exactly one owner — the owner of row `i` — so **no reduction and no
  conflict resolution is needed**. That is the single most valuable property here.
- **Triangular cost.** Row `i` costs ~`i` matrix elements, so equal row *counts*
  are badly unequal work. Use **strided ownership** (rank `r` takes rows
  `r, r+K, r+2K, ...`), which gives each rank ~`N^2/(2K)` work by construction.
  Contiguous blocks would need sqrt-spaced boundaries and would still be sensitive
  to per-element cost variation.

**Design: two farm stages.**

1. **Fill stage.** Unit = (channel, row block). Each unit reads `jac` (already a
   file), computes its rows, writes them to a per-`(channel,block)` partial file
   under the run's tmp dir. Unit count becomes `sum_ch K(ch)`.
2. **Assembly stage.** A second `parent_child_procedure` over channels: one rank per
   channel reads its partials, assembles the full `this`, then runs the existing
   post-processing — `cfp^T * this * cfp`, the non-local regulator, the
   diagonalisation and the SRG flow — and writes the channel's output files.

Stage 2 is why the ceiling is ~11x rather than 31x: it serialises ~9 % of a unit
per channel (SRG 8.4 %, diag 0.2 %, plus the gather). For the heaviest channel that
is ~18 s of work that cannot be split, which also sets a sensible minimum block
size — blocks much below that buy little.

**Blocking rule.** `K(ch) = max(1, ceil(cost(ch)/target))` with `target ~ 30 s`, so
the largest block stays well under the 91.8 s floor and packing stays smooth.
`cost(ch)` is available from a `#PROF_UNIT` run; until then the triangular model
`cost ~ N^2/2` is good enough to start.

**Prerequisite: guard `v` (cheap, independent, do this first).** In the same
routine, `v` is allocated as `N(N+1)/2` and written for *every* element in all five
LEC passes, but it is only **read when `save_3nf_before_lec` is true** — which is
`.false.` by default and unset in our inputs. Guard the allocation and the writes.
This removes a ~`N^2/2` array from the split design *and* is a candidate small win
on its own, measurable in isolation before any MPI work.

**Staged implementation, with a verification gate at each stage.**

1. [x] Guard `v`. *Gate:* deuteron + `accept.py` + output unchanged; measure alone.
       **Done — gate passed, timing benefit nil.** 16x2 on ccc0499: 139 s before,
       139 s after; output identical in all 456 320 values. Kept as a prerequisite
       for stage 2 (it removes the scratch array from the block units entirely), not
       as a performance win. See `FINDINGS.md`, "Row-split stage 1".
2. Add optional row-range arguments to `set_nnn_int_chEFT_n2lo_isospin_local` /
   `set_inside`, defaulting to the full range. **No MPI yet.** *Gate:* the
   whole-channel path reproduces the current output **exactly**. This proves row
   restriction is sound before any communication exists — the cheapest possible
   place to discover that it is not.
3. Run one channel split `K` ways in-process and compare against the whole-channel
   matrix. *Gate:* identical within `accept.py` tolerance.
4. Wire the two stages into the farm. *Gate:* full case at 32x1 against the 91.8 s
   ideal, then a 16x2 A/B against 141 s.

**Risks, each with the measurement that retires it.**

- **Per-block setup duplication.** Each rank runs `nnn_force%init` plus five
  `nnn_force%set` calls (the `fk`/`fkx`/`zx` precomputations) for its own block. If
  that is a large share of a block, finer blocks lose more than they gain. Profile
  `init`+`set` against `set_inside` and **measure before choosing K** — this is
  exactly the trap that made the `chEFT_n2lo` copy rewrite worthless.
- **Gather cost.** `sum_ch K(ch)` partial files, each `rows x N` doubles. File I/O
  is already the idiom here (three cache levels), but this multiplies file count;
  watch metadata overhead on scratch.
- **Peak memory.** Unchanged in stage 2 (one rank still holds a full `N x N`);
  lower in stage 1.
- **Checkpoint/resume.** The `s%isfile(fv) .and. s%isfile(fut)` early-return is per
  channel. The final `fv`/`fut` must remain the *only* completion signal, with
  partials treated as scratch, or a resumed run will mistake partial output for a
  finished channel.
- **Cache interaction.** The 1.54x assumes per-unit work is unchanged when split.
  Cache behaviour could move either way and the model cannot see it — hence the
  stage-3 gate on a real split channel rather than trusting the arithmetic.
- **Threads.** Threads saturate at 2, so this split is about using more *processes*.
  Keep `16x2` as the reference and re-check 32x1 vs 16x2 after stage 4.

**Non-goals.** No distributed eigensolver (diagonalisation is 0.2 %); no change to
the redistribution (0.031 s); no change to `calc_each_channel`'s channel-level
caching, which is what makes reruns cheap.

**Not planned: splitting only the largest few channels.** The imbalance is broad,
not one outlier (202.7, 160.7, 160.5, 128.4, 126.1, ... down to 49.2). Halving the
top 4 would give a 1.10x end-to-end gain and the top 8 a 1.22x, against 1.54x for
splitting generally — so a special-case path buys a fraction of the prize for most
of the design cost.

### P3b — Jacobi-space / ramp cost

- [x] Ramp as an explicit sweep axis (`ramplarge`, `rampsmall`), recorded per run
- [x] Measure the existing `ramp20` sweep
- [x] Peak memory measured: rampsmall 1.65 GB/rank vs ramplarge **~20.5 GiB/rank**
      (OOM-killed at 32 ranks) — the ramp is a memory knob first
- [x] Complete `cfp/` distribution: the Nmax24 tail is 9.2 % of bytes at e3max6
- [x] Ramp comparison at a **matched** configuration (8 ranks x 4 threads):
      rampsmall **32/32 channels in 13:04**; ramplarge **2/32 channels in 10:19:31**
      when cancelled — roughly 770x per channel
- [x] Production-ramp recommendation: **do not use `ramplarge` at this size.** Three
      independent failures — OOM at 32 ranks, cancelled at 8x1, time-limited at 8x4 —
      plus the cost ratio above. `rampsmall` (or an intermediate ramp) is the only
      practical choice; the question is where between them the accuracy/cost knee sits.
- *Exit:* measured cost/memory vs ramp and a recommendation **— met**

**Correction (2026-10-02):** the earlier claim that ramplarge at 32 ranks was
infeasible was **wrong**. The scavenger pool is heterogeneous — 94 GB up to
**4031 GB**, with 15 nodes at >= 1000 GB — so the ~656 GiB that 32 ranks needed
would have fitted on a large node. The OOM was caused by the `--mem=200G` request
landing on a 257 GB node, not by a hardware ceiling: the binding constraint was
our request, and memory is a request rather than a wall.

### P4 — GPU feasibility: gated on a hot kernel that no longer exists

*Re-scoped 2026-10-03.* The premise of the bake-off was a dominant hot kernel to
offload. The re-profile removes it: the cost is diffuse (36 % library
transcendentals, ~25 % barrier idle, 18 % physics spread over many small
routines), and `dgemm` — the one kernel that would have been worth porting — is
down to 10.6 % after the MKL relink. Two corrections from the GPU reconnaissance
stand: `ifx` is not an option (no Intel GPUs here), and there is no A100 in the
scavenger pool (sm_90 H100 / sm_89 L40S / sm_75 RTX 6000 / sm_70 V100).

- [ ] **4.0** Re-state the premise: identify a kernel that is both *hot* and
      offloadable, or conclude that none exists. No current candidate satisfies
      the "hot" half.
- [ ] **Gate:** >= ~3–5x on one hot kernel with matching numerics
- [ ] **4.1** If a candidate appears: CUDA C++ behind `ISO_C_BINDING` is the
      low-risk arm (`nvcc` is already installed); NVHPC/OpenACC is the
      maintainable production path if a multi-GB scratch install is justified
- [ ] **4.3** If no-go, prototype the ported fraction in Kokkos/CuPy/JAX only
- *Exit:* written go/no-go memo — currently reads as **no-go pending a hot
  kernel**, and writing it up is cheap

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
