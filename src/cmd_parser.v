// cmd_parser.v — Command parser for capacitive encoder
//
// Commands:
//   EX (4 bytes): 'E' 'X' + freq_div[2 BE]
//   MD (4 bytes): 'M' 'D' + mode[1] + avg_count[1]
//   ZR (2 bytes): 'Z' 'R' — zero position
//
// Same byte-buffer state machine pattern as tcd1254-fpga cmd_parser.

module cmd_parser (
    input  wire       clk,
    input  wire       rst,

    // From uart_rx
    input  wire [7:0] rx_data,
    input  wire       rx_valid,

    // EX command outputs
    output reg [15:0] freq_div,
    output reg        ex_cmd_valid,    // Pulse on new EX command

    // MD command outputs
    output reg [7:0]  mode,            // 1=position, 2=diagnostics, 3=raw
    output reg [7:0]  avg_count,       // 1-255
    output reg        md_cmd_valid,    // Pulse on new MD command

    // ZR command output
    output reg        zero_cmd         // Pulse on zero command
);

    // Receive buffer — large enough for longest command (4 bytes)
    reg [7:0] cbuf [0:3];
    reg [2:0] byte_idx;

    // Track command type
    localparam CMD_NONE = 2'd0,
               CMD_EX   = 2'd1,   // 'EX' — 4 bytes
               CMD_MD   = 2'd2,   // 'MD' — 4 bytes
               CMD_ZR   = 2'd3;   // 'ZR' — 2 bytes

    reg [1:0] cmd_type;

    always @(posedge clk) begin
        if (rst) begin
            byte_idx     <= 0;
            cmd_type     <= CMD_NONE;
            freq_div     <= 16'd400;     // Default 200 kHz
            mode         <= 8'd1;        // Position mode
            avg_count    <= 8'd16;       // 16 samples
            ex_cmd_valid <= 1'b0;
            md_cmd_valid <= 1'b0;
            zero_cmd     <= 1'b0;
        end else begin
            ex_cmd_valid <= 1'b0;
            md_cmd_valid <= 1'b0;
            zero_cmd     <= 1'b0;

            if (rx_valid) begin
                if (byte_idx == 0) begin
                    // First byte — detect command type
                    if (rx_data == 8'h45) begin        // 'E'
                        cbuf[0]  <= rx_data;
                        byte_idx <= 1;
                        cmd_type <= CMD_EX;
                    end else if (rx_data == 8'h4D) begin // 'M'
                        cbuf[0]  <= rx_data;
                        byte_idx <= 1;
                        cmd_type <= CMD_MD;
                    end else if (rx_data == 8'h5A) begin // 'Z'
                        cbuf[0]  <= rx_data;
                        byte_idx <= 1;
                        cmd_type <= CMD_ZR;
                    end
                    // else: unrecognized, stay at 0
                end else if (byte_idx == 1) begin
                    // Second byte — verify command header
                    if (cmd_type == CMD_EX && rx_data == 8'h58) begin  // 'X'
                        cbuf[1]  <= rx_data;
                        byte_idx <= 2;
                    end else if (cmd_type == CMD_MD && rx_data == 8'h44) begin // 'D'
                        cbuf[1]  <= rx_data;
                        byte_idx <= 2;
                    end else if (cmd_type == CMD_ZR && rx_data == 8'h52) begin // 'R'
                        // ZR is only 2 bytes — complete
                        byte_idx <= 0;
                        cmd_type <= CMD_NONE;
                        zero_cmd <= 1'b1;
                    end else if (rx_data == 8'h45) begin
                        // Could be new 'E' — restart
                        cbuf[0]  <= rx_data;
                        byte_idx <= 1;
                        cmd_type <= CMD_EX;
                    end else if (rx_data == 8'h4D) begin
                        cbuf[0]  <= rx_data;
                        byte_idx <= 1;
                        cmd_type <= CMD_MD;
                    end else if (rx_data == 8'h5A) begin
                        cbuf[0]  <= rx_data;
                        byte_idx <= 1;
                        cmd_type <= CMD_ZR;
                    end else begin
                        byte_idx <= 0;
                        cmd_type <= CMD_NONE;
                    end
                end else begin
                    cbuf[byte_idx] <= rx_data;

                    if (cmd_type == CMD_EX && byte_idx == 3) begin
                        // Full EX command: bytes 2-3 = freq_div BE
                        byte_idx <= 0;
                        cmd_type <= CMD_NONE;
                        freq_div <= {cbuf[2], rx_data};
                        ex_cmd_valid <= 1'b1;
                    end else if (cmd_type == CMD_MD && byte_idx == 3) begin
                        // Full MD command: byte 2 = mode, byte 3 = avg
                        byte_idx <= 0;
                        cmd_type <= CMD_NONE;
                        mode      <= cbuf[2];
                        avg_count <= (rx_data > 0) ? rx_data : 8'd1;
                        md_cmd_valid <= 1'b1;
                    end else begin
                        byte_idx <= byte_idx + 1;
                    end
                end
            end
        end
    end

endmodule
