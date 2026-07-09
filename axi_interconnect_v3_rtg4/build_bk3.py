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
  - Source Space:          src/hdl/, src/stimulus/, src/constraints/, src/tcl/
                           (General scripts in src/tcl/, target-specific in src/tcl/<target_family>/)
  - Libero Project Space:  build/<target_family>/top/
  - Simulation Workspace:  build/<target_family>/sim/
"""

import os
import argparse
import subprocess
import sys
import shutil
import re

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


def get_sorted_generated_components(proj_dir):
    """
    Recursively scans the Libero component directory to compile generated modules.
    Excludes physical primitives wrappers and include-only files to avoid double-compilation namespaces.
    """
    gen_v_files = []
    
    # Exclude files that are parameter-only headers and internal IP regression testbenches
    exclude_files = ["coreparameters.v", "parameters.v", "coreparameters_tgi.v"]
    exclude_dirs = ["/test/", "/testbench/"]
    
    # 1. Scan component/work/ for SmartDesigns and Wrappers
    comp_work_dir = os.path.join(proj_dir, "component", "work")
    if os.path.isdir(comp_work_dir):
        for root, _, files in os.walk(comp_work_dir):
            if any(ed in root.replace(os.sep, "/") for ed in exclude_dirs):
                continue
            for file in files:
                if file.endswith('.v'):
                    if file in exclude_files:
                        continue
                    gen_v_files.append(os.path.join(root, file))
                    
    # 2. Scan component/Actel/DirectCore/ for Soft IP Cores (Interconnects, Bridges, Controllers)
    comp_actel_dir = os.path.join(proj_dir, "component", "Actel", "DirectCore")
    if os.path.isdir(comp_actel_dir):
        for root, _, files in os.walk(comp_actel_dir):
            if any(ed in root.replace(os.sep, "/") for ed in exclude_dirs):
                continue
            for file in files:
                if file.endswith('.v'):
                    if file in exclude_files:
                        continue
                    gen_v_files.append(os.path.join(root, file))

    # Sorting deepest files first places leaf sub-modules before parent wrappers.
    gen_v_files.sort(key=lambda path: len(path.replace(os.sep, "/").split("/")), reverse=True)
    return gen_v_files


def get_include_dirs(comp_dir):
    """Recursively finds all subdirectories containing .vh or .h headers, or EDA standard paths."""
    inc_dirs = set()
    if os.path.isdir(comp_dir):
        for root, _, files in os.walk(comp_dir):
            if any(f.endswith('.vh') or f.endswith('.h') for f in files):
                inc_dirs.add(root)
            if root.endswith('core') or root.endswith('rtl') or root.endswith('vlog'):
                inc_dirs.add(root)
    return sorted(list(inc_dirs))


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
def generate_tcl(target, hdl_dir, stim_dir, constraints, output_tcl, mode, tcl_dir=None, design_tcls=None, project_exists=False):
    """Constructs an absolute-path based Tcl scripting engine to build the Libero project."""
    cfg = DEVICE_DB[target]
    
    # RESOLVED CRITICAL EDA BUG: Resolved proj_dir to an ABSOLUTE path. This prevents
    # Libero from falling back to bin64 installation directories if launcher paths have spaces.
    proj_dir = os.path.abspath(f"./build/{target}/top").replace(os.sep, "/")
    
    hdl_source_files = [os.path.join(hdl_dir, f) for f in os.listdir(hdl_dir) if f.endswith('.v')]
    import_hdl_cmds = "\n".join([f'import_files -hdl_source {{{f.replace(os.sep, "/")}}}' for f in hdl_source_files])
    
    import_stim_cmds = ""
    if os.path.isdir(stim_dir):
        # STIMULUS UPGRADE: Find Verilog stimulus files (.v) along with header files (.vh, .h) 
        # so Libero imports them cleanly into the project's internal stimulus folder.
        stim_source_files = []
        for f in os.listdir(stim_dir):
            if f.endswith('.v') or f.endswith('.vh') or f.endswith('.h'):
                stim_source_files.append(os.path.join(stim_dir, f))
                
        if stim_source_files:
            import_stim_cmds = "\n# Import stimulus Testbench Files into Libero\n" + "\n".join(
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

    # Assemble Sourcing Instructions for pre-created design components (e.g. DDR, FCCC)
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

    # Book or append logic depending on project retention state
    if project_exists:
        project_init_cmd = f"open_project -file {{{proj_dir}/top.prjx}}"
        design_tcl_cmds = ""      # Skip re-instantiating cores as they already exist in the database
        fccc_generation_cmd = ""  # Skip FCCC generation to prevent naming collisions
    else:
        project_init_cmd = f"""new_project \\
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
    -ondemand_build_dh 0"""

        # Basic FCCC generation falls back here only if custom design scripts were NOT supplied
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
{project_init_cmd}

{import_hdl_cmds}
{import_stim_cmds}

build_design_hierarchy
{design_tcl_cmds}
{fccc_generation_cmd}
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
def generate_modelsim_macro(target, hdl_files, proj_stim_dir, stim_dir, build_dir, tb_top, sim_time, precompiled_base, do_file_path, console_mode, vcd_mode):
    """Dynamically writes an optimized macro script (run.do) pulling assets out of the Libero database."""
    cfg = DEVICE_DB[target]
    
    proj_dir_abs = os.path.abspath(os.path.join(build_dir, target, "top")).replace(os.sep, "/")
    precompiled_base_clean = precompiled_base.replace(os.sep, "/")
    sim_workspace_dir_abs = os.path.abspath(os.path.join(build_dir, target, "sim")).replace(os.sep, "/")
    
    # Path to Libero's native simulation directory and output scripts
    libero_run_do = os.path.join(build_dir, target, "top", "simulation", "run.do")
    
    error_trapping = "onerror {quit -force}\nonbreak {quit -force}\n" if console_mode else ""
    vsim_generics = "-gRAM_ES_BEHAVIOR=1" if target == "rtg4" else ""
    vcd_cmds = f"\nvcd file {tb_top}.vcd\nvcd add -r /{tb_top}/*\n" if vcd_mode else ""
    
    if console_mode:
        exec_cmds = f"\n{vcd_cmds}log -r /*\nrun {sim_time}\nquit -force\n"
    else:
        exec_cmds = f"\n{vcd_cmds}add wave /{tb_top}/*\nrun {sim_time}\n"

    # STRATEGY 1: PARSE AND REMAP LIBERO'S GENERATED RUN.DO (100% COMPLIANT CLONE)
    if os.path.isfile(libero_run_do):
        print(f"[INFO] Aligning simulation macro with Libero's generated run.do: {libero_run_do}")
        do_lines = []
        do_lines.append(f"{error_trapping}cd \"{sim_workspace_dir_abs}\"")
        
        with open(libero_run_do, "r") as lf:
            skip_remaining = False
            for line in lf:
                line_stripped = line.strip()
                if skip_remaining:
                    continue
                
                # Replace the PROJECT_DIR assignment line to point to our absolute sandbox
                if line_stripped.startswith("quietly set PROJECT_DIR"):
                    do_lines.append(f'quietly set PROJECT_DIR "{proj_dir_abs}"')
                
                # COMPILER ERROR FIXED: Skip direct standalone compilation of include-only parameter headers
                # and core-internal self-test templates. They are compiled inline inside parent modules.
                elif line_stripped.startswith("vlog") and any(ex in line_stripped for ex in ["coreparameters.v", "parameters.v", "coreparameters_tgi.v", "/test/", "/testbench/"]):
                    filename = line_stripped.split()[-1].replace('"', '').split('/')[-1]
                    print(f"[INFO] Skipping standalone compilation of include-only/test file: {filename}")
                    continue
                
                # Intercept the vsim command to adapt search libraries and testbench naming
                elif line_stripped.startswith("vsim "):
                    # Extract all mapped -L flags from Libero's run.do
                    libs = re.findall(r'-L \S+', line_stripped)
                    # Force COREAPB3_LIB search paths if not parsed
                    if "-L COREAPB3_LIB" not in line_stripped:
                        libs.append("-L COREAPB3_LIB")
                    lib_str = " ".join(libs)
                    
                    custom_vsim = f'vsim -voptargs="+acc" {lib_str} -t 1ps {vsim_generics} presynth.{tb_top}'
                    do_lines.append(custom_vsim)
                    skip_remaining = True # Custom wave adds/run control appended separately
                
                # Dynamic remapping of generated libraries (like COREAPB3_LIB) to the presynth build-folder
                elif line_stripped.startswith("vmap ") and "presynth" not in line_stripped and "RTG4" not in line_stripped:
                    parts = line_stripped.split()
                    if len(parts) >= 3:
                        do_lines.append(f'vmap {parts[1]} presynth')
                else:
                    do_lines.append(line)
                    
        do_content = "\n".join(do_lines) + exec_cmds

    # STRATEGY 2: FALLBACK TO SYSTEM SCANNER (IF RUN.DO HAS NOT BEEN GENERATED)
    else:
        print("[INFO] Libero simulation script not found. Running fallback directory scan.")
        do_content = f"""{error_trapping}cd "{sim_workspace_dir_abs}"
quietly set ACTELLIBNAME {cfg['lib_name']}
quietly set PROJECT_DIR "{proj_dir_abs}"

if {{[file exists presynth/_info]}} {{
   echo "INFO: Simulation library presynth already exists"
}} else {{
   file delete -force presynth 
   vlib presynth
}}
vmap presynth presynth
vmap work presynth
vmap COREAPB3_LIB presynth
vmap {cfg['lib_name']} "{precompiled_base_clean}/{cfg['vlog_lib_dir']}"
"""
        # Dynamic extraction of soft IPs and SmartDesigns
        comp_dir = os.path.join(build_dir, target, "top")
        gen_comp_files = get_sorted_generated_components(comp_dir)
        
        # Scan and compile target header includes
        inc_dirs = get_include_dirs(os.path.join(comp_dir, "component"))
        inc_cmds = ""
        for d in inc_dirs:
            rel_path = os.path.relpath(d, os.path.join(build_dir, target, "top")).replace(os.sep, "/")
            inc_cmds += f' "+incdir+${{PROJECT_DIR}}/{rel_path}"'
        
        if gen_comp_files:
            do_content += "\n# Compile Generated SmartDesign / Core IP Components (Bottom-Up)\n"
            for f in gen_comp_files:
                rel_to_proj = os.path.relpath(f, os.path.join(build_dir, target, "top")).replace(os.sep, "/")
                do_content += f'vlog{inc_cmds} -sv -work presynth "${{PROJECT_DIR}}/{rel_to_proj}"\n'

        do_content += "\n# Compile Project HDL Source Files\n"
        for f in hdl_files:
            rel_to_proj = os.path.relpath(f, os.path.join(build_dir, target, "top")).replace(os.sep, "/")
            do_content += f'vlog{inc_cmds} -sv -work presynth "${{PROJECT_DIR}}/{rel_to_proj}"\n'
            
        if os.path.isdir(proj_stim_dir):
            do_content += "\n# Compile Project Testbench Files\n"
            src_stim_abs = os.path.abspath(stim_dir).replace(os.sep, "/")
            for f in sorted(os.listdir(proj_stim_dir)):
                if f.endswith('.v'):
                    do_content += f'vlog{inc_cmds} "+incdir+${{PROJECT_DIR}}/stimulus" "+incdir+{src_stim_abs}" -sv -work presynth "${{PROJECT_DIR}}/stimulus/{f}"\n'
        
        do_content += f"""
vsim -voptargs="+acc" -L {cfg['lib_name']} -L presynth -L COREAPB3_LIB -t 1ps {vsim_generics} presynth.{tb_top}
"""
        do_content += exec_cmds

    with open(do_file_path, "w") as f:
        f.write(do_content)
    print(f"[INFO] Standalone project-linked macro written to: {do_file_path}")


def run_modelsim(modelsim_path, do_file_path, console_mode, sim_workspace_dir):
    """Invokes ModelSim/Questa using subprocess executing directly within the target sim/ directory boundary."""
    print(f"[INFO] Launching ModelSim Engine Wrapper Axis inside: {sim_workspace_dir}")
    
    if console_mode:
        sim_cmd = [modelsim_path, "-c", "-batch", "-do", do_file_path]
    else:
        sim_cmd = [modelsim_path, "-gui", "-do", do_file_path]
        
    try:
        subprocess.run(sim_cmd, check=True, cwd=sim_workspace_dir)
    except FileNotFoundError:
        print(f"[ERROR] Failed to locate ModelSim binary file link at path: '{modelsim_path}'.")
        sys.exit(1)


# ==========================================================================
# MODULE 5: Main Orchestrator Interface Entry Point
# ==========================================================================
def main():
    helper_description = (
        "===============================================================================\n"
        "         Microchip Libero SoC & ModelSim Modular Automation Pipeline          \n"
        "===============================================================================\n"
        "Expected Workspace Layout:\n"
        "  ├── src/\n"
        "  │   ├── hdl/                <-- All parallel Verilog design modules\n"
        "  │   ├── stimulus/           <-- Testbenches and external memory models\n"
        "  │   ├── constraints/\n"
        "  │   └── tcl/                <-- Recursive hardware build script folders\n"
        "  └── build/"
    )

    helper_epilog = (
        "Execution Examples:\n"
        "  # 1. Source all .tcl scripts found in src/tcl/rtg4/ automatically (Default)\n"
        "  python3 build.py --family rtg4 --build\n\n"
        "  # 2. Run simulation with target-specific automated IP imports\n"
        "  python3 build.py --family rtg4 --sim\n\n"
        "  # 3. Force rebuild of Libero project database from scratch\n"
        "  python3 build.py --family rtg4 --sim --clean"
    )

    # RESOLVED CRITICAL EDA BUG: Set allow_abbrev=False to prevent argparse from 
    # matching the partial mode-flag '--sim' to the '--sim_time' option block.
    parser = argparse.ArgumentParser(
        description=helper_description, 
        epilog=helper_epilog, 
        formatter_class=argparse.RawDescriptionHelpFormatter,
        allow_abbrev=False
    )
    parser.add_argument("--family", required=True, choices=["smartfusion2", "polarfire", "rtg4"], help="Target device architecture family.")
    parser.add_argument("--sim_time", default="150us", help="Total simulation runtime limit window (e.g., 150us, 1000ns).")
    parser.add_argument("--tb_top", default="tb_top_axi", help="Module name string identifier referencing your testbench block.")
    parser.add_argument("--libero_path", default="libero", help="Absolute path command pointing to Libero SoC.")
    parser.add_argument("--modelsim_path", default="vsim", help="Absolute path command pointing to ModelSim/Questa 'vsim'.")
    parser.add_argument("--precompiled_base", default="/opt/microchip/Libero_SoC_2025.2/Libero_SoC/Designer/lib/modelsimpro/precompiled/vlog", help="Precompiled vendor primitives maps base folder directory.")
    parser.add_argument("--console", action="store_true", help="Execute simulation directly inside the command line console (Text Only).")
    parser.add_argument("--vcd", action="store_true", help="Generate a standard .vcd signal dump file for post-processing view loops.")
    parser.add_argument("--design_tcl", default=None, help="Specific hardware component IP TCL script name. If omitted, ALL scripts are run by default.")
    parser.add_argument("--clean", action="store_true", help="Clean and force full recreation of the Libero project database.")

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
    
    # HIGH-PRIORITY USER WARNING: If the workspace folder name has spaces, warn the user.
    if " " in script_dir:
        print("\n" + "!" * 80)
        print("[WARNING] Space character detected in active workspace directory path:")
        print(f"          '{script_dir}'")
        print("[WARNING] Microchip Libero's native bash wrapper scripts (e.g. line 259) contain")
        print("          unquoted directory variables. It is highly recommended that you rename")
        print("          your directory to remove spaces to prevent launcher path failures.")
        print("!" * 80 + "\n")
        
    hdl_dir = os.path.join(script_dir, "src", "hdl")
    constraints_dir = os.path.join(script_dir, "src", "constraints", target)
    build_dir = os.path.join(script_dir, "build")
    tcl_dir = os.path.join(script_dir, "src", "tcl")
    
    # Establish target-specific subdirectory path inside src/tcl/
    target_tcl_dir = os.path.join(tcl_dir, target)
    
    stim_dir = os.path.join(script_dir, "src", "stimulus")
    if not os.path.isdir(stim_dir):
        stim_dir = os.path.join(script_dir, "src", "stimilas")
    
    target_impl_dir = os.path.join(build_dir, target, "top")
    sim_workspace_dir = os.path.join(build_dir, target, "sim")
    
    output_tcl = os.path.join(build_dir, f"run_project_{target}.tcl")
    do_file_path = os.path.join(sim_workspace_dir, "run.do")
    
    # Initialize workspace structure safely
    os.makedirs(build_dir, exist_ok=True)
    
    # PROJECT RETENTION ALGORITHM: Detect if the Libero database project file (*.prjx) already exists
    prjx_path = os.path.join(target_impl_dir, "top.prjx")
    project_exists = os.path.isfile(prjx_path)
    should_clean = args.clean or not project_exists

    if should_clean:
        cleanup_workspace(target_impl_dir, f"Libero Project [{target.upper()}]")
    else:
        print(f"[INFO] Existing Libero project database found at '{target_impl_dir}'. Bypassing full project recreation.")
        
    if mode == "sim":
        cleanup_workspace(sim_workspace_dir, "QuestaSim Engine")
        os.makedirs(sim_workspace_dir, exist_ok=True)

    constraints = verify_constraints(constraints_dir)

    # Validate and enable custom TCL design execution BY DEFAULT
    design_tcls_active = []
    tcl_dir_active = None

    if args.design_tcl:
        # If the user explicitly requested a single Tcl script via the CLI
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
        # DEFAULT BEHAVIOR: Auto-detect and source ALL .tcl files directly in the directory
        # (Excluding hdl_source.tcl helper script to prevent duplicate runs)
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
                print(f"[INFO] Auto-detected and sourcing ALL target-specific scripts in {target}: {', '.join(design_tcls_active)}")
        
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
                print(f"[INFO] Auto-detected and sourcing ALL general scripts in src/tcl/: {', '.join(design_tcls_active)}")
    
    if not design_tcls_active:
        print("[INFO] No custom IP/Clock generation scripts detected. Running pure RTL-only sequence.")

    # Step 1: Run Libero project generation to import HDL, Testbenches, and custom TCL components
    # Pass 'project_exists' to ensure we call 'open_project' instead of 'new_project' and bypass redundant core creation
    generate_tcl(target, hdl_dir, stim_dir, constraints, output_tcl, mode, tcl_dir_active, design_tcls_active, project_exists=(not should_clean))
    run_libero(args.libero_path, output_tcl, target)

    # Step 2: Handle isolated simulation out of build/<target>/sim workspace parameters
    if mode == "sim":
        proj_hdl_dir = os.path.join(build_dir, target, "top", "hdl")
        proj_stim_dir = os.path.join(build_dir, target, "top", "stimulus")
        
        hdl_files = get_sorted_project_hdl(proj_hdl_dir)

        generate_modelsim_macro(target, hdl_files, proj_stim_dir, stim_dir, build_dir, args.tb_top, args.sim_time, args.precompiled_base, do_file_path, args.console, args.vcd)
        run_modelsim(args.modelsim_path, do_file_path, args.console, sim_workspace_dir)
    else:
        print(f"[SUCCESS] Hardware design build compilation successfully finished for target family: {target}.")


if __name__ == "__main__":
    main()