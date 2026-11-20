# **Microchip Libero SoC Master Automation Pipeline**
=============================================================================

This infrastructure provides a modular, production-ready command-line orchestration pipeline for Microchip FPGAs (**SmartFusion2**, **RTG4**, and **PolarFire**). It automates the entire flow from project instantiation, hardware synthesis, placement, routing, and constraint management to high-performance native behavioral simulation using ModelSim / QuestaSim Pro.

## **Directory Schema Layout**

The automation script expects a clean separation of design source spaces and internal compilation workspaces:

```text
├── src/
│   ├── hdl/                <-- All parallel Verilog design modules (*.v)
│   ├── stimulus/           <-- Behavioral Testbenches (*.v) and Parameters (*.vh, *.h)
│   ├── constraints/
│   │   └── <target_family>/
│   │       ├── io/         <-- Physical I/O Pin Placement Constraints (top_io.pdc)
│   │       ├── fp/         <-- Floorplan Constraints (top_fp.pdc)
│   │       └── sdc/        <-- Structural User Timing Constraints (top.SDC)
│   └── tcl/
│       └── <target_family>/ <-- Target-specific IP component and peripheral configs
└── build/                  <-- Auto-generated output matrix space (Purged on clean runs)
    └── <target_family>/
        └── top/            <-- Libero Project Root Database Space (top.prjx)
```

---

## **v5: PolarFire Multi-Burst AXI4-MM DMA & Interconnect Test Design** (Latest)
*November 20, 2026*

This design ports the AXI4 Full Master verification platform to **Microchip PolarFire (`MPF300T-1FCG1152E`)** at **100 MHz**, upgrades `axi4_master_if` and `ram_dual_port` to support **multi-burst transfers up to 512 KB** (with 4 KB boundary splitting), and verifies both **64-bit native** and **32-bit width-converted** AXI4 LSRAM slaves through `COREAXI4INTERCONNECT_C0`.

### **1. Architecture Overview**

```text
+---------------------------------------------------------------------------------------------------+
|                                          top (PolarFire MPF300T)                                  |
|                                                                                                   |
|  REF_CLK (50 MHz) ──► [PF_CCC_C0] ──► CLK_100 (100 MHz)                                           |
|                            │                                                                      |
|  reset_n ──► [AND2_0] ◄────┴── PLL_LOCK_0                                                         |
|                 │                                                                                 |
|                 ▼                                                                                 |
|       [reset_synchronizer_1] ──► reset_sync (Active-Low System Reset)                             |
|                                                                                                   |
|  Host / TB Ports                                                                                  |
|   ├── ram_a_addr[15:0] ──► +-------------------+      +------------------+                        |
|   ├── ram_a_wdata[63:0]──► |  ram_dual_port_0  |      |  axi4_master_if  |                        |
|   ├── ram_a_we ──────────► | (512 KB True DPRAM|◄────►|  (Multi-Burst    |                        |
|   └── ram_a_rdata[63:0]◄── |  65,536 x 64-bit) |Port B|   AXI4 Master)   |                        |
|                            +-------------------+      +--------+---------+                        |
|                                                                │ AXI4_Master (64-bit)             |
|                                                                ▼                                  |
|                                                  +---------------------------+                    |
|                                                  |  COREAXI4INTERCONNECT_C0  |                    |
|                                                  |  (1M x 2S, Reg Slices ON) |                    |
|                                                  +------+-------------+------+                    |
|                                                         │             │                           |
|                              Slave 0 (64-bit, 512 KB)   │             │ Slave 1 (32-bit, 512 KB)  |
|                            0x6000_0000 - 0x7FFF_FFFF    │             │ 0x8000_0000 - 0x8FFF_FFFF |
|                                                         ▼             ▼                           |
|                                               +--------------+  +--------------+                  |
|                                               | PF_SRAM_AHBL |  | PF_SRAM_AHBL |                  |
|                                               |   _AXI_C0    |  |   _AXI_C1    |                  |
|                                               +--------------+  +--------------+                  |
+---------------------------------------------------------------------------------------------------+
```

### **2. Execution Steps & Expected Outputs**

**Step 1: Clean Project Build & Console Simulation**
Creates a fresh Libero project, generates the PolarFire PLL and AXI4 IPs, compiles the RTL, and runs the multi-burst regression sweeps headless in the terminal.

```bash
python3 build.py --family polarfire --sim --tb_top tb_top_axi4 --sim_time 10ms --console --clean
```

*Expected Output:*
```text
[INFO] Clean switch active. Purging previous target matrix structures...
[INFO] Launching Libero SoC Database Engine for POLARFIRE...
Info: 'COREAXI4INTERCONNECT_C0' was successfully generated.
Info: 'PF_CCC_C0' was successfully generated.
...
[INFO] Restructuring macro profile 'run.do' for optimized interactive run (10ms)...
[INFO] Handing off control to ModelSim Live Console Shell environment...

# =========================================================
#    LAUNCHING MULTI-BURST AXI4 MEMORY REGRESSION SWEEPS   
# =========================================================
# [STATUS] Waiting for PF_CCC PLL lock and synchronized reset release...
# [STATUS] PLL locked and system reset released! Starting sweeps.
# 
# ---------------------------------------------------------
#  PHASE 1: SLAVE 0 (64-BIT) SINGLE & MULTI-BURST SWEEPS   
# ---------------------------------------------------------
# [MATRIX SWEEP] Addr: 0x60001000 | Words: 1 (8 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x60001000 | Data: 0xc001a00100000000
#   [PASS] All 1 words (8 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x60002400 | Words: 4 (32 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x60002400 | Data: 0xbeef000400000000
#   [MATCH] Word     1 | AXI Addr: 0x60002408 | Data: 0xbeef000400000001
#   [MATCH] Word     2 | AXI Addr: 0x60002410 | Data: 0xbeef000400000002
#   [MATCH] Word     3 | AXI Addr: 0x60002418 | Data: 0xbeef000400000003
#   [PASS] All 4 words (32 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x60003000 | Words: 13 (104 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x60003000 | Data: 0x7777d11100000000
#   [MATCH] Word     1 | AXI Addr: 0x60003008 | Data: 0x7777d11100000001
#   [MATCH] Word     2 | AXI Addr: 0x60003010 | Data: 0x7777d11100000002
#   [MATCH] Word     3 | AXI Addr: 0x60003018 | Data: 0x7777d11100000003
#   [MATCH] Word     4 | AXI Addr: 0x60003020 | Data: 0x7777d11100000004
#   [MATCH] Word     5 | AXI Addr: 0x60003028 | Data: 0x7777d11100000005
#   [MATCH] Word     6 | AXI Addr: 0x60003030 | Data: 0x7777d11100000006
#   [MATCH] Word     7 | AXI Addr: 0x60003038 | Data: 0x7777d11100000007
#   [MATCH] Word     8 | AXI Addr: 0x60003040 | Data: 0x7777d11100000008
#   [MATCH] Word     9 | AXI Addr: 0x60003048 | Data: 0x7777d11100000009
#   [MATCH] Word    10 | AXI Addr: 0x60003050 | Data: 0x7777d1110000000a
#   [MATCH] Word    11 | AXI Addr: 0x60003058 | Data: 0x7777d1110000000b
#   [MATCH] Word    12 | AXI Addr: 0x60003060 | Data: 0x7777d1110000000c
#   [PASS] All 13 words (104 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x60004500 | Words: 64 (512 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x60004500 | Data: 0xdead006400000000
#   [MATCH] Word     1 | AXI Addr: 0x60004508 | Data: 0xdead006400000001
#   [MATCH] Word     2 | AXI Addr: 0x60004510 | Data: 0xdead006400000002
#   [MATCH] Word    61 | AXI Addr: 0x600046e8 | Data: 0xdead00640000003d
#   [MATCH] Word    62 | AXI Addr: 0x600046f0 | Data: 0xdead00640000003e
#   [MATCH] Word    63 | AXI Addr: 0x600046f8 | Data: 0xdead00640000003f
#   [PASS] All 64 words (512 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x60000000 | Words: 256 (2048 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x60000000 | Data: 0x5555025600000000
#   [MATCH] Word     1 | AXI Addr: 0x60000008 | Data: 0x5555025600000001
#   [MATCH] Word     2 | AXI Addr: 0x60000010 | Data: 0x5555025600000002
#   [MATCH] Word   253 | AXI Addr: 0x600007e8 | Data: 0x55550256000000fd
#   [MATCH] Word   254 | AXI Addr: 0x600007f0 | Data: 0x55550256000000fe
#   [MATCH] Word   255 | AXI Addr: 0x600007f8 | Data: 0x55550256000000ff
#   [PASS] All 256 words (2048 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x60000000 | Words: 512 (4096 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x60000000 | Data: 0x4b00051200000000
#   [MATCH] Word     1 | AXI Addr: 0x60000008 | Data: 0x4b00051200000001
#   [MATCH] Word     2 | AXI Addr: 0x60000010 | Data: 0x4b00051200000002
#   [MATCH] Word   509 | AXI Addr: 0x60000fe8 | Data: 0x4b000512000001fd
#   [MATCH] Word   510 | AXI Addr: 0x60000ff0 | Data: 0x4b000512000001fe
#   [MATCH] Word   511 | AXI Addr: 0x60000ff8 | Data: 0x4b000512000001ff
#   [PASS] All 512 words (4096 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x60000e00 | Words: 600 (4800 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x60000e00 | Data: 0xb0d0060000000000
#   [MATCH] Word     1 | AXI Addr: 0x60000e08 | Data: 0xb0d0060000000001
#   [MATCH] Word     2 | AXI Addr: 0x60000e10 | Data: 0xb0d0060000000002
#   [MATCH] Word   597 | AXI Addr: 0x600020a8 | Data: 0xb0d0060000000255
#   [MATCH] Word   598 | AXI Addr: 0x600020b0 | Data: 0xb0d0060000000256
#   [MATCH] Word   599 | AXI Addr: 0x600020b8 | Data: 0xb0d0060000000257
#   [PASS] All 600 words (4800 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x60000000 | Words: 4096 (32768 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x60000000 | Data: 0x320b409600000000
#   [MATCH] Word     1 | AXI Addr: 0x60000008 | Data: 0x320b409600000001
#   [MATCH] Word     2 | AXI Addr: 0x60000010 | Data: 0x320b409600000002
#   [MATCH] Word  4093 | AXI Addr: 0x60007fe8 | Data: 0x320b409600000ffd
#   [MATCH] Word  4094 | AXI Addr: 0x60007ff0 | Data: 0x320b409600000ffe
#   [MATCH] Word  4095 | AXI Addr: 0x60007ff8 | Data: 0x320b409600000fff
#   [PASS] All 4096 words (32768 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x60000000 | Words: 12800 (102400 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x60000000 | Data: 0x100cc80000000000
#   [MATCH] Word     1 | AXI Addr: 0x60000008 | Data: 0x100cc80000000001
#   [MATCH] Word     2 | AXI Addr: 0x60000010 | Data: 0x100cc80000000002
#   [MATCH] Word 12797 | AXI Addr: 0x60018fe8 | Data: 0x100cc800000031fd
#   [MATCH] Word 12798 | AXI Addr: 0x60018ff0 | Data: 0x100cc800000031fe
#   [MATCH] Word 12799 | AXI Addr: 0x60018ff8 | Data: 0x100cc800000031ff
#   [PASS] All 12800 words (102400 Bytes) verified cleanly.
# 
# ---------------------------------------------------------
#  PHASE 2: SLAVE 1 (32-BIT DWC) SINGLE & MULTI-BURST SWEEPS
# ---------------------------------------------------------
# [MATRIX SWEEP] Addr: 0x80000000 | Words: 1 (8 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x80000000 | Data: 0xc002b00200000000
#   [PASS] All 1 words (8 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x80001000 | Words: 8 (64 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x80001000 | Data: 0xa5a5000800000000
#   [MATCH] Word     1 | AXI Addr: 0x80001008 | Data: 0xa5a5000800000001
#   [MATCH] Word     2 | AXI Addr: 0x80001010 | Data: 0xa5a5000800000002
#   [MATCH] Word     3 | AXI Addr: 0x80001018 | Data: 0xa5a5000800000003
#   [MATCH] Word     4 | AXI Addr: 0x80001020 | Data: 0xa5a5000800000004
#   [MATCH] Word     5 | AXI Addr: 0x80001028 | Data: 0xa5a5000800000005
#   [MATCH] Word     6 | AXI Addr: 0x80001030 | Data: 0xa5a5000800000006
#   [MATCH] Word     7 | AXI Addr: 0x80001038 | Data: 0xa5a5000800000007
#   [PASS] All 8 words (64 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x80004200 | Words: 32 (256 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x80004200 | Data: 0xb4b4003200000000
#   [MATCH] Word     1 | AXI Addr: 0x80004208 | Data: 0xb4b4003200000001
#   [MATCH] Word     2 | AXI Addr: 0x80004210 | Data: 0xb4b4003200000002
#   [MATCH] Word    29 | AXI Addr: 0x800042e8 | Data: 0xb4b400320000001d
#   [MATCH] Word    30 | AXI Addr: 0x800042f0 | Data: 0xb4b400320000001e
#   [MATCH] Word    31 | AXI Addr: 0x800042f8 | Data: 0xb4b400320000001f
#   [PASS] All 32 words (256 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x80008000 | Words: 127 (1016 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x80008000 | Data: 0xecec012700000000
#   [MATCH] Word     1 | AXI Addr: 0x80008008 | Data: 0xecec012700000001
#   [MATCH] Word     2 | AXI Addr: 0x80008010 | Data: 0xecec012700000002
#   [MATCH] Word   124 | AXI Addr: 0x800083e0 | Data: 0xecec01270000007c
#   [MATCH] Word   125 | AXI Addr: 0x800083e8 | Data: 0xecec01270000007d
#   [MATCH] Word   126 | AXI Addr: 0x800083f0 | Data: 0xecec01270000007e
#   [PASS] All 127 words (1016 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x8000a000 | Words: 256 (2048 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x8000a000 | Data: 0x9999025600000000
#   [MATCH] Word     1 | AXI Addr: 0x8000a008 | Data: 0x9999025600000001
#   [MATCH] Word     2 | AXI Addr: 0x8000a010 | Data: 0x9999025600000002
#   [MATCH] Word   253 | AXI Addr: 0x8000a7e8 | Data: 0x99990256000000fd
#   [MATCH] Word   254 | AXI Addr: 0x8000a7f0 | Data: 0x99990256000000fe
#   [MATCH] Word   255 | AXI Addr: 0x8000a7f8 | Data: 0x99990256000000ff
#   [PASS] All 256 words (2048 Bytes) verified cleanly.
# 
# [MATRIX SWEEP] Addr: 0x80000000 | Words: 1024 (8192 Bytes)
#   [MATCH] Word     0 | AXI Addr: 0x80000000 | Data: 0x8b00102400000000
#   [MATCH] Word     1 | AXI Addr: 0x80000008 | Data: 0x8b00102400000001
#   [MATCH] Word     2 | AXI Addr: 0x80000010 | Data: 0x8b00102400000002
#   [MATCH] Word  1021 | AXI Addr: 0x80001fe8 | Data: 0x8b001024000003fd
#   [MATCH] Word  1022 | AXI Addr: 0x80001ff0 | Data: 0x8b001024000003fe
#   [MATCH] Word  1023 | AXI Addr: 0x80001ff8 | Data: 0x8b001024000003ff
#   [PASS] All 1024 words (8192 Bytes) verified cleanly.
# 

```

**Step 2: Incremental Console Simulation**
Re-runs the simulation using the existing compiled project database, saving minutes of IP regeneration time. Useful when you only change Verilog code.

```bash
python3 build.py --family polarfire --sim --tb_top tb_top_axi4 --sim_time 10ms --console
```

*Expected Output:*
```text
[INFO] Existing database asset verified at: ./build/polarfire/top/top.prjx
[INFO] Bypassing design initialization. Launching in INCREMENTAL compilation mode.
[INFO] Launching Libero SoC Database Engine for POLARFIRE...
...
# ** Note: (vsim-8009) Loading existing optimized design _opt
# Loading work.tb_top_axi4(fast)
...
=========================================================
   ALL MULTI-BURST (UP TO 200 KB) SWEEPS PASSED!         
=========================================================
```

**Step 3: Interactive GUI Simulation (Waveform Debugging)**
Launches the full QuestaSim/ModelSim Graphical User Interface. 

```bash
python3 build.py --family polarfire --sim --tb_top tb_top_axi4 --sim_time 10ms --gui
```

*Expected Output:*
```text
[INFO] Existing database asset verified at: ./build/polarfire/top/top.prjx
[INFO] Restructuring macro profile 'run.do' for optimized interactive run (10ms)...
[INFO] Handing off control to ModelSim Graphic Interface Layout...
```
*(The simulator GUI will open. It will automatically compile, run for 10ms, and print the sweep results to the GUI Transcript. When the testbench hits `$finish`, a prompt will ask "Are you sure you want to finish?" Click **No** to keep the GUI open and inspect your AXI4 waveforms.)*

> **Hardware `--build` Note:** Synthesis (`SYNTHESIZE`) passes cleanly out of the box. Before running `--build` (Place & Route) on PolarFire, ensure `src/tcl/polarfire/constraints/io/top_io.pdc` and `fp/top_fp.pdc` contain only constraints for ports/macros present in `top.v` (remove any leftover `UART_*` or `RV32_SYS_0/PF_DDR3_C0_0` constraints from previous RTG4 reference designs).

---

## **v4: RTG4 DDR3 Test Design with East and West DDR Memory**
*July 10, 2026*

This demo design has two DDR3 controllers, for west DDR3 and east DDR3. The AXILSRAM memory is removed. The same memory map is used for the simulation.

**Usage Examples:**
* Create a clean project and simulate:
  `python3 build.py --family rtg4 --sim --tb_top tb_top_axi_ddr3 --sim_time 1ms --console --clean`
* Simulate an existing project:
  `python3 build.py --family rtg4 --sim --tb_top tb_top_axi_ddr3 --sim_time 1ms --console`
* Simulate in GUI mode:
  `python3 build.py --family rtg4 --sim --tb_top tb_top_axi_ddr3 --sim_time 1ms --gui`

---

## **v3: RTG4 DDR3 Test Design**
*July 8, 2026*

This design has an RTG4 DDR Controller with a DDR3 memory model. AXI4Interconnect is used. Along with the DDR3 controller, another AXILSRAM is used as a slave. 

The testbench is provided for verification of read/write into the DDR and LSRAM. Use the updated `build.py` to generate the design and run.

---

## **Core Automation Mechanics**

### **1. Self-Healing Constraint Engine**
Designs without complex IP hard blocks (e.g., custom pure RTL configurations) often do not generate Netlist Design Constraints (.ndc) or derived .sdc files via `derive_constraints_sdc`.

The pipeline uses a native Tcl file-inspection layer (`file exists`) to dynamically verify whether derived constraints were written to disk before running the tool mapping sequences. It only binds elements to **Synthesis**, **Place and Route**, and **Timing Verification** if they actually exist, eliminating crash-on-launch behaviors.

### **2. Incremental Workspace Optimization**
To save time during iterative development, the tool avoids creating projects from scratch on every run.
* **Incremental Mode (Default):** If an existing `top.prjx` database file is detected, the script issues an `open_project` command, refreshes changed HDL and stimulus files, and immediately starts compiling or simulating.  
* **Clean Mode:** Passing the `--clean` flag bypasses database reuse, erases previous folder trees, and rebuilds all primitives from scratch.

### **3. Automated Interactive Macro Cleansing**
When generating simulation assets, Libero writes a batch regression script (`run.do`) that ends with a structural `exit`/`quit` command and performs an immediate initialization check via `run 0ns`.

When running interactive simulations, this batch layout will crash graphical views or immediately exit terminal windows. This tool uses an automated regex macro parser that edits the file right before launching the simulator to:
* **Comment out** all `exit`, `quit`, and `run 0ns` statements.  
* **Scrub** wildcard log statements (e.g., `log /tb_top_axi/*`) that trigger structural crashes in newer versions of QuestaSim. 
* **Strip** 32-bit PLI flags (e.g., `-pli ...pf_crypto_lin_me_pli.so`) so 64-bit ModelSim/QuestaSim launches without `ELFCLASS32` failures.
* **Inject** your custom `--sim_time` parameters directly into the end of the script execution queue.

## **Command Line Interface (CLI) Reference**

### **Command Arguments Matrix**

| Argument | Requirement | Default | Description |
| :---- | :---- | :---- | :---- |
| `--family` | **Required** | *None* | Selects target architecture family: `smartfusion2`, `rtg4`, or `polarfire`. |
| `--sim_time` | Optional | `1000ns` | Simulation runtime limit window (e.g., `20ms`, `500us`, `all`). |
| `--tb_top` | Optional | `testbench` | Name identifier matching your top-level testbench module block. |
| `--libero_path` | Optional | `libero` | Absolute path or systemic pointer command to the Libero SoC binary. |
| `--modelsim_path` | Optional | `vsim` | Absolute path or systemic pointer command to Questa/ModelSim vsim. |
| `--design_tcl` | Optional | *None* | Explicitly targets a single IP component script inside `src/tcl/`. |
| `--clean` | Optional | *False* | Purges previous project workspaces completely and forces a full rebuild. |

### **Mutually Exclusive Processing Modes**

**Note:** You can only pass one processing mode command parameter flag per execution block.

* `--build`: Compiles layout logic, maps constraints, runs synthesis and place-and-route, and exports programming bitstream job files (.job). *(Default configuration mode)*  
* `--program`: Executes a full `--build` processing pass, then interfaces with local hardware links via FlashPro to program the target silicon.  
* `--sim`: Pre-compiles hardware IPs and testbenches natively within Libero, then transitions into the chosen presentation layer.

## **Troubleshooting & Self-Healing Diagnostics**

If a background simulation run fails during headless continuous integration passes, the execution wrapper includes an automatic **Self-Diagnostic Log Dumper**.

Instead of showing a generic exit code, the script automatically parses the internal compilation directories, locates `testbench_presynth_simulation.log`, and dumps the compiler or elaboration trace directly into the terminal stream. This helps you quickly diagnose syntax issues or missing parameters.