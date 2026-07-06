`timescale 1ns/1ps

// =========================================================================
// PROTOCOL COMMAND OPCODES & HANDSHAKE TOKEN MACROS
// =========================================================================
`define CMD_SINGLE_WRITE 8'h31  // ASCII "1"
`define CMD_SINGLE_READ  8'h32  // ASCII "2"
`define CMD_BURST_WRITE  8'h33  // ASCII "3"
`define CMD_BURST_READ   8'h34  // ASCII "4"

`define TOK_ACK_A        8'h61  // ASCII "a" (acknowledge_a_state)
`define TOK_ACK_D        8'h64  // ASCII "d" (acknowledge_d_state)
`define TOK_ACK_L        8'h6C  // ASCII "l" (acknowledge_len_state)
`define TOK_ACK_C        8'h63  // ASCII "c" (internal RAM buffer ready)

module tb_fpga_top_v3;

    // Simulation Stimulus Regs / Wires
    reg  clk_50mhz;
    reg  board_rst;   // Active-High physical board pin
    reg  rx_serial;
    wire tx_serial;

    // Burst loop index counters
    integer w_idx;
    integer b_idx;
    reg [63:0] dynamic_burst_word;

    // Runtime Dynamic Variables to change test parameters on the fly
    reg [15:0] test_write_words; 
    reg [15:0] test_read_words;  

    // 50 MHz Board-Level Clock Oscillator: Period = 20ns (10ns High, 10ns Low)
    always #10.00 clk_50mhz = ~clk_50mhz;

    // Instantiate Unit Under Test (UUT)
    top uut (
        .clk_50mhz(clk_50mhz),
        .board_rst(board_rst),
        .rx_serial(rx_serial),
        .tx_serial(tx_serial)
    );

    // UART Timing Profile Line Target: 1 / 115200 Baud rate = 8680 ns per bit window
    localparam BIT_PERIOD = 8680;

    // =========================================================================
    // TESTBENCH-SIDE PHYSICAL WIRE UART DESERIALIZER (SNIFFER)
    // =========================================================================
    reg [7:0] tb_rx_byte;   // Stores the byte deserialized from the physical wire
    reg       tb_rx_ready;  // Flag pulsing high when a complete byte is captured
    integer   bit_i;

    initial begin
        tb_rx_ready = 1'b0;
        tb_rx_byte  = 8'h00;
    end

    always begin
        // 1. Wait for start bit falling edge on the actual physical output wire
        @(negedge tx_serial); 
        tb_rx_ready = 1'b0;
        
        // 2. Wait 1.5 bit periods to step right into the middle of Data Bit 0
        #(BIT_PERIOD * 1.5);   
        
        // 3. Sample all 8 bits sequentially at the center of each bit window
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
            tb_rx_byte[bit_i] = tx_serial;
            #BIT_PERIOD;
        end
        
        // 4. Arrived at the middle of the stop bit. Pulse the ready flag.
        tb_rx_ready = 1'b1;
        #100; // Hold pulse width briefly for edge-sensitive triggers
        tb_rx_ready = 1'b0;
    end

    // =========================================================================
    // CLOSED-LOOP VERIFICATION & STREAMING TASKS
    // =========================================================================

    // Automated Task to serialize and send data bytes over the RX line
    task send_uart_byte;
        input [7:0] payload_data;
        integer i;
        begin
            rx_serial = 1'b0; // Start bit (driven low)
            #BIT_PERIOD;
            for (i = 0; i < 8; i = i + 1) begin
                rx_serial = payload_data[i]; // Data bits 0 to 7
                #BIT_PERIOD;
            end
            rx_serial = 1'b1; // Stop bit (driven high)
            #BIT_PERIOD;
        end
    endtask

    // Active Closed-Loop Handshake Checker Task (Pure Black-Box Wire Sniffer)
    task verify_fpga_handshake;
        input [7:0] expected_token;
        begin
            $display("[CHECKER] Waiting for physical wire response token... (Expecting ASCII: '%c')", expected_token);
            
            // Wait for our testbench-side deserializer to finish capturing a wire packet
            @(posedge tb_rx_ready); 
            
            if (tb_rx_byte !== expected_token) begin
                $display("\n[CRITICAL FAILURE] Handshake protocol violation on physical wire at %0t ns!", $time);
                $display("Expected Token: '%c' (0x%02X)", expected_token, expected_token);
                $display("Received Token: '%c' (0x%02X)", tb_rx_byte, tb_rx_byte);
                $display("=========================================================");
                $finish; 
            end else begin
                $display("[HANDSHAKE SUCCESS] Verified physical token '%c' at %0t ns.", 
                         expected_token, $time);
            end
        end
    endtask

    // =========================================================================
    // SIMULATION REAL-TIME LOGGING MONITORS
    // =========================================================================
    
    // Monitor PLL lock status
    always @(posedge clk_50mhz) begin
        if (uut.pll_inst.LOCK && uut.sys_rst_n) begin
            if ($time < 500) begin
                $display("[TIME: %0t ns] [SYSTEM MONITOR] PLL Locked. Safe Internal Active-Low System Reset (sys_rst_n) released.", $time);
            end
        end
    end

    // NEW REFACTOR: High-Speed AXI4 System Bus Real-Time Monitor
    always @(posedge uut.clk_80mhz) begin
        if (uut.sys_rst_n) begin
            // Track AXI Write Address Phase
            if (uut.axi_master_mover.m_axi_awvalid && uut.axi_master_mover.m_axi_awready) begin
                $display("[TIME: %0t ns] [AXI4 BUS Master] -> AW WRITE BURST LAUNCH: Addr=0x%08X, Len-Beat Count=%0d", 
                         $time, uut.axi_master_mover.m_axi_awaddr, uut.axi_master_mover.m_axi_awlen + 1);
            end
            // Track AXI Write Data Stream Beats
            if (uut.axi_master_mover.m_axi_wvalid && uut.axi_master_mover.m_axi_wready) begin
                $display("[TIME: %0t ns] [AXI4 BUS Master] -> W-BEAT DATA DATA TRANSFER: Data=0x%016X, Last=%b", 
                         $time, uut.axi_master_mover.m_axi_wdata, uut.axi_master_mover.m_axi_wlast);
            end
            // Track AXI Read Address Phase
            if (uut.axi_master_mover.m_axi_arvalid && uut.axi_master_mover.m_axi_arready) begin
                $display("[TIME: %0t ns] [AXI4 BUS Master] -> AR READ BURST LAUNCH: Addr=0x%08X, Len-Beat Count=%0d", 
                         $time, uut.axi_master_mover.m_axi_araddr, uut.axi_master_mover.m_axi_arlen + 1);
            end
            // Track AXI Read Return Channel Beats
            if (uut.axi_master_mover.m_axi_rvalid && uut.axi_master_mover.m_axi_rready) begin
                $display("[TIME: %0t ns] [AXI4 BUS Slave]  <- R-BEAT DATA RETURN: Data=0x%016X, Last=%b", 
                         $time, uut.axi_master_mover.m_axi_rdata, uut.axi_master_mover.m_axi_rlast);
            end
        end
    end

    // Refactored FSM Controller State Updates (Includes New Co-processing States)
   // Scale the state-change tracking register to 5 bits wide
    reg [4:0] prev_state;
    always @(posedge uut.clk_80mhz) begin
        if (uut.sys_rst_n && (uut.protocol_engine_inst.state != prev_state)) begin
            case (uut.protocol_engine_inst.state)
                4'd0:  $display("  [FSM STATE] -> ST_IDLE");
                4'd1:  $display("  [FSM STATE] -> ST_ACK_A (Handshake Step 1: Opcode ACK, returning 'a')");
                4'd2:  $display("  [FSM STATE] -> ST_RX_ADDR (Handshake Step 2: Grabbing 32-bit address)");
                4'd3:  $display("  [FSM STATE] -> ST_ACK_D (Handshake Step 3: Address locked, returning 'd')");
                4'd11: $display("  [FSM STATE] -> ST_RX_LEN  (Handshake Step 4: Grabbing 16-bit word length)");
                4'd12: $display("  [FSM STATE] -> ST_ACK_L  (Handshake Step 5: Length locked, returning 'l')");
                4'd4:  $display("  [FSM STATE] -> ST_DATA_ROUTE (Routing I/O payload streams)");
                4'd5:  $display("  [FSM STATE] -> ST_WRITE_WORD (Committing data word to RAM array)");
                
                // NEW DIAGNOSTIC STATES DISPLAY
                4'd13: $display("  [FSM STATE] -> ST_LAUNCH_AXI_W (Triggering high-speed RAM -> AXI Memory Flash)");
                4'd14: $display("  [FSM STATE] -> ST_WAIT_AXI_W   (AXI Master writing... stalling UART interface)");
                4'd15: $display("  [FSM STATE] -> ST_LAUNCH_AXI_R (Triggering high-speed AXI Memory -> RAM Fetch)");
                4'd16: $display("  [FSM STATE] -> ST_WAIT_AXI_R   (AXI Master reading... stalling UART interface)");
                
                4'd6:  $display("  [FSM STATE] -> ST_READ_FETCH (Fetching word from internal RAM array)");
                4'd7:  $display("  [FSM STATE] -> ST_READ_WAIT  (RAM pipeline latency sync delay pass)");
                4'd8:  $display("  [FSM STATE] -> ST_TX_STREAM  (Streaming data out over serial link)");
                4'd9:  $display("  [FSM STATE] -> ST_BURST_ACK_C(Burst milestone reached: returning 'c')");
                4'd10: $display("  [FSM STATE] -> ST_BURST_READ (Advancing to next block index)");
            endcase
            prev_state <= uut.protocol_engine_inst.state;
        end
    end

    // =========================================================================
    // MAIN TESTBENCH STIMULUS EXECUTION
    // =========================================================================
    initial begin
        clk_50mhz  = 1'b0;
        board_rst  = 1'b1; // Start in reset (ACTIVE-HIGH)
        rx_serial  = 1'b1; // Line idles high
        prev_state = 4'd0;

        $display("\n=========================================================");
        $display("   STARTING AXI4-FULL CLOSED-LOOP SYSTEM REGRESSION RUNS ");
        $display("=========================================================");
        
        #100;
        $display("[TIME: %0t ns] [SIM STATUS] De-asserting active-high board reset pin...", $time);
        board_rst = 1'b0; // Release system reset state
        
        // Wait until your custom PLL module hits frequency stabilization lock
        @(posedge uut.pll_inst.LOCK);
        #50;

        // ---------------------------------------------------------------------
        // RUN TEST 1: SINGLE WRITE (Baseline Check)
        // ---------------------------------------------------------------------
        $display("\n[STAGE 1] Testing Single Word Write: Addr 0x00000010 -> Data 0x0123456789ABCDEF\n");
        send_uart_byte(`CMD_SINGLE_WRITE);
        verify_fpga_handshake(`TOK_ACK_A);

        send_uart_byte(8'h00); send_uart_byte(8'h00); send_uart_byte(8'h00); send_uart_byte(8'h10);
        verify_fpga_handshake(`TOK_ACK_D);

        send_uart_byte(8'h01); send_uart_byte(8'h23); send_uart_byte(8'h45); send_uart_byte(8'h67);
        send_uart_byte(8'h89); send_uart_byte(8'hAB); send_uart_byte(8'hCD); send_uart_byte(8'hEF);
        #(BIT_PERIOD * 2);

        // ---------------------------------------------------------------------
        // RUN TEST 2: SINGLE READ (Baseline Check)
        // ---------------------------------------------------------------------
        $display("\n[STAGE 2] Testing Single Word Read back from target address 0x00000010\n");
        send_uart_byte(`CMD_SINGLE_READ);
        verify_fpga_handshake(`TOK_ACK_A);

        send_uart_byte(8'h00); send_uart_byte(8'h00); send_uart_byte(8'h00); send_uart_byte(8'h10);
        verify_fpga_handshake(`TOK_ACK_D);

        $display("[CHECKER] Capturing 8-byte response payload data stream from physical wire...");
        for (w_idx = 0; w_idx < 8; w_idx = w_idx + 1) begin
            @(posedge tb_rx_ready); 
            $display("  Captured Single Byte %0d/8: 0x%02X", w_idx + 1, tb_rx_byte);
        end

        // ---------------------------------------------------------------------
        // RUN TEST 3: DYNAMIC BURST WRITE (128 Bytes -> Staging Buffer -> AXI RAM)
        // ---------------------------------------------------------------------
        test_write_words = 16'd16; // 16 words * 8 bytes/word = 128 Bytes total
        $display("\n[STAGE 3] Testing Dynamic Burst Write: Size = 128 Bytes (%0d Words)\n", test_write_words);
        
        send_uart_byte(`CMD_BURST_WRITE);
        verify_fpga_handshake(`TOK_ACK_A);

        // Base Target Address on AXI System Memory: 0x00002000
        send_uart_byte(8'h00); send_uart_byte(8'h00); send_uart_byte(8'h20); send_uart_byte(8'h00);
        verify_fpga_handshake(`TOK_ACK_D);

        // Send 16-bit payload length
        send_uart_byte(test_write_words[15:8]); 
        send_uart_byte(test_write_words[7:0]);  
        verify_fpga_handshake(`TOK_ACK_L);      

        $display("[CHECKER] Handshake complete. Sending UART bytes to Staging RAM...");
        for (w_idx = 0; w_idx < test_write_words; w_idx = w_idx + 1) begin
            dynamic_burst_word = {32'hAA55AA55, w_idx[31:0]};
            for (b_idx = 7; b_idx >= 0; b_idx = b_idx - 1) begin
                send_uart_byte(dynamic_burst_word[(b_idx * 8) +: 8]);
            end
        end
        
        // Wait briefly for high-speed AXI burst flash processing loops to settle out
        #2000;

        // ---------------------------------------------------------------------
        // RUN TEST 4: DYNAMIC BURST READ (64 Bytes -> AXI RAM -> Staging Buffer -> UART)
        // ---------------------------------------------------------------------
        test_read_words = 16'd8; // 8 words * 8 bytes/word = 64 Bytes total
        $display("\n[STAGE 4] Testing Dynamic Burst Read: Size = 64 Bytes (%0d Words)\n", test_read_words);
        
        send_uart_byte(`CMD_BURST_READ);
        verify_fpga_handshake(`TOK_ACK_A);

        // Base Target Address on AXI System Memory: 0x00002000
        send_uart_byte(8'h00); send_uart_byte(8'h00); send_uart_byte(8'h20); send_uart_byte(8'h00);
        verify_fpga_handshake(`TOK_ACK_D);

        // Send 16-bit length
        send_uart_byte(test_read_words[15:8]); 
        send_uart_byte(test_read_words[7:0]);  
        verify_fpga_handshake(`TOK_ACK_L);

        // Expect internal memory compilation tracking completion flag "c"
        verify_fpga_handshake(`TOK_ACK_C);

        $display("[CHECKER] Token 'c' confirmed. Sniffing exactly %0d bytes from serial wire...", (test_read_words * 8));
        for (w_idx = 0; w_idx < (test_read_words * 8); w_idx = w_idx + 1) begin
            @(posedge tb_rx_ready);
            if (w_idx % 8 == 0) begin
                $display("  Streaming payload data block line offset byte: %0d/64", w_idx);
            end
        end
        
        $display("\n=========================================================");
        $display("   AXI4 FULL HARDWARE REGRESSION COMPLETED SUCCESSFULLY  ");
        $display("=========================================================\n");
        $finish;
    end

    // Keeps the optimization warning flags happy
    wire u_ready_check = uut.receiver_inst.rx_ready;

endmodule
