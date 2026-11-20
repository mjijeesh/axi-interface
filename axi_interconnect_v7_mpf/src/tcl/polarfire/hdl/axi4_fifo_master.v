module axi4_fifo_master #(
    parameter ID_WIDTH   = 1,   // Matches COREAXI4INTERCONNECT_C0 ID_WIDTH=1
    parameter ADDR_WIDTH = 32,  // Matches COREAXI4INTERCONNECT_C0 ADDR_WIDTH=32
    parameter CNT_WIDTH  = 12   // Matches COREFIFO_C0 RDEPTH=2048 -> RDCNT[11:0]
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Control & Status Interface (matches top.tcl ports)
    input  wire [ADDR_WIDTH-1:0]  base_address,
    input  wire [15:0]            word_count,
    input  wire                   start_write,
    output reg                    axi_busy,
    output reg                    axi_done,

    // COREFIFO_C0 64-bit Read Interface (Standard Read Mode, PIPE=1, READ_DVALID=false)
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

    wire [CNT_WIDTH:0] total_avail_words = {1'b0, fifo_rdcnt}
                                         + {{CNT_WIDTH{1'b0}}, skid_valid}
                                         + {{CNT_WIDTH{1'b0}}, re_d1};

    // -------------------------------------------------------------------------
    // 2. Start Edge Detection & AXI4 Write Burst FSM
    // -------------------------------------------------------------------------
    localparam [1:0] ST_IDLE = 2'd0,
                     ST_ADDR = 2'd1,
                     ST_DATA = 2'd2,
                     ST_RESP = 2'd3;

    reg [1:0]            state;
    reg                  start_d1;
    reg [ADDR_WIDTH-1:0] cur_addr;
    reg [15:0]           words_rem;
    reg [7:0]            beats_rem;
    reg [8:0]            burst_beats;

    wire start_pulse = start_write && !start_d1;

    // Maximum 8-byte beats before crossing an AXI4 4KB (0x1000) boundary
    wire [8:0] max_4k_beats = 9'd256 - {1'b0, cur_addr[11:3]};

    reg [8:0] cand_beats;
    always @(*) begin
        cand_beats = {4'd0, MAX_BURST_BEATS};
        if (total_avail_words < {{(CNT_WIDTH-8){1'b0}}, cand_beats}) begin
            cand_beats = total_avail_words[8:0];
        end
        if ({7'd0, cand_beats} > words_rem) begin
            cand_beats = words_rem[8:0];
        end
        if (cand_beats > max_4k_beats) begin
            cand_beats = max_4k_beats;
        end
    end

    wire ready_to_burst = axi_busy && (words_rem != 16'd0) && (cand_beats != 9'd0) &&
                          ((cand_beats >= {4'd0, MAX_BURST_BEATS}) ||
                           ({7'd0, cand_beats} == words_rem) ||
                           (cand_beats == max_4k_beats));

    assign m_axi_wdata  = skid_data;
    assign m_axi_wvalid = (state == ST_DATA) && skid_valid;
    assign m_axi_wlast  = (state == ST_DATA) && (beats_rem == 8'd0);
    assign m_axi_bready = (state == ST_RESP);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            start_d1      <= 1'b0;
            axi_busy      <= 1'b0;
            axi_done      <= 1'b0;
            cur_addr      <= {ADDR_WIDTH{1'b0}};
            words_rem     <= 16'd0;
            beats_rem     <= 8'd0;
            burst_beats   <= 9'd0;
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen   <= 8'd0;
            m_axi_awvalid <= 1'b0;
        end else begin
            start_d1 <= start_write;

            if (!axi_busy) begin
                if (start_pulse && (word_count != 16'd0)) begin
                    axi_busy  <= 1'b1;
                    axi_done  <= 1'b0;
                    cur_addr  <= {base_address[ADDR_WIDTH-1:3], 3'b000};
                    words_rem <= word_count;
                end
            end else begin
                case (state)
                    ST_IDLE: begin
                        if (words_rem == 16'd0) begin
                            axi_busy <= 1'b0;
                            axi_done <= 1'b1;
                        end else if (ready_to_burst) begin
                            m_axi_awaddr  <= cur_addr;
                            m_axi_awlen   <= cand_beats[7:0] - 8'd1;
                            m_axi_awvalid <= 1'b1;
                            beats_rem     <= cand_beats[7:0] - 8'd1;
                            burst_beats   <= cand_beats;
                            state         <= ST_ADDR;
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
                            cur_addr  <= cur_addr + {20'd0, burst_beats, 3'b000};
                            words_rem <= words_rem - {7'd0, burst_beats};
                            state     <= ST_IDLE;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule