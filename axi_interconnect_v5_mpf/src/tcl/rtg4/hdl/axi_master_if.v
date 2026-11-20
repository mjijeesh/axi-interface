//------------------------------------------------------------------------------
// Company/Institution:  Creative System Labs
// Engineer:             Jijeesh M 
// 
// Create Date:          2026
// Module Name:          axi4_master_if
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
//   Stall-Protection Fix (v3.8):
//     - Integrated a synchronous holding/skid register to buffer in-flight 
//       BRAM read data during AXI write stalls (WREADY deassertion).
//     - Fixed recovery logic to always increment ram_b_addr on a successful
//       handshake, maintaining perfect address-to-beat synchronization.
//     - Guarantees 100% data integrity during write stalls with zero lost, 
//       skipped, or duplicate data beats.
//------------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module axi4_master_if (
    // Core Clock and System Reset Inputs
    input  wire           clk,           // Main global fabric execution clock (80 MHz)
    input  wire           rst_n,         // Synchronized active-low logic domain reset
    
    // Local Control and Status Interface
    input  wire           start_write,   // 1-cycle active-high pulse to trigger RAM -> AXI
    input  wire           start_read,    // 1-cycle active-high pulse to trigger AXI -> RAM
    input  wire  [31:0]   base_address,  // Target memory destination base address pointer
    input  wire  [15:0]   word_count,    // Total number of 64-bit words to transfer
    output reg            axi_busy,      // Asserted high continuously throughout transaction
    output reg            axi_done,      // Active-high pulse for 1 clock cycle on complete

    // Internal Staging Block RAM Interface Channel (Port B Wire Mapping)
    output reg   [7:0]    ram_b_addr,    // Pure sequential register pointer index
    output wire           ram_b_we,      // Combinational Port B write enable strobe line
    output wire  [63:0]   ram_b_wdata,   // Combinational Port B data routing input bus
    input  wire  [63:0]   ram_b_rdata,   // Port B parallel synchronous read data lane

    // Exported External AXI4 Full Master System Bus Ports
    // Write Address Channel (AW)
    output wire  [7:0]    m_axi_awid,    
    output reg   [31:0]   m_axi_awaddr,  
    output reg   [7:0]    m_axi_awlen,   
    output wire  [2:0]    m_axi_awsize,  
    output wire  [1:0]    m_axi_awburst, 
    output reg            m_axi_awvalid, 
    input  wire           m_axi_awready, 
    
    // Write Data Channel (W)
    output reg   [63:0]   m_axi_wdata,   
    output wire  [7:0]    m_axi_wstrb,   
    output reg            m_axi_wlast,   
    output reg            m_axi_wvalid,  
    input  wire           m_axi_wready,  
    
    // Write Response Channel (B)
    input  wire  [7:0]    m_axi_bid,     
    input  wire  [1:0]    m_axi_bresp,   
    input  wire           m_axi_bvalid,  
    output wire           m_axi_bready,  
    
    // Read Address Channel (AR)
    output wire  [7:0]    m_axi_arid,    
    output reg   [31:0]   m_axi_araddr,  
    output reg   [7:0]    m_axi_arlen,   
    output wire  [2:0]    m_axi_arsize,  
    output wire  [1:0]    m_axi_arburst, 
    output reg            m_axi_arvalid, 
    input  wire           m_axi_arready, 
    
    // Read Data Channel (R)
    input  wire  [7:0]    m_axi_rid,     
    input  wire  [63:0]   m_axi_rdata,   
    input  wire  [1:0]    m_axi_rresp,   
    input  wire           m_axi_rlast,   
    input  wire           m_axi_rvalid,  
    output reg            m_axi_rready   
);

    // Static Bus Feature Assignments
    assign m_axi_awid    = 8'h00;     
    assign m_axi_arid    = 8'h00;     
    assign m_axi_awsize  = 3'b011;    // 8 Bytes per data beat (64-bit width)
    assign m_axi_arsize  = 3'b011;    
    assign m_axi_awburst = 2'b01;     // Incrementing Burst Type
    assign m_axi_arburst = 2'b01;     
    assign m_axi_wstrb   = 8'hFF;     // Assert all byte lanes
    assign m_axi_bready  = 1'b1;     // Master always ready for responses

    // FSM States
    localparam [2:0] STATE_IDLE       = 3'd0,
                     STATE_AW_STAGE   = 3'd1,
                     STATE_W_PREFETCH = 3'd2,
                     STATE_W_BURST    = 3'd3,
                     STATE_W_LAST     = 3'd4,
                     STATE_B_WAIT     = 3'd5,
                     STATE_AR_STAGE   = 3'd6,
                     STATE_R_BURST    = 3'd7;

    reg [2:0]  state;               
    reg [15:0] loop_counter;        

    // Skid Buffer Registers for Stall Protection
    reg [63:0] holding_reg;         // Holds the committed read beat during a pipeline stall
    reg        holding_valid;       // High when the holding register contains unread valid data

    // Combinational RAM Interface Link Mappings
    assign ram_b_wdata = m_axi_rdata;
    assign ram_b_we    = (state == STATE_R_BURST) && (m_axi_rvalid && m_axi_rready);
    
    // FSM Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= STATE_IDLE;
            axi_busy      <= 1'b0;
            axi_done      <= 1'b0;
            m_axi_awaddr  <= 32'h0;
            m_axi_awlen   <= 8'h0;
            m_axi_awvalid <= 1'b0;
            m_axi_wdata   <= 64'h0;
            m_axi_wvalid  <= 1'b0;
            m_axi_wlast   <= 1'b0;
            m_axi_araddr  <= 32'h0;
            m_axi_arlen   <= 8'h0;
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            loop_counter  <= 16'h0;
            ram_b_addr    <= 8'h0;
            holding_reg   <= 64'h0;
            holding_valid <= 1'b0;
        end else begin
            axi_done <= 1'b0; 

            case (state)
                STATE_IDLE: begin
                    axi_busy      <= 1'b0;
                    loop_counter  <= 16'h0;
                    ram_b_addr    <= 8'h0; // Prime address pointer back to 0
                    holding_reg   <= 64'h0;
                    holding_valid <= 1'b0;
                    
                    if (start_write) begin
                        axi_busy      <= 1'b1;
                        m_axi_awaddr  <= base_address;
                        m_axi_awlen   <= word_count - 1'b1; 
                        m_axi_awvalid <= 1'b1;
                        state         <= STATE_AW_STAGE;
                    end else if (start_read) begin
                        axi_busy      <= 1'b1;
                        m_axi_araddr  <= base_address;
                        m_axi_arlen   <= word_count - 1'b1; 
                        m_axi_arvalid <= 1'b1;
                        state         <= STATE_AR_STAGE;
                    end
                end

                STATE_AW_STAGE: begin
                    if (m_axi_awready && m_axi_awvalid) begin
                        m_axi_awvalid <= 1'b0;
                        ram_b_addr    <= ram_b_addr + 1'b1; // Lock address 0 while wait states pass
                        state         <= STATE_W_PREFETCH;
                    end
                end

                STATE_W_PREFETCH: begin
                    m_axi_wvalid <= 1'b1;  
                    m_axi_wdata  <= ram_b_rdata;       // Perfectly registers location 0 data
                    ram_b_addr   <= ram_b_addr + 1'b1; // Prefetch location 1 data for next cycle
                    
                    if (m_axi_awlen == 8'd0) begin
                        m_axi_wlast <= 1'b1;
                        state       <= STATE_W_LAST; 
                    end else begin
                        m_axi_wlast <= 1'b0;
                        state       <= STATE_W_BURST;
                    end
                end

                STATE_W_BURST: begin
                    if (m_axi_wready && m_axi_wvalid) begin
                        // Master-Slave Handshake Completed successfully!
                        loop_counter <= loop_counter + 1'b1;
                        ram_b_addr   <= ram_b_addr + 1'b1; // Address always increments on handshake to shift pipeline
                        
                        if (holding_valid) begin
                            // Recover stalled data from the holding skid register
                            m_axi_wdata   <= holding_reg;
                            holding_valid <= 1'b0;
                        end else begin
                            // Read normally from the active block RAM output lane
                            m_axi_wdata   <= ram_b_rdata;
                        end
                        
                        if (loop_counter == m_axi_awlen - 1'b1) begin
                            m_axi_wlast <= 1'b1;
                            state       <= STATE_W_LAST;
                        end
                    end else if (!m_axi_wready && m_axi_wvalid) begin
                        // STALL DETECTED (Slave dropped WREADY)!
                        // Capture the currently active in-flight BRAM data before it gets overwritten
                        if (!holding_valid) begin
                            holding_reg   <= ram_b_rdata;
                            holding_valid <= 1'b1;
                        end
                    end
                end

                STATE_W_LAST: begin
                    if (m_axi_wready && m_axi_wvalid) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_wlast  <= 1'b0;
                        state        <= STATE_B_WAIT;
                    end
                end

                STATE_B_WAIT: begin
                    if (m_axi_bvalid) begin
                        axi_done <= 1'b1; 
                        state    <= STATE_IDLE;
                    end
                end

                STATE_AR_STAGE: begin
                    if (m_axi_arready && m_axi_arvalid) begin
                        m_axi_arvalid <= 1'b0; 
                        m_axi_rready  <= 1'b1; 
                        ram_b_addr    <= 8'h0; // Read directly back into staging RAM location 0
                        loop_counter  <= 16'h0;
                        state         <= STATE_R_BURST;
                    end
                end

                // Direct Master-to-Slave coupled streaming
                STATE_R_BURST: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        loop_counter <= loop_counter + 1'b1;
                        ram_b_addr   <= ram_b_addr + 1'b1; 
                        
                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0; 
                            axi_done     <= 1'b1; 
                            state        <= STATE_IDLE;
                        end
                    end
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
`resetall