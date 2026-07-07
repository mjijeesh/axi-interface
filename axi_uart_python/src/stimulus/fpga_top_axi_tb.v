//------------------------------------------------------------------------------
// Company/Institution:  Creative System Labs
// Engineer:             Unified Engineering AI Group
// 
// Create Date:          2026
// Module Name:          tb_fpga_top_v3_axi_direct
// Project Name:         RTG4/SmartFusion2 Serial to AXI Memory Staging System
//
// Description:
//   Advanced high-speed system testbench designed to test the AXI4 Full Master 
//   Data Mover and target AXI RAM directly at the 80 MHz system clock rate.
//   Bypasses UART lines using clean procedural force/release task structures.
//------------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module tb_fpga_top_v3_axi_direct;

    //--------------------------------------------------------------------------
    // Simulation Stimulus Registers & Wires
    //--------------------------------------------------------------------------
    reg  clk_50mhz;
    reg  board_rst;
    reg  rx_serial;
    wire tx_serial;

    // Loop Iteration Counters
    integer idx;
    reg [63:0] verification_read_word;

    //--------------------------------------------------------------------------
    // 50 MHz Board Clock Generator (20ns Period)
    //--------------------------------------------------------------------------
    always #10.00 clk_50mhz = ~clk_50mhz;

    //--------------------------------------------------------------------------
    // Unit Under Test (UUT) Instantiation
    //--------------------------------------------------------------------------
    top uut (
        .clk_50mhz (clk_50mhz),
        .board_rst (board_rst),
        .rx_serial (rx_serial),
        .tx_serial (tx_serial)
    );

    //--------------------------------------------------------------------------
    // REAL-TIME BUS DIAGNOSTIC MONITORS
    //--------------------------------------------------------------------------
    always @(posedge uut.clk_80mhz) begin
        if (uut.sys_rst_n) begin
            // Monitor Write Address (AW) Channel Handshakes
            if (uut.axi_master_mover.m_axi_awvalid && uut.axi_master_mover.m_axi_awready) begin
                $display("[AXI4 AW CHANNEL] Time: %0t ns | Write Address 0x%08X Locked. Burst Length: %0d Beats", 
                         $time, uut.axi_master_mover.m_axi_awaddr, uut.axi_master_mover.m_axi_awlen + 1);
            end
            
            // Monitor Write Data (W) Channel Beats
            if (uut.axi_master_mover.m_axi_wvalid && uut.axi_master_mover.m_axi_wready) begin
                $display("[AXI4 DATA CHANNEL]   -> W-BEAT Transferred: Data=0x%016X, WLAST=%b", 
                         uut.axi_master_mover.m_axi_wdata, uut.axi_master_mover.m_axi_wlast);
            end
            
            // Monitor Write Response (B) Channel Handshakes
            if (uut.axi_master_mover.m_axi_bvalid && uut.axi_master_mover.m_axi_bready) begin
                $display("[AXI4 RESP Channel]   <- Write Transaction Committed. BRESP status: 2'b%b", uut.axi_master_mover.m_axi_bresp);
            end

            // Monitor Read Address (AR) Channel Handshaking
            if (uut.axi_master_mover.m_axi_arvalid && uut.axi_master_mover.m_axi_arready) begin
                $display("[TIME: %0t ns] [AXI4 AR CHANNEL] -> AR READ BURST LAUNCH: Addr=0x%08X, Beat Count=%0d", 
                         $time, uut.axi_master_mover.m_axi_araddr, uut.axi_master_mover.m_axi_arlen + 1);
            end

            // Monitor Read Data (R) Returning Beats
            if (uut.axi_master_mover.m_axi_rvalid && uut.axi_master_mover.m_axi_rready) begin
                $display("[TIME: %0t ns] [AXI4 R CHANNEL]  <- R-BEAT DATA RETURNED: Data=0x%016X, RLAST=%b", 
                         $time, uut.axi_master_mover.m_axi_rdata, uut.axi_master_mover.m_axi_rlast);
            end
        end
    end

    //--------------------------------------------------------------------------
    // DIRECT HIGH-SPEED COP_ROCESSING DRIVER TASKS
    //--------------------------------------------------------------------------
    
    // Task to trigger a clean AXI Master Write transaction from the staging RAM
    task execute_direct_axi_master_write;
        input [31:0] target_address; 
        input [15:0] block_word_count;
        begin
            $display("\n[AXI TESTMASTER] Initializing high-speed fabric Write transaction...");
            $display("[AXI TESTMASTER] Destination: 0x%08X | Footprint: %0d Words (%0d Bytes)", 
                     target_address, block_word_count, block_word_count * 8);
            
            // Wait until the underlying UART state machine is safely idling out
            wait(uut.protocol_engine_inst.state == 5'd0); 
            @(posedge uut.clk_80mhz);
            
            // Use FORCE statements to temporarily override the FSM's idling default wire values
            force uut.axi_shared_address    = target_address;
            force uut.axi_shared_word_len   = block_word_count;
            force uut.axi_start_write_pulse = 1'b1;
            
            @(posedge uut.clk_80mhz);
            force uut.axi_start_write_pulse = 1'b0;
            
            // Wait for the high speed data mover to finish driving hardware cycles
            @(posedge uut.axi_mover_done_pulse);
            
            // RELEASE the internal nets so the FSM can assume normal operation control loops
            release uut.axi_shared_address;
            release uut.axi_shared_word_len;
            release uut.axi_start_write_pulse;
            
            $display("[AXI TESTMASTER] Fabric write committed safely to target memory space.\n");
        end
    endtask

    // Task to trigger a clean AXI Master Read transaction into the staging RAM
    task execute_direct_axi_master_read;
        input [31:0] target_address; 
        input [15:0] block_word_count;
        begin
            $display("\n[AXI TESTMASTER] Initializing high-speed fabric Read transaction...");
            $display("[AXI TESTMASTER] Source Target: 0x%08X | Footprint: %0d Words", target_address, block_word_count);
            
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
            
            $display("[AXI TESTMASTER] Memory block fetched into local staging RAM buffer spaces.\n");
        end
    endtask

    //--------------------------------------------------------------------------
    // MAIN SIMULATION STIMULUS SEQUENCER
    //--------------------------------------------------------------------------
    initial begin
        // Initialize clock and control lines to remove 'X' states immediately
        clk_50mhz             = 1'b0;
        board_rst             = 1'b1; // Start in active reset (Active-High)
        rx_serial             = 1'b1; // UART lines baseline idle high

        $display("\n=========================================================");
        $display("   STARTING DIRECT AXI FABRIC BURST VERIFICATION RUNS     ");
        $display("=========================================================");
        
        #100;
        board_rst = 1'b0; // Release system reset
        
        // Wait until the clock conditioning tree stabilizes out frequency locks
        @(posedge uut.pll_inst.LOCK);
        #50;
        $display("[SYSTEM STATUS] Fabric clock tree stabilized. 80 MHz pipeline operational.");

        //----------------------------------------------------------------------
        // NATIVE TRANS-BURST TEST 1: SINGLE BEAT WRITE/READ REGRESSION
        //----------------------------------------------------------------------
        $display("\n--- RUNNING TEST 1: SINGLE-BEAT POINT ADDR ACCURACY SWEEP ---");
        
        // Hierarchically pre-seed data into cell row 0 of your True Dual-Port Staging RAM
        uut.staging_buffer_ram.dual_port_mem[0] = 64'hDEADBEEFCAFE1234;
        
        // Trigger a 1-word direct write to target AXI memory address 0x00001000
        execute_direct_axi_master_write(32'h00001000, 16'd1);

        // Clear the staging RAM to ensure we pull fresh data back from the memory array
        uut.staging_buffer_ram.dual_port_mem[0] = 64'h0000000000000000;

        // Trigger a 1-word direct read back from address 0x00001000
        execute_direct_axi_master_read(32'h00001000, 16'd1);

        // Evaluate read validation data match criteria results
        verification_read_word = uut.staging_buffer_ram.dual_port_mem[0];
        if (verification_read_word !== 64'hDEADBEEFCAFE1234) begin
            $display("[CRITICAL ERROR] Test 1 Data Mismatch! Read: 0x%016X", verification_read_word);
            $finish;
        end
        $display("[SUCCESS] Test 1 Single-Beat verification matches perfectly.");
        
        //----------------------------------------------------------------------
        // NATIVE TRANS-BURST TEST 2: DYNAMIC BURST WRITE & READ SWEEPS (128 Bytes)
        //----------------------------------------------------------------------
        $display("\n--- RUNNING TEST 2: DYNAMIC BURST WRITE (128 Bytes / 16 Words) ---");
        
        // Directly fill local storage buffer cells before bursting onto the active bus fabric
        for (idx = 0; idx < 16; idx = idx + 1) begin
            uut.staging_buffer_ram.dual_port_mem[idx[7:0]] = {32'hAA55AA55, idx[31:0]};
        end
        
        // Execute direct AXI Master Write burst to memory offset space 0x00002000
        execute_direct_axi_master_write(32'h00002000, 16'd16);
        #500;

        //----------------------------------------------------------------------
        // NATIVE TRANS-BURST TEST 3: DYNAMIC BURST READBACK INTEGRITY CHECK (64 Bytes)
        //----------------------------------------------------------------------
        $display("\n--- RUNNING TEST 3: DYNAMIC BURST READ (64 Bytes / 8 Words) ---");
        
        // Wipe local buffer spaces to ensure clean validation reads
        for (idx = 0; idx < 16; idx = idx + 1) begin
            uut.staging_buffer_ram.dual_port_mem[idx[7:0]] = 64'h0;
        end

        // Execute direct AXI Master Read loop to verify target stability index arrays
        execute_direct_axi_master_read(32'h00002000, 16'd8);
        
        // Verify block data matches expectations
        for (idx = 0; idx < 8; idx = idx + 1) begin
            verification_read_word = uut.staging_buffer_ram.dual_port_mem[idx[7:0]];
            if (verification_read_word !== {32'hAA55AA55, idx[31:0]}) begin
                $display("[CRITICAL ERROR] Test 3 Data Mismatch at Index %0d! Read: 0x%016X", idx, verification_read_word);
                $finish;
            end
        end
        #100;
        
        $display("\n=========================================================");
        $display("   AXI4 FULL HARDWARE REGRESSION COMPLETED SUCCESSFULLY  ");
        $display("=========================================================\n");
        $finish;
    end

endmodule
`resetall
