#!/usr/bin/env python3
"""summarise_repeat.py

Summarise a CSV emitted by ``run_L2_repeat10.sh`` or ``run_L3_repeat10.sh``.

The expected columns are::

    rep,wall_seconds,max_rss_kb,exit_code,verdict,steps,sources_steps,warnings

The script prints run count, verdict multiset, proof-step multiset,
source-saturation multiset, warning multiset, and the mean / median /
standard deviation / min / max of wall time (seconds) and peak resident
set size (converted to MiB).

Usage::

    python3 scripts/summarise_repeat.py results/clean_release/L2_L3/L2_repeat10.csv
"""

from __future__ import annotations

import argparse
import csv
import statistics
import sys
from collections import Counter
from pathlib import Path


def summarise(csv_path: Path) -> int:
    with csv_path.open() as fp:
        rows = list(csv.DictReader(fp))

    if not rows:
        print(f"error: no rows in {csv_path}", file=sys.stderr)
        return 2

    wall = [float(r["wall_seconds"]) for r in rows]
    rss_kb = [int(r["max_rss_kb"]) for r in rows]
    rss_mib = [x / 1024.0 for x in rss_kb]

    verdicts = Counter(r["verdict"] for r in rows)
    steps = Counter(r["steps"] for r in rows)
    sources = Counter(r["sources_steps"] for r in rows)
    warnings = Counter(r["warnings"] for r in rows)
    exit_codes = Counter(r["exit_code"] for r in rows)

    n = len(rows)
    print(f"file:            {csv_path}")
    print(f"runs:            {n}")
    print(f"verdicts:        {dict(verdicts)}")
    print(f"steps:           {dict(steps)}")
    print(f"sources_steps:   {dict(sources)}")
    print(f"warnings:        {dict(warnings)}")
    print(f"exit_codes:      {dict(exit_codes)}")

    def summary(label: str, xs: list[float], unit: str) -> None:
        print(f"{label:15s}"
              f" mean={statistics.mean(xs):10.3f}{unit}"
              f" median={statistics.median(xs):10.3f}{unit}"
              f" stdev={statistics.stdev(xs) if n > 1 else 0.0:8.3f}{unit}"
              f" min={min(xs):10.3f}{unit}"
              f" max={max(xs):10.3f}{unit}")

    summary("wall_seconds:", wall, "s")
    summary("peak_rss_mib:", rss_mib, "MiB")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path, help="CSV file to summarise")
    args = parser.parse_args()
    return summarise(args.csv)


if __name__ == "__main__":
    sys.exit(main())
