# Creating SmartDesign "top"
set sd_name {top}
create_smartdesign -sd_name ${sd_name}

# Disable auto promotion of pins of type 'pad'
auto_promote_pad_pins -promote_all 0

# Top-Level Scalar Ports
sd_create_scalar_port -sd_name ${sd_name} -port_name {REF_CLK}          -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {reset_n}          -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {fifo_wclk}        -port_direction {IN}

sd_create_scalar_port -sd_name ${sd_name} -port_name {gen_en}           -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {gen_reset}        -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {gen_random_delay} -port_direction {IN}

sd_create_scalar_port -sd_name ${sd_name} -port_name {stream_en}        -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {soft_rst}         -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {irq_en}           -port_direction {IN}
sd_create_scalar_port -sd_name ${sd_name} -port_name {irq_ack}          -port_direction {IN}

sd_create_scalar_port -sd_name ${sd_name} -port_name {CLK_100}          -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {axi_busy}         -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {axi_err}          -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {mss_irq}          -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {mss_irq_pulse}    -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {fifo_full}        -port_direction {OUT}
sd_create_scalar_port -sd_name ${sd_name} -port_name {fifo_afull}       -port_direction {OUT}

# Top-Level Bus Ports
sd_create_bus_port -sd_name ${sd_name} -port_name {gen_pattern_tag}     -port_direction {IN}  -port_range {[15:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {gen_burst_len}       -port_direction {IN}  -port_range {[15:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {gen_delay_cycles}    -port_direction {IN}  -port_range {[15:0]}

sd_create_bus_port -sd_name ${sd_name} -port_name {base_address}        -port_direction {IN}  -port_range {[31:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {buffer_size}         -port_direction {IN}  -port_range {[31:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {burst_threshold}     -port_direction {IN}  -port_range {[11:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {idle_flush_cycles}   -port_direction {IN}  -port_range {[15:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {irq_chunk_bytes}     -port_direction {IN}  -port_range {[31:0]}

sd_create_bus_port -sd_name ${sd_name} -port_name {gen_words_generated} -port_direction {OUT} -port_range {[31:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {wr_offset}           -port_direction {OUT} -port_range {[31:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {total_bytes_written} -port_direction {OUT} -port_range {[31:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {irq_pending_cnt}     -port_direction {OUT} -port_range {[15:0]}
sd_create_bus_port -sd_name ${sd_name} -port_name {last_irq_offset}     -port_direction {OUT} -port_range {[31:0]}

# Instantiate Components & HDL Modules
sd_instantiate_macro -sd_name ${sd_name} -macro_name {AND2} -instance_name {AND2_0}
sd_instantiate_hdl_module -sd_name ${sd_name} -hdl_module_name {fifo_data_generator} -hdl_file {hdl/fifo_data_generator.v} -instance_name {fifo_data_generator_0}
sd_instantiate_hdl_core -sd_name ${sd_name} -hdl_core_name {axi4_fifo_master} -instance_name {axi4_fifo_master_0}
sd_instantiate_component -sd_name ${sd_name} -component_name {COREFIFO_C0} -instance_name {COREFIFO_C0_0}
sd_instantiate_component -sd_name ${sd_name} -component_name {COREAXI4INTERCONNECT_C0} -instance_name {COREAXI4INTERCONNECT_C0_0}
sd_instantiate_component -sd_name ${sd_name} -component_name {PF_CCC_C0} -instance_name {PF_CCC_C0_0}
sd_connect_pins_to_constant -sd_name ${sd_name} -pin_names {PF_CCC_C0_0:PLL_POWERDOWN_N_0} -value {VCC}
sd_instantiate_component -sd_name ${sd_name} -component_name {PF_SRAM_AHBL_AXI_C0} -instance_name {PF_SRAM_AHBL_AXI_C0_0}
sd_instantiate_component -sd_name ${sd_name} -component_name {PF_SRAM_AHBL_AXI_C1} -instance_name {PF_SRAM_AHBL_AXI_C1_0}
sd_instantiate_hdl_module -sd_name ${sd_name} -hdl_module_name {reset_synchronizer} -hdl_file {hdl/reset_synchronizer.v} -instance_name {reset_synchronizer_1}

# Scalar Net Connections
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_0:A" "reset_n"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_0:B" "PF_CCC_C0_0:PLL_LOCK_0"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"AND2_0:Y" "reset_synchronizer_1:reset"}

sd_connect_pins -sd_name ${sd_name} -pin_names {"CLK_100" "COREAXI4INTERCONNECT_C0_0:ACLK" "COREFIFO_C0_0:RCLOCK" "PF_CCC_C0_0:OUT0_FABCLK_0" "PF_SRAM_AHBL_AXI_C0_0:ACLK" "PF_SRAM_AHBL_AXI_C1_0:ACLK" "axi4_fifo_master_0:clk" "reset_synchronizer_1:clock"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:ARESETN" "COREFIFO_C0_0:RRESET_N" "COREFIFO_C0_0:WRESET_N" "PF_SRAM_AHBL_AXI_C0_0:ARESETN" "PF_SRAM_AHBL_AXI_C1_0:ARESETN" "axi4_fifo_master_0:rst_n" "fifo_data_generator_0:wrst_n" "reset_synchronizer_1:reset_sync"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"PF_CCC_C0_0:REF_CLK_0" "REF_CLK"}

sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:WCLOCK" "fifo_data_generator_0:wclk" "fifo_wclk"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:WE" "fifo_data_generator_0:fifo_we"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:FULL" "fifo_data_generator_0:fifo_full" "fifo_full"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:AFULL" "fifo_afull"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"fifo_data_generator_0:gen_en" "gen_en"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"fifo_data_generator_0:gen_reset" "gen_reset"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"fifo_data_generator_0:random_delay" "gen_random_delay"}

sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:RE" "axi4_fifo_master_0:fifo_re"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:EMPTY" "axi4_fifo_master_0:fifo_empty"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:stream_en" "stream_en"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:soft_rst" "soft_rst"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:irq_en" "irq_en"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:irq_ack" "irq_ack"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:axi_busy" "axi_busy"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:axi_err" "axi_err"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:mss_irq" "mss_irq"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:mss_irq_pulse" "mss_irq_pulse"}

# Bus Net Connections
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:DATA" "fifo_data_generator_0:fifo_wdata"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"fifo_data_generator_0:pattern_tag" "gen_pattern_tag"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"fifo_data_generator_0:burst_len" "gen_burst_len"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"fifo_data_generator_0:delay_cycles" "gen_delay_cycles"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"fifo_data_generator_0:words_generated" "gen_words_generated"}

sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:Q" "axi4_fifo_master_0:fifo_q"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREFIFO_C0_0:RDCNT" "axi4_fifo_master_0:fifo_rdcnt"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:base_address" "base_address"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:buffer_size" "buffer_size"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:burst_threshold" "burst_threshold"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:idle_flush_cycles" "idle_flush_cycles"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:irq_chunk_bytes" "irq_chunk_bytes"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:wr_offset" "wr_offset"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:total_bytes_written" "total_bytes_written"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:irq_pending_cnt" "irq_pending_cnt"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"axi4_fifo_master_0:last_irq_offset" "last_irq_offset"}

# Bus Interface Net Connections
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:AXI4mmaster0" "axi4_fifo_master_0:AXI4_Master"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:AXI4mslave0" "PF_SRAM_AHBL_AXI_C0_0:AXI4_Slave"}
sd_connect_pins -sd_name ${sd_name} -pin_names {"COREAXI4INTERCONNECT_C0_0:AXI4mslave1" "PF_SRAM_AHBL_AXI_C1_0:AXI4_Slave"}

# Re-enable auto promotion of pins of type 'pad'
auto_promote_pad_pins -promote_all 1
save_smartdesign -sd_name ${sd_name}
generate_component -component_name ${sd_name}