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
acct=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    a="${args[i]}"
    case "$a" in
        --partition=*) part="${a#--partition=}" ;;
        -p | --partition) part="${args[i + 1]:-}" ;;
        -p*) part="${a#-p}" ;;
        --account=*) acct="${a#--account=}" ;;
        -A | --account) acct="${args[i + 1]:-}" ;;
        -A*) acct="${a#-A}" ;;
    esac
done

if ! nh_check_partition "$part"; then
    exit 2
fi

# Account policy.  Checked before anything is queued, so a disallowed account can
# never be charged by accident -- see the reasoning in partitions.sh.
if ! nh_check_account "$acct"; then
    exit 2
fi

# Some partitions admit us only through an explicit account; omitting -A there
# fails inside sbatch with a message that reads like a permissions problem.
if nh_partition_needs_account "$part" && [ -z "$acct" ]; then
    printf 'REFUSING: partition "%s" requires an explicit account.\n' "$part" >&2
    printf 'Pass -A %s.\n' "$NH_ALLOWED_ACCOUNTS" >&2
    exit 2
fi

exec sbatch "$@"
