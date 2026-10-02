#!/usr/bin/env python3
"""Generate NuHamil benchmark inputs (namelists) under $SCRATCH_ROOT.

This is login-node safe: it only imports the upstream parameter builders and
writes text files under scratch_root.  It never builds or runs NuHamil.

The case definitions live in bench/cases.yaml.  All derived quantities
(jmax3, LECs, output file names, ...) come from the upstream builders in
exe/NuHamil_2BME.py, exe/NuHamil_3BME.py and exe/few-body/deuteron.py, so
nothing is duplicated here.

Usage
-----
  python3 bench/gen_cases.py --list
  python3 bench/gen_cases.py                        # all non-production cases
  python3 bench/gen_cases.py --cases 3bme_e3max6 3bme_e3max8
  python3 bench/gen_cases.py --include-production
  python3 bench/gen_cases.py --root /scratch/soham/NuHamil-faster

Produces, per case:
  <root>/runs/<case-id>/Input_<base>.dat   the Fortran namelist
  <root>/runs/<case-id>/manifest.json      resolved params + expectations

Requires PyYAML (system python3 provides it; otherwise `module load python`).
"""

import argparse
import importlib.util
import json
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("PyYAML is required (try: module load python/3.13.2)")

BENCH_DIR = Path(__file__).resolve().parent
REPO = BENCH_DIR.parent
CASES_YAML = BENCH_DIR / "cases.yaml"


# ---------------------------------------------------------------------------
# upstream module loading
# ---------------------------------------------------------------------------
def load_upstream(relpath, name):
    """Import one of the upstream driver modules without running main()."""
    spec = importlib.util.spec_from_file_location(name, REPO / relpath)
    if spec is None or spec.loader is None:
        sys.exit("cannot load upstream module: %s" % (REPO / relpath))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def git_commit(path):
    try:
        return subprocess.check_output(
            ["git", "-C", str(path), "rev-parse", "HEAD"],
            stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return None


# ---------------------------------------------------------------------------
# namelist writer -- byte-for-byte the same formatting as the upstream
# gen_script() functions so generated files are interchangeable with theirs.
# ---------------------------------------------------------------------------
def namelist_text(params):
    out = ["&input"]
    for key, value in params.items():
        if isinstance(value, str):
            out.append("  " + str(key) + '= "' + str(value) + '" ')
            continue
        if isinstance(value, list):
            line = "  " + str(key) + "= "
            for x in value[:-1]:
                line += str(x) + ", "
            line += str(value[-1])
            out.append(line)
            continue
        out.append("  " + str(key) + "=" + str(value))
    out.append("&end")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# per-kind parameter construction
# ---------------------------------------------------------------------------
def build_case(case, cfg, nn_dir, mods):
    """Return (params, script_base, expected_output) for one case."""
    d = cfg["defaults"]
    kind = case["kind"]

    if kind == "deuteron":
        m = mods["deuteron"]
        m.path_to_nninput = str(nn_dir)
        params = OrderedDict()
        m.set_input(params, hw=case.get("hw", d["hw"]))
        return params, m.get_script_name(params), None

    if kind == "namelist2":
        m = mods["n2"]
        m.path_to_nninput = str(nn_dir)
        m.NNF = case.get("nn", d["nn"])
        params = OrderedDict()
        m.set_input(params,
                    hw=case.get("hw", d["hw"]),
                    emax=case.get("emax", d["emax"]),
                    e2max=case.get("e2max", d["e2max"]))
        return params, m.get_script_name(params), params.get("file_name_nn")

    if kind == "namelist3":
        m = mods["n3"]
        m.path_to_nninput = str(nn_dir)
        m.NNF = case.get("nn", d["nn"])
        m.TNF = case.get("tnf", d["tnf"])
        if case.get("_ramp"):
            m.ramp_space = case["_ramp"]
        params = OrderedDict()
        m.set_input(params,
                    hw=case.get("hw", d["hw"]),
                    hw_target=case.get("hw_target", d["hw_target"]),
                    emax=case.get("emax", d["emax"]),
                    e2max=case.get("e2max", d["e2max"]),
                    e3max=case.get("e3max", d["e3max"]))
        # get_script_name() consumes params["3nf"] (an internal key that must
        # not reach the namelist), so it has to run after set_file_name_3n().
        base = m.get_script_name(params)
        return params, base, params.get("file_name_3n")

    sys.exit("unknown case kind: %r (case %s)"
             % (kind, case.get("_id", case.get("id"))))


def derived(case, params, kind):
    """Extra cost/expectation metadata recorded in the manifest."""
    d = {}
    if kind == "namelist3":
        e3max = int(params["e3max"])
        d["n_channels"] = (e3max + 2) * 4
        d["jmax3"] = params.get("jmax3")
        d["ramp"] = params.get("ramp")
        d["lab_3bme_precision"] = params.get("lab_3bme_precision", "single")
        if params.get("ramp") and params.get("jmax3"):
            sched = parse_ramp(params["ramp"])[0]
            d["nmax_per_channel"] = {
                "2J+1=%d" % j: nmax_for_j(sched, j)
                for j in range(1, int(params["jmax3"]) + 1, 2)}
            d["ramp_nmax_values"] = sorted(set(d["nmax_per_channel"].values()),
                                           reverse=True)
    if kind == "namelist2":
        d["emax"] = params.get("emax")
        d["e2max"] = params.get("e2max")
    return d


# ---------------------------------------------------------------------------
# Jacobi-space ramp helpers.  A python mirror of GetRampNmax() in
# src/ThreeBody/ThreeBodyJacobiSpaceIso.F90, so the harness can record and
# cross-check exactly which Nmax every (J,P,T) channel gets.  The Fortran
# callers pass j = 2J+1.
# ---------------------------------------------------------------------------
def parse_ramp(ramp):
    """Return (schedule, is_flat).

    schedule[0] is (None, seed_Nmax); every later entry (j_threshold, Nmax)
    means "for 2J+1 > j_threshold use Nmax".
    """
    r = str(ramp).strip()
    if r.startswith("flat"):
        return [(None, int(r[4:]))], True
    if r.startswith("ramp"):
        parts = r.split("-")
        sched = [(None, int(parts[0][4:]))]
        for i in range(1, len(parts) // 2 + 1):
            sched.append((int(parts[2 * i - 1]), int(parts[2 * i])))
        return sched, False
    raise ValueError("unrecognised ramp %r (expected 'flat<N>' or "
                     "'ramp<N>-<j>-<N>-...')" % ramp)


def nmax_for_j(sched, j):
    """Nmax for one channel, j being 2J+1 as the Fortran callers pass it."""
    n = sched[0][1]
    for thr, val in sched[1:]:
        if j > thr:
            n = val
    return n


def ramp_schedule_text(sched):
    if sched is None:
        return "-"
    bits = ["seed Nmax=%d" % sched[0][1]]
    bits += ["2J+1>%d -> %d" % (thr, val) for thr, val in sched[1:]]
    return ", ".join(bits)


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cases", nargs="*", default=None,
                    help="case ids to generate; base id or expanded id "
                         "(default: all non-production)")
    ap.add_argument("--ramps", nargs="*", default=None,
                    help="ramp names to instantiate for 3N cases "
                         "(default: every case's ramp_sweep)")
    ap.add_argument("--include-production", action="store_true",
                    help="also generate tier=production cases")
    ap.add_argument("--root", default=None,
                    help="scratch root (default: scratch_root from cases.yaml)")
    ap.add_argument("--list", action="store_true", help="list cases and exit")
    ap.add_argument("--force", action="store_true",
                    help="overwrite an existing Input_*.dat")
    args = ap.parse_args()

    with open(CASES_YAML) as fh:
        cfg = yaml.safe_load(fh)

    ramps = cfg.get("ramps") or {}
    for _name, _r in ramps.items():
        parse_ramp(_r)  # fail fast on a malformed ramp

    # ---- expand: one instance per (case, ramp) for 3N cases --------------
    inst = []
    for c in cfg["cases"]:
        if c["kind"] == "namelist3":
            names = c.get("ramp_sweep") or list(ramps)
            for rn in names:
                if rn not in ramps:
                    sys.exit("case %s references unknown ramp %r" % (c["id"], rn))
                inst.append(dict(c, _id="%s__%s" % (c["id"], rn),
                                 _ramp_name=rn, _ramp=ramps[rn]))
        else:
            inst.append(dict(c, _id=c["id"], _ramp_name=None, _ramp=None))

    if args.list:
        print("%-36s %-11s %-10s %s" % ("ID", "TIER", "KIND", "RAMP SCHEDULE"))
        for c in inst:
            sched = parse_ramp(c["_ramp"])[0] if c["_ramp"] else None
            print("%-36s %-11s %-10s %s"
                  % (c["_id"], c["tier"], c["kind"], ramp_schedule_text(sched)))
        return 0

    if args.cases:
        known = {c["_id"] for c in inst} | {c["id"] for c in inst}
        unknown = [x for x in args.cases if x not in known]
        if unknown:
            sys.exit("unknown case id(s): %s" % ", ".join(unknown))
    if args.ramps:
        unknown = [x for x in args.ramps if x not in ramps]
        if unknown:
            sys.exit("unknown ramp name(s): %s (known: %s)"
                     % (", ".join(unknown), ", ".join(ramps)))

    selected = []
    for c in inst:
        if not args.include_production and c["tier"] == "production":
            continue
        if args.cases and c["_id"] not in args.cases and c["id"] not in args.cases:
            continue
        if args.ramps and c["_ramp_name"] and c["_ramp_name"] not in args.ramps:
            continue
        selected.append(c)
    if not selected:
        sys.exit("no cases selected")

    root = Path(args.root or cfg["scratch_root"]).expanduser()
    runs = root / "runs"
    nn_dir = REPO / "input_nn_files"

    # locate the NN input files the upstream builders will reference
    nn_files = sorted(nn_dir.glob("*_kmax8_N100_Jmax8.bin"))
    if not nn_files:
        sys.exit("no NN input files found in %s" % nn_dir)

    mods = {
        "deuteron": load_upstream("exe/few-body/deuteron.py", "nh_deuteron"),
        "n2": load_upstream("exe/NuHamil_2BME.py", "nh_2bme"),
        "n3": load_upstream("exe/NuHamil_3BME.py", "nh_3bme"),
    }
    commit = git_commit(REPO)

    print("repo       : %s" % REPO)
    print("commit     : %s" % (commit or "(unknown)"))
    print("nn inputs  : %s (%d files)" % (nn_dir, len(nn_files)))
    print("run root   : %s" % runs)
    for rn, rv in ramps.items():
        print("ramp %-10s: %s   [%s]" % (rn, rv, ramp_schedule_text(parse_ramp(rv)[0])))
    print()

    written = []
    for case in selected:
        cid = case["_id"]
        params, base, expected = build_case(case, cfg, nn_dir, mods)
        kind = case["kind"]
        cdir = runs / cid
        cdir.mkdir(parents=True, exist_ok=True)
        input_name = "Input_" + base + ".dat"
        input_path = cdir / input_name

        if input_path.exists() and not args.force:
            action = "kept"
        else:
            input_path.write_text(namelist_text(params))
            action = "wrote"

        manifest = {
            "case": cid,
            "case_base": case["id"],
            "tier": case["tier"],
            "kind": kind,
            "description": " ".join(case["description"].split()),
            "generated_by": "bench/gen_cases.py",
            "repo": str(REPO),
            "repo_commit": commit,
            "input_file": input_name,
            "script_base": base,
            "expected_output": expected,
            "reference": case.get("reference", {}),
            "params": dict(params),
            "derived": derived(case, params, kind),
            "nn_input_file": params.get("input_nn_file"),
        }
        if case["_ramp"]:
            manifest["ramp_name"] = case["_ramp_name"]
            manifest["ramp"] = case["_ramp"]
        (cdir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

        nn_ref = params.get("input_nn_file")
        nn_ok = bool(nn_ref) and Path(nn_ref).exists()
        print("[%-6s] %-36s %s" % (action, cid, input_name))
        if nn_ref and not nn_ok:
            print("         WARNING: referenced NN file does not exist: %s" % nn_ref)
        if expected:
            print("         -> output: %s" % expected)
        if kind == "namelist3":
            sched = parse_ramp(case["_ramp"])[0]
            print("         -> %d channels, jmax3=%s"
                  % ((int(params["e3max"]) + 2) * 4, params.get("jmax3")))
            print("         -> %s" % ramp_schedule_text(sched))
            print("         -> Nmax values in use: %s"
                  % sorted({nmax_for_j(sched, j)
                            for j in range(1, int(params["jmax3"]) + 1, 2)},
                           reverse=True))
        written.append(cid)

    print()
    print("generated %d instance(s): %s" % (len(written), ", ".join(written)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
