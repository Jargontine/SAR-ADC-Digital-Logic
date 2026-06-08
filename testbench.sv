`timescale 1ns/1ps

module tb_sar_dig_logic;

parameter CLK_PERIOD = 125; // 8 MHz
parameter CLK_DIV    = 8;   // change to test different speeds:
                            // 8=1MHz, 4=2MHz, 2=4MHz, 16=500kHz

//DUT signals
reg  sar_adc_dig_clk_vdd, sar_pdnb_vdd, sar_cmp_out_vdd;

wire sarclk_cds_vref_vdd, sar_comp_pdnb_vdd;
wire sar_cmp_cdsamp1_vdd, sar_cmp_cdsamp2_vdd, sar_cmp_cdsamp3_vdd;
wire sar_dac_sampvcm_vdd;
wire sar_BclK;
wire [11:0] sar_vrefset_bit_vdd;
wire sar_cmp_clk_vdd, sar_cmp_ltch_disable_vdd, sar_data_samp;
wire sar_smp_unitcap_vdd;
wire [11:0] dac_pcode, dac_ncode, adc_out;

//DUT
sar_dig_logic #(.CLK_DIV(CLK_DIV)) dut (
    .sar_adc_dig_clk_vdd     (sar_adc_dig_clk_vdd),
    .sar_pdnb_vdd            (sar_pdnb_vdd),
    .sar_cmp_out_vdd         (sar_cmp_out_vdd),
    .sarclk_cds_vref_vdd     (sarclk_cds_vref_vdd),
    .sar_comp_pdnb_vdd       (sar_comp_pdnb_vdd),
    .sar_cmp_cdsamp1_vdd     (sar_cmp_cdsamp1_vdd),
    .sar_cmp_cdsamp2_vdd     (sar_cmp_cdsamp2_vdd),
    .sar_cmp_cdsamp3_vdd     (sar_cmp_cdsamp3_vdd),
    .sar_dac_sampvcm_vdd     (sar_dac_sampvcm_vdd),
    .sar_BclK                (sar_BclK),
    .sar_vrefset_bit_vdd     (sar_vrefset_bit_vdd),
    .sar_cmp_clk_vdd         (sar_cmp_clk_vdd),
    .sar_cmp_ltch_disable_vdd(sar_cmp_ltch_disable_vdd),
    .sar_data_samp           (sar_data_samp),
    .sar_smp_unitcap_vdd     (sar_smp_unitcap_vdd),
    .dac_pcode               (dac_pcode),
    .dac_ncode               (dac_ncode),
    .adc_out                 (adc_out)
);

//Clock
initial sar_adc_dig_clk_vdd = 0;
always #(CLK_PERIOD/2) sar_adc_dig_clk_vdd = ~sar_adc_dig_clk_vdd;

//cmp_out pattern control
// 0 = fixed LOW, 1 = fixed HIGH, 2 = alternating
reg [1:0] test_mode;
reg       alt_cmp; // alternates on each data_samp falling edge

// Alternating cmp_out — flips every time data_samp falls
// alt_cmp is explicitly cleared in do_reset to prevent corruption
// from spurious falling edges caused by reset firing mid-conversion
always @(negedge sar_data_samp or negedge sar_pdnb_vdd) begin
    if (!sar_pdnb_vdd)
        alt_cmp <= 0;
    else
        alt_cmp <= ~alt_cmp;
end

// Drive cmp_out based on test mode
always @(*) begin
    case (test_mode)
        2'd0: sar_cmp_out_vdd = 1'b0; // always 0 → all bits should be 1
        2'd1: sar_cmp_out_vdd = 1'b1; // always 1 → all bits should be 0
        2'd2: sar_cmp_out_vdd = alt_cmp; // alternating 0,1,0,1
        default: sar_cmp_out_vdd = 1'b0;
    endcase
end

//Waveform dump
initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_sar_dig_logic);
end

//Conversion wait task
// Startup=20µs + conversion=120µs = 140µs
// At 8MHz: 140µs = 1120 cycles. Use CLK_DIV*300 for margin at all speeds.
task wait_conversion;
    repeat(CLK_DIV * 300) @(posedge sar_adc_dig_clk_vdd);
endtask

task do_reset;
    sar_pdnb_vdd = 0;
    // Wait long enough for any in-progress data_samp pulse to complete
    // before releasing reset, so no spurious negedge fires on data_samp
    // that would corrupt alt_cmp state
    repeat(CLK_DIV * 20) @(posedge sar_adc_dig_clk_vdd);
    sar_pdnb_vdd = 1;
    // Explicitly clear alt_cmp after reset regardless of timing
    // Root cause: when reset fires mid-conversion, sar_data_samp may be HIGH
    // The reset forces it LOW creating a spurious falling edge
    // that flips alt_cmp before Test 3 begins
    alt_cmp = 0;
    $display("[%0t ns] Reset released (CLK_DIV=%0d)", $time/1000, CLK_DIV);
endtask

//Main test
integer pass_count, fail_count;

initial begin
    sar_pdnb_vdd = 0;
    test_mode    = 0;
    pass_count   = 0;
    fail_count   = 0;

    $display("  SAR ADC — 3 Verification Tests");
    $display("  CLK_DIV = %0d", CLK_DIV);

    // TEST 1: cmp_out = always 0
    // Expected: all bits = 1, adc_out = 0xFFF = 111111111111
    // data=0 → bit=1 → keep pcode HIGH for every bit
    $display("--- TEST 1: cmp_out always 0 ---");
    $display("  Expected: adc_out = 111111111111 (0xFFF)");
    $display("  Reason: data=0 -> bit=1 -> all bits kept HIGH");
    test_mode = 2'd0;
    do_reset;
    wait_conversion;
    $display("  Result:   adc_out = %b (0x%03X)", adc_out, adc_out);
    if (adc_out === 12'hFFF) begin
        $display("  PASS\n"); pass_count = pass_count + 1;
    end else begin
        $display("  FAIL (got 0x%03X, expected 0xFFF)\n", adc_out);
        fail_count = fail_count + 1;
    end

    // TEST 2: cmp_out = always 1
    // Expected: all bits = 0, adc_out = 0x000 = 000000000000
    // data=1 → bit=0 → clear pcode for every bit
    $display("--- TEST 2: cmp_out always 1 ---");
    $display("  Expected: adc_out = 000000000000 (0x000)");
    $display("  Reason: data=1 -> bit=0 -> all bits cleared");
    test_mode = 2'd1;
    do_reset;
    wait_conversion;
    $display("  Result:   adc_out = %b (0x%03X)", adc_out, adc_out);
    if (adc_out === 12'h000) begin
        $display("  PASS\n"); pass_count = pass_count + 1;
    end else begin
        $display("  FAIL (got 0x%03X, expected 0x000)\n", adc_out);
        fail_count = fail_count + 1;
    end

    // TEST 3: cmp_out alternating 0,1,0,1,0,1,0,1,0,1,0,1
    // Expected: bits 1,0,1,0,1,0,1,0,1,0,1,0
    // adc_out = 101010101010 = 0xAAA
    $display("TEST 3: cmp_out alternating 0,1,0,1");
    $display("  Expected: adc_out = 101010101010 (0xAAA)");
    $display("  Reason: cmp_out=0->bit=1, cmp_out=1->bit=0, alternating");
    test_mode = 2'd2;
    do_reset;
    wait_conversion;
    $display("  Result:   adc_out = %b (0x%03X)", adc_out, adc_out);
    if (adc_out === 12'hAAA) begin
        $display("  PASS\n"); pass_count = pass_count + 1;
    end else begin
        $display("  FAIL (got 0x%03X, expected 0xAAA)\n", adc_out);
        fail_count = fail_count + 1;
    end

    // SUMMARY
    $display("  PASSED: %0d / 3", pass_count);
    $display("  FAILED: %0d / 3", fail_count);
    if (fail_count == 0)
        $display("  ALL 3 TESTS PASSED");
    else
        $display("  SOME TESTS FAILED");

    #1000; $finish;
end

// Per-sample monitor
always @(negedge sar_data_samp) begin
    $display("  [%0t ns] Sample b%0d: cmp_out=%b -> bit=%b | pcode=%b",
             $time/1000, 11-dut.bit_idx, sar_cmp_out_vdd, ~sar_cmp_out_vdd, dac_pcode);
end

endmodule
