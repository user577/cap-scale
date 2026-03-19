// channel_mux.v — 4-channel analog mux controller for CD4052
//
// Cycles mux_sel through 0→1→2→3 on each cycle_done from excitation_gen.
// Inserts configurable settling delay before enabling ADC sampling.

module channel_mux #(
    parameter DEFAULT_SETTLING = 80  // 1 us at 80 MHz
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,

    // From excitation_gen
    input  wire       cycle_done,

    // Configuration
    input  wire [7:0] settling_clocks,   // 0 = use default
    input  wire       config_valid,

    // Outputs
    output reg  [1:0] mux_sel,           // To CD4052 address pins
    output reg  [1:0] channel_sel,       // Current channel (matches mux_sel)
    output reg        adc_enable,        // High when settling is complete
    output reg        all_channels_done  // Pulse after ch3 cycle_done
);

    reg [7:0] active_settling;
    reg [7:0] settle_cnt;
    reg       settling;

    // Latch config
    always @(posedge clk) begin
        if (rst)
            active_settling <= DEFAULT_SETTLING[7:0];
        else if (config_valid)
            active_settling <= (settling_clocks == 0) ? DEFAULT_SETTLING[7:0] : settling_clocks;
    end

    // Mux cycling state machine
    always @(posedge clk) begin
        if (rst || !enable) begin
            mux_sel           <= 2'd0;
            channel_sel       <= 2'd0;
            adc_enable        <= 1'b0;
            all_channels_done <= 1'b0;
            settle_cnt        <= 0;
            settling          <= 1'b1;  // Start with settling on channel 0
        end else begin
            all_channels_done <= 1'b0;

            if (settling) begin
                // Wait for mux to settle
                if (settle_cnt >= active_settling - 1) begin
                    settling   <= 1'b0;
                    adc_enable <= 1'b1;
                    settle_cnt <= 0;
                end else begin
                    settle_cnt <= settle_cnt + 1;
                end
            end

            if (cycle_done) begin
                // Advance to next channel
                adc_enable <= 1'b0;
                settling   <= 1'b1;
                settle_cnt <= 0;

                if (mux_sel == 2'd3) begin
                    mux_sel           <= 2'd0;
                    channel_sel       <= 2'd0;
                    all_channels_done <= 1'b1;
                end else begin
                    mux_sel     <= mux_sel + 1;
                    channel_sel <= mux_sel + 1;
                end
            end
        end
    end

endmodule
