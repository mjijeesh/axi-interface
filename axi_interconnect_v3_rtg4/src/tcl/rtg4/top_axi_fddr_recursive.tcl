#This Tcl file sources other Tcl files to build the design(on which recursive export is run) in a bottom-up fashion

#Sourcing the Tcl file in which all the HDL source files used in the design are imported or linked
source hdl_source.tcl
build_design_hierarchy

#Sourcing the Tcl files in which HDL+ core definitions are created for HDL modules
source components/axi4_master_if.tcl 
build_design_hierarchy

#Sourcing the Tcl files for creating individual components under the top level
source components/COREAXI4INTERCONNECT_C0.tcl 
source components/FDDRC_With_INIT.tcl 
source components/RTG4FCCC_C1.tcl 
source components/RTG4_SRAM_AHBL_AXI_C0.tcl 
source components/top_axi_fddr.tcl 
build_design_hierarchy
