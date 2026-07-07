//------------------------------------------------------------------------------
// Module: tb_fpga_top_v3_axi_direct
// Description: Multi-Slave Dedicated Interface Bus Regression Platform.
//------------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module tb_top_axi;

    // Simulation Stimulus Wires / Registers
    reg         clk_50mhz = 1'b0;   
    reg         board_rst;          
    
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

    // Loop trackers
    integer idx;

    // 50 MHz Oscillator Generator (20ns Period)
    always #10.00 clk_50mhz = ~clk_50mhz;

    // Unit Under Test (UUT) Instantiation
    top uut (
        .clk_50mhz    (clk_50mhz),
        .board_rst    (board_rst),
        .start_write  (start_write),
        .start_read   (start_read),
        .base_address (base_address),
        .word_count   (word_count),
        .axi_busy     (axi_busy),
        .axi_done     (axi_done),
        .ram_a_we     (ram_a_we),
        .ram_a_addr   (ram_a_addr),
        .ram_a_wdata  (ram_a_wdata),
        .ram_a_rdata  (ram_a_rdata)
    );

    //--------------------------------------------------------------------------
    // LOW-LEVEL TRANSACTION CONTROLLER TASKS
    //--------------------------------------------------------------------------
    task execute_hardware_axi_write;
        input [31:0] addr;
        input [15:0] count;
        begin
            wait(!axi_busy);
            @(posedge uut.clk_80mhz); #1; 
            base_address = addr;
            word_count   = count;
            start_write  = 1'b1;
            @(posedge uut.clk_80mhz); #1;
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
            @(posedge uut.clk_80mhz); #1;
            base_address = addr;
            word_count   = count;
            start_read   = 1'b1;
            @(posedge uut.clk_80mhz); #1;
            start_read   = 1'b0;
            @(posedge axi_done);
            #10;
        end
    endtask

    //--------------------------------------------------------------------------
    // AUTOMATED MATRIX REGRESSION SWEEP TASK
    //--------------------------------------------------------------------------
   
//--------------------------------------------------------------------------
    // AUTOMATED MATRIX REGRESSION SWEEP TASK
    //--------------------------------------------------------------------------
    task run_burst_regression_sweep;
        input [31:0] target_axi_addr;
        input [15:0] total_words;
        input [31:0] pattern_header;
        integer i;
        reg mismatch_detected; // Local task tracking register
        begin
            mismatch_detected = 1'b0;
            $display("[MATRIX SWEEP] Testing Target Address 0x%08X | Length: %0d Beats", target_axi_addr, total_words);
            
            // Fill Internal RAM A with test data
            for (i = 0; i < total_words; i = i + 1) begin
                @(posedge uut.clk_80mhz); #1;
                ram_a_addr  = i[7:0];
                ram_a_wdata = {pattern_header, i[31:0]};
                ram_a_we    = 1'b1;
            end
            @(posedge uut.clk_80mhz); #1; ram_a_we = 1'b0;

            // Execute the master write transaction to external AXI
            execute_hardware_axi_write(target_axi_addr, total_words);

            // Clear Internal RAM A to prove read recovery works
            for (i = 0; i < total_words; i = i + 1) begin
                @(posedge uut.clk_80mhz); #1;
                ram_a_addr  = i[7:0];
                ram_a_wdata = 64'h0;
                ram_a_we    = 1'b1;
            end
            @(posedge uut.clk_80mhz); #1; ram_a_we = 1'b0;

            // Execute the master read transaction back from external AXI
            execute_hardware_axi_read(target_axi_addr, total_words);

            // Print itemized data comparison logs for each location
            $display("  --- Individual Location Verification Report ---");
            for (i = 0; i < total_words; i = i + 1) begin
                ram_a_addr = i[7:0];
                @(posedge uut.clk_80mhz); #1; 
                
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

        $display("\n=========================================================");
        $display("   LAUNCHING SEPARATED PORT REGRESSION SWEEPS             ");
        $display("=========================================================");
        
        #100;
        board_rst = 1'b0; 
        
        @(posedge uut.pll_inst.LOCK);
        #50;
        $display("[STATUS] Global clock stabilized at 80 MHz. Initiating sweeps...\n");

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
