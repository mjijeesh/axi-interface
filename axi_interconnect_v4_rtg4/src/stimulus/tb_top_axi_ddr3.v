//------------------------------------------------------------------------------
// Module: tb_top_axi
// Company/Institution:  Creative System Labs
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

module tb_top_axi_ddr3;
    // Simulation Stimulus Wires / Registers
    reg         clk_50mhz = 1'b0;
    reg         board_rst;    
    reg         NSYSRESET;
    reg         start_write;
    reg         start_read;
    reg  [31:0] base_address;
    reg  [15:0] word_count;
    wire        axi_busy;
    wire        axi_done;

    reg         ram_a_we;
    reg  [7:0]  ram_a_addr;
    reg  [63:0] ram_a_wdata;
    wire [63:0] ram_a_rdata;

    //--------------------------------------------------------------------------
    // DDR3 PHYSICAL SYSTEM COUPLING WIRES - EAST DOMAIN (DDR_0)
    //--------------------------------------------------------------------------
    wire [15:0] fddr_east_addr;
    wire [2:0]  fddr_east_ba;
    wire        fddr_east_cas_n;
    wire        fddr_east_cke;
    wire        fddr_east_clk;
    wire        fddr_east_clk_n;
    wire        fddr_east_cs_n;
    wire        fddr_east_odt;
    wire        fddr_east_ras_n;
    wire        fddr_east_reset_n;
    wire        fddr_east_we_n;
    wire [3:0]  fddr_east_dm_rdqs;
    wire [31:0] fddr_east_dq;
    wire [3:0]  fddr_east_dqs;
    wire [3:0]  fddr_east_dqs_n;
    wire        fddr_east_dqs_tmatch_0_out;
    wire        fddr_east_dqs_tmatch_1_out;

    //--------------------------------------------------------------------------
    // DDR3 PHYSICAL SYSTEM COUPLING WIRES - WEST DOMAIN (DDR_1)
    //--------------------------------------------------------------------------
    wire [15:0] fddr_west_addr;
    wire [2:0]  fddr_west_ba;
    wire        fddr_west_cas_n;
    wire        fddr_west_cke;
    wire        fddr_west_clk;
    wire        fddr_west_clk_n;
    wire        fddr_west_cs_n;
    wire        fddr_west_odt;
    wire        fddr_west_ras_n;
    wire        fddr_west_reset_n;
    wire        fddr_west_we_n;
    wire [3:0]  fddr_west_dm_rdqs;
    wire [31:0] fddr_west_dq;
    wire [3:0]  fddr_west_dqs;
    wire [3:0]  fddr_west_dqs_n;
    wire        fddr_west_dqs_tmatch_0_out;
    wire        fddr_west_dqs_tmatch_1_out;

    // System Monitoring Nets
    wire [0:0]  fddr_init_done;
    wire        clk_80mhz;

    // Loop trackers
    integer idx;

    // 50 MHz Oscillator Generator (20ns Period)
    always #10.00 clk_50mhz = ~clk_50mhz;

    // Reset Pulse
    initial begin
        #100;
        NSYSRESET = 1'b1;
    end

    //--------------------------------------------------------------------------
    // UNIT UNDER TEST (UUT) INSTANTIATION (Dual-Controller Layout)
    //--------------------------------------------------------------------------
    top uut (
        // Inputs
        .DEVRST_N                 (NSYSRESET),
        .base_address             (base_address),
        .ram_a_addr               (ram_a_addr),
        .ram_a_wdata              (ram_a_wdata),
        .ram_a_we                 (ram_a_we),
        .start_read               (start_read),
        .start_write              (start_write),
        .word_count               (word_count),
        
        // Outputs
        .GL0                      (clk_80mhz),
        .axi_busy                 (axi_busy),
        .axi_done                 (axi_done),
        .init_done                (fddr_init_done),
        .ram_a_rdata              (ram_a_rdata),

        // DDR3 East Physical Ports (DDR_0)
        .FDDR_ADDR_0              (fddr_east_addr),
        .FDDR_BA_0                (fddr_east_ba),
        .FDDR_CAS_N_0             (fddr_east_cas_n),
        .FDDR_CKE_0               (fddr_east_cke),
        .FDDR_CLK_0               (fddr_east_clk),
        .FDDR_CLK_N_0             (fddr_east_clk_n),
        .FDDR_CS_N_0              (fddr_east_cs_n),
        .FDDR_ODT_0               (fddr_east_odt),
        .FDDR_RAS_N_0             (fddr_east_ras_n),
        .FDDR_RESET_N_0           (fddr_east_reset_n),
        .FDDR_WE_N_0              (fddr_east_we_n),
        .FDDR_DM_RDQS_0           (fddr_east_dm_rdqs),
        .FDDR_DQ_0                (fddr_east_dq),
        .FDDR_DQS_0               (fddr_east_dqs),
        .FDDR_DQS_N_0             (fddr_east_dqs_n),
        .FDDR_DQS_TMATCH_0_IN_0   (fddr_east_dqs_tmatch_0_out),
        .FDDR_DQS_TMATCH_1_IN_0   (fddr_east_dqs_tmatch_1_out),
        .FDDR_DQS_TMATCH_0_OUT_0  (fddr_east_dqs_tmatch_0_out),
        .FDDR_DQS_TMATCH_1_OUT_0  (fddr_east_dqs_tmatch_1_out),

        // DDR3 West Physical Ports (DDR_1)
        .FDDR_ADDR              (fddr_west_addr),
        .FDDR_BA                (fddr_west_ba),
        .FDDR_CAS_N             (fddr_west_cas_n),
        .FDDR_CKE               (fddr_west_cke),
        .FDDR_CLK               (fddr_west_clk),
        .FDDR_CLK_N             (fddr_west_clk_n),
        .FDDR_CS_N              (fddr_west_cs_n),
        .FDDR_ODT               (fddr_west_odt),
        .FDDR_RAS_N             (fddr_west_ras_n),
        .FDDR_RESET_N           (fddr_west_reset_n),
        .FDDR_WE_N              (fddr_west_we_n),
        .FDDR_DM_RDQS           (fddr_west_dm_rdqs),
        .FDDR_DQ                (fddr_west_dq),
        .FDDR_DQS               (fddr_west_dqs),
        .FDDR_DQS_N             (fddr_west_dqs_n),
        .FDDR_DQS_TMATCH_0_IN   (fddr_west_dqs_tmatch_0_out),
        .FDDR_DQS_TMATCH_1_IN   (fddr_west_dqs_tmatch_1_out),
        .FDDR_DQS_TMATCH_0_OUT  (fddr_west_dqs_tmatch_0_out),
        .FDDR_DQS_TMATCH_1_OUT  (fddr_west_dqs_tmatch_1_out)
    );

    //--------------------------------------------------------------------------
    // INSTANTIATE 4 x8 DDR3 MEMORY MODULES IN PARALLEL FOR EAST CHANNEL
    //--------------------------------------------------------------------------
    generate
        genvar e;
        for (e = 0; e < 4; e = e + 1) begin : ddr3_chip_east
            ddr3 #(
                .check_strict_timing (1'b0), // Relax timing violations for 80 MHz clock
                .STOP_ON_ERROR       (1'b0), // Avoid simulation aborts on clock warnings
                .DEBUG               (1'b0)  // Clean up diagnostic shell outputs
            ) ddr3_east_inst (
                .rst_n   (fddr_east_reset_n),
                .ck      (fddr_east_clk),
                .ck_n    (fddr_east_clk_n),
                .cke     (fddr_east_cke),
                .cs_n    (fddr_east_cs_n),
                .ras_n   (fddr_east_ras_n),
                .cas_n   (fddr_east_cas_n),
                .we_n    (fddr_east_we_n),
                .dm_tdqs (fddr_east_dm_rdqs[e]),
                .ba      (fddr_east_ba),
                .addr    (fddr_east_addr[14:0]),
                .dq      (fddr_east_dq[8*e +: 8]),
                .dqs     (fddr_east_dqs[e]),
                .dqs_n   (fddr_east_dqs_n[e]),
                .tdqs_n  (), 
                .odt     (fddr_east_odt)
            );
        end
    endgenerate

    //--------------------------------------------------------------------------
    // INSTANTIATE 4 x8 DDR3 MEMORY MODULES IN PARALLEL FOR WEST CHANNEL
    //--------------------------------------------------------------------------
    generate
        genvar w;
        for (w = 0; w < 4; w = w + 1) begin : ddr3_chip_west
            ddr3 #(
                .check_strict_timing (1'b0), 
                .STOP_ON_ERROR       (1'b0), 
                .DEBUG               (1'b0)  
            ) ddr3_west_inst (
                .rst_n   (fddr_west_reset_n),
                .ck      (fddr_west_clk),
                .ck_n    (fddr_west_clk_n),
                .cke     (fddr_west_cke),
                .cs_n    (fddr_west_cs_n),
                .ras_n   (fddr_west_ras_n),
                .cas_n   (fddr_west_cas_n),
                .we_n    (fddr_west_we_n),
                .dm_tdqs (fddr_west_dm_rdqs[w]),
                .ba      (fddr_west_ba),
                .addr    (fddr_west_addr[14:0]),
                .dq      (fddr_west_dq[8*w +: 8]),
                .dqs     (fddr_west_dqs[w]),
                .dqs_n   (fddr_west_dqs_n[w]),
                .tdqs_n  (), 
                .odt     (fddr_west_odt)
            );
        end
    endgenerate

    //--------------------------------------------------------------------------
    // LOW-LEVEL TRANSACTION CONTROLLER TASKS
    //--------------------------------------------------------------------------
    task execute_hardware_axi_write;
        input [31:0] addr;
        input [15:0] count;
        begin
            wait(!axi_busy);
            @(posedge clk_80mhz); #1; 
            base_address = addr;
            word_count   = count;
            start_write  = 1'b1;
            @(posedge clk_80mhz); #1;
            start_write  = 1'b0;
            @(posedge axi_done);
            #10;
        end
    endtask

    task execute_hardware_axi_read;
        input [31:0] addr;
        input [15:0] count;
        begin
            wait(!axi_busy);
            @(posedge clk_80mhz); #1;
            base_address = addr;
            word_count   = count;
            start_read   = 1'b1;
            @(posedge clk_80mhz); #1;
            start_read   = 1'b0;
            @(posedge axi_done);
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
        reg mismatch_detected;
        begin
            mismatch_detected = 1'b0;
            $display("[MATRIX SWEEP] Testing Target Address 0x%08X | Length: %0d Beats", target_axi_addr, total_words);
            
            // Fill Internal RAM A with test data
            for (i = 0; i < total_words; i = i + 1) begin
                @(posedge clk_80mhz);
                #1;
                ram_a_addr  = i[7:0];
                ram_a_wdata = {pattern_header, i[31:0]};
                ram_a_we    = 1'b1;
            end
            @(posedge clk_80mhz); #1; ram_a_we = 1'b0;
            
            // Execute the master write transaction to external AXI
            execute_hardware_axi_write(target_axi_addr, total_words);
            
            // Clear Internal RAM A to prove read recovery works
            for (i = 0; i < total_words; i = i + 1) begin
                @(posedge clk_80mhz);
                #1;
                ram_a_addr  = i[7:0];
                ram_a_wdata = 64'h0;
                ram_a_we    = 1'b1;
            end
            @(posedge clk_80mhz); #1; ram_a_we = 1'b0;
            
            // Execute the master read transaction back from external AXI
            execute_hardware_axi_read(target_axi_addr, total_words);
            
            // Print itemized data comparison logs for each location
            $display("  --- Individual Location Verification Report ---");
            for (i = 0; i < total_words; i = i + 1) begin
                ram_a_addr = i[7:0];
                @(posedge clk_80mhz); #1; 
                
                if (ram_a_rdata === {pattern_header, i[31:0]}) begin
                    $display("  [MATCH] Beat %03d | AXI Addr: 0x%08X | Data: 0x%016X", i, target_axi_addr + (i * 8), ram_a_rdata);
                end else begin
                    $display("  [ERROR] Beat %03d | AXI Addr: 0x%08X | Expected: 0x%016X | Got: 0x%016X", i, target_axi_addr + (i * 8), {pattern_header, i[31:0]}, ram_a_rdata);
                    mismatch_detected = 1'b1;
                end
            end
            
            if (mismatch_detected) begin
                $display("\n[CRITICAL FAILURE] Sweep complete with data corruption errors at Address 0x%08X!\n", target_axi_addr);
                $finish;
            end else begin
                $display("   [PASS] Sweep zone verified successfully.\n");
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // MAIN SIMULATION CONTROL ROUTINE
    //--------------------------------------------------------------------------
    initial begin
        board_rst    = 1'b1;
        start_write  = 1'b0;
        start_read   = 1'b0;
        base_address = 32'h0;
        word_count   = 16'h0;
        ram_a_we     = 1'b0;
        ram_a_addr   = 8'h0;
        ram_a_wdata  = 64'h0;
        NSYSRESET    = 1'b0;

        $display("\n=========================================================");
        $display("   LAUNCHING EXCLUSIVE DDR3 MEMORY REGRESSION SWEEPS     ");
        $display("=========================================================");
        
        #100;
        board_rst = 1'b0;
        #50;
        $display("[STATUS] Global clock stabilized at 80 MHz.");
        
        // WAIT STEP: Wait until both physical FDDR blocks complete calibration
        $display("[STATUS] Waiting for East & West FDDR Controller Initialization to complete...");
        wait(fddr_init_done[0] === 1'b1);
        $display("[STATUS] Both FDDR Controllers Calibration complete! Memory system online.\n");
        
        // SWEEP PHASE 1: TARGETING LOWER SLAVE ZONE (AXI RAM 1: Slot 0)
        $display("---------------------------------------------------------");
        $display(" RUNNING SWEEP PHASE 1: AXI RAM 1 LOWER DOMAIN ACCURACY  ");
        $display("---------------------------------------------------------");
        run_burst_regression_sweep(32'h0000_1000, 16'd1,   32'hC001_A001);
        run_burst_regression_sweep(32'h0000_2400, 16'd4,   32'hBEEF_0004); 
        run_burst_regression_sweep(32'h0000_3000, 16'd13,  32'h7777_D111); 
        run_burst_regression_sweep(32'h0000_4500, 16'd64,  32'hDEAD_0064); 
        run_burst_regression_sweep(32'h0000_0000, 16'd256, 32'h5555_0256);

        // SWEEP PHASE 2: TARGETING UPPER SLAVE ZONE (AXI RAM 2: Slot 1)
        $display("---------------------------------------------------------");
        $display(" RUNNING SWEEP PHASE 2: AXI RAM 2 UPPER DOMAIN ACCURACY  ");
        $display("---------------------------------------------------------");
        run_burst_regression_sweep(32'hE000_0000, 16'd1,   32'hC002_B002);
        run_burst_regression_sweep(32'hE000_1000, 16'd8,   32'hA5A5_0008); 
        run_burst_regression_sweep(32'hE000_4200, 16'd32,  32'hB4B4_0032); 
        run_burst_regression_sweep(32'hE000_8000, 16'd127, 32'hECEC_0127); 
        run_burst_regression_sweep(32'hE000_A000, 16'd256, 32'h9999_0256); 

        $display("=========================================================");
        $display("   ALL MULTI-PORT SEPARATED SWEEPS COMPLETED CLEANLY    ");
        $display("=========================================================\n");
        $finish;
    end

endmodule
`resetall