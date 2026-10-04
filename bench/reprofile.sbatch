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

# Every run gets its own directory.  Deriving it from the source name alone meant
# successive profiles of the same source silently overwrote each other -- which
# actually happened: a 4-thread flat profile was replaced by the 1-thread one, and
# the stale numbers were nearly read as current.  Override with NH_PROFILE_TAG.
PROF_TAG="${NH_PROFILE_TAG:-$(date +%Y%m%dT%H%M%S)}"
DEST="$SCRATCH_ROOT/runs/prof-$(basename "$SRC")-$PROF_TAG"
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
# NH_CALLGRAPH=1 adds stacks, which is what attributes barrier-idle time
# (libgomp) to the parallel region that caused it -- a flat profile cannot.
if [ "${NH_CALLGRAPH:-0}" = "1" ]; then
    # Depth and rate matter here: the default dwarf dump is ~8 KB/sample at the
    # default ~4 kHz, which produced an 11 GB perf.data for an 83 s run and took
    # longer to report than to record.  2048 bytes at 197 Hz is ~35 MB and still
    # ample to see which parallel region a barrier belongs to.
    CG=(--call-graph dwarf,2048 -F 197)
    echo "=== call graph: dwarf,2048 -F 197 ==="
else
    CG=()
fi
perf record -e cycles:u "${CG[@]}" -o "$DEST/perf.data" -- "$BIN" "$INPUT" > "$DEST/run.out" 2>&1
END=$(date +%s)
echo "=== wall=$((END - START))s"

perf report --stdio -i "$DEST/perf.data" --sort overhead,symbol \
    > "$DEST/perf-report.txt" 2>/dev/null || true
echo "=== top symbols ==============================================="
sed -n '/^ *[0-9]/p' "$DEST/perf-report.txt" | head -25
echo "=== full report: $DEST/perf-report.txt"
echo "=== run log:     $DEST/run.out"

if [ "${NH_CALLGRAPH:-0}" = "1" ]; then
    perf report --stdio -i "$DEST/perf.data" -g folded \
        > "$DEST/perf-folded.txt" 2>/dev/null || true
    echo "=== folded stacks (for attribution): $DEST/perf-folded.txt"
    # Which parallel region does the barrier time belong to?  Walk each folded
    # chain, find gomp_barrier_wait*, and report the nearest enclosing
    # _omp_fn / subroutine frame.
    awk '
      /;gomp_(team_)?barrier_wait/ {
        n = split($0, a, ";")
        region = "?"
        for (i = n; i >= 1; i--) {
          if (a[i] ~ /_omp_fn|MOD_/) { region = a[i]; break }
        }
        printf "%4.2f%%  %s\n", $1, region
      }' "$DEST/perf-folded.txt" 2>/dev/null | sort -rn | head -20
fi
