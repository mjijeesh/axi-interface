//------------------------------------------------------------------------------
// Module: tb_top_axi4
// Company/Institution:  Tecnomic Components
// Engineer:             Jijeesh M
//
// Description:
//   Self-Checking Asynchronous FIFO-to-AXI4 DMA Regression Testbench.
//   Verifies:
//     1. Asynchronous 32-bit write (75 MHz) -> 64-bit read (100 MHz) COREFIFO_C0
//        little-endian word packing ({Write_1, Write_0}) and CDC synchronization.
//     2. Standard-mode CoreFIFO (PIPE=1) 1-word skid buffer inside axi4_fifo_master.
//     3. Multi-burst AXI4 INCR transactions across COREAXI4INTERCONNECT_C0 into:
//          - Slave 0: PF_SRAM_AHBL_AXI_C0 (64-bit native SRAM @ 0x6000_0000)
//          - Slave 1: PF_SRAM_AHBL_AXI_C1 (32-bit DWC SRAM    @ 0x8000_0000)
//     4. AXI4 4 KB (0x1000) boundary burst splitting, FIFO backpressure (FULL),
//        and intermittent producer idle gaps (EMPTY stall/resume).
//------------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module tb_top;
    localparam integer MAX_TEST_WORDS = 16384; // Supports sweeps up to 16K x 64-bit (128 KB)
    localparam [31:0]  SLAVE0_BASE    = 32'h6000_0000;
    localparam [31:0]  SLAVE1_BASE    = 32'h8000_0000;

    // Clocks & Resets
    reg         clk_50mhz    = 1'b0; // Oscillator input -> PF_CCC_C0 -> 100 MHz fabric clock
    reg         fifo_wclk    = 1'b0; // Asynchronous 75 MHz FPGA producer clock
    reg         NSYSRESET    = 1'b0;
    wire        clk_100mhz;

    // Top-Level FIFO Write Interface (32-bit Producer Domain)
    reg         fifo_we      = 1'b0;
    reg  [31:0] fifo_wdata   = 32'h0;
    wire        fifo_full;
    wire        fifo_afull;

    // Top-Level DMA Control & Status Interface (100 MHz AXI Domain)
    reg  [31:0] base_address = 32'h0;
    reg  [15:0] word_count   = 16'h0;
    reg         start_write  = 1'b0;
    wire        axi_busy;
    wire        axi_done;

    // Scoreboard & Protocol Checker State
    reg  [31:0] active_sweep_base = 32'h0;
    reg  [63:0] s0_captured_u64 [0:MAX_TEST_WORDS-1];
    reg  [31:0] s1_captured_u32 [0:(MAX_TEST_WORDS*2)-1];
    integer     s0_burst_cnt      = 0;
    integer     s1_burst_cnt      = 0;
    integer     s0_beat_cnt       = 0;
    integer     s1_beat_cnt       = 0;
    integer     proto_errors      = 0;
    integer     full_stall_events = 0;

    // -------------------------------------------------------------------------
    // Clock & Reset Generators
    // -------------------------------------------------------------------------
    // 50 MHz Reference Oscillator (20.00 ns period -> 100 MHz PF_CCC output)
    always #10.00 clk_50mhz = ~clk_50mhz;

    // 75 MHz Asynchronous Producer Clock (13.332 ns period)
    always #6.666 fifo_wclk = ~fifo_wclk;

    initial begin
        #100;
        NSYSRESET = 1'b1;
    end

    // -------------------------------------------------------------------------
    // Unit Under Test (SmartDesign "top")
    // -------------------------------------------------------------------------
    top uut (
        .REF_CLK      (clk_50mhz),
        .reset_n      (NSYSRESET),
        .start_write  (start_write),
        .fifo_wclk    (fifo_wclk),
        .fifo_we      (fifo_we),
        .base_address (base_address),
        .word_count   (word_count),
        .fifo_wdata   (fifo_wdata),
        .CLK_100      (clk_100mhz),
        .axi_busy     (axi_busy),
        .axi_done     (axi_done),
        .fifo_full    (fifo_full),
        .fifo_afull   (fifo_afull)
    );

    // -------------------------------------------------------------------------
    // AXI4 Slave 0 Monitor (PF_SRAM_AHBL_AXI_C0_0 @ 0x6000_0000, 64-bit Native)
    // -------------------------------------------------------------------------
    reg [31:0] s0_awaddr_q = 32'h0;
    reg [7:0]  s0_awlen_q  = 8'h0;
    reg [7:0]  s0_beat_q   = 8'h0;

    wire        s0_aw_hs   = uut.PF_SRAM_AHBL_AXI_C0_0.AWVALID && uut.PF_SRAM_AHBL_AXI_C0_0.AWREADY;
    wire        s0_w_hs    = uut.PF_SRAM_AHBL_AXI_C0_0.WVALID  && uut.PF_SRAM_AHBL_AXI_C0_0.WREADY;
    wire        s0_b_hs    = uut.PF_SRAM_AHBL_AXI_C0_0.BVALID  && uut.PF_SRAM_AHBL_AXI_C0_0.BREADY;

    wire [31:0] s0_eff_addr = s0_aw_hs ? uut.PF_SRAM_AHBL_AXI_C0_0.AWADDR : s0_awaddr_q;
    wire [7:0]  s0_eff_len  = s0_aw_hs ? uut.PF_SRAM_AHBL_AXI_C0_0.AWLEN  : s0_awlen_q;
    wire [7:0]  s0_eff_beat = s0_aw_hs ? 8'd0 : s0_beat_q;

    always @(posedge clk_100mhz) begin
        if (!NSYSRESET) begin
            s0_awaddr_q <= 32'h0;
            s0_awlen_q  <= 8'h0;
            s0_beat_q   <= 8'h0;
        end else begin
            if (s0_aw_hs) begin
                // Verify AXI4 4KB boundary compliance on every burst
                if (({1'b0, uut.PF_SRAM_AHBL_AXI_C0_0.AWADDR[11:0]} +
                    (({5'd0, uut.PF_SRAM_AHBL_AXI_C0_0.AWLEN} + 13'd1) << uut.PF_SRAM_AHBL_AXI_C0_0.AWSIZE)) > 13'h1000) begin
                    $display("[AXI-ERR] Slave 0 burst crossed 4KB boundary! AWADDR=0x%08X AWLEN=%0d AWSIZE=%0d",
                             uut.PF_SRAM_AHBL_AXI_C0_0.AWADDR,
                             uut.PF_SRAM_AHBL_AXI_C0_0.AWLEN,
                             uut.PF_SRAM_AHBL_AXI_C0_0.AWSIZE);
                    proto_errors = proto_errors + 1;
                end
                if (!s0_w_hs) begin
                    s0_awaddr_q <= uut.PF_SRAM_AHBL_AXI_C0_0.AWADDR;
                    s0_awlen_q  <= uut.PF_SRAM_AHBL_AXI_C0_0.AWLEN;
                    s0_beat_q   <= 8'd0;
                end
            end

            if (s0_w_hs) begin
                if (s0_eff_addr >= active_sweep_base &&
                    ((s0_eff_addr - active_sweep_base) >> 3) < MAX_TEST_WORDS) begin
                    s0_captured_u64[(s0_eff_addr - active_sweep_base) >> 3] = uut.PF_SRAM_AHBL_AXI_C0_0.WDATA;
                end
                if (uut.PF_SRAM_AHBL_AXI_C0_0.WLAST !== (s0_eff_beat == s0_eff_len)) begin
                    $display("[AXI-ERR] Slave 0 WLAST mismatch at beat %0d / %0d", s0_eff_beat, s0_eff_len);
                    proto_errors = proto_errors + 1;
                end
                s0_awaddr_q <= s0_eff_addr + 32'd8;
                s0_awlen_q  <= s0_eff_len;
                s0_beat_q   <= s0_eff_beat + 8'd1;
                s0_beat_cnt <= s0_beat_cnt + 1;
            end

            if (s0_b_hs) begin
                if (uut.PF_SRAM_AHBL_AXI_C0_0.BRESP !== 2'b00) begin
                    $display("[AXI-ERR] Slave 0 non-OKAY BRESP=0x%0h", uut.PF_SRAM_AHBL_AXI_C0_0.BRESP);
                    proto_errors = proto_errors + 1;
                end
                s0_burst_cnt <= s0_burst_cnt + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // AXI4 Slave 1 Monitor (PF_SRAM_AHBL_AXI_C1_0 @ 0x8000_0000, 32-bit DWC)
    // -------------------------------------------------------------------------
    reg [31:0] s1_awaddr_q = 32'h0;
    reg [7:0]  s1_awlen_q  = 8'h0;
    reg [7:0]  s1_beat_q   = 8'h0;

    wire        s1_aw_hs   = uut.PF_SRAM_AHBL_AXI_C1_0.AWVALID && uut.PF_SRAM_AHBL_AXI_C1_0.AWREADY;
    wire        s1_w_hs    = uut.PF_SRAM_AHBL_AXI_C1_0.WVALID  && uut.PF_SRAM_AHBL_AXI_C1_0.WREADY;
    wire        s1_b_hs    = uut.PF_SRAM_AHBL_AXI_C1_0.BVALID  && uut.PF_SRAM_AHBL_AXI_C1_0.BREADY;

    wire [31:0] s1_eff_addr = s1_aw_hs ? uut.PF_SRAM_AHBL_AXI_C1_0.AWADDR : s1_awaddr_q;
    wire [7:0]  s1_eff_len  = s1_aw_hs ? uut.PF_SRAM_AHBL_AXI_C1_0.AWLEN  : s1_awlen_q;
    wire [7:0]  s1_eff_beat = s1_aw_hs ? 8'd0 : s1_beat_q;

    always @(posedge clk_100mhz) begin
        if (!NSYSRESET) begin
            s1_awaddr_q <= 32'h0;
            s1_awlen_q  <= 8'h0;
            s1_beat_q   <= 8'h0;
        end else begin
            if (s1_aw_hs) begin
                if (({1'b0, uut.PF_SRAM_AHBL_AXI_C1_0.AWADDR[11:0]} +
                    (({5'd0, uut.PF_SRAM_AHBL_AXI_C1_0.AWLEN} + 13'd1) << uut.PF_SRAM_AHBL_AXI_C1_0.AWSIZE)) > 13'h1000) begin
                    $display("[AXI-ERR] Slave 1 burst crossed 4KB boundary! AWADDR=0x%08X AWLEN=%0d AWSIZE=%0d",
                             uut.PF_SRAM_AHBL_AXI_C1_0.AWADDR,
                             uut.PF_SRAM_AHBL_AXI_C1_0.AWLEN,
                             uut.PF_SRAM_AHBL_AXI_C1_0.AWSIZE);
                    proto_errors = proto_errors + 1;
                end
                if (!s1_w_hs) begin
                    s1_awaddr_q <= uut.PF_SRAM_AHBL_AXI_C1_0.AWADDR;
                    s1_awlen_q  <= uut.PF_SRAM_AHBL_AXI_C1_0.AWLEN;
                    s1_beat_q   <= 8'd0;
                end
            end

            if (s1_w_hs) begin
                if (s1_eff_addr >= active_sweep_base &&
                    ((s1_eff_addr - active_sweep_base) >> 2) < (MAX_TEST_WORDS * 2)) begin
                    s1_captured_u32[(s1_eff_addr - active_sweep_base) >> 2] = uut.PF_SRAM_AHBL_AXI_C1_0.WDATA[31:0];
                end
                if (uut.PF_SRAM_AHBL_AXI_C1_0.WLAST !== (s1_eff_beat == s1_eff_len)) begin
                    $display("[AXI-ERR] Slave 1 WLAST mismatch at beat %0d / %0d", s1_eff_beat, s1_eff_len);
                    proto_errors = proto_errors + 1;
                end
                s1_awaddr_q <= s1_eff_addr + 32'd4;
                s1_awlen_q  <= s1_eff_len;
                s1_beat_q   <= s1_eff_beat + 8'd1;
                s1_beat_cnt <= s1_beat_cnt + 1;
            end

            if (s1_b_hs) begin
                if (uut.PF_SRAM_AHBL_AXI_C1_0.BRESP !== 2'b00) begin
                    $display("[AXI-ERR] Slave 1 non-OKAY BRESP=0x%0h", uut.PF_SRAM_AHBL_AXI_C1_0.BRESP);
                    proto_errors = proto_errors + 1;
                end
                s1_burst_cnt <= s1_burst_cnt + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 32-Bit FIFO Producer Tasks (wclk Domain)
    // -------------------------------------------------------------------------
    task push_single_u32;
        input [31:0]  data_word;
        input integer gap_cycles;
        integer g;
        begin
            @(posedge fifo_wclk);
            while (fifo_full) begin
                fifo_we <= 1'b0;
                full_stall_events = full_stall_events + 1;
                @(posedge fifo_wclk);
            end
            #1;
            fifo_wdata = data_word;
            fifo_we    = 1'b1;
            @(posedge fifo_wclk); #1;
            fifo_we    = 1'b0;
            for (g = 0; g < gap_cycles; g = g + 1) begin
                @(posedge fifo_wclk);
            end
        end
    endtask

    // Pushes (2 * num_u64_words) 32-bit words into COREFIFO_C0:
    //   Even 32-bit write -> Q[31:0]  = word_index
    //   Odd  32-bit write -> Q[63:32] = pattern_header
    task push_fifo_u64_stream;
        input [15:0]  num_u64_words;
        input [31:0]  pattern_header;
        input integer gap_cycles;
        integer idx;
        begin
            for (idx = 0; idx < num_u64_words; idx = idx + 1) begin
                push_single_u32(idx[31:0],      gap_cycles);
                push_single_u32(pattern_header, gap_cycles);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // AXI4 FIFO Master Trigger & Completion Wait Task (100 MHz Domain)
    // -------------------------------------------------------------------------
    task trigger_and_wait_axi_dma;
        input [31:0]  addr;
        input [15:0]  count;
        input integer gap_cycles;
        integer timeout_cnt;
        integer max_cycles;
        begin
            wait(!axi_busy);
            @(posedge clk_100mhz); #1;
            base_address = addr;
            word_count   = count;
            start_write  = 1'b1;
            @(posedge clk_100mhz); #1;
            start_write  = 1'b0;

            max_cycles  = (count * (16 + (gap_cycles * 4))) + 10000;
            timeout_cnt = 0;
            while (!axi_done && timeout_cnt < max_cycles) begin
                @(posedge clk_100mhz);
                timeout_cnt = timeout_cnt + 1;
            end
            if (!axi_done) begin
                $display("[TIMEOUT] axi4_fifo_master stalled at 0x%08X (Words: %0d, Cycles: %0d)",
                         addr, count, timeout_cnt);
                $finish;
            end
            repeat (4) @(posedge clk_100mhz);
        end
    endtask

    // -------------------------------------------------------------------------
    // End-to-End Concurrent FIFO -> AXI4 Sweep & Verification Task
    // -------------------------------------------------------------------------
    task run_fifo_dma_sweep;
        input [31:0]  target_axi_addr;
        input [15:0]  total_u64_words;
        input [31:0]  pattern_header;
        input integer producer_gap_cycles;
        input         arm_dma_first;
        integer i;
        integer error_count;
        reg [63:0] actual_word;
        reg [63:0] expected_word;
        begin
            error_count       = 0;
            active_sweep_base = target_axi_addr;
            s0_burst_cnt      = 0;
            s1_burst_cnt      = 0;
            s0_beat_cnt       = 0;
            s1_beat_cnt       = 0;
            full_stall_events = 0;

            // Clear scoreboard shadow arrays
            for (i = 0; i < total_u64_words; i = i + 1) begin
                s0_captured_u64[i]        = 64'hDEAD_DEAD_DEAD_DEAD;
                s1_captured_u32[2*i]      = 32'hDEAD_DEAD;
                s1_captured_u32[2*i + 1]  = 32'hDEAD_DEAD;
            end

            $display("[FIFO-DMA SWEEP] Target: 0x%08X | u64_Words: %0d (%0d B) | Gap: %0d | ArmFirst: %0d",
                     target_axi_addr, total_u64_words, total_u64_words * 8,
                     producer_gap_cycles, arm_dma_first);

            if (arm_dma_first) begin
                // Start DMA before FIFO has data (exercises EMPTY stall & resume)
                fork
                    trigger_and_wait_axi_dma(target_axi_addr, total_u64_words, producer_gap_cycles);
                    begin
                        repeat (20) @(posedge fifo_wclk);
                        push_fifo_u64_stream(total_u64_words, pattern_header, producer_gap_cycles);
                    end
                join
            end else begin
                // Stream 32-bit producer concurrently with 64-bit AXI4 DMA drain
                fork
                    push_fifo_u64_stream(total_u64_words, pattern_header, producer_gap_cycles);
                    begin
                        repeat (6) @(posedge clk_100mhz);
                        trigger_and_wait_axi_dma(target_axi_addr, total_u64_words, producer_gap_cycles);
                    end
                join
            end

            // Verify every 64-bit word received at the target SRAM slave boundary
            for (i = 0; i < total_u64_words; i = i + 1) begin
                expected_word = {pattern_header, i[31:0]};
                if (target_axi_addr < SLAVE1_BASE) begin
                    actual_word = s0_captured_u64[i];
                end else begin
                    actual_word = {s1_captured_u32[2*i + 1], s1_captured_u32[2*i]};
                end

                if (actual_word === expected_word) begin
                    if (total_u64_words <= 16 || i < 2 || i >= (total_u64_words - 2)) begin
                        $display("  [MATCH] Word %05d | Addr: 0x%08X | Data: 0x%016X",
                                 i, target_axi_addr + (i * 8), actual_word);
                    end
                end else begin
                    if (error_count < 16) begin
                        $display("  [ERROR] Word %05d | Addr: 0x%08X | Expected: 0x%016X | Got: 0x%016X",
                                 i, target_axi_addr + (i * 8), expected_word, actual_word);
                    end
                    error_count = error_count + 1;
                end
            end

            if (error_count > 0 || proto_errors > 0) begin
                $display("\n[CRITICAL FAILURE] Data Errors=%0d, AXI Protocol Errors=%0d at 0x%08X!\n",
                         error_count, proto_errors, target_axi_addr);
                $finish;
            end else begin
                $display("  [PASS] %0d u64 words (%0d B) verified | Bursts: %0d | FULL stalls: %0d\n",
                         total_u64_words, total_u64_words * 8,
                         (target_axi_addr < SLAVE1_BASE) ? s0_burst_cnt : s1_burst_cnt,
                         full_stall_events);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Simulation Sequence
    // -------------------------------------------------------------------------
    initial begin
        $display("\n=================================================================");
        $display("   ASYNC COREFIFO (32b->64b) TO AXI4 MASTER REGRESSION SUITE     ");
        $display("=================================================================");

        $display("[STATUS] Waiting for PF_CCC PLL lock and synchronized reset release...");
        wait(uut.reset_synchronizer_1_reset_sync === 1'b1);
        repeat (10) @(posedge clk_100mhz);
        $display("[STATUS] System ready (wclk=75 MHz, aclk=100 MHz). Starting sweeps.\n");

        // ---------------------------------------------------------------------
        // PHASE 1: SLAVE 0 (64-bit PF_SRAM_AHBL_AXI_C0 @ 0x6000_0000)
        // ---------------------------------------------------------------------
        $display("-----------------------------------------------------------------");
        $display(" PHASE 1: SLAVE 0 (64-BIT AXI4 SRAM @ 0x6000_0000)               ");
        $display("-----------------------------------------------------------------");
        run_fifo_dma_sweep(32'h6000_1000, 16'd1,    32'hC001_A001, 0, 1'b0); // 8 B (single beat)
        run_fifo_dma_sweep(32'h6000_2400, 16'd4,    32'hBEEF_0004, 0, 1'b0); // 32 B (4 beats)
        run_fifo_dma_sweep(32'h6000_3000, 16'd13,   32'h7777_D111, 0, 1'b0); // 104 B (partial burst)
        run_fifo_dma_sweep(32'h6000_3800, 16'd16,   32'h1616_B016, 0, 1'b0); // 128 B (exact 16-beat burst)
        run_fifo_dma_sweep(32'h6000_4500, 16'd64,   32'hDEAD_0064, 0, 1'b0); // 512 B (4 bursts)
        run_fifo_dma_sweep(32'h6000_0FC0, 16'd32,   32'h4B4B_B0D0, 0, 1'b0); // 256 B crossing 0x6000_1000 4KB boundary
        run_fifo_dma_sweep(32'h6000_0000, 16'd512,  32'h4B00_0512, 0, 1'b0); // 4 KB (32 bursts)
        run_fifo_dma_sweep(32'h6000_0000, 16'd4096, 32'hF1F0_4096, 0, 1'b0); // 32 KB (2x FIFO capacity -> tests FULL stall)

        // ---------------------------------------------------------------------
        // PHASE 2: SLAVE 1 (32-bit Width-Converted PF_SRAM_AHBL_AXI_C1 @ 0x8000_0000)
        // ---------------------------------------------------------------------
        $display("-----------------------------------------------------------------");
        $display(" PHASE 2: SLAVE 1 (32-BIT DWC AXI4 SRAM @ 0x8000_0000)           ");
        $display("-----------------------------------------------------------------");
        run_fifo_dma_sweep(32'h8000_0000, 16'd1,    32'hC002_B002, 0, 1'b0); // 8 B -> two 32-bit beats
        run_fifo_dma_sweep(32'h8000_1000, 16'd8,    32'hA5A5_0008, 0, 1'b0); // 64 B
        run_fifo_dma_sweep(32'h8000_4200, 16'd32,   32'hB4B4_0032, 0, 1'b0); // 256 B
        run_fifo_dma_sweep(32'h8000_8000, 16'd127,  32'hECEC_0127, 0, 1'b0); // 1,016 B (odd word count)
        run_fifo_dma_sweep(32'h8000_0FE0, 16'd16,   32'h4B32_B0D0, 0, 1'b0); // 128 B crossing 0x8000_1000 4KB boundary
        run_fifo_dma_sweep(32'h8000_0000, 16'd3072, 32'hD0C3_3072, 0, 1'b0); // 24 KB (exceeds FIFO capacity + DWC)

        // ---------------------------------------------------------------------
        // PHASE 3: INTERMITTENT / THROTTLED PRODUCER (EMPTY STALL & RESUME)
        // ---------------------------------------------------------------------
        $display("-----------------------------------------------------------------");
        $display(" PHASE 3: THROTTLED PRODUCER & PRE-ARMED DMA (EMPTY HANDSHAKE)   ");
        $display("-----------------------------------------------------------------");
        run_fifo_dma_sweep(32'h6001_0000, 16'd64,   32'h5100_0064, 5, 1'b1); // Pre-armed DMA + 5-cycle gaps
        run_fifo_dma_sweep(32'h8001_0000, 16'd64,   32'h5100_3264, 5, 1'b1); // Pre-armed DMA + 5-cycle gaps (DWC)

        $display("=================================================================");
        $display("   ALL ASYNC FIFO-TO-AXI4 REGRESSION SWEEPS PASSED CLEANLY!      ");
        $display("=================================================================\n");
        $finish;
    end

endmodule
`resetall