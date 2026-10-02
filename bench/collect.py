#!/usr/bin/env python3
"""Collect NuHamil benchmark results from $SCRATCH_ROOT/runs into CSV/JSON.

Login-node safe: reads logs and writes small summary files, runs no NuHamil.

For every $SCRATCH_ROOT/runs/<case>/run-<jobid>.env written by
bench/run_case.sbatch it extracts

  * run metadata       (ranks, threads, partition, node, wall, exit code)
  * per-rank profiler  (#PROF_RANK lines) -> work imbalance max/mean/min
  * per-rank category  (#PROF_CAT lines, when NUHAMIL_PROF_DUMP=1)
  * output artefact    (existence + sha256 of manifest['expected_output'])
  * reference check    (e.g. the deuteron energy vs manifest['reference'])
  * Slurm accounting   (optional: Elapsed / MaxRSS via sacct)

and writes
  <out>/results.csv    one row per run
  <out>/results.json   nested, includes the rank-0 category breakdown

Usage
-----
  python3 bench/collect.py
  python3 bench/collect.py --cases 3bme_e3max8 --quiet
  python3 bench/collect.py --no-sacct
  python3 bench/collect.py --root /scratch/soham/NuHamil-faster --out /tmp/x
"""

import argparse
import csv
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
from pathlib import Path

HASH_LIMIT = 4 * 1024 ** 3  # do not hash artefacts larger than 4 GiB
FLOAT_RE = re.compile(r"^\s*(-?\d+\.\d{6,})\s*$")
TABLE_RE = re.compile(r"^(.*?)\s+(-?\d+\.\d+)\s+(\d+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s*$")


# ---------------------------------------------------------------------------
def read_env(path):
    d = {}
    for line in path.read_text(errors="replace").splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            d[k.strip()] = v.strip()
    return d


def parse_prof_rank(text):
    """#PROF_RANK <rank> <nprocs> wall <w> acct <a> misc <m>"""
    rows = []
    for line in text.splitlines():
        if not line.startswith("#PROF_RANK"):
            continue
        t = line.split()
        if len(t) != 9 or t[3] != "wall" or t[5] != "acct" or t[7] != "misc":
            continue
        try:
            rows.append({"rank": int(t[1]), "nprocs": int(t[2]),
                         "wall": float(t[4]), "acct": float(t[6]),
                         "misc": float(t[8])})
        except ValueError:
            continue
    return rows


def parse_prof_cat(text):
    """#PROF_CAT <rank> <key possibly containing spaces> <time> <ncall>

    The category key contains spaces ('MPI parent-child procedure',
    'Read from file', ...), so the key must be taken as everything between the
    rank token and the final two numeric tokens.
    """
    by_rank = {}
    for line in text.splitlines():
        if not line.startswith("#PROF_CAT "):
            continue
        rank_s, sep, remainder = line[len("#PROF_CAT "):].partition(" ")
        if not sep:
            continue
        bits = remainder.rsplit(None, 2)
        if len(bits) != 3:
            continue
        key, time_s, ncall_s = bits
        try:
            by_rank.setdefault(int(rank_s), []).append(
                {"key": key, "time": float(time_s), "ncall": int(ncall_s)})
        except ValueError:
            continue
    return by_rank


def parse_rank0_table(text):
    """Fallback: parse the human readable rank-0 profiler table."""
    out, in_tbl = [], False
    for line in text.splitlines():
        if "time,    ncall, time/ncall,   ratio" in line:
            in_tbl = True
            continue
        if in_tbl:
            if line.strip() == "" or line.strip().startswith("misc"):
                in_tbl = False
                continue
            m = TABLE_RE.match(line)
            if m:
                try:
                    out.append({"key": m.group(1).strip(),
                                "time": float(m.group(2)),
                                "ncall": int(m.group(3))})
                except ValueError:
                    pass
    return out


def parse_energies(text):
    vals = []
    for line in text.splitlines():
        m = FLOAT_RE.match(line)
        if m:
            vals.append(float(m.group(1)))
            if len(vals) >= 5:
                break
    return vals


def sha256_of(path, limit=HASH_LIMIT):
    if not path.is_file():
        return None
    if path.stat().st_size > limit:
        return "skipped-too-large"
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


TIME_V_RE = re.compile(r"Maximum resident set size \(kbytes\):\s*(\d+)")


def parse_time_v(text):
    """Peak RSS reported by `/usr/bin/time -v` (single-rank runs only)."""
    m = TIME_V_RE.search(text)
    return int(m.group(1)) if m else None


def to_kb(txt):
    """Slurm prints MaxRSS with a unit suffix (K/M/G); normalise to KiB."""
    if not txt:
        return None
    t = txt.strip()
    if t in ("", "0", "0K"):
        return 0
    mult = {"K": 1, "M": 1024, "G": 1024 ** 2, "T": 1024 ** 3}
    if t[-1].upper() in mult:
        try:
            return int(float(t[:-1]) * mult[t[-1].upper()])
        except ValueError:
            return None
    try:
        return int(float(t))
    except ValueError:
        return None


def sacct_info(jobid):
    """Aggregate Elapsed/MaxRSS over every step of a job.

    `-X` (allocations only) leaves MaxRSS blank on this Slurm build, so query
    all steps and keep the largest RSS seen; the wall time comes from the
    top-level job line.
    """
    if not jobid or jobid == "local" or shutil.which("sacct") is None:
        return {}
    try:
        out = subprocess.check_output(
            ["sacct", "-j", str(jobid), "-n", "-P",
             "-o", "JobID,Elapsed,MaxRSS,MaxVMSize,State,ExitCode"],
            stderr=subprocess.DEVNULL, text=True, timeout=30)
    except Exception:
        return {}

    info, maxrss, maxvms = {}, None, None
    for line in out.splitlines():
        line = line.strip()
        if not line or "|" not in line:
            continue
        f = line.split("|")
        if len(f) < 6:
            continue
        jid, elapsed, rss, vms, state, ec = (f[0], f[1], f[2], f[3], f[4], f[5])
        if jid.endswith(".extern"):
            continue
        if "sacct_elapsed" not in info and elapsed:
            info["sacct_elapsed"] = elapsed
            info["sacct_state"] = state
            info["sacct_exitcode"] = ec
        r, v = to_kb(rss), to_kb(vms)
        if r is not None:
            maxrss = r if maxrss is None else max(maxrss, r)
        if v is not None:
            maxvms = v if maxvms is None else max(maxvms, v)
    if maxrss:
        info["sacct_maxrss_kb"] = maxrss
        info["sacct_maxrss_mb"] = round(maxrss / 1024.0, 1)
    if maxvms:
        info["sacct_maxvmsize_kb"] = maxvms
    return info


def mean(xs):
    return sum(xs) / len(xs) if xs else math.nan


def elapsed_to_s(txt):
    """Slurm Elapsed formats: MM:SS, HH:MM:SS, D-HH:MM:SS."""
    if not txt:
        return None
    try:
        days = 0
        if "-" in txt:
            d, txt = txt.split("-", 1)
            days = int(d)
        parts = [int(p) for p in txt.split(":")]
        while len(parts) < 3:
            parts.insert(0, 0)
        return days * 86400 + parts[0] * 3600 + parts[1] * 60 + parts[2]
    except Exception:
        return None


# ---------------------------------------------------------------------------
def collect_run(env_path, do_sacct=True):
    meta = read_env(env_path)
    rdir = env_path.parent
    rec = dict(meta)
    rec["run_dir"] = str(rdir)
    rec["run_env"] = env_path.name

    for k in ("ntasks", "cpus_per_task", "omp_num_threads", "total_threads",
              "wall_s", "exit_code", "restart_count"):
        try:
            rec[k] = int(meta.get(k, ""))
        except ValueError:
            rec[k] = None

    manifest = {}
    mpath = rdir / "manifest.json"
    if mpath.is_file():
        try:
            manifest = json.loads(mpath.read_text())
        except Exception:
            manifest = {}
    rec["tier"] = manifest.get("tier")
    rec["case"] = meta.get("case") or manifest.get("case")
    rec["kind"] = meta.get("kind") or manifest.get("kind")

    log = rdir / meta.get("log", "")
    text = log.read_text(errors="replace") if log.is_file() else ""

    ranks = parse_prof_rank(text)
    cats = parse_prof_cat(text)
    tbl = parse_rank0_table(text)
    rec["n_ranks_reported"] = len(ranks)

    if ranks:
        acct = [r["acct"] for r in ranks]
        wall = [r["wall"] for r in ranks]
        rec["acct_max_s"] = max(acct)
        rec["acct_min_s"] = min(acct)
        rec["acct_mean_s"] = mean(acct)
        rec["wall_max_s"] = max(wall)
        rec["wall_min_s"] = min(wall)
        rec["imbalance_max_over_mean"] = (max(acct) / mean(acct)
                                          if mean(acct) else math.nan)
        rec["imbalance_max_over_min"] = (max(acct) / min(acct)
                                         if min(acct) > 0 else math.nan)
        rec["efficiency_mean_over_max"] = (mean(acct) / max(acct)
                                           if max(acct) else math.nan)
    else:
        for k in ("acct_max_s", "acct_min_s", "acct_mean_s", "wall_max_s",
                  "wall_min_s", "imbalance_max_over_mean",
                  "imbalance_max_over_min", "efficiency_mean_over_max"):
            rec[k] = math.nan

    # rank-0 category breakdown: prefer the machine readable dump
    rank0 = sorted(cats.get(0, []), key=lambda d: -d["time"]) if cats else []
    if not rank0:
        rank0 = sorted(tbl, key=lambda d: -d["time"])
    rec["rank0_categories"] = rank0[:15]
    rec["rank0_acct_s"] = next((r["acct"] for r in ranks if r["rank"] == 0),
                               None) if ranks else None
    if rank0:
        rec["rank0_top_cat"] = rank0[0]["key"]
        rec["rank0_top_cat_s"] = rank0[0]["time"]

    # reference check (deuteron energy etc.)
    ref = manifest.get("reference") or {}
    if ref:
        vals = parse_energies(text)
        if vals:
            rec["energy_MeV"] = vals[0]
            rec["energy_candidates"] = vals
            r0 = ref.get("energy_MeV")
            tol = ref.get("tolerance_MeV", 1e-5)
            if r0 is not None:
                rec["energy_ref_MeV"] = r0
                rec["energy_ok"] = abs(vals[0] - r0) <= tol

    # output artefact
    exp = manifest.get("expected_output")
    if exp:
        op = rdir / exp
        rec["output_file"] = exp
        rec["output_exists"] = op.is_file()
        if op.is_file():
            rec["output_bytes"] = op.stat().st_size
            rec["output_sha256"] = sha256_of(op)

    tv = parse_time_v(text)
    if tv is not None:
        rec["time_v_maxrss_kb"] = tv
        rec["time_v_maxrss_mb"] = round(tv / 1024.0, 1)

    if do_sacct:
        rec.update(sacct_info(meta.get("jobid")))
    if rec.get("sacct_elapsed"):
        rec["sacct_elapsed_s"] = elapsed_to_s(rec["sacct_elapsed"])

    ec = rec.get("exit_code")
    st = rec.get("sacct_state")
    rec["status"] = ("unknown" if ec is None else
                     ("ok" if ec == 0 else "failed"))
    if st and st not in ("COMPLETED", "") and rec["status"] == "ok":
        rec["status"] = st.lower()
    return rec


def add_scaling(recs):
    """Per case: speedup and parallel efficiency vs the smallest thread count."""
    by_case = {}
    for r in recs:
        if r.get("case") and r.get("wall_s"):
            by_case.setdefault(r["case"], []).append(r)
    for case, rows in by_case.items():
        base = min(rows, key=lambda r: (r.get("total_threads") or 10 ** 9,
                                        r.get("wall_s")))
        w0 = base.get("wall_s")
        t0 = base.get("total_threads") or 1
        for r in rows:
            w, t = r.get("wall_s"), r.get("total_threads")
            if w and t and w0:
                r["speedup_vs_min_threads"] = w0 / w
                r["parallel_efficiency"] = (w0 / w) * (t0 / t)
                r["baseline_total_threads"] = t0
                r["baseline_wall_s"] = w0
    return recs


CSV_COLS = [
    "case", "tier", "kind", "status", "jobid", "partition", "nodelist",
    "ntasks", "cpus_per_task", "omp_num_threads", "total_threads", "cold",
    "wall_s", "sacct_elapsed", "sacct_maxrss_mb", "sacct_maxrss_kb",
    "sacct_maxvmsize_kb", "time_v_maxrss_mb", "exit_code",
    "acct_max_s", "acct_mean_s", "acct_min_s",
    "imbalance_max_over_mean", "imbalance_max_over_min",
    "efficiency_mean_over_max",
    "speedup_vs_min_threads", "parallel_efficiency", "baseline_total_threads",
    "rank0_top_cat", "rank0_top_cat_s",
    "energy_MeV", "energy_ref_MeV", "energy_ok",
    "output_file", "output_exists", "output_bytes", "output_sha256",
    "n_ranks_reported", "run_dir", "log",
]


def fmt(v):
    if isinstance(v, float):
        if math.isnan(v):
            return ""
        return "%.6g" % v
    return "" if v is None else v


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default="/scratch/soham/NuHamil-faster")
    ap.add_argument("--out", default=None,
                    help="output dir (default: <root>/bench)")
    ap.add_argument("--cases", nargs="*", default=None)
    ap.add_argument("--no-sacct", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    root = Path(args.root)
    runs = root / "runs"
    out = Path(args.out) if args.out else (root / "bench")
    out.mkdir(parents=True, exist_ok=True)

    envs = sorted(runs.glob("*/run-*.env"))
    if args.cases:
        envs = [e for e in envs if e.parent.name in set(args.cases)]
    if not envs:
        sys.exit("no run-*.env found under %s (submit a case first)" % runs)

    recs = [collect_run(e, do_sacct=not args.no_sacct) for e in envs]
    recs = add_scaling(recs)
    recs.sort(key=lambda r: (r.get("case") or "", r.get("total_threads") or 0,
                             r.get("jobid") or ""))

    csv_path = out / "results.csv"
    with open(csv_path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=CSV_COLS, extrasaction="ignore")
        w.writeheader()
        for r in recs:
            w.writerow({k: fmt(r.get(k)) for k in CSV_COLS})

    json_path = out / "results.json"
    json_path.write_text(json.dumps(recs, indent=2, default=str) + "\n")

    if not args.quiet:
        print("%-22s %5s %5s %8s %10s %10s %9s %6s"
              % ("case", "rank", "omp", "wall_s", "acct_max", "acct_mean",
                 "imbal", "status"))
        print("-" * 84)
        for r in recs:
            print("%-22s %5s %5s %8s %10s %10s %9s %6s"
                  % (r.get("case"), r.get("ntasks"), r.get("omp_num_threads"),
                     fmt(r.get("wall_s")), fmt(r.get("acct_max_s")),
                     fmt(r.get("acct_mean_s")),
                     fmt(r.get("imbalance_max_over_mean")), r.get("status")))
        print()
        print("runs     : %d" % len(recs))
        print("results  : %s" % csv_path)
        print("           %s" % json_path)
        bad = [r for r in recs if r.get("status") != "ok"]
        if bad:
            print("non-ok   : %s" % ", ".join(
                "%s(job %s)" % (r.get("case"), r.get("jobid")) for r in bad))
    return 0


if __name__ == "__main__":
    sys.exit(main())
