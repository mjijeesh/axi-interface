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

=========================================================
   LAUNCHING MULTI-BURST AXI4 MEMORY REGRESSION SWEEPS   
=========================================================
[STATUS] Waiting for PF_CCC PLL lock and synchronized reset release...
[STATUS] PLL locked and system reset released! Starting sweeps.

---------------------------------------------------------
 PHASE 1: SLAVE 0 (64-BIT) SINGLE & MULTI-BURST SWEEPS   
---------------------------------------------------------
[MATRIX SWEEP] Addr: 0x60000000 | Words: 256 (2048 Bytes)
  [MATCH] Word 00000 | AXI Addr: 0x60000000 | Data: 0x5555025600000000
  [PASS] All 256 words (2048 Bytes) verified cleanly.
...
[MATRIX SWEEP] Addr: 0x60000000 | Words: 12800 (102400 Bytes)
  [PASS] All 12800 words (102400 Bytes) verified cleanly.
...
=========================================================
   ALL MULTI-BURST (UP TO 200 KB) SWEEPS PASSED!         
=========================================================
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