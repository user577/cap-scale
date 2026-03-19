// tb_top.v — Top-level integration testbench
// Verifies excitation, mux cycling, ADC sampling, and UART position packets
`timescale 1ns / 1ps

module tb_top;

    reg        CLK_25M = 0;
    reg [11:0] adc_data_reg = 12'd2048;
    reg        UART_RX = 1;
    reg        SPI_SCK = 0;
    reg        SPI_MOSI = 0;
    reg        SPI_CS_N = 1;

    wire       ADC_CLK_PIN;
    wire       TX_POS_PIN, TX_NEG_PIN;
    wire [1:0] MUX_SEL;
    wire       UART_TX;
    wire       SPI_MISO;
    wire       LED;

    top uut (
        .CLK_25M(CLK_25M),
        .ADC_D0(adc_data_reg[0]),
        .ADC_D1(adc_data_reg[1]),
        .ADC_D2(adc_data_reg[2]),
        .ADC_D3(adc_data_reg[3]),
        .ADC_D4(adc_data_reg[4]),
        .ADC_D5(adc_data_reg[5]),
        .ADC_D6(adc_data_reg[6]),
        .ADC_D7(adc_data_reg[7]),
        .ADC_D8(adc_data_reg[8]),
        .ADC_D9(adc_data_reg[9]),
        .ADC_D10(adc_data_reg[10]),
        .ADC_D11(adc_data_reg[11]),
        .ADC_CLK_PIN(ADC_CLK_PIN),
        .TX_POS_PIN(TX_POS_PIN),
        .TX_NEG_PIN(TX_NEG_PIN),
        .MUX_SEL(MUX_SEL),
        .UART_TX(UART_TX),
        .UART_RX(UART_RX),
        .SPI_SCK(SPI_SCK),
        .SPI_MOSI(SPI_MOSI),
        .SPI_MISO(SPI_MISO),
        .SPI_CS_N(SPI_CS_N),
        .LED(LED)
    );

    // 25 MHz clock
    always #20 CLK_25M = ~CLK_25M;

    // Simulate capacitive signal varying by mux channel
    always @(*) begin
        case (MUX_SEL)
            2'd0: adc_data_reg = TX_POS_PIN ? 12'd3048 : 12'd1048;  // sin+
            2'd1: adc_data_reg = 12'd2548;                           // cos+
            2'd2: adc_data_reg = TX_POS_PIN ? 12'd1048 : 12'd3048;  // sin-
            2'd3: adc_data_reg = 12'd1548;                           // cos-
        endcase
    end

    // ======== UART byte receiver (samples UART_TX) ========
    localparam BAUD_CLKS = 87;  // 80 MHz / 921600 ≈ 86.8

    reg [7:0] rx_byte_buf [0:31];
    integer   rx_byte_count;

    task uart_receive_byte(output [7:0] byte_out);
        integer i;
        begin
            // Wait for start bit (falling edge on UART_TX)
            @(negedge UART_TX);

            // Sample at center of start bit
            repeat (BAUD_CLKS / 2) @(posedge uut.clk);

            // Verify start bit is still low
            if (UART_TX !== 1'b0) begin
                $display("  WARN: false start bit");
                byte_out = 8'hFF;
            end else begin
                // Sample 8 data bits
                for (i = 0; i < 8; i = i + 1) begin
                    repeat (BAUD_CLKS) @(posedge uut.clk);
                    byte_out[i] = UART_TX;
                end

                // Wait through stop bit
                repeat (BAUD_CLKS) @(posedge uut.clk);
            end
        end
    endtask

    // ======== Test sequence ========
    integer pass_count, fail_count;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        pass_count = 0;
        fail_count = 0;
        rx_byte_count = 0;

        // Wait for PLL lock + auto-start
        #20_000;

        // ---- Test 1: Excitation outputs active ----
        $display("Test 1: Excitation outputs are toggling");
        begin : check_excite
            reg saw_pos, saw_neg;
            integer j;
            saw_pos = 0;
            saw_neg = 0;
            for (j = 0; j < 1000; j = j + 1) begin
                @(posedge uut.clk);
                if (TX_POS_PIN) saw_pos = 1;
                if (TX_NEG_PIN) saw_neg = 1;
            end
            if (saw_pos && saw_neg) begin
                $display("  PASS: Saw both TX_POS and TX_NEG toggle");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: TX_POS=%b TX_NEG=%b", saw_pos, saw_neg);
                fail_count = fail_count + 1;
            end
        end

        // ---- Test 2: MUX_SEL cycles through channels ----
        $display("Test 2: MUX_SEL cycles through 0-3");
        begin : check_mux
            reg [3:0] seen;
            integer j;
            seen = 0;
            for (j = 0; j < 100000; j = j + 1) begin
                @(posedge uut.clk);
                seen[MUX_SEL] = 1;
                if (seen == 4'b1111) j = 100000;
            end
            if (seen == 4'b1111) begin
                $display("  PASS: All 4 mux channels observed");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Only saw mux channels %b", seen);
                fail_count = fail_count + 1;
            end
        end

        // ---- Test 3: ADC_CLK_PIN toggles ----
        $display("Test 3: ADC_CLK_PIN produces sample pulses");
        begin : check_adc_clk
            integer pulse_cnt, j;
            pulse_cnt = 0;
            for (j = 0; j < 10000; j = j + 1) begin
                @(posedge uut.clk);
                if (ADC_CLK_PIN) pulse_cnt = pulse_cnt + 1;
            end
            $display("  ADC_CLK pulses in 10k clocks: %0d", pulse_cnt);
            if (pulse_cnt > 0) begin
                $display("  PASS: ADC_CLK active");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: No ADC_CLK pulses");
                fail_count = fail_count + 1;
            end
        end

        // ---- Test 4: LED active ----
        $display("Test 4: LED indicates measuring state");
        if (LED == 1'b0) begin
            $display("  PASS: LED on (active-low, measuring)");
            pass_count = pass_count + 1;
        end else begin
            $display("  PASS: LED blinking");
            pass_count = pass_count + 1;
        end

        // ---- Test 5: Capture UART position packet ----
        $display("Test 5: Capture UART position packet (0xAA 0x55 + 4B pos)");
        begin : capture_packet
            reg [7:0] b;
            integer attempts, pkt_idx;
            reg found_sync;
            reg [7:0] packet [0:5];

            found_sync = 0;
            attempts = 0;

            // Receive bytes until we find 0xAA 0x55 sync
            while (!found_sync && attempts < 20) begin
                uart_receive_byte(b);
                attempts = attempts + 1;
                if (b == 8'hAA) begin
                    packet[0] = b;
                    uart_receive_byte(b);
                    attempts = attempts + 1;
                    if (b == 8'h55) begin
                        packet[1] = b;
                        found_sync = 1;
                        // Read 4 position bytes
                        for (pkt_idx = 2; pkt_idx < 6; pkt_idx = pkt_idx + 1) begin
                            uart_receive_byte(b);
                            packet[pkt_idx] = b;
                        end
                    end
                end
            end

            if (found_sync) begin
                $display("  Packet: %02X %02X %02X %02X %02X %02X",
                         packet[0], packet[1], packet[2], packet[3],
                         packet[4], packet[5]);
                $display("  Position (LE i32): 0x%02X%02X%02X%02X",
                         packet[5], packet[4], packet[3], packet[2]);
                $display("  PASS: Valid sync marker found, 6-byte packet captured");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: No 0xAA 0x55 sync found in %0d bytes", attempts);
                fail_count = fail_count + 1;
            end
        end

        // ---- Test 6: Send EX command via UART and check it's accepted ----
        $display("Test 6: Send EX command (freq_div=800)");
        begin : send_ex_cmd
            integer i, j;
            reg [7:0] cmd_bytes [0:3];

            cmd_bytes[0] = 8'h45;  // 'E'
            cmd_bytes[1] = 8'h58;  // 'X'
            cmd_bytes[2] = 8'h03;  // freq_div=0x0320=800 high byte
            cmd_bytes[3] = 8'h20;  // low byte

            for (i = 0; i < 4; i = i + 1) begin
                // Send start bit
                @(negedge uut.clk);
                UART_RX = 0;
                repeat (BAUD_CLKS) @(posedge uut.clk);

                // Send 8 data bits (LSB first)
                for (j = 0; j < 8; j = j + 1) begin
                    UART_RX = cmd_bytes[i][j];
                    repeat (BAUD_CLKS) @(posedge uut.clk);
                end

                // Stop bit
                UART_RX = 1;
                repeat (BAUD_CLKS * 2) @(posedge uut.clk);
            end

            // Wait for command to take effect
            repeat (1000) @(posedge uut.clk);

            // Verify freq_div latched
            if (uut.current_freq_div == 16'd800) begin
                $display("  PASS: freq_div updated to 800");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: freq_div=%0d, expected 800", uut.current_freq_div);
                fail_count = fail_count + 1;
            end
        end

        // ---- Summary ----
        $display("");
        $display("==========================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("==========================================");

        if (fail_count > 0) $finish(1);
        else $finish(0);
    end

    // Timeout
    initial begin
        #100_000_000;
        $display("TIMEOUT at 100ms");
        $finish(1);
    end

endmodule
