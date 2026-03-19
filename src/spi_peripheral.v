// spi_peripheral.v — SPI slave interface for RP2040 ↔ FPGA communication
//
// Adapted for capacitive encoder. Register map:
//   0x10 = Write encoder config (freq_div[2] + mode[1] + avg[1])
//   0x03 = Read position (4B signed LE)
//   0x04 = Read diagnostics (sin[2] + cos[2] + amp[2] + angle[2])
//   0x20 = Trigger measurement
//   0x30 = Zero position
//   0xFE = Status register read

module spi_peripheral (
    input  wire        clk,       // System clock (80 MHz)
    input  wire        rst,

    // SPI pins
    input  wire        spi_sck,
    input  wire        spi_mosi,
    output wire        spi_miso,
    input  wire        spi_cs_n,

    // Register interface
    output reg  [7:0]  reg_addr,
    output reg  [7:0]  reg_wdata,
    output reg         reg_wr,
    input  wire [7:0]  reg_rdata,

    // Encoder config
    output reg         cmd_write_config, // Pulse: config written
    output reg         cmd_trigger,      // Pulse: trigger measurement
    output reg         cmd_zero,         // Pulse: zero position
    output reg  [31:0] enc_config,       // freq_div[16] + mode[8] + avg[8]

    // Status inputs
    input  wire        measuring,
    input  wire        pos_valid,
    input  wire signed [31:0] position,
    input  wire signed [15:0] sin_val,
    input  wire signed [15:0] cos_val,
    input  wire        [15:0] amplitude,
    input  wire        [11:0] angle
);

    // ---- Synchronize SPI signals to system clock ----
    reg [2:0] sck_sync;
    reg [1:0] mosi_sync;
    reg [1:0] cs_sync;

    always @(posedge clk) begin
        sck_sync  <= {sck_sync[1:0], spi_sck};
        mosi_sync <= {mosi_sync[0], spi_mosi};
        cs_sync   <= {cs_sync[0], spi_cs_n};
    end

    wire sck_rise = (sck_sync[2:1] == 2'b01);
    wire sck_fall = (sck_sync[2:1] == 2'b10);
    wire mosi_in  = mosi_sync[1];
    wire cs_active = !cs_sync[1];

    // ---- SPI shift register ----
    reg [7:0] shift_in;
    reg [7:0] shift_out;
    reg [2:0] bit_cnt;
    reg       byte_ready;

    assign spi_miso = cs_active ? shift_out[7] : 1'bz;

    always @(posedge clk) begin
        if (rst || !cs_active) begin
            bit_cnt    <= 0;
            byte_ready <= 0;
        end else begin
            byte_ready <= 0;
            if (sck_rise) begin
                shift_in <= {shift_in[6:0], mosi_in};
                bit_cnt  <= bit_cnt + 1;
                if (bit_cnt == 3'd7)
                    byte_ready <= 1;
            end
            if (sck_fall)
                shift_out <= {shift_out[6:0], 1'b0};
        end
    end

    // ---- Command state machine ----
    localparam ST_CMD       = 3'd0,
               ST_ADDR      = 3'd1,
               ST_WRITE     = 3'd2,
               ST_READ      = 3'd3,
               ST_CONFIG_RX = 3'd4,
               ST_READ_POS  = 3'd5,
               ST_READ_DIAG = 3'd6;

    reg [2:0] cmd_state;
    reg [7:0] current_cmd;
    reg [3:0] data_idx;
    reg [7:0] config_buf [0:3];

    always @(posedge clk) begin
        if (rst) begin
            cmd_state        <= ST_CMD;
            reg_wr           <= 0;
            cmd_write_config <= 0;
            cmd_trigger      <= 0;
            cmd_zero         <= 0;
        end else begin
            reg_wr           <= 0;
            cmd_write_config <= 0;
            cmd_trigger      <= 0;
            cmd_zero         <= 0;

            if (!cs_active) begin
                cmd_state <= ST_CMD;
            end else if (byte_ready) begin
                case (cmd_state)
                    ST_CMD: begin
                        current_cmd <= shift_in;
                        data_idx    <= 0;
                        case (shift_in)
                            8'h01: cmd_state <= ST_ADDR;
                            8'h02: cmd_state <= ST_ADDR;
                            8'h03: begin // Read position
                                shift_out <= position[7:0];
                                cmd_state <= ST_READ_POS;
                            end
                            8'h04: begin // Read diagnostics
                                shift_out <= sin_val[7:0];
                                cmd_state <= ST_READ_DIAG;
                            end
                            8'h10: begin // Write encoder config
                                cmd_state <= ST_CONFIG_RX;
                            end
                            8'h20: begin // Trigger measurement
                                cmd_trigger <= 1;
                            end
                            8'h30: begin // Zero position
                                cmd_zero <= 1;
                            end
                            8'hFE: begin // Status
                                shift_out <= {5'd0, pos_valid, measuring, 1'b0};
                                cmd_state <= ST_READ;
                            end
                            default: ;
                        endcase
                    end

                    ST_ADDR: begin
                        reg_addr <= shift_in;
                        if (current_cmd == 8'h01)
                            cmd_state <= ST_WRITE;
                        else
                            cmd_state <= ST_READ;
                    end

                    ST_WRITE: begin
                        reg_wdata <= shift_in;
                        reg_wr    <= 1;
                        reg_addr  <= reg_addr + 1;
                    end

                    ST_READ: begin
                        shift_out <= reg_rdata;
                        reg_addr  <= reg_addr + 1;
                    end

                    ST_CONFIG_RX: begin
                        config_buf[data_idx] <= shift_in;
                        data_idx <= data_idx + 1;
                        if (data_idx == 4'd3) begin
                            enc_config <= {config_buf[0], config_buf[1],
                                          config_buf[2], shift_in};
                            cmd_write_config <= 1;
                            cmd_state <= ST_CMD;
                        end
                    end

                    ST_READ_POS: begin
                        data_idx <= data_idx + 1;
                        case (data_idx)
                            4'd0: shift_out <= position[15:8];
                            4'd1: shift_out <= position[23:16];
                            4'd2: begin
                                shift_out <= position[31:24];
                                cmd_state <= ST_CMD;
                            end
                            default: cmd_state <= ST_CMD;
                        endcase
                    end

                    ST_READ_DIAG: begin
                        data_idx <= data_idx + 1;
                        case (data_idx)
                            4'd0: shift_out <= sin_val[15:8];
                            4'd1: shift_out <= cos_val[7:0];
                            4'd2: shift_out <= cos_val[15:8];
                            4'd3: shift_out <= amplitude[7:0];
                            4'd4: shift_out <= amplitude[15:8];
                            4'd5: shift_out <= angle[7:0];
                            4'd6: begin
                                shift_out <= {4'd0, angle[11:8]};
                                cmd_state <= ST_CMD;
                            end
                            default: cmd_state <= ST_CMD;
                        endcase
                    end

                    default: cmd_state <= ST_CMD;
                endcase
            end
        end
    end

endmodule
