// sync_demod.v — Synchronous demodulator for capacitive sensing
//
// 4 independent channels, each with a 20-bit signed accumulator.
// Multiplies ADC samples by demod_ref sign, accumulates over N samples.
// After N samples per channel, latches results and pulses measurement_done.
//
// Accumulator width: 12-bit signed sample × 256 max samples = 20 bits

module sync_demod #(
    parameter ACC_WIDTH = 20
)(
    input  wire        clk,
    input  wire        rst,

    // ADC input
    input  wire [11:0] adc_data,
    input  wire        sample_valid,

    // Demodulation reference
    input  wire        demod_ref,     // 1 = add, 0 = subtract

    // Channel selection
    input  wire [1:0]  channel_sel,   // Which channel is currently active

    // Configuration
    input  wire [7:0]  samples_per_ch, // Samples to accumulate per channel (power of 2)

    // Outputs — signed demodulated amplitudes
    output reg  signed [15:0] ch0_amplitude,
    output reg  signed [15:0] ch1_amplitude,
    output reg  signed [15:0] ch2_amplitude,
    output reg  signed [15:0] ch3_amplitude,
    output reg                measurement_done  // Pulse: all 4 channels measured
);

    // Accumulators (one per channel)
    reg signed [ACC_WIDTH-1:0] acc [0:3];

    // Sample counters (one per channel)
    reg [7:0] count [0:3];

    // Channel completion flags
    reg [3:0] ch_done;

    // Convert unsigned ADC to signed: centered at 2048
    wire signed [12:0] signed_sample = {1'b0, adc_data} - 13'sd2048;

    // Accumulate
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                acc[i]   <= 0;
                count[i] <= 0;
            end
            ch_done          <= 4'b0;
            ch0_amplitude    <= 0;
            ch1_amplitude    <= 0;
            ch2_amplitude    <= 0;
            ch3_amplitude    <= 0;
            measurement_done <= 1'b0;
        end else begin
            measurement_done <= 1'b0;

            if (sample_valid) begin
                // Multiply-accumulate for active channel
                if (demod_ref)
                    acc[channel_sel] <= acc[channel_sel] + {{(ACC_WIDTH-13){signed_sample[12]}}, signed_sample};
                else
                    acc[channel_sel] <= acc[channel_sel] - {{(ACC_WIDTH-13){signed_sample[12]}}, signed_sample};

                count[channel_sel] <= count[channel_sel] + 1;

                // Check if this channel is done
                if (count[channel_sel] == samples_per_ch - 1) begin
                    ch_done[channel_sel] <= 1'b1;
                end
            end

            // All 4 channels done → latch and reset
            if (ch_done == 4'b1111) begin
                // Truncate accumulators to 16-bit signed output
                // Right-shift by log2(samples) for averaging (use top 16 bits)
                ch0_amplitude <= acc[0][ACC_WIDTH-1:ACC_WIDTH-16];
                ch1_amplitude <= acc[1][ACC_WIDTH-1:ACC_WIDTH-16];
                ch2_amplitude <= acc[2][ACC_WIDTH-1:ACC_WIDTH-16];
                ch3_amplitude <= acc[3][ACC_WIDTH-1:ACC_WIDTH-16];

                measurement_done <= 1'b1;

                // Reset for next measurement cycle
                for (i = 0; i < 4; i = i + 1) begin
                    acc[i]   <= 0;
                    count[i] <= 0;
                end
                ch_done <= 4'b0;
            end
        end
    end

endmodule
