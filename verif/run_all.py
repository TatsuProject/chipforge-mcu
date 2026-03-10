#!/usr/bin/env python3
"""
run_all.py - Complete verification flow for the RV32IMC processor.

This is the single entry-point that anyone can run to verify the design:

    cd verif
    python3 run_all.py

Steps:
  1. gen_sim    - Compile the Verilator simulation (rtl.f + tb_files.f -> binary)
  2. regression - Run all pre-generated tests against the simulation
  3. summary    - Generate regression summary (CSV + JSON)

Options:
  --tests      Run only specific test suites
  --iter       Override iteration count per test
  --skip-build Skip compilation if binary already exists
  --sim-timeout  Per-simulation timeout in seconds (default: 120)
"""

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


def run_step(name: str, cmd: list[str], cwd: Path) -> int:
    """Run a step, streaming output to terminal. Returns exit code."""
    print(f"\n{'='*60}")
    print(f"  STEP: {name}")
    print(f"{'='*60}\n")

    result = subprocess.run(cmd, cwd=cwd)
    return result.returncode


def main():
    parser = argparse.ArgumentParser(
        description="Complete RV32IMC verification flow",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 run_all.py                          # Full run (all tests, 100 iterations each)
  python3 run_all.py --tests riscv_aes_test   # Single test suite
  python3 run_all.py --iter 5                 # Quick smoke test (5 iterations)
  python3 run_all.py --skip-build             # Skip compilation
        """
    )
    parser.add_argument("--tests", nargs="*", default=None,
                        help="Test suites to run (default: all)")
    parser.add_argument("--iter", type=int, default=None,
                        help="Iterations per test (default: all available)")
    parser.add_argument("--skip-build", action="store_true",
                        help="Skip Verilator compilation if binary exists")
    parser.add_argument("--sim-timeout", type=int, default=120,
                        help="Per-simulation timeout in seconds (default: 120)")
    parser.add_argument("--repo-root", type=str, default=None,
                        help="MCU repo root (default: auto-detect)")
    args = parser.parse_args()

    this_dir = Path(__file__).resolve().parent
    sim_bin = this_dir / "obj_dir" / "Vtb_top"
    t0 = time.time()

    date_tag = datetime.now().strftime("%Y-%m-%d")

    # ── Step 1: Compile ──────────────────────────────────────────
    if args.skip_build and sim_bin.exists():
        print(f"\n[run_all] Skipping build (--skip-build), binary: {sim_bin}")
    else:
        gen_sim_cmd = [sys.executable, str(this_dir / "gen_sim.py")]
        if args.repo_root:
            gen_sim_cmd += ["--repo-root", args.repo_root]

        rc = run_step("Compile Verilator Simulation", gen_sim_cmd, cwd=this_dir)
        if rc != 0:
            print("\n[run_all] FAILED at compilation step.")
            sys.exit(1)

    # ── Step 2: Run regression ───────────────────────────────────
    reg_cmd = [
        sys.executable, str(this_dir / "run_regression.py"),
        "--date-tag", date_tag,
        "--sim-timeout", str(args.sim_timeout),
    ]
    if args.tests:
        reg_cmd += ["--tests"] + args.tests
    if args.iter is not None:
        reg_cmd += ["--iter", str(args.iter)]

    rc = run_step("Run Regression Tests", reg_cmd, cwd=this_dir)
    if rc != 0:
        print("\n[run_all] FAILED at regression step.")
        sys.exit(1)

    # ── Step 3: Generate summary ─────────────────────────────────
    results_dir = this_dir / "results" / date_tag
    summary_cmd = [
        sys.executable, str(this_dir / "gen_summary.py"),
        "--results-dir", str(results_dir),
    ]

    rc = run_step("Generate Summary", summary_cmd, cwd=this_dir)
    if rc != 0:
        print("\n[run_all] FAILED at summary step.")
        sys.exit(1)

    # ── Final report ─────────────────────────────────────────────
    elapsed = time.time() - t0
    summary_json = results_dir / "regression_summary.json"

    print(f"\n{'='*60}")
    print(f"  VERIFICATION COMPLETE")
    print(f"{'='*60}")
    print(f"  Elapsed time : {elapsed:.1f}s ({elapsed/60:.1f}m)")
    print(f"  Results      : {results_dir}")

    if summary_json.exists():
        with open(summary_json) as f:
            data = json.load(f)
        score = data.get("functionality_score", 0)
        ipc = data.get("ipc", 0)
        total = data.get("total_instr", 0)
        passed = data.get("total_instr_passed", 0)
        failed = data.get("total_instr_failed", 0)

        print(f"\n  Total Instructions  : {total}")
        print(f"  Instructions Passed : {passed}")
        print(f"  Instructions Failed : {failed}")
        print(f"  Functionality Score : {score:.6f}")
        print(f"  IPC                 : {ipc:.6f}")

        if failed == 0 and total > 0:
            print(f"\n  ALL INSTRUCTIONS MATCH - VERIFICATION PASSED")
        else:
            print(f"\n  MISMATCHES DETECTED - VERIFICATION FAILED")

    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
