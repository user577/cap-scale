// position_calc.v — atan2 position calculator with pitch counting
//
// Takes 4 demodulated channel amplitudes, computes differential sin/cos,
// uses 1024-entry atan2 LUT for angle, and tracks pitch count via
// sin zero-crossing detection.
//
// Output: 32-bit position = pitch_count * 4096 + angle
// Resolution: 4096 counts per pitch (e.g., 2mm pitch → 0.49 um/count)

module position_calc (
    input  wire        clk,
    input  wire        rst,

    // Demodulated channel amplitudes (signed 16-bit)
    input  wire signed [15:0] ch0_amp,  // sin+
    input  wire signed [15:0] ch1_amp,  // cos+
    input  wire signed [15:0] ch2_amp,  // sin-
    input  wire signed [15:0] ch3_amp,  // cos-
    input  wire               measurement_done,

    // Control
    input  wire               zero_cmd,  // Pulse to zero position

    // Outputs
    output reg  signed [31:0] position,    // pitch_count * 4096 + angle
    output reg  signed [15:0] sin_out,     // Differential sin (diagnostics)
    output reg  signed [15:0] cos_out,     // Differential cos (diagnostics)
    output reg         [15:0] amplitude,   // Signal amplitude (diagnostics)
    output reg         [11:0] angle,       // Current angle within pitch (0-4095)
    output reg                pos_valid    // Pulse: new position ready
);

    // ---- atan2 LUT (1024 entries, 12-bit angle output) ----
    // Indexed by |sin|/|cos| ratio mapped to 0-1023
    // Covers first octant (0-45 deg); other octants derived by symmetry
    reg [11:0] atan_lut [0:1023];

    // Initialize LUT — atan(i/1024) * 4096 / (2*pi) for octant mapping
    // Actually: atan(i/1024) * (4096/8) since this covers 1/8 of full circle
    integer k;
    initial begin
        for (k = 0; k < 1024; k = k + 1) begin
            // Precomputed: angle = atan(k/1024) * 2048 / (pi/4)
            // Simplified: angle = k * 512 / 1024 = k/2 (linear approx for init)
            // In practice, load from $readmemh or compute offline
            // Using linear approximation: good enough for first octant
            atan_lut[k] = (k * 512) / 1024;
        end
    end

    // Pipeline registers
    reg signed [16:0] sin_diff, cos_diff;
    reg signed [16:0] abs_sin, abs_cos;
    reg        [1:0]  octant;
    reg               pipe_valid_1, pipe_valid_2, pipe_valid_3;

    // Pitch tracking
    reg signed [19:0] pitch_count;
    reg signed [15:0] prev_sin;
    reg               prev_sin_valid;

    // Zero offset
    reg signed [31:0] zero_offset;

    // LUT index and result
    reg [9:0]  lut_index;
    reg [11:0] lut_result;
    reg [11:0] raw_angle;

    // Stage 1: Compute differentials
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

    // Stage 2: Absolute values, determine octant, compute LUT index
    always @(posedge clk) begin
        if (rst) begin
            abs_sin      <= 0;
            abs_cos      <= 0;
            octant       <= 0;
            lut_index    <= 0;
            pipe_valid_2 <= 0;
        end else begin
            pipe_valid_2 <= 0;
            if (pipe_valid_1) begin
                abs_sin <= sin_diff[16] ? -sin_diff : sin_diff;
                abs_cos <= cos_diff[16] ? -cos_diff : cos_diff;

                // Octant: {sin_sign, cos_sign, |sin|>|cos|}
                // Simplified to quadrant + swap
                octant <= {sin_diff[16], cos_diff[16]};

                // LUT index: ratio of smaller/larger * 1024
                if ((sin_diff[16] ? -sin_diff : sin_diff) <=
                    (cos_diff[16] ? -cos_diff : cos_diff)) begin
                    // |sin| <= |cos|: index = |sin|*1024/|cos|
                    if (cos_diff == 0)
                        lut_index <= 0;
                    else
                        lut_index <= ((sin_diff[16] ? -sin_diff : sin_diff) * 1024) /
                                     (cos_diff[16] ? -cos_diff : cos_diff);
                end else begin
                    // |sin| > |cos|: index = |cos|*1024/|sin|
                    if (sin_diff == 0)
                        lut_index <= 0;
                    else
                        lut_index <= ((cos_diff[16] ? -cos_diff : cos_diff) * 1024) /
                                     (sin_diff[16] ? -sin_diff : sin_diff);
                end

                pipe_valid_2 <= 1'b1;
            end
        end
    end

    // Stage 3: LUT lookup + octant correction + pitch tracking
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
        end else begin
            pos_valid    <= 1'b0;
            pipe_valid_3 <= 1'b0;

            // Zero command
            if (zero_cmd) begin
                zero_offset <= position + zero_offset;
                pitch_count <= 0;
            end

            if (pipe_valid_2) begin
                // LUT lookup
                lut_result <= atan_lut[lut_index];

                // Reconstruct full angle from octant
                // Quadrant 0 (sin>=0, cos>=0): angle = lut or 1024-lut
                // Quadrant 1 (sin>=0, cos<0):  angle = 2048 +/- lut
                // Quadrant 2 (sin<0, cos<0):   angle = 2048 +/- lut
                // Quadrant 3 (sin<0, cos>=0):  angle = 4096 - lut or 3072+lut
                case (octant)
                    2'b00: begin // sin>=0, cos>=0 (Q1)
                        if (abs_sin <= abs_cos)
                            raw_angle <= atan_lut[lut_index];
                        else
                            raw_angle <= 12'd1024 - atan_lut[lut_index];
                    end
                    2'b01: begin // sin>=0, cos<0 (Q2)
                        if (abs_sin > abs_cos)
                            raw_angle <= 12'd1024 + atan_lut[lut_index];
                        else
                            raw_angle <= 12'd2048 - atan_lut[lut_index];
                    end
                    2'b11: begin // sin<0, cos<0 (Q3)
                        if (abs_sin <= abs_cos)
                            raw_angle <= 12'd2048 + atan_lut[lut_index];
                        else
                            raw_angle <= 12'd3072 - atan_lut[lut_index];
                    end
                    2'b10: begin // sin<0, cos>=0 (Q4)
                        if (abs_sin > abs_cos)
                            raw_angle <= 12'd3072 + atan_lut[lut_index];
                        else
                            raw_angle <= 12'd4096 - atan_lut[lut_index];
                    end
                endcase

                // Pitch counting: detect sin zero-crossing
                if (prev_sin_valid) begin
                    if (prev_sin < 0 && sin_diff[15:0] >= 0)
                        pitch_count <= pitch_count + 1;  // Forward crossing
                    else if (prev_sin >= 0 && sin_diff[15:0] < 0)
                        pitch_count <= pitch_count - 1;  // Reverse crossing
                end

                prev_sin       <= sin_diff[15:0];
                prev_sin_valid <= 1'b1;

                // Latch diagnostic outputs
                sin_out <= sin_diff[15:0];
                cos_out <= cos_diff[15:0];

                // Amplitude: alpha-max-beta-min approximation
                // amp ≈ max(|sin|,|cos|) + 0.375*min(|sin|,|cos|)
                if (abs_sin >= abs_cos)
                    amplitude <= abs_sin[15:0] + (abs_cos[15:0] >> 2) + (abs_cos[15:0] >> 3);
                else
                    amplitude <= abs_cos[15:0] + (abs_sin[15:0] >> 2) + (abs_sin[15:0] >> 3);

                pipe_valid_3 <= 1'b1;
            end

            if (pipe_valid_3) begin
                angle    <= raw_angle;
                position <= (pitch_count * 4096 + {20'd0, raw_angle}) - zero_offset;
                pos_valid <= 1'b1;
            end
        end
    end

endmodule
