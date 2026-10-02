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

exec bash "$REPO/bench/build_icc.sh" "$TAG" "${SLURM_CPUS_PER_TASK:-8}"
