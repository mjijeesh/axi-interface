//------------------------------------------------------------------------------
// Company/Institution:  Creative System Labs
// Engineer:             Jijeesh M
// 
// Create Date:          2026
// Module Name:          fpga_top
// Project Name:         RTG4/SmartFusion2 Serial to AXI Memory Staging System
// Target Devices:       Microchip SmartFusion2 / RTG4 Fabric Core Architecture
// Tool Versions:        Libero SoC Design Suite v12.0+
//
// Description:
//   Pure Hardware Multi-Slave AXI Subsystem Top-Level Wrapper.
//   Unpacks flattened interconnect vectors into separate, distinct AXI Master 
//   interface channels (m0 for RAM 1, m1 for RAM 2).
//   
//   Fixes Implemented:
//     - Declared m0_axi_bready, m0_axi_rready, m1_axi_bready, and m1_axi_rready
//       wires to resolve Libero VERI-1128 compilation dropouts.
//------------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module top (
    // Clock and Reset Signals
    input  wire         clk_50mhz,          // External 50 MHz reference oscillator
    input  wire         board_rst,          // Active-High external physical reset
    
    // Top-Level Native Coprocessor Control Interface (Direct Mover Access)
    input  wire         start_write,        // Pulse high for 1 cycle to kick off RAM -> AXI
    input  wire         start_read,         // Pulse high for 1 cycle to kick off AXI -> RAM
    input  wire  [31:0] base_address,       // 32-bit destination/source AXI bus address
    input  wire  [15:0] word_count,         // Number of 64-bit words to transfer
    output wire         axi_busy,         // Stays high continuously during AXI transfers
    output wire         axi_done,         // Pulses high for 1 cycle upon completion

    // Top-Level Native Staging Buffer Interface (Direct Port A Access)
    input  wire         ram_a_we,           // Port A Active-High Write Enable strobe flag
    input  wire  [7:0]  ram_a_addr,         // Port A 8-bit pointer address index (256 depth)
    input  wire  [63:0] ram_a_wdata,        // Port A 64-bit parallel incoming write payload data
    output wire  [63:0] ram_a_rdata         // Port A 64-bit parallel synchronous output read data
);

    // Clock/Reset Tree Nets
    wire clk_80mhz;
    wire pll_locked;
    wire sys_rst_n;
    assign sys_rst_n = (!board_rst) && pll_locked;

    // Local Staging Memory Management Port B Interface Nets
    wire        ram_b_we;
    wire [7:0]  ram_b_addr;
    wire [63:0] ram_b_wdata;
    wire [63:0] ram_b_rdata;

    //--------------------------------------------------------------------------
    // AXI BUS INTERFACE WIRES
    //--------------------------------------------------------------------------
    // Master Mover Core Interface (Connects into Interconnect Slave side)
    wire [7:0]  mst_awid;    wire [31:0] mst_awaddr;  wire [7:0]  mst_awlen;
    wire [2:0]  mst_awsize;  wire [1:0]  mst_awburst; wire        mst_awvalid; wire mst_awready;
    wire [63:0] mst_wdata;   wire [7:0]  mst_wstrb;   wire        mst_wlast;   wire mst_wvalid;  wire mst_wready;
    wire [7:0]  mst_bid;     wire [1:0]  mst_bresp;   wire        mst_bvalid;  wire mst_bready;
    wire [7:0]  mst_arid;    wire [31:0] mst_araddr;  wire [7:0]  mst_arlen;
    wire [2:0]  mst_arsize;  wire [1:0]  mst_arburst; wire        mst_arvalid; wire mst_arready;
    wire [7:0]  mst_rid;     wire [63:0] mst_rdata;   wire [1:0]  mst_rresp;   wire mst_rlast;   wire mst_rvalid; wire mst_rready;

    // INTERCONNECT MASTER PORT 0 (Dedicated to AXI RAM 1 - Lower Address Space)
    wire [7:0]  m0_axi_awid;    wire [31:0] m0_axi_awaddr;  wire [7:0]  m0_axi_awlen;
    wire [2:0]  m0_axi_awsize;  wire [1:0]  m0_axi_awburst; wire        m0_axi_awvalid; wire m0_axi_awready;
    wire [63:0] m0_axi_wdata;   wire [7:0]  m0_axi_wstrb;   wire        m0_axi_wlast;   wire m0_axi_wvalid;  wire m0_axi_wready;
    wire [7:0]  m0_axi_bid;     wire [1:0]  m0_axi_bresp;   wire        m0_axi_bvalid;  wire m0_axi_bready;
    wire [7:0]  m0_axi_arid;    wire [31:0] m0_axi_araddr;  wire [7:0]  m0_axi_arlen;
    wire [2:0]  m0_axi_arsize;  wire [1:0]  m0_axi_arburst; wire        m0_axi_arvalid; wire m0_axi_arready;
    wire [7:0]  m0_axi_rid;     wire [63:0] m0_axi_rdata;   wire [1:0]  m0_axi_rresp;   wire m0_axi_rlast;   wire m0_axi_rvalid; wire m0_axi_rready;

    // INTERCONNECT MASTER PORT 1 (Dedicated to AXI RAM 2 - Upper Address Space)
    wire [7:0]  m1_axi_awid;    wire [31:0] m1_axi_awaddr;  wire [7:0]  m1_axi_awlen;
    wire [2:0]  m1_axi_awsize;  wire [1:0]  m1_axi_awburst; wire        m1_axi_awvalid; wire m1_axi_awready;
    wire [63:0] m1_axi_wdata;   wire [7:0]  m1_axi_wstrb;   wire        m1_axi_wlast;   wire m1_axi_wvalid;  wire m1_axi_wready;
    wire [7:0]  m1_axi_bid;     wire [1:0]  m1_axi_bresp;   wire        m1_axi_bvalid;  wire m1_axi_bready;
    wire [7:0]  m1_axi_arid;    wire [31:0] m1_axi_araddr;  wire [7:0]  m1_axi_arlen;
    wire [2:0]  m1_axi_arsize;  wire [1:0]  m1_axi_arburst; wire        m1_axi_arvalid; wire m1_axi_arready;
    wire [7:0]  m1_axi_rid;     wire [63:0] m1_axi_rdata;   wire [1:0]  m1_axi_rresp;   wire m1_axi_rlast;   wire m1_axi_rvalid; wire m1_axi_rready;

    //--------------------------------------------------------------------------
    // CORE INFRASTRUCTURE INSTANTIATIONS
    //--------------------------------------------------------------------------
    FCCC_C0 pll_inst (
        .CLK0_PAD (clk_50mhz),
        .GL0      (clk_80mhz),
        .LOCK     (pll_locked)
    );

    ram_2k_true_dual_port staging_buffer_ram (
        .clk     (clk_80mhz),
        .we_a    (ram_a_we), 
        .addr_a  (ram_a_addr), 
        .wdata_a (ram_a_wdata), 
        .rdata_a (ram_a_rdata),
        .we_b    (ram_b_we), 
        .addr_b  (ram_b_addr), 
        .wdata_b (ram_b_wdata), 
        .rdata_b (ram_b_rdata)
    );

    axi4_master_if axi4_master_if_inst (
        .clk           (clk_80mhz), 
        .rst_n         (sys_rst_n), 
        .start_write   (start_write), 
        .start_read    (start_read), 
        .base_address  (base_address), 
        .word_count    (word_count), 
        .axi_busy      (axi_busy), 
        .axi_done      (axi_done),
        .ram_b_addr    (ram_b_addr), 
        .ram_b_we      (ram_b_we), 
        .ram_b_wdata   (ram_b_wdata), 
        .ram_b_rdata   (ram_b_rdata),
        .m_axi_awid    (mst_awid), 
        .m_axi_awaddr  (mst_awaddr), 
        .m_axi_awlen   (mst_awlen), 
        .m_axi_awsize  (mst_awsize), 
        .m_axi_awburst (mst_awburst), 
        .m_axi_awvalid (mst_awvalid), 
        .m_axi_awready (mst_awready),
        .m_axi_wdata   (mst_wdata), 
        .m_axi_wstrb   (mst_wstrb), 
        .m_axi_wlast   (mst_wlast), 
        .m_axi_wvalid  (mst_wvalid), 
        .m_axi_wready  (mst_wready),
        .m_axi_bid     (mst_bid), 
        .m_axi_bresp   (mst_bresp), 
        .m_axi_bvalid  (mst_bvalid), 
        .m_axi_bready  (mst_bready),
        .m_axi_arid    (mst_arid), 
        .m_axi_araddr  (mst_araddr), 
        .m_axi_arlen   (mst_arlen), 
        .m_axi_arsize  (mst_arsize), 
        .m_axi_arburst (mst_arburst), 
        .m_axi_arvalid (mst_arvalid), 
        .m_axi_arready (mst_arready),
        .m_axi_rid     (mst_rid), 
        .m_axi_rdata   (mst_rdata), 
        .m_axi_rresp   (mst_rresp), 
        .m_axi_rlast   (mst_rlast), 
        .m_axi_rvalid  (mst_rvalid), 
        .m_axi_rready  (mst_rready)
    );

    //--------------------------------------------------------------------------
    // 1-MASTER x 2-SLAVE AXI INTERCONNECT SWITCHBOARD
    //--------------------------------------------------------------------------
    axi_interconnect #(
        .S_COUNT           (1), 
        .M_COUNT           (2), 
        .DATA_WIDTH        (64), 
        .ADDR_WIDTH        (32), 
        .ID_WIDTH          (8), 
        .M_REGIONS         (1),
        .M_BASE_ADDR       ({32'hE000_0000, 32'h0000_0000}),
        .M_ADDR_WIDTH      ({32'd29, 32'd29})
    ) axi_interconnect_inst (
        .clk               (clk_80mhz), 
        .rst               (!sys_rst_n),

        // Slave Port 0 Input Interface Connections
        .s_axi_awid        (mst_awid), 
        .s_axi_awaddr      (mst_awaddr), 
        .s_axi_awlen       (mst_awlen), 
        .s_axi_awsize      (mst_awsize), 
        .s_axi_awburst     (mst_awburst), 
        .s_axi_awlock      (1'b0), 
        .s_axi_awcache     (4'b0011), 
        .s_axi_awprot      (3'b000), 
        .s_axi_awqos       (4'h0), 
        .s_axi_awuser      (1'b0), 
        .s_axi_awvalid     (mst_awvalid), 
        .s_axi_awready     (mst_awready),
        .s_axi_wdata       (mst_wdata), 
        .s_axi_wstrb       (mst_wstrb), 
        .s_axi_wlast       (mst_wlast), 
        .s_axi_wuser       (1'b0), 
        .s_axi_wvalid      (mst_wvalid), 
        .s_axi_wready      (mst_wready),
        .s_axi_bid         (mst_bid), 
        .s_axi_bresp       (mst_bresp), 
        .s_axi_buser       (), 
        .s_axi_bvalid      (mst_bvalid), 
        .s_axi_bready      (mst_bready),
        .s_axi_arid        (mst_arid), 
        .s_axi_araddr      (mst_araddr), 
        .s_axi_arlen       (mst_arlen), 
        .s_axi_arsize      (mst_arsize), 
        .s_axi_arburst     (mst_arburst), 
        .s_axi_arlock      (1'b0), 
        .s_axi_arcache     (4'b0011), 
        .s_axi_arprot      (3'b000), 
        .s_axi_arqos       (4'h0), 
        .s_axi_aruser      (1'b0), 
        .s_axi_arvalid     (mst_arvalid), 
        .s_axi_arready     (mst_arready),
        .s_axi_rid         (mst_rid), 
        .s_axi_rdata       (mst_rdata), 
        .s_axi_rresp       (mst_rresp), 
        .s_axi_rlast       (mst_rlast), 
        .s_axi_ruser       (), 
        .s_axi_rvalid      (mst_rvalid), 
        .s_axi_rready      (mst_rready),

        // Unpacked Master Array Combinational Mappings { Master 1, Master 0 }
        .m_axi_awid        ({m1_axi_awid,    m0_axi_awid}),
        .m_axi_awaddr      ({m1_axi_awaddr,  m0_axi_awaddr}),
        .m_axi_awlen       ({m1_axi_awlen,   m0_axi_awlen}),
        .m_axi_awsize      ({m1_axi_awsize,  m0_axi_awsize}),
        .m_axi_awburst     ({m1_axi_awburst, m0_axi_awburst}),
        .m_axi_awlock      (), 
        .m_axi_awcache     (), 
        .m_axi_awprot      (), 
        .m_axi_awqos       (), 
        .m_axi_awregion    (), 
        .m_axi_awuser      (),
        .m_axi_awvalid     ({m1_axi_awvalid, m0_axi_awvalid}),
        .m_axi_awready     ({m1_axi_awready, m0_axi_awready}),
        .m_axi_wdata       ({m1_axi_wdata,   m0_axi_wdata}),
        .m_axi_wstrb       ({m1_axi_wstrb,   m0_axi_wstrb}),
        .m_axi_wlast       ({m1_axi_wlast,   m0_axi_wlast}),
        .m_axi_wuser       (),
        .m_axi_wvalid      ({m1_axi_wvalid,  m0_axi_wvalid}),
        .m_axi_wready      ({m1_axi_wready,  m0_axi_wready}),
        .m_axi_bid         ({m1_axi_bid,     m0_axi_bid}),
        .m_axi_bresp       ({m1_axi_bresp,   m0_axi_bresp}),
        .m_axi_buser       (2'b00),
        .m_axi_bvalid      ({m1_axi_bvalid,  m0_axi_bvalid}),
        .m_axi_bready      ({m1_axi_bready,  m0_axi_bready}),
        .m_axi_arid        ({m1_axi_arid,    m0_axi_arid}),
        .m_axi_araddr      ({m1_axi_araddr,  m0_axi_araddr}),
        .m_axi_arlen       ({m1_axi_arlen,   m0_axi_arlen}),
        .m_axi_arsize      ({m1_axi_arsize,  m0_axi_arsize}),
        .m_axi_arburst     ({m1_axi_arburst, m0_axi_arburst}),
        .m_axi_arlock      (), 
        .m_axi_arcache     (), 
        .m_axi_arprot      (), 
        .m_axi_arqos       (), 
        .m_axi_arregion    (), 
        .m_axi_aruser      (),
        .m_axi_arvalid     ({m1_axi_arvalid, m0_axi_arvalid}),
        .m_axi_arready     ({m1_axi_arready, m0_axi_arready}),
        .m_axi_rid         ({m1_axi_rid,     m0_axi_rid}),
        .m_axi_rdata       ({m1_axi_rdata,   m0_axi_rdata}),
        .m_axi_rresp       ({m1_axi_rresp,   m0_axi_rresp}),
        .m_axi_rlast       ({m1_axi_rlast,   m0_axi_rlast}),
        .m_axi_ruser       (2'b00),
        .m_axi_rvalid      ({m1_axi_rvalid,  m0_axi_rvalid}),
        .m_axi_rready      ({m1_axi_rready,  m0_axi_rready})
    );

    //--------------------------------------------------------------------------
    // AXI RAM SLAVE 1: Mapped to Interconnect Master Slot 0 (0x0000_0000 Zone)
    //--------------------------------------------------------------------------
    axi_ram #(
        .DATA_WIDTH(64), .ADDR_WIDTH(14), .ID_WIDTH(8), .PIPELINE_OUTPUT(1)
    ) external_target_axi_ram_1 (
        .clk           (clk_80mhz), 
        .rst           (!sys_rst_n),
        .s_axi_awid    (m0_axi_awid), 
        .s_axi_awaddr  (m0_axi_awaddr[13:0]), 
        .s_axi_awlen   (m0_axi_awlen), 
        .s_axi_awsize  (m0_axi_awsize), 
        .s_axi_awburst (m0_axi_awburst), 
        .s_axi_awlock  (1'b0), 
        .s_axi_awcache (4'b0011), 
        .s_axi_awprot  (3'b000), 
        .s_axi_awvalid (m0_axi_awvalid), 
        .s_axi_awready (m0_axi_awready),
        .s_axi_wdata   (m0_axi_wdata), 
        .s_axi_wstrb   (m0_axi_wstrb), 
        .s_axi_wlast   (m0_axi_wlast), 
        .s_axi_wvalid  (m0_axi_wvalid), 
        .s_axi_wready  (m0_axi_wready),
        .s_axi_bid     (m0_axi_bid), 
        .s_axi_bresp   (m0_axi_bresp), 
        .s_axi_bvalid  (m0_axi_bvalid), 
        .s_axi_bready  (m0_axi_bready),
        .s_axi_arid    (m0_axi_arid), 
        .s_axi_araddr  (m0_axi_araddr[13:0]), 
        .s_axi_arlen   (m0_axi_arlen), 
        .s_axi_arsize  (m0_axi_arsize), 
        .s_axi_arburst (m0_axi_arburst), 
        .s_axi_arlock  (1'b0), 
        .s_axi_arcache (4'b0011), 
        .s_axi_arprot  (3'b000), 
        .s_axi_arvalid (m0_axi_arvalid), 
        .s_axi_arready (m0_axi_arready),
        .s_axi_rid     (m0_axi_rid), 
        .s_axi_rdata   (m0_axi_rdata), 
        .s_axi_rresp   (m0_axi_rresp), 
        .s_axi_rlast   (m0_axi_rlast), 
        .s_axi_rvalid  (m0_axi_rvalid), 
        .s_axi_rready  (m0_axi_rready)
    );

    //--------------------------------------------------------------------------
    // AXI RAM SLAVE 2: Mapped to Interconnect Master Slot 1 (0xE000_0000 Zone)
    //--------------------------------------------------------------------------
    axi_ram #(
        .DATA_WIDTH(64), .ADDR_WIDTH(14), .ID_WIDTH(8), .PIPELINE_OUTPUT(1)
    ) external_target_axi_ram_2 (
        .clk           (clk_80mhz), 
        .rst           (!sys_rst_n),
        .s_axi_awid    (m1_axi_awid), 
        .s_axi_awaddr  (m1_axi_awaddr[13:0]), 
        .s_axi_awlen   (m1_axi_awlen), 
        .s_axi_awsize  (m1_axi_awsize), 
        .s_axi_awburst (m1_axi_awburst), 
        .s_axi_awlock  (1'b0), 
        .s_axi_awcache (4'b0011), 
        .s_axi_awprot  (3'b000), 
        .s_axi_awvalid (m1_axi_awvalid), 
        .s_axi_awready (m1_axi_awready),
        .s_axi_wdata   (m1_axi_wdata), 
        .s_axi_wstrb   (m1_axi_wstrb), 
        .s_axi_wlast   (m1_axi_wlast), 
        .s_axi_wvalid  (m1_axi_wvalid), 
        .s_axi_wready  (m1_axi_wready),
        .s_axi_bid     (m1_axi_bid), 
        .s_axi_bresp   (m1_axi_bresp), 
        .s_axi_bvalid  (m1_axi_bvalid), 
        .s_axi_bready  (m1_axi_bready),
        .s_axi_arid    (m1_axi_arid), 
        .s_axi_araddr  (m1_axi_araddr[13:0]), 
        .s_axi_arlen   (m1_axi_arlen), 
        .s_axi_arsize  (m1_axi_arsize), 
        .s_axi_arburst (m1_axi_arburst), 
        .s_axi_arlock  (1'b0), 
        .s_axi_arcache (4'b0011), 
        .s_axi_arprot  (3'b000), 
        .s_axi_arvalid (m1_axi_arvalid), 
        .s_axi_arready (m1_axi_arready),
        .s_axi_rid     (m1_axi_rid), 
        .s_axi_rdata   (m1_axi_rdata), 
        .s_axi_rresp   (m1_axi_rresp), 
        .s_axi_rlast   (m1_axi_rlast), 
        .s_axi_rvalid  (m1_axi_rvalid), 
        .s_axi_rready  (m1_axi_rready)
    );

endmodule
`resetall
