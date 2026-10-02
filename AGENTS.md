# Repository Guidelines

NuHamil generates nucleon–nucleon (NN) and three-nucleon (3N) matrix elements in the harmonic-oscillator basis. Fortran 2003+ with OpenMP/MPI; Python is used only for run drivers and tooling.

## Project Structure & Module Organization

- `src/` — driver `NuHamilMain.F90`, namelist `NuHamilInput.F90`, `Profiler.F90`, `MPIFunction.F90`, containers `ClassSys.f90`, `MyLibrary.F90`, `OperatorDefinitions.F90`, `Renormalization.F90`.
- `src/{OneBody,TwoBody,ThreeBody,ABody}/` — physics for each `particle_rank` (1–4+).
- `src/**/*.inc` — precision templates. Edit the `.inc`, never the `*Single.F90` / `*Double.F90` / `*Half.F90` wrappers, which only `#define PRECISION` and `#include` it.
- `submodules/{LinAlgf90,NdSpline}/` — git submodules; run `git submodule update --init`.
- `exe/` — Python drivers that emit namelists. `input_nn_files/` — tracked NN binaries.
- `bench/` — benchmark harness: `cases.yaml`, `gen_cases.py`, `build_icc.sh`, `run_case.sbatch`, `collect.py`.

## Build, Test, and Development Commands

Build and run **only on cluster compute nodes** — never on login nodes. All output goes under `/scratch/soham/NuHamil-faster`.

```bash
sbatch bench/build_icc.sbatch base       # serial+OpenMP and MPI builds -> build/base/
python3 bench/gen_cases.py               # namelists for every case x ramp
python3 bench/gen_cases.py --list        # expanded case ids
sbatch bench/run_case.sbatch <case-id>   # one case; serial vs MPI from -n
python3 bench/collect.py                 # logs + profiler -> results.csv/json
```

`-fdefault-integer-8` is mandatory. Do not run `make install` (it symlinks into `$HOME/bin`); pass `INSTLDIR=` instead. New sources are picked up by Makefile wildcards, but add a `makefile.d` entry so `make -j` stays race-free.

## Coding Style & Naming Conventions

Two-space indent, free-form. Modules and types use `CamelCase` (`ThreeBodyJacIsoChan`); procedures mix `CamelCase` and `snake_case`; locals are lower-case. No formatter or linter is configured. Preserve the surrounding `!$omp` and `#ifdef MPI` guards. Keep new lines within 132 columns (the build sets `-ffree-line-length-0` for legacy long lines).

## Testing Guidelines

There is no unit-test framework. `src/tests.F90::test_main()` is a stub — add cases under the matching `particle_rank` and reach it with `test_mode = .true.` in the namelist. Verification is numerical: compare against the reference products and hashes in `golden/` (for example the deuteron `E = -2.22434870` MeV, and the `me3j.gz` checksums). Explain any change to a numerical result.

## Commit & Pull Request Guidelines

Upstream history uses short, sentence-case subjects (`Add optional phase parameter handling in MyLibrary`). This fork prefixes the touched area: `bench:`, `Profiler:`, `Build:`.

`upstream` points at third-party code (github.com/Takayuki-Miyagi/NuHamil-public) and is **read-only for us** — never push there, and its push URL is disabled locally by design. Do all work on a branch and push to this project's own fork, which is tracked as `origin` (`git remote -v`).

Pull requests target the fork, not upstream. State the physics or performance motivation, the exact command used, and the reference values compared. For performance work, attach before/after `bench/collect.py` output; flag any numerical change explicitly.
