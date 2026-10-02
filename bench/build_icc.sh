#!/bin/bash
# ---------------------------------------------------------------------------
# Build NuHamil on the Illinois Campus Cluster into $SCRATCH_ROOT/build/<tag>/.
#
# MUST run on a COMPUTE NODE -- never on a login node.
#
#   srun --account=soham-ic --partition=IllinoisComputes -n 1 -c 32 --mem=64G \
#        --time=02:00:00 bash bench/build_icc.sh base 32
#
#   # or, equivalently:
#   sbatch bench/build_icc.sbatch
#
# Produces under $SCRATCH_ROOT/build/<tag>/ :
#   NuHamil_serial.exe   serial + OpenMP
#   NuHamil_mpi.exe      MPI + OpenMP
#   build-serial.log     full compile/link log
#   build-mpi.log        full compile/link log
#   build-info.txt       commit, toolchain, flags, sha256 vs the golden build
#
# The build happens in a SHADOW COPY of the repo under scratch, so no object
# files, .mod files or executables are written to $HOME.  It deliberately uses
# the unmodified upstream Makefile (+ the preserved ICC block) so that the
# resulting binaries are directly comparable to the frozen golden ones.
#
# Phase 2 replaces this with a real out-of-tree build (config/ fragments and
# CMake); this script is the Phase-1 way of getting a trustworthy baseline.
# ---------------------------------------------------------------------------
set -euo pipefail

TAG="${1:-base}"
NPROC="${2:-${SLURM_CPUS_PER_TASK:-8}}"
SCRATCH_ROOT="${NH_SCRATCH_ROOT:-/scratch/soham/NuHamil-faster}"
REPO="${NH_REPO:-/u/soham/NuHamil-faster/upstream}"
BUILDROOT="$SCRATCH_ROOT/build/$TAG"
SHADOW="$BUILDROOT/src"
GOLDEN="$SCRATCH_ROOT/golden"

if ! command -v module >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    source /etc/profile.d/lmod.sh 2>/dev/null || source /usr/share/lmod/lmod/init/bash
fi
module load gcc/13.3.0
module load gsl/2.8

mkdir -p "$BUILDROOT" "$SHADOW"
echo "=== build_icc.sh tag=$TAG jobs=$NPROC host=$(hostname) date=$(date -Is)"

COMMIT="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
DIRTY="$(git -C "$REPO" status --porcelain 2>/dev/null | head -n 5 || true)"

# --- shadow copy of the working tree (no .git, no build artefacts) ---------
rsync -a --delete \
      --exclude '.git/' \
      --exclude 'obj/' \
      --exclude 'mod/' \
      --exclude 'exe/NuHamil.exe' \
      --exclude 'exe/NuHamil_serial.exe' \
      "$REPO/" "$SHADOW/"
echo "=== shadow copy ready: $SHADOW"

# --- serial + OpenMP -------------------------------------------------------
cd "$SHADOW"
make clean >/dev/null 2>&1 || true
echo "=== serial build"
make -j"$NPROC" INSTLDIR="$BUILDROOT/install" 2>&1 | tee "$BUILDROOT/build-serial.log"
cp -f "$SHADOW/exe/NuHamil.exe" "$BUILDROOT/NuHamil_serial.exe"

# --- MPI + OpenMP ----------------------------------------------------------
module load openmpi/5.0.1-gcc-13.3.0
make clean >/dev/null 2>&1 || true
echo "=== mpi build"
make MPI=on -j"$NPROC" INSTLDIR="$BUILDROOT/install" 2>&1 | tee "$BUILDROOT/build-mpi.log"
cp -f "$SHADOW/exe/NuHamil.exe" "$BUILDROOT/NuHamil_mpi.exe"

# --- provenance ------------------------------------------------------------
{
    echo "tag=$TAG"
    echo "repo=$REPO"
    echo "commit=$COMMIT"
    echo "dirty_files_before_build:"
    echo "${DIRTY:-  (clean)}"
    echo "shadow=$SHADOW"
    echo "host=$(hostname)"
    echo "date=$(date -Is)"
    echo "jobs=$NPROC"
    echo
    echo "== modules =="
    module list 2>&1
    echo
    echo "== compilers =="
    gfortran --version 2>&1 | head -n 2
    mpifort --showme:command 2>&1
    ompi_info --version 2>&1 | head -n 1
    echo
    echo "== upstream Makefile hash (must match the golden build) =="
    sha256sum "$SHADOW/Makefile" "$REPO/Makefile" 2>/dev/null || true
    echo
    echo "== binaries =="
    ls -l "$BUILDROOT"/NuHamil_*.exe
    sha256sum "$BUILDROOT"/NuHamil_*.exe
    echo
    echo "== frozen golden binaries (for comparison) =="
    if [ -f "$GOLDEN/toolchain/SOURCE-SHA256.txt" ]; then
        cat "$GOLDEN/toolchain/SOURCE-SHA256.txt"
    else
        echo "(no golden manifest found at $GOLDEN/toolchain/SOURCE-SHA256.txt)"
    fi
    echo
    echo "== executable types =="
    file "$BUILDROOT"/NuHamil_*.exe
} > "$BUILDROOT/build-info.txt"

echo "=== build-info.txt ==="
cat "$BUILDROOT/build-info.txt"
echo "=== done $(date -Is)"
