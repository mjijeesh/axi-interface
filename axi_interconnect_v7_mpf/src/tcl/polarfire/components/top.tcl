# Creating SmartDesign "top"
set sd_name {top}
create_smartdesign -sd_name ${sd_name}

# Disable auto promotion of pins of type 'pad'
auto_promote_pad_pins -promote_all 0

# Create top level Scalar Ports
sd_create_scalar_port -sd_name ${sd_name} -port_name {REF_CLK} -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {reset_n} -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {start_write} -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {fifo_wclk} -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {fifo_we} -port_direction {IN}

sd_create_scalar_port -sd_name ${sd_name} -port_name {CLK_100} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {axi_busy} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {axi_done} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {fifo_full} -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {fifo_afull} -port_direction {OUT}

# Create top level Bus Ports
sd_create_bus_port -sd_name ${sd_name} -port_name {base_address} -port_direction {IN} -port_range {[31:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {word_count} -port_direction {IN} -port_range {[15:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {fifo_wdata} -port_direction {IN} -port_range {[31:0]}

# Add AND2_0 instance
sd_instantiate_macro -sd_name ${sd_name} -macro_name {AND2} -instance_name {AND2_0}

# Add axi4_fifo_master_0 instance
sd_instantiate_hdl_core -sd_name ${sd_name} -hdl_core_name {axi4_fifo_master} -instance_name {axi4_fifo_master_0}

# Add COREFIFO_C0_0 instance (32-bit write / 64-bit read, Standard Read Mode)
sd_instantiate_component -sd_name ${sd_name} -component_name {COREFIFO_C0} -instance_name {COREFIFO_C0_0}

# Add COREAXI4INTERCONNECT_C0_0 instance
sd_instantiate_component -sd_name ${sd_name} -component_name {COREAXI4INTERCONNECT_C0} -instance_name {COREAXI4INTERCONNECT_C0_0}

# Add PF_CCC_C0_0 instance
sd_instantiate_component -sd_name ${sd_name} -component_name {PF_CCC_C0} -instance_name {PF_CCC_C0_0}
sd_connect_pins_to_constant -sd_name ${sd_name} -pin_names {PF_CCC_C0_0:PLL_POWERDOWN_N_0} -value {VCC}

# Add PF_SRAM_AHBL_AXI_C0_0 instance (64-bit AXI SRAM @ 0x60000000)
sd_instantiate_component -sd_name ${sd_name} -component_name {PF_SRAM_AHBL_AXI_C0} -instance_name {PF_SRAM_AHBL_AXI_C0_0}

# Add PF_SRAM_AHBL_AXI_C1_0 instance (32-bit AXI SRAM @ 0x80000000)
sd_instantiate_component -sd_name ${sd_name} -component_name {PF_SRAM_AHBL_AXI_C1} -instance_name {PF_SRAM_AHBL_AXI_C1_0}

# Add reset_synchronizer_1 instance
sd_instantiate_hdl_module -sd_name ${sd_name} -hdl_module_name {reset_synchronizer} -hdl_file {hdl/reset_synchronizer.v} -instance_name {reset_synchronizer_1}

# Add scalar net connections
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_0:A" "reset_n"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_0:B" "PF_CCC_C0_0:PLL_LOCK_0"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_0:Y" "reset_synchronizer_1:reset"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"CLK_100" "COREAXI4INTERCONNECT_C0_0:ACLK" "COREFIFO_C0_0:RCLOCK" "PF_CCC_C0_0:OUT0_FABCLK_0" "PF_SRAM_AHBL_AXI_C0_0:ACLK" "PF_SRAM_AHBL_AXI_C1_0:ACLK" "axi4_fifo_master_0:clk" "reset_synchronizer_1:clock"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:ARESETN" "COREFIFO_C0_0:RRESET_N" "COREFIFO_C0_0:WRESET_N" "PF_SRAM_AHBL_AXI_C0_0:ARESETN" "PF_SRAM_AHBL_AXI_C1_0:ARESETN" "axi4_fifo_master_0:rst_n" "reset_synchronizer_1:reset_sync"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"PF_CCC_C0_0:REF_CLK_0" "REF_CLK"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:WCLOCK" "fifo_wclk"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:WE" "fifo_we"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:FULL" "fifo_full"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:AFULL" "fifo_afull"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:RE" "axi4_fifo_master_0:fifo_re"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:EMPTY" "axi4_fifo_master_0:fifo_empty"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:axi_busy" "axi_busy"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:axi_done" "axi_done"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:start_write" "start_write"}

# Add bus net connections
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:DATA" "fifo_wdata"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:Q" "axi4_fifo_master_0:fifo_q"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:RDCNT" "axi4_fifo_master_0:fifo_rdcnt"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:base_address" "base_address"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:word_count" "word_count"}

# Add bus interface net connections
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:AXI4mmaster0" "axi4_fifo_master_0:AXI4_Master"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:AXI4mslave0" "PF_SRAM_AHBL_AXI_C0_0:AXI4_Slave"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:AXI4mslave1" "PF_SRAM_AHBL_AXI_C1_0:AXI4_Slave"}

# Re-enable auto promotion of pins of type 'pad'
auto_promote_pad_pins -promote_all 1
# Save the SmartDesign
save_smartdesign -sd_name ${sd_name}
# Generate SmartDesign "top"
generate_component -component_name ${sd_name}