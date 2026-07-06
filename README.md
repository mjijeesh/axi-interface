## Microchip Libero SoC & ModelSim/QuestaSim Automation Pipeline

An advanced, highly modular Python automation framework designed to streamline and accelerate the digital design workflow for Microchip FPGAs (**SmartFusion2**, **RTG4**, and **PolarFire**). This script (`build.py`) acts as a unified command-line orchestrator that automates headless project creation, clock Conditioning Infrastructure (FCCC IP Core) generation, design constraint validation, complete hardware implementation (Synthesis through Place & Route), direct device programming, and high-performance sandboxed behavioral simulation.

🚀 Key Features

* **Headless Project Provisioning:** Generates unified, deterministic Libero SoC projects programmatically via Tcl generation, enforcing corporate Default I/O Signaling Rules (e.g., `LVCMOS 3.3V` / `1.8V`).  
* **Deterministic Bottom-Up Compilation Tree:** Automatically scans design files and guarantees top-level architectures (`top.v` or `fpga_top.v`) compile last, preventing module dependency errors.  
* **Fail-Fast Constraint Auditing:** Explicitly verifies pin placements and timing constraints (`.pdc` and `.sdc`) before initiating lengthy vendor tool execution loops.  
* **Sandboxed Workspace Isolation:**  
  * **Hardware Logic:** Contained strictly within `build/<target_family>/top/`.  
  * **Simulation Environment:** Contained strictly within an isolated sandbox `build/<target_family>/sim/`, ensuring zero repository root pollution.  
* **Blazing Fast Direct Simulator Interfacing:** Bypasses sluggish Libero GUI initialization entirely by compiling project sources directly in **QuestaSim/ModelSim** via custom-generated `run.do` macro files.  
* **Pure Terminal Console Mode Execution:** Provides a true text-only non-interactive execution mode (`-c -batch` parameters) with automated error trapping (`onerror {quit -force}`) to pass simulation logs directly to your standard output stream.  
* **On-Demand VCD Trace Dumps:** Generates absolute, clean Value Change Dump (`.vcd`) waveform profiles hierarchically to power headless profiling or external waveform view loops (e.g., GTKWave).

📂 Project Directory Structure

To operate seamlessly, the automation launcher script expects the following structural repository tree:

TXT  
Plaintext

```
├── src/
│   ├── hdl/                <-- All parallel Verilog design modules
│   ├── stimulus/           <-- Testbenches & simulation modules (Accepts 'stimilas')
│   └── constraints/
│       ├── smartfusion2/   <-- Folder channels: io/top_io.pdc, fp/top_fp.pdc, sdc/top.sdc
│       ├── rtg4/           <-- Space-grade constraints path layouts 
│       └── polarfire/      <-- Low-power architecture constraints layouts 
└── build.py                <-- Master Automation & Workflow Orchestrator Launcher 
```

⚙️ Command-Line Interface (CLI) Specification

To dynamically manage design configurations, pass standard options to the orchestrator:

Bash

```
python3 build.py --family <target> [mode_switch] [runtime_overrides]
```

### Core Architecture Switch (Mandatory)

* **`--family {smartfusion2, polarfire, rtg4}`**: Selects the target hardware fabric template database, signaling voltage parameters, default I/O standards, and clock IP core naming versions.

### Processing Execution Mode Switches (Mutually Exclusive)

* **`--build`**: Initializes the workspace, generates clock networks, binds hardware constraints, runs synthesis, implements layout routing, and exports final application programming bitstreams. This is the implicit default option.  
* **`--program`**: Executes a comprehensive system `--build` cycle, and immediately launches Microchip FlashPro over JTAG links to erase, verify, and write bitstream data blocks to the physical device.  
* **`--sim`**: Halts the physical toolchain processing loop after project and clock configuration generation to run direct behavioral simulations inside QuestaSim/ModelSim.

### Simulation Configuration Arguments (Optional Overrides)

* **`--sim_time <string>`**: Total simulation execution length tracking metrics (e.g., `20ms`, `500us`, `2000ns`). *Default: `1000ns`*.  
* **`--tb_top <string>`**: Name identifier mapping the exact root Verilog simulation testbench module. *Default: `tb_fpga_top_v3`*.  
* **`--console`**: Forces simulation processing headlessly into text-only mode inside the console (`-c -batch`), streaming log outputs straight to your active shell interface.  
* **`--vcd`**: Injects automated Value Change Dump (`.vcd`) instruction sets into the initialization script layout to dump signal transitions.

### Toolchain Directory Path Overrides (Optional Overrides)

* **`--libero_path <path>`**: Command string override to map custom Libero installation nodes. \*Default: `libero`  
* **`--modelsim_path <path>`**: Command string override to map custom ModelSim/Questa `vsim` installation nodes. *Default: `vsim`*.  
* **`--precompiled_base <path>`**: Absolute system path tracker specifying where vendor compiled primitives live. *Default: `/opt/microchip/Libero_SoC_2025.2/.../vlog`*.

## 🏁 Step-by-Step Execution Scenarios

#### Scenario 1: Full Hardware Compilation (`--build`)

This mode executes headless project creation, imports synthesizable code blocks, instantiates the hardware clock conditioning infrastructure core (FCCC), maps constraint rules, and runs the entire physical implementation layout down to final fabrication bitstream packages.

Bash

```
python3 build.py --family smartfusion2 --build
```

**Expected Console Logging Trace:**

Plaintext

```
[CLEANUP] Purging previous Libero Project [SMARTFUSION2] workspace tree: ./build/smartfusion2/top
[INFO] Initializing Libero Core Database for SMARTFUSION2 system configurations...
[INFO] Launching Libero SoC Database Engine for SMARTFUSION2...
... (Libero Synthesis & Place & Route Log Output) ...
[SUCCESS] Hardware design build compilation successfully finished for target family: smartfusion2.
```

#### Scenario 2: Automated Physical Hardware Flashing (`--program`)

This configuration builds on top of a full hardware compilation pass by instructing Libero to launch the physical programming hardware (FlashPro tool stack) over connected debug probes to instantly flash the silicon device fabric.

Bash

```
python3 build.py --family smartfusion2 --program
```

**Expected Application Output Execution Block:**

Plaintext

```
[CLEANUP] Purging previous Libero Project [SMARTFUSION2] workspace tree: ./build/smartfusion2/top
[INFO] Initializing Libero Core Database for SMARTFUSION2...
... (Libero full pipeline runs up to bitstream generation) ...
Info: Running PROGRAMDEVICE tool...
Info: FlashPro connection established.
Erasing device array... [cite: 27]
Info: Writing FPGA fabric array... [cite: 27]
Info: Verification cycle passed. Programming Succeeded. [cite: 27]
```

#### Scenario 3: Interactive Graphical Waveform Simulation (`--sim`)

This configuration sets up the baseline project environment, links your custom clocks, and handles workspace setup. It then copies required data blocks and initializes the ModelSim/Questa Graphical User Interface (GUI), setting up standard wave tracking blocks automatically.

Bash

```
python3 build.py --family smartfusion2 --sim --sim_time 15us --tb_top tb_fpga_top_v3
```

**Generated Macro Script (`build/smartfusion2/sim/run.do`):**

Tcl

```
quietly set ACTELLIBNAME SmartFusion2
quietly set PROJECT_DIR "/home/user/project/build/smartfusion2/top"
if {[file exists presynth/_info]} {
   echo "INFO: Simulation library presynth already exists"
} else {
   file delete -force presynth 
   vlib presynth
}
vmap presynth presynth
vmap SmartFusion2 "/opt/microchip/Libero_SoC_2025.2/Libero_SoC/Designer/lib/modelsimpro/precompiled/vlog/smartfusion2"
vlog -sv -work presynth "${PROJECT_DIR}/component/work/FCCC_C0/FCCC_C0_0/FCCC_C0_FCCC_C0_0_FCCC.v"
vlog -sv -work presynth "${PROJECT_DIR}/component/work/FCCC_C0/FCCC_C0.v"
vlog -sv -work presynth "${PROJECT_DIR}/hdl/axi_if.v"
vlog -sv -work presynth "${PROJECT_DIR}/hdl/uart_rx.v"
vlog -sv -work presynth "${PROJECT_DIR}/hdl/fpga_top.v"
vlog "+incdir+${PROJECT_DIR}/stimulus" -sv -work presynth "${PROJECT_DIR}/stimulus/fpga_top_tb.v"

vsim -voptargs="+acc" -L SmartFusion2 -L presynth -t 1fs presynth.tb_fpga_top_v3
add wave /tb_fpga_top_v3/*
run 15us
```

#### Scenario 4: Headless Text-Only Console Simulation (`--sim --console`)

Perfect for high-speed continuous integration pipeline scripts or terminal-only environments. This setup executes simulations entirely headlessly using the text terminal stream parameters (`-c -batch`), printing `$display` readouts right inside your active console shell.

Bash

```
python3 build.py --family smartfusion2 --sim --sim_time 500ns --tb_top tb_fpga_top_v3 --console
```

**Expected Console Logging Trace:**

Plaintext

```
[CLEANUP] Purging previous QuestaSim Engine workspace tree: ./build/smartfusion2/sim
[INFO] Launching Libero SoC Database Engine...
... (Libero generates required clock models and project structures) ...
[INFO] Standalone project-linked macro written to: ./build/smartfusion2/sim/run.do
[INFO] Launching ModelSim Engine Wrapper Axis inside: ./build/smartfusion2/sim
Reading run.do
# Map presynth to presynth library data structures
# Loading sv_std.std
# Loading presynth.tb_fpga_top_v3
# Loading SmartFusion2.CCC(fast)
# Loading SmartFusion2.CLKINT(fast)
# [UART_TX_LOG] Initializing transmitter block... Clock speed set to 80MHz. 
# [SYSTEM_CONTROL] Reset state de-asserted safely at timestamp: 45000fs. [cite: 33]
# [AXI_RAM_TEST] Core write handshake cycle verified successfully. [cite: 33]
# Simulation reached target limit threshold window. Automated termination triggered. [cite: 34]
```

#### Scenario 5: Console Simulation with VCD Waveform Dumps (`--sim --console --vcd`)

This setup combines headless command-line text execution with comprehensive automated waveform signal tracking. It dumps every data change across all design blocks directly into an independent, industry-standard Value Change Dump (`.vcd`) wave layout file.

Bash

```
python3 build.py --family smartfusion2 --sim --sim_time 20ms --tb_top tb_fpga_top_v3 --console --vcd
```

**Generated Macro Script Execution Strategy (`build/smartfusion2/sim/run.do`):**

Tcl

```
onerror {quit -force}
onbreak {quit -force}
... (Library Mappings & Source Compilation Blocks) ...
vsim -voptargs="+acc" -L SmartFusion2 -L presynth -t 1fs presynth.tb_fpga_top_v3
vcd file tb_fpga_top_v3.vcd
vcd add -r /tb_fpga_top_v3/*
log -r /*
run 20ms
quit -force
```

💡 **Note:** Your structural waveform trace details will generate cleanly inside the local directory path: `./build/smartfusion2/sim/tb_fpga_top_v3.vcd`.

## 🛡️ Built-in Safety Infrastructure & Fail-Fast Mechanics

The automation framework incorporates defensive programming checks to prevent stale builds, hanging processes, or hidden design errors:

* **Fail-Fast Constraint Checks:** Rather than letting the compilation fail hours later during layout, the script scans the `src/` directory beforehand. If `top_io.pdc`, `top_fp.pdc`, or `top.sdc` are missing, it stops immediately.  
* **Bottom-Up Compilation Trees:** The framework automatically ensures that top-level module architectures (`top.v` or `fpga_top.v`) are shifted to the absolute tail end of the compiler array, ensuring parent instances resolve cleanly.  
* **Visibility Preservation Under Optimization Pass:** The simulator execution commands pass explicit `-voptargs="+acc"` override strings under all run conditions. This instructs the optimizer (`vopt`) to preserve internal net names, preventing object errors like: `No objects found matching '/*'`..  
* **Non-Interactive Crash-Abort Trapping Engine:** When running in console mode, the macro injects explicit `onerror {quit -force}` instructions. If a compilation error or syntax break occurs, the process exits cleanly back to the terminal with a non-zero exit status instead of hanging in the background or stalling your CI/CD pipelines.

## 🔍 Troubleshooting Common Toolchain Failures

### 1\. File Not Found Error (`vlog-7 ENOENT`)

* **Symptom:** Simulator aborts on instructions with errors matching: `Failed to open design unit file... in read mode`.  
* **Root Cause:** Passing stimulus testbenches directly from the raw `src/` directory into headless simulators causes path mismatch breaks. Libero doesn't physically copy simulation models into its local directory database until the GUI is opened manually.  
* **Resolution:** Covered automatically by this pipeline framework. The script forces Libero to execute project instantiation first, which copies all hardware sources and stimulus testbenches. The Python script then scans Libero's local project workspace directory (`build/<target_family>/top/`) to dynamically build your macro script.

### 2\. Invalid Command Name Errors inside Libero

* **Symptom:** Libero project setups crash out with errors matching: `invalid command name "set_simulation_options"`.  
* **Root Cause:** Trying to pass simulation configurations through outdated global Tcl command lines inside headless project setups throws fatal tool execution breaks.  
* **Resolution:** Removed from the Libero project generation pass. All simulation runtime controls are managed directly via the `run $sim_time` macro lines inside the dedicated `build/<target_family>/sim/` simulation sandbox workspace.

## 📝 File Management Script

To save this document programmatically as `USAGE_GUIDE.md` from your workspace directory, run this Python block:

Python

```
with open("USAGE_GUIDE.md", "w") as f:
    f.write(usage_guide_content)

print("USAGE_GUIDE.md generated successfully.")
```

### **Key Contents Summary:**

* **Prerequisites Validation:** Clear instructions for environment setups covering required paths, environment strings, and precompiled vendor hardware primitives (`vlog`).  
* **Sandboxed Directory Architecture Layout:** A structural breakdown showing the physical isolation between the synthesizable hardware core engine files (`build/<target_family>/top/`) and the isolated verification simulator playground (`build/<target_family>/sim/`).  
* **CLI Parameter Matrix:** A comprehensive lookup reference detailing target boundaries, argument constraints, choices, flag behaviors, and structural defaults.  
* **5 Practical Copy-Paste Recipes:** Complete walkthroughs with realistic console traces and output results for every major mode—including full hardware compilations , physical automated device flashing , graphical wave viewers , pure terminal console logging streams , and automated Value Change Dump (`.vcd`) waveform profiles.  
   TXT  
* **Built-in Safety & Troubleshooting:** Automated defense strategies deployed by the script to safeguard your workflow.  
   TXT

