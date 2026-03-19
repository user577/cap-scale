// tb_excitation_gen.v — Testbench for excitation generator
`timescale 1ns / 1ps

module tb_excitation_gen;

    reg        clk = 0;
    reg        rst = 1;
    reg        enable = 0;
    reg [15:0] freq_div = 0;
    reg [7:0]  samples_per_hc = 0;
    reg        config_valid = 0;

    wire       tx_pos, tx_neg;
    wire       demod_ref;
    wire       sample_trigger;
    wire       cycle_done;

    excitation_gen #(
        .DEFAULT_FREQ_DIV(400),
        .DEFAULT_SAMPLES(16)
    ) uut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .freq_div(freq_div),
        .samples_per_hc(samples_per_hc),
        .config_valid(config_valid),
        .tx_pos(tx_pos),
        .tx_neg(tx_neg),
        .demod_ref(demod_ref),
        .sample_trigger(sample_trigger),
        .cycle_done(cycle_done)
    );

    // 80 MHz clock
    always #6.25 clk = ~clk;

    // Monitoring
    integer sample_count;
    integer cycle_count;
    integer pass_count;
    integer fail_count;

    initial begin
        $dumpfile("tb_excitation_gen.vcd");
        $dumpvars(0, tb_excitation_gen);

        pass_count = 0;
        fail_count = 0;
        sample_count = 0;
        cycle_count = 0;

        // ---- Test 1: Default 200 kHz frequency ----
        $display("Test 1: Default 200 kHz excitation");
        #100;
        rst = 0;
        #25;
        enable = 1;

        // Wait for a few cycles
        repeat (5) begin
            @(posedge cycle_done);
            cycle_count = cycle_count + 1;
        end

        if (cycle_count == 5) begin
            $display("  PASS: Got 5 cycle_done pulses");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected 5 cycles, got %0d", cycle_count);
            fail_count = fail_count + 1;
        end

        // ---- Test 2: Anti-phase outputs ----
        $display("Test 2: Anti-phase TX outputs");
        // tx_pos and tx_neg should always be complementary
        repeat (100) @(posedge clk);
        if (tx_pos != tx_neg) begin
            $display("  PASS: tx_pos and tx_neg are anti-phase");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: tx_pos=%b tx_neg=%b not anti-phase", tx_pos, tx_neg);
            fail_count = fail_count + 1;
        end

        // ---- Test 3: demod_ref tracks positive half ----
        $display("Test 3: demod_ref tracks tx_pos");
        if (demod_ref == tx_pos) begin
            $display("  PASS: demod_ref matches tx_pos");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: demod_ref=%b tx_pos=%b", demod_ref, tx_pos);
            fail_count = fail_count + 1;
        end

        // ---- Test 4: Count samples per cycle ----
        $display("Test 4: Sample count per cycle");
        sample_count = 0;
        @(posedge cycle_done);
        fork
            begin
                @(posedge cycle_done);
            end
            begin
                forever begin
                    @(posedge clk);
                    if (sample_trigger) sample_count = sample_count + 1;
                end
            end
        join_any
        disable fork;

        $display("  Samples per cycle: %0d (expected ~32 = 16*2 half-cycles)", sample_count);
        if (sample_count >= 28 && sample_count <= 36) begin
            $display("  PASS: Sample count in expected range");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Sample count %0d out of range", sample_count);
            fail_count = fail_count + 1;
        end

        // ---- Test 5: Runtime frequency change ----
        $display("Test 5: Runtime frequency change to 100 kHz (div=800)");
        freq_div = 800;
        config_valid = 1;
        @(posedge clk);
        config_valid = 0;

        // Count clocks for one full cycle
        @(posedge cycle_done);
        begin : measure_period
            integer clk_count;
            clk_count = 0;
            fork
                begin
                    @(posedge cycle_done);
                end
                begin
                    forever begin
                        @(posedge clk);
                        clk_count = clk_count + 1;
                    end
                end
            join_any
            disable fork;
            $display("  Clocks per cycle: %0d (expected ~800)", clk_count);
            if (clk_count >= 780 && clk_count <= 820) begin
                $display("  PASS: Period matches new freq_div");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Period %0d out of range", clk_count);
                fail_count = fail_count + 1;
            end
        end

        // ---- Summary ----
        $display("");
        $display("==========================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("==========================================");

        if (fail_count > 0) begin
            $display("TESTBENCH FAILED");
            $finish(1);
        end else begin
            $display("ALL TESTS PASSED");
            $finish(0);
        end
    end

    // Timeout
    initial begin
        #5_000_000;
        $display("TIMEOUT");
        $finish(1);
    end

endmodule
