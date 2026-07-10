v4: RTG4  DDR3 test design with east and west DDR memroy

This demo design has two ddr3 controllers, for west ddr3 and east ddr3. 
the axilsram memory is removed.
Sam memory map is used for the simualtion.

usage examples:

### create a clean project and simulate

python3 build.py --family rtg4 --sim --tb_top tb_top_axi_ddr3 --sim_time 1ms --console --clean

** simulate an existing project 

python3 build.py --family rtg4 --sim --tb_top tb_top_axi_ddr3 --sim_time 1ms --console 

** simulate in gui mode 

python3 build.py --family rtg4 --sim --tb_top tb_top_axi_ddr3 --sim_time 1ms --gui

10th july 2026





## v3 : RTG4  DDR3 test design

This design has RTG4 DDR Controller with ddr3 memory model.
AXI4Interconnect is used .
along with the ddr3 controller, another axilsram is used as slave.

the testbench is provided for verification of read/write into the ddr and lsram.

use the updated build.py to generate the design and run.



8th july 2026

# **Microchip Libero SoC Master Automation Pipeline**

\=============================================================================

This infrastructure provides a modular, production-ready command-line orchestration pipeline for Microchip FPGAs (**SmartFusion2**, **RTG4**, and **PolarFire**). It automates the entire flow from project instantiation, hardware synthesis, placement, routing, and constraint management to high-performance native behavioral simulation using ModelSim / QuestaSim Pro.

## **Directory Schema Layout**

The automation script expects a clean separation of design source spaces and internal compilation workspaces:

Plaintext

```
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

## **Core Automation Mechanics**

### **1\. Self-Healing Constraint Engine**

Designs without complex IP hard blocks (e.g., custom pure RTL configurations) often do not generate Netlist Design Constraints (.ndc) or derived .sdc files via derive\_constraints\_sdc.

The pipeline uses a native Tcl file-inspection layer (file exists) to dynamically verify whether derived constraints were written to disk before running the tool mapping sequences. It only binds elements to **Synthesis**, **Place and Route**, and **Timing Verification** if they actually exist, eliminating crash-on-launch behaviors.

### **2\. Incremental Workspace Optimization**

To save time during iterative development, the tool avoids creating projects from scratch on every run.

* **Incremental Mode (Default):** If an existing top.prjx database file is detected, the script issues an open\_project command, refreshes changed HDL and stimulus files, and immediately starts compiling or simulating.  
* **Clean Mode:** Passing the \--clean flag bypasses database reuse, erases previous folder trees, and rebuilds all primitives from scratch.

### **3\. Automated Interactive Macro Cleansing**

When generating simulation assets, Libero writes a batch regression script (run.do) that ends with a structural exit/quit command and performs an immediate initialization check via run 0ns.

When running interactive simulations, this batch layout will crash graphical views or immediately exit terminal windows. This tool uses an automated regex macro parser that edits the file right before launching the simulator to:

* **Comment out** all exit, quit, and run 0ns statements.  
* **Scrub** wildcard log statements (e.g., log /tb\_top\_axi/\*) that trigger structural crashes in newer versions of QuestaSim.  
* **Inject** your custom \--sim\_time parameters directly into the end of the script execution queue.

## **Command Line Interface (CLI) Reference**

### **Command Arguments Matrix**

| Argument | Requirement | Default | Description |
| :---- | :---- | :---- | :---- |
| \--family | **Required** | *None* | Selects target architecture family: smartfusion2, rtg4, or polarfire. |
| \--sim\_time | Optional | 1000ns | Simulation runtime limit window (e.g., 20ms, 500us, 1500ns). |
| \--tb\_top | Optional | testbench | Name identifier matching your top-level testbench module block. |
| \--libero\_path | Optional | libero | Absolute path or systemic pointer command to the Libero SoC binary. |
| \--modelsim\_path | Optional | vsim | Absolute path or systemic pointer command to Questa/ModelSim vsim. |
| \--design\_tcl | Optional | *None* | Explicitly targets a single IP component script inside src/tcl/. |
| \--clean | Optional | *False* | Purges previous project workspaces completely and forces a full rebuild. |

### **Mutually Exclusive Processing Modes**

**Note:** You can only pass one processing mode command parameter flag per execution block.

* \--build: Compiles layout logic, maps constraints, runs synthesis and place-and-route, and exports programming bitstream job files (.job). *(Default configuration mode)*  
* \--program: Executes a full \--build processing pass, then interfaces with local hardware links via FlashPro to program the target silicon.  
* \--sim: Pre-compiles hardware IPs and testbenches natively within Libero, then transitions into the chosen presentation layer.

## **Production Execution Examples**

### **1\. Headless Hardware Synthesis & Bitstream Generation**

To run a clean, full hardware build for an RTG4 system database and output a production programming file:

Bash

```
python3 build.py --family rtg4 --build --clean
```

### **2\. Fast-Reuse Headless Simulation Run**

To run an incremental check on code modifications and print the simulation results directly back to your terminal console:

Bash

```
python3 build.py --family rtg4 --sim --tb_top tb_top_axi --sim_time 500us
```

### **3\. Interactive Graphical Debug Session (\--gui)**

To skip batch text outputs, open the full graphical layout of ModelSim/Questa, preserve wave views, and let the window stay open at your specified runtime checkpoint:

Bash

```
python3 build.py --family rtg4 --sim --tb_top tb_top_axi --sim_time 2000ns --gui
```

### **4\. Interactive Command-Line Debug Session (\--console)**

To run simulations directly inside your existing terminal shell window and drops you into a live, interactive command prompt (QuestaSim\>) to step through code manually:

Bash

```
python3 build.py --family rtg4 --sim --tb_top tb_top_axi --console
```

## **Troubleshooting & Self-Healing Diagnostics**

If a background simulation run fails during headless continuous integration passes, the execution wrapper includes an automatic **Self-Diagnostic Log Dumper**.

Instead of showing a generic exit code, the script automatically parses the internal compilation directories, locates testbench\_presynth\_simulation.log, and dumps the compiler or elaboration trace directly into the terminal stream. This helps you quickly diagnose syntax issues or missing parameters.









# **AXI4 Full Master Data Mover Engine**

## **Overview**

The `axi4_master_data_mover` is a high-performance, parameterizable DMA-style staging controller designed specifically for **Microchip SmartFusion2 and RTG4 Fabric Core Architectures**. It serves as an ultra-reliable memory bridge, facilitating rapid bidirectional data streams between an internal dual-port Staging Block RAM (Port B) and an external AXI4 Full System Bus.

Developed for the **RTG4/SmartFusion2 Serial to AXI Memory Staging System**, this core operates at a fabric clock frequency of **80 MHz**, streamlining memory layout access without the penalty of combinational lookahead logic bottlenecks.

## **Key Features**

* **Protocol Standard:** Fully compliant with AMBA AXI4 Full Master interface specifications.  
* **Optimized Pipeline:** Employs a pure sequential early address advancement FSM to cleanly absorb the 1-clock-cycle read latency inherent to synchronous Block RAM blocks.  
* **Burst Efficiency:** Automatically manages incrementing burst transfers up to 256 beats per transaction (`AxLEN = 0 to 255`).  
* **Static Bus Mapping:** Hardcoded for 64-bit data widths (`AxSIZE = 3'b011`), continuous full-byte lane strobes (`WSTRB = 8'hFF`), and standard type-01 incrementing bursts (`AxBURST = 2'b01`).

## **System Architecture & FSM Operation**

To avoid timing closure degradation on tight fabric layouts, this core relies entirely on a synchronous register pipeline. Because a standard Block RAM takes 1 cycle to output data after an address change, and `m_axi_wdata` takes a second cycle to update, the system utilizes a **2-stage register pipeline**. The Finite State Machine (FSM) safely manages this by pre-priming address indices one clock edge ahead of active handshakes:

```
                  +-----------------+      +-----------------+
  ram_b_addr ---> |  Block RAM Core | ---> |   m_axi_wdata   ---> AXI4 Bus
  (FSM Reg)       | (1-Cycle Delay) |      | (1-Cycle Delay) |    (WDATA Channel)
                  +-----------------+      +-----------------+
```

### **FSM State Machine States**

1. `STATE_IDLE`: Rests at an idle state, holding the memory read pointer locked at location `0`. Evaluates incoming `start_write` or `start_read` trigger pulses.  
2. `STATE_AW_STAGE`: Asserts `m_axi_awvalid` to request write transaction access. On a valid slave handshake, it sequentially steps `ram_b_addr` to index `1`.  
3. `STATE_W_PREFETCH`: Safely registers the stable contents of RAM location `0` directly into `m_axi_wdata`. Simultaneously advances the RAM address to index `2`.  
4. `STATE_W_BURST`: Streams sequential data bursts. Every valid `wready` and `wvalid` handshake shifts the underlying data array into the master output register while cleanly incrementing the memory pointer.  
5. `STATE_W_LAST`: Handles the final data handshake while asserting `m_axi_wlast`.  
6. `STATE_B_WAIT`: Pauses execution until the AXI slave interface returns a definitive `m_axi_bvalid` response write acknowledgment.  
7. `STATE_AR_STAGE`: Latches the read request properties onto the bus and prepares the internal write-enable signals.  
8. `STATE_R_BURST`: Accepts high-speed streams from the AXI Read Data lane, driving them straight into the Staging RAM.

## **Signal Port Interface Maps**

### **1\. Host Control & System Pins**

| Port Name | Direction | Width | Description |
| ----- | ----- | ----- | ----- |
| `clk` | Input | 1-bit | Fabric System Clock Line (80 MHz) |
| `rst_n` | Input | 1-bit | Active-Low Synchronous Reset |
| `start_write` | Input | 1-bit | Active-High pulse to trigger RAM-to-AXI Transfer |
| `start_read` | Input | 1-bit | Active-High pulse to trigger AXI-to-RAM Transfer |
| `base_address` | Input | 32-bit | Starting AXI Memory Destination/Source Block Address Pointer |
| `word_count` | Input | 16-bit | Total amount of 64-bit words to process per trigger execution |
| `mover_busy` | Output | 1-bit | Continuously asserted high throughout an active loop |
| `mover_done` | Output | 1-bit | 1-cycle Active-High pulse generated at completion |

### **2\. Internal Staging Block RAM Interface**

| Port Name | Direction | Width | Description |
| ----- | ----- | ----- | ----- |
| `ram_b_addr` | Output | 8-bit | Synchronous RAM Memory Location Address Pointer |
| `ram_b_we` | Output | 1-bit | RAM Write Enable control strobe line |
| `ram_b_wdata` | Output | 64-bit | Core Write Data routing pipeline map |
| `ram_b_rdata` | Input | 64-bit | Parallel Synchronous Input Read Data Lane |

### **3\. External AXI4 System Bus Interface**

| Channel | Port Name | Direction | Width | Standard Value / Notes |
| ----- | ----- | ----- | ----- | ----- |
| **AW** | `m_axi_awid` | Output | 8-bit | Tied to `8'h00` |
| **AW** | `m_axi_awaddr` | Output | 32-bit | Dynamically set via `base_address` |
| **AW** | `m_axi_awlen` | Output | 8-bit | Scaled to `word_count - 1` |
| **AW** | `m_axi_awsize` | Output | 3'b011 | Fixed 8-Bytes per beat width (64-bit) |
| **AW** | `m_axi_awburst` | Output | 2'b01 | Fixed Incrementing type |
| **AW** | `m_axi_awvalid` | Output | 1-bit | Managed via FSM engine |
| **AW** | `m_axi_awready` | Input | 1-bit | Provided by target AXI Slave |
| **W** | `m_axi_wdata` | Output | 64-bit | Pipelined data stream out |
| **W** | `m_axi_wstrb` | Output | 8-bit | Tied to `8'hFF` (Full Lane Strobes) |
| **W** | `m_axi_wlast` | Output | 1-bit | Asserted on final data transfer beat |
| **W** | `m_axi_wvalid` | Output | 1-bit | Managed via FSM engine |
| **W** | `m_axi_wready` | Input | 1-bit | Provided by target AXI Slave |
| **B** | `m_axi_bvalid` | Input | 1-bit | Slave response write indicator |
| **B** | `m_axi_bready` | Output | 1-bit | Tied to `1'b1` (Always Ready) |
| **AR** | `m_axi_araddr` | Output | 32-bit | Dynamically set via `base_address` |
| **AR** | `m_axi_arlen` | Output | 8-bit | Scaled to `word_count - 1` |
| **R** | `m_axi_rdata` | Input | 64-bit | Incoming Read Data Stream |
| **R** | `m_axi_rlast` | Input | 1-bit | Slave-driven final burst identifier |
| **R** | `m_axi_rvalid` | Input | 1-bit | Handshake indicator from Slave |
| **R** | `m_axi_rready` | Output | 1-bit | Controlled via Read FSM engine |

## **Testbench & Regression Verification Environment**

The validation platform `tb_top_axi` performs matrix regression sweeps across two separated target memory slave domains:

* **Phase 1 Lower Domain Zone:** Verifies memory accuracy inside AXI RAM 1 (`Slot 0`: `0x0000_0000` to `0x1FFF_FFFF`).  
* **Phase 2 Upper Domain Zone:** Verifies accuracy inside AXI RAM 2 (`Slot 1`: `0xE000_0000` to `0xFFFF_FFFF`).

Every sweep fills the memory space with identifiable hex headers (`0xC001_A001`, `0xBEEF_0004`, etc.) combined with sequential loop markers, performs the automated dual-direction physical hardware translation, cleans out validation states to avoid false positives, and executes a cycle-accurate checker routine.

## **Simulation Execution & Expected Results**

To run the verification suite inside Mentor Graphics ModelSim or Questa Advanced Simulator, source the simulation script using the following macro commands:

Tcl

```
add wave -position insertpoint sim:/tb_top_axi/uut/axi_master_mover/*
restart -f
run 150 us
```

### **Expected Simulator Transcript Console Output**

When the design runs successfully, the testbench pipelined checker eliminates race conditions and prints an itemized data verification matrix log for each memory offset location. The simulation must pass cleanly through all variable burst bounds without throwing errors:

Plaintext

```
# Addressing configuration for axi_interconnect instance tb_top_axi.uut.central_bus_switchboard
#  0 ( 0): 00000000 / 29 -- 00000000-1fffffff
#  1 ( 0): e0000000 / 29 -- e0000000-ffffffff
# 
# =========================================================
#    LAUNCHING SEPARATED PORT REGRESSION SWEEPS              
# =========================================================
# [STATUS] Global clock stabilized at 80 MHz. Initiating sweeps...
# 
# ---------------------------------------------------------
#  RUNNING SWEEP PHASE 1: AXI RAM 1 LOWER DOMAIN ACCURACY  
# ---------------------------------------------------------
# [MATRIX SWEEP] Testing Target Address 0x00001000 | Length: 1 Beats
#   --- Individual Location Verification Report ---
#   [MATCH] Beat 000 | Memory Index: 0 | Addr Offset: +0 B | Data: 0xc001a00100000000
#    [PASS] Sweep zone verified successfully.
# 
# [MATRIX SWEEP] Testing Target Address 0x00002400 | Length: 4 Beats
#   --- Individual Location Verification Report ---
#   [MATCH] Beat 000 | Memory Index: 0 | Addr Offset: +0 B | Data: 0xbeef000400000000
#   [MATCH] Beat 001 | Memory Index: 1 | Addr Offset: +8 B | Data: 0xbeef000400000001
#   [MATCH] Beat 002 | Memory Index: 2 | Addr Offset: +16 B | Data: 0xbeef000400000002
#   [MATCH] Beat 003 | Memory Index: 3 | Addr Offset: +24 B | Data: 0xbeef000400000003
#    [PASS] Sweep zone verified successfully.
# 
# [MATRIX SWEEP] Testing Target Address 0x00003000 | Length: 13 Beats
#   --- Individual Location Verification Report ---
#   [MATCH] Beat 000 | Memory Index: 0 | Addr Offset: +0 B | Data: 0x7777d11100000000
#   [MATCH] Beat 001 | Memory Index: 1 | Addr Offset: +8 B | Data: 0x7777d11100000001
#   ...
#   [MATCH] Beat 012 | Memory Index: 12 | Addr Offset: +96 B | Data: 0x7777d1110000000c
#    [PASS] Sweep zone verified successfully.
# 
# ---------------------------------------------------------
#  RUNNING SWEEP PHASE 2: AXI RAM 2 UPPER DOMAIN ACCURACY  
# ---------------------------------------------------------
# [MATRIX SWEEP] Testing Target Address 0xE0000000 | Length: 1 Beats
#   --- Individual Location Verification Report ---
#   [MATCH] Beat 000 | Memory Index: 0 | Addr Offset: +0 B | Data: 0xc002b00200000000
#    [PASS] Sweep zone verified successfully.
# 
# [MATRIX SWEEP] Testing Target Address 0xE0001000 | Length: 8 Beats
#   --- Individual Location Verification Report ---
#   [MATCH] Beat 000 | Memory Index: 0 | Addr Offset: +0 B | Data: 0xa5a5000800000000
#   [MATCH] Beat 001 | Memory Index: 1 | Addr Offset: +8 B | Data: 0xa5a5000800000001
#   [MATCH] Beat 002 | Memory Index: 2 | Addr Offset: +16 B | Data: 0xa5a5000800000002
#   [MATCH] Beat 003 | Memory Index: 3 | Addr Offset: +24 B | Data: 0xa5a5000800000003
#   [MATCH] Beat 004 | Memory Index: 4 | Addr Offset: +32 B | Data: 0xa5a5000800000004
#   [MATCH] Beat 005 | Memory Index: 5 | Addr Offset: +40 B | Data: 0xa5a5000800000005
#   [MATCH] Beat 006 | Memory Index: 6 | Addr Offset: +48 B | Data: 0xa5a5000800000006
#   [MATCH] Beat 007 | Memory Index: 7 | Addr Offset: +56 B | Data: 0xa5a5000800000007
#    [PASS] Sweep zone verified successfully.
# 
# =========================================================
#    ALL MULTI-PORT SEPARATED SWEEPS COMPLETED CLEANLY    
# =========================================================
```

**Verification Note:** If any individual beat prints an `[ERROR]` tag instead of `[MATCH]`, the testbench terminates immediately via a `$finish` statement to preserve simulation trace histories at the exact failure point.

