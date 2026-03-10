# ChipForge SN84 — RISC-V MCU

A RISC-V microcontroller core designed through decentralized competition on
[Bittensor Subnet 84 (ChipForge)](https://chipforge.io). Miners compete to design
and optimize the processor, evaluated on functionality, performance, area, and power.

The core implements **RV32IMC** with scalar cryptography extensions
(**Zkne**, **Zknd**, **Zknh**, **Zbkb**, **Zbkc**, **Zbkx**, **Zbb**), targeting
low-power edge AI applications.

---

## Quick Start

```bash
# Install Verilator (Ubuntu/Debian)
sudo apt-get install -y verilator make g++ python3 python3-pip
pip3 install pandas

# Run the full verification suite
cd verif
python3 run_all.py
```

That's it. The flow compiles the design, runs 700 tests, and reports a pass/fail
summary with functionality score and IPC.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| **Verilator** | 5.0+ | See [Installing Verilator](#installing-verilator) below |
| **Python 3** | 3.10+ | Comes pre-installed on most systems |
| **GNU Make** | 4.0+ | `sudo apt-get install make` |
| **g++** | 11+ | `sudo apt-get install g++` |
| **pandas** | any | `pip3 install pandas` |

> Verilator 5.0+ is required for the `--timing` flag. Check your version with
> `verilator --version`.

### Installing Verilator

**Ubuntu/Debian** (apt):
```bash
sudo apt-get install verilator
```

**From source** (recommended for latest version):
```bash
git clone https://github.com/verilator/verilator.git
cd verilator && git checkout stable
autoconf && ./configure && make -j$(nproc)
sudo make install
verilator --version   # should show 5.x+
```

**macOS** (Homebrew):
```bash
brew install verilator
```

---

## Verification

The repository includes a complete, standalone verification environment. All test
stimuli and Spike ISA simulator reference traces are pre-generated — no external
tools beyond Verilator are needed.

### How It Works

<p align="center">
  <img src="docs/verification_flow.svg" alt="Verification Flow Diagram" width="800"/>
</p>

The verification methodology compares the RTL execution trace against a
golden reference from the [Spike](https://github.com/riscv-software-src/riscv-isa-sim)
RISC-V ISA simulator:

1. **Compile** — Verilator compiles the RTL and testbench into a fast C++ simulation binary
2. **Simulate** — Each pre-generated test program (`.mem` files) is loaded and executed
3. **Trace** — An RVFI-based tracer captures every committed instruction and its GPR state changes
4. **Compare** — The core's execution trace is compared instruction-by-instruction against the Spike reference
5. **Report** — A summary is generated with pass/fail counts, functionality score, and IPC

### Running a Single Test

Start with one test suite to verify your setup:

```bash
cd verif
python3 run_all.py --tests riscv_arithmetic_basic_test --iter 1
```

This compiles the design, runs a single iteration of the arithmetic test suite,
and reports the result. You should see:

```
ALL INSTRUCTIONS MATCH - VERIFICATION PASSED
```

### Running a Smoke Test

Run all 7 test suites with 5 iterations each (quick sanity check):

```bash
python3 run_all.py --iter 5
```

### Running the Full Regression

Run the complete test suite — 7 suites, 100 iterations each, 700 total runs:

```bash
python3 run_all.py
```

This takes approximately 15–30 minutes depending on your machine.

### Selecting Specific Test Suites

Run one or more specific test suites:

```bash
# Single suite
python3 run_all.py --tests riscv_aes_test

# Multiple suites
python3 run_all.py --tests riscv_aes_test riscv_sha_test riscv_bitmanip_test

# Multiple suites with limited iterations
python3 run_all.py --tests riscv_crypto_test riscv_aes_test --iter 10
```

### Skipping Recompilation

If you've already compiled and just want to re-run tests:

```bash
python3 run_all.py --skip-build --tests riscv_loop_test
```

### All Options

```
python3 run_all.py [OPTIONS]

  --tests TEST [TEST ...]   Test suites to run (default: all 7)
  --iter N                  Iterations per suite (default: 100)
  --skip-build              Skip Verilator compilation
  --sim-timeout SECONDS     Per-simulation timeout (default: 120)
  --repo-root PATH          MCU repo root (default: auto-detect)
```

### Running Individual Steps

Each stage of the pipeline can be run independently:

```bash
python3 gen_sim.py            # Step 1: Compile RTL + testbench
python3 run_regression.py     # Step 2: Run tests and compare traces
python3 gen_summary.py        # Step 3: Generate summary from existing results
```

### Test Suites

| Suite | Description | Coverage |
|-------|-------------|----------|
| `riscv_arithmetic_basic_test` | Base integer arithmetic | ADD, SUB, SLT, shifts, logical ops |
| `riscv_mmu_stress_test` | Memory access patterns | Loads, stores, alignment, byte/half/word |
| `riscv_loop_test` | Control flow | Loops, branches, JAL/JALR |
| `riscv_crypto_test` | All scalar crypto | Combined Zk* extension coverage |
| `riscv_aes_test` | AES operations | `aes32esi`, `aes32esmi`, `aes32dsi`, `aes32dsmi` |
| `riscv_sha_test` | SHA-256 acceleration | `sha256sum0/1`, `sha256sig0/1` |
| `riscv_bitmanip_test` | Bit manipulation | `clmul`, `xperm`, `pack`, `brev8`, `zip`/`unzip` |

Each suite contains **100 randomized iterations**, for a total of **700 test runs**.

### Understanding the Output

Results are written to `verif/results/<date>/`:

```
verif/results/2026-03-10/
  regression_summary.csv              # Per-iteration pass/fail
  regression_summary.json             # Aggregated scores
  riscv_arithmetic_basic_test/
    verilator_0.log                   # Simulation stdout
    core_trace_0.log                  # Raw RVFI trace
    core_trace_0.csv                  # Parsed core trace
    spike_trace_0.csv                 # Spike reference trace
    diff_0.log                        # Instruction-by-instruction comparison
    ...
```

The JSON summary:
```json
{
  "total_instr_passed": 3761400,
  "total_instr_failed": 0,
  "functionality_score": 1.0,
  "ipc": 0.58
}
```

- **`functionality_score`**: Fraction of instructions that match Spike (must be `1.0` to pass)
- **`ipc`**: Instructions Per Cycle (performance metric)

---

## Architecture

| Property | Value |
|----------|-------|
| **ISA** | RV32IMC + Zkne + Zknd + Zknh + Zbkb + Zbkc + Zbkx + Zbb |
| **Pipeline** | Multi-stage in-order with hazard detection and forwarding |
| **Top module** | `rv32imc_top` |
| **HDL** | SystemVerilog |

### Supported Extensions

| Extension | Instructions |
|-----------|-------------|
| **I** | Base integer (RV32I) |
| **M** | Hardware multiply/divide (`mul`, `mulh`, `div`, `rem`, ...) |
| **C** | Compressed 16-bit instructions |
| **Zkne/Zknd** | AES encrypt/decrypt (`aes32esi`, `aes32esmi`, `aes32dsi`, `aes32dsmi`) |
| **Zknh** | SHA-256 acceleration (`sha256sum0`, `sha256sum1`, `sha256sig0`, `sha256sig1`) |
| **Zbkb** | Bit-manipulation for crypto (`pack`, `packh`, `brev8`, `zip`, `unzip`) |
| **Zbkc** | Carry-less multiply (`clmul`, `clmulh`) |
| **Zbkx** | Crossbar permutations (`xperm4`, `xperm8`) |
| **Zbb** | Basic bit-manipulation (`andn`, `orn`, `xnor`, `rol`, `ror`, `rev8`, ...) |

---

## Project Structure

```
rtl/                              # Processor RTL (SystemVerilog)
  rv32imc_top.sv                  # Top-level module
  rv32imc.sv                      # Core wrapper
  data_path.sv                    # Datapath (IF/ID/EX/MEM/WB)
  control_unit.sv                 # Main control unit
  decode_control.sv               # Instruction decoder
  alu.sv                          # ALU with Zbb support
  alu_control.sv                  # ALU operation selection
  mul_unit.sv                     # M-extension multiplier
  div_unit.sv                     # M-extension divider
  decompressor.sv                 # C-extension decompressor
  csr_file.sv                     # CSR file
  reg_file.sv                     # Register file (32x32)
  imm_gen.sv                      # Immediate generator
  lsu.sv                          # Load/store unit
  mem_controller.sv               # Memory controller
  branch_controller.sv            # Branch resolution
  forwarding_unit.sv              # Data hazard forwarding
  hazard_controller.sv            # Hazard detection
  pipeline_controller.sv          # Pipeline flow control
  exception_encoder.sv            # Exception handling
  iadu.sv                         # Instruction address decode
  alignment_units.sv              # Address alignment
  core_dbg_fsm.sv                 # Debug FSM
  lib.sv                          # Shared types and primitives
  riscv_types.vh                  # RISC-V type definitions
  crypto/                         # Scalar cryptography
    aes_unit.sv                   # AES (Zkne/Zknd)
    crypto_unit.sv                # Crypto top-level mux
    crypto_bitmanip_lib_optimized.sv  # Zbkb/Zbkc/Zbkx
rtl.f                             # RTL file list

verif/                            # Verification environment
  run_all.py                      # Single entry point
  gen_sim.py                      # Verilator compilation
  run_regression.py               # Test execution + trace comparison
  gen_summary.py                  # Results aggregation
  Makefile                        # Verilator build rules
  tb_top.sv                       # Testbench top module
  imem.sv / dmem.sv               # Memory models
  tracer.sv                       # RVFI execution tracer
  tests/                          # Pre-generated stimuli (7 suites x 100 iter)
  scripts/                        # Trace conversion and comparison
  results/                        # Output (generated at runtime)

docs/
  verification_flow.svg           # Verification flow diagram
```

---

## Design History

This core was iteratively designed across five ChipForge challenges:

| Challenge | Milestone |
|-----------|-----------|
| 005 | RV32I base integer core |
| 007 | Added M-extension, compressed instructions, and crypto |
| 008 | Full scalar crypto (Zkne, Zknd, Zknh, Zbkb, Zbkc, Zbkx, Zbb) |
| 009 | Performance and area optimization |
| 010 | Power-aware optimization for edge AI |

### Evaluation Criteria

Designs are scored on a weighted combination of:

- **Functionality** (50%) — must be 100% correct or the design is disqualified
- **Performance** (17-25%) — clock cycles to complete test suite
- **Area** (17-25%) — gate count after synthesis
- **Power** (0-17%) — introduced in Challenge 010

---

## Roadmap

### ISA Extensions

- [ ] **F** — Single-precision floating-point (`fadd.s`, `fsub.s`, `fmul.s`, `fdiv.s`, `fsqrt.s`, `fcvt`, `fmv`, IEEE 754 compliant)
- [ ] **Zicond** — Integer conditional operations (`czero.eqz`, `czero.nez` — branchless select, eliminates branch penalties)

### System & Software

- [ ] RISC-V Debug Module (dm spec 0.13) with JTAG TAP
- [ ] CLIC — Core-Local Interrupt Controller (preemptive, priority-based interrupts for RTOS)
- [ ] PMP — Physical Memory Protection (memory isolation for RTOS tasks)
- [ ] RTOS support (FreeRTOS / Zephyr BSP)

### Peripherals

- [ ] UART, SPI, I2C, GPIO
- [ ] Timer / watchdog (RISC-V mtime/mtimecmp compliant)
- [ ] DMA controller

### Verification

- [ ] Integrated test generation — run Spike + random program generator alongside RTL simulation in a single flow
- [ ] Formal verification for critical control paths (hazard detection, CSR access)
- [ ] Code coverage tracking (line, toggle, FSM)

### Architecture

- [ ] Dual-core configuration with shared memory

## License

TBD
