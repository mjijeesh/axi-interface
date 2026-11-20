#JTAG TCK clock creation
create_clock -name {TCK} -period 33.33 -waveform {0 16.665 } [ get_ports { TCK } ]
##SET CLOCK GROUPS - ASYNCHRONOUS CLOCKS##
set_clock_groups -name {REFCLK_P_GRP} -asynchronous -group [ get_clocks { REFCLK_P } ]
set_clock_groups -name {REF_CLK_0_GRP} -asynchronous -group [ get_clocks { REF_CLK_50MHZ } ]
set_clock_groups -name {SGMII_CDR_0_0_CLK_OUT_GRP} -asynchronous -group [ get_clocks { CoreTSE_SYS_0/PF_IOD_CDR_C0_0/PF_LANECTRL_0/I_LANECTRL/CLK_OUT_R } ]
set_clock_groups -name {Y_DIV_GRP} -asynchronous -group [ get_clocks { CoreTSE_SYS_0/PF_IOD_CDR_CCC_C0_0/PF_CLK_DIV_0/I_CD/Y_DIV } ]
set_clock_groups -name {NWC_PLL_OUT0_GRP} -asynchronous -group [ get_clocks { CoreTSE_SYS_0/PF_IOD_CDR_CCC_C0_0/PF_CCC_0/pll_inst_0/OUT0 } ]
set_clock_groups -name {NWC_PLL_OUT1_GRP} -asynchronous -group [ get_clocks { CoreTSE_SYS_0/PF_IOD_CDR_CCC_C0_0/PF_CCC_0/pll_inst_0/OUT1 } ]
set_clock_groups -name {NWC_PLL_OUT2_GRP} -asynchronous -group [ get_clocks { CoreTSE_SYS_0/PF_IOD_CDR_CCC_C0_0/PF_CCC_0/pll_inst_0/OUT2 } ]
set_clock_groups -name {NWC_PLL_OUT3_GRP} -asynchronous -group [ get_clocks { CoreTSE_SYS_0/PF_IOD_CDR_CCC_C0_0/PF_CCC_0/pll_inst_0/OUT3 } ]
set_clock_groups -name {PF_CCC_0_OUT0_GRP} -asynchronous -group [ get_clocks { CLK_RESET_SYS_0/PF_CCC_C0_0/PF_CCC_C0_0/pll_inst_0/OUT0 } ]
# JATG and Mi-V clocks are independent - adding asynchronous clock group
set_clock_groups -name {async_grps1} -asynchronous -group [ get_clocks { CLK_RESET_SYS_0/PF_CCC_C0_0/PF_CCC_C0_0/pll_inst_0/OUT0 } ] -group [ get_clocks { TCK } ]
# Mi-V clock/system clock and DDR AXI clock are independent because CoreAXI4_Interconnect IP takes care of clock domain crossing- adding asynchronous clock group
#set_clock_groups -name {async_grps2} -asynchronous -group [ get_clocks { PF_CCC_0/pll_inst_0/OUT0 } ] -group [ get_clocks { ddr3_subsystem_0/CCC_0/pll_inst_0/OUT1 } ] -group [ get_clocks { TCK } ]
