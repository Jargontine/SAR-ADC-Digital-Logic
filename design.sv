// SAR ADC Digital Controller for temperature sensor: Pramod Gururajan 

`timescale 1ns/1ps

module sar_dig_logic (
    input  wire        master_clk,
    input  wire        sar_pdnb,
    input  wire        sar_cmp_out,

    // Startup outputs
    output reg         sarclk_cds_vref,
    output reg         sar_cmp_pdnb,
    output reg         sar_cmp_cdsamp1,
    output reg         sar_cmp_cdsamp2,
    output reg         sar_cmp_cdsamp3,
    output reg         sar_dac_smp_vcm,

    // Conversion outputs
    output reg         sar_BclK,
    output reg  [11:0] sar_Vrefset,
    output reg         sar_cmp_clk,
    output reg         sar_cmp_ltch_disable,
    output reg         sar_data_samp,
    output reg         sar_smp_unitcap,
    output reg  [11:0] dac_pcode,
    output reg  [11:0] dac_ncode,
    output reg  [11:0] adc_out
);

// Parameters
parameter CLK_DIV = 8; // these can be changed for different divisions: 8=1MHz, 4=2MHz, 						16=500kHz, 2=4MHz

localparam BCLK_PERIOD = 10;
localparam BCLK_HALF   = 5;
localparam CMP_CLK_ON  = 5;
localparam CMP_CLK_DUR = 3;
localparam LTCH_ON     = 6;
localparam DSAMP_ON    = 7;
localparam SAMPLE_TICK = 8;

  // Startup timing (ref_ticks in µs)
localparam STARTUP_DELAY    = 5;  // wait 5µs after pdnb before sarclk rises
localparam SARCLK_DUR       = 5;  // sarclk_cds_vref is high for 5µs
localparam CDACP1_DUR       = 7;  // cdsamp1 is high for 7µs from group rise
localparam CDACP2_DUR       = 8;
localparam CDACP3_DUR       = 9;
localparam SMPCVM_DUR       = 10;

// Clock divider
reg [4:0] clk_cnt;
reg       ref_tick;

always @(posedge master_clk or negedge sar_pdnb) begin
    if (!sar_pdnb) begin
        clk_cnt  <= 0;
        ref_tick <= 0;
    end else begin
        if (clk_cnt == CLK_DIV - 1) begin
            clk_cnt  <= 0;
            ref_tick <= 1;
        end else begin
            clk_cnt  <= clk_cnt + 1;
            ref_tick <= 0;
        end
    end
end

//  State machine 
// States
localparam ST_IDLE     = 3'd0; // waiting for pdnb
localparam ST_DELAY    = 3'd1; // 5µs delay after pdnb
localparam ST_SARCLK   = 3'd2; // sarclk_cds_vref pulse
localparam ST_SAMPLE   = 3'd3; // analog sampling phase
localparam ST_CONVERT  = 3'd4; // SAR conversion

reg [2:0]  state;
reg [4:0]  startup_cnt; // counts µs during startup
reg [3:0]  bit_idx;
reg [3:0]  tick;
reg        cmp_sampled;

always @(posedge master_clk or negedge sar_pdnb) begin
    if (!sar_pdnb) begin
        state                <= ST_IDLE;
        startup_cnt          <= 0;
        bit_idx              <= 0;
        tick                 <= 0;
        cmp_sampled          <= 0;
        sarclk_cds_vref      <= 0;
        sar_cmp_pdnb        <= 0;
        sar_cmp_cdsamp1       <= 0;
        sar_cmp_cdsamp2       <= 0;
        sar_cmp_cdsamp3       <= 0;
        sar_dac_smp_vcm       <= 0;
        sar_BclK             <= 0;
        sar_Vrefset          <= 0;
        sar_cmp_clk          <= 0;
        sar_cmp_ltch_disable <= 0;
        sar_data_samp        <= 0;
        sar_smp_unitcap      <= 0;
        dac_pcode            <= 0;
        dac_ncode            <= 0;
        adc_out              <= 0;
    end
    else if (ref_tick) begin

        case (state)

        // ST_IDLE: pdnb just went HIGH, start delay
        ST_IDLE: begin
            startup_cnt <= 0;
            state       <= ST_DELAY;
        end

        // ST_DELAY: wait 5µs before sarclk rises
        ST_DELAY: begin
            startup_cnt <= startup_cnt + 1;
            if (startup_cnt == STARTUP_DELAY - 1) begin
                sarclk_cds_vref <= 1; // rise at t=5µs
                startup_cnt     <= 0;
                state           <= ST_SARCLK;
            end
        end

        // ST_SARCLK: sarclk HIGH for 5µs, then sampling group rises
        ST_SARCLK: begin
            startup_cnt <= startup_cnt + 1;
            if (startup_cnt == SARCLK_DUR - 1) begin
                // sarclk falls, all sampling signals rise together
                sarclk_cds_vref <= 0;
                sar_cmp_pdnb   <= 1;
                sar_cmp_cdsamp1  <= 1;
                sar_cmp_cdsamp2  <= 1;
                sar_cmp_cdsamp3  <= 1;
                sar_dac_smp_vcm  <= 1;
                startup_cnt     <= 0;
                state           <= ST_SAMPLE;
            end
        end

        // ST_SAMPLE: sampling phase, each signal falls at its time
        ST_SAMPLE: begin
            startup_cnt <= startup_cnt + 1;

            // cdsamp1 falls at +7µs
            if (startup_cnt == CDACP1_DUR - 1)
                sar_cmp_cdsamp1 <= 0;

            // cdsamp2 falls at +8µs
            if (startup_cnt == CDACP2_DUR - 1)
                sar_cmp_cdsamp2 <= 0;

            // cdsamp3 falls at +9µs
            if (startup_cnt == CDACP3_DUR - 1)
                sar_cmp_cdsamp3 <= 0;

            // Vcm and SmpVin fall at +10µs: BclK starts
            if (startup_cnt == SMPCVM_DUR - 1) begin
                sar_dac_smp_vcm  <= 0;
                // Start conversion
                sar_smp_unitcap <= 1;
                sar_BclK        <= 1;
                // Assert Vrefset b11 immediately with BclK
                sar_Vrefset     <= 12'b1000_0000_0000;
                dac_pcode       <= 12'b1000_0000_0000;
                dac_ncode       <= 12'b0111_1111_1111;
                bit_idx         <= 0;
                tick            <= 0;
                state           <= ST_CONVERT;
            end
        end

        // ST_CONVERT: 12-bit SAR conversion
        ST_CONVERT: begin

            // Advance tick
            if (tick == BCLK_PERIOD - 1)
                tick <= 0;
            else
                tick <= tick + 1;

            // Tick 0: BclK rises, Vrefset asserts current bit
            if (tick == 0) begin
                sar_BclK              <= 1;
                sar_Vrefset           <= 12'd1 << (11 - bit_idx);
                dac_pcode[11-bit_idx] <= 1;
            end

            // Tick 5: BclK falls, cmp_clk rises
            if (tick == CMP_CLK_ON) begin
                sar_BclK    <= 0;
                sar_cmp_clk <= 1;
            end

            // Tick 6: ltch_disable rises
            if (tick == LTCH_ON)
                sar_cmp_ltch_disable <= 1;

            // Tick 7: data_samp rises
            if (tick == DSAMP_ON)
                sar_data_samp <= 1;

            // Tick 8: ALL FALL — sample point
            if (tick == SAMPLE_TICK) begin
                sar_cmp_clk          <= 0;
                sar_cmp_ltch_disable <= 0;
                sar_data_samp        <= 0;
                cmp_sampled          <= sar_cmp_out;

                if (sar_cmp_out == 1) begin
                    dac_pcode[11-bit_idx] <= 0;
                    dac_ncode[11-bit_idx] <= 1;
                end else begin
                    dac_pcode[11-bit_idx] <= 1;
                    dac_ncode[11-bit_idx] <= 0;
                end
            end

            // Tick 9: prepare next bit
            // KEY FIX: Vrefset for NEXT bit is asserted here
            // so there is NO gap, it transitions directly
            if (tick == BCLK_PERIOD - 1) begin
                if (bit_idx == 11) begin
                    // Conversion complete
                    adc_out         <= dac_pcode;
                    sar_Vrefset     <= 12'd0;
                    // Immediately restart
                    bit_idx         <= 0;
                    dac_pcode       <= 12'd0;
                    dac_ncode       <= 12'hFFF;
                end else begin
                    // Assert NEXT bit's Vrefset now (no gap)
                    sar_Vrefset <= 12'd1 << (11 - (bit_idx + 1));
                    bit_idx     <= bit_idx + 1;
                end
            end

        end // ST_CONVERT

        endcase
    end
end

endmodule
