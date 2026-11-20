# Exporting core axi4_master_if to TCL
# Exporting Create HDL core command for module axi4_master_if
create_hdl_core -file {hdl/axi_master_if.v} -module {axi4_master_if} -library {work} -package {}
# Exporting BIF information of  HDL core command for module axi4_master_if
hdl_core_add_bif -hdl_core_name {axi4_master_if} -bif_definition {AXI4:AMBA:AMBA4:master} -bif_name {BIF_1} -signal_map {\
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
"RREADY:m_axi_rready" }
