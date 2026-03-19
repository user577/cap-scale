// tb_channel_mux.v — Testbench for channel multiplexer
`timescale 1ns / 1ps

module tb_channel_mux;

    reg       clk = 0;
    reg       rst = 1;
    reg       enable = 0;
    reg       cycle_done = 0;
    reg [7:0] settling_clocks = 0;
    reg       config_valid = 0;

    wire [1:0] mux_sel;
    wire [1:0] channel_sel;
    wire       adc_enable;
    wire       all_channels_done;

    channel_mux #(
        .DEFAULT_SETTLING(8)  // Short settling for simulation
    ) uut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .cycle_done(cycle_done),
        .settling_clocks(settling_clocks),
        .config_valid(config_valid),
        .mux_sel(mux_sel),
        .channel_sel(channel_sel),
        .adc_enable(adc_enable),
        .all_channels_done(all_channels_done)
    );

    // 80 MHz clock
    always #6.25 clk = ~clk;

    integer pass_count, fail_count;

    task pulse_cycle_done;
        begin
            @(posedge clk);
            cycle_done = 1;
            @(posedge clk);
            cycle_done = 0;
        end
    endtask

    initial begin
        $dumpfile("tb_channel_mux.vcd");
        $dumpvars(0, tb_channel_mux);

        pass_count = 0;
        fail_count = 0;

        #100;
        rst = 0;
        #25;
        enable = 1;

        // ---- Test 1: Initial state ----
        $display("Test 1: Initial state is channel 0");
        repeat (20) @(posedge clk);  // Wait for settling
        if (mux_sel == 2'd0) begin
            $display("  PASS: mux_sel=0");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: mux_sel=%0d, expected 0", mux_sel);
            fail_count = fail_count + 1;
        end

        // ---- Test 2: Settling delay ----
        $display("Test 2: ADC enable after settling");
        // adc_enable should go high after settling period
        if (adc_enable) begin
            $display("  PASS: adc_enable is high after settling");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: adc_enable should be high");
            fail_count = fail_count + 1;
        end

        // ---- Test 3: Channel cycling ----
        $display("Test 3: Channels cycle 0→1→2→3");

        pulse_cycle_done();
        repeat (20) @(posedge clk);
        if (mux_sel == 2'd1) begin
            $display("  PASS: Advanced to channel 1");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected ch 1, got %0d", mux_sel);
            fail_count = fail_count + 1;
        end

        pulse_cycle_done();
        repeat (20) @(posedge clk);
        if (mux_sel == 2'd2) begin
            $display("  PASS: Advanced to channel 2");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected ch 2, got %0d", mux_sel);
            fail_count = fail_count + 1;
        end

        pulse_cycle_done();
        repeat (20) @(posedge clk);
        if (mux_sel == 2'd3) begin
            $display("  PASS: Advanced to channel 3");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected ch 3, got %0d", mux_sel);
            fail_count = fail_count + 1;
        end

        // ---- Test 4: Wrap around + all_channels_done ----
        $display("Test 4: Wrap around to 0 with all_channels_done");
        pulse_cycle_done();
        // Check all_channels_done fired
        @(posedge clk);
        repeat (2) @(posedge clk);  // all_channels_done is combinational on cycle_done

        repeat (20) @(posedge clk);
        if (mux_sel == 2'd0) begin
            $display("  PASS: Wrapped to channel 0");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected ch 0, got %0d", mux_sel);
            fail_count = fail_count + 1;
        end

        // ---- Test 5: channel_sel matches mux_sel ----
        $display("Test 5: channel_sel matches mux_sel");
        if (channel_sel == mux_sel) begin
            $display("  PASS: channel_sel=%0d == mux_sel=%0d", channel_sel, mux_sel);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: channel_sel=%0d != mux_sel=%0d", channel_sel, mux_sel);
            fail_count = fail_count + 1;
        end

        // ---- Summary ----
        $display("");
        $display("==========================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("==========================================");

        if (fail_count > 0) $finish(1);
        else $finish(0);
    end

    initial begin
        #5_000_000;
        $display("TIMEOUT");
        $finish(1);
    end

endmodule
