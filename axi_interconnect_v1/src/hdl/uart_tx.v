//------------------------------------------------------------------------------
// Company/Institution:  Tecnomic Components
// Engineer:             Jijeesh M// 
// Create Date:          2026
// Module Name:          uart_tx
// Project Name:         RTG4/SmartFusion2 Serial to AXI Memory Staging System
// Target Devices:       Microchip SmartFusion2 / RTG4 Fabric Core Architecture
// Tool Versions:        Libero SoC Design Suite v12.0+
//
// Description:
//   A parameterizable, robust UART Serial Transmitter module. This hardware 
//   component transforms parallel 8-bit byte packets into an asynchronous,
//   timed bitstream format over a single physical wire line.
//
//   Transmission Protocol Layout:
//     - Line Idle Condition: Continually driven High (1'b1).
//     - Start Bit: Driven Low (1'b0) for exactly 1 full bit period window.
//     - Data Payload: 8 bits serialized sequentially, Least-Significant Bit (LSB) first.
//     - Stop Bit: Driven High (1'b1) for exactly 1 full bit period window.
//
//   Baud Rate Generation:
//     - Uses a high-resolution clock division counter (`clk_counter`) calculated
//       directly from the input system clock frequency parameter. This enables
//       uninterrupted back-to-back word transfers without introducing clock drift
//       or timing akumulations.
//
// Dependencies:
//   None (Self-contained asynchronous interface component)
//
// Revision History:
//   v1.0 - Baseline 115200 Baud serial output state machine.
//   v2.0 - Added strict net definitions and timing-aligned inline annotations.
//------------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module uart_tx #
(
    //--------------------------------------------------------------------------
    // Parameterized Clock and Baud Rate Configurations
    //--------------------------------------------------------------------------
    parameter CLK_FREQ  = 80000000,   // Main global logic domain clock speed (80 MHz)
    parameter BAUD_RATE = 115200      // Target serialization transmission line speed
)
(
    //--------------------------------------------------------------------------
    // Core Clock, Reset, and Control I/O Ports
    //--------------------------------------------------------------------------
    input  wire        clk,           // Main global fabric execution clock (80 MHz)
    input  wire        rst_n,         // Synchronized active-low system reset
    input  wire        tx_start,      // 1-cycle active-high pulse to lock payload and launch TX
    input  wire [7:0]  tx_byte,       // Parallel 8-bit target data byte package to serialize
    output reg         tx_serial,     // Exported physical serial stream output pad pin wire
    output reg         tx_busy        // High continuously throughout active bitstream serialization
);

    //--------------------------------------------------------------------------
    // Mathematical Clock Division Local Constants
    //--------------------------------------------------------------------------
    // Total system clock cycles required to span a single bit width period window
    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;

    // Finite State Machine State Encodings
    localparam [1:0] IDLE  = 2'b00,
                     START = 2'b01,
                     DATA  = 2'b10,
                     STOP  = 2'b11;

    // Internal Signal Allocation Registers
    reg [1:0]  state;                // Core serialization tracking pipeline state register
    reg [15:0] clk_counter;          // Generates the transmission bit period time windows
    reg [2:0]  bit_index;            // Tracking pointer referencing the current output payload bit
    reg [7:0]  tx_reg;               // Internal holding cache register storing the active word

    //--------------------------------------------------------------------------
    // Main Core Transmitter Finite State Machine (FSM) Processes
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            clk_counter <= 16'd0;
            bit_index   <= 3'd0;
            tx_reg      <= 8'h00;
            tx_serial   <= 1'b1;     // Communication lines always idle high
            tx_busy     <= 1'b0;
        end else begin
            case (state)
                // Wait for a transmit trigger command pulse from the protocol FSM core
                IDLE: begin
                    tx_serial   <= 1'b1; // Hold line safely at high baseline idle
                    tx_busy     <= 1'b0; // Indicate core lines are clear for new input entries
                    clk_counter <= 16'd0;
                    
                    if (tx_start) begin
                        tx_reg    <= tx_byte; // Cache target parallel word into internal shift buffer
                        tx_busy   <= 1'b1;    // Interlock busy lines immediately to stall upstream loads
                        state     <= START;
                    end
                end

                // Assert the low framing Start Bit to alert the receiver node
                START: begin
                    tx_serial <= 1'b0; // Drive serial pad wire low for 1 full bit period
                    
                    if (clk_counter == BIT_PERIOD - 1) begin
                        clk_counter <= 16'd0;
                        bit_index   <= 3'd0;
                        state       <= DATA; // Start bit window completed, branch to payload stream
                    end else begin
                        clk_counter <= clk_counter + 1'b1;
                    end
                end

                // Serialize the cached 8 data bits onto the wire (LSB First)
                DATA: begin
                    tx_serial <= tx_reg[bit_index]; // Extrude the target indexed bit onto the output pad
                    
                    if (clk_counter == BIT_PERIOD - 1) begin
                        clk_counter <= 16'd0;
                        
                        if (bit_index == 3'd7) begin
                            state <= STOP; // All 8 data bits successfully pushed onto line buffers
                        end else begin
                            bit_index <= bit_index + 1'b1; // Increment pointer to reference next upper bit
                        end
                    end else begin
                        clk_counter <= clk_counter + 1'b1;
                    end
                end

                // Assert the high framing Stop Bit to close the transaction envelope
                STOP: begin
                    tx_serial <= 1'b1; // Drive line back high to complete framing bounds rules
                    
                    if (clk_counter == BIT_PERIOD - 1) begin
                        clk_counter <= 16'd0;
                        state       <= IDLE; // Envelope closed cleanly. Return to poll for next word.
                    end else begin
                        clk_counter <= clk_counter + 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
`resetall