//------------------------------------------------------------------------------
// Company/Institution:  Tecnomic Components
// Engineer:             Jijeesh M
// 
// Create Date:          2026
// Module Name:          fpga_top
// Project Name:         RTG4/SmartFusion2 Serial to AXI Memory Staging System
// Target Devices:       Microchip SmartFusion2 / RTG4 Fabric Core Architecture
// Tool Versions:        Libero SoC Design Suite v12.0+
//
// Description:
//   This module acts as the primary top-level structural wrapper layer. It
//   implements a dedicated Staging Buffer Architecture designed to isolate 
//   slow asynchronous serial lines (UART) from a high-frequency system bus.
//
//   Operational Flow:
//     1. Write: Serial bytes are collected slowly into a 2KB Staging BRAM.
//        Once a burst finishes, the AXI Master Mover blasts the entire packet
//        onto the high-speed AXI fabric at 80 MHz in a single burst.
//     2. Read: High-speed AXI reads fetch data blocks from the target system
//        memory into the Staging Buffer RAM, which then streams data back 
//        to the host utility over UART.
//
// Dependencies:
//   - FCCC_C0               (SmartFusion2 Native Hard-IP Clock Block)
//   - uart_rx / uart_tx     (Physical Line Serialization Controllers)
//   - ram_2k_true_dual_port (Dual-Access Asymmetric Bridge RAM Layout)
//   - system_control_fsm    (5-bit Handshake Protocol Controller Engine)
//   - axi4_master_data_mover(High-Speed AXI4 Burst Controller Engine)
//   - axi_ram               (Alex Forencich System Memory Emulation target)
//
// Revision History:
//   v1.0 - Baseline 2KB hardcoded burst system loop.
//   v2.0 - Added dynamic 16-bit word length parameters handshake tracking.
//   v3.0 - Integrated 64-bit AXI4 Full Master pipeline & True Dual-Port BRAM.
//   v3.1 - Converted to 5-bit width FCCC-sync state tracking matrices.
//------------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module top (
    //--------------------------------------------------------------------------
    // Physical Board Pin Hookups
    //--------------------------------------------------------------------------
    input  wire         clk_50mhz,     // External 50 MHz input crystal pin oscillator
    input  wire         board_rst,     // Active-High mechanical push button pad input
    input  wire         rx_serial,     // Physical UART RX pin incoming transmission wire line
    output wire         tx_serial      // Physical UART TX pin outgoing serialization wire line
);

    //--------------------------------------------------------------------------
    // Clock & Reset Conditioning Nets
    //--------------------------------------------------------------------------
    wire        clk_80mhz;             // Main global logic domain clock line (Fabric)
    wire        pll_locked;            // Asserted high when FCCC output matches target bounds
    wire        sys_rst_n;             // Unified system active-low reset tracking net
    
    // Core Clock/Reset Discipline Rule: Hold your fabric subsystems in an absolute 
    // reset state until the physical internal FCCC stabilizes its output clock phases
    // and asserts its LOCK pin high.
    assign sys_rst_n = (!board_rst) && pll_locked;

    //--------------------------------------------------------------------------
    // Physical UART Peripheral Interconnect Routing Nets
    //--------------------------------------------------------------------------
    wire        rx_ready_net;          // Pulsed high for 1 cycle when serial byte arrives
    wire [7:0]  rx_byte_net;           // Raw parallel byte captured from physical RX line
    wire        tx_busy_net;           // High while transmitter is serializing down the wire
    wire        tx_start_net;          // Pulse high for 1 cycle to request byte transmission
    wire [7:0]  tx_byte_net;           // Byte payload directed down to transmitter shift loops

    //--------------------------------------------------------------------------
    // Staging RAM Memory Management Mapping Interconnect Channels (2KB)
    //--------------------------------------------------------------------------
    // Port A: Slower UART Handshake Protocol State Machine Access Bus Layout
    wire        ram_a_we;              // Port A Write Enable strobe line
    wire [7:0]  ram_a_waddr;           // Port A Write Pointer Index
    wire [63:0] ram_a_wdata;           // Port A 64-bit Parallel input data lane
    wire [7:0]  ram_a_raddr;           // Port A Read Pointer Index
    wire [63:0] ram_a_rdata;           // Port A 64-bit Parallel output data data lane

    // Port B: High-Speed AXI4 Full Master Data Mover Block Engine Access Bus Layout
    wire        ram_b_we;              // Port B Write Enable strobe line
    wire [7:0]  ram_b_addr;            // Port B Read/Write Address Pointer index
    wire [63:0] ram_b_wdata;           // Port B 64-bit Parallel input data lane
    wire [63:0] ram_b_rdata;           // Port B 64-bit Parallel output data data lane

    //--------------------------------------------------------------------------
    // Inter-Module Co-Processing Coordination Handshake Flags
    //--------------------------------------------------------------------------
    wire        axi_start_write_pulse; // FSM pulse to launch Staging RAM -> AXI bus copy
    wire        axi_start_read_pulse;  // FSM pulse to launch AXI bus -> Staging RAM copy
    wire        axi_mover_busy_flag;   // High continuously while AXI Master owns the channels
    wire        axi_mover_done_pulse;  // Pulsed high for 1 cycle by Data Mover on complete
    wire [31:0] axi_shared_address;    // AXI bus destination address offset index tracker
    wire [15:0] axi_shared_word_len;   // Total count of 64-bit words targeted in transaction

    //--------------------------------------------------------------------------
    // Interconnect Buses Routing AXI4 Master Signals straight into AXI4 Slave RAM
    //--------------------------------------------------------------------------
    wire [7:0]  axi_awid;
    wire [31:0] axi_awaddr;
    wire [7:0]  axi_awlen;
    wire [2:0]  axi_awsize;
    wire [1:0]  axi_awburst;
    wire        axi_awvalid;
    wire        axi_awready;

    wire [63:0] axi_wdata;
    wire [7:0]  axi_wstrb;
    wire        axi_wlast;
    wire        axi_wvalid;
    wire        axi_wready;

    wire [7:0]  axi_bid;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    wire        axi_bready;

    wire [7:0]  axi_arid;
    wire [31:0] axi_araddr;
    wire [7:0]  axi_arlen;
    wire [2:0]  axi_arsize;
    wire [1:0]  axi_arburst;
    wire        axi_arvalid;
    wire        axi_arready;

    wire [7:0]  axi_rid;
    wire [63:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rlast;
    wire        axi_rvalid;
    wire        axi_rready;

    //==========================================================================
    // IP COMPONENT INSTANTIATION MATRIX STRATEGIES
    //==========================================================================

    //--------------------------------------------------------------------------
    // HARDWARE INSTANCE: SmartFusion2 Fabric Clock Control Center (FCCC) Core
    //--------------------------------------------------------------------------
    FCCC_C0 pll_inst (
        // Inputs
        .CLK0_PAD (clk_50mhz),            // 50 MHz reference pin crystal feedback oscillator
        // Outputs
        .GL0  (clk_80mhz),            // Primary global high frequency clock line output
       // .GL1  (),                     // Left open (Unused output branch)
        .LOCK (pll_locked)            // Flag indicating clock tree alignment validation
    );

    //--------------------------------------------------------------------------
    // HARDWARE INSTANCE: UART Serial Asynchronous Interface Line Receiver
    //--------------------------------------------------------------------------
    uart_rx receiver_inst (
        .clk       (clk_80mhz),       // Clock input (80 MHz)
        .rst_n     (sys_rst_n),       // Active-Low synchronized system reset
        .rx_serial (rx_serial),       // Outboard physical board pin rx link
        .rx_ready  (rx_ready_net),    // Strobe flag routing to FSM controller
        .rx_data   (rx_byte_net)      // Data payload routing to FSM shift loops
    );

    //--------------------------------------------------------------------------
    // HARDWARE INSTANCE: UART Serial Asynchronous Interface Line Transmitter
    //--------------------------------------------------------------------------
    uart_tx transmitter_inst (
        .clk       (clk_80mhz),       // Clock input (80 MHz)
        .rst_n     (sys_rst_n),       // Active-Low synchronized system reset
        .tx_start  (tx_start_net),    // Kickoff command strobe from FSM controller
        .tx_byte   (tx_byte_net),     // Outbound target payload slice routing
        .tx_serial (tx_serial),       // Outboard physical board pin tx link
        .tx_busy   (tx_busy_net)      // Feedback flag state routing to FSM
    );

    //--------------------------------------------------------------------------
    // HARDWARE INSTANCE: True Dual-Port 2KB Block Storage RAM (Staging Buffer)
    //--------------------------------------------------------------------------
    ram_2k_true_dual_port staging_buffer_ram (
        .clk     (clk_80mhz),
        
        // Channel A (Owned strictly by the slow UART Handshake Protocol FSM Engine)
        .we_a    (ram_a_we), 
        .addr_a  (ram_a_we ? ram_a_waddr : ram_a_raddr), 
        .wdata_a (ram_a_wdata), 
        .rdata_a (ram_a_rdata),
        
        // Channel B (Owned strictly by the high-speed AXI4 Full Master Data Mover)
        .we_b    (ram_b_we), 
        .addr_b  (ram_b_addr), 
        .wdata_b (ram_b_wdata), 
        .rdata_b (ram_b_rdata)
    );

    //--------------------------------------------------------------------------
    // HARDWARE INSTANCE: Handshake Controller Protocol FSM Logic Core
    //--------------------------------------------------------------------------
    system_control_fsm protocol_engine_inst (
        .clk                (clk_80mhz),             // Logic operating execution speed (80 MHz)
        .rst_n              (sys_rst_n),             // Main synchronized system reset
        
        // Hardware UART line mapping pins
        .rx_ready           (rx_ready_net),
        .rx_byte            (rx_byte_net),
        .tx_busy            (tx_busy_net),
        .tx_start           (tx_start_net),
        .tx_byte            (tx_byte_net),
        
        // Staging Buffer Block RAM channel A ports
        .ram_we             (ram_a_we),
        .ram_waddr          (ram_a_waddr),
        .ram_wdata          (ram_a_wdata),
        .ram_raddr          (ram_a_raddr),
        .ram_rdata          (ram_a_rdata),
        
        // AXI Master Engine launch coordination channels
        .axi_write_trigger  (axi_start_write_pulse), // Pulse out high to initiate AXI master write
        .axi_read_trigger   (axi_start_read_pulse),  // Pulse out high to initiate AXI master read
        .axi_target_address (axi_shared_address),    // Base address to target on the AXI bus
        .axi_length_words   (axi_shared_word_len),   // Number of 64-bit words to move
        .axi_engine_busy    (axi_mover_busy_flag),   // Status monitor line from mover
        .axi_engine_done    (axi_mover_done_pulse)   // Done transaction monitor line from mover
    );

    //--------------------------------------------------------------------------
    // HARDWARE INSTANCE: High-Speed AXI4 Full Master Data Mover Engine
    //--------------------------------------------------------------------------
    axi4_master_data_mover axi_master_mover (
        .clk               (clk_80mhz),              // Operating System Execution Clock (80 MHz)
        .rst_n             (sys_rst_n),              // Main synchronized system reset
        
        // Coordination hooks driving operation launch pipelines
        .start_write       (axi_start_write_pulse),
        .start_read        (axi_start_read_pulse),
        .base_address      (axi_shared_address),
        .word_count        (axi_shared_word_len),
        .mover_busy        (axi_mover_busy_flag),
        .mover_done        (axi_mover_done_pulse),
        
        // Staging Buffer Block RAM channel B ports
        .ram_b_addr        (ram_b_addr),
        .ram_b_we          (ram_b_we),
        .ram_b_wdata       (ram_b_wdata),
        .ram_b_rdata       (ram_b_rdata),
        
        // Master Output Bus Lanes routing into Interconnect Networks
        .m_axi_awid        (axi_awid),
        .m_axi_awaddr      (axi_awaddr),
        .m_axi_awlen       (axi_awlen),
        .m_axi_awsize      (axi_awsize),
        .m_axi_awburst     (axi_awburst),
        .m_axi_awvalid     (axi_awvalid),
        .m_axi_awready     (axi_awready),
        .m_axi_wdata       (axi_wdata),
        .m_axi_wstrb       (axi_wstrb),
        .m_axi_wlast       (axi_wlast),
        .m_axi_wvalid      (axi_wvalid),
        .m_axi_wready      (axi_wready),
        .m_axi_bid         (axi_bid),
        .m_axi_bresp       (axi_bresp),
        .m_axi_bvalid      (axi_bvalid),
        .m_axi_bready      (axi_bready),
        .m_axi_arid        (axi_arid),
        .m_axi_araddr      (axi_araddr),
        .m_axi_arlen       (axi_arlen),
        .m_axi_arsize      (axi_arsize),
        .m_axi_arburst     (axi_arburst),
        .m_axi_arvalid     (axi_arvalid),
        .m_axi_arready     (axi_arready),
        .m_axi_rid         (axi_rid),
        .m_axi_rdata       (axi_rdata),
        .m_axi_rresp       (axi_rresp),
        .m_axi_rlast       (axi_rlast),
        .m_axi_rvalid      (axi_rvalid),
        .m_axi_rready      (axi_rready)
    );

    //--------------------------------------------------------------------------
    // HARDWARE INSTANCE: Target External Memory Array Block (User Core)
    // Parameterized for standard 64-bit wide Data Architecture bus layout.
    //--------------------------------------------------------------------------
    axi_ram # (
        .DATA_WIDTH      (64),        // Configured width matching data mover lanes
        .ADDR_WIDTH      (14),        // 16KB addressing allocation memory capacity space
        .ID_WIDTH        (8),         // Standard AXI Transaction Tracking ID tagging size
        .PIPELINE_OUTPUT (1)          // Pipeline flag to optimize timing closures
    ) external_target_axi_ram (
        .clk             (clk_80mhz), // Driven at same system speed clock bounds (80 MHz)
        .rst             (!sys_rst_n),// Forencich core utilizes an ACTIVE-HIGH reset schema
        
        // Write Address Target Channel Connections
        .s_axi_awid      (axi_awid),
        .s_axi_awaddr    (axi_awaddr[13:0]), // Clamped to lower 16-bit physical memory range
        .s_axi_awlen     (axi_awlen),
        .s_axi_awsize    (axi_awsize),
        .s_axi_awburst   (axi_awburst),
        .s_axi_awlock    (1'b0),      // Locked transactions disabled (Normal memory space)
        .s_axi_awcache   (4'b0011),   // Normal Non-cacheable, Modifiable, Bufferable property
        .s_axi_awprot    (3'b000),    // Normal Unprivileged, Secure, Data-access protection
        .s_axi_awvalid   (axi_awvalid),
        .s_axi_awready   (axi_awready),
        
        // Write Data Payload Channel Connections
        .s_axi_wdata     (axi_wdata),
        .s_axi_wstrb     (axi_wstrb),
        .s_axi_wlast     (axi_wlast),
        .s_axi_wvalid    (axi_wvalid),
        .s_axi_wready    (axi_wready),
        
        // Outbound Write Response Handshaking Channels
        .s_axi_bid       (axi_bid),
        .s_axi_bresp     (axi_bresp),
        .s_axi_bvalid    (axi_bvalid),
        .s_axi_bready    (axi_bready),
        
        // Read Address Target Channel Connections
        .s_axi_arid      (axi_arid),
        .s_axi_araddr    (axi_araddr[13:0]),
        .s_axi_arlen     (axi_arlen),
        .s_axi_arsize    (axi_arsize),
        .s_axi_arburst   (axi_arburst),
        .s_axi_arlock    (1'b0),
        .s_axi_arcache   (4'b0011),
        .s_axi_arprot    (3'b000),
        .s_axi_arvalid   (axi_arvalid),
        .s_axi_arready   (axi_arready),
        
        // Outbound Read Data Response Streaming Channels
        .s_axi_rid       (axi_rid),
        .s_axi_rdata     (axi_rdata),
        .s_axi_rresp     (axi_rresp),
        .s_axi_rlast     (axi_rlast),
        .s_axi_rvalid    (axi_rvalid),
        .s_axi_rready    (axi_rready)
    );

endmodule
`resetall
