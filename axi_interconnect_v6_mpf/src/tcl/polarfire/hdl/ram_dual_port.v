//------------------------------------------------------------------------------
// Company/Institution:  Tecnomic Components
// Engineer:             Jijeesh M
// 
// Create Date:          2026
// Module Name:          ram_2k_true_dual_port
// Project Name:         RTG4/SmartFusion2 Serial to AXI Memory Staging System
// Target Devices:       Microchip SmartFusion2 / RTG4 Fabric Core Architecture
// Tool Versions:        Libero SoC Design Suite v12.0+
//
// Description:
//   A synthesizable, true dual-port block RAM staging buffer. Configured with a 
//   depth of 256 addresses and a width of 64 bits per row, providing exactly 
//   2 Kilobytes (16,384 bits) of local block storage space.
//
//   This memory serves as the critical timing boundary interface link connecting
//   the slow serial execution domain and the high-speed system bus.
//
//   Port Assignment Architecture:
//     - Port A: Connected strictly to the system_control_fsm module. It collects
//               slow asynchronous incoming bytes from the UART lines or streams
//               cached data back out over the serial wire line.
//     - Port B: Connected strictly to the high-speed axi4_master_data_mover
//               engine. It drives full 64-bit parallel data words onto the AXI
//               bus layout fabric at full clock velocity.
//
//   Synthesis/Hardware Notes:
//     - The (* RAM_STYLE="BLOCK" *) synthesis attribute forces Libero Synplify
//       to map this logic directly into physical hardware Large SRAM (LSRAM) 
//       blocks inside the SmartFusion2/RTG4 die instead of wasting fabric LUTs.
//     - This memory utilizes synchronous "Read-First" / "Old-Data" behavior. If
//       a write command is issued, the read output (rdata) latches the data that
//       was present *prior* to the write edge, avoiding internal bus racing.
//
// Dependencies:
//   None (Primitive block level memory array layer)
//
// Revision History:
//   v1.0 - Baseline dual-port execution layer.
//   v2.0 - Added Synplify block layout compiler tags and strict net definitions.
//------------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module ram_dual_port #(
    parameter integer DATA_WIDTH = 64,
    parameter integer ADDR_WIDTH = 16  // 2^16 = 65,536 words x 64-bit = 512 KB
)(
    // Unified Core Clock Input
    input  wire                  clk,

    // Port A Bus Interface (Testbench / Control FSM Domain)
    input  wire                  we_a,
    input  wire [ADDR_WIDTH-1:0] addr_a,
    input  wire [DATA_WIDTH-1:0] wdata_a,
    output reg  [DATA_WIDTH-1:0] rdata_a,

    // Port B Bus Interface (AXI4 Master Engine Domain)
    input  wire                  we_b,
    input  wire [ADDR_WIDTH-1:0] addr_b,
    input  wire [DATA_WIDTH-1:0] wdata_b,
    output reg  [DATA_WIDTH-1:0] rdata_b
);

    localparam integer DEPTH = (1 << ADDR_WIDTH);

    // Enforces mapping to embedded hardware LSRAM blocks
    (* ramstyle = "block" *) reg [DATA_WIDTH-1:0] dual_port_mem [0:DEPTH-1];

    // Port A Synchronous Read-First Logic
    always @(posedge clk) begin
        if (we_a) begin
            dual_port_mem[addr_a] <= wdata_a;
        end
        rdata_a <= dual_port_mem[addr_a];
    end

    // Port B Synchronous Read-First Logic
    always @(posedge clk) begin
        if (we_b) begin
            dual_port_mem[addr_b] <= wdata_b;
        end
        rdata_b <= dual_port_mem[addr_b];
    end

    // Zero-initialize memory for clean simulation startup
   integer i;
    initial begin
        // synthesis loop_limit 70000
        for (i = 0; i < DEPTH; i = i + 1) begin
            dual_port_mem[i] = {DATA_WIDTH{1'b0}};
        end
    end

endmodule
`resetall