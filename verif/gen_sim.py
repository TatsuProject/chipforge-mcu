#!/usr/bin/env python3
"""
gen_sim.py - Compile the Verilator simulation binary.

Passes REPO_ROOT to the Makefile, which uses:
  -I$(REPO_ROOT) -f $(REPO_ROOT)/rtl.f -f tb_files.f

Only recompiles if RTL or testbench sources have changed (incremental build).
Use --clean to force a full rebuild.
"""

import argparse
import subprocess
import sys
from pathlib import Path


def find_repo_root(start: Path) -> Path | None:
    """Walk up from start until we find rtl.f."""
    candidate = start
    for _ in range(10):
        candidate = candidate.parent
        if (candidate / "rtl.f").exists():
            return candidate
    return None


def build_sim(verif_dir: Path, repo_root: Path, clean: bool = False) -> Path:
    """Run 'make build_verilator_sim REPO_ROOT=...' in verif_dir."""
    sim_bin = verif_dir / "obj_dir" / "Vtb_top"

    if clean:
        print("[gen_sim] Cleaning previous build...")
        subprocess.run(["make", "clean"], cwd=verif_dir, capture_output=True)

    print("[gen_sim] Building Verilator simulation...")
    result = subprocess.run(
        ["make", "build_verilator_sim", f"REPO_ROOT={repo_root}"],
        cwd=verif_dir,
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr)
        sys.exit(f"[gen_sim] ERROR: Verilator build failed (rc={result.returncode})")

    if not sim_bin.exists():
        sys.exit(f"[gen_sim] ERROR: Simulator binary not found at {sim_bin}")

    print(f"[gen_sim] Build successful: {sim_bin}")
    return sim_bin


def main():
    parser = argparse.ArgumentParser(description="Compile Verilator simulation")
    parser.add_argument("--repo-root", type=str, default=None,
                        help="Path to MCU repo root (default: auto-detect)")
    parser.add_argument("--clean", action="store_true",
                        help="Clean before building (force full rebuild)")
    args = parser.parse_args()

    this_dir = Path(__file__).resolve().parent
    if args.repo_root:
        repo_root = Path(args.repo_root).resolve()
    else:
        repo_root = find_repo_root(this_dir)
        if repo_root is None:
            sys.exit("ERROR: Could not find rtl.f in any parent directory. "
                     "Use --repo-root to specify the MCU repo root.")

    rtl_f = repo_root / "rtl.f"
    if not rtl_f.exists():
        sys.exit(f"ERROR: rtl.f not found at {rtl_f}")

    print(f"[gen_sim] Repo root : {repo_root}")
    print(f"[gen_sim] Verif dir : {this_dir}")
    print(f"[gen_sim] RTL file  : {rtl_f}")

    sim_bin = build_sim(this_dir, repo_root, clean=args.clean)
    return sim_bin


if __name__ == "__main__":
    main()
