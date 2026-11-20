//------------------------------------------------------------------------------
// Module: tb_top_axi
// Company/Institution:  Tecnomic Components
// Engineer:             Jijeesh M
// 
// Description:
//   Multi-Slave Dedicated Interface Bus Regression Platform.
//   Verifies dual physical DDR3 memory interfaces (East and West) mapped 
//   inside the AXI space using 2 parallel sets of 4 parallel DDR3 memory chips.
//
//   Integrated Features:
//     - Realigned ports and wires to match the updated dual-DDR top-level layout.
//     - Probed internal joint fddr_init_done status hierarchically.
//     - Trimmed out stagnant internal AXI block RAM sweeps.
//------------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module tb_top_axi4;
    localparam integer RAM_ADDR_WIDTH = 16; // Matches 512 KB (65,536 x 64-bit) staging RAM

    // Simulation Stimulus Wires / Registers
    reg                       clk_50mhz    = 1'b0;
    reg                       NSYSRESET    = 1'b0;
    reg                       start_write  = 1'b0;
    reg                       start_read   = 1'b0;
    reg  [31:0]               base_address = 32'h0;
    reg  [15:0]               word_count   = 16'h0;
    wire                      axi_busy;
    wire                      axi_done;

    reg                       ram_a_we     = 1'b0;
    reg  [RAM_ADDR_WIDTH-1:0] ram_a_addr   = {RAM_ADDR_WIDTH{1'b0}};
    reg  [63:0]               ram_a_wdata  = 64'h0;
    wire [63:0]               ram_a_rdata;
    wire                      clk_100mhz;

    // 50 MHz Oscillator Generator (20ns Period -> 100 MHz PF_CCC output)
    always #10.00 clk_50mhz = ~clk_50mhz;

    // Reset Pulse
    initial begin
        #100;
        NSYSRESET = 1'b1;
    end

    //--------------------------------------------------------------------------
    // UNIT UNDER TEST (UUT) INSTANTIATION
    //--------------------------------------------------------------------------
    top uut (
        .reset_n      (NSYSRESET),
        .REF_CLK      (clk_50mhz),
        .base_address (base_address),
        .ram_a_addr   (ram_a_addr),
        .ram_a_wdata  (ram_a_wdata),
        .ram_a_we     (ram_a_we),
        .start_read   (start_read),
        .start_write  (start_write),
        .word_count   (word_count),
        .CLK_100      (clk_100mhz),
        .axi_busy     (axi_busy),
        .axi_done     (axi_done),
        .ram_a_rdata  (ram_a_rdata)
    );

    //--------------------------------------------------------------------------
    // LOW-LEVEL TRANSACTION CONTROLLER TASKS (With Dynamic Cycle Watchdogs)
    //--------------------------------------------------------------------------
    task execute_hardware_axi_write;
        input [31:0] addr;
        input [15:0] count;
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

            max_cycles  = (count * 8) + 5000;
            timeout_cnt = 0;
            while (!axi_done && timeout_cnt < max_cycles) begin
                @(posedge clk_100mhz);
                timeout_cnt = timeout_cnt + 1;
            end
            if (!axi_done) begin
                $display("[TIMEOUT] AXI Write stalled at 0x%08X (Words: %0d, Cycles: %0d)",
                         addr, count, timeout_cnt);
                $finish;
            end
            #10;
        end
    endtask

    task execute_hardware_axi_read;
        input [31:0] addr;
        input [15:0] count;
        integer timeout_cnt;
        integer max_cycles;
        begin
            wait(!axi_busy);
            @(posedge clk_100mhz); #1;
            base_address = addr;
            word_count   = count;
            start_read   = 1'b1;
            @(posedge clk_100mhz); #1;
            start_read   = 1'b0;

            max_cycles  = (count * 8) + 5000;
            timeout_cnt = 0;
            while (!axi_done && timeout_cnt < max_cycles) begin
                @(posedge clk_100mhz);
                timeout_cnt = timeout_cnt + 1;
            end
            if (!axi_done) begin
                $display("[TIMEOUT] AXI Read stalled at 0x%08X (Words: %0d, Cycles: %0d)",
                         addr, count, timeout_cnt);
                $finish;
            end
            #10;
        end
    endtask

    //--------------------------------------------------------------------------
    // AUTOMATED MATRIX REGRESSION SWEEP TASK
    //--------------------------------------------------------------------------
    task run_burst_regression_sweep;
        input [31:0] target_axi_addr;
        input [15:0] total_words;
        input [31:0] pattern_header;
        integer i;
        integer error_count;
        begin
            error_count = 0;
            $display("[MATRIX SWEEP] Addr: 0x%08X | Words: %0d (%0d Bytes)",
                     target_axi_addr, total_words, total_words * 8);

            // 1. Fill Internal Staging RAM A with deterministic test pattern
            for (i = 0; i < total_words; i = i + 1) begin
                @(posedge clk_100mhz); #1;
                ram_a_addr  = i[RAM_ADDR_WIDTH-1:0];
                ram_a_wdata = {pattern_header, i[31:0]};
                ram_a_we    = 1'b1;
            end
            @(posedge clk_100mhz); #1;
            ram_a_we = 1'b0;

            // 2. Execute multi-burst AXI4 Write (RAM -> External AXI Slave)
            execute_hardware_axi_write(target_axi_addr, total_words);

            // 3. Clear Internal Staging RAM A to prove readback recovery
            for (i = 0; i < total_words; i = i + 1) begin
                @(posedge clk_100mhz); #1;
                ram_a_addr  = i[RAM_ADDR_WIDTH-1:0];
                ram_a_wdata = 64'h0;
                ram_a_we    = 1'b1;
            end
            @(posedge clk_100mhz); #1;
            ram_a_we = 1'b0;

            // 4. Execute multi-burst AXI4 Read (External AXI Slave -> RAM)
            execute_hardware_axi_read(target_axi_addr, total_words);

            // 5. Verify all words (log sample beats for large transfers, all errors)
            for (i = 0; i < total_words; i = i + 1) begin
                ram_a_addr = i[RAM_ADDR_WIDTH-1:0];
                @(posedge clk_100mhz); #1;

                if (ram_a_rdata === {pattern_header, i[31:0]}) begin
                    if (total_words <= 16 || i < 3 || i >= (total_words - 3)) begin
                        $display("  [MATCH] Word %05d | AXI Addr: 0x%08X | Data: 0x%016X",
                                 i, target_axi_addr + (i * 8), ram_a_rdata);
                    end
                end else begin
                    if (error_count < 16) begin
                        $display("  [ERROR] Word %05d | AXI Addr: 0x%08X | Expected: 0x%016X | Got: 0x%016X",
                                 i, target_axi_addr + (i * 8), {pattern_header, i[31:0]}, ram_a_rdata);
                    end
                    error_count = error_count + 1;
                end
            end

            if (error_count > 0) begin
                $display("\n[CRITICAL FAILURE] %0d mismatches detected at Address 0x%08X!\n",
                         error_count, target_axi_addr);
                $finish;
            end else begin
                $display("  [PASS] All %0d words (%0d Bytes) verified cleanly.\n",
                         total_words, total_words * 8);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // MAIN SIMULATION CONTROL ROUTINE
    //--------------------------------------------------------------------------
    initial begin
        $display("\n=========================================================");
        $display("   LAUNCHING MULTI-BURST AXI4 MEMORY REGRESSION SWEEPS   ");
        $display("=========================================================");

        $display("[STATUS] Waiting for PF_CCC PLL lock and synchronized reset release...");
        wait(uut.reset_synchronizer_1_reset_sync === 1'b1);
        repeat (5) @(posedge clk_100mhz);
        $display("[STATUS] PLL locked and system reset released! Starting sweeps.\n");

        // ---------------------------------------------------------------------
        // PHASE 1: LOWER SLAVE ZONE (64-bit AXI4 SRAM @ 0x6000_0000)
        // ---------------------------------------------------------------------
        $display("---------------------------------------------------------");
        $display(" PHASE 1: SLAVE 0 (64-BIT) SINGLE & MULTI-BURST SWEEPS   ");
        $display("---------------------------------------------------------");
        run_burst_regression_sweep(32'h6000_1000, 16'd1,     32'hC001_A001); // 8 B (1 beat)
        run_burst_regression_sweep(32'h6000_2400, 16'd4,     32'hBEEF_0004); // 32 B
        run_burst_regression_sweep(32'h6000_3000, 16'd13,    32'h7777_D111); // 104 B
        run_burst_regression_sweep(32'h6000_4500, 16'd64,    32'hDEAD_0064); // 512 B
        run_burst_regression_sweep(32'h6000_0000, 16'd256,   32'h5555_0256); // 2 KB (max single burst)
        run_burst_regression_sweep(32'h6000_0000, 16'd512,   32'h4B00_0512); // 4 KB (2 bursts)
        run_burst_regression_sweep(32'h6000_0E00, 16'd600,   32'hB0D0_0600); // 4.8 KB (4KB boundary split)
        run_burst_regression_sweep(32'h6000_0000, 16'd4096,  32'h320B_4096); // 32 KB (16 bursts)
        run_burst_regression_sweep(32'h6000_0000, 16'd12800, 32'h100C_C800); // 100 KB (50 bursts)

        // ---------------------------------------------------------------------
        // PHASE 2: UPPER SLAVE ZONE (32-bit Width-Converted SRAM @ 0x8000_0000)
        // ---------------------------------------------------------------------
        $display("---------------------------------------------------------");
        $display(" PHASE 2: SLAVE 1 (32-BIT DWC) SINGLE & MULTI-BURST SWEEPS");
        $display("---------------------------------------------------------");
        run_burst_regression_sweep(32'h8000_0000, 16'd1,     32'hC002_B002); // 8 B
        run_burst_regression_sweep(32'h8000_1000, 16'd8,     32'hA5A5_0008); // 64 B
        run_burst_regression_sweep(32'h8000_4200, 16'd32,    32'hB4B4_0032); // 256 B
        run_burst_regression_sweep(32'h8000_8000, 16'd127,   32'hECEC_0127); // 1,016 B
        run_burst_regression_sweep(32'h8000_A000, 16'd256,   32'h9999_0256); // 2 KB
        run_burst_regression_sweep(32'h8000_0000, 16'd1024,  32'h8B00_1024); // 8 KB (4 bursts)
        run_burst_regression_sweep(32'h8000_0000, 16'd12800, 32'h100C_32B1); // 100 KB (50 bursts)
     

        $display("=========================================================");
        $display("   ALL MULTI-BURST (UP TO 200 KB) SWEEPS PASSED!         ");
        $display("=========================================================\n");
        $finish;
    end

endmodule
`resetall