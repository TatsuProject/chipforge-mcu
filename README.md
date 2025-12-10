# ChipForge SN84 — RISC-V MCU

A RISC-V microcontroller core designed through decentralized competition on
[Bittensor Subnet 84 (ChipForge)](https://chipforge.ai). Miners compete to design
and optimize the processor, evaluated on functionality, performance, area, and power.

The core implements **RV32IMC** with scalar cryptography extensions
(**Zkne**, **Zknd**, **Zknh**, **Zbkb**, **Zbkc**, **Zbkx**, **Zbb**), targeting
low-power edge AI applications.

## Architecture

- **ISA**: RV32IMC_Zkne_Zknd_Zknh_Zbkb_Zbkc_Zbkx_Zbb
- **Pipeline**: Multi-stage in-order with hazard detection and forwarding
- **Top module**: `rv32imc_top`
- **HDL**: SystemVerilog

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

## Project Structure

```
rtl/                        # Processor core RTL
  rv32imc_top.sv            # Top-level module (SoC interface)
  rv32imc.sv                # Core wrapper
  data_path.sv              # Datapath (fetch, decode, execute, memory, writeback)
  control_unit.sv           # Main control unit
  decode_control.sv         # Instruction decoder
  alu.sv                    # ALU with Zbb support
  alu_control.sv            # ALU operation selection
  mul_unit.sv               # M-extension multiplier
  div_unit.sv               # M-extension divider
  decompressor.sv           # C-extension 16-bit to 32-bit expansion
  csr_file.sv               # Control and status registers
  reg_file.sv               # Register file
  imm_gen.sv                # Immediate generator
  lsu.sv                    # Load/store unit
  mem_controller.sv         # Memory controller
  mem_aligner.sv            # Memory alignment logic
  branch_controller.sv      # Branch prediction/resolution
  forwarding_unit.sv        # Data hazard forwarding
  hazard_controller.sv      # Pipeline hazard detection
  pipeline_controller.sv    # Pipeline flow control
  exception_encoder.sv      # Exception handling
  iadu.sv                   # Instruction address decode unit
  alignment_units.sv        # Address alignment
  core_dbg_fsm.sv           # Debug FSM
  reset_sync.sv             # Reset synchronizer
  lib.sv                    # Shared types and definitions
  common_pkg.sv             # Common package
  debug_pkg.sv              # Debug package
  riscv_types.vh            # RISC-V type definitions
  rv32i.sdc                 # Timing constraints
  crypto/                   # Scalar cryptography units
    aes_unit.sv             # AES encrypt/decrypt (Zkne/Zknd)
    crypto_unit.sv          # Crypto top-level mux
    crypto_bitmanip_lib_optimized.sv  # Bit-manipulation for crypto (Zbkb/Zbkc/Zbkx)
rtl.f                       # File list for synthesis and simulation
```

## Design History

This core was iteratively designed across five ChipForge challenges:

| Challenge | Date | Milestone |
|-----------|------|-----------|
| 005 | Nov 2024 | RV32I — base integer core |
| 007 | Nov 2024 | RV32IMC — added M-extension, compressed instructions, and crypto |
| 008 | Nov 2024 | Full scalar crypto — Zkne, Zknd, Zknh, Zbkb, Zbkc, Zbkx, Zbb |
| 009 | Dec 2024 | Performance and area optimization (baseline score 81 -> target >= 82) |
| 010 | Dec 2024 | Power optimization for edge AI (new power-aware scoring model) |

### Evaluation Criteria

Designs are scored on a weighted combination of:
- **Functionality** (50%) — must be 100% correct or design is disqualified
- **Performance** (25% / 17%) — clock cycles to complete test suite
- **Area** (25% / 17%) — gate count after synthesis
- **Power** (0% / 17%) — introduced in Challenge 010 after top designs hit ~202mW

## Roadmap

- [ ] RTOS support
- [ ] RISC-V debug module (dm spec 0.13)
- [ ] Peripheral subsystem (UART, SPI, I2C, GPIO, timer)
- [ ] Dual-core configuration

## License

TBD
