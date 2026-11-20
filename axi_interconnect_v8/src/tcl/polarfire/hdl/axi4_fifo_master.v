//------------------------------------------------------------------------------
// Module: axi4_fifo_master
// Description:
//   Autonomous FIFO-to-AXI4 Write Master with Threshold Triggering, Idle-Gap
//   Partial Burst Flushing, Circular Buffer Wrapping, and MSS Interrupt Generation.
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module axi4_fifo_master #(
    parameter ID_WIDTH   = 1,   // Matches COREAXI4INTERCONNECT_C0 ID_WIDTH=1
    parameter ADDR_WIDTH = 32,  // Matches COREAXI4INTERCONNECT_C0 ADDR_WIDTH=32
    parameter CNT_WIDTH  = 12   // Matches COREFIFO_C0 RDEPTH=2048 -> RDCNT[11:0]
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Autonomous DMA & Interrupt Configuration / Status Interface
    input  wire                   stream_en,          // 1 = Autonomous FIFO drain enabled
    input  wire                   soft_rst,           // Active-high synchronous reset of pointers/IRQ
    input  wire [ADDR_WIDTH-1:0]  base_address,       // 8-byte aligned destination base address
    input  wire [31:0]            buffer_size,        // Ring buffer size in bytes (0 = linear)
    input  wire [CNT_WIDTH-1:0]   burst_threshold,    // Min 64-bit words in FIFO to start burst (e.g. 16)
    input  wire [15:0]            idle_flush_cycles,  // Idle cycles before flushing partial burst (0 = off)

    input  wire                   irq_en,             // 1 = Enable MSS interrupt generation
    input  wire                   irq_ack,            // 1 = Acknowledge/clear level-sensitive mss_irq
    input  wire [31:0]            irq_chunk_bytes,    // Bytes committed per MSS interrupt (e.g. 512)
    output reg                    mss_irq,            // Level-sensitive IRQ to MSS_INT_F2M (cleared by irq_ack)
    output reg                    mss_irq_pulse,      // Single-cycle IRQ pulse on chunk commit
    output reg  [15:0]            irq_pending_cnt,    // Unacknowledged interrupt events count
    output reg  [31:0]            last_irq_offset,    // Buffer byte offset of most recent IRQ chunk

    output reg                    axi_busy,           // 1 = AXI4 write burst currently in flight
    output reg                    axi_err,            // Sticky flag: non-OKAY AXI4 BRESP detected
    output reg  [31:0]            wr_offset,          // Current byte offset from base_address
    output reg  [31:0]            total_bytes_written,// Total bytes committed via BVALID/BREADY

    // COREFIFO_C0 64-bit Read Interface (Standard Read Mode, PIPE=1)
    input  wire [63:0]            fifo_q,
    output wire                   fifo_re,
    input  wire                   fifo_empty,
    input  wire [CNT_WIDTH-1:0]   fifo_rdcnt,

    // AXI4 64-bit Master Interface -> BIF "AXI4_Master"
    output wire [ID_WIDTH-1:0]    m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output reg  [7:0]             m_axi_awlen,
    output wire [2:0]             m_axi_awsize,
    output wire [1:0]             m_axi_awburst,
    output reg                    m_axi_awvalid,
    input  wire                   m_axi_awready,

    output wire [63:0]            m_axi_wdata,
    output wire [7:0]             m_axi_wstrb,
    output wire                   m_axi_wlast,
    output wire                   m_axi_wvalid,
    input  wire                   m_axi_wready,

    input  wire [ID_WIDTH-1:0]    m_axi_bid,
    input  wire [1:0]             m_axi_bresp,
    input  wire                   m_axi_bvalid,
    output wire                   m_axi_bready,

    // Unused AXI4 Read Channel (tied off cleanly for AXI4_Master BIF completeness)
    output wire [ID_WIDTH-1:0]    m_axi_arid,
    output wire [ADDR_WIDTH-1:0]  m_axi_araddr,
    output wire [7:0]             m_axi_arlen,
    output wire [2:0]             m_axi_arsize,
    output wire [1:0]             m_axi_arburst,
    output wire                   m_axi_arvalid,
    input  wire                   m_axi_arready,

    input  wire [ID_WIDTH-1:0]    m_axi_rid,
    input  wire [63:0]            m_axi_rdata,
    input  wire [1:0]             m_axi_rresp,
    input  wire                   m_axi_rlast,
    input  wire                   m_axi_rvalid,
    output wire                   m_axi_rready
);

    localparam [4:0] MAX_BURST_BEATS = 5'd16; // 16 x 8B = 128 bytes per AXI4 INCR burst

    // Fixed AXI4 attributes
    assign m_axi_awid    = {ID_WIDTH{1'b0}};
    assign m_axi_awsize  = 3'b011; // 8 bytes (64-bit)
    assign m_axi_awburst = 2'b01;  // INCR
    assign m_axi_wstrb   = 8'hFF;

    assign m_axi_arid    = {ID_WIDTH{1'b0}};
    assign m_axi_araddr  = {ADDR_WIDTH{1'b0}};
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = 3'b011;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = 1'b0;
    assign m_axi_rready  = 1'b0;

    // -------------------------------------------------------------------------
    // 1. Standard-Mode CoreFIFO (PIPE=1) 1-Word Skid Buffer
    //    COREFIFO_C0 presents valid data on fifo_q 1 clock after fifo_re=1.
    // -------------------------------------------------------------------------
    reg        re_d1;
    reg        skid_valid;
    reg [63:0] skid_data;

    wire w_beat_accepted = m_axi_wvalid && m_axi_wready;
    wire fifo_pop        = (!fifo_empty) && (!re_d1) && (!skid_valid || w_beat_accepted);

    assign fifo_re = fifo_pop;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            re_d1      <= 1'b0;
            skid_valid <= 1'b0;
            skid_data  <= 64'd0;
        end else if (soft_rst) begin
            re_d1      <= 1'b0;
            skid_valid <= 1'b0;
            skid_data  <= 64'd0;
        end else begin
            re_d1 <= fifo_pop;

            if (re_d1) begin
                skid_data  <= fifo_q;
                skid_valid <= 1'b1;
            end else if (w_beat_accepted) begin
                skid_valid <= 1'b0;
            end
        end
    end

    // Conserved count of 64-bit words ready across FIFO + prefetch pipeline
    wire [CNT_WIDTH:0] total_avail_words = {1'b0, fifo_rdcnt}
                                         + {{CNT_WIDTH{1'b0}}, skid_valid}
                                         + {{CNT_WIDTH{1'b0}}, re_d1};

    // -------------------------------------------------------------------------
    // 2. Producer Delay Monitor (Idle-Flush Timer)
    //    Tracks how long partial data (< burst_threshold) sits waiting in FIFO.
    // -------------------------------------------------------------------------
    localparam [1:0] ST_IDLE = 2'd0,
                     ST_ADDR = 2'd1,
                     ST_DATA = 2'd2,
                     ST_RESP = 2'd3;

    reg [1:0]           state;
    reg [CNT_WIDTH-1:0] prev_rdcnt;
    reg [15:0]          idle_cnt;

    wire [CNT_WIDTH-1:0] eff_threshold = (burst_threshold == {CNT_WIDTH{1'b0}})
                                       ? {{(CNT_WIDTH-1){1'b0}}, 1'b1}
                                       : burst_threshold;

    wire has_data        = (total_avail_words != {(CNT_WIDTH+1){1'b0}});
    wire above_threshold = (total_avail_words >= {1'b0, eff_threshold});
    wire rdcnt_grew      = (fifo_rdcnt > prev_rdcnt);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_rdcnt <= {CNT_WIDTH{1'b0}};
            idle_cnt   <= 16'd0;
        end else if (soft_rst) begin
            prev_rdcnt <= {CNT_WIDTH{1'b0}};
            idle_cnt   <= 16'd0;
        end else begin
            prev_rdcnt <= fifo_rdcnt;

            if (!stream_en || !has_data || above_threshold || (state != ST_IDLE) || rdcnt_grew) begin
                idle_cnt <= 16'd0;
            end else if ((idle_flush_cycles != 16'd0) && (idle_cnt < idle_flush_cycles)) begin
                idle_cnt <= idle_cnt + 16'd1;
            end
        end
    end

    wire idle_flush_trigger = (idle_flush_cycles != 16'd0) &&
                              has_data &&
                              (idle_cnt >= idle_flush_cycles);

    // -------------------------------------------------------------------------
    // 3. Burst Sizing (4KB AXI Boundary + Ring Buffer Wrap Clamping)
    // -------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] aligned_base = {base_address[ADDR_WIDTH-1:3], 3'b000};
    wire [31:0]           aligned_size = {buffer_size[31:3], 3'b000};
    wire [ADDR_WIDTH-1:0] next_awaddr  = aligned_base + wr_offset;

    // Max 8-byte beats before crossing an AXI4 4KB (0x1000) boundary
    wire [8:0] max_4k_beats = 9'd256 - {1'b0, next_awaddr[11:3]};

    // Max 8-byte beats before reaching end of circular buffer (when buffer_size > 0)
    wire [31:0] rem_buf_bytes = (aligned_size > wr_offset) ? (aligned_size - wr_offset) : 32'd0;
    wire [8:0]  max_buf_beats = (aligned_size == 32'd0) ? 9'd256 :
                                (rem_buf_bytes[31:3] > 29'd256) ? 9'd256 : rem_buf_bytes[11:3];

    reg [8:0] cand_beats;
    always @(*) begin
        cand_beats = {4'd0, MAX_BURST_BEATS};
        if (total_avail_words < {{(CNT_WIDTH-8){1'b0}}, cand_beats}) begin
            cand_beats = total_avail_words[8:0];
        end
        if (cand_beats > max_4k_beats) begin
            cand_beats = max_4k_beats;
        end
        if ((aligned_size != 32'd0) && (cand_beats > max_buf_beats)) begin
            cand_beats = max_buf_beats;
        end
    end

    // Start burst autonomously when watermark threshold is met OR idle-flush expires
    wire ready_to_burst = stream_en && !soft_rst && (cand_beats != 9'd0) &&
                          (above_threshold || idle_flush_trigger);

    // -------------------------------------------------------------------------
    // 4. AXI4 Write Master FSM & MSS Interrupt Controller
    // -------------------------------------------------------------------------
    reg [7:0]  beats_rem;
    reg [8:0]  burst_beats;
    reg        burst_was_flushed;
    reg [31:0] irq_byte_accum;

    wire [31:0] eff_irq_bytes = (irq_chunk_bytes == 32'd0) ? 32'd512 : irq_chunk_bytes;
    wire [31:0] burst_bytes   = {20'd0, burst_beats, 3'b000};
    wire [31:0] next_wr_off   = wr_offset + burst_bytes;
    wire [31:0] next_irq_acc  = irq_byte_accum + burst_bytes;

    // Fire interrupt on AXI write response when accumulated committed bytes reach
    // irq_chunk_bytes OR when an idle-flush finishes draining the FIFO.
    wire b_handshake = (state == ST_RESP) && m_axi_bvalid && m_axi_bready;
    wire irq_fire    = b_handshake && (
                           (next_irq_acc >= eff_irq_bytes) ||
                           (burst_was_flushed && !has_data && (next_irq_acc != 32'd0))
                       );

    assign m_axi_wdata  = skid_data;
    assign m_axi_wvalid = (state == ST_DATA) && skid_valid;
    assign m_axi_wlast  = (state == ST_DATA) && (beats_rem == 8'd0);
    assign m_axi_bready = (state == ST_RESP);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= ST_IDLE;
            axi_busy            <= 1'b0;
            axi_err             <= 1'b0;
            wr_offset           <= 32'd0;
            total_bytes_written <= 32'd0;
            beats_rem           <= 8'd0;
            burst_beats         <= 9'd0;
            burst_was_flushed   <= 1'b0;
            m_axi_awaddr        <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen         <= 8'd0;
            m_axi_awvalid       <= 1'b0;
            irq_byte_accum      <= 32'd0;
            mss_irq             <= 1'b0;
            mss_irq_pulse       <= 1'b0;
            irq_pending_cnt     <= 16'd0;
            last_irq_offset     <= 32'd0;
        end else if (soft_rst) begin
            state               <= ST_IDLE;
            axi_busy            <= 1'b0;
            axi_err             <= 1'b0;
            wr_offset           <= 32'd0;
            total_bytes_written <= 32'd0;
            beats_rem           <= 8'd0;
            burst_beats         <= 9'd0;
            burst_was_flushed   <= 1'b0;
            m_axi_awaddr        <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen         <= 8'd0;
            m_axi_awvalid       <= 1'b0;
            irq_byte_accum      <= 32'd0;
            mss_irq             <= 1'b0;
            mss_irq_pulse       <= 1'b0;
            irq_pending_cnt     <= 16'd0;
            last_irq_offset     <= 32'd0;
        end else begin
            mss_irq_pulse <= 1'b0;

            // Level-sensitive MSS interrupt set/acknowledge tracking
            if (irq_fire && irq_en) begin
                mss_irq         <= 1'b1;
                mss_irq_pulse   <= 1'b1;
                last_irq_offset <= wr_offset;
                if (!irq_ack) begin
                    irq_pending_cnt <= irq_pending_cnt + 16'd1;
                end
            end else if (irq_ack) begin
                mss_irq         <= 1'b0;
                irq_pending_cnt <= 16'd0;
            end

            case (state)
                ST_IDLE: begin
                    if (ready_to_burst) begin
                        axi_busy          <= 1'b1;
                        m_axi_awaddr      <= next_awaddr;
                        m_axi_awlen       <= cand_beats[7:0] - 8'd1;
                        m_axi_awvalid     <= 1'b1;
                        beats_rem         <= cand_beats[7:0] - 8'd1;
                        burst_beats       <= cand_beats;
                        burst_was_flushed <= idle_flush_trigger && !above_threshold;
                        state             <= ST_ADDR;
                    end else begin
                        axi_busy <= 1'b0;
                    end
                end

                ST_ADDR: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        state         <= ST_DATA;
                    end
                end

                ST_DATA: begin
                    if (w_beat_accepted) begin
                        if (beats_rem == 8'd0) begin
                            state <= ST_RESP;
                        end else begin
                            beats_rem <= beats_rem - 8'd1;
                        end
                    end
                end

                ST_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        if (m_axi_bresp != 2'b00) begin
                            axi_err <= 1'b1;
                        end

                        total_bytes_written <= total_bytes_written + burst_bytes;

                        // Advance offset with circular wrap when buffer_size != 0
                        if ((aligned_size != 32'd0) && (next_wr_off >= aligned_size)) begin
                            wr_offset <= 32'd0;
                        end else begin
                            wr_offset <= next_wr_off;
                        end

                        // Update interrupt byte accumulator
                        if (irq_fire) begin
                            if (next_irq_acc >= eff_irq_bytes) begin
                                irq_byte_accum <= next_irq_acc - eff_irq_bytes;
                            end else begin
                                irq_byte_accum <= 32'd0;
                            end
                        end else begin
                            irq_byte_accum <= next_irq_acc;
                        end

                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule