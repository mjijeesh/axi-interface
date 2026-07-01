# Microchip Technology Inc.
# Date: 2026-Jul-01 14:44:34
# This file was generated based on the following SDC source files:
#   /home/jijeesh/projects/m2s-creative/ddr_test_gui_v1/component/work/FCCC_C0/FCCC_C0_0/FCCC_C0_FCCC_C0_0_FCCC.sdc
# *** Any modifications to this file will be lost if derived constraints is re-run. ***
#

create_clock -name {clk_50mhz} -period 20 [ get_ports { clk_50mhz } ]
create_generated_clock -name {pll_inst/FCCC_C0_0/GL0} -multiply_by 16 -divide_by 10 -source [ get_pins { pll_inst/FCCC_C0_0/CCC_INST/CLK0 } ] -phase 0 [ get_pins { pll_inst/FCCC_C0_0/CCC_INST/GL0 } ]
