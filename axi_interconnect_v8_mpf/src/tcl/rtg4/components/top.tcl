# Creating SmartDesign "top"
set sd_name {top}
create_smartdesign -sd_name ${sd_name}

# Disable auto promotion of pins of type 'pad'
auto_promote_pad_pins -promote_all 0

# Create top level Scalar Ports
sd_create_scalar_port -sd_name ${sd_name} -port_name {DEVRST_N} -port_direction {IN} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_DQS_TMATCH_0_IN_0} -port_direction {IN} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_DQS_TMATCH_0_IN} -port_direction {IN} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_DQS_TMATCH_1_IN_0} -port_direction {IN} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_DQS_TMATCH_1_IN} -port_direction {IN} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {ram_a_we} -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {start_read} -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {start_write} -port_direction {IN}

sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_CAS_N_0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_CAS_N} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_CKE_0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_CKE} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_CLK_0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_CLK_N_0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_CLK_N} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_CLK} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_CS_N_0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_CS_N} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_DQS_TMATCH_0_OUT_0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_DQS_TMATCH_0_OUT} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_DQS_TMATCH_1_OUT_0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_DQS_TMATCH_1_OUT} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_ODT_0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_ODT} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_RAS_N_0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_RAS_N} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_RESET_N_0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_RESET_N} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_WE_N_0} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {FDDR_WE_N} -port_direction {OUT} -port_is_pad {1}
sd_create_scalar_port -sd_name ${sd_name} -port_name {GL0} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {axi_busy} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {axi_done} -port_direction {OUT}


# Create top level Bus Ports
sd_create_bus_port -sd_name ${sd_name} -port_name {base_address} -port_direction {IN} -port_range {[31:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {ram_a_addr} -port_direction {IN} -port_range {[7:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {ram_a_wdata} -port_direction {IN} -port_range {[63:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {word_count} -port_direction {IN} -port_range {[15:0]}

sd_create_bus_port -sd_name ${sd_name} -port_name {FDDR_ADDR_0} -port_direction {OUT} -port_range {[15:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {FDDR_ADDR} -port_direction {OUT} -port_range {[15:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {FDDR_BA_0} -port_direction {OUT} -port_range {[2:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {FDDR_BA} -port_direction {OUT} -port_range {[2:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {init_done} -port_direction {OUT} -port_range {[0:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {ram_a_rdata} -port_direction {OUT} -port_range {[63:0]}

sd_create_bus_port -sd_name ${sd_name} -port_name {FDDR_DM_RDQS_0} -port_direction {INOUT} -port_range {[3:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {FDDR_DM_RDQS} -port_direction {INOUT} -port_range {[3:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {FDDR_DQS_0} -port_direction {INOUT} -port_range {[3:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {FDDR_DQS_N_0} -port_direction {INOUT} -port_range {[3:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {FDDR_DQS_N} -port_direction {INOUT} -port_range {[3:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {FDDR_DQS} -port_direction {INOUT} -port_range {[3:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {FDDR_DQ_0} -port_direction {INOUT} -port_range {[31:0]} -port_is_pad {1}
sd_create_bus_port -sd_name ${sd_name} -port_name {FDDR_DQ} -port_direction {INOUT} -port_range {[31:0]} -port_is_pad {1}

# Add AND2_0 instance
sd_instantiate_macro -sd_name ${sd_name} -macro_name {AND2} -instance_name {AND2_0}



# Add AND2_1 instance
sd_instantiate_macro -sd_name ${sd_name} -macro_name {AND2} -instance_name {AND2_1}



# Add axi4_master_if_0 instance
sd_instantiate_hdl_core -sd_name ${sd_name} -hdl_core_name {axi4_master_if} -instance_name {axi4_master_if_0}



# Add COREAXI4INTERCONNECT_C0_0 instance
sd_instantiate_component -sd_name ${sd_name} -component_name {COREAXI4INTERCONNECT_C0} -instance_name {COREAXI4INTERCONNECT_C0_0}



# Add DDR3_EAST_0 instance
sd_instantiate_component -sd_name ${sd_name} -component_name {RTG4FDDRC_INIT_C0} -instance_name {DDR3_EAST_0}



# Add DDR3_WEST_0 instance
sd_instantiate_component -sd_name ${sd_name} -component_name {RTG4FDDRC_INIT_C1} -instance_name {DDR3_WEST_0}



# Add ram_2k_true_dual_port_0 instance
sd_instantiate_hdl_module -sd_name ${sd_name} -hdl_module_name {ram_2k_true_dual_port} -hdl_file {hdl/ram_2k_true_dual_port.v} -instance_name {ram_2k_true_dual_port_0}



# Add RCOSC_50MHZ_0 instance
sd_instantiate_macro -sd_name ${sd_name} -macro_name {RCOSC_50MHZ} -instance_name {RCOSC_50MHZ_0}



# Add reset_synchronizer_0 instance
sd_instantiate_hdl_module -sd_name ${sd_name} -hdl_module_name {reset_synchronizer} -hdl_file {hdl\reset_synchronizer.v} -instance_name {reset_synchronizer_0}



# Add reset_synchronizer_1 instance
sd_instantiate_hdl_module -sd_name ${sd_name} -hdl_module_name {reset_synchronizer} -hdl_file {hdl\reset_synchronizer.v} -instance_name {reset_synchronizer_1}



# Add reset_synchronizer_2 instance
sd_instantiate_hdl_module -sd_name ${sd_name} -hdl_module_name {reset_synchronizer} -hdl_file {hdl\reset_synchronizer.v} -instance_name {reset_synchronizer_2}



# Add RTG4FCCC_C1_0 instance
sd_instantiate_component -sd_name ${sd_name} -component_name {RTG4FCCC_C1} -instance_name {RTG4FCCC_C1_0}



# Add SYSRESET_0 instance
sd_instantiate_macro -sd_name ${sd_name} -macro_name {SYSRESET} -instance_name {SYSRESET_0}



# Add scalar net connections
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_0:A" "SYSRESET_0:POWER_ON_RESET_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_0:B" "RTG4FCCC_C1_0:LOCK" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_0:Y" "reset_synchronizer_0:reset" "reset_synchronizer_1:reset" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_1:A" "DDR3_EAST_0:INIT_DONE" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_1:B" "DDR3_WEST_0:INIT_DONE" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_1:Y" "reset_synchronizer_2:reset" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:ACLK" "DDR3_EAST_0:CLK_BASE" "DDR3_WEST_0:CLK_BASE" "GL0" "RTG4FCCC_C1_0:GL0" "axi4_master_if_0:clk" "ram_2k_true_dual_port_0:clk" "reset_synchronizer_0:clock" "reset_synchronizer_2:clock" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:ARESETN" "axi4_master_if_0:rst_n" "init_done" "reset_synchronizer_2:reset_sync" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:CORE_RESET_N" "DDR3_WEST_0:CORE_RESET_N" "reset_synchronizer_0:reset_sync" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_CAS_N" "FDDR_CAS_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_CKE" "FDDR_CKE" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_CLK" "FDDR_CLK" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_CLK_N" "FDDR_CLK_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_CS_N" "FDDR_CS_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_DQS_TMATCH_0_IN" "FDDR_DQS_TMATCH_0_IN" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_DQS_TMATCH_0_OUT" "FDDR_DQS_TMATCH_0_OUT" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_DQS_TMATCH_1_IN" "FDDR_DQS_TMATCH_1_IN" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_DQS_TMATCH_1_OUT" "FDDR_DQS_TMATCH_1_OUT" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_ODT" "FDDR_ODT" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_RAS_N" "FDDR_RAS_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_RESET_N" "FDDR_RESET_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_WE_N" "FDDR_WE_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:INIT_CLK_50MHZ" "DDR3_WEST_0:INIT_CLK_50MHZ" "RTG4FCCC_C1_0:GL1" "reset_synchronizer_1:clock" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:INIT_RESET_N" "DDR3_WEST_0:INIT_RESET_N" "reset_synchronizer_1:reset_sync" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_CAS_N" "FDDR_CAS_N_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_CKE" "FDDR_CKE_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_CLK" "FDDR_CLK_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_CLK_N" "FDDR_CLK_N_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_CS_N" "FDDR_CS_N_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_DQS_TMATCH_0_IN" "FDDR_DQS_TMATCH_0_IN_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_DQS_TMATCH_0_OUT" "FDDR_DQS_TMATCH_0_OUT_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_DQS_TMATCH_1_IN" "FDDR_DQS_TMATCH_1_IN_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_DQS_TMATCH_1_OUT" "FDDR_DQS_TMATCH_1_OUT_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_ODT" "FDDR_ODT_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_RAS_N" "FDDR_RAS_N_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_RESET_N" "FDDR_RESET_N_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_WE_N" "FDDR_WE_N_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DEVRST_N" "SYSRESET_0:DEVRST_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"RCOSC_50MHZ_0:CLKOUT" "RTG4FCCC_C1_0:RCOSC_50MHZ" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_master_if_0:axi_busy" "axi_busy" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_master_if_0:axi_done" "axi_done" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_master_if_0:ram_b_we" "ram_2k_true_dual_port_0:we_b" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_master_if_0:start_read" "start_read" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_master_if_0:start_write" "start_write" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"ram_2k_true_dual_port_0:we_a" "ram_a_we" }

# Add bus net connections
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_ADDR" "FDDR_ADDR" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_BA" "FDDR_BA" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_DM_RDQS" "FDDR_DM_RDQS" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_DQ" "FDDR_DQ" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_DQS" "FDDR_DQS" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_EAST_0:FDDR_DQS_N" "FDDR_DQS_N" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_ADDR" "FDDR_ADDR_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_BA" "FDDR_BA_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_DM_RDQS" "FDDR_DM_RDQS_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_DQ" "FDDR_DQ_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_DQS" "FDDR_DQS_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"DDR3_WEST_0:FDDR_DQS_N" "FDDR_DQS_N_0" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_master_if_0:base_address" "base_address" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_master_if_0:ram_b_addr" "ram_2k_true_dual_port_0:addr_b" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_master_if_0:ram_b_rdata" "ram_2k_true_dual_port_0:rdata_b" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_master_if_0:ram_b_wdata" "ram_2k_true_dual_port_0:wdata_b" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_master_if_0:word_count" "word_count" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"ram_2k_true_dual_port_0:addr_a" "ram_a_addr" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"ram_2k_true_dual_port_0:rdata_a" "ram_a_rdata" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"ram_2k_true_dual_port_0:wdata_a" "ram_a_wdata" }

# Add bus interface net connections
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:AXI3mslave0" "DDR3_EAST_0:AXI_SLAVE" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:AXI3mslave1" "DDR3_WEST_0:AXI_SLAVE" }
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:AXI4mmaster0" "axi4_master_if_0:BIF_1" }

# Re-enable auto promotion of pins of type 'pad'
auto_promote_pad_pins -promote_all 1
# Save the SmartDesign 
save_smartdesign -sd_name ${sd_name}
# Generate SmartDesign "top"
generate_component -component_name ${sd_name}
