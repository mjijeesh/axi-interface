set_component FCCC_C0_FCCC_C0_0_FCCC
# Microchip Technology Inc.
# Date: 2026-Jul-01 12:08:16
#

create_clock -period 20 [ get_pins { CCC_INST/CLK0 } ]
create_generated_clock -multiply_by 16 -divide_by 10 -source [ get_pins { CCC_INST/CLK0 } ] -phase 0 [ get_pins { CCC_INST/GL0 } ]
create_generated_clock -multiply_by 16 -divide_by 16 -source [ get_pins { CCC_INST/CLK0 } ] -phase 0 [ get_pins { CCC_INST/GL1 } ]
