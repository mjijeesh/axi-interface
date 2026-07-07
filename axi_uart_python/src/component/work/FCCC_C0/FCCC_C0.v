//////////////////////////////////////////////////////////////////////
// Created by SmartDesign Wed Jul  1 12:08:16 2026
// Version: 2025.2 2025.2.0.14
//////////////////////////////////////////////////////////////////////

`timescale 1ns / 100ps

//////////////////////////////////////////////////////////////////////
// Component Description (Tcl) 
//////////////////////////////////////////////////////////////////////
/*
# Exporting Component Description of FCCC_C0 to TCL
# Family: SmartFusion2
# Part Number: M2S025-VF256I
# Create and Configure the core component FCCC_C0
create_and_configure_core -core_vlnv {Actel:SgCore:FCCC:2.0.201} -component_name {FCCC_C0} -params {\
"ADVANCED_TAB_CHANGED:false"  \
"CLK0_IS_USED:true"  \
"CLK0_PAD_IS_USED:false"  \
"CLK1_IS_USED:false"  \
"CLK1_PAD_IS_USED:false"  \
"CLK2_IS_USED:false"  \
"CLK2_PAD_IS_USED:false"  \
"CLK3_IS_USED:false"  \
"CLK3_PAD_IS_USED:false"  \
"DYN_CONF_IS_USED:false"  \
"GL0_BP_IN_0_FREQ:100"  \
"GL0_BP_IN_0_SRC:IO_HARDWIRED_0"  \
"GL0_BP_IN_1_FREQ:100"  \
"GL0_BP_IN_1_SRC:IO_HARDWIRED_0"  \
"GL0_FREQUENCY_LOCKED:false"  \
"GL0_IN_0_SRC:PLL"  \
"GL0_IN_1_SRC:UNUSED"  \
"GL0_IS_INVERTED:false"  \
"GL0_IS_USED:true"  \
"GL0_OUT_0_FREQ:80"  \
"GL0_OUT_1_FREQ:50"  \
"GL0_OUT_IS_GATED:false"  \
"GL0_PLL_IN_0_PHASE:0"  \
"GL0_PLL_IN_1_PHASE:0"  \
"GL1_BP_IN_0_FREQ:100"  \
"GL1_BP_IN_0_SRC:IO_HARDWIRED_0"  \
"GL1_BP_IN_1_FREQ:100"  \
"GL1_BP_IN_1_SRC:IO_HARDWIRED_0"  \
"GL1_FREQUENCY_LOCKED:false"  \
"GL1_IN_0_SRC:PLL"  \
"GL1_IN_1_SRC:UNUSED"  \
"GL1_IS_INVERTED:false"  \
"GL1_IS_USED:true"  \
"GL1_OUT_0_FREQ:50"  \
"GL1_OUT_1_FREQ:50"  \
"GL1_OUT_IS_GATED:false"  \
"GL1_PLL_IN_0_PHASE:0"  \
"GL1_PLL_IN_1_PHASE:0"  \
"GL2_BP_IN_0_FREQ:100"  \
"GL2_BP_IN_0_SRC:IO_HARDWIRED_0"  \
"GL2_BP_IN_1_FREQ:100"  \
"GL2_BP_IN_1_SRC:IO_HARDWIRED_0"  \
"GL2_FREQUENCY_LOCKED:false"  \
"GL2_IN_0_SRC:PLL"  \
"GL2_IN_1_SRC:UNUSED"  \
"GL2_IS_INVERTED:false"  \
"GL2_IS_USED:false"  \
"GL2_OUT_0_FREQ:100"  \
"GL2_OUT_1_FREQ:50"  \
"GL2_OUT_IS_GATED:false"  \
"GL2_PLL_IN_0_PHASE:0"  \
"GL2_PLL_IN_1_PHASE:0"  \
"GL3_BP_IN_0_FREQ:100"  \
"GL3_BP_IN_0_SRC:IO_HARDWIRED_0"  \
"GL3_BP_IN_1_FREQ:100"  \
"GL3_BP_IN_1_SRC:IO_HARDWIRED_0"  \
"GL3_FREQUENCY_LOCKED:false"  \
"GL3_IN_0_SRC:PLL"  \
"GL3_IN_1_SRC:UNUSED"  \
"GL3_IS_INVERTED:false"  \
"GL3_IS_USED:false"  \
"GL3_OUT_0_FREQ:100"  \
"GL3_OUT_1_FREQ:50"  \
"GL3_OUT_IS_GATED:false"  \
"GL3_PLL_IN_0_PHASE:0"  \
"GL3_PLL_IN_1_PHASE:0"  \
"GPD0_IS_USED:true"  \
"GPD0_NOPIPE_RSTSYNC:true"  \
"GPD0_SYNC_STYLE:G3STYLE_AND_LOCK_RSTSYNC"  \
"GPD1_IS_USED:true"  \
"GPD1_NOPIPE_RSTSYNC:true"  \
"GPD1_SYNC_STYLE:G3STYLE_AND_LOCK_RSTSYNC"  \
"GPD2_IS_USED:false"  \
"GPD2_NOPIPE_RSTSYNC:true"  \
"GPD2_SYNC_STYLE:G3STYLE_AND_NO_LOCK_RSTSYNC"  \
"GPD3_IS_USED:false"  \
"GPD3_NOPIPE_RSTSYNC:true"  \
"GPD3_SYNC_STYLE:G3STYLE_AND_NO_LOCK_RSTSYNC"  \
"GPD_EXPOSE_RESETS:false"  \
"GPD_SYNC_STYLE:G3STYLE_AND_LOCK_RSTSYNC"  \
"INIT:0000007FB8000044574000F18C6309C231839DF00404201400F01"  \
"IO_HARDWIRED_0_IS_DIFF:false"  \
"IO_HARDWIRED_1_IS_DIFF:false"  \
"IO_HARDWIRED_2_IS_DIFF:false"  \
"IO_HARDWIRED_3_IS_DIFF:false"  \
"MODE_10V:false"  \
"NGMUX0_HOLD_IS_USED:false"  \
"NGMUX0_IS_USED:false"  \
"NGMUX1_HOLD_IS_USED:false"  \
"NGMUX1_IS_USED:false"  \
"NGMUX2_HOLD_IS_USED:false"  \
"NGMUX2_IS_USED:false"  \
"NGMUX3_HOLD_IS_USED:false"  \
"NGMUX3_IS_USED:false"  \
"NGMUX_EXPOSE_HOLD:false"  \
"PLL_DELAY:0"  \
"PLL_EXPOSE_BYPASS:false"  \
"PLL_EXPOSE_RESETS:false"  \
"PLL_EXT_FB_GL:EXT_FB_GL0"  \
"PLL_FB_SRC:CCC_INTERNAL"  \
"PLL_IN_FREQ:50"  \
"PLL_IN_SRC:CORE_0"  \
"PLL_IS_USED:true"  \
"PLL_LOCK_IND:1024"  \
"PLL_LOCK_WND:32000"  \
"PLL_SSM_DEPTH:0.5"  \
"PLL_SSM_ENABLE:false"  \
"PLL_SSM_FREQ:40"  \
"PLL_SUPPLY_VOLTAGE:25_V"  \
"PLL_VCO_TARGET:700"  \
"RCOSC_1MHZ_IS_USED:false"  \
"RCOSC_25_50MHZ_IS_USED:false"  \
"VCOFREQUENCY:800.000"  \
"XTLOSC_IS_USED:false"  \
"Y0_IS_USED:false"  \
"Y1_IS_USED:false"  \
"Y2_IS_USED:false"  \
"Y3_IS_USED:false"   }
# Exporting Component Description of FCCC_C0 to TCL done
*/

// FCCC_C0
module FCCC_C0(
    // Inputs
    CLK0,
    // Outputs
    GL0,
    GL1,
    LOCK
);

//--------------------------------------------------------------------
// Input
//--------------------------------------------------------------------
input  CLK0;
//--------------------------------------------------------------------
// Output
//--------------------------------------------------------------------
output GL0;
output GL1;
output LOCK;
//--------------------------------------------------------------------
// Nets
//--------------------------------------------------------------------
wire   CLK0;
wire   GL0_net_0;
wire   GL1_net_0;
wire   LOCK_net_0;
wire   GL0_net_1;
wire   GL1_net_1;
wire   LOCK_net_1;
//--------------------------------------------------------------------
// TiedOff Nets
//--------------------------------------------------------------------
wire   GND_net;
wire   [7:2]PADDR_const_net_0;
wire   [7:0]PWDATA_const_net_0;
//--------------------------------------------------------------------
// Constant assignments
//--------------------------------------------------------------------
assign GND_net            = 1'b0;
assign PADDR_const_net_0  = 6'h00;
assign PWDATA_const_net_0 = 8'h00;
//--------------------------------------------------------------------
// Top level output port assignments
//--------------------------------------------------------------------
assign GL0_net_1  = GL0_net_0;
assign GL0        = GL0_net_1;
assign GL1_net_1  = GL1_net_0;
assign GL1        = GL1_net_1;
assign LOCK_net_1 = LOCK_net_0;
assign LOCK       = LOCK_net_1;
//--------------------------------------------------------------------
// Component instances
//--------------------------------------------------------------------
//--------FCCC_C0_FCCC_C0_0_FCCC   -   Actel:SgCore:FCCC:2.0.201
FCCC_C0_FCCC_C0_0_FCCC FCCC_C0_0(
        // Inputs
        .CLK0 ( CLK0 ),
        // Outputs
        .GL0  ( GL0_net_0 ),
        .GL1  ( GL1_net_0 ),
        .LOCK ( LOCK_net_0 ) 
        );


endmodule
