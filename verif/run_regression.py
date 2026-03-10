#!/usr/bin/env python3
"""
run_regression.py - Run pre-generated tests against the Verilator simulation.

For each test suite and each iteration:
  1. Copy imem_N.mem and dmem_N.mem into the sim directory
  2. Run the simulator binary (obj_dir/Vtb_top)
  3. Save the core trace log
  4. Convert core trace log to CSV (core_log_to_trace_csv.py)
  5. Copy spike reference CSV
  6. Compare core CSV vs spike CSV (instr_trace_compare.py)

All results go into results/<date>/<test_name>/.
"""

import argparse
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path


# Default test suites and iteration count (matches Regression.mk)
DEFAULT_TESTS = [
    "riscv_arithmetic_basic_test",
    "riscv_mmu_stress_test",
    "riscv_loop_test",
    "riscv_crypto_test",
    "riscv_aes_test",
    "riscv_sha_test",
    "riscv_bitmanip_test",
]
DEFAULT_ITER = 100

# Trace log produced by the tracer module
TRACE_LOG_NAME = "trace_core_00000001.log"


def discover_tests(tests_dir: Path) -> list[str]:
    """Return sorted list of test directories that exist."""
    if not tests_dir.is_dir():
        sys.exit(f"ERROR: Tests directory not found: {tests_dir}")
    return sorted(d.name for d in tests_dir.iterdir() if d.is_dir())


def discover_iterations(test_dir: Path) -> int:
    """Count how many imem_N.mem files exist in a test directory."""
    return sum(1 for f in test_dir.glob("imem_*.mem"))


def run_single_test(sim_bin: Path, verif_dir: Path, tests_dir: Path,
                    out_dir: Path, scripts_dir: Path,
                    test_name: str, iteration: int,
                    sim_timeout: int) -> bool:
    """Run a single test iteration. Returns True on success."""
    test_src = tests_dir / test_name
    test_out = out_dir / test_name
    test_out.mkdir(parents=True, exist_ok=True)

    imem_src = test_src / f"imem_{iteration}.mem"
    dmem_src = test_src / f"dmem_{iteration}.mem"

    if not imem_src.exists():
        print(f"  SKIP {test_name} iter {iteration}: imem_{iteration}.mem not found")
        return False

    # 1. Copy memory files to sim directory
    shutil.copy2(imem_src, verif_dir / "imem.mem")
    if dmem_src.exists():
        shutil.copy2(dmem_src, verif_dir / "dmem.mem")

    # 2. Run simulation
    sim_log = test_out / f"verilator_{iteration}.log"
    try:
        result = subprocess.run(
            [str(sim_bin)],
            cwd=str(verif_dir),
            capture_output=True, text=True,
            timeout=sim_timeout
        )
        sim_log.write_text(result.stdout + result.stderr)
    except subprocess.TimeoutExpired:
        sim_log.write_text(f"TIMEOUT after {sim_timeout}s\n")
        print(f"  TIMEOUT {test_name} iter {iteration}")
        return False

    # 3. Copy trace log
    trace_src = verif_dir / TRACE_LOG_NAME
    core_trace_log = test_out / f"core_trace_{iteration}.log"
    if not trace_src.exists():
        print(f"  ERROR {test_name} iter {iteration}: {TRACE_LOG_NAME} not generated")
        return False
    shutil.copy2(trace_src, core_trace_log)

    # 4. Convert core trace log to CSV
    core_trace_csv = test_out / f"core_trace_{iteration}.csv"
    csv_result = subprocess.run(
        [sys.executable,
         str(scripts_dir / "core_log_to_trace_csv.py"),
         "--log", str(core_trace_log),
         "--csv", str(core_trace_csv)],
        capture_output=True, text=True
    )
    if csv_result.returncode != 0:
        print(f"  ERROR {test_name} iter {iteration}: trace-to-csv failed")
        print(f"    {csv_result.stderr.strip()}")
        return False

    # 5. Copy spike reference CSV
    spike_src = test_src / f"spike_trace_{iteration}.csv"
    spike_dst = test_out / f"spike_trace_{iteration}.csv"
    if spike_src.exists():
        shutil.copy2(spike_src, spike_dst)
    else:
        print(f"  WARN {test_name} iter {iteration}: spike_trace_{iteration}.csv not found")
        return False

    # 6. Compare traces
    diff_log = test_out / f"diff_{iteration}.log"
    cmp_result = subprocess.run(
        [sys.executable,
         str(scripts_dir / "instr_trace_compare.py"),
         "--csv_file_1", str(spike_dst),
         "--csv_file_2", str(core_trace_csv),
         "--csv_name_1", "spike",
         "--csv_name_2", "core",
         "--log", str(diff_log)],
        capture_output=True, text=True
    )
    if cmp_result.returncode != 0:
        print(f"  ERROR {test_name} iter {iteration}: compare failed")
        print(f"    {cmp_result.stderr.strip()}")
        return False

    return True


def main():
    parser = argparse.ArgumentParser(description="Run regression tests")
    parser.add_argument("--tests", nargs="*", default=None,
                        help="Test names to run (default: all discovered tests)")
    parser.add_argument("--iter", type=int, default=None,
                        help="Number of iterations per test (default: auto-detect)")
    parser.add_argument("--date-tag", type=str, default=None,
                        help="Date tag for results dir (default: today)")
    parser.add_argument("--sim-timeout", type=int, default=120,
                        help="Timeout per simulation in seconds (default: 120)")
    parser.add_argument("--verif-dir", type=str, default=None,
                        help="Path to verilator verif dir (default: auto-detect)")
    args = parser.parse_args()

    # Auto-detect paths
    this_dir = Path(__file__).resolve().parent
    verif_dir = Path(args.verif_dir).resolve() if args.verif_dir else this_dir
    tests_dir = verif_dir / "tests"
    scripts_dir = verif_dir / "scripts"
    sim_bin = verif_dir / "obj_dir" / "Vtb_top"

    if not sim_bin.exists():
        sys.exit(f"ERROR: Simulator binary not found at {sim_bin}\n"
                 f"       Run gen_sim.py first to compile.")

    # Results directory
    date_tag = args.date_tag or datetime.now().strftime("%Y-%m-%d")
    out_dir = verif_dir / "results" / date_tag
    out_dir.mkdir(parents=True, exist_ok=True)

    # Discover or use specified tests
    available_tests = discover_tests(tests_dir)
    if args.tests:
        test_list = [t for t in args.tests if t in available_tests]
        missing = [t for t in args.tests if t not in available_tests]
        if missing:
            print(f"WARNING: Tests not found: {missing}")
    else:
        test_list = available_tests

    if not test_list:
        sys.exit("ERROR: No tests to run.")

    print(f"[run_regression] Results   : {out_dir}")
    print(f"[run_regression] Simulator : {sim_bin}")
    print(f"[run_regression] Tests     : {len(test_list)}")
    print()

    total_pass = 0
    total_fail = 0
    total_skip = 0

    for test_name in test_list:
        test_src = tests_dir / test_name
        n_iter = args.iter if args.iter is not None else discover_iterations(test_src)
        if n_iter == 0:
            print(f"[{test_name}] No iterations found, skipping.")
            continue

        print(f"[{test_name}] Running {n_iter} iterations...")
        pass_cnt = 0
        fail_cnt = 0

        for i in range(n_iter):
            ok = run_single_test(
                sim_bin, verif_dir, tests_dir, out_dir, scripts_dir,
                test_name, i, args.sim_timeout
            )
            if ok:
                pass_cnt += 1
            else:
                fail_cnt += 1

            # Progress indicator every 10 iterations
            done = i + 1
            if done % 10 == 0 or done == n_iter:
                print(f"  [{test_name}] {done}/{n_iter} done")

        total_pass += pass_cnt
        total_fail += fail_cnt
        print(f"  [{test_name}] Completed: {pass_cnt} ok, {fail_cnt} errors\n")

    print("=" * 60)
    print(f"[run_regression] All tests complete.")
    print(f"  Iterations processed : {total_pass}")
    print(f"  Iterations with errors: {total_fail}")
    print(f"  Results directory     : {out_dir}")
    print("=" * 60)

    return str(out_dir)


if __name__ == "__main__":
    main()
