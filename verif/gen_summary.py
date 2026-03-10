#!/usr/bin/env python3
"""
gen_summary.py - Generate the regression summary from diff logs.

Wraps the existing scripts/regression_summary.py logic. Can be called
standalone or from run_all.py.

Usage:
    python3 gen_summary.py --results-dir results/2026-03-10
    python3 gen_summary.py   # auto-detect latest results dir
"""

import argparse
import subprocess
import sys
from pathlib import Path


def find_latest_results(base_dir: Path) -> Path | None:
    """Find the most recently modified results/<date> directory."""
    if not base_dir.exists():
        return None
    candidates = [d for d in base_dir.iterdir() if d.is_dir()]
    if not candidates:
        return None
    return max(candidates, key=lambda d: d.stat().st_mtime)


def main():
    parser = argparse.ArgumentParser(description="Generate regression summary")
    parser.add_argument("--results-dir", type=str, default=None,
                        help="Path to results directory (default: auto-detect latest)")
    args = parser.parse_args()

    this_dir = Path(__file__).resolve().parent
    scripts_dir = this_dir / "scripts"
    summary_script = scripts_dir / "regression_summary.py"

    if not summary_script.exists():
        sys.exit(f"ERROR: regression_summary.py not found at {summary_script}")

    if args.results_dir:
        results_dir = Path(args.results_dir).resolve()
    else:
        results_dir = find_latest_results(this_dir / "results")
        if results_dir is None:
            sys.exit("ERROR: No results directory found. Run run_regression.py first.")

    if not results_dir.is_dir():
        sys.exit(f"ERROR: Results directory does not exist: {results_dir}")

    # Check that there are diff logs to summarize
    diff_logs = list(results_dir.rglob("diff_*.log"))
    if not diff_logs:
        sys.exit(f"ERROR: No diff_*.log files found in {results_dir}")

    print(f"[gen_summary] Results dir  : {results_dir}")
    print(f"[gen_summary] Diff logs    : {len(diff_logs)}")
    print()

    # Run the existing regression_summary.py
    result = subprocess.run(
        [sys.executable, str(summary_script), str(results_dir)],
        capture_output=False, text=True
    )

    if result.returncode != 0:
        sys.exit(f"[gen_summary] ERROR: regression_summary.py failed (rc={result.returncode})")

    # Check outputs
    summary_csv = results_dir / "regression_summary.csv"
    summary_json = results_dir / "regression_summary.json"

    print()
    if summary_csv.exists():
        print(f"[gen_summary] CSV  : {summary_csv}")
    if summary_json.exists():
        print(f"[gen_summary] JSON : {summary_json}")

    return str(summary_csv)


if __name__ == "__main__":
    main()
