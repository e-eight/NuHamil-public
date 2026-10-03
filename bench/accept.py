#!/usr/bin/env python3
"""Numeric acceptance test for NuHamil output products.

Why this exists
---------------
``.me3j`` products are ASCII text and are **not bit-reproducible across
configurations**. The same binary run as 32 ranks x 1 thread and as 8 ranks x 4
threads differs in ~3% of bytes, because threading reorders summations; a
different build differs again. Hashing the ``.gz`` therefore is not a correctness
test -- it flags every legitimate configuration change as a failure.

Measured noise floor (rampsmall e3max6, single precision), which sets the default
tolerances below:

    same binary, threads differ (8x4 vs 32x1)   max |abs| 8.4e-07
    different build vs golden                   max |abs| 1.6e-06
    single-worker configs (2x16, 1x32)          max |abs| 5.2e-06

So the worst deviation seen so far is 5.2e-06, and the default atol of 1e-4 leaves
a ~19x margin.  The single-worker configurations deviate ~3x more than the
many-worker ones -- the same reordered-summation effect, more visible because one
rank accumulates all 32 channels sequentially.  If a future configuration exceeds
the margin, raise atol deliberately and record why; do not go back to hashing.

What this does instead
----------------------
Parses the numbers, compares **element by element** against a reference, and
passes only when every element satisfies

    |a - b| <= atol + rtol * |b|

Elementwise rather than aggregate on purpose: one badly wrong matrix element must
fail the run even if the overall maximum is dominated by noise elsewhere. The
atol term carries the weight, because this data contains many near-zero elements
whose *relative* differences are meaningless -- a column of 1e-8 values can differ
by 100% and still mean nothing, while an absolute error of 1e-3 anywhere is fatal.

Usage
-----
    bench/accept.py REFERENCE CANDIDATE [--atol X] [--rtol Y] [--quiet]

REFERENCE and CANDIDATE may each be a ``.me3j``, a ``.me3j.gz``, or a directory
containing exactly one of either.
"""

import argparse
import gzip
import io
import os
import re
import sys

# Defaults: ~60x the worst deviation observed against a different build, so a
# legitimate rebuild or reconfiguration passes, while any real regression (which
# perturbs matrix elements far more than 1e-4) fails.
DEFAULT_ATOL = 1.0e-4
DEFAULT_RTOL = 1.0e-4

_NUM = re.compile(r"^[-+]?(?:\d+\.?\d*|\.\d+)(?:[eEdD][-+]?\d+)?$")


def _is_number(tok):
    return bool(_NUM.match(tok))


def _open_text(path):
    if path.endswith(".gz"):
        return io.TextIOWrapper(gzip.open(path, "rb"), encoding="ascii", errors="replace")
    return open(path, "r", encoding="ascii", errors="replace")


def resolve(path):
    """Accept a file or a directory containing exactly one product."""
    if os.path.isdir(path):
        cands = sorted(
            os.path.join(path, f)
            for f in os.listdir(path)
            if f.endswith(".me3j") or f.endswith(".me3j.gz")
        )
        if len(cands) != 1:
            raise SystemExit("expected exactly one .me3j(.gz) in %s, found %d" % (path, len(cands)))
        return cands[0]
    if not os.path.exists(path):
        raise SystemExit("no such file or directory: %s" % path)
    return path


def load(path):
    """Return (values, header). Lines that are not purely numeric are skipped."""
    values = []
    header = None
    with _open_text(path) as fh:
        for line in fh:
            toks = line.split()
            if not toks:
                continue
            if all(_is_number(t) for t in toks):
                values.extend(float(t.replace("d", "e").replace("D", "E")) for t in toks)
            elif header is None:
                header = line.rstrip("\n")
    return values, header


def compare(ref, cand, atol=DEFAULT_ATOL, rtol=DEFAULT_RTOL):
    if len(ref) != len(cand):
        return {"count_mismatch": (len(ref), len(cand))}

    nbad = 0
    maxabs = 0.0
    maxabs_at = -1
    worst_bad = None
    scale = 0.0
    for i, (b, a) in enumerate(zip(ref, cand)):
        ab = abs(a - b)
        if ab > maxabs:
            maxabs, maxabs_at = ab, i
        if ab > scale:
            scale = ab
        if ab > atol + rtol * abs(b):
            nbad += 1
            if worst_bad is None or ab > worst_bad[2]:
                worst_bad = (i, b, ab)
    return {
        "n": len(ref),
        "nbad": nbad,
        "maxabs": maxabs,
        "maxabs_at": maxabs_at,
        "ref_at": ref[maxabs_at] if maxabs_at >= 0 else 0.0,
        "cand_at": cand[maxabs_at] if maxabs_at >= 0 else 0.0,
        "worst_bad": worst_bad,
        "max_abs_value": max(abs(v) for v in ref) if ref else 0.0,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description="numeric acceptance test for .me3j products")
    ap.add_argument("reference")
    ap.add_argument("candidate")
    ap.add_argument("--atol", type=float, default=DEFAULT_ATOL)
    ap.add_argument("--rtol", type=float, default=DEFAULT_RTOL)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    ref_path, cand_path = resolve(args.reference), resolve(args.candidate)
    ref, ref_hdr = load(ref_path)
    cand, cand_hdr = load(cand_path)
    res = compare(ref, cand, args.atol, args.rtol)

    if "count_mismatch" in res:
        r, c = res["count_mismatch"]
        print("FAIL: element count differs: reference %d, candidate %d" % (r, c), file=sys.stderr)
        return 1

    ok = res["nbad"] == 0
    if not args.quiet:
        print("reference : %s" % ref_path)
        print("candidate : %s" % cand_path)
        if ref_hdr:
            print("ref  prov : %s" % ref_hdr)
        if cand_hdr:
            print("cand prov : %s" % cand_hdr)
        print("elements  : %d" % res["n"])
        print("tolerance : |a-b| <= %.1e + %.1e*|b|" % (args.atol, args.rtol))
        print("max |diff|: %.6e  at element %d  (%.10g vs %.10g)"
              % (res["maxabs"], res["maxabs_at"], res["ref_at"], res["cand_at"]))
        print("  as a fraction of the largest element (%.6g): %.3e"
              % (res["max_abs_value"],
                 res["maxabs"] / res["max_abs_value"] if res["max_abs_value"] else 0.0))
        if ok:
            print("elements over tolerance: 0")
        else:
            i, b, ab = res["worst_bad"]
            print("elements over tolerance: %d of %d" % (res["nbad"], res["n"]))
            print("  worst: element %d, reference %.10g, |diff| %.6e" % (i, b, ab))
        print("verdict   : %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
