#!/bin/bash
# Submit a NuHamil-faster benchmark/build job, refusing partitions that are not
# on the allow-list.
#
#   bench/submit.sh -p scavenger --requeue -J nh-omp8x4 -n 8 -c 4 \
#       --mem=64G --time=08:00:00 bench/run_case.sbatch 3bme_e3max6__rampsmall
#
# Every argument is passed to sbatch unchanged.  This wrapper exists because a
# batch script cannot intercept its own `-p` value until the job is already
# queued -- by which point the mistake has been made.  The .sbatch scripts also
# check $SLURM_JOB_PARTITION as defence in depth, in case sbatch is called
# directly.
#
# See bench/partitions.sh for the policy and the reasoning behind it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=partitions.sh
. "$HERE/partitions.sh"

part=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    a="${args[i]}"
    case "$a" in
        --partition=*) part="${a#--partition=}" ;;
        -p | --partition) part="${args[i + 1]:-}" ;;
        -p*) part="${a#-p}" ;;
    esac
done

if ! nh_check_partition "$part"; then
    exit 2
fi

exec sbatch "$@"
