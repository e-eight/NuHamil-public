#!/bin/bash
#SBATCH --job-name=nh-nodecal
#SBATCH --account=soham-ic
#SBATCH --partition=scavenger
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=8G
#SBATCH --time=00:15:00
#SBATCH --output=/scratch/soham/NuHamil-faster/runs/slurm-%j.out
#SBATCH --error=/scratch/soham/NuHamil-faster/runs/slurm-%j.err
# ---------------------------------------------------------------------------
# Run the node-speed calibration probe on one compute node.  Never run on a
# login node.  Compiles bench/nodecal.c here (a few seconds) and runs it.
#
#   bench/submit.sh -p scavenger --requeue -c 32 bench/nodecal.sbatch
#   bench/submit.sh -p scavenger --requeue -c 32 --nodelist=ccc0497 bench/nodecal.sbatch
#
# Results are appended to $SCRATCH_ROOT/tmp/nodecal-<node>.txt so repeated runs
# build up a per-node table.  Compare with the full-case times in
# docs/FINDINGS.md before trusting the probe for small deltas.
#
# Why: scavenger nodes are heterogeneous by up to 1.67x for the same binary, and
# that has already invalidated three sets of measurements.  See nodecal.c.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRATCH_ROOT="${NH_SCRATCH_ROOT:-/scratch/soham/NuHamil-faster}"
REPO="${NH_REPO:-/u/soham/NuHamil-faster/upstream}"
MKLROOT="/sw/apps/intel/oneapi/mkl/2025.0"

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

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-${SLURM_CPUS_PER_TASK:-1}}"

BIN="$SCRATCH_ROOT/tmp/nodecal-${SLURM_JOB_ID:-$$}.exe"
mkdir -p "$SCRATCH_ROOT/tmp"

echo "=== nodecal: node=${SLURMD_NODENAME:-?} threads=$OMP_NUM_THREADS date=$(date -Is)"
echo "=== compiler: $(gcc --version | head -n1)"

gcc -O3 -fopenmp -o "$BIN" "$REPO/bench/nodecal.c" \
    -L"$MKLROOT/lib" -lmkl_intel_lp64 -lmkl_gnu_thread -lmkl_core \
    -lm -ldl -lpthread -Wl,-rpath,"$MKLROOT/lib"

OUT="$SCRATCH_ROOT/tmp/nodecal-${SLURMD_NODENAME:-unknown}.txt"
"$BIN" | tee "$OUT"
echo "=== wrote $OUT"
