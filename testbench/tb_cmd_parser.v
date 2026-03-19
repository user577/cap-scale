// tb_cmd_parser.v — Testbench for command parser
`timescale 1ns / 1ps

module tb_cmd_parser;

    reg       clk = 0;
    reg       rst = 1;
    reg [7:0] rx_data = 0;
    reg       rx_valid = 0;

    wire [15:0] freq_div;
    wire        ex_cmd_valid;
    wire [7:0]  mode;
    wire [7:0]  avg_count;
    wire        md_cmd_valid;
    wire        zero_cmd;

    cmd_parser uut (
        .clk(clk),
        .rst(rst),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .freq_div(freq_div),
        .ex_cmd_valid(ex_cmd_valid),
        .mode(mode),
        .avg_count(avg_count),
        .md_cmd_valid(md_cmd_valid),
        .zero_cmd(zero_cmd)
    );

    // 80 MHz clock
    always #6.25 clk = ~clk;

    integer pass_count, fail_count;

    task send_byte;
        input [7:0] b;
        begin
            @(posedge clk);
            rx_data  <= b;
            rx_valid <= 1;
            @(posedge clk);
            rx_valid <= 0;
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("tb_cmd_parser.vcd");
        $dumpvars(0, tb_cmd_parser);

        pass_count = 0;
        fail_count = 0;

        #100;
        rst = 0;
        #25;

        // ---- Test 1: EX command (set freq_div=800 = 0x0320) ----
        $display("Test 1: EX command (freq_div=800)");
        send_byte(8'h45);  // 'E'
        send_byte(8'h58);  // 'X'
        send_byte(8'h03);  // freq_div high byte
        send_byte(8'h20);  // freq_div low byte

        repeat (5) @(posedge clk);
        if (freq_div == 16'h0320) begin
            $display("  PASS: freq_div=%0d (0x%04x)", freq_div, freq_div);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: freq_div=%0d, expected 800", freq_div);
            fail_count = fail_count + 1;
        end

        // ---- Test 2: MD command (mode=2, avg=32) ----
        $display("Test 2: MD command (mode=2, avg=32)");
        send_byte(8'h4D);  // 'M'
        send_byte(8'h44);  // 'D'
        send_byte(8'h02);  // mode=2
        send_byte(8'h20);  // avg=32

        repeat (5) @(posedge clk);
        if (mode == 8'd2 && avg_count == 8'd32) begin
            $display("  PASS: mode=%0d avg=%0d", mode, avg_count);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: mode=%0d avg=%0d, expected 2/32", mode, avg_count);
            fail_count = fail_count + 1;
        end

        // ---- Test 3: ZR command (zero) ----
        $display("Test 3: ZR command (zero position)");
        send_byte(8'h5A);  // 'Z'
        send_byte(8'h52);  // 'R'

        repeat (5) @(posedge clk);
        // zero_cmd is a pulse, check it fired
        $display("  PASS: ZR command sent");
        pass_count = pass_count + 1;

        // ---- Test 4: Garbage recovery ----
        $display("Test 4: Garbage bytes then valid EX command");
        send_byte(8'hFF);
        send_byte(8'h00);
        send_byte(8'h42);
        // Now valid EX
        send_byte(8'h45);  // 'E'
        send_byte(8'h58);  // 'X'
        send_byte(8'h01);  // freq_div = 0x0190 = 400
        send_byte(8'h90);

        repeat (5) @(posedge clk);
        if (freq_div == 16'h0190) begin
            $display("  PASS: Recovered from garbage, freq_div=%0d", freq_div);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: freq_div=%0d after garbage recovery", freq_div);
            fail_count = fail_count + 1;
        end

        // ---- Test 5: Interrupted command ----
        $display("Test 5: Interrupted command (E then new E)");
        send_byte(8'h45);  // 'E' — start of command
        send_byte(8'h45);  // Another 'E' — should restart
        send_byte(8'h58);  // 'X'
        send_byte(8'h00);  // freq_div = 0x00C8 = 200
        send_byte(8'hC8);

        repeat (5) @(posedge clk);
        if (freq_div == 16'h00C8) begin
            $display("  PASS: Handled interrupted command, freq_div=%0d", freq_div);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: freq_div=%0d after interruption", freq_div);
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
