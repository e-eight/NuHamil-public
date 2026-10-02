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
        if "ramp" in case:
            m.ramp_space = case["ramp"]
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

    sys.exit("unknown case kind: %r (case %s)" % (kind, case["id"]))


def derived(case, params, kind):
    """Extra cost/expectation metadata recorded in the manifest."""
    d = {}
    if kind == "namelist3":
        e3max = int(params["e3max"])
        d["n_channels"] = (e3max + 2) * 4
        d["jmax3"] = params.get("jmax3")
        d["ramp"] = params.get("ramp")
        d["lab_3bme_precision"] = params.get("lab_3bme_precision", "single")
    if kind == "namelist2":
        d["emax"] = params.get("emax")
        d["e2max"] = params.get("e2max")
    return d


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cases", nargs="*", default=None,
                    help="case ids to generate (default: all non-production)")
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

    cases = cfg["cases"]
    by_id = {c["id"]: c for c in cases}

    if args.list:
        print("%-24s %-11s %-10s %s" % ("ID", "TIER", "KIND", "DESCRIPTION"))
        for c in cases:
            print("%-24s %-11s %-10s %s"
                  % (c["id"], c["tier"], c["kind"],
                     " ".join(c["description"].split())[:80]))
        return 0

    if args.cases:
        unknown = [c for c in args.cases if c not in by_id]
        if unknown:
            sys.exit("unknown case id(s): %s" % ", ".join(unknown))
        selected = [by_id[c] for c in args.cases]
    else:
        selected = [c for c in cases
                    if args.include_production or c["tier"] != "production"]

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
    print()

    written = []
    for case in selected:
        params, base, expected = build_case(case, cfg, nn_dir, mods)
        kind = case["kind"]
        cdir = runs / case["id"]
        cdir.mkdir(parents=True, exist_ok=True)
        input_name = "Input_" + base + ".dat"
        input_path = cdir / input_name

        if input_path.exists() and not args.force:
            action = "kept"
        else:
            input_path.write_text(namelist_text(params))
            action = "wrote"

        manifest = {
            "case": case["id"],
            "tier": case["tier"],
            "kind": kind,
            "description": " ".join(case["description"].split()),
            "generated_by": "bench/gen_cases.py",
            "repo": str(REPO),
            "repo_commit": commit,
            "input_file": input_name,
            "script_base": base,
            "expected_output": expected,
            "expected_output_used": case.get("expected_output", expected),
            "reference": case.get("reference", {}),
            "params": dict(params),
            "derived": derived(case, params, kind),
            "nn_input_file": params.get("input_nn_file"),
        }
        (cdir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

        nn_ref = params.get("input_nn_file")
        nn_ok = bool(nn_ref) and Path(nn_ref).exists()
        print("[%-6s] %-24s %s" % (action, case["id"], input_name))
        if nn_ref and not nn_ok:
            print("         WARNING: referenced NN file does not exist: %s" % nn_ref)
        if expected:
            print("         -> output: %s" % expected)
        if kind == "namelist3":
            print("         -> %d channels, jmax3=%s"
                  % ((int(params["e3max"]) + 2) * 4, params.get("jmax3")))
        written.append(case["id"])

    print()
    print("generated %d case(s): %s" % (len(written), ", ".join(written)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
