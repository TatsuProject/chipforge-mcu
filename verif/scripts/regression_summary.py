#!/usr/bin/env python3
import os
import re
import pandas as pd
import sys
import json
from pathlib import Path

if len(sys.argv) != 2:
    print("Usage: python3 regression_summary.py <RESULTS_DIR>")
    sys.exit(1)

RESULTS_DIR = Path(sys.argv[1])
SUMMARY_CSV = RESULTS_DIR / "regression_summary.csv"

# Regexes
pass_pattern = re.compile(r"\[PASSED\]:\s*(\d+)\s*matched", re.IGNORECASE)
fail_pattern = re.compile(r"\[FAILED\]:\s*(\d+)\s*matched", re.IGNORECASE)

summary = []
total_instr_passed = 0
total_instr_failed = 0
total_cycles_for_passed = 0

for test_dir in RESULTS_DIR.iterdir():
    if not test_dir.is_dir():
        continue
    test_name = test_dir.name

    for diff_file in test_dir.glob("diff_*.log"):
        iteration = diff_file.stem.split("_")[1] if "_" in diff_file.stem else "0"

        # Corresponding spike trace CSV
        spike_csv = test_dir / f"spike_trace_{iteration}.csv"
        total_instructions = 0
        if spike_csv.exists():
            with open(spike_csv) as f:
                total_instructions = sum(1 for _ in f)

        # Corresponding core log (to extract cycle count)
        core_log = test_dir / f"core_trace_{iteration}.log"
        last_cycle = None
        if core_log.exists():
            with open(core_log) as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 2 and parts[1].isdigit():
                        last_cycle = int(parts[1])  # 2nd col = Cycle
        if last_cycle is None:
            last_cycle = 0

        status = "UNKNOWN"
        instr_passed = 0
        instr_failed = 0

        with open(diff_file, "r") as f:
            log = f.read()

            m_pass = pass_pattern.search(log)
            m_fail = fail_pattern.search(log)

            if m_pass and total_instructions > 0:
                status = "PASSED"
                instr_passed = total_instructions
                instr_failed = 0
                total_cycles_for_passed += last_cycle  # only add cycles if test passed

            elif m_fail and total_instructions > 0:
                status = "FAILED"
                matched = int(m_fail.group(1))
                instr_passed = matched
                instr_failed = total_instructions - matched

        total_instr_passed += instr_passed
        total_instr_failed += instr_failed

        summary.append({
            "Test": test_name,
            "Iteration": iteration,
            "Status": status,
            "Instr_Passed": instr_passed,
            "Instr_Failed": instr_failed,
            "Total_Instr": total_instructions,
            "Cycles": last_cycle,
            "Log File": diff_file.name
        })

# Save CSV
df = pd.DataFrame(summary)
if not df.empty:
    df.sort_values(by=["Test", "Iteration"], inplace=True)
df.to_csv(SUMMARY_CSV, index=False)

# Totals
total_instr = total_instr_passed + total_instr_failed
func_score = total_instr_passed / total_instr if total_instr > 0 else 0.0
ipc = (total_instr_passed / total_cycles_for_passed) if total_cycles_for_passed > 0 else 0.0

# Print summary
print("\n📋 Regression Summary:\n")
if not df.empty:
    print(df.to_string(index=False))
else:
    print("No diff_*.log files found!")

print("\n==============================")
print(f" Total Instructions Passed : {total_instr_passed}")
print(f" Total Instructions Failed : {total_instr_failed}")
print(f" Total Instructions        : {total_instr}")
print(f" Total Cycles (passed)     : {total_cycles_for_passed}")
print("==============================")

print(f"\n Final Functionality Score : {func_score:.6f}")
print(f" IPC (Instr per Cycle)     : {ipc:.6f}")

if total_instr_failed == 0 and total_instr > 0:
    print("\n✅✅✅ ALL INSTRUCTIONS MATCH ✅✅✅\n")
else:
    print("\n❌❌❌ SOME INSTRUCTIONS MISMATCH ❌❌❌\n")

# JSON output
json_summary = {
    "total_instr_passed": total_instr_passed,
    "total_instr_failed": total_instr_failed,
    "total_instr": total_instr,
    "total_cycles_passed": total_cycles_for_passed,
    "functionality_score": func_score,
    "ipc": ipc
}
with open(RESULTS_DIR / "regression_summary.json", "w") as jf:
    json.dump(json_summary, jf, indent=2)
