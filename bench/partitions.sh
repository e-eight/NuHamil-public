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

# ---------------------------------------------------------------------------
# Account policy.  Same shape of rule as the partition list above, and here for
# the same reason: the scheduler enforces what it will *accept*, not what the
# project is *allowed* to use.
#
# The user holds several accounts (`sacctmgr show assoc user=soham`) and Slurm
# will happily charge any of them.  For this project only `soham-ic` may be used;
# `ncsa-ic` in particular is NOT ours to spend.  That is a policy fact about the
# project, and Slurm cannot know it, so it has to live here.
#
# IllinoisComputes is account-gated: it admits acc-illinoiscomputes/acc-ncsa via
# AllowAccounts, and our access is via `-A soham-ic`.  Omitting `-A` there fails
# with a misleading "You must specify an account in order to submit a job to this
# partition" -- which reads like a permissions problem and is not one.  So an
# explicit allowed account is REQUIRED for that partition.

NH_ALLOWED_ACCOUNTS="soham-ic"
NH_ACCOUNT_REQUIRED_PARTITIONS="IllinoisComputes IllinoisComputes-GPU"

nh_account_reason() {
    case "$1" in
        soham-ic)
            printf '%s' "" ;;
        "")
            # No -A given: fine on partitions that resolve a default account.
            # Where an account is genuinely required, nh_partition_needs_account
            # below catches it -- keeping "omitted" apart from "not allowed".
            printf '%s' "" ;;
        ncsa-ic)
            printf '%s' "not this project's account -- ncsa-ic is not ours to spend" ;;
        *)
            printf '%s' "not on the NuHamil-faster account allow-list ($NH_ALLOWED_ACCOUNTS)" ;;
    esac
}

# Return 0 if the account may be used, 1 with an explanation otherwise.
nh_check_account() {
    _nh_areason=$(nh_account_reason "$1")
    [ -z "$_nh_areason" ] && return 0
    printf 'REFUSING account "%s": %s\n' "${1:-(none given)}" "$_nh_areason" >&2
    printf 'Allowed accounts for this project: %s\n' "$NH_ALLOWED_ACCOUNTS" >&2
    return 1
}

# IllinoisComputes needs an account passed explicitly, so require one there
# rather than letting sbatch fail with a message that misattributes the cause.
nh_partition_needs_account() {
    case "$1" in
        IllinoisComputes | IllinoisComputes-GPU) return 0 ;;
        *) return 1 ;;
    esac
}
