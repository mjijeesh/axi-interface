//------------------------------------------------------------------------------
// Module: fifo_data_generator
// Description:
//   Synthesizable Continuous 32-Bit Data Generator with Configurable Inter-Burst
//   Delays and FIFO Backpressure Handling.
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module fifo_data_generator (
    input  wire        wclk,
    input  wire        wrst_n,

    // Generator Control Inputs
    input  wire        gen_en,           // 1 = Run continuous data generation
    input  wire        gen_reset,        // Active-high reset of sample counter
    input  wire [15:0] pattern_tag,      // Upper 16-bit tag embedded in each 32-bit word
    input  wire [15:0] burst_len,        // 32-bit words per burst before inserting delay (0 = no delay)
    input  wire [15:0] delay_cycles,     // Clock cycles to pause between bursts (0 = back-to-back)
    input  wire        random_delay,     // 1 = Modulate delay_cycles using 16-bit LFSR

    // Status Outputs
    output reg  [31:0] words_generated,  // Total 32-bit words accepted by FIFO

    // COREFIFO_C0 32-bit Write Port
    output wire [31:0] fifo_wdata,
    output wire        fifo_we,
    input  wire        fifo_full
);

    reg [15:0] sample_idx;
    reg [15:0] burst_cnt;
    reg [15:0] delay_rem;
    reg        in_delay;
    reg [15:0] lfsr;

    // 16-bit Galois LFSR for pseudo-random delay variation
    wire [15:0] next_lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    wire [15:0] eff_delay = random_delay ? (delay_cycles & {8'h00, next_lfsr[7:0]}) : delay_cycles;

    assign fifo_wdata = {pattern_tag, sample_idx};
    assign fifo_we    = gen_en && !gen_reset && !in_delay && !fifo_full;

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            sample_idx      <= 16'd0;
            burst_cnt       <= 16'd0;
            delay_rem       <= 16'd0;
            in_delay        <= 1'b0;
            words_generated <= 32'd0;
            lfsr            <= 16'hACE1;
        end else if (gen_reset) begin
            sample_idx      <= 16'd0;
            burst_cnt       <= 16'd0;
            delay_rem       <= 16'd0;
            in_delay        <= 1'b0;
            words_generated <= 32'd0;
            lfsr            <= 16'hACE1;
        end else begin
            lfsr <= next_lfsr;

            if (!gen_en) begin
                // Hold state cleanly when paused
            end else if (in_delay) begin
                if (delay_rem <= 16'd1) begin
                    in_delay  <= 1'b0;
                    delay_rem <= 16'd0;
                    burst_cnt <= 16'd0;
                end else begin
                    delay_rem <= delay_rem - 16'd1;
                end
            end else if (fifo_we) begin
                sample_idx      <= sample_idx + 16'd1;
                words_generated <= words_generated + 32'd1;

                if ((burst_len != 16'd0) && ((burst_cnt + 16'd1) >= burst_len)) begin
                    burst_cnt <= 16'd0;
                    if (eff_delay != 16'd0) begin
                        in_delay  <= 1'b1;
                        delay_rem <= eff_delay;
                    end
                end else begin
                    burst_cnt <= burst_cnt + 16'd1;
                end
            end
        end
    end

endmodule