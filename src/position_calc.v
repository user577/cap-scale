// position_calc.v — atan2 position calculator with pitch counting
//
// Takes 4 demodulated channel amplitudes, computes differential sin/cos,
// uses atan2 LUT for angle, and tracks pitch count via zero-crossing.
//
// Output: 32-bit position = pitch_count * 4096 + angle
// Resolution: 4096 counts per pitch (e.g., 2mm pitch → 0.49 um/count)
//
// Pipeline: 4 stages (measurement_done → pos_valid in 4 clocks)
//
// Atan2 approach: direct 2D LUT indexed by upper bits of |sin| and |cos|.
// 64x64 = 4096 entries × 12 bits = 48 Kbits (3 EBR blocks).
// No division required — single BRAM read per measurement.

module position_calc (
    input  wire        clk,
    input  wire        rst,

    input  wire signed [15:0] ch0_amp,  // sin+
    input  wire signed [15:0] ch1_amp,  // cos+
    input  wire signed [15:0] ch2_amp,  // sin-
    input  wire signed [15:0] ch3_amp,  // cos-
    input  wire               measurement_done,

    input  wire               zero_cmd,

    output reg  signed [31:0] position,
    output reg  signed [15:0] sin_out,
    output reg  signed [15:0] cos_out,
    output reg         [15:0] amplitude,
    output reg         [11:0] angle,
    output reg                pos_valid
);

    // ---- atan2 LUT: 4096 entries (64x64), 12-bit angle output ----
    // Index = {|sin|[top 6 bits], |cos|[top 6 bits]}
    // Value = full-circle angle (0-4095) for first quadrant
    // Other quadrants derived by simple arithmetic
    reg [11:0] atan2_lut [0:4095];

    // Load precomputed 2D atan2 LUT
    initial begin
        $readmemh("atan2_lut.hex", atan2_lut);
    end

    // Pipeline registers
    reg signed [16:0] sin_diff, cos_diff;
    reg        [16:0] abs_sin, abs_cos;
    reg        [1:0]  quadrant;           // {sin_neg, cos_neg}
    reg signed [16:0] p2_sin_diff, p2_cos_diff;
    reg        [16:0] p2_abs_sin, p2_abs_cos;
    reg        [1:0]  p2_quadrant;
    reg               pipe_valid_1, pipe_valid_2, pipe_valid_3;

    // LUT address and result
    reg [11:0] lut_addr;
    reg [11:0] lut_val;
    reg [11:0] raw_angle;

    // Pitch tracking
    reg signed [19:0] pitch_count;
    reg signed [15:0] prev_sin;
    reg               prev_sin_valid;

    // Zero offset
    reg signed [31:0] zero_offset;

    // ====== Stage 1: Compute differentials ======
    always @(posedge clk) begin
        if (rst) begin
            sin_diff     <= 0;
            cos_diff     <= 0;
            pipe_valid_1 <= 0;
        end else begin
            pipe_valid_1 <= 0;
            if (measurement_done) begin
                sin_diff     <= {ch0_amp[15], ch0_amp} - {ch2_amp[15], ch2_amp};
                cos_diff     <= {ch1_amp[15], ch1_amp} - {ch3_amp[15], ch3_amp};
                pipe_valid_1 <= 1'b1;
            end
        end
    end

    // ====== Stage 2: Abs values + quadrant + LUT address ======
    always @(posedge clk) begin
        if (rst) begin
            abs_sin      <= 0;
            abs_cos      <= 0;
            quadrant     <= 0;
            lut_addr     <= 0;
            p2_sin_diff  <= 0;
            p2_cos_diff  <= 0;
            pipe_valid_2 <= 0;
        end else begin
            pipe_valid_2 <= 0;
            if (pipe_valid_1) begin
                abs_sin  <= sin_diff[16] ? -sin_diff : sin_diff;
                abs_cos  <= cos_diff[16] ? -cos_diff : cos_diff;
                quadrant <= {sin_diff[16], cos_diff[16]};

                // LUT address from top 6 bits of |sin| and |cos|
                // Normalize: find max of the two, use as scale reference
                // Simple approach: use bits [15:10] of absolute values
                // (shift right by 10 to get 6-bit index, clamp at 63)
                begin : compute_addr
                    reg [16:0] as, ac;
                    reg [5:0] si, ci;
                    as = sin_diff[16] ? -sin_diff : sin_diff;
                    ac = cos_diff[16] ? -cos_diff : cos_diff;
                    // Scale to 6 bits: divide by max/63 to normalize
                    // Simpler: just use upper bits, clamped
                    si = (as[16:10] > 6'd63) ? 6'd63 : as[15:10];
                    ci = (ac[16:10] > 6'd63) ? 6'd63 : ac[15:10];
                    lut_addr <= {si, ci};
                end

                p2_sin_diff  <= sin_diff;
                p2_cos_diff  <= cos_diff;
                pipe_valid_2 <= 1'b1;
            end
        end
    end

    // ====== Stage 3: LUT read + quadrant correction + pitch tracking ======
    always @(posedge clk) begin
        if (rst) begin
            raw_angle      <= 0;
            angle          <= 0;
            sin_out        <= 0;
            cos_out        <= 0;
            amplitude      <= 0;
            position       <= 0;
            pos_valid      <= 0;
            pitch_count    <= 0;
            prev_sin       <= 0;
            prev_sin_valid <= 0;
            zero_offset    <= 0;
            pipe_valid_3   <= 0;
            p2_abs_sin     <= 0;
            p2_abs_cos     <= 0;
            p2_quadrant    <= 0;
        end else begin
            pos_valid    <= 1'b0;
            pipe_valid_3 <= 1'b0;

            if (zero_cmd) begin
                zero_offset <= position + zero_offset;
                pitch_count <= 0;
            end

            if (pipe_valid_2) begin
                // Read LUT (first-quadrant angle, 0-1023 range)
                lut_val <= atan2_lut[lut_addr];

                // Pass through for stage 4
                p2_abs_sin  <= abs_sin;
                p2_abs_cos  <= abs_cos;
                p2_quadrant <= quadrant;

                // Pitch counting
                if (prev_sin_valid) begin
                    if (prev_sin < 0 && p2_sin_diff[15:0] >= 0)
                        pitch_count <= pitch_count + 1;
                    else if (prev_sin >= 0 && p2_sin_diff[15:0] < 0)
                        pitch_count <= pitch_count - 1;
                end
                prev_sin       <= p2_sin_diff[15:0];
                prev_sin_valid <= 1'b1;

                // Diagnostics
                sin_out <= p2_sin_diff[15:0];
                cos_out <= p2_cos_diff[15:0];

                // Amplitude: alpha-max-beta-min
                if (abs_sin >= abs_cos)
                    amplitude <= abs_sin[15:0] + (abs_cos[15:0] >> 2) + (abs_cos[15:0] >> 3);
                else
                    amplitude <= abs_cos[15:0] + (abs_sin[15:0] >> 2) + (abs_sin[15:0] >> 3);

                pipe_valid_3 <= 1'b1;
            end

            // ====== Stage 4: Quadrant correction + position output ======
            if (pipe_valid_3) begin
                // lut_val is first-quadrant angle (0-1023)
                // Map to full circle based on quadrant (combinational)
                case (p2_quadrant)
                    2'b00: raw_angle = lut_val;                        // Q1: 0-1023
                    2'b01: raw_angle = 12'd2048 - lut_val;            // Q2: 1024-2048
                    2'b11: raw_angle = 12'd2048 + lut_val;            // Q3: 2048-3072
                    2'b10: raw_angle = 12'd4096 - lut_val;            // Q4: 3072-4096
                    default: raw_angle = 0;
                endcase

                angle    <= raw_angle;
                position <= (pitch_count * 4096 + {20'd0, raw_angle}) - zero_offset;
                pos_valid <= 1'b1;
            end
        end
    end

endmodule
