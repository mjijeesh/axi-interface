//------------------------------------------------------------------------------
// Company/Institution:  Creative System Labs
// Author/Copyright:     (c) 2018 Alex Forencich
// Re-Formatter:         Unified Engineering AI Group
// 
// Create Date:          2018
// Refactor Date:        2026
// Module Name:          axi_ram
// Project Name:         RTG4/SmartFusion2 Serial to AXI Memory Staging System
// Target Devices:       Microchip SmartFusion2 / RTG4 Fabric Core Architecture
// Tool Versions:        Libero SoC Design Suite v12.0+
//
// Description:
//   A highly parameterizable, high-performance AXI4 Full Slave Synchronous RAM
//   emulation core. It acts as the ultimate destination space for all memory-mapped
//   bus cycles processed by the upstream AXI4 Master Data Mover.
//
//   Key Features:
//     - True 64-bit/32-bit width adaptability via data bus parameters.
//     - Native back-to-back hardware burst scaling handling up to 256 beats.
//     - Individual byte write validation via automated Write Strobe (WSTRB) masking.
//     - Optional output pipeline stage to optimize physical fabric timing closures.
//
// Dependencies:
//   None (Self-contained block memory layer)
//
// Revision History:
//   v1.0 - Initial open-source release by Alex Forencich.
//   v2.0 - Cleaned parameter declarations to eliminate Libero VERI-1199 warnings.
//------------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module axi_ram #
(
    //--------------------------------------------------------------------------
    // Parameterized Architectural Configurations
    //--------------------------------------------------------------------------
    parameter DATA_WIDTH      = 64,             // Width of data bus in bits (e.g. 32 or 64)
    parameter ADDR_WIDTH      = 16,             // Width of address bus in bits (Allocates space)
    parameter STRB_WIDTH      = (DATA_WIDTH/8), // Width of write strobe lane vector mask
    parameter ID_WIDTH        = 8,              // Width of transaction thread ID signals
    parameter PIPELINE_OUTPUT = 1               // Injects extra pipeline register on outputs if high
)
(
    //--------------------------------------------------------------------------
    // Global Clock & System Reset Input Ports
    //--------------------------------------------------------------------------
    input  wire                    clk,         // Main processing system clock domain
    input  wire                    rst,         // Asynchronous system active-high reset

    //--------------------------------------------------------------------------
    // AXI4 Full Slave Interface Channels
    //--------------------------------------------------------------------------
    // Write Address Channel (AW)
    input  wire [ID_WIDTH-1:0]     s_axi_awid,    // Inbound Write Transaction Identification ID tag
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,  // Inbound target burst write start address offset
    input  wire [7:0]              s_axi_awlen,   // Burst Length: Number of beats within block (-1)
    input  wire [2:0]              s_axi_awsize,  // Burst Size: Individual beat byte width index
    input  wire [1:0]              s_axi_awburst, // Burst Type: Address change protocol behavior
    input  wire                    s_axi_awlock,  // Atomic transaction access lock state flag
    input  wire [3:0]              s_axi_awcache, // Memory caching attributes profile descriptor
    input  wire [2:0]              s_axi_awprot,  // Security protection level attribute flag
    input  wire                    s_axi_awvalid, // Master write address validation indicator flag
    output wire                    s_axi_awready, // Slave address acceptance handshaking flag
    
    // Write Data Channel (W)
    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,   // Parallel input data burst payload lanes
    input  wire [STRB_WIDTH-1:0]   s_axi_wstrb,   // Byte lane write validation strobes vector mask
    input  wire                    s_axi_wlast,   // High indicating current beat is final in burst
    input  wire                    s_axi_wvalid,  // Master write data payload validation indicator
    output wire                    s_axi_wready,  // Slave write data channel acceptance handshaking flag
    
    // Write Response Status Channel (B)
    output wire [ID_WIDTH-1:0]     s_axi_bid,     // Outbound response transaction identifier tag
    output wire [1:0]              s_axi_bresp,   // Outbound write transaction completion status flag
    output wire                    s_axi_bvalid,  // Slave write status verification line valid flag
    input  wire                    s_axi_bready,  // Master status channel acceptance handshaking flag
    
    // Read Address Channel (AR)
    input  wire [ID_WIDTH-1:0]     s_axi_arid,    // Inbound Read Transaction Identification ID tag
    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,  // Inbound target burst read start address offset
    input  wire [7:0]              s_axi_arlen,   // Burst Length: Number of beats within block (-1)
    input  wire [2:0]              s_axi_arsize,  // Burst Size: Individual beat byte width index
    input  wire [1:0]              s_axi_arburst, // Burst Type: Address change protocol behavior
    input  wire                    s_axi_arlock,  // Atomic transaction access lock state flag
    input  wire [3:0]              s_axi_arcache, // Memory caching attributes profile descriptor
    input  wire [2:0]              s_axi_arprot,  // Security protection level attribute flag
    input  wire                    s_axi_arvalid, // Master read address validation indicator flag
    output wire                    s_axi_arready, // Slave address acceptance handshaking flag
    
    // Read Data Response Channel (R)
    output wire [ID_WIDTH-1:0]     s_axi_rid,     // Outbound read data transaction identifier tag
    output wire [DATA_WIDTH-1:0]   s_axi_rdata,   // Parallel output data burst payload lanes
    output wire [1:0]              s_axi_rresp,   // Outbound read transaction completion status flag
    output wire                    s_axi_rlast,   // High indicating final data beat returned from RAM
    output wire                    s_axi_rvalid,  // Slave data response validation line valid flag
    input  wire                    s_axi_rready   // Master data channel acceptance handshaking flag
);

    //--------------------------------------------------------------------------
    // FIXED Local Constants (Re-allocated to clear Libero VERI-1199 warnings)
    //--------------------------------------------------------------------------
    localparam VALID_ADDR_WIDTH = ADDR_WIDTH - $clog2(STRB_WIDTH);
    localparam WORD_WIDTH       = STRB_WIDTH;
    localparam WORD_SIZE        = DATA_WIDTH/WORD_WIDTH;

    // Bus Parameter Integrity Structural Assertions
    initial begin
        if (WORD_SIZE * STRB_WIDTH != DATA_WIDTH) begin
            $error("Error: AXI data width not evenly divisible (instance %m)");
            $finish;
        end

        if (2**$clog2(WORD_WIDTH) != WORD_WIDTH) begin
            $error("Error: AXI word width must be an even power of two (instance %m)");
            $finish;
        end
    end

    // Internal FSM State Mappings
    localparam [0:0] READ_STATE_IDLE  = 1'd0,
                     READ_STATE_BURST = 1'd1;

    localparam [1:0] WRITE_STATE_IDLE  = 2'd0,
                     WRITE_STATE_BURST = 2'd1,
                     WRITE_STATE_RESP  = 2'd2;

    // Pipeline Command Flags
    reg mem_wr_en;
    reg mem_rd_en;

    // Read Transaction Internal Tracking Context Cache Registers
    reg [0:0]              read_state_reg = READ_STATE_IDLE, read_state_next;
    reg [ID_WIDTH-1:0]     read_id_reg    = {ID_WIDTH{1'b0}}, read_id_next;
    reg [ADDR_WIDTH-1:0]   read_addr_reg  = {ADDR_WIDTH{1'b0}}, read_addr_next;
    reg [7:0]              read_count_reg = 8'd0, read_count_next;
    reg [2:0]              read_size_reg  = 3'd0, read_size_next;
    reg [1:0]              read_burst_reg = 2'd0, read_burst_next;

    // Write Transaction Internal Tracking Context Cache Registers
    reg [1:0]              write_state_reg = WRITE_STATE_IDLE, write_state_next;
    reg [ID_WIDTH-1:0]     write_id_reg    = {ID_WIDTH{1'b0}}, write_id_next;
    reg [ADDR_WIDTH-1:0]   write_addr_reg  = {ADDR_WIDTH{1'b0}}, write_addr_next;
    reg [7:0]              write_count_reg = 8'd0, write_count_next;
    reg [2:0]              write_size_reg  = 3'd0, write_size_next;
    reg [1:0]              write_burst_reg = 2'd0, write_burst_next;

    // Interface Latch Interconnect Nets
    reg                    s_axi_awready_reg = 1'b0, s_axi_awready_next;
    reg                    s_axi_wready_reg  = 1'b0, s_axi_wready_next;
    reg [ID_WIDTH-1:0]     s_axi_bid_reg     = {ID_WIDTH{1'b0}}, s_axi_bid_next;
    reg                    s_axi_bvalid_reg  = 1'b0, s_axi_bvalid_next;
    reg                    s_axi_arready_reg = 1'b0, s_axi_arready_next;
    reg [ID_WIDTH-1:0]     s_axi_rid_reg     = {ID_WIDTH{1'b0}}, s_axi_rid_next;
    reg [DATA_WIDTH-1:0]   s_axi_rdata_reg   = {DATA_WIDTH{1'b0}}, s_axi_rdata_next;
    reg                    s_axi_rlast_reg   = 1'b0, s_axi_rlast_next;
    reg                    s_axi_rvalid_reg  = 1'b0, s_axi_rvalid_next;

    // High Speed Pipeline Timing Closure Storage Elements
    reg [ID_WIDTH-1:0]     s_axi_rid_pipe_reg   = {ID_WIDTH{1'b0}};
    reg [DATA_WIDTH-1:0]   s_axi_rdata_pipe_reg = {DATA_WIDTH{1'b0}};
    reg                    s_axi_rlast_pipe_reg  = 1'b0;
    reg                    s_axi_rvalid_pipe_reg = 1'b0;

    //--------------------------------------------------------------------------
    // CORE MEMORY VECTOR GRID STORAGE ARRAY DECLARATION
    //--------------------------------------------------------------------------
    // (* RAM_STYLE="BLOCK" *)
    reg [DATA_WIDTH-1:0] mem[(2**VALID_ADDR_WIDTH)-1:0];

    // Address Decoding Shift Alignments (Maps bytes down to native bus indexing bounds)
    wire [VALID_ADDR_WIDTH-1:0] s_axi_awaddr_valid = s_axi_awaddr >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
    wire [VALID_ADDR_WIDTH-1:0] s_axi_araddr_valid = s_axi_araddr >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
    wire [VALID_ADDR_WIDTH-1:0] read_addr_valid     = read_addr_reg >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
    wire [VALID_ADDR_WIDTH-1:0] write_addr_valid    = write_addr_reg >> (ADDR_WIDTH - VALID_ADDR_WIDTH);

    // Dynamic Port Vector Bypass Mappings
    assign s_axi_awready = s_axi_awready_reg;
    assign s_axi_wready  = s_axi_wready_reg;
    assign s_axi_bid     = s_axi_bid_reg;
    assign s_axi_bresp   = 2'b00; // Force static OKAY status condition feedback
    assign s_axi_bvalid  = s_axi_bvalid_reg;
    assign s_axi_arready = s_axi_arready_reg;
    
    assign s_axi_rid     = PIPELINE_OUTPUT ? s_axi_rid_pipe_reg   : s_axi_rid_reg;
    assign s_axi_rdata   = PIPELINE_OUTPUT ? s_axi_rdata_pipe_reg : s_axi_rdata_reg;
    assign s_axi_rresp   = 2'b00; // Force static OKAY status condition feedback
    assign s_axi_rlast   = PIPELINE_OUTPUT ? s_axi_rlast_pipe_reg : s_axi_rlast_reg;
    assign s_axi_rvalid  = PIPELINE_OUTPUT ? s_axi_rvalid_pipe_reg  : s_axi_rvalid_reg;

    //--------------------------------------------------------------------------
    // Synthesizer Loop Memory Initialization Block
    //--------------------------------------------------------------------------
    integer i, j;
    initial begin
        // Dual nested loops structure to bypass vendor tool warnings on deep memories
        for (i = 0; i < 2**VALID_ADDR_WIDTH; i = i + 2**(VALID_ADDR_WIDTH/2)) begin
            for (j = i; j < i + 2**(VALID_ADDR_WIDTH/2); j = j + 1) begin
                mem[j] = 0;
            end
        end
    end

    //==========================================================================
    // AXI WRITE STORAGE ENGINE DESIGN LAYER
    //==========================================================================
    always @* begin
        write_state_next   = WRITE_STATE_IDLE;
        mem_wr_en          = 1'b0;
        write_id_next      = write_id_reg;
        write_addr_next    = write_addr_reg;
        write_count_next   = write_count_reg;
        write_size_next    = write_size_reg;
        write_burst_next   = write_burst_reg;
        s_axi_awready_next = 1'b0;
        s_axi_wready_next  = 1'b0;
        s_axi_bid_next     = s_axi_bid_reg;
        s_axi_bvalid_next  = s_axi_bvalid_reg && !s_axi_bready;

        case (write_state_reg)
            // Wait for host write address channel request flags
            WRITE_STATE_IDLE: begin
                s_axi_awready_next = 1'b1;

                if (s_axi_awready && s_axi_awvalid) begin
                    write_id_next    = s_axi_awid;
                    write_addr_next  = s_axi_awaddr;
                    write_count_next = s_axi_awlen;
                    write_size_next  = s_axi_awsize < $clog2(STRB_WIDTH) ? s_axi_awsize : $clog2(STRB_WIDTH);
                    write_burst_next = s_axi_awburst;

                    s_axi_awready_next = 1'b0;
                    s_axi_wready_next  = 1'b1; // Switch channel active link immediately to Data collection loop
                    write_state_next   = WRITE_STATE_BURST;
                end else begin
                    write_state_next = WRITE_STATE_IDLE;
                end
            end

            // Run sequential burst data loop collection steps
            WRITE_STATE_BURST: begin
                s_axi_wready_next = 1'b1;

                if (s_axi_wready && s_axi_wvalid) begin
                    mem_wr_en = 1'b1; // Trigger active pulse to write data block row array
                    if (write_burst_reg != 2'b00) begin
                        write_addr_next = write_addr_reg + (1 << write_size_reg); // Advance address pointer index
                    end
                    write_count_next = write_count_reg - 1'b1;
                    
                    if (write_count_reg > 0) begin
                        write_state_next = WRITE_STATE_BURST;
                    end else begin
                        s_axi_wready_next = 1'b0;
                        if (s_axi_bready || !s_axi_bvalid) begin
                            s_axi_bid_next     = write_id_reg;
                            s_axi_bvalid_next  = 1'b1; // Flash write status line acknowledgement high
                            s_axi_awready_next = 1'b1;
                            write_state_next   = WRITE_STATE_IDLE;
                        end else begin
                            write_state_next   = WRITE_STATE_RESP;
                        end
                    end
                end else begin
                    write_state_next = WRITE_STATE_BURST;
                end
            end

            // Wait until channel state lines clear to return handshake token back home
            WRITE_STATE_RESP: begin
                if (s_axi_bready || !s_axi_bvalid) begin
                    s_axi_bid_next     = write_id_reg;
                    s_axi_bvalid_next  = 1'b1;
                    s_axi_awready_next = 1'b1;
                    write_state_next   = WRITE_STATE_IDLE;
                end else begin
                    write_state_next   = WRITE_STATE_RESP;
                end
            end
        endcase
    end

    // Synchronous Write Commit State Latch Process Block
    always @(posedge clk) begin
        write_state_reg   <= write_state_next;
        write_id_reg      <= write_id_next;
        write_addr_reg    <= write_addr_next;
        write_count_reg   <= write_count_next;
        write_size_reg    <= write_size_next;
        write_burst_reg   <= write_burst_next;
        s_axi_awready_reg <= s_axi_awready_next;
        s_axi_wready_reg  <= s_axi_wready_next;
        s_axi_bid_reg     <= s_axi_bid_next;
        s_axi_bvalid_reg  <= s_axi_bvalid_next;

        // Byte Write Mask Strobe Resolution Multiplexer Structure Loop
        for (i = 0; i < WORD_WIDTH; i = i + 1) begin
            if (mem_wr_en && s_axi_wstrb[i]) begin
                mem[write_addr_valid][WORD_SIZE*i +: WORD_SIZE] <= s_axi_wdata[WORD_SIZE*i +: WORD_SIZE];
            end
        end

        if (rst) begin
            write_state_reg   <= WRITE_STATE_IDLE;
            s_axi_awready_reg <= 1'b0;
            s_axi_wready_reg  <= 1'b0;
            s_axi_bvalid_reg  <= 1'b0;
        end
    end

    //==========================================================================
    // AXI READ RETRIEVAL ENGINE DESIGN LAYER
    //==========================================================================
    always @* begin
        read_state_next    = READ_STATE_IDLE;
        mem_rd_en          = 1'b0;
        s_axi_rid_next     = s_axi_rid_reg;
        s_axi_rlast_next   = s_axi_rlast_reg;
        s_axi_rvalid_next  = s_axi_rvalid_reg && !(s_axi_rready || (PIPELINE_OUTPUT && !s_axi_rvalid_pipe_reg));
        read_id_next       = read_id_reg;
        read_addr_next     = read_addr_reg;
        read_count_next    = read_count_reg;
        read_size_next     = read_size_reg;
        read_burst_next    = read_burst_reg;
        s_axi_arready_next = 1'b0;

        case (read_state_reg)
            // Wait for incoming Read targets address requests
            READ_STATE_IDLE: begin
                s_axi_arready_next = 1'b1;

                if (s_axi_arready && s_axi_arvalid) begin
                    read_id_next    = s_axi_arid;
                    read_addr_next  = s_axi_araddr;
                    read_count_next = s_axi_arlen;
                    read_size_next  = s_axi_arsize < $clog2(STRB_WIDTH) ? s_axi_arsize : $clog2(STRB_WIDTH);
                    read_burst_next = s_axi_arburst;

                    s_axi_arready_next = 1'b0;
                    read_state_next    = READ_STATE_BURST;
                end else begin
                    read_state_next    = READ_STATE_IDLE;
                end
            end

            // Run sequential burst retrieval streams until final element flag hits boundary limits
            READ_STATE_BURST: begin
                if (s_axi_rready || (PIPELINE_OUTPUT && !s_axi_rvalid_pipe_reg) || !s_axi_rvalid_reg) begin
                    mem_rd_en         = 1'b1; // Trigger active read pulse lookahead line
                    s_axi_rvalid_next = 1'b1;
                    s_axi_rid_next    = read_id_reg;
                    s_axi_rlast_next  = (read_count_reg == 0);
                    
                    if (read_burst_reg != 2'b00) begin
                        read_addr_next = read_addr_reg + (1 << read_size_reg); // Increment read address offset index
                    end
                    read_count_next = read_count_reg - 1'b1;
                    
                    if (read_count_reg > 0) begin
                        read_state_next = READ_STATE_BURST;
                    end else begin
                        s_axi_arready_next = 1'b1;
                        read_state_next    = READ_STATE_IDLE; // Loop sequence clear. Head home.
                    end
                end else begin
                    read_state_next = READ_STATE_BURST;
                end
            end
        endcase
    end

    // Synchronous Read Latch & Pipeline Execution Process Block
    always @(posedge clk) begin
        read_state_reg    <= read_state_next;
        read_id_reg       <= read_id_next;
        read_addr_reg     <= read_addr_next;
        read_count_reg    <= read_count_next;
        read_size_reg     <= read_size_next;
        read_burst_reg    <= read_burst_next;
        s_axi_arready_reg <= s_axi_arready_next;
        s_axi_rid_reg     <= s_axi_rid_next;
        s_axi_rlast_reg   <= s_axi_rlast_next;
        s_axi_rvalid_reg  <= s_axi_rvalid_next;

        if (mem_rd_en) begin
            s_axi_rdata_reg <= mem[read_addr_valid];
        end

        // Pipeline Output Stage Register (Provides crucial isolation logic to boost operational speeds)
        if (!s_axi_rvalid_pipe_reg || s_axi_rready) begin
            s_axi_rid_pipe_reg    <= s_axi_rid_reg;
            s_axi_rdata_pipe_reg  <= s_axi_rdata_reg;
            s_axi_rlast_pipe_reg   <= s_axi_rlast_reg;
            s_axi_rvalid_pipe_reg <= s_axi_rvalid_reg;
        end

        if (rst) begin
            read_state_reg        <= READ_STATE_IDLE;
            s_axi_arready_reg     <= 1'b0;
            s_axi_rvalid_reg      <= 1'b0;
            s_axi_rvalid_pipe_reg <= 1'b0;
        end
    end

endmodule
`resetall