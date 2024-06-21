# Lucid64
[![RISC-V Arch Tests](https://github.com/Peter-Herrmann/Lucid64-Verif/actions/workflows/build-ubuntu.yml/badge.svg)](https://github.com/Peter-Herrmann/Lucid64-Verif/actions/workflows/build-ubuntu.yml) [![Lint](https://github.com/Peter-Herrmann/Lucid64-Verif/actions/workflows/lint.yml/badge.svg)](https://github.com/Peter-Herrmann/Lucid64-Verif/actions/workflows/lint.yml) [![Synthesis](https://github.com/Peter-Herrmann/Lucid64-Verif/actions/workflows/synthesis.yml/badge.svg)](https://github.com/Peter-Herrmann/Lucid64-Verif/actions/workflows/synthesis.yml)

A 64-bit RISC-V core written with plain and simple Verilog. The core is a 5-stage, in-order RV64IMAC_Zicsr_Zifencei processor that prioritizes readability with minimal tool-specific knowledge (no exotic language features, code generation, excessive configurability).

## Verification

The verification for this core is in a seperate repository, [Lucid64-Verif](https://github.com/Peter-Herrmann/Lucid64-Verif). The badges above are associated with CI runs from that repository.

## Memory Interfaces

The instruction and data busses use a subset of the OBI interface, as defined below:

| Pin Name  | Pin Count | Direction               | Description                                                    |
|-----------|:---------:|-------------------------|----------------------------------------------------------------|
| req     | 1  | Controller -> Memory    | Asserted by the controller to request a memory transaction. The controller is responsible to keep all address signals valid while req is high.     |
| gnt     | 1  | Memory -> Controller    | Asserted by the memory system when new transactions can be accepted. A transaction is accepted on the rising edge of the clock if req and gnt are both high.   |
| addr    | 32 | Controller -> Memory    | Address output from the controller to access memory location   |
| we      | 1  | Controller -> Memory    | Asserted by the controller to indicate a write operation         |
| be      | 4  | Controller -> Memory    | Byte enable output (strobe), to specify which bytes should be accessed  |
| wdata   | 32 | Controller -> Memory    | Write data output from the controller to be written to memory  |
| rvalid  | 1  | Memory -> Controller    | Asserted by the memory system to signal valid read data. The read response is completed on the first rising clock edge when rvalid is asserted. rdata must be valid as long as rvalid is high.       |
| rdata   | 32 | Memory -> Controller    | Read data input to the controller from the memory system       |
