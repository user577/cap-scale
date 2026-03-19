// top.v — Top-level integration for Cap-Scale capacitive linear encoder
// Target: Colorlight i9 v7.2 (LFE5U-45F-6BG381C)
//
// Signal flow:
//   pll → reset → excitation_gen → (TX pins, ADC_CLK) →
//   channel_mux → (MUX_SEL) → adc_capture → sync_demod →
//   position_calc → position_tx → uart_tx

module top (
    input  wire       CLK_25M,      // 25 MHz oscillator

    // ADC data D[11:0] — same pin sites as CCD project
    input  wire       ADC_D0,
    input  wire       ADC_D1,
    input  wire       ADC_D2,
    input  wire       ADC_D3,
    input  wire       ADC_D4,
    input  wire       ADC_D5,
    input  wire       ADC_D6,
    input  wire       ADC_D7,
    input  wire       ADC_D8,
    input  wire       ADC_D9,
    input  wire       ADC_D10,
    input  wire       ADC_D11,

    // ADC clock output
    output wire       ADC_CLK_PIN,  // Sample trigger → AD9226 clock

    // Excitation drive (reuse FM/SH pin sites)
    output wire       TX_POS_PIN,   // Was FM_PIN — positive excitation
    output wire       TX_NEG_PIN,   // Was SH_PIN — negative excitation

    // Analog mux select (reuse ICG + FLASH_0 pin sites)
    output wire [1:0] MUX_SEL,      // CD4052 address pins

    // UART
    output wire       UART_TX,
    input  wire       UART_RX,

    // SPI to RP2040
    input  wire       SPI_SCK,
    input  wire       SPI_MOSI,
    output wire       SPI_MISO,
    input  wire       SPI_CS_N,

    // LED (active-low)
    output wire       LED
);

    // ========== Parameters ==========
    localparam SYS_CLK_FREQ = 80_000_000;
    localparam BAUD_RATE    = 921_600;

    // ========== PLL ==========
    wire clk;
    wire pll_locked;

    pll pll_inst (
        .clk_25m(CLK_25M),
        .clk_sys(clk),
        .locked(pll_locked)
    );

    // ========== Power-on Reset ==========
    reg [7:0] rst_shift = 8'hFF;
    wire rst = rst_shift[7];

    always @(posedge clk) begin
        if (!pll_locked)
            rst_shift <= 8'hFF;
        else
            rst_shift <= {rst_shift[6:0], 1'b0};
    end

    // ========== ADC Data Bus ==========
    wire [11:0] adc_data_pins = {ADC_D11, ADC_D10, ADC_D9, ADC_D8,
                                  ADC_D7,  ADC_D6,  ADC_D5, ADC_D4,
                                  ADC_D3,  ADC_D2,  ADC_D1, ADC_D0};

    // 2-stage synchronizer
    reg [11:0] adc_data_sync1, adc_data;
    always @(posedge clk) begin
        adc_data_sync1 <= adc_data_pins;
        adc_data       <= adc_data_sync1;
    end

    // ========== Forward Declarations ==========
    wire        ex_cmd_valid;
    wire        md_cmd_valid;
    wire        zero_cmd;
    wire        spi_cmd_trigger;
    wire        spi_cmd_zero;
    wire        spi_cmd_write_config;
    wire [31:0] spi_enc_config;
    reg  [7:0]  current_mode;
    reg  [7:0]  current_avg;
    reg  [15:0] current_freq_div;

    // ========== Excitation Generator ==========
    wire tx_pos, tx_neg;
    wire demod_ref;
    wire sample_trigger;
    wire cycle_done;
    wire excitation_running;

    excitation_gen excite_inst (
        .clk(clk),
        .rst(rst),
        .enable(excitation_running),
        .freq_div(current_freq_div),
        .samples_per_hc(current_avg),
        .config_valid(ex_cmd_valid | spi_cmd_write_config),
        .tx_pos(tx_pos),
        .tx_neg(tx_neg),
        .demod_ref(demod_ref),
        .sample_trigger(sample_trigger),
        .cycle_done(cycle_done)
    );

    assign TX_POS_PIN  = tx_pos;
    assign TX_NEG_PIN  = tx_neg;
    assign ADC_CLK_PIN = sample_trigger;

    // ========== Channel Mux ==========
    wire [1:0] mux_sel_out;
    wire [1:0] channel_sel;
    wire       adc_enable;
    wire       all_channels_done;

    channel_mux mux_inst (
        .clk(clk),
        .rst(rst),
        .enable(excitation_running),
        .cycle_done(cycle_done),
        .settling_clocks(8'd0),  // Use default
        .config_valid(1'b0),
        .mux_sel(mux_sel_out),
        .channel_sel(channel_sel),
        .adc_enable(adc_enable),
        .all_channels_done(all_channels_done)
    );

    assign MUX_SEL = mux_sel_out;

    // ========== ADC Capture ==========
    wire [11:0] cap_sample_data;
    wire        cap_sample_valid;

    // Gate ADC capture with mux adc_enable
    wire gated_sample_trigger = sample_trigger & adc_enable;

    adc_capture adc_cap_inst (
        .clk(clk),
        .rst(rst),
        .adc_data(adc_data),
        .sample_valid(gated_sample_trigger),
        .sample_data(cap_sample_data),
        .sample_valid_out(cap_sample_valid)
    );

    // ========== Synchronous Demodulator ==========
    wire signed [15:0] ch0_amplitude, ch1_amplitude, ch2_amplitude, ch3_amplitude;
    wire               measurement_done;

    sync_demod demod_inst (
        .clk(clk),
        .rst(rst),
        .adc_data(cap_sample_data),
        .sample_valid(cap_sample_valid),
        .demod_ref(demod_ref),
        .channel_sel(channel_sel),
        .samples_per_ch(current_avg),
        .ch0_amplitude(ch0_amplitude),
        .ch1_amplitude(ch1_amplitude),
        .ch2_amplitude(ch2_amplitude),
        .ch3_amplitude(ch3_amplitude),
        .measurement_done(measurement_done)
    );

    // ========== Position Calculator ==========
    wire signed [31:0] position;
    wire signed [15:0] sin_val, cos_val;
    wire        [15:0] amp_val;
    wire        [11:0] angle_val;
    wire               pos_valid;

    position_calc calc_inst (
        .clk(clk),
        .rst(rst),
        .ch0_amp(ch0_amplitude),
        .ch1_amp(ch1_amplitude),
        .ch2_amp(ch2_amplitude),
        .ch3_amp(ch3_amplitude),
        .measurement_done(measurement_done),
        .zero_cmd(zero_cmd | spi_cmd_zero),
        .position(position),
        .sin_out(sin_val),
        .cos_out(cos_val),
        .amplitude(amp_val),
        .angle(angle_val),
        .pos_valid(pos_valid)
    );

    // ========== UART TX ==========
    wire       uart_tx_line;
    wire       uart_tx_busy;
    wire [7:0] uart_tx_data;
    wire       uart_tx_start;

    uart_tx #(
        .CLK_FREQ(SYS_CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_tx_inst (
        .clk(clk),
        .rst(rst),
        .data(uart_tx_data),
        .start(uart_tx_start),
        .tx(uart_tx_line),
        .busy(uart_tx_busy)
    );

    assign UART_TX = uart_tx_line;

    // ========== UART RX ==========
    wire [7:0] uart_rx_data;
    wire       uart_rx_valid;

    uart_rx #(
        .CLK_FREQ(SYS_CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_rx_inst (
        .clk(clk),
        .rst(rst),
        .rx(UART_RX),
        .data(uart_rx_data),
        .valid(uart_rx_valid)
    );

    // ========== Command Parser ==========
    wire [15:0] cmd_freq_div;
    wire [7:0]  cmd_mode;
    wire [7:0]  cmd_avg;

    cmd_parser cmd_inst (
        .clk(clk),
        .rst(rst),
        .rx_data(uart_rx_data),
        .rx_valid(uart_rx_valid),
        .freq_div(cmd_freq_div),
        .ex_cmd_valid(ex_cmd_valid),
        .mode(cmd_mode),
        .avg_count(cmd_avg),
        .md_cmd_valid(md_cmd_valid),
        .zero_cmd(zero_cmd)
    );

    // ========== Position TX ==========
    position_tx ptx_inst (
        .clk(clk),
        .rst(rst),
        .mode(current_mode),
        .pos_valid(pos_valid),
        .position(position),
        .sin_val(sin_val),
        .cos_val(cos_val),
        .amplitude(amp_val),
        .tx_data(uart_tx_data),
        .tx_start(uart_tx_start),
        .tx_busy(uart_tx_busy),
        .transmitting()
    );

    // ========== SPI Peripheral ==========
    wire [7:0] spi_reg_addr;
    wire [7:0] spi_reg_wdata;
    wire       spi_reg_wr;

    spi_peripheral spi_inst (
        .clk(clk),
        .rst(rst),
        .spi_sck(SPI_SCK),
        .spi_mosi(SPI_MOSI),
        .spi_miso(SPI_MISO),
        .spi_cs_n(SPI_CS_N),
        .reg_addr(spi_reg_addr),
        .reg_wdata(spi_reg_wdata),
        .reg_wr(spi_reg_wr),
        .reg_rdata(8'd0),
        .cmd_write_config(spi_cmd_write_config),
        .cmd_trigger(spi_cmd_trigger),
        .cmd_zero(spi_cmd_zero),
        .enc_config(spi_enc_config),
        .measuring(excitation_running),
        .pos_valid(pos_valid),
        .position(position),
        .sin_val(sin_val),
        .cos_val(cos_val),
        .amplitude(amp_val),
        .angle(angle_val)
    );

    // ========== Mode/Config Latch ==========
    always @(posedge clk) begin
        if (rst) begin
            current_mode     <= 8'd1;
            current_avg      <= 8'd16;
            current_freq_div <= 16'd400;
        end else if (spi_cmd_write_config) begin
            current_freq_div <= spi_enc_config[31:16];
            current_mode     <= spi_enc_config[15:8];
            current_avg      <= spi_enc_config[7:0];
        end else begin
            if (ex_cmd_valid)
                current_freq_div <= cmd_freq_div;
            if (md_cmd_valid) begin
                current_mode <= cmd_mode;
                current_avg  <= cmd_avg;
            end
        end
    end

    // ========== Auto-start ==========
    reg [3:0] auto_start_cnt;
    reg       auto_start_done;

    assign excitation_running = auto_start_done;

    always @(posedge clk) begin
        if (rst) begin
            auto_start_cnt  <= 0;
            auto_start_done <= 1'b0;
        end else begin
            if (!auto_start_done && auto_start_cnt < 4'd10) begin
                auto_start_cnt <= auto_start_cnt + 1;
                if (auto_start_cnt == 4'd9)
                    auto_start_done <= 1'b1;
            end
        end
    end

    // ========== LED Heartbeat ==========
    reg [25:0] heartbeat;
    always @(posedge clk) begin
        if (rst)
            heartbeat <= 0;
        else
            heartbeat <= heartbeat + 1;
    end

    // Solid when measuring, blink when idle (active-low LED)
    assign LED = excitation_running ? 1'b0 : heartbeat[25];

endmodule
