# **Microchip Libero SoC & QuestaSim Automation Pipeline User Guide**

**Company/Institution:** Tecnomic Components 

**Engineer:** Automated Flow Engine

**Release Year:** 2026

**Target Hardware:** Microchip SmartFusion2, RTG4, and PolarFire FPGAs

**Associated Automation Script:** `build.py`

## **1\. Overview**

The `build.py` Python script is a robust, modularized, command-line utility designed to automate, sand-box, and orchestrate the development lifecycle of Microchip FPGAs. It manages two main workflows:

1. **Hardware Compilation Pipeline (`--build` / `--program`):** Creates an isolated Libero project, imports design files and constraint files, sources target-specific custom hardware components (such as DDR, PLL/FCCC controllers), runs synthesis and layouts, and exports the final trusted facility programming bitstreams.  
2. **Behavioral Verification Pipeline (`--sim`):** Dynamically extracts generated IP modules and project design wrappers out of the Libero database, sorts them bottom-up in perfect architectural dependency order, compiles all project assets, and launches QuestaSim/ModelSim cleanly in either CLI interactive mode or GUI mode with no elaboration timing delays.

## **2\. Directory Layout Schema**

To run the master script, your project folder structure must match this layout. This strict layout ensures that builds remain completely sandboxed, allowing multiple target device builds to coexist cleanly on the same machine without file-lock collisions.

```
<project_root>/
├── build.py                             # Master automation orchestrator script
├── src/                                 # Central Source Repository
│   ├── hdl/                             # All design RTL modules (*.v)
│   │   ├── fpga_top.v
│   │   ├── axi_master_if.v
│   │   └── ...
│   ├── stimulus/                        # Testbench modules (*.v)
│   │   └── tb_top_axi.v
│   ├── constraints/                     # Target-specific physical mapping
│   │   ├── smartfusion2/
│   │   ├── polarfire/
│   │   └── rtg4/
│   │       ├── io/top_io.pdc            # I/O pin assignments
│   │       ├── fp/top_fp.pdc            # Floorplanning / Placement rules
│   │       └── sdc/top.sdc              # Design Timing constraints
│   └── tcl/                             # Sub-system instantiation TCLs
│       ├── FDDRC_With_INIT_recursive.tcl # General sub-system TCL script (fallback)
│       ├── smartfusion2/                # Target-specific SmartFusion2 TCL scripts
│       ├── polarfire/                   # Target-specific PolarFire TCL scripts
│       └── rtg4/                        # Target-specific RTG4 TCL scripts
│           └── FDDRC_With_INIT_recursive.tcl
│
└── build/                               # Dynamic Build Output (Auto-Generated)
    ├── run_project_<target>.tcl         # Master Libero workspace build script
    └── <target_family>/                 # Sandboxed target workspace folder
        ├── top/                         # Libero Database Sandbox (contains top.prjx)
        │   ├── component/work/          # Auto-generated IP source codes
        │   └── ...
        └── sim/                         # Simulator Sandbox (contains compile databases)
            ├── run.do                   # QuestaSim macro file (auto-generated)
            └── presynth/                # Compiled logical simulation libraries
```

## **3\. Script Features & Solved Constraints**

* **Bottom-Up Compilation Ordering:** Standard directories contain circular file listings. This script crawls generated components recursively and compiles deepest leaf-submodules first (e.g., compiling nested PLLs and physical layers before outer wrappers) to avoid `module not defined` compiler warnings.  
* **Auto-Bypass Duplicate IPs:** The script detects if you are sourcing a custom sub-system TCL file that generates a global clocking network. If it is active, it automatically suppresses Libero's default FCCC core generator (`FCCC_C0`) to prevent dual-definition elaboration aborts.  
* **Timing Resolution Hard-Alignment:** Microchip precompiled simulation primitives are compiled with a time step of $1\\text{ ps}$. The script overrides QuestaSim's default $1\\text{ fs}$ launch parameter to $-t\\text{ 1ps}$ globally, preventing severe delay calculation rounding mismatch aborts.  
* **Headless/GUI Workspace Binding:** In GUI mode, the script forces graphical thread initializes via `-gui` and prepends directory locks inside `run.do` (`cd "<path>"`), allowing custom wave setups (`add wave`) to run without system faults.

## **4\. Command Line Option Reference**

| Parameter Flag | Description | Default Value |
| ----- | ----- | ----- |
| `--family` | **Required.** Targets the silicon architecture. Must be `smartfusion2`, `rtg4`, or `polarfire`. | *None* |
| `--build` | Initiates Libero synthesis, layout, and programming exports. | `True` (if no other mode selected) |
| `--sim` | Initiates database collection and launches the simulator. | `False` |
| `--program` | Performs a full build, then attempts to flash the device via FlashPro. | `False` |
| `--sim_time` | Total simulation execution time. | `1000ns` |
| `--tb_top` | The top-level module name representing the simulation wrapper. | `tb_fpga_top_v3` |
| `--design_tcl` | Sourced IP build script name expected in the TCL directories. | `FDDRC_With_INIT_recursive.tcl` |
| `--console` | Launches Questasim cleanly in text-only console shell. | `False` (GUI by default) |
| `--vcd` | Dumps wave traces to a standard `.vcd` file in the sim directory. | `False` |
| `--libero_path` | Path or environment alias pointing to your Libero binary. | `libero` |
| `--modelsim_path` | Path or environment alias pointing to your `vsim` executable. | `vsim` |
| `--precompiled_base` | Directory path mapping precompiled device libraries. | `/opt/microchip/.../vlog` |

## **5\. Practical Execution Examples**

### **Example A: Run Complete RTL-to-Bitstream Hardware Compilation (RTG4)**

This compiles your physical code, sources target-specific configurations under `src/tcl/rtg4`, and writes out programming files.

```
python3 build.py --family rtg4 --build
```

### **Example B: Run Behavioral Simulation in GUI Mode (PolarFire)**

Instantiates the database and launches QuestaSim Pro's GUI interface with loaded waveform views.

```
python3 build.py --family polarfire --sim --tb_top tb_top_axi --sim_time 10us
```

### **Example C: Run Interactive Headless Text-Only Simulation (SmartFusion2)**

Forces compilation and checks results instantly inside the terminal shell window.

```
python3 build.py --family smartfusion2 --sim --console --sim_time 500ns
```

## **6\. Expected Console Outputs**

### **Successful Hardware Build Run (`--build`)**

Running the compilation yields clean logging, starting with database checks, and proceeding through constraint mapping up to file exports:

```
[CLEANUP] Purging previous Libero Project [RTG4] workspace tree: /home/user/axi-interface/build/rtg4/top
[CLEANUP] Stale Libero Project [RTG4] workspace removed successfully.
[INFO] Sourcing target-specific custom IP/Sub-system design script by default: rtg4/FDDRC_With_INIT_recursive.tcl
[INFO] Launching Libero SoC Database Engine for RTG4...

Executing Tcl commands...
--------------------------------------------------
- Initializing sandboxed project: build/rtg4/top...
- Importing Design RTL from src/hdl...
- Importing Timing and Placement Constraints...
- Sourcing custom DDR layout script...
- Linking constraint tools...
- Running synthesis...
- Running Place & Route...
- Exporting trusted facility programming file: build/rtg4/top/designer/top/export/top.job
--------------------------------------------------

[SUCCESS] Hardware design build compilation successfully finished for target family: rtg4.
```

### **Successful Simulation Launch (`--sim`)**

Running the simulator outputs your mapped dependencies, builds compile databases inside the sandbox, and launches the simulator:

```
[CLEANUP] Purging previous Libero Project [RTG4] workspace tree: /home/user/axi-interface/build/rtg4/top
[CLEANUP] Stale Libero Project [RTG4] workspace removed successfully.
[CLEANUP] Purging previous QuestaSim Engine workspace tree: /home/user/axi-interface/build/rtg4/sim
[CLEANUP] Stale QuestaSim Engine workspace removed successfully.
[INFO] Sourcing target-specific custom IP/Sub-system design script by default: rtg4/FDDRC_With_INIT_recursive.tcl
[INFO] Launching Libero SoC Database Engine for RTG4...
...[Libero generates components and files]...

[INFO] Standalone project-linked macro written to: /home/user/axi-interface/build/rtg4/sim/run.do
[INFO] Launching ModelSim Engine Wrapper Axis inside: /home/user/axi-interface/build/rtg4/sim

QuestaSim Pro Microchip Edition-64 vmap 2024.3 Lib Mapping Utility 2024.09 Sep 10 2024
vmap presynth presynth 
Modifying /home/user/axi-interface/build/rtg4/sim/modelsim.ini

vmap RTG4 /opt/microchip/Libero_SoC_2025.2/Libero_SoC/Designer/lib/modelsimpro/precompiled/vlog/rtg4 
Modifying /home/user/axi-interface/build/rtg4/sim/modelsim.ini

# Compile Generated SmartDesign / Core IP Components (Bottom-Up)
vlog -sv -work presynth "$PROJECT_DIR/component/work/FCCC_C0/FCCC_C0_0/FCCC_C0_FCCC_C0_0_RTG4FCCC.v"
-- Compiling module FCCC_C0_FCCC_C0_0_RTG4FCCC
vlog -sv -work presynth "$PROJECT_DIR/component/work/FCCC_C0/FCCC_C0.v"
-- Compiling module FCCC_C0

# Compile Project HDL Source Files
vlog -sv -work presynth "$PROJECT_DIR/hdl/axi_master_if.v"
-- Compiling module axi4_master_if
vlog -sv -work presynth "$PROJECT_DIR/hdl/fpga_top.v"
-- Compiling module top

# Compile Project Testbench Files
vlog "+incdir+$PROJECT_DIR/stimulus" -sv -work presynth "$PROJECT_DIR/stimulus/tb_top_axi.v"
-- Compiling module tb_top_axi

vsim -voptargs="+acc" -L RTG4 -L presynth -t 1ps -gRAM_ES_BEHAVIOR=1 presynth.tb_top_axi
Loading work.tb_top_axi(fast)
Loading work.top(fast)
Loading work.FCCC_C0(fast)
Loading work.FCCC_C0_FCCC_C0_0_RTG4FCCC(fast)
Loading RTG4.CCC_PLL(fast)
Loading RTG4.AutoReset_PLL(fast)
Loading work.axi4_master_if(fast)
...
Elaboration Successful. Launching user environment...
```

## **7\. Troubleshooting Simulation Errors**

#### **Issue 1: `Error loading design` / `Module 'XYZ' is not defined`**

* **Cause:** QuestaSim timing resolution was mismatching with precompiled models, or a standard IP was compiled double into the target environment.  
* **Correction:** Ensure your script is updated to the latest revision, check that the precompiled path directory points to a valid `/vlog/rtg4` target, and verify that the target directory `build/rtg4/sim/` is mapping files cleanly during run initialization.

#### **Issue 2: QuestaSim launches but the window closes instantly**

* **Cause:** Running with CLI configuration commands in GUI launch context.  
* **Correction:** Do not pass the `--console` flag if you want to inspect waves graphically. The script natively opens the full interactive graphical waveform user interface by default.

