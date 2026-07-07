//------------------------------------------------------------------------------
// Company/Institution:  Tecnomic Components
// Engineer:             Jijeesh M
// 
// Create Date:          2026
// Module Name:          axi4_master_data_mover
// Project Name:         RTG4/SmartFusion2 Serial to AXI Memory Staging System
// Target Devices:       Microchip SmartFusion2 / RTG4 Fabric Core Architecture
// Tool Versions:        Libero SoC Design Suite v12.0+
//
// Description:
//   This module implements a high-speed AXI4 Full Master controller interface.
//   It acts as a coprocessor that moves blocks of data back and forth between
//   the Port B channel of the internal dual-port staging buffer RAM and an
//   external AXI4 memory architecture at full clock rates.
//
//   Handshake Pipelines:
//     - Write Loop: Pulls data from the staging RAM and drives it out over the 
//       AXI Write Address (AW) and Write Data (W) channels using dynamic bursts.
//     - Read Loop: Issues requests over the AXI Read Address (AR) channel, 
//       swallows incoming data beats over the Read Data (R) channel, and streams
//       them directly into Port B of the staging buffer RAM.
//
// Dependencies:
//   - ram_2k_true_dual_port (Staging memory framework)
//   - system_control_fsm    (Main protocol coordinator engine)
//
// Revision History:
//   v1.0 - Baseline hardware data mover engine framework.
//   v2.0 - Added static AXI ID tag fields and dual-direction channel maps.
//   v2.1 - Patched duplicate port conflicts and aligned vector bit widths.
//------------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module axi4_master_data_mover (
    //--------------------------------------------------------------------------
    // Core Clock and System Reset Inputs
    //--------------------------------------------------------------------------
    input  wire         clk,           // Main global fabric execution clock (80 MHz)
    input  wire         rst_n,         // Synchronized active-low logic domain reset
    
    //--------------------------------------------------------------------------
    // Local Control and Status Interface (From Protocol Engine)
    //--------------------------------------------------------------------------
    input  wire         start_write,   // 1-cycle active-high pulse to trigger RAM -> AXI
    input  wire         start_read,    // 1-cycle active-high pulse to trigger AXI -> RAM
    input  wire  [31:0] base_address,  // Target memory destination base address pointer
    input  wire  [15:0] word_count,    // Total number of 64-bit words to transfer
    output reg          mover_busy,    // Asserted high continuously throughout transaction
    output reg          mover_done,    // Active-high pulse for 1 clock cycle on complete

    //--------------------------------------------------------------------------
    // Internal Staging Block RAM Interface Channel (Port B Mapping)
    //--------------------------------------------------------------------------
    output reg   [7:0]  ram_b_addr,    // 8-bit Port B read/write pointer address index
    output reg          ram_b_we,      // Port B active-high write enable strobe line
    output reg   [63:0] ram_b_wdata,   // Port B 64-bit input data bus to staging memory
    input  wire  [63:0] ram_b_rdata,   // Port B 64-bit output read data from staging memory

    //--------------------------------------------------------------------------
    // Exported External AXI4 Full Master System Bus Ports
    //--------------------------------------------------------------------------
    // Write Address Channel (AW)
    output wire  [7:0]  m_axi_awid,    // Outbound write transaction thread identification tag
    output reg   [31:0] m_axi_awaddr,  // Outbound target burst destination write address
    output reg   [7:0]  m_axi_awlen,   // AXI4 Burst Length (Number of data beats = AWLEN + 1)
    output wire  [2:0]  m_axi_awsize,  // Burst Size: Bytes per beat (3'b011 = 8 bytes / 64-bit)
    output wire  [1:0]  m_axi_awburst, // Burst Type: Address modification rule (2'b01 = INCR)
    output reg          m_axi_awvalid, // Write address valid line indicator
    input  wire         m_axi_awready, // Slave write address channel acceptance flag
    
    // Write Data Channel (W)
    output wire  [63:0] m_axi_wdata,   // Parallel burst payload data transmission lanes
    output wire  [7:0]  m_axi_wstrb,   // Write byte lanes valid indicator strobe flag
    output reg          m_axi_wlast,   // Active-high indicator on the final transfer beat
    output reg          m_axi_wvalid,  // Write data payload valid line indicator
    input  wire         m_axi_wready,  // Slave write data channel acceptance flag
    
    // Write Response Channel (B)
    input  wire  [7:0]  m_axi_bid,     // Slave response identifier match tag
    input  wire  [1:0]  m_axi_bresp,   // Write transaction error status feedback loop
    input  wire         m_axi_bvalid,  // Slave response channel valid indicator
    output wire         m_axi_bready,  // Master response acceptance line flag
    
    // Read Address Channel (AR)
    output wire  [7:0]  m_axi_arid,    // Outbound read transaction thread identification tag
    output reg   [31:0] m_axi_araddr,  // Outbound target burst source read address
    output reg   [7:0]  m_axi_arlen,   // AXI4 Burst Length (Number of data beats = ARLEN + 1)
    output wire  [2:0]  m_axi_arsize,  // Burst Size: Bytes per beat (3'b011 = 8 bytes / 64-bit)
    output wire  [1:0]  m_axi_arburst, // Burst Type: Address modification rule (2'b01 = INCR)
    output reg          m_axi_arvalid, // Read address valid line indicator
    input  wire         m_axi_arready, // Slave read address channel acceptance flag
    
    // Read Data Channel (R)
    input  wire  [7:0]  m_axi_rid,     // Slave read data thread identifier tag
    input  wire  [63:0] m_axi_rdata,   // Parallel incoming payload read data lanes
    input  wire  [1:0]  m_axi_rresp,   // Read transaction error status feedback loop
    input  wire         m_axi_rlast,   // High indicating final data beat from slave
    input  wire         m_axi_rvalid,  // Slave data valid line indicator
    output reg          m_axi_rready   // Master read data channel acceptance flag
);

    //--------------------------------------------------------------------------
    // Static Bus Feature Assignments (Point-to-Point Single Master Optimizations)
    //--------------------------------------------------------------------------
    assign m_axi_awid    = 8'h00;  // Static ID Tag for isolated unthreaded setups
    assign m_axi_arid    = 8'h00;  // Static ID Tag for isolated unthreaded setups
    assign m_axi_awsize  = 3'b011; // 2^3 = 8 Bytes per data beat (Matches 64-bit lane width)
    assign m_axi_arsize  = 3'b011; // 2^3 = 8 Bytes per data beat (Matches 64-bit lane width)
    assign m_axi_awburst = 2'b01;  // Incrementing Burst Type (Addresses advance sequentially)
    assign m_axi_arburst = 2'b01;  // Incrementing Burst Type (Addresses advance sequentially)
    assign m_axi_wstrb   = 8'hFF;  // Assert all 8 byte lanes as continuously valid
    assign m_axi_bready  = 1'b1;   // Master is always ready to accept write status responses

    // Transparently forward staging RAM Port B data straight out onto the active AXI bus
    assign m_axi_wdata   = ram_b_rdata;

    //--------------------------------------------------------------------------
    // Finite State Machine Parameters & Register Trackers
    //--------------------------------------------------------------------------
    localparam [2:0] STATE_IDLE      = 3'd0,
                     STATE_AW_STAGE  = 3'd1,
                     STATE_W_BURST   = 3'd2,
                     STATE_B_WAIT    = 3'd3,
                     STATE_AR_STAGE  = 3'd4,
                     STATE_R_BURST   = 3'd5,
                     STATE_COMPLETED = 3'd6;

    reg [2:0]  state;               // Main data mover pipeline state tracking register
    reg [15:0] loop_counter;        // Internal beat counter tracking the burst index loop
    reg [7:0]  ram_pointer;         // Tracking index referencing local staging RAM spaces

    //--------------------------------------------------------------------------
    // Main Synchronous Sequencer Process Logic Block
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= STATE_IDLE;
            mover_busy    <= 1'b0;
            mover_done    <= 1'b0;
            ram_b_addr    <= 8'h0;
            ram_b_we      <= 1'b0;
            ram_b_wdata   <= 64'h0;
            m_axi_awaddr  <= 32'h0;
            m_axi_awlen   <= 8'h0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_wlast   <= 1'b0;
            m_axi_araddr  <= 32'h0;
            m_axi_arlen   <= 8'h0;
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            loop_counter  <= 16'h0;
            ram_pointer   <= 8'h0;
        end else begin
            mover_done <= 1'b0;     // Default fallback to guarantee 1-clock pulse width
            ram_b_we   <= 1'b0;     // Default fallback to prevent accidental memory overwrites

            case (state)
                // Wait for a launch trigger pulse from the primary UART controller FSM
                STATE_IDLE: begin
                    mover_busy   <= 1'b0;
                    loop_counter <= 16'h0;
                    ram_pointer  <= 8'h0;
                    
                    if (start_write) begin
                        mover_busy    <= 1'b1;
                        m_axi_awaddr  <= base_address;
                        // AXI burst length uses N-1 notation (e.g. 0x00 = 1 beat transfer)
                        m_axi_awlen   <= word_count - 1'b1; 
                        m_axi_awvalid <= 1'b1;
                        
                        // Prime the Staging Buffer RAM read pipeline lookahead address loop
                        ram_b_addr    <= 8'd0; 
                        state         <= STATE_AW_STAGE;
                    end else if (start_read) begin
                        mover_busy    <= 1'b1;
                        m_axi_araddr  <= base_address;
                        m_axi_arlen   <= word_count - 1'b1; // N-1 notation conversion rule
                        m_axi_arvalid <= 1'b1;
                        state         <= STATE_AR_STAGE;
                    end
                end

                //--------------------------------------------------------------
                // AXI WRITE CHANNEL HANDSHAKING PIPELINE
                //--------------------------------------------------------------
                
                // Establish address channel link validation before bursting data payload
                STATE_AW_STAGE: begin
                    if (m_axi_awready && m_axi_awvalid) begin
                        m_axi_awvalid <= 1'b0; // De-assert address valid immediately on handshake clear
                        m_axi_wvalid  <= 1'b1; // Turn on data payload stream lines
                        
                        // Advance lookahead pointer to cache memory cells for the next clock beat
                        ram_b_addr    <= ram_pointer + 1'b1; 
                        
                        if (m_axi_awlen == 8'd0)
                            m_axi_wlast <= 1'b1; // Handle 1-beat single operations safely
                            
                        state <= STATE_W_BURST;
                    end
                end

                // Stream elements out from staging block RAM directly to target system memory space
                STATE_W_BURST: begin
                    if (m_axi_wready && m_axi_wvalid) begin
                        loop_counter <= loop_counter + 1'b1;
                        ram_pointer  <= ram_pointer + 1'b1;
                        
                        if (m_axi_wlast) begin
                            m_axi_wvalid <= 1'b0; // Turn off data stream line on transaction complete
                            m_axi_wlast  <= 1'b0; // Drop final transmission beat flag
                            state        <= STATE_B_WAIT;
                        end else begin
                            // Advance staging buffer RAM read pointer to stay ahead of the next AXI data beat
                            ram_b_addr <= ram_pointer + 2'd2; 
                            
                            // Check if the next beat is the final transfer element in the burst
                            if (loop_counter == m_axi_awlen - 1'b1) begin
                                m_axi_wlast <= 1'b1;
                            end
                        end
                    end
                end

                // Wait for the slave device to confirm the transaction cleared its internal caches
                STATE_B_WAIT: begin
                    if (m_axi_bvalid) begin
                        state <= STATE_COMPLETED;
                    end
                end

                //--------------------------------------------------------------
                // AXI READ CHANNEL HANDSHAKING PIPELINE
                //--------------------------------------------------------------
                
                // Establish read source location boundaries on external system bus
                STATE_AR_STAGE: begin
                    if (m_axi_arready && m_axi_arvalid) begin
                        m_axi_arvalid <= 1'b0; // Drop read target address line immediately
                        m_axi_rready  <= 1'b1; // Assert ready to accept incoming streaming elements
                        state         <= STATE_R_BURST;
                    end
                end

                // Catch incoming streaming beats and write them directly into Staging RAM Port B
                STATE_R_BURST: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        ram_b_we    <= 1'b1;             // Pulse write enable high for local staging BRAM
                        ram_b_addr  <= ram_pointer;      // Target local pointer index address
                        ram_b_wdata <= m_axi_rdata;      // Route parallel bus word directly to data input bus
                        ram_pointer <= ram_pointer + 1'b1;
                        
                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0;        // Drop channel acceptance line immediately
                            state        <= STATE_COMPLETED;
                        end
                    end
                end

                //--------------------------------------------------------------
                // CORE TRANSACTION CLOSURE
                //--------------------------------------------------------------
                STATE_COMPLETED: begin
                    mover_done <= 1'b1; // Pulse done high to alert the core protocol FSM
                    state      <= STATE_IDLE;
                end
            endcase
        end
    end
endmodule
`resetall