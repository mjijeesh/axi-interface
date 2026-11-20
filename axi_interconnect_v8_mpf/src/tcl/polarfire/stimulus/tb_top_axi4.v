//------------------------------------------------------------------------------
// Module: tb_top_axi4
// Description:
//   Self-Checking Testbench for Continuous RTL Data Generator -> Async CoreFIFO
//   -> Autonomous Threshold-Triggered AXI4 Master -> MSS Interrupt Generation.
//------------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module tb_top_axi4;
    localparam integer MAX_WORDS   = 16384;
    localparam [31:0]  SLAVE0_BASE = 32'h6000_0000;
    localparam [31:0]  SLAVE1_BASE = 32'h8000_0000;

    // Clocks & Resets
    reg         clk_50mhz          = 1'b0; // Oscillator -> PF_CCC -> 100 MHz
    reg         fifo_wclk          = 1'b0; // 75 MHz async producer clock
    reg         NSYSRESET          = 1'b0;
    wire        clk_100mhz;

    // Data Generator Controls
    reg         gen_en             = 1'b0;
    reg         gen_reset          = 1'b0;
    reg         gen_random_delay   = 1'b0;
    reg  [15:0] gen_pattern_tag    = 16'hA501;
    reg  [15:0] gen_burst_len      = 16'd32;
    reg  [15:0] gen_delay_cycles   = 16'd0;
    wire [31:0] gen_words_generated;

    // Autonomous AXI4 Master & Interrupt Controls
    reg         stream_en          = 1'b0;
    reg         soft_rst           = 1'b0;
    reg         irq_en             = 1'b0;
    reg         irq_ack            = 1'b0;
    reg  [31:0] base_address       = SLAVE0_BASE;
    reg  [31:0] buffer_size        = 32'd0;
    reg  [11:0] burst_threshold    = 12'd16;
    reg  [15:0] idle_flush_cycles  = 16'd64;
    reg  [31:0] irq_chunk_bytes    = 32'd512;

    // Status & Interrupt Outputs
    wire        axi_busy;
    wire        axi_err;
    wire        mss_irq;
    wire        mss_irq_pulse;
    wire        fifo_full;
    wire        fifo_afull;
    wire [31:0] wr_offset;
    wire [31:0] total_bytes_written;
    wire [15:0] irq_pending_cnt;
    wire [31:0] last_irq_offset;

    // Scoreboard State
    reg  [31:0] active_base        = SLAVE0_BASE;
    reg  [63:0] captured_mem_u64 [0:MAX_WORDS-1];
    integer     s0_burst_cnt       = 0;
    integer     s1_burst_cnt       = 0;
    integer     irq_ack_count      = 0;
    integer     proto_errors       = 0;

    // -------------------------------------------------------------------------
    // Clocks & Reset
    // -------------------------------------------------------------------------
    always #10.00 clk_50mhz = ~clk_50mhz; // 50 MHz -> 100 MHz PF_CCC
    always #6.666 fifo_wclk = ~fifo_wclk; // 75 MHz async producer

    initial begin
        #100;
        NSYSRESET = 1'b1;
    end

    // -------------------------------------------------------------------------
    // Unit Under Test
    // -------------------------------------------------------------------------
    top uut (
        .REF_CLK             (clk_50mhz),
        .reset_n             (NSYSRESET),
        .fifo_wclk           (fifo_wclk),
        .gen_en              (gen_en),
        .gen_reset           (gen_reset),
        .gen_random_delay    (gen_random_delay),
        .stream_en           (stream_en),
        .soft_rst            (soft_rst),
        .irq_en              (irq_en),
        .irq_ack             (irq_ack),
        .CLK_100             (clk_100mhz),
        .axi_busy            (axi_busy),
        .axi_err             (axi_err),
        .mss_irq             (mss_irq),
        .mss_irq_pulse       (mss_irq_pulse),
        .fifo_full           (fifo_full),
        .fifo_afull          (fifo_afull),
        .gen_pattern_tag     (gen_pattern_tag),
        .gen_burst_len       (gen_burst_len),
        .gen_delay_cycles    (gen_delay_cycles),
        .base_address        (base_address),
        .buffer_size         (buffer_size),
        .burst_threshold     (burst_threshold),
        .idle_flush_cycles   (idle_flush_cycles),
        .irq_chunk_bytes     (irq_chunk_bytes),
        .gen_words_generated (gen_words_generated),
        .wr_offset           (wr_offset),
        .total_bytes_written (total_bytes_written),
        .irq_pending_cnt     (irq_pending_cnt),
        .last_irq_offset     (last_irq_offset)
    );

    // -------------------------------------------------------------------------
    // AXI4 Master M0 Protocol Checker & Scoreboard
    // -------------------------------------------------------------------------
    reg [31:0] m0_awaddr_q = 32'h0;
    reg [7:0]  m0_awlen_q  = 8'h0;
    reg [7:0]  m0_beat_q   = 8'h0;

    wire        m0_aw_hs   = uut.axi4_fifo_master_0.m_axi_awvalid && uut.axi4_fifo_master_0.m_axi_awready;
    wire        m0_w_hs    = uut.axi4_fifo_master_0.m_axi_wvalid  && uut.axi4_fifo_master_0.m_axi_wready;
    wire        m0_b_hs    = uut.axi4_fifo_master_0.m_axi_bvalid  && uut.axi4_fifo_master_0.m_axi_bready;

    wire [31:0] m0_eff_addr = m0_aw_hs ? uut.axi4_fifo_master_0.m_axi_awaddr : m0_awaddr_q;
    wire [7:0]  m0_eff_len  = m0_aw_hs ? uut.axi4_fifo_master_0.m_axi_awlen  : m0_awlen_q;
    wire [7:0]  m0_eff_beat = m0_aw_hs ? 8'd0 : m0_beat_q;

    always @(posedge clk_100mhz) begin
        if (!NSYSRESET || soft_rst) begin
            m0_awaddr_q <= 32'h0;
            m0_awlen_q  <= 8'h0;
            m0_beat_q   <= 8'h0;
        end else begin
            if (m0_aw_hs) begin
                if (({1'b0, uut.axi4_fifo_master_0.m_axi_awaddr[11:0]} +
                    (({5'd0, uut.axi4_fifo_master_0.m_axi_awlen} + 13'd1) << uut.axi4_fifo_master_0.m_axi_awsize)) > 13'h1000) begin
                    $display("[AXI-ERR] Burst crossed 4KB boundary! AWADDR=0x%08X AWLEN=%0d AWSIZE=%0d",
                             uut.axi4_fifo_master_0.m_axi_awaddr,
                             uut.axi4_fifo_master_0.m_axi_awlen,
                             uut.axi4_fifo_master_0.m_axi_awsize);
                    proto_errors = proto_errors + 1;
                end
                if (!m0_w_hs) begin
                    m0_awaddr_q <= uut.axi4_fifo_master_0.m_axi_awaddr;
                    m0_awlen_q  <= uut.axi4_fifo_master_0.m_axi_awlen;
                    m0_beat_q   <= 8'd0;
                end
            end

            if (m0_w_hs) begin
                if (m0_eff_addr >= active_base && ((m0_eff_addr - active_base) >> 3) < MAX_WORDS) begin
                    captured_mem_u64[(m0_eff_addr - active_base) >> 3] = uut.axi4_fifo_master_0.m_axi_wdata;
                end
                if (uut.axi4_fifo_master_0.m_axi_wlast !== (m0_eff_beat == m0_eff_len)) begin
                    $display("[AXI-ERR] WLAST mismatch at beat %0d / %0d", m0_eff_beat, m0_eff_len);
                    proto_errors = proto_errors + 1;
                end
                m0_awaddr_q <= m0_eff_addr + 32'd8;
                m0_awlen_q  <= m0_eff_len;
                m0_beat_q   <= m0_eff_beat + 8'd1;
            end

            if (m0_b_hs) begin
                if (uut.axi4_fifo_master_0.m_axi_bresp !== 2'b00) begin
                    $display("[AXI-ERR] Non-OKAY BRESP=0x%0h at 0x%08X",
                             uut.axi4_fifo_master_0.m_axi_bresp, m0_awaddr_q);
                    proto_errors = proto_errors + 1;
                end
                if (m0_awaddr_q <= SLAVE1_BASE) begin
                    s0_burst_cnt <= s0_burst_cnt + 1;
                end else begin
                    s1_burst_cnt <= s1_burst_cnt + 1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Emulated MSS PLIC Interrupt Service Routine
    // -------------------------------------------------------------------------
    always @(posedge clk_100mhz) begin
        if (!NSYSRESET || soft_rst) begin
            irq_ack <= 1'b0;
        end else if (mss_irq && !irq_ack) begin
            repeat (8) @(posedge clk_100mhz); #1;
            irq_ack       = 1'b1;
            irq_ack_count = irq_ack_count + 1;
            @(posedge clk_100mhz); #1;
            irq_ack       = 1'b0;
        end
    end

    task reset_streaming_engine;
        begin
            gen_en    = 1'b0;
            stream_en = 1'b0;
            wait(!axi_busy);
            @(posedge fifo_wclk); #1; gen_reset = 1'b1;
            @(posedge clk_100mhz); #1; soft_rst  = 1'b1;
            repeat (6) @(posedge clk_100mhz);
            @(posedge fifo_wclk); #1; gen_reset = 1'b0;
            @(posedge clk_100mhz); #1; soft_rst  = 1'b0;
            repeat (4) @(posedge clk_100mhz);
        end
    endtask

    integer i, err_cnt, watchdog;
    reg [15:0] idx_lo, idx_hi;
    reg [63:0] exp_u64, got_u64;

    initial begin
        $display("\n=====================================================================");
        $display("   AUTONOMOUS FIFO-TO-AXI4 STREAMING + MSS INTERRUPT REGRESSION      ");
        $display("=====================================================================");

        wait(NSYSRESET === 1'b1);
        #10000;
        repeat (10) @(posedge clk_100mhz);
        $display("[STATUS] PLL Locked & Reset Released (wclk=75 MHz, aclk=100 MHz).\n");

        // =====================================================================
        // PHASE 1: Continuous Bursty Data Generator -> Slave 0 + MSS IRQ every 512 B
        // =====================================================================
        $display("---------------------------------------------------------------------");
        $display(" PHASE 1: CONTINUOUS BURSTY STREAM + MSS IRQ -> SLAVE 0 (0x6000_0000) ");
        $display("---------------------------------------------------------------------");
        reset_streaming_engine();
        active_base       = SLAVE0_BASE;
        base_address      = SLAVE0_BASE;
        buffer_size       = 32'd0;
        burst_threshold   = 12'd16;
        idle_flush_cycles = 16'd64;
        irq_chunk_bytes   = 32'd512;
        irq_en            = 1'b1;
        gen_pattern_tag   = 16'h1101;
        gen_burst_len     = 16'd32;
        gen_delay_cycles  = 16'd12;
        gen_random_delay  = 1'b1;
        s0_burst_cnt      = 0;
        irq_ack_count     = 0;

        @(posedge clk_100mhz); #1; stream_en = 1'b1;
        @(posedge fifo_wclk); #1; gen_en    = 1'b1;

        watchdog = 0;
        while ((total_bytes_written < 32'd2048) && (watchdog < 20000)) begin
            @(posedge clk_100mhz);
            watchdog = watchdog + 1;
        end
        @(posedge fifo_wclk); #1;
        gen_en = 1'b0;

        // Wait for any partial tail words in FIFO to flush completely
        repeat (200) @(posedge clk_100mhz);
        wait(!axi_busy);

        $display("[PHASE 1] Written=%0d B | Gen_u32=%0d | AXI_Bursts=%0d | MSS_IRQs_Acked=%0d",
                 total_bytes_written, gen_words_generated, s0_burst_cnt, irq_ack_count);

        err_cnt = 0;
        for (i = 0; i < (total_bytes_written / 8); i = i + 1) begin
            idx_lo  = i[14:0] * 16'd2;
            idx_hi  = idx_lo + 16'd1;
            exp_u64 = {gen_pattern_tag, idx_hi, gen_pattern_tag, idx_lo};
            got_u64 = captured_mem_u64[i];
            if (got_u64 !== exp_u64) begin
                if (err_cnt < 8)
                    $display("  [ERROR] u64[%0d]: Expected 0x%016X, Got 0x%016X", i, exp_u64, got_u64);
                err_cnt = err_cnt + 1;
            end
        end
        if (err_cnt != 0 || proto_errors != 0 || (irq_ack_count < 4) || axi_err) begin
            $display("[FAIL] Phase 1 failed! err=%0d proto=%0d irqs=%0d", err_cnt, proto_errors, irq_ack_count);
            $finish;
        end
        $display("  [PASS] All %0d 64-bit words verified and %0d MSS interrupts serviced!\n",
                 total_bytes_written / 8, irq_ack_count);

        // =====================================================================
        // PHASE 2: Intermittent Long Delay (300 cycles) -> Idle-Flush + MSS IRQ
        // =====================================================================
        $display("---------------------------------------------------------------------");
        $display(" PHASE 2: INTERMITTENT LONG DELAY -> IDLE-FLUSH & MSS INTERRUPT      ");
        $display("---------------------------------------------------------------------");
        reset_streaming_engine();
        active_base       = 32'h6000_2000;
        base_address      = 32'h6000_2000;
        buffer_size       = 32'd0;
        burst_threshold   = 12'd16;
        idle_flush_cycles = 16'd48;
        irq_chunk_bytes   = 32'd512;
        irq_en            = 1'b1;
        gen_pattern_tag   = 16'h2202;
        gen_burst_len     = 16'd10;
        gen_delay_cycles  = 16'd300;
        gen_random_delay  = 1'b0;
        irq_ack_count     = 0;

        @(posedge clk_100mhz); #1; stream_en = 1'b1;
        @(posedge fifo_wclk); #1; gen_en    = 1'b1;

        watchdog = 0;
        while ((irq_ack_count < 3) && (watchdog < 10000)) begin
            @(posedge clk_100mhz);
            watchdog = watchdog + 1;
        end
        @(posedge fifo_wclk); #1;
        gen_en = 1'b0;
        repeat (150) @(posedge clk_100mhz);
        wait(!axi_busy);

        $display("[PHASE 2] Flushed Partial Packets: Written=%0d B | MSS_IRQs_Acked=%0d",
                 total_bytes_written, irq_ack_count);
        if ((total_bytes_written < 32'd120) || (irq_ack_count < 3)) begin
            $display("[FAIL] Phase 2 idle-flush failed!");
            $finish;
        end
        $display("  [PASS] Idle-flush timer drained partial bursts & fired MSS IRQ!\n");

        // =====================================================================
        // PHASE 3: Circular Ring Wrap (1024 B) -> Slave 1 (32-bit DWC) + MSS IRQ
        // =====================================================================
        $display("---------------------------------------------------------------------");
        $display(" PHASE 3: CIRCULAR RING WRAP & BACKPRESSURE -> SLAVE 1 (0x8000_0000) ");
        $display("---------------------------------------------------------------------");
        reset_streaming_engine();
        active_base       = SLAVE1_BASE;
        base_address      = SLAVE1_BASE;
        buffer_size       = 32'd1024;
        burst_threshold   = 12'd16;
        idle_flush_cycles = 16'd64;
        irq_chunk_bytes   = 32'd256;
        irq_en            = 1'b1;
        gen_pattern_tag   = 16'h3303;
        gen_burst_len     = 16'd0;
        gen_delay_cycles  = 16'd0;
        irq_ack_count     = 0;

        @(posedge clk_100mhz); #1; stream_en = 1'b1;
        @(posedge fifo_wclk); #1; gen_en    = 1'b1;

        watchdog = 0;
        while ((total_bytes_written < 32'd4096) && (watchdog < 30000)) begin
            @(posedge clk_100mhz);
            watchdog = watchdog + 1;
        end
        @(posedge fifo_wclk); #1;
        gen_en = 1'b0;
        repeat (200) @(posedge clk_100mhz);
        wait(!axi_busy);

        $display("[PHASE 3] Ring Stream: Written=%0d B | wr_offset=%0d | MSS_IRQs_Acked=%0d",
                 total_bytes_written, wr_offset, irq_ack_count);
        if ((wr_offset >= 32'd1024) || (irq_ack_count < 16) || axi_err || (proto_errors != 0)) begin
            $display("[FAIL] Phase 3 ring wrap failed!");
            $finish;
        end
        $display("  [PASS] Circular buffer wrapped cleanly modulo 1024 B with %0d MSS interrupts!\n",
                 irq_ack_count);

        $display("=====================================================================");
        $display("   ALL AUTONOMOUS FIFO-TO-AXI4 + MSS INTERRUPT TESTS PASSED!         ");
        $display("=====================================================================\n");
        $finish;
    end

endmodule
`resetall