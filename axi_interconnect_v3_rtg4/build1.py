#!/usr/bin/env python3
"""
Microchip Libero SoC Master Automation Pipeline Tool
=============================================================================
Company/Institution:  Tecnomic Components / Creative System Labs
Engineer:             Automated Flow Engine
Year:                 2026

Description:
  This script provides a modularized, robust command-line interface to
  orchestrate hardware compilation and behavioral verification pipelines 
  for Microchip FPGAs (SmartFusion2, RTG4, and PolarFire) natively using 
  the Libero SoC internal tool chain infrastructure.
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
        "range": "COM",
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
        "speed": "STD",
        "voltage": "1.2",
        "range": "MIL",
        "adv_options": "-adv_options {IO_DEFT_STD:LVCMOS 2.5V}",
        "core_vlnv": "Actel:SgCore:RTG4FCCC:*",
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
        "range": "EXT",
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
def generate_tcl(target, hdl_dir, stim_dir, constraints, output_tcl, mode, tcl_dir=None, design_tcls=None, tb_top="testbench", sim_time="1000ns"):
    """Constructs a platform-specific Tcl scripting engine to build and process the Libero project."""
    cfg = DEVICE_DB[target]
    proj_dir = f"./build/{target}/top"
    
    hdl_source_files = [os.path.join(hdl_dir, f) for f in os.listdir(hdl_dir) if f.endswith('.v')]
    import_hdl_cmds = "\n".join([f'import_files -hdl_source {{{f.replace(os.sep, "/")}}}' for f in hdl_source_files])
    
    import_stim_cmds = ""
    organize_stim_cmds = ""
    
    if os.path.isdir(stim_dir):
        stim_files = sorted(os.listdir(stim_dir))
        import_list = []
        org_list = []
        
        for f in stim_files:
            if f.endswith('.v') or f.endswith('.vh') or f.endswith('.h'):
                import_list.append(f'import_files -stimulus {{{os.path.join(stim_dir, f).replace(os.sep, "/")}}}')
            if f.endswith('.v'):
                org_list.append(f'-file ./{proj_dir}/stimulus/{f}')
                
        if import_list:
            import_stim_cmds = "\n# Import stimulus Testbench Files into Libero\n" + "\n".join(import_list)
        if org_list:
            files_formatted = " \\\n                    ".join(org_list)
            organize_stim_cmds = f"""
organize_tool_files -tool {{SIM_PRESYNTH}} \\
                    {files_formatted} \\
                    -module {{top::work}} -input_type {{stimulus}}"""

    flow_cmds = ""
    
    # Correctly mapping VSIM options based on valid parameter list
    vsim_target_opts = "-add_vsim_options {-gRAM_ES_BEHAVIOR=1}" if target == "rtg4" else ""

    if mode == "sim":
        flow_cmds = f"""
# --------------------------------------------------------------------------
# Native Libero Presynth Simulation Execution Block
# --------------------------------------------------------------------------
{organize_stim_cmds}

set_modelsim_options \\
    -use_automatic_do_file 1 \\
    -sim_runtime {{{sim_time}}} \\
    -tb_module_name {{{tb_top}}} \\
    -log_all_signals 1 \\
    -include_do_file 1 \\
    -disable_pulse_filtering 1 \\
    -resolution {{1ps}} \\
    -timeunit 1 \\
    -timeunit_base {{ns}} \\
    -precision 1 \\
    -precision_base {{ps}} \\
    {vsim_target_opts}

run_tool -name {{SIM_PRESYNTH}}
puts "Simulation completed successfully\\n"
"""
    else:
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

    # Assemble Sourcing Instructions for pre-created design components
    design_tcl_cmds = ""
    if tcl_dir and design_tcls:
        tcl_dir_clean = tcl_dir.replace(os.sep, "/")
        source_cmds = "\n".join([f"source {{{script}}}" for script in design_tcls])
        design_tcl_cmds = f"""
# Sourcing pre-created IP components in bottom-up fashion
set original_dir [pwd]
cd {{{tcl_dir_clean}}}
{source_cmds}
cd $original_dir
build_design_hierarchy
"""

    fccc_generation_cmd = ""
    if not design_tcls:
        fccc_generation_cmd = f"""
create_and_configure_core \\
    -core_vlnv {{{cfg['core_vlnv']}}} \\
    -component_name {{FCCC_C0}} \\
    {cfg['ccc_params']}
build_design_hierarchy
"""

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
    -part_range {{{cfg['range']}}} \\
    {cfg['adv_options']} \\
    -ondemand_build_dh 0

set PRJ_DIR "{proj_dir}"

{import_hdl_cmds}
{import_stim_cmds}

build_design_hierarchy
{design_tcl_cmds}
{fccc_generation_cmd}
set_root -module {{top::work}}

# --------------------------------------------------------------------------
# Import Repository Floorplan and Timing Constraint Assets
# --------------------------------------------------------------------------
import_files -io_pdc {{{constraints['io_pdc']}}}
import_files -fp_pdc {{{constraints['fp_pdc']}}}
import_files -convert_EDN_to_HDL 0 -sdc {{{constraints['top_sdc']}}}

# Derive SDC constraints from the design and configured hardware core blocks
derive_constraints_sdc

# --------------------------------------------------------------------------
# Dynamic Constraint Engine Integration (Self-Healing File Guard)
# --------------------------------------------------------------------------
set synth_constraints [list]
set pr_constraints [list]
set vt_constraints [list]

if {{[file exists "$PRJ_DIR/constraint/top.sdc"]}} {{
    lappend pr_constraints "$PRJ_DIR/constraint/top.sdc"
    lappend vt_constraints "$PRJ_DIR/constraint/top.sdc"
}}
if {{[file exists "$PRJ_DIR/constraint/io/top_io.pdc"]}} {{
    lappend pr_constraints "$PRJ_DIR/constraint/io/top_io.pdc"
}}
if {{[file exists "$PRJ_DIR/constraint/fp/top_fp.pdc"]}} {{
    lappend pr_constraints "$PRJ_DIR/constraint/fp/top_fp.pdc"
}}

if {{[file exists "$PRJ_DIR/constraint/top_derived_constraints.sdc"]}} {{
    lappend synth_constraints "$PRJ_DIR/constraint/top_derived_constraints.sdc"
    lappend pr_constraints "$PRJ_DIR/constraint/top_derived_constraints.sdc"
    lappend vt_constraints "$PRJ_DIR/constraint/top_derived_constraints.sdc"
}}
if {{[file exists "$PRJ_DIR/constraint/top_derived_constraints.ndc"]}} {{
    lappend synth_constraints "$PRJ_DIR/constraint/top_derived_constraints.ndc"
}}

if {{[llength $synth_constraints] > 0}} {{
    set cmd [list organize_tool_files -tool {{SYNTHESIZE}} -module {{top::work}} -input_type {{constraint}}]
    foreach f $synth_constraints {{ lappend cmd -file $f }}
    eval $cmd
}}
if {{[llength $pr_constraints] > 0}} {{
    set cmd [list organize_tool_files -tool {{PLACEROUTE}} -module {{top::work}} -input_type {{constraint}}]
    foreach f $pr_constraints {{ lappend cmd -file $f }}
    eval $cmd
}}
if {{[llength $vt_constraints] > 0}} {{
    set cmd [list organize_tool_files -tool {{VERIFYTIMING}} -module {{top::work}} -input_type {{constraint}}]
    foreach f $vt_constraints {{ lappend cmd -file $f }}
    eval $cmd
}}

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
        print(f"[ERROR] Libero flow automation processing broken: {e}")
        
        # Self-diagnostic log dumper
        script_dir = os.path.dirname(os.path.abspath(tcl_script_path))
        log_path = os.path.join(script_dir, target_name, "top", "simulation", "testbench_presynth_simulation.log")
        
        if os.path.isfile(log_path):
            print("\n" + "="*80)
            print(f"[DIAGNOSTIC] Dumping Native ModelSim Engine Error Log: {log_path}")
            print("="*80)
            try:
                with open(log_path, "r") as log_file:
                    print(log_file.read())
            except Exception as read_err:
                print(f"[WARNING] Could not extract log asset content: {read_err}")
            print("="*80 + "\n")
        else:
            fallback_log = os.path.join(os.getcwd(), "testbench_presynth_simulation.log")
            if os.path.isfile(fallback_log):
                print("\n" + "="*80)
                print(f"[DIAGNOSTIC] Dumping ModelSim Simulation Log File: {fallback_log}")
                print("="*80)
                with open(fallback_log, "r") as log_file:
                    print(log_file.read())
                print("="*80 + "\n")
                
        sys.exit(1)


# ==========================================================================
# MODULE 4: Main Orchestrator Interface Entry Point
# ==========================================================================
def main():
    helper_description = (
        "===============================================================================\n"
        "           Microchip Libero SoC Native Flow Automation Pipeline                \n"
        "===============================================================================\n"
        "Expected Workspace Layout:\n"
        "  ├── src/\n"
        "  │   ├── hdl/                <-- All parallel Verilog design modules\n"
        "  │   ├── stimulus/           <-- Testbenches & .vh parameters\n"
        "  │   ├── constraints/\n"
        "  │   └── tcl/                <-- Hardware IP configurations\n"
        "  └── build/"
    )

    helper_epilog = (
        "Execution Examples:\n"
        "  # 1. Hardware compilation & synthesis mapping flow\n"
        "  python3 build.py --family rtg4 --build\n\n"
        "  # 2. Run Presynth Simulation using native Libero options block\n"
        "  python3 build.py --family rtg4 --sim --tb_top testbench --sim_time 1500ns"
    )

    parser = argparse.ArgumentParser(description=helper_description, epilog=helper_epilog, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--family", required=True, choices=["smartfusion2", "polarfire", "rtg4"], help="Target device architecture family.")
    parser.add_argument("--sim_time", default="1000ns", help="Total simulation runtime window (e.g., 20ms, 1000ns).")
    parser.add_argument("--tb_top", default="testbench", help="Top-level module name identifier referencing your testbench block.")
    parser.add_argument("--libero_path", default="libero", help="Absolute path command pointing to Libero SoC.")
    parser.add_argument("--design_tcl", default=None, help="Specific hardware component IP TCL script name.")

    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument("--build", action="store_true", help="Compile layout logic and generate programming bitstream files. (Default)")
    mode_group.add_argument("--program", action="store_true", help="Execute a complete '--build' processing run, then invoke FlashPro.")
    mode_group.add_argument("--sim", action="store_true", help="Initialize database and run verification using native Libero simulation engine configurations.")
    
    args = parser.parse_args()
    target = args.family.lower()

    mode = "build"
    if args.program: mode = "program"
    elif args.sim: mode = "sim"
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    hdl_dir = os.path.join(script_dir, "src", "hdl")
    constraints_dir = os.path.join(script_dir, "src", "constraints", target)
    build_dir = os.path.join(script_dir, "build")
    tcl_dir = os.path.join(script_dir, "src", "tcl")
    
    target_tcl_dir = os.path.join(tcl_dir, target)
    stim_dir = os.path.join(script_dir, "src", "stimulus")
    
    target_impl_dir = os.path.join(build_dir, target, "top")
    output_tcl = os.path.join(build_dir, f"run_project_{target}.tcl")
    
    os.makedirs(build_dir, exist_ok=True)
    cleanup_workspace(target_impl_dir, f"Libero Project [{target.upper()}]")

    constraints = verify_constraints(constraints_dir)

    design_tcls_active = []
    tcl_dir_active = None

    if args.design_tcl:
        specific_script = args.design_tcl
        if os.path.isdir(target_tcl_dir) and os.path.isfile(os.path.join(target_tcl_dir, specific_script)):
            design_tcls_active = [specific_script]
            tcl_dir_active = target_tcl_dir
            print(f"[INFO] Sourcing user-specified target-specific script: {os.path.join(target, specific_script)}")
        elif os.path.isdir(tcl_dir) and os.path.isfile(os.path.join(tcl_dir, specific_script)):
            design_tcls_active = [specific_script]
            tcl_dir_active = tcl_dir
            print(f"[INFO] Sourcing user-specified general script: {specific_script}")
        else:
            print(f"[ERROR] User-specified design script '{specific_script}' not found.")
            sys.exit(1)
    else:
        if os.path.isdir(target_tcl_dir):
            available_scripts = sorted([
                f for f in os.listdir(target_tcl_dir) 
                if f.endswith('.tcl') 
                and os.path.isfile(os.path.join(target_tcl_dir, f))
                and f != "hdl_source.tcl"
            ])
            if available_scripts:
                design_tcls_active = available_scripts
                tcl_dir_active = target_tcl_dir
                print(f"[INFO] Auto-detected scripts in {target}: {', '.join(design_tcls_active)}")
        
        if not design_tcls_active and os.path.isdir(tcl_dir):
            available_scripts = sorted([
                f for f in os.listdir(tcl_dir) 
                if f.endswith('.tcl') 
                and os.path.isfile(os.path.join(tcl_dir, f))
                and f != "hdl_source.tcl"
            ])
            if available_scripts:
                design_tcls_active = available_scripts
                tcl_dir_active = tcl_dir
                print(f"[INFO] Auto-detected general scripts in src/tcl/: {', '.join(design_tcls_active)}")
    
    if not design_tcls_active:
        print("[INFO] No custom IP/Clock generation scripts detected. Running pure RTL-only sequence.")

    # Generate unified Tcl instruction file and execute Libero interface execution map
    generate_tcl(
        target=target, 
        hdl_dir=hdl_dir, 
        stim_dir=stim_dir, 
        constraints=constraints, 
        output_tcl=output_tcl, 
        mode=mode, 
        tcl_dir=tcl_dir_active, 
        design_tcls=design_tcls_active,
        tb_top=args.tb_top,
        sim_time=args.sim_time
    )
    
    run_libero(args.libero_path, output_tcl, target)
    print(f"[SUCCESS] Native Libero pipeline run completed successfully for target family: {target.upper()} [{mode.upper()}].")


if __name__ == "__main__":
    main()