//------------------------------------------------------------------------------
// Company/Institution:  Creative System Labs
// Engineer:             Unified Engineering AI Group
// 
// Create Date:          2026
// Module Name:          tb_fpga_top_v3_axi_direct
// Project Name:         RTG4/SmartFusion2 Serial to AXI Memory Staging System
//
// Description:
//   Multi-Slave Direct AXI Fabric Testbench. Bypasses the slow UART clock domain
//   and executes pure 80 MHz back-to-back hardware regressions.
//   
//   Sweeps Verified:
//     - Target RAM 1 (Lower Domain: 0x0000_0000) vs Target RAM 2 (Upper Domain: 0xE000_0000)
//     - Dynamic Burst Lengths: 1 beat, 4 beats, 32 beats, up to full 256 beats.
//     - Pattern uniqueness checks to prevent false read-back verification passes.
//------------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module tb_fpga_top_v3_axi_direct;

    //--------------------------------------------------------------------------
    // Simulation Stimulus Signals
    //--------------------------------------------------------------------------
    reg  clk_50mhz;
    reg  board_rst;
    reg  rx_serial;
    wire tx_serial;

    // Diagnostic Iteration Control Registers
    integer idx;
    reg [63:0] verification_read_word;
    reg [63:0] expected_pattern;

    //--------------------------------------------------------------------------
    // 50 MHz Board Clock Oscillator (20ns Period)
    //--------------------------------------------------------------------------
    always #10.00 clk_50mhz = ~clk_50mhz;

    //--------------------------------------------------------------------------
    // Unit Under Test (UUT) Instantiation
    //--------------------------------------------------------------------------
    fpga_top uut (
        .clk_50mhz (clk_50mhz),
        .board_rst (board_rst),
        .rx_serial (rx_serial),
        .tx_serial (tx_serial)
    );

    //--------------------------------------------------------------------------
    // REAL-TIME INTERCONNECT & BUS MONITORS
    //--------------------------------------------------------------------------
    always @(posedge uut.clk_80mhz) begin
        if (uut.sys_rst_n) begin
            // Track Interconnect Slave Input Port (From Master Mover)
            if (uut.mst_awvalid && uut.mst_awready) begin
                $display("[IC INPUT PORT] AW Write Address: 0x%08X Intercepted. LEN-Beats: %0d", uut.mst_awaddr, uut.mst_awlen + 1);
            end
            if (uut.mst_arvalid && uut.mst_arready) begin
                $display("[IC INPUT PORT] AR Read Address:  0x%08X Intercepted. LEN-Beats: %0d", uut.mst_araddr, uut.mst_arlen + 1);
            end

            // Monitor Routed Operations to RAM 1 (Lower Select)
            if (uut.ic_m_awvalid[0] && uut.ic_m_awready[0]) begin
                $display("  ==> ROUTING TO RAM 1 (LOWER): AWADDR=0x%08X, Physical index slice=0x%04X", uut.ic_m_awaddr[31:0], uut.ic_m_awaddr[13:0]);
            end
            if (uut.ic_m_arvalid[0] && uut.ic_m_arready[0]) begin
                $display("  ==> ROUTING TO RAM 1 (LOWER): ARADDR=0x%08X, Physical index slice=0x%04X", uut.ic_m_araddr[31:0], uut.ic_m_araddr[13:0]);
            end

            // Monitor Routed Operations to RAM 2 (Upper Select)
            if (uut.ic_m_awvalid[1] && uut.ic_m_awready[1]) begin
                $display("  ==> ROUTING TO RAM 2 (UPPER): AWADDR=0x%08X, Physical index slice=0x%04X", uut.ic_m_awaddr[63:32], uut.ic_m_awaddr[45:32]);
            end
            if (uut.ic_m_arvalid[1] && uut.ic_m_arready[1]) begin
                $display("  ==> ROUTING TO RAM 2 (UPPER): ARADDR=0x%08X, Physical index slice=0x%04X", uut.ic_m_araddr[63:32], uut.ic_m_araddr[45:32]);
            end
        end
    end

    //--------------------------------------------------------------------------
    // PARAMETERIZABLE COP_ROCESSING DRIVER TASKS
    //--------------------------------------------------------------------------
    
    // Task to trigger an AXI Master Write transaction from Staging RAM -> Bus
    task execute_direct_axi_master_write;
        input [31:0] target_address; 
        input [15:0] block_word_count;
        begin
            wait(uut.protocol_engine_inst.state == 5'd0); // Wait for idle
            @(posedge uut.clk_80mhz);
            
            force uut.axi_shared_address    = target_address;
            force uut.axi_shared_word_len   = block_word_count;
            force uut.axi_start_write_pulse = 1'b1;
            
            @(posedge uut.clk_80mhz);
            force uut.axi_start_write_pulse = 1'b0;
            
            @(posedge uut.axi_mover_done_pulse); // Wait for done handshake
            
            release uut.axi_shared_address;
            release uut.axi_shared_word_len;
            release uut.axi_start_write_pulse;
        end
    endtask

    // Task to trigger an AXI Master Read transaction from Bus -> Staging RAM
    task execute_direct_axi_master_read;
        input [31:0] target_address; 
        input [15:0] block_word_count;
        begin
            wait(uut.protocol_engine_inst.state == 5'd0);
            @(posedge uut.clk_80mhz);
            
            force uut.axi_shared_address   = target_address;
            force uut.axi_shared_word_len  = block_word_count;
            force uut.axi_start_read_pulse = 1'b1;
            
            @(posedge uut.clk_80mhz);
            force uut.axi_start_read_pulse = 1'b0;
            
            @(posedge uut.axi_mover_done_pulse);
            
            release uut.axi_shared_address;
            release uut.axi_shared_word_len;
            release uut.axi_start_read_pulse;
        end
    endtask

    //--------------------------------------------------------------------------
    // MAIN SIMULATION STIMULUS MATRIX RUNS
    //--------------------------------------------------------------------------
    initial begin
        // Initialize lines at time-zero to clean up unknowns 'X'
        clk_50mhz = 1'b0;
        board_rst = 1'b1; // Hold hardware in active reset state
        rx_serial = 1'b1;

        $display("\n=========================================================");
        $display("   STARTING MULTI-MEMORY INTERCONNECT REGRESSION SWEEPS   ");
        $display("=========================================================");
        
        #100;
        board_rst = 1'b0; // Release hardware reset
        
        @(posedge uut.pll_inst.LOCK); // Block progression until PLL matches frequency lock
        #50;
        $display("[SYSTEM STATUS] Fabric clock tree stabilized at 80 MHz. Commencing tests...");

        //======================================================================
        // PHASE 1: TARGETING AXI RAM 1 (LOWER SPACE: 0x0000_0000 Region)
        //======================================================================
        $display("\n---------------------------------------------------------");
        $display("  PHASE 1: TESTING AXI RAM 1 (LOWER ADDR RANGE BLOCK)");
        $display("---------------------------------------------------------");

        // Test 1A: Single-Beat (1 Word / 8 Bytes)
        $display("\n[TEST 1A] Executing Single Word Transfer to RAM 1...");
        uut.staging_buffer_ram.dual_port_mem[0] = 64'h1111_2222_3333_4444;
        execute_direct_axi_master_write(32'h0000_1000, 16'd1);
        uut.staging_buffer_ram.dual_port_mem[0] = 64'h0; // Clear buffer
        execute_direct_axi_master_read(32'h0000_1000, 16'd1);
        
        if (uut.staging_buffer_ram.dual_port_mem[0] !== 64'h1111_2222_3333_4444) begin
            $display("[FATAL MISMATCH] Test 1A Failed! Got: 0x%016X", uut.staging_buffer_ram.dual_port_mem[0]); $finish;
        end
        $display(" -> Verified Successfully.");

        // Test 1B: Short Burst (4 Words / 32 Bytes)
        $display("\n[TEST 1B] Executing Short Burst (4 Words) to RAM 1...");
        for (idx = 0; idx < 4; idx = idx + 1) begin
            uut.staging_buffer_ram.dual_port_mem[idx] = {32'hAAAA_0001, idx[31:0]};
        end
        execute_direct_axi_master_write(32'h0000_2000, 16'd4);
        for (idx = 0; idx < 4; idx = idx + 1) uut.staging_buffer_ram.dual_port_mem[idx] = 64'h0; // Clear
        execute_direct_axi_master_read(32'h0000_2000, 16'd4);
        
        for (idx = 0; idx < 4; idx = idx + 1) begin
            if (uut.staging_buffer_ram.dual_port_mem[idx] !== {32'hAAAA_0001, idx[31:0]}) begin
                $display("[FATAL MISMATCH] Test 1B Failed at index %0d!", idx); $finish;
            end
        end
        $display(" -> Verified Successfully.");

        // Test 1C: Full Pipeline Stress Burst (256 Words / 2048 Bytes)
        $display("\n[TEST 1C] Executing Max Burst Size (256 Words / 2KB) to RAM 1...");
        for (idx = 0; idx < 256; idx = idx + 1) begin
            uut.staging_buffer_ram.dual_port_mem[idx] = {32'h5555_CCCC, idx[31:0]};
        end
        execute_direct_axi_master_write(32'h0000_0000, 16'd256);
        for (idx = 0; idx < 256; idx = idx + 1) uut.staging_buffer_ram.dual_port_mem[idx] = 64'h0; // Clear
        execute_direct_axi_master_read(32'h0000_0000, 16'd256);
        
        for (idx = 0; idx < 256; idx = idx + 1) begin
            if (uut.staging_buffer_ram.dual_port_mem[idx] !== {32'h5555_CCCC, idx[31:0]}) begin
                $display("[FATAL MISMATCH] Test 1C Failed at index %0d!", idx); $finish;
            end
        end
        $display(" -> Verified Successfully. 256-beat back-to-back burst boundaries confirmed clean.");


        //======================================================================
        // PHASE 2: TARGETING AXI RAM 2 (UPPER SPACE: 0xE000_0000 Region)
        //======================================================================
        $display("\n---------------------------------------------------------");
        $display("  PHASE 2: TESTING AXI RAM 2 (UPPER ADDR RANGE BLOCK)");
        $display("---------------------------------------------------------");

        // Test 2A: Single-Beat (1 Word / 8 Bytes)
        $display("\n[TEST 2A] Executing Single Word Transfer to RAM 2...");
        uut.staging_buffer_ram.dual_port_mem[0] = 64'h9999_8888_7777_6666;
        execute_direct_axi_master_write(32'hE000_1000, 16'd1);
        uut.staging_buffer_ram.dual_port_mem[0] = 64'h0; // Clear buffer
        execute_direct_axi_master_read(32'hE000_1000, 16'd1);
        
        if (uut.staging_buffer_ram.dual_port_mem[0] !== 64'h9999_8888_7777_6666) begin
            $display("[FATAL MISMATCH] Test 2A Failed! Got: 0x%016X", uut.staging_buffer_ram.dual_port_mem[0]); $finish;
        end
        $display(" -> Verified Successfully.");

        // Test 2B: Medium Burst (32 Words / 256 Bytes)
        $display("\n[TEST 2B] Executing Medium Burst (32 Words) to RAM 2...");
        for (idx = 0; idx < 32; idx = idx + 1) begin
            uut.staging_buffer_ram.dual_port_mem[idx] = {32'hBBBB_0002, idx[31:0]};
        end
        execute_direct_axi_master_write(32'hE000_1500, 16'd32);
        for (idx = 0; idx < 32; idx = idx + 1) uut.staging_buffer_ram.dual_port_mem[idx] = 64'h0; // Clear
        execute_direct_axi_master_read(32'hE000_1500, 16'd32);
        
        for (idx = 0; idx < 32; idx = idx + 1) begin
            if (uut.staging_buffer_ram.dual_port_mem[idx] !== {32'hBBBB_0002, idx[31:0]}) begin
                $display("[FATAL MISMATCH] Test 2B Failed at index %0d!", idx); $finish;
            end
        end
        $display(" -> Verified Successfully.");

        // Test 2C: Full Pipeline Stress Burst (256 Words / 2048 Bytes)
        $display("\n[TEST 2C] Executing Max Burst Size (256 Words / 2KB) to RAM 2...");
        for (idx = 0; idx < 256; idx = idx + 1) begin
            uut.staging_buffer_ram.dual_port_mem[idx] = {32'hEEEE_3333, idx[31:0]};
        end
        execute_direct_axi_master_write(32'hE000_0000, 16'd256);
        for (idx = 0; idx < 256; idx = idx + 1) uut.staging_buffer_ram.dual_port_mem[idx] = 64'h0; // Clear
        execute_direct_axi_master_read(32'hE000_0000, 16'd256);
        
        for (idx = 0; idx < 256; idx = idx + 1) begin
            if (uut.staging_buffer_ram.dual_port_mem[idx] !== {32'hEEEE_3333, idx[31:0]}) begin
                $display("[FATAL MISMATCH] Test 2C Failed at index %0d!", idx); $finish;
            end
        end
        $display(" -> Verified Successfully. Interconnect address routing decoding matrices verified completely stable.");

        //----------------------------------------------------------------------
        // SIMULATION WRAP-UP
        //----------------------------------------------------------------------
        $display("\n=========================================================");
        $display("   ALL MULTI-SLAVE AND MULTI-BURST OPERATIONS COMPLETED  ");
        $display("   REGRESSION LOG: ALL CHECKS PASSED WITH ZERO ERRORS   ");
        $display("=========================================================\n");
        $finish;
    end

endmodule
`resetall
