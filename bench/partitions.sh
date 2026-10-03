# Partition policy for NuHamil-faster.  SOURCE this file; do not execute it.
#
#   . "$REPO/bench/partitions.sh"
#   nh_check_partition "$SLURM_JOB_PARTITION" || exit 2
#
# Why this exists
# ---------------
# Slurm's MaxTime is what the scheduler *enforces*, not what the site *permits*.
# ic-express advertises MaxTime=08:00:00 while its published policy is short
# interactive/debugging jobs needing rapid turnaround with a 2-hour maximum, and
# it is a SINGLE node (TotalNodes=1, TotalCPUs=48).  Slurm therefore accepted an
# 8-hour batch sweep without complaint, and those jobs would have monopolised the
# entire express queue.  ic-express is listed below as explicitly forbidden, not
# merely absent from an allow-list, so the reason travels with the rule.
#
# The enforced limit is not the policy.  Before adding a partition here, read its
# published intended use rather than trusting `scontrol show partition`.

NH_ALLOWED_PARTITIONS="scavenger IllinoisComputes IllinoisComputes-GPU"

# Echo the reason a partition is refused, or nothing if it is acceptable.
nh_partition_reason() {
    case "$1" in
        ic-express)
            printf '%s' "reserved for short interactive/debugging jobs (2h maximum, single 48-CPU node); batch builds and sweeps block the express queue" ;;
        scavenger | IllinoisComputes | IllinoisComputes-GPU)
            printf '%s' "" ;;
        "")
            # no partition given: the #SBATCH --partition directive in the
            # script decides, and those are all on the allow-list
            printf '%s' "" ;;
        *)
            printf '%s' "not on the NuHamil-faster allow-list ($NH_ALLOWED_PARTITIONS)" ;;
    esac
}

# Return 0 if $1 may be used, 1 (with an explanation on stderr) if not.
# NH_PARTITION_OVERRIDE=1 forces it through with a warning.
nh_check_partition() {
    _nh_reason=$(nh_partition_reason "$1")
    [ -z "$_nh_reason" ] && return 0

    if [ "${NH_PARTITION_OVERRIDE:-0}" = "1" ]; then
        printf 'WARNING: partition "%s" is %s\n' "$1" "$_nh_reason" >&2
        printf 'WARNING: NH_PARTITION_OVERRIDE=1 set; proceeding anyway.\n' >&2
        return 0
    fi

    printf 'REFUSING partition "%s": %s\n' "$1" "$_nh_reason" >&2
    printf 'Allowed partitions: %s\n' "$NH_ALLOWED_PARTITIONS" >&2
    printf "Check a partition's published intended use before adding it.\n" >&2
    printf 'To override deliberately: NH_PARTITION_OVERRIDE=1\n' >&2
    return 1
}
