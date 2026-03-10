import sys

def parse_hex_file(filename, expected_bytes):
    result = bytearray()
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip().lower()
            if line.startswith("0x"):
                line = line[2:]
            if len(line) != 8:
                continue
            word = int(line, 16)
            result += word.to_bytes(4, byteorder='little')
    return result.ljust(expected_bytes, b'\x00')[:expected_bytes]

def write_hex_file(data_bytes, filename):
    with open(filename, 'w') as f:
        for i in range(0, len(data_bytes), 4):
            word = int.from_bytes(data_bytes[i:i+4], byteorder='little')
            f.write(f"{word:08x}\n")

# === Parse args ===
if len(sys.argv) != 5:
    print("Usage: python3 merge_sections.py <inst_in> <data_in> <inst_out> <data_out>")
    sys.exit(1)

inst_input  = sys.argv[1]
data_input  = sys.argv[2]
inst_out    = sys.argv[3]
data_out    = sys.argv[4]

# Constants
DATA_SIZE      = 16 * 1024
TEXT_TOTAL     = 32 * 1024
TEXT_HALF_SIZE = 16 * 1024

# Parse input files
data_bytes = parse_hex_file(data_input, DATA_SIZE)
text_bytes = parse_hex_file(inst_input, TEXT_TOTAL)

# Split and combine
text_low  = text_bytes[:TEXT_HALF_SIZE]
text_high = text_bytes[TEXT_HALF_SIZE:]
inst_mem  = data_bytes + text_low
data_mem  = text_high

# Write outputs
write_hex_file(inst_mem, inst_out)
write_hex_file(data_mem, data_out)
