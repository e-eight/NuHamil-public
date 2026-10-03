#!/bin/bash
#SBATCH --job-name=nh-prof
#SBATCH --account=soham-ic
#SBATCH --partition=scavenger
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=/scratch/soham/NuHamil-faster/runs/slurm-%j.out
#SBATCH --error=/scratch/soham/NuHamil-faster/runs/slurm-%j.err
# ---------------------------------------------------------------------------
# Sampling profile of the 3-body force construction, taken on a completed run.
# Never run this on a login node.
#
#   bench/submit.sh -p scavenger --requeue -c 4 bench/reprofile.sbatch \
#       <completed-run-dir> [channel-substring]
#
# Method (from docs/FINDINGS.md): copy a run directory whose cfp/ and ops/ are
# complete, then delete ONE channel's two ops files so that channel recomputes
# while every other channel returns early from the ops cache.  The profile then
# covers essentially only that channel's force construction.  The serial binary
# is used so there is no MPI noise.
#
# This is how the original 40 % dgemm / 25 % barrier profile was taken.  It is
# repeated here because the MKL relink has changed which cost dominates, so the
# old ranking can no longer be used to choose where to optimise.
#
# perf: compute nodes run perf 5.14 with kernel.perf_event_paranoid=2, so
# user-space cycles:u sampling of our own process is permitted (no kernel
# symbols, which we do not need).
#
# Env knobs: NH_TAG=<build tag>   which binary to profile (default: mkl-fix)
# ---------------------------------------------------------------------------
set -euo pipefail

SRC="${1:?usage: reprofile.sbatch <completed-run-dir> [channel-substring]}"
CHAN="${2:-j3p+t1_Nmax20}"
SCRATCH_ROOT="${NH_SCRATCH_ROOT:-/scratch/soham/NuHamil-faster}"
REPO="${NH_REPO:-/u/soham/NuHamil-faster/upstream}"
TAG="${NH_TAG:-mkl-fix}"

# shellcheck source=partitions.sh
. "$REPO/bench/partitions.sh"
if ! nh_check_partition "${SLURM_JOB_PARTITION:-}"; then
    echo "ERROR: aborting before doing any work." >&2
    exit 2
fi

if ! command -v module >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    source /etc/profile.d/lmod.sh 2>/dev/null || source /usr/share/lmod/lmod/init/bash
fi
module load gcc/13.3.0
module load gsl/2.8

DEST="$SCRATCH_ROOT/runs/prof-$(basename "$SRC")"
BIN="$SCRATCH_ROOT/build/$TAG/NuHamil_serial.exe"
if [ ! -x "$BIN" ]; then
    echo "ERROR: no serial binary at $BIN" >&2
    exit 2
fi

rm -rf "$DEST"
cp -r "$SRC" "$DEST"
rm -f "$DEST"/ops/*"$CHAN"*
cd "$DEST"
INPUT="$(ls Input_*.dat | head -n1)"

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-${SLURM_CPUS_PER_TASK:-1}}"
export NUHAMIL_CLEAN=0   # keep cfp/ and the remaining ops/ so channels skip

echo "=== reprofile: node=${SLURMD_NODENAME:-?} binary=$BIN"
echo "=== source=$SRC"
echo "=== profile dir=$DEST"
echo "=== channel removed: $CHAN  ->  ops files left: $(ls ops | wc -l)/64"
echo "=== threads=$OMP_NUM_THREADS  start=$(date -Is)"

START=$(date +%s)
perf record -e cycles:u -o "$DEST/perf.data" -- "$BIN" "$INPUT" > "$DEST/run.out" 2>&1
END=$(date +%s)
echo "=== wall=$((END - START))s"

perf report --stdio -i "$DEST/perf.data" --sort overhead,symbol \
    > "$DEST/perf-report.txt" 2>/dev/null || true
echo "=== top symbols ==============================================="
sed -n '/^ *[0-9]/p' "$DEST/perf-report.txt" | head -25
echo "=== full report: $DEST/perf-report.txt"
echo "=== run log:     $DEST/run.out"
