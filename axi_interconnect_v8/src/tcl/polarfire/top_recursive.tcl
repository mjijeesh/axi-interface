# This Tcl file sources other Tcl files to build the design in a bottom-up fashion

# 1. Import/link HDL source files
source hdl_source.tcl
build_design_hierarchy

# 2. Package HDL+ core definitions
source components/axi4_fifo_master.tcl
build_design_hierarchy

# 3. Create individual components under the top level
source components/COREAXI4INTERCONNECT_C0.tcl
source components/PF_CCC_C0.tcl
source components/PF_SRAM_AHBL_AXI_C0.tcl
source components/PF_SRAM_AHBL_AXI_C1.tcl
source components/COREFIFO_C0.tcl

# 4. Assemble and generate SmartDesign "top"
source components/top.tcl
build_design_hierarchy

# 5. Attach custom grouped waveform script (wave.do) to ModelSim/QuestaSim run.do
set script_dir   [file dirname [file normalize [info script]]]
set wave_do_file [file normalize [file join $script_dir "stimulus" "wave.do"]]

if {[file exists $wave_do_file]} {
    set_modelsim_options \
        -use_automatic_do_file true \
        -include_do_file true \
        -included_do_file $wave_do_file \
        -display_dut_wave 0 \
        -sim_runtime {1000us}
}