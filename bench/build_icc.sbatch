#!/bin/bash
#SBATCH --job-name=nh-build
#SBATCH --account=soham-ic
#SBATCH --partition=IllinoisComputes
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=/scratch/soham/NuHamil-faster/build/slurm-%j.out
#SBATCH --error=/scratch/soham/NuHamil-faster/build/slurm-%j.err
# ---------------------------------------------------------------------------
# Thin scheduler wrapper around bench/build_icc.sh (run on a compute node).
#
#   sbatch bench/build_icc.sbatch            # tag=base   -> build/base/
#   sbatch bench/build_icc.sbatch mytag      # tag=mytag
#   sbatch -c 64 --time=03:00:00 bench/build_icc.sbatch base
#
# See bench/build_icc.sh for outputs and env knobs.
# ---------------------------------------------------------------------------
set -euo pipefail

REPO="${NH_REPO:-/u/soham/NuHamil-faster/upstream}"
TAG="${1:-base}"

# Refuse a partition that is not on the allow-list.  Defence in depth: the real
# guard is bench/submit.sh, which catches -p before sbatch is called.
# shellcheck source=partitions.sh
. "$REPO/bench/partitions.sh"
if ! nh_check_partition "${SLURM_JOB_PARTITION:-}"; then
    echo "ERROR: aborting before doing any work." >&2
    exit 2
fi

exec bash "$REPO/bench/build_icc.sh" "$TAG" "${SLURM_CPUS_PER_TASK:-8}"
