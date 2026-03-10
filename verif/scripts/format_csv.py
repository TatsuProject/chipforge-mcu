import sys

def find_prev_pc_before_ecall(spike_csv):
    """Find the PC of the line before where 'ecall' instruction occurs."""
    last_pc = None
    with open(spike_csv, 'r') as f:
        for line in f:
            fields = line.strip().split(',')
            # Check all fields for 'ecall'
            for field in fields:
                if 'ecall' in field.strip().lower():
                    if last_pc:
                        print(f"[INFO] ecall found. Using previous PC: {last_pc}")
                        return last_pc
                    else:
                        print("[ERROR] ecall found at the very first line. No previous PC!")
                        return None
            if len(fields) >= 1:
                last_pc = fields[0].strip()  # Save PC for next round
    print("[ERROR] No 'ecall' found in spike CSV!")
    return None

def truncate_core_csv(core_csv, output_csv, stop_pc):
    """Write lines from core CSV up to (and including) the stop_pc."""
    with open(core_csv, 'r') as f_in, open(output_csv, 'w') as f_out:
        for line in f_in:
            fields = line.strip().split(',')
            if len(fields) >= 1:
                pc = fields[0].strip()
                f_out.write(line)
                if pc.lower() == stop_pc.lower():
                    print(f"[INFO] Stopped writing at PC: {pc}")
                    break

def main():
    if len(sys.argv) != 4:
        print("Usage: python3 script.py <spike_csv> <core_csv> <output_csv>")
        sys.exit(1)

    spike_csv = sys.argv[1]
    core_csv = sys.argv[2]
    output_csv = sys.argv[3]

    stop_pc = find_prev_pc_before_ecall(spike_csv)
    if stop_pc:
        truncate_core_csv(core_csv, output_csv, stop_pc)
        print(f"[SUCCESS] Truncated file written to: {output_csv}")
    else:
        print("[ERROR] Could not find PC before ecall. No output generated.")

if __name__ == "__main__":
    main()
