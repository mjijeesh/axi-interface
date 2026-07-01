set_device -family {SmartFusion2} -die {M2S025} -speed {STD} -range {IND}
read_verilog -mode system_verilog {/home/jijeesh/projects/m2s-creative/ddr_test_gui_v1/component/work/FCCC_C0/FCCC_C0_0/FCCC_C0_FCCC_C0_0_FCCC.v}
read_verilog -mode system_verilog {/home/jijeesh/projects/m2s-creative/ddr_test_gui_v1/component/work/FCCC_C0/FCCC_C0.v}
read_verilog -mode system_verilog {/home/jijeesh/projects/m2s-creative/ddr_test_gui_v1/hdl/ram_2k.v}
read_verilog -mode system_verilog {/home/jijeesh/projects/m2s-creative/ddr_test_gui_v1/hdl/system_control.v}
read_verilog -mode system_verilog {/home/jijeesh/projects/m2s-creative/ddr_test_gui_v1/hdl/uart_rx.v}
read_verilog -mode system_verilog {/home/jijeesh/projects/m2s-creative/ddr_test_gui_v1/hdl/uart_tx.v}
read_verilog -mode system_verilog {/home/jijeesh/projects/m2s-creative/ddr_test_gui_v1/hdl/fpga_top.v}
set_top_level {fpga_top}
read_sdc -component {/home/jijeesh/projects/m2s-creative/ddr_test_gui_v1/component/work/FCCC_C0/FCCC_C0_0/FCCC_C0_FCCC_C0_0_FCCC.sdc}
derive_constraints
write_sdc {/home/jijeesh/projects/m2s-creative/ddr_test_gui_v1/constraint/fpga_top_derived_constraints.sdc}
write_ndc {/home/jijeesh/projects/m2s-creative/ddr_test_gui_v1/constraint/fpga_top_derived_constraints.ndc}
write_pdc {/home/jijeesh/projects/m2s-creative/ddr_test_gui_v1/constraint/fp/fpga_top_derived_constraints.pdc}
