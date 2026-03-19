// adc_capture.v — Captures AD9226 12-bit parallel data on sample_valid strobe
//
// Simplified from CCD version: no pixel_index or pipeline offset.
// Simply latches ADC data when sample_valid is asserted.

module adc_capture #(
    parameter DATA_WIDTH = 12
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire [DATA_WIDTH-1:0] adc_data,       // AD9226 D[11:0]
    input  wire                  sample_valid,    // From excitation_gen sample_trigger

    output reg  [DATA_WIDTH-1:0] sample_data,     // Captured ADC value
    output reg                   sample_valid_out  // Pulse: new sample ready
);

    always @(posedge clk) begin
        if (rst) begin
            sample_data      <= 0;
            sample_valid_out <= 1'b0;
        end else begin
            sample_valid_out <= 1'b0;

            if (sample_valid) begin
                sample_data      <= adc_data;
                sample_valid_out <= 1'b1;
            end
        end
    end

endmodule
