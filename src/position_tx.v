// position_tx.v — UART serialization for position/diagnostics data
//
// Three modes:
//   Mode 1 (6B):  0xAA 0x55 + position[4B LE signed]
//   Mode 2 (12B): 0xAA 0x55 + position[4B] + sin[2B] + cos[2B] + amplitude[2B]
//   Mode 3:       Raw ADC stream (debug) — not yet implemented
//
// Same tx_data/tx_start/tx_busy interface to uart_tx as frame_tx.v

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

    // UART TX interface
    output reg  [7:0]  tx_data,
    output reg         tx_start,
    input  wire        tx_busy,

    // Status
    output reg         transmitting
);

    localparam S_IDLE    = 4'd0,
               S_SYNC0   = 4'd1,
               S_SYNC1   = 4'd2,
               S_POS_0   = 4'd3,   // position[7:0]
               S_POS_1   = 4'd4,   // position[15:8]
               S_POS_2   = 4'd5,   // position[23:16]
               S_POS_3   = 4'd6,   // position[31:24]
               S_SIN_LO  = 4'd7,
               S_SIN_HI  = 4'd8,
               S_COS_LO  = 4'd9,
               S_COS_HI  = 4'd10,
               S_AMP_LO  = 4'd11,
               S_AMP_HI  = 4'd12;

    reg [3:0]  state;
    reg        pending;

    // Latched data (stable during transmission)
    reg signed [31:0] lat_pos;
    reg signed [15:0] lat_sin, lat_cos;
    reg        [15:0] lat_amp;

    always @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            tx_data      <= 0;
            tx_start     <= 1'b0;
            transmitting <= 1'b0;
            pending      <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            // Latch pending position
            if (pos_valid) begin
                pending <= 1'b1;
                lat_pos <= position;
                lat_sin <= sin_val;
                lat_cos <= cos_val;
                lat_amp <= amplitude;
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

                S_SYNC0: begin
                    if (!tx_busy) begin
                        tx_data  <= 8'hAA;
                        tx_start <= 1'b1;
                        state    <= S_SYNC1;
                    end
                end

                S_SYNC1: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= 8'h55;
                        tx_start <= 1'b1;
                        state    <= S_POS_0;
                    end
                end

                S_POS_0: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= lat_pos[7:0];
                        tx_start <= 1'b1;
                        state    <= S_POS_1;
                    end
                end

                S_POS_1: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= lat_pos[15:8];
                        tx_start <= 1'b1;
                        state    <= S_POS_2;
                    end
                end

                S_POS_2: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= lat_pos[23:16];
                        tx_start <= 1'b1;
                        state    <= S_POS_3;
                    end
                end

                S_POS_3: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= lat_pos[31:24];
                        tx_start <= 1'b1;
                        if (mode == 8'd2)
                            state <= S_SIN_LO;
                        else
                            state <= S_IDLE;
                    end
                end

                // Diagnostics mode (mode 2) — additional fields
                S_SIN_LO: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= lat_sin[7:0];
                        tx_start <= 1'b1;
                        state    <= S_SIN_HI;
                    end
                end

                S_SIN_HI: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= lat_sin[15:8];
                        tx_start <= 1'b1;
                        state    <= S_COS_LO;
                    end
                end

                S_COS_LO: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= lat_cos[7:0];
                        tx_start <= 1'b1;
                        state    <= S_COS_HI;
                    end
                end

                S_COS_HI: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= lat_cos[15:8];
                        tx_start <= 1'b1;
                        state    <= S_AMP_LO;
                    end
                end

                S_AMP_LO: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= lat_amp[7:0];
                        tx_start <= 1'b1;
                        state    <= S_AMP_HI;
                    end
                end

                S_AMP_HI: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= lat_amp[15:8];
                        tx_start <= 1'b1;
                        state    <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
