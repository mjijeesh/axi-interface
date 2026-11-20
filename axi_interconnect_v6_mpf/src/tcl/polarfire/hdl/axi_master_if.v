//------------------------------------------------------------------------------
// Company/Institution: Tecnomic Components
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

module axi4_master_if #(
    parameter integer RAM_ADDR_WIDTH  = 16,  // 2^16 = 65,536 x 64-bit words = 512 KB max
    parameter integer MAX_BURST_BEATS = 256  // 1..256 (256 = max AXI4 burst = 2 KB)
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // Local Control and Status Interface
    input  wire                      start_write,   // 1-cycle pulse: RAM -> AXI4
    input  wire                      start_read,    // 1-cycle pulse: AXI4 -> RAM
    input  wire [31:0]               base_address,  // 8-byte aligned target address
    input  wire [15:0]               word_count,    // Total 64-bit words (up to 65,535 = 512 KB)
    output reg                       axi_busy,
    output reg                       axi_done,

    // Internal Staging Block RAM Interface (Port B)
    output reg  [RAM_ADDR_WIDTH-1:0] ram_b_addr,
    output wire                      ram_b_we,
    output wire [63:0]               ram_b_wdata,
    input  wire [63:0]               ram_b_rdata,

    // AXI4 Write Address Channel (AW)
    output wire [7:0]                m_axi_awid,
    output reg  [31:0]               m_axi_awaddr,
    output reg  [7:0]                m_axi_awlen,
    output wire [2:0]                m_axi_awsize,
    output wire [1:0]                m_axi_awburst,
    output reg                       m_axi_awvalid,
    input  wire                      m_axi_awready,

    // AXI4 Write Data Channel (W)
    output reg  [63:0]               m_axi_wdata,
    output wire [7:0]                m_axi_wstrb,
    output reg                       m_axi_wlast,
    output reg                       m_axi_wvalid,
    input  wire                      m_axi_wready,

    // AXI4 Write Response Channel (B)
    input  wire [7:0]                m_axi_bid,
    input  wire [1:0]                m_axi_bresp,
    input  wire                      m_axi_bvalid,
    output wire                      m_axi_bready,

    // AXI4 Read Address Channel (AR)
    output wire [7:0]                m_axi_arid,
    output reg  [31:0]               m_axi_araddr,
    output reg  [7:0]                m_axi_arlen,
    output wire [2:0]                m_axi_arsize,
    output wire [1:0]                m_axi_arburst,
    output reg                       m_axi_arvalid,
    input  wire                      m_axi_arready,

    // AXI4 Read Data Channel (R)
    input  wire [7:0]                m_axi_rid,
    input  wire [63:0]               m_axi_rdata,
    input  wire [1:0]                m_axi_rresp,
    input  wire                      m_axi_rlast,
    input  wire                      m_axi_rvalid,
    output reg                       m_axi_rready
);

    assign m_axi_awid    = 8'h00;
    assign m_axi_arid    = 8'h00;
    assign m_axi_awsize  = 3'b011; // 8 bytes per beat
    assign m_axi_arsize  = 3'b011;
    assign m_axi_awburst = 2'b01;  // INCR
    assign m_axi_arburst = 2'b01;
    assign m_axi_wstrb   = 8'hFF;
    assign m_axi_bready  = 1'b1;

    localparam [3:0] STATE_IDLE       = 4'd0,
                     STATE_NEXT_BURST = 4'd1,
                     STATE_AW_STAGE   = 4'd2,
                     STATE_W_PREFETCH = 4'd3,
                     STATE_W_BURST    = 4'd4,
                     STATE_W_LAST     = 4'd5,
                     STATE_B_WAIT     = 4'd6,
                     STATE_AR_STAGE   = 4'd7,
                     STATE_R_BURST    = 4'd8;

    reg [3:0]                state;
    reg                      is_write_op;
    reg [31:0]               cur_addr;
    reg [15:0]               words_remaining;
    reg [8:0]                cur_burst_beats; // 1..256 beats in active sub-burst
    reg [8:0]                beat_counter;
    reg [RAM_ADDR_WIDTH-1:0] ram_burst_base;

    // Skid Buffer Registers for Write Stall Protection
    reg [63:0] holding_reg;
    reg        holding_valid;

    assign ram_b_wdata = m_axi_rdata;
    assign ram_b_we    = (state == STATE_R_BURST) && (m_axi_rvalid && m_axi_rready);

    // Combinational calculation of next sub-burst size (respects MAX_BURST_BEATS & 4 KB boundary)
    wire [9:0] words_to_4kb = 10'd512 - {1'b0, cur_addr[11:3]};
    reg  [8:0] next_beats;

    always @(*) begin
        next_beats = MAX_BURST_BEATS[8:0];
        if (words_remaining < {7'd0, next_beats})
            next_beats = words_remaining[8:0];
        if (words_to_4kb < {1'b0, next_beats})
            next_beats = words_to_4kb[8:0];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= STATE_IDLE;
            axi_busy        <= 1'b0;
            axi_done        <= 1'b0;
            is_write_op     <= 1'b0;
            cur_addr        <= 32'h0;
            words_remaining <= 16'h0;
            cur_burst_beats <= 9'h0;
            beat_counter    <= 9'h0;
            ram_burst_base  <= {RAM_ADDR_WIDTH{1'b0}};
            ram_b_addr      <= {RAM_ADDR_WIDTH{1'b0}};
            m_axi_awaddr    <= 32'h0;
            m_axi_awlen     <= 8'h0;
            m_axi_awvalid   <= 1'b0;
            m_axi_wdata     <= 64'h0;
            m_axi_wvalid    <= 1'b0;
            m_axi_wlast     <= 1'b0;
            m_axi_araddr    <= 32'h0;
            m_axi_arlen     <= 8'h0;
            m_axi_arvalid   <= 1'b0;
            m_axi_rready    <= 1'b0;
            holding_reg     <= 64'h0;
            holding_valid   <= 1'b0;
        end else begin
            axi_done <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    axi_busy       <= 1'b0;
                    beat_counter   <= 9'h0;
                    ram_burst_base <= {RAM_ADDR_WIDTH{1'b0}};
                    ram_b_addr     <= {RAM_ADDR_WIDTH{1'b0}};
                    holding_reg    <= 64'h0;
                    holding_valid  <= 1'b0;

                    if ((start_write || start_read) && (word_count != 16'd0)) begin
                        axi_busy        <= 1'b1;
                        is_write_op     <= start_write;
                        cur_addr        <= base_address;
                        words_remaining <= word_count;
                        state           <= STATE_NEXT_BURST;
                    end
                end

                // Dispatch next sub-burst or finish entire transfer
                STATE_NEXT_BURST: begin
                    beat_counter  <= 9'h0;
                    holding_valid <= 1'b0;
                    ram_b_addr    <= ram_burst_base;

                    if (words_remaining == 16'd0) begin
                        axi_done <= 1'b1;
                        axi_busy <= 1'b0;
                        state    <= STATE_IDLE;
                    end else begin
                        cur_burst_beats <= next_beats;
                        if (is_write_op) begin
                            m_axi_awaddr  <= cur_addr;
                            m_axi_awlen   <= next_beats[7:0] - 8'd1;
                            m_axi_awvalid <= 1'b1;
                            state         <= STATE_AW_STAGE;
                        end else begin
                            m_axi_araddr  <= cur_addr;
                            m_axi_arlen   <= next_beats[7:0] - 8'd1;
                            m_axi_arvalid <= 1'b1;
                            state         <= STATE_AR_STAGE;
                        end
                    end
                end

                STATE_AW_STAGE: begin
                    if (m_axi_awready && m_axi_awvalid) begin
                        m_axi_awvalid <= 1'b0;
                        ram_b_addr    <= ram_b_addr + 1'b1;
                        state         <= STATE_W_PREFETCH;
                    end
                end

                STATE_W_PREFETCH: begin
                    m_axi_wvalid <= 1'b1;
                    m_axi_wdata  <= ram_b_rdata;
                    ram_b_addr   <= ram_b_addr + 1'b1;

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
                        beat_counter <= beat_counter + 1'b1;
                        ram_b_addr   <= ram_b_addr + 1'b1;

                        if (holding_valid) begin
                            m_axi_wdata   <= holding_reg;
                            holding_valid <= 1'b0;
                        end else begin
                            m_axi_wdata   <= ram_b_rdata;
                        end

                        if (beat_counter == {1'b0, m_axi_awlen} - 9'd1) begin
                            m_axi_wlast <= 1'b1;
                            state       <= STATE_W_LAST;
                        end
                    end else if (!m_axi_wready && m_axi_wvalid) begin
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
                        words_remaining <= words_remaining - {7'd0, cur_burst_beats};
                        cur_addr        <= cur_addr + {20'd0, cur_burst_beats, 3'b000};
                        ram_burst_base  <= ram_burst_base + {{(RAM_ADDR_WIDTH-9){1'b0}}, cur_burst_beats};
                        ram_b_addr      <= ram_burst_base + {{(RAM_ADDR_WIDTH-9){1'b0}}, cur_burst_beats};
                        state           <= STATE_NEXT_BURST;
                    end
                end

                STATE_AR_STAGE: begin
                    if (m_axi_arready && m_axi_arvalid) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        ram_b_addr    <= ram_burst_base;
                        state         <= STATE_R_BURST;
                    end
                end

                STATE_R_BURST: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        ram_b_addr <= ram_b_addr + 1'b1;

                        if (m_axi_rlast) begin
                            m_axi_rready    <= 1'b0;
                            words_remaining <= words_remaining - {7'd0, cur_burst_beats};
                            cur_addr        <= cur_addr + {20'd0, cur_burst_beats, 3'b000};
                            ram_burst_base  <= ram_burst_base + {{(RAM_ADDR_WIDTH-9){1'b0}}, cur_burst_beats};
                            ram_b_addr      <= ram_burst_base + {{(RAM_ADDR_WIDTH-9){1'b0}}, cur_burst_beats};
                            state           <= STATE_NEXT_BURST;
                        end
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
`resetall