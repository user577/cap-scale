// excitation_gen.v — Square-wave excitation generator for capacitive sensing
//
// Divides 80 MHz system clock by freq_div to produce anti-phase TX drive signals.
// Default: freq_div=400 → 200 kHz excitation (80M / 400 = 200 kHz full cycle).
//
// Outputs:
//   tx_pos, tx_neg    — Anti-phase GPIO outputs to scale TX electrodes
//   demod_ref          — Sign bit for synchronous demodulator (1=positive half)
//   sample_trigger     — ADC sample strobe (N pulses per excitation half-cycle)
//   cycle_done         — Pulse at end of each full excitation cycle

module excitation_gen #(
    parameter DEFAULT_FREQ_DIV     = 400,   // 80 MHz / 400 = 200 kHz
    parameter DEFAULT_SAMPLES      = 16     // Samples per half-cycle
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    // Runtime configuration
    input  wire [15:0] freq_div,       // Clock divider (0 = use default)
    input  wire [7:0]  samples_per_hc, // Samples per half-cycle (0 = use default)
    input  wire        config_valid,   // Pulse to latch new config

    // Outputs
    output reg         tx_pos,
    output reg         tx_neg,
    output reg         demod_ref,      // 1 = positive half-cycle
    output reg         sample_trigger, // ADC sample strobe
    output reg         cycle_done      // Pulse at end of full cycle
);

    // Latched configuration
    reg [15:0] active_freq_div;
    reg [7:0]  active_samples;

    // Derived: half-period in clocks, sample interval
    wire [15:0] half_period = active_freq_div >> 1;  // freq_div / 2
    wire [15:0] sample_interval;

    // sample_interval = half_period / active_samples
    // Use shift approximation for power-of-2 samples, or division
    assign sample_interval = half_period / {8'd0, active_samples};

    // Counters
    reg [15:0] cycle_cnt;       // Counts within half-cycle
    reg [7:0]  sample_cnt;      // Counts samples within half-cycle
    reg [15:0] sample_timer;    // Counts clocks between samples
    reg        half_sel;        // 0 = positive half, 1 = negative half

    // Latch config
    always @(posedge clk) begin
        if (rst) begin
            active_freq_div <= DEFAULT_FREQ_DIV[15:0];
            active_samples  <= DEFAULT_SAMPLES[7:0];
        end else if (config_valid) begin
            active_freq_div <= (freq_div == 0) ? DEFAULT_FREQ_DIV[15:0] : freq_div;
            active_samples  <= (samples_per_hc == 0) ? DEFAULT_SAMPLES[7:0] : samples_per_hc;
        end
    end

    // Main excitation state machine
    always @(posedge clk) begin
        if (rst || !enable) begin
            cycle_cnt      <= 0;
            sample_cnt     <= 0;
            sample_timer   <= 0;
            half_sel       <= 0;
            tx_pos         <= 0;
            tx_neg         <= 0;
            demod_ref      <= 0;
            sample_trigger <= 0;
            cycle_done     <= 0;
        end else begin
            sample_trigger <= 1'b0;
            cycle_done     <= 1'b0;

            // Drive outputs based on half-cycle
            tx_pos    <= ~half_sel;
            tx_neg    <=  half_sel;
            demod_ref <= ~half_sel;

            // Sample timing within half-cycle
            if (sample_timer >= sample_interval - 1) begin
                sample_timer <= 0;
                if (sample_cnt < active_samples) begin
                    sample_trigger <= 1'b1;
                    sample_cnt     <= sample_cnt + 1;
                end
            end else begin
                sample_timer <= sample_timer + 1;
            end

            // Half-cycle boundary
            if (cycle_cnt >= half_period - 1) begin
                cycle_cnt    <= 0;
                sample_cnt   <= 0;
                sample_timer <= 0;

                if (half_sel) begin
                    // End of negative half → full cycle done
                    cycle_done <= 1'b1;
                    half_sel   <= 0;
                end else begin
                    // End of positive half → switch to negative
                    half_sel <= 1;
                end
            end else begin
                cycle_cnt <= cycle_cnt + 1;
            end
        end
    end

endmodule
