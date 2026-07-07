//------------------------------------------------------------------------------
// Company/Institution:  Tecnomic Components
// Engineer:             Jijeesh M
// 
// Create Date:          2026
// Module Name:          system_control_fsm
// Project Name:         RTG4/SmartFusion2 Serial to AXI Memory Staging System
// Target Devices:       Microchip SmartFusion2 / RTG4 Fabric Core Architecture
// Tool Versions:        Libero SoC Design Suite v12.0+
//
// Description:
//   The central command orchestrator FSM layer for the memory subsystem. It 
//   bridges the slow asynchronous UART clock domain with the synchronous 
//   high-speed AXI4 Master infrastructure via an asymmetric staging RAM.
//
//   Handshake Protocol Workflow Layout:
//     1. [Host] Opcode Byte  ---> [FSM] -> Returns Token 'a' (Opcode Accepted)
//     2. [Host] 32-bit Addr  ---> [FSM] -> Returns Token 'd' (Address Latched)
//     3. [Host] 16-bit Length---> [FSM] -> Returns Token 'l' (Length Latched) *Burst Only
//     4. [Host] Data Stream  <===> [FSM] -> Core Data Phase execution
//
//   Operational Redirection Features:
//     - Single operations are intercepted during the address validation loop
//       and handled as an optimized, single-beat (1-word) AXI burst. This 
//       ensures the high-speed AXI Master engine asserts clean waveforms on 
//       every transaction type.
//
// Dependencies:
//   - uart_rx / uart_tx (Serial interface layer)
//   - axi4_master_data_mover (High-speed co-processor trigger network)
//
// Revision History:
//   v1.0 - Baseline 2KB fixed-size state tracker.
//   v2.0 - Added dynamic 16-bit word length parameters extraction.
//   v3.0 - Patched VERI-1208 truncation warnings by scaling state bus to 5 bits.
//   v3.1 - Configured single transactions to execute as 1-beat AXI cycles.
//------------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module system_control_fsm (
    //--------------------------------------------------------------------------
    // Clock and System Reset Inputs
    //--------------------------------------------------------------------------
    input  wire         clk,                 // Global fabric system clock domain (80 MHz)
    input  wire         rst_n,               // Synchronized active-low logic domain reset
    
    //--------------------------------------------------------------------------
    // Hardware UART Core Controller Interface Ports
    //--------------------------------------------------------------------------
    input  wire         rx_ready,            // Pulses high for 1 clock cycle when a new byte arrives
    input  wire [7:0]   rx_byte,             // Parallel 8-bit data character from the UART receiver
    input  wire         tx_busy,             // Asserted high continuously while UART TX is serializing
    output reg          tx_start,            // Pulse high for 1 clock cycle to launch UART transmission
    output reg  [7:0]   tx_byte,             // Parallel 8-bit data payload directed down to UART transmitter
    
    //--------------------------------------------------------------------------
    // Staging RAM Interface Channel Ports (Dedicated to Port A)
    //--------------------------------------------------------------------------
    output reg          ram_we,              // Port A active-high write enable strobe line
    output reg  [7:0]   ram_waddr,           // Port A 8-bit memory target write address pointer
    output reg  [63:0]  ram_wdata,           // Port A 64-bit parallel incoming payload data lane
    output reg  [7:0]   ram_raddr,           // Port A 8-bit memory target read address pointer
    input  wire [63:0]  ram_rdata,           // Port A 64-bit parallel outgoing cached data lane

    //--------------------------------------------------------------------------
    // Co-Processing Coordination Hooks Routed to AXI4 Master Engine
    //--------------------------------------------------------------------------
    output reg          axi_write_trigger,   // Pulse high for 1 cycle to launch AXI write sequence
    output reg          axi_read_trigger,    // Pulse high for 1 cycle to launch AXI read sequence
    output reg  [31:0]  axi_target_address,  // Target memory destination address mapped on AXI bus
    output reg  [15:0]  axi_length_words,    // Total count of 64-bit data beats requested
    input  wire         axi_engine_busy,     // High continuously while AXI bus transactions are live
    input  wire         axi_engine_done      // Pulses high for 1 cycle upon AXI transaction complete
);

    //--------------------------------------------------------------------------
    // Finite State Machine Parameter Declarations
    // FIXED: Register scaled to 5 bits wide [4:0] to fit state 16 (VERI-1208)
    //--------------------------------------------------------------------------
    reg [4:0] state;

    localparam [4:0] ST_IDLE          = 5'd0,
                     ST_ACK_A         = 5'd1,
                     ST_RX_ADDR       = 5'd2,
                     ST_ACK_D         = 5'd3,
                     ST_RX_LEN        = 5'd11,
                     ST_ACK_L         = 5'd12,
                     ST_DATA_ROUTE    = 5'd4,
                     ST_WRITE_WORD    = 5'd5,
                     
                     // Master Mover Co-Processing Handshaking States
                     ST_LAUNCH_AXI_W  = 5'd13, 
                     m_STATE_WAIT_W   = 5'd14, // Aligned tracking network node
                     ST_LAUNCH_AXI_R  = 5'd15,
                     m_STATE_WAIT_R   = 5'd16, // Aligned tracking network node
                     
                     // Serial Wire Line Outbound Output Streaming States
                     ST_READ_FETCH    = 5'd6,
                     ST_READ_WAIT     = 5'd7,
                     ST_TX_STREAM     = 5'd8,
                     ST_BURST_ACK_C   = 5'd9,
                     ST_BURST_READ    = 5'd10;

    //--------------------------------------------------------------------------
    // Internal Setup Tracking Storage Cache Registers
    //--------------------------------------------------------------------------
    reg [7:0]  opcode;                       // Holds the active command character ('1' through '4')
    reg [31:0] addr_buffer;                  // Assembles the 32-bit big-endian target address
    reg [63:0] data_buffer;                  // Assembles incoming bytes into a full 64-bit word
    reg [15:0] len_buffer;                   // Captures the requested 16-bit word allocation limit
    reg [3:0]  byte_counter;                 // Generic loop index for grouping incoming byte packets
    reg [15:0] burst_counter;                // Word index tracking the multi-beat burst progression

    // Automatically maps the 32-bit bus address down to native 64-bit staging memory indexes
    wire [7:0] aligned_ram_idx = addr_buffer[10:3]; 

    //--------------------------------------------------------------------------
    // Core Synchronous Process Logic Block
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            opcode             <= 8'h0;
            addr_buffer        <= 32'h0;
            data_buffer        <= 64'h0;
            len_buffer         <= 16'h0;
            byte_counter       <= 4'd0;
            burst_counter      <= 16'd0;
            tx_start           <= 1'b0;
            tx_byte            <= 8'h0;
            ram_we             <= 1'b0;
            ram_waddr          <= 8'h0;
            ram_wdata          <= 64'h0;
            ram_raddr          <= 8'h0;
            axi_write_trigger  <= 1'b0;
            axi_read_trigger   <= 1'b0;
            axi_target_address <= 32'h0;
            axi_length_words   <= 16'h0;
        end else begin
            // Enforce default outputs low to guarantee clean single-clock pulse generation
            tx_start          <= 1'b0;
            ram_we            <= 1'b0;
            axi_write_trigger <= 1'b0;
            axi_read_trigger  <= 1'b0;

            case (state)
                // Wait for an incoming command instruction character from the host interface
                ST_IDLE: begin
                    byte_counter  <= 4'd0;
                    burst_counter <= 16'd0;
                    if (rx_ready) begin
                        if (rx_byte == "1" || rx_byte == "2" || rx_byte == "3" || rx_byte == "4") begin
                            opcode <= rx_byte;
                            state  <= ST_ACK_A;
                        end
                    end
                end

                // Handshake Phase 1: Send Opcode Ack token 'a' (0x61) back to host
                ST_ACK_A: begin
                    if (!tx_busy && !tx_start) begin
                        tx_byte  <= "a"; 
                        tx_start <= 1'b1;
                        state    <= ST_RX_ADDR;
                    end
                end

                // Shift in all 4 big-endian bytes of the 32-bit transaction address
                ST_RX_ADDR: begin
                    if (rx_ready) begin
                        addr_buffer <= {addr_buffer[23:0], rx_byte};
                        if (byte_counter == 3) begin
                            byte_counter <= 4'd0;
                            state        <= ST_ACK_D;
                        end else begin
                            byte_counter <= byte_counter + 1'b1;
                        end
                    end
                end

                // Handshake Phase 2: Send Address Ack token 'd' (0x64) back to host
                ST_ACK_D: begin
                    if (!tx_busy && !tx_start) begin
                        tx_byte  <= "d";
                        tx_start <= 1'b1;
                        
                        if (opcode == "3" || opcode == "4") begin
                            // Burst commands advance to the length-collection phase
                            state        <= ST_RX_LEN;
                            byte_counter <= 4'd0;
                            len_buffer   <= 16'h0;
                        end else begin
                            // REFACTOR: Intercept single operations and force them into a 1-word AXI transaction
                            len_buffer   <= 16'd1; 
                            byte_counter <= 4'd0;
                            if (opcode == "2") begin
                                state <= ST_LAUNCH_AXI_R; // Single Read: Immediately fetch the target word from memory
                            end else begin
                                state <= ST_DATA_ROUTE;   // Single Write: Gather the 8 data bytes first
                            end
                        end
                    end
                end

                // Shift in both big-endian bytes of the 16-bit transaction length count
                ST_RX_LEN: begin
                    if (rx_ready) begin
                        len_buffer <= {len_buffer[7:0], rx_byte};
                        if (byte_counter == 1) begin
                            byte_counter <= 4'd0;
                            state        <= ST_ACK_L;
                        end else begin
                            byte_counter <= byte_counter + 1'b1;
                        end
                    end
                end

                // Handshake Phase 3: Send Length Ack token 'l' (0x6C) back to host
                ST_ACK_L: begin
                    if (!tx_busy && !tx_start) begin
                        tx_byte  <= "l";
                        tx_start <= 1'b1;
                        if (opcode == "4") begin
                            state <= ST_LAUNCH_AXI_R; // Burst Read: Kick off high-speed AXI retrieval loop
                        end else begin
                            state <= ST_DATA_ROUTE;   // Burst Write: Proceed to collect serial bytes
                        end
                    end
                end

                // Inbound Payload Collection Data Phase
                ST_DATA_ROUTE: begin
                    if (opcode == "1" || opcode == "3") begin // Write Operations
                        if (rx_ready) begin
                            data_buffer  <= {data_buffer[55:0], rx_byte};
                            if (byte_counter == 7) begin
                                byte_counter <= 4'd0;
                                state        <= ST_WRITE_WORD;
                            end else begin
                                byte_counter <= byte_counter + 1'b1;
                            end
                        end
                    end else if (opcode == "2") begin // Single Read Operation
                        ram_raddr <= 8'd0; // Staged single responses are always locked down at index 0
                        state     <= ST_READ_FETCH;
                    end
                end

                // Commit the compiled 64-bit data word into the staging buffer
                ST_WRITE_WORD: begin
                    ram_we    <= 1'b1;
                    // Burst writes scale dynamically; single writes dump exclusively into slot 0
                    ram_waddr <= (opcode == "3") ? burst_counter[7:0] : 8'd0;
                    ram_wdata <= data_buffer;
                    
                    if (opcode == "3") begin // Burst mode check
                        if (burst_counter == len_buffer - 1) begin
                            state <= ST_LAUNCH_AXI_W; // Buffer full. Fire high-speed data mover copy cycle!
                        end else begin
                            burst_counter <= burst_counter + 1'b1;
                            byte_counter  <= 4'd0; 
                            state         <= ST_DATA_ROUTE;
                        end
                    end else begin
                        // REFACTOR: Route single writes out to external AXI memory space
                        state <= ST_LAUNCH_AXI_W;
                    end
                end

                //--------------------------------------------------------------
                // HIGH-SPEED AXI CO-PROCESSING INTERFACE STATES
                //--------------------------------------------------------------
                
                // Pulse the control lines to launch the AXI Master Mover engine
                ST_LAUNCH_AXI_W: begin
                    axi_target_address <= addr_buffer;
                    axi_length_words   <= len_buffer; // 1 for single operations, N for burst operations
                    axi_write_trigger  <= 1'b1;       // Handshake output strobe high
                    state              <= m_STATE_WAIT_W;
                end

                // Hold the UART FSM lines completely still while AXI bursts fly over the system bus
                m_STATE_WAIT_W: begin
                    if (axi_engine_done) begin
                        state <= ST_IDLE; // AXI transfer safely written to physical memory lines
                    end
                end

                // Pulse the read control lines to launch the AXI Master Mover engine
                ST_LAUNCH_AXI_R: begin
                    axi_target_address <= addr_buffer;
                    axi_length_words   <= len_buffer; 
                    axi_read_trigger   <= 1'b1;       // Handshake output strobe high
                    state              <= m_STATE_WAIT_R;
                end

                // Wait for the AXI Master Mover to fill the staging buffer area
                m_STATE_WAIT_R: begin
                    if (axi_engine_done) begin
                        burst_counter <= 16'd0;
                        if (opcode == "2") begin
                            state <= ST_DATA_ROUTE;  // Single Read: Proceed directly to parse the staging buffer word
                        end else begin
                            state <= ST_BURST_ACK_C; // Burst Read: Send data-ready buffer verification flag 'c'
                        end
                    end
                end

                //--------------------------------------------------------------
                // SERIAL WIRE OUTPUT TRANSMISSION CHANNEL DRIVERS
                //--------------------------------------------------------------
                ST_READ_FETCH: begin
                    state <= ST_READ_WAIT; 
                end

                ST_READ_WAIT: begin
                    data_buffer <= ram_rdata;
                    state       <= ST_TX_STREAM;
                end

                // Shift the local 64-bit payload data out over the UART TX wire byte by byte
                ST_TX_STREAM: begin
                    if (!tx_busy && !tx_start) begin
                        tx_byte      <= data_buffer[63:56];
                        data_buffer  <= {data_buffer[55:0], 8'h00};
                        tx_start     <= 1'b1;
                        
                        if (byte_counter == 7) begin
                            byte_counter <= 4'd0;
                            if (opcode == "4") begin // Burst mode verification loop
                                if (burst_counter == len_buffer - 1) begin
                                    state <= ST_IDLE; // Complete block downloaded successfully
                                end else begin
                                    burst_counter <= burst_counter + 1'b1;
                                    ram_raddr     <= burst_counter[7:0] + 1'b1; // Step up Port A address index lookahead
                                    state         <= ST_BURST_READ;
                                end
                            end else begin
                                state <= ST_IDLE; // Single read operation complete
                            end
                        end else begin
                            byte_counter <= byte_counter + 1'b1;
                        end
                    end
                end

                // Handshake Phase 4: Alert host utility that AXI cache is ready with token 'c' (0x63)
                ST_BURST_ACK_C: begin
                    if (!tx_busy && !tx_start) begin
                        tx_byte   <= "c";
                        tx_start  <= 1'b1;
                        ram_raddr <= 8'd0; // Reset lookahead reader back to index 0
                        state     <= ST_READ_FETCH;
                    end
                end

                ST_BURST_READ: begin
                    state <= ST_READ_WAIT; 
                end
            endcase
        end
    end
endmodule
`resetall