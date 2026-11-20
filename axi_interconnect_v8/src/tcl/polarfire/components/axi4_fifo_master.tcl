# ==============================================================================
# Libero SoC Tcl Script: Package axi4_fifo_master.v as an HDL+ SmartDesign IP
# ==============================================================================

set script_dir   [file dirname [file normalize [info script]]]
set src_hdl_file [file normalize [file join $script_dir ".." "hdl" "axi4_fifo_master.v"]]
set core_name    "axi4_fifo_master"

# 1. Create the HDL+ core from an already-imported/linked file in the project.
#    Only remove an existing core or import the Verilog file if the initial call fails.
if {[catch { create_hdl_core -file {hdl/axi4_fifo_master.v} -module $core_name -library {work} -package {} }] != 0} {
    catch { remove_hdl_core -hdl_core_name $core_name }
    if {[catch { create_hdl_core -file {hdl/axi4_fifo_master.v} -module $core_name -library {work} -package {} }] != 0} {
        if {[catch { create_hdl_core -file $src_hdl_file -module $core_name -library {work} -package {} }] != 0} {
            if {![file exists $src_hdl_file]} {
                error "HDL source file not found: $src_hdl_file"
            }
            puts "INFO: Importing $src_hdl_file into Libero project..."
            import_files -hdl_source $src_hdl_file
            build_design_hierarchy
            create_hdl_core -file {hdl/axi4_fifo_master.v} -module $core_name -library {work} -package {}
        }
    }
}

# 2. Add & Map AXI4 64-Bit Master Bus Interface -> "AXI4_Master" (matches top.tcl)
hdl_core_add_bif \
    -hdl_core_name $core_name \
    -bif_definition {AXI4:AMBA:AMBA4:master} \
    -bif_name {AXI4_Master} \
    -signal_map { \
        "AWID:m_axi_awid" \
        "AWADDR:m_axi_awaddr" \
        "AWLEN:m_axi_awlen" \
        "AWSIZE:m_axi_awsize" \
        "AWBURST:m_axi_awburst" \
        "AWVALID:m_axi_awvalid" \
        "AWREADY:m_axi_awready" \
        "WDATA:m_axi_wdata" \
        "WSTRB:m_axi_wstrb" \
        "WLAST:m_axi_wlast" \
        "WVALID:m_axi_wvalid" \
        "WREADY:m_axi_wready" \
        "BID:m_axi_bid" \
        "BRESP:m_axi_bresp" \
        "BVALID:m_axi_bvalid" \
        "BREADY:m_axi_bready" \
        "ARID:m_axi_arid" \
        "ARADDR:m_axi_araddr" \
        "ARLEN:m_axi_arlen" \
        "ARSIZE:m_axi_arsize" \
        "ARBURST:m_axi_arburst" \
        "ARVALID:m_axi_arvalid" \
        "ARREADY:m_axi_arready" \
        "RID:m_axi_rid" \
        "RDATA:m_axi_rdata" \
        "RRESP:m_axi_rresp" \
        "RLAST:m_axi_rlast" \
        "RVALID:m_axi_rvalid" \
        "RREADY:m_axi_rready" \
    }

puts "INFO: Successfully packaged '$core_name' with AXI4_Master bus interface."