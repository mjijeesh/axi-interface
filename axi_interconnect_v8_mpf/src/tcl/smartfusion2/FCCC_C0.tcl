# Exporting Component Description of FCCC_C0 to TCL
# Family: Smartfusion2
# Part Number: M2S025-VF256
# Create and Configure the core component FCCC_C0

     
        
create_and_configure_core -core_vlnv {Actel:SgCore:FCCC:*} -component_name {FCCC_C0} -params {CLK0_IS_USED:true GL0_IS_USED:true GL0_OUT_0_FREQ:80 PLL_IN_FREQ:50 PLL_IS_USED:true}

