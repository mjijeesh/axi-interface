//------------------------------------------------------------------------------
// Company/Institution:  Tecnomic Components
// Engineer:             Jijeesh M
// 
// Create Date:          2026
// Module Name:          uart_rx
// Project Name:         RTG4/SmartFusion2 Serial to AXI Memory Staging System
// Target Devices:       Microchip SmartFusion2 / RTG4 Fabric Core Architecture
// Tool Versions:        Libero SoC Design Suite v12.0+
//
// Description:
//   A parameterizable, high-reliability UART Receiver core. This module captures
//   asynchronous serial data by oversampling the input line at 16x the target 
//   Baud Rate. 
//
//   Key Features:
//     - Metastability Mitigation: Passes the raw rx_serial input line through 
//       a dual-stage flip-flop register synchronizer pipeline.
//     - Noise/Glitch Rejection: Evaluates the start bit at its exact midpoint
//       (sample_counter == 7) to filter out spurious line glitches.
//     - Precise Mid-bit Sampling: Samples data and stop bits at their mathematical
//       midpoints (sample_counter == 15) to maximize setup/hold margins and
//       tolerate clock skew or line jitter.
//
// Dependencies:
//   None (Self-contained asynchronous interface component)
//
// Revision History:
//   v1.0 - Baseline 115200 Baud oversampled receiver loop.
//   v2.0 - Added strict net definitions and timing-aligned inline annotations.
//------------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module uart_rx #
(
    //--------------------------------------------------------------------------
    // Parameterized Physical Sizing Configurations
    //--------------------------------------------------------------------------
    parameter CLK_FREQ   = 80000000, // Main global fabric clock frequency (80 MHz)
    parameter BAUD_RATE  = 115200,   // Target serialization line speed (Bits/sec)
    parameter OVERSAMPLE = 16        // Oversampling resolution factor (Ticks per bit)
)
(
    //--------------------------------------------------------------------------
    // Global Clock, Reset, and Physical Interface Ports
    //--------------------------------------------------------------------------
    input  wire        clk,          // Unified processing system clock domain
    input  wire        rst_n,        // Synchronized active-low system reset
    input  wire        rx_serial,    // Physical asynchronous serial input line pad pin
    output reg         rx_ready,     // Active-high pulse for 1 cycle when a byte is ready
    output reg  [7:0]  rx_data       // 8-bit parallel byte latched from shift registers
);

    //--------------------------------------------------------------------------
    // Mathematical Clock Division Constants
    //--------------------------------------------------------------------------
    // Total clock cycles contained within an individual oversampling micro-tick
    localparam TICK_COUNT = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);
    
    // Finite State Machine State Encodings
    localparam [1:0] IDLE  = 2'b00,
                     START = 2'b01,
                     DATA  = 2'b10,
                     STOP  = 2'b11;

    // Internal Signal Allocation Registers
    reg [1:0]  state;                // Core receiver tracking pipeline state register
    reg [15:0] tick_counter;         // Clock divider register generating oversample ticks
    reg [3:0]  sample_counter;       // Accumulates micro-ticks within a single bit window
    reg [2:0]  bit_index;            // Tracking pointer referencing the current data bit
    reg [7:0]  shift_reg;            // Holding register assembling incoming data bits

    //--------------------------------------------------------------------------
    // Dual-Stage Anti-Metastability Synchronization Pipeline
    //--------------------------------------------------------------------------
    // Isolates the raw asynchronous input line from the internal clock domain
    reg rx_sync_0;
    reg rx_sync_1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync_0 <= 1'b1; // Line idles high
            rx_sync_1 <= 1'b1;
        end else begin
            rx_sync_0 <= rx_serial;
            rx_sync_1 <= rx_sync_0; // Fully synchronized signal used by FSM logic
        end
    end

    //--------------------------------------------------------------------------
    // Oversampling Micro-Tick Pulse Generator Block
    //--------------------------------------------------------------------------
    wire tick = (tick_counter == TICK_COUNT - 16'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_counter <= 16'd0;
        end else if (tick) begin
            tick_counter <= 16'd0;
        end else begin
            tick_counter <= tick_counter + 16'b1;
        end
    end

    //--------------------------------------------------------------------------
    // Main Core Receiver Finite State Machine (FSM) Processes
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            sample_counter <= 4'd0;
            bit_index      <= 3'd0;
            shift_reg      <= 8'h00;
            rx_ready       <= 1'b0;
            rx_data        <= 8'h00;
        end else begin
            rx_ready <= 1'b0; // Default pulse low to enforce single-cycle duration
            
            // FSM advances strictly on synchronized micro-tick boundaries
            if (tick) begin
                case (state)
                    // Wait for a falling edge on the synchronized RX line
                    IDLE: begin
                        if (rx_sync_1 == 1'b0) begin 
                            state          <= START;
                            sample_counter <= 4'd0;
                        end
                    end
                    
                    // Validate Start Bit and align center-of-bit sampling point
                    START: begin
                        if (sample_counter == 4'd7) begin 
                            // Sample at the exact midpoint of the start bit window
                            if (rx_sync_1 == 1'b0) begin
                                sample_counter <= 4'd0; // Reset counter for data bit frames
                                bit_index      <= 3'd0;
                                state          <= DATA;
                            end else begin
                                state <= IDLE; // False start glitch rejected; return to IDLE
                            end
                        end else begin
                            sample_counter <= sample_counter + 1'b1;
                        end
                    end
                    
                    // Sample data bits at their midpoints and shift into storage
                    DATA: begin
                        if (sample_counter == 4'd15) begin 
                            // Arrived at the exact midpoint of the data bit window (16 ticks per bit)
                            sample_counter       <= 4'd0;
                            shift_reg[bit_index] <= rx_sync_1; // Capture data bit (LSB First)
                            
                            if (bit_index == 3'd7) begin
                                state <= STOP; // All 8 data bits collected successfully
                            end else begin
                                bit_index <= bit_index + 1'b1;
                            end
                        end else begin
                            sample_counter <= sample_counter + 1'b1;
                        end
                    end
                    
                    // Verify the Stop Bit validation frame and latch parallel output byte
                    STOP: begin
                        if (sample_counter == 4'd15) begin 
                            // Arrived at the midpoint of the stop bit window
                            if (rx_sync_1 == 1'b1) begin // Check for a valid stop bit (high)
                                rx_data  <= shift_reg;   // Latch fully assembled byte to output port
                                rx_ready <= 1'b1;        // Pulse output handshake high for 1 cycle
                            end
                            state <= IDLE; // Return to wait for the next command frame
                        end else begin
                            sample_counter <= sample_counter + 1'b1;
                        end
                    end
                endcase
            end
        end
    end

endmodule
`resetall