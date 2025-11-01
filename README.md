# ChipForge SN84 — MCU Design Challenges

Decentralized chip design on Bittensor Subnet 84. Miners compete to design and optimize
RISC-V processor cores evaluated on functionality, performance, area, and power.

## Challenge Progression

| Challenge | Date | ISA | Description |
|-----------|------|-----|-------------|
| 005 | Nov 2024 | RV32I | Base integer RISC-V core (PicoRV32-based) |
| 007 | Nov 2024 | RV32IMC_Zkne_Zknd_Zknh_Zbkb_Zbkc_Zbkx_Zbb | Compressed, M-ext, crypto + bit-manip extensions |
| 008 | Nov 2024 | RV32IMC_Zkne_Zknd_Zknh_Zbkb_Zbkc_Zbkx_Zbb | Full crypto: AES, SHA-256, bit-manipulation for crypto |
| 009 | Dec 2024 | RV32IMC_Zkne_Zknd_Zknh_Zbkb_Zbkc_Zbkx_Zbb | Optimize performance and area (target score >= 82) |
| 010 | Dec 2024 | RV32IMC_Zkne_Zknd_Zknh_Zbkb_Zbkc_Zbkx_Zbb | Optimize for real edge AI — power-aware scoring |

## Scoring

- **Functionality**: Must be 100% correct (disqualified otherwise)
- **Performance**: Clock cycles to execute test suite
- **Area**: Gate count after synthesis
- **Power**: Introduced in Challenge 010 (~202mW baseline was too high for edge AI)

## Top Module

`rv32imc_top` — consistent interface across all challenges (from Challenge 007 onward).

## Structure

```
rtl/           # Processor RTL (SystemVerilog)
rtl/crypto/    # AES (Zkne/Zknd), SHA-256 (Zknh), bit-manipulation (Zbkb/Zbkc/Zbkx)
rtl/pqc/       # Post-quantum cryptography (Montgomery multiplier)
rtl.f          # File list for synthesis/simulation
```
