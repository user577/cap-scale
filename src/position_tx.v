// position_tx.v — UART serialization for position/diagnostics data
//
// Three modes:
//   Mode 1 (6B):  0xAA 0x55 + position[4B LE signed]
//   Mode 2 (20B): 0xAA 0x55 + position[4B] + sin[2B] + cos[2B] + amplitude[2B]
//                  + ch0[2B] + ch1[2B] + ch2[2B] + ch3[2B]
//   Mode 3:       Raw ADC stream (debug) — not yet implemented

module position_tx (
    input  wire        clk,
    input  wire        rst,

    // Control
    input  wire [7:0]  mode,              // 1=position, 2=diagnostics
    input  wire        pos_valid,         // Pulse: new position ready

    // Position data
    input  wire signed [31:0] position,
    input  wire signed [15:0] sin_val,
    input  wire signed [15:0] cos_val,
    input  wire        [15:0] amplitude,

    // Per-channel amplitudes
    input  wire signed [15:0] ch0_amp,
    input  wire signed [15:0] ch1_amp,
    input  wire signed [15:0] ch2_amp,
    input  wire signed [15:0] ch3_amp,

    // UART TX interface
    output reg  [7:0]  tx_data,
    output reg         tx_start,
    input  wire        tx_busy,

    // Status
    output reg         transmitting
);

    localparam S_IDLE    = 5'd0,
               S_SYNC0   = 5'd1,
               S_SYNC1   = 5'd2,
               S_POS_0   = 5'd3,
               S_POS_1   = 5'd4,
               S_POS_2   = 5'd5,
               S_POS_3   = 5'd6,
               S_SIN_LO  = 5'd7,
               S_SIN_HI  = 5'd8,
               S_COS_LO  = 5'd9,
               S_COS_HI  = 5'd10,
               S_AMP_LO  = 5'd11,
               S_AMP_HI  = 5'd12,
               S_CH0_LO  = 5'd13,
               S_CH0_HI  = 5'd14,
               S_CH1_LO  = 5'd15,
               S_CH1_HI  = 5'd16,
               S_CH2_LO  = 5'd17,
               S_CH2_HI  = 5'd18,
               S_CH3_LO  = 5'd19,
               S_CH3_HI  = 5'd20;

    reg [4:0]  state;
    reg        pending;

    // Latched data (stable during transmission)
    reg signed [31:0] lat_pos;
    reg signed [15:0] lat_sin, lat_cos;
    reg        [15:0] lat_amp;
    reg signed [15:0] lat_ch0, lat_ch1, lat_ch2, lat_ch3;

    always @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            tx_data      <= 0;
            tx_start     <= 1'b0;
            transmitting <= 1'b0;
            pending      <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            if (pos_valid) begin
                pending <= 1'b1;
                lat_pos <= position;
                lat_sin <= sin_val;
                lat_cos <= cos_val;
                lat_amp <= amplitude;
                lat_ch0 <= ch0_amp;
                lat_ch1 <= ch1_amp;
                lat_ch2 <= ch2_amp;
                lat_ch3 <= ch3_amp;
            end

            case (state)
                S_IDLE: begin
                    transmitting <= 1'b0;
                    if (pending) begin
                        pending      <= 1'b0;
                        transmitting <= 1'b1;
                        state        <= S_SYNC0;
                    end
                end

                S_SYNC0: if (!tx_busy) begin
                    tx_data <= 8'hAA; tx_start <= 1'b1; state <= S_SYNC1;
                end
                S_SYNC1: if (!tx_busy && !tx_start) begin
                    tx_data <= 8'h55; tx_start <= 1'b1; state <= S_POS_0;
                end

                S_POS_0: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_pos[7:0]; tx_start <= 1'b1; state <= S_POS_1;
                end
                S_POS_1: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_pos[15:8]; tx_start <= 1'b1; state <= S_POS_2;
                end
                S_POS_2: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_pos[23:16]; tx_start <= 1'b1; state <= S_POS_3;
                end
                S_POS_3: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_pos[31:24]; tx_start <= 1'b1;
                    state <= (mode == 8'd2) ? S_SIN_LO : S_IDLE;
                end

                // Diagnostics mode (mode 2)
                S_SIN_LO: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_sin[7:0]; tx_start <= 1'b1; state <= S_SIN_HI;
                end
                S_SIN_HI: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_sin[15:8]; tx_start <= 1'b1; state <= S_COS_LO;
                end
                S_COS_LO: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_cos[7:0]; tx_start <= 1'b1; state <= S_COS_HI;
                end
                S_COS_HI: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_cos[15:8]; tx_start <= 1'b1; state <= S_AMP_LO;
                end
                S_AMP_LO: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_amp[7:0]; tx_start <= 1'b1; state <= S_AMP_HI;
                end
                S_AMP_HI: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_amp[15:8]; tx_start <= 1'b1; state <= S_CH0_LO;
                end

                // Per-channel amplitudes
                S_CH0_LO: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_ch0[7:0]; tx_start <= 1'b1; state <= S_CH0_HI;
                end
                S_CH0_HI: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_ch0[15:8]; tx_start <= 1'b1; state <= S_CH1_LO;
                end
                S_CH1_LO: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_ch1[7:0]; tx_start <= 1'b1; state <= S_CH1_HI;
                end
                S_CH1_HI: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_ch1[15:8]; tx_start <= 1'b1; state <= S_CH2_LO;
                end
                S_CH2_LO: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_ch2[7:0]; tx_start <= 1'b1; state <= S_CH2_HI;
                end
                S_CH2_HI: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_ch2[15:8]; tx_start <= 1'b1; state <= S_CH3_LO;
                end
                S_CH3_LO: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_ch3[7:0]; tx_start <= 1'b1; state <= S_CH3_HI;
                end
                S_CH3_HI: if (!tx_busy && !tx_start) begin
                    tx_data <= lat_ch3[15:8]; tx_start <= 1'b1; state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
