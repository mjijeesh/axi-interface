#!/usr/bin/env python3
"""
Microchip Libero SoC & ModelSim Master Automation Pipeline Tool
=============================================================================
Company/Institution:  Tecnomic Components / Creative System Labs
Engineer:             Automated Flow Engine
Year:                 2026

Description:
  This script provides a modularized, robust command-line interface to
  orchestrate hardware compilation and behavioral verification pipelines 
  for Microchip FPGAs (SmartFusion2, RTG4, and PolarFire).

Directory Layout Schema:
  - Libero Project Space:  build/<target_family>/top/
  - Simulation Workspace:  build/<target_family>/sim/
"""

import os
import argparse
import subprocess
import sys
import shutil

# ==========================================================================
# Multi-Device Architecture Parameters Mapping Database
# ==========================================================================
DEVICE_DB = {
    "smartfusion2": {
        "family": "SmartFusion2",
        "die": "M2S025",
        "package": "VF256",
        "speed": "STD",
        "voltage": "1.2",
        "adv_options": "-adv_options {IO_DEFT_STD:LVCMOS 3.3V}",
        "core_vlnv": "Actel:SgCore:FCCC:2.0.201",
        "ccc_params": "-params {CLK0_IS_USED:true GL0_IS_USED:true GL0_OUT_0_FREQ:80 PLL_IN_FREQ:50 PLL_IS_USED:true}",
        "lib_name": "SmartFusion2",
        "vlog_lib_dir": "smartfusion2"
    },
    "rtg4": {
        "family": "RTG4",
        "die": "RT4G150_ES",
        "package": "CG1657",
        "speed": "-1",
        "voltage": "1.2",
        "adv_options": "-adv_options {IO_DEFT_STD:LVCMOS 3.3V}",
        "core_vlnv": "Actel:SgCore:RTG4FCCC:2.0.201",
        "ccc_params": "-params {CLK0_IS_USED:true GL0_IS_USED:true GL0_OUT_0_FREQ:80 PLL_IN_FREQ:50 PLL_IS_USED:true}",
        "lib_name": "RTG4",
        "vlog_lib_dir": "rtg4"
    },
    "polarfire": {
        "family": "PolarFire",
        "die": "MPF300T",
        "package": "FCG1152",
        "speed": "-1",
        "voltage": "1.0",
        "adv_options": "-adv_options {IO_DEFT_STD:LVCMOS 1.8V}",
        "core_vlnv": "Actel:SystemBuilder:PF_CCC:2.0.300",
        "ccc_params": "-params {CLK0_IS_USED:true GL0_IS_USED:true GL0_OUT_0_FREQ:80 PLL_IN_FREQ:50 PLL_IS_USED:true}",
        "lib_name": "PolarFire",
        "vlog_lib_dir": "polarfire"
    }
}


# ==========================================================================
# MODULE 1: Environment & Workspace Management
# ==========================================================================
def cleanup_workspace(directory_path, label):
    """Safely purges designated directories to clear stale compile assets or file locks."""
    if os.path.isdir(directory_path):
        print(f"[CLEANUP] Purging previous {label} workspace tree: {directory_path}")
        try:
            shutil.rmtree(directory_path)
            print(f"[CLEANUP] Stale {label} workspace removed successfully.")
        except Exception as e:
            print(f"[WARNING] Cleanup encountered minor friction on {label}: {e}. Moving forward...")


def get_sorted_project_hdl(proj_hdl_dir):
    """Scans Libero's internal imported hdl folder and sorts modules bottom-up for compilation."""
    if not os.path.isdir(proj_hdl_dir):
        print(f"[ERROR] Libero failed to create the internal HDL folder structure: {proj_hdl_dir}")
        sys.exit(1)

    hdl_files = sorted([f for f in os.listdir(proj_hdl_dir) if f.endswith('.v')])
    for top_candidate in ["fpga_top.v", "top.v"]:
        if top_candidate in hdl_files:
            hdl_files.remove(top_candidate)
            hdl_files.append(top_candidate)
            break
    return hdl_files


# ==========================================================================
# MODULE 2: Constraint Verification Engine
# ==========================================================================
def verify_constraints(constraints_dir):
    """
    Validates that required physical placement and timing assets exist in the source repository.
    Aborts early with an error code if any critical design constraints are missing.
    """
    constraint_paths = {
        "io_pdc": os.path.join(constraints_dir, "io", "top_io.pdc"),
        "fp_pdc": os.path.join(constraints_dir, "fp", "top_fp.pdc"),
        "top_sdc": os.path.join(constraints_dir, "sdc", "top.sdc")
    }

    # Verify presence of all required configuration files
    for name, path in constraint_paths.items():
        if not os.path.isfile(path):
            print(f"[ERROR] Critical constraint file missing from repository: {path}")
            print("[ERROR] Please ensure your layout constraints are present before compiling.")
            sys.exit(1)

    # Return sanitized paths for Tcl interpretation
    return {k: v.replace(os.sep, "/") for k, v in constraint_paths.items()}


# ==========================================================================
# MODULE 3: Libero Code Generator & Subprocess Axis
# ==========================================================================
def generate_tcl(target, hdl_dir, stim_dir, constraints, output_tcl, mode):
    """Constructs a platform-specific Tcl scripting engine to build the Libero project."""
    cfg = DEVICE_DB[target]
    proj_dir = f"./build/{target}/top"
    
    hdl_source_files = [os.path.join(hdl_dir, f) for f in os.listdir(hdl_dir) if f.endswith('.v')]
    import_hdl_cmds = "\n".join([f'import_files -hdl_source {{{f.replace(os.sep, "/")}}}' for f in hdl_source_files])
    
    import_stim_cmds = ""
    if os.path.isdir(stim_dir):
        stim_source_files = [os.path.join(stim_dir, f) for f in os.listdir(stim_dir) if f.endswith('.v')]
        if stim_source_files:
            import_stim_cmds = "\n# Import Stimulus Testbench Files into Libero\n" + "\n".join(
                [f'import_files -stimulus {{{f.replace(os.sep, "/")}}}' for f in stim_source_files]
            )

    flow_cmds = ""
    if mode != "sim":
        flow_cmds = f"""
# Full Hardware Pipeline Processing Implementations
run_tool -name {{CONSTRAINT_MANAGEMENT}}
run_tool -name {{SYNTHESIZE}}
run_tool -name {{PLACEROUTE}}
run_tool -name {{GENERATEPROGRAMMINGDATA}}
run_tool -name {{GENERATEPROGRAMMINGFILE}}

# Programming Package Job Generation Data Export
export_prog_job \\
    -job_file_name {{top}} \\
    -export_dir {{{proj_dir}/designer/top/export}} \\
    -bitstream_file_type {{TRUSTED_FACILITY}} \\
    -bitstream_file_components {{FABRIC }}
"""
        if mode == "program":
            flow_cmds += "\nrun_tool -name {PROGRAMDEVICE}\n"

    tcl_content = f"""# --------------------------------------------------------------------------
new_project \\
    -location {{{proj_dir}}} \\
    -name {{top}} \\
    -block_mode 0 \\
    -standalone_peripheral_initialization 0 \\
    -instantiate_in_smartdesign 1 \\
    -use_enhanced_constraint_flow 1 \\
    -hdl {{VERILOG}} \\
    -family {{{cfg['family']}}} \\
    -die {{{cfg['die']}}} \\
    -package {{{cfg['package']}}} \\
    -speed {{{cfg['speed']}}} \\
    -die_voltage {{{cfg['voltage']}}} \\
    -part_range {{COM}} \\
    {cfg['adv_options']} \\
    -ondemand_build_dh 0

{import_hdl_cmds}
{import_stim_cmds}

build_design_hierarchy

create_and_configure_core \\
    -core_vlnv {{{cfg['core_vlnv']}}} \\
    -component_name {{FCCC_C0}} \\
    {cfg['ccc_params']}

build_design_hierarchy
set_root -module {{top::work}}
derive_constraints_sdc

import_files -io_pdc {{{constraints['io_pdc']}}}
import_files -fp_pdc {{{constraints['fp_pdc']}}}
import_files -convert_EDN_to_HDL 0 -sdc {{{constraints['top_sdc']}}}

organize_tool_files -tool {{SYNTHESIZE}} -file {{{proj_dir}/constraint/top.sdc}} -module {{top}} -input_type {{constraint}}
organize_tool_files -tool {{PLACEROUTE}} -file {{{proj_dir}/constraint/io/top_io.pdc}} -file {{{proj_dir}/constraint/fp/top_fp.pdc}} -file {{{proj_dir}/constraint/top.sdc}} -module {{top}} -input_type {{constraint}}
organize_tool_files -tool {{VERIFYTIMING}} -file {{{proj_dir}/constraint/top.sdc}} -module {{top}} -input_type {{constraint}}
{flow_cmds}
"""
    with open(output_tcl, "w") as f:
        f.write(tcl_content)


def run_libero(libero_path, tcl_script_path, target_name):
    """Launches Microchip Libero SoC headlessly in batch mode."""
    print(f"[INFO] Launching Libero SoC Database Engine for {target_name.upper()}...")
    cmd = [libero_path, f"SCRIPT:{tcl_script_path}"]
    try:
        subprocess.run(cmd, check=True, stdout=sys.stdout, stderr=sys.stderr)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Libero hardware compilation broken: {e}")
        sys.exit(1)


# ==========================================================================
# MODULE 4: Standalone ModelSim Macro Factory & Execution Axis
# ==========================================================================
def generate_modelsim_macro(target, hdl_files, proj_stim_dir, build_dir, tb_top, sim_time, precompiled_base, do_file_path, console_mode, vcd_mode):
    """Dynamically writes an optimized macro script (run.do) pulling assets out of the Libero database."""
    cfg = DEVICE_DB[target]
    
    proj_dir_abs = os.path.abspath(os.path.join(build_dir, target, "top")).replace(os.sep, "/")
    precompiled_base_clean = precompiled_base.replace(os.sep, "/")
    
    error_trapping = "onerror {quit -force}\nonbreak {quit -force}\n" if console_mode else ""

    do_content = f"""{error_trapping}quietly set ACTELLIBNAME {cfg['lib_name']}
quietly set PROJECT_DIR "{proj_dir_abs}"

if {{[file exists presynth/_info]}} {{
   echo "INFO: Simulation library presynth already exists"
}} else {{
   file delete -force presynth 
   vlib presynth
}}
vmap presynth presynth
vmap {cfg['lib_name']} "{precompiled_base_clean}/{cfg['vlog_lib_dir']}"

vlog -sv -work presynth "${{PROJECT_DIR}}/component/work/FCCC_C0/FCCC_C0_0/FCCC_C0_FCCC_C0_0_FCCC.v"
vlog -sv -work presynth "${{PROJECT_DIR}}/component/work/FCCC_C0/FCCC_C0.v"
"""

    for f in hdl_files:
        do_content += f'vlog -sv -work presynth "${{PROJECT_DIR}}/hdl/{f}"\n'
        
    if os.path.isdir(proj_stim_dir):
        for f in sorted(os.listdir(proj_stim_dir)):
            if f.endswith('.v'):
                do_content += f'vlog "+incdir+${{PROJECT_DIR}}/stimulus" -sv -work presynth "${{PROJECT_DIR}}/stimulus/{f}"\n'
            
    vcd_cmds = ""
    if vcd_mode:
        vcd_cmds = f"\nvcd file {tb_top}.vcd\nvcd add -r /{tb_top}/*\n"

    if console_mode:
        do_content += f"""
vsim -voptargs="+acc" -L {cfg['lib_name']} -L presynth  -t 1fs presynth.{tb_top}
{vcd_cmds}log -r /*
run {sim_time}
quit -force
"""
    else:
        do_content += f"""
vsim -voptargs="+acc" -L {cfg['lib_name']} -L presynth  -t 1fs presynth.{tb_top}
{vcd_cmds}add wave /{tb_top}/*
run {sim_time}
"""

    with open(do_file_path, "w") as f:
        f.write(do_content)
    print(f"[INFO] Standalone project-linked macro written to: {do_file_path}")


def run_modelsim(modelsim_path, do_file_path, console_mode, sim_workspace_dir):
    """Invokes ModelSim/Questa using subprocess executing directly within the target sim/ directory boundary."""
    print(f"[INFO] Launching ModelSim Engine Wrapper Axis inside: {sim_workspace_dir}")
    
    if console_mode:
        sim_cmd = [modelsim_path, "-c", "-batch", "-do", do_file_path]
    else:
        sim_cmd = [modelsim_path, "-do", do_file_path]
        
    try:
        subprocess.run(sim_cmd, check=True, cwd=sim_workspace_dir)
    except FileNotFoundError:
        print(f"[ERROR] Failed to locate ModelSim binary file link at path: '{modelsim_path}'.")
        sys.exit(1)


# ==========================================================================
# MODULE 5: Main Orchestrator Interface Entry Point
# ==========================================================================
def main():
    # Helper description mapped to the nested target path constraints
    helper_description = (
        "===============================================================================\n"
        "         Microchip Libero SoC & ModelSim Modular Automation Pipeline          \n"
        "===============================================================================\n"
        "Expected Workspace Layout:\n"
        "  ├── src/\n"
        "  │   ├── hdl/                <-- All parallel Verilog design modules\n"
        "  │   ├── stimulus/           <-- Testbenches (e.g. ddr3.v, fpga_top_tb.v)\n"
        "  │   └── constraints/\n"
        "  └── build/\n"
        "      └── <target_family>/\n"
        "          ├── top/            <-- Libero Project Sandboxed Database Root\n"
        "          └── sim/            <-- Isolated ModelSim/Questa Simulator Sandbox Root"
    )

    helper_epilog = (
        "Execution Examples:\n"
        "  # 1. Complete full structural hardware compile up to bitstream packages\n"
        "  python3 build.py --family smartfusion2 --build\n\n"
        "  # 2. Run simulation inside terminal console mode with a VCD wave dump\n"
        "  python3 build.py --family smartfusion2 --sim --sim_time 20ms --tb_top tb_fpga_top_v3 --console --vcd"
    )

    parser = argparse.ArgumentParser(description=helper_description, epilog=helper_epilog, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--family", required=True, choices=["smartfusion2", "polarfire", "rtg4"], help="Target device architecture family.")
    parser.add_argument("--sim_time", default="1000ns", help="Total simulation runtime limit window (e.g., 20ms, 1000ns).")
    parser.add_argument("--tb_top", default="tb_fpga_top_v3", help="Module name string identifier referencing your testbench block.")
    parser.add_argument("--libero_path", default="libero", help="Absolute path command pointing to Libero SoC.")
    parser.add_argument("--modelsim_path", default="vsim", help="Absolute path command pointing to ModelSim/Questa 'vsim'.")
    parser.add_argument("--precompiled_base", default="/opt/microchip/Libero_SoC_2025.2/Libero_SoC/Designer/lib/modelsimpro/precompiled/vlog", help="Precompiled vendor primitives maps base folder directory.")
    parser.add_argument("--console", action="store_true", help="Execute simulation directly inside the command line console (Text Only).")
    parser.add_argument("--vcd", action="store_true", help="Generate a standard .vcd signal dump file for post-processing view loops.")

    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument("--build", action="store_true", help="Compile layout logic and generate programming bitstream files. (Default)")
    mode_group.add_argument("--program", action="store_true", help="Execute a complete '--build' processing run, then invoke FlashPro.")
    mode_group.add_argument("--sim", action="store_true", help="Initialize database and run verification inside ModelSim.")
    
    args = parser.parse_args()
    target = args.family.lower()

    mode = "build"
    if args.program: mode = "program"
    elif args.sim: mode = "sim"
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    hdl_dir = os.path.join(script_dir, "src", "hdl")
    constraints_dir = os.path.join(script_dir, "src", "constraints", target)
    build_dir = os.path.join(script_dir, "build")
    
    stim_dir = os.path.join(script_dir, "src", "stimulus")
    if not os.path.isdir(stim_dir):
        stim_dir = os.path.join(script_dir, "src", "stimilas")
    
    # FIXED: Shifted sim folder generation logic underneath build/<target>/sim/ bounds
    target_impl_dir = os.path.join(build_dir, target, "top")
    sim_workspace_dir = os.path.join(build_dir, target, "sim")
    
    output_tcl = os.path.join(build_dir, f"run_project_{target}.tcl")
    do_file_path = os.path.join(sim_workspace_dir, "run.do")
    
    # Initialize workspace structure safely
    os.makedirs(build_dir, exist_ok=True)
    
    cleanup_workspace(target_impl_dir, f"Libero Project [{target.upper()}]")
    if mode == "sim":
        cleanup_workspace(sim_workspace_dir, "QuestaSim Engine")
        os.makedirs(sim_workspace_dir, exist_ok=True)

    constraints = verify_constraints(constraints_dir)

    # Step 1: Run Libero project generation to import HDL and Testbenches
    generate_tcl(target, hdl_dir, stim_dir, constraints, output_tcl, mode)
    run_libero(args.libero_path, output_tcl, target)

    # Step 2: Handle isolated simulation out of build/<target>/sim workspace parameters
    if mode == "sim":
        proj_hdl_dir = os.path.join(build_dir, target, "top", "hdl")
        proj_stim_dir = os.path.join(build_dir, target, "top", "stimulus")
        
        hdl_files = get_sorted_project_hdl(proj_hdl_dir)

        generate_modelsim_macro(target, hdl_files, proj_stim_dir, build_dir, args.tb_top, args.sim_time, args.precompiled_base, do_file_path, args.console, args.vcd)
        run_modelsim(args.modelsim_path, do_file_path, args.console, sim_workspace_dir)
    else:
        print(f"[SUCCESS] Hardware design build compilation successfully finished for target family: {target}.")


if __name__ == "__main__":
    main()