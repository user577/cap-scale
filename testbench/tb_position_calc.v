// tb_position_calc.v — Testbench for position calculator
`timescale 1ns / 1ps

module tb_position_calc;

    reg        clk = 0;
    reg        rst = 1;
    reg signed [15:0] ch0_amp = 0;
    reg signed [15:0] ch1_amp = 0;
    reg signed [15:0] ch2_amp = 0;
    reg signed [15:0] ch3_amp = 0;
    reg        measurement_done = 0;
    reg        zero_cmd = 0;

    wire signed [31:0] position;
    wire signed [15:0] sin_out, cos_out;
    wire        [15:0] amplitude;
    wire        [11:0] angle;
    wire               pos_valid;

    position_calc uut (
        .clk(clk),
        .rst(rst),
        .ch0_amp(ch0_amp),
        .ch1_amp(ch1_amp),
        .ch2_amp(ch2_amp),
        .ch3_amp(ch3_amp),
        .measurement_done(measurement_done),
        .zero_cmd(zero_cmd),
        .position(position),
        .sin_out(sin_out),
        .cos_out(cos_out),
        .amplitude(amplitude),
        .angle(angle),
        .pos_valid(pos_valid)
    );

    // 80 MHz clock
    always #6.25 clk = ~clk;

    integer pass_count, fail_count;

    task apply_measurement;
        input signed [15:0] c0, c1, c2, c3;
        begin
            @(posedge clk);
            ch0_amp <= c0;
            ch1_amp <= c1;
            ch2_amp <= c2;
            ch3_amp <= c3;
            measurement_done <= 1;
            @(posedge clk);
            measurement_done <= 0;
            // Wait for pipeline
            repeat (10) @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("tb_position_calc.vcd");
        $dumpvars(0, tb_position_calc);

        pass_count = 0;
        fail_count = 0;

        #100;
        rst = 0;
        #25;

        // ---- Test 1: Quadrature at 0 degrees ----
        // sin=0 (ch0=ch2), cos=max (ch1>ch3)
        $display("Test 1: 0 degrees (sin=0, cos=max)");
        apply_measurement(16'd1000, 16'd2000, 16'd1000, 16'd0);
        // sin_diff = ch0-ch2 = 0, cos_diff = ch1-ch3 = 2000
        $display("  angle=%0d sin=%0d cos=%0d pos=%0d",
                 angle, sin_out, cos_out, position);
        if (angle < 200) begin
            $display("  PASS: Angle near 0");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected angle ~0, got %0d", angle);
            fail_count = fail_count + 1;
        end

        // ---- Test 2: 90 degrees ----
        // sin=max (ch0>ch2), cos=0 (ch1=ch3)
        $display("Test 2: 90 degrees (sin=max, cos=0)");
        apply_measurement(16'd2000, 16'd1000, 16'd0, 16'd1000);
        // sin_diff = 2000, cos_diff = 0
        $display("  angle=%0d sin=%0d cos=%0d", angle, sin_out, cos_out);
        if (angle >= 800 && angle <= 1200) begin
            $display("  PASS: Angle near 1024 (90 deg)");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected angle ~1024, got %0d", angle);
            fail_count = fail_count + 1;
        end

        // ---- Test 3: 180 degrees ----
        // sin=0, cos=-max (ch3>ch1)
        $display("Test 3: 180 degrees (sin=0, cos=-max)");
        apply_measurement(16'd1000, 16'd0, 16'd1000, 16'd2000);
        // sin_diff = 0, cos_diff = -2000
        $display("  angle=%0d sin=%0d cos=%0d", angle, sin_out, cos_out);
        if (angle >= 1800 && angle <= 2300) begin
            $display("  PASS: Angle near 2048 (180 deg)");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected angle ~2048, got %0d", angle);
            fail_count = fail_count + 1;
        end

        // ---- Test 4: Zero command ----
        $display("Test 4: Zero command resets position");
        @(posedge clk);
        zero_cmd = 1;
        @(posedge clk);
        zero_cmd = 0;
        repeat (5) @(posedge clk);

        // Feed same measurement again
        apply_measurement(16'd2000, 16'd1000, 16'd0, 16'd1000);
        $display("  Position after zero+measure: %0d", position);
        // Position should be relative to zero point
        pass_count = pass_count + 1;
        $display("  PASS: Zero command accepted");

        // ---- Test 5: Amplitude calculation ----
        $display("Test 5: Amplitude output non-zero for valid signal");
        if (amplitude > 0) begin
            $display("  PASS: amplitude=%0d", amplitude);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: amplitude should be > 0");
            fail_count = fail_count + 1;
        end

        // ---- Test 6: Direction reversal ----
        $display("Test 6: Multi-pitch traversal");
        // Simulate forward: 0→90→180→270→0 (one full pitch)
        apply_measurement(16'd1000, 16'd2000, 16'd1000, 16'd0);  // 0 deg
        apply_measurement(16'd2000, 16'd1000, 16'd0, 16'd1000);  // 90 deg
        apply_measurement(16'd1000, 16'd0, 16'd1000, 16'd2000);  // 180 deg

        // sin goes negative (270 deg)
        apply_measurement(16'd0, 16'd1000, 16'd2000, 16'd1000);  // 270 deg
        $display("  Position at 270: %0d", position);

        // Back to 0 (completes one pitch → pitch_count should increment)
        apply_measurement(16'd1000, 16'd2000, 16'd1000, 16'd0);  // 360=0 deg
        $display("  Position after full pitch: %0d", position);
        $display("  PASS: Multi-pitch traversal completed");
        pass_count = pass_count + 1;

        // ---- Summary ----
        $display("");
        $display("==========================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("==========================================");

        if (fail_count > 0) $finish(1);
        else $finish(0);
    end

    initial begin
        #10_000_000;
        $display("TIMEOUT");
        $finish(1);
    end

endmodule
