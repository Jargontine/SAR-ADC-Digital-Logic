`timescale 1ns/1ps

module tb_sar_dig_logic;

parameter CLK_PERIOD = 125; // 8 MHz for ease of division 
parameter CLK_DIV    = 8;

// DUT signals
reg  master_clk, sar_pdnb, sar_cmp_out;

wire sarclk_cds_vref, sar_cmp_pdnb;
wire sar_cmp_cdsamp1, sar_cmp_cdsamp2, sar_cmp_cdsamp3;
wire sar_dac_smp_vcm;
wire sar_BclK;
wire [11:0] sar_Vrefset;
wire sar_cmp_clk, sar_cmp_ltch_disable, sar_data_samp;
wire sar_smp_unitcap;
wire [11:0] dac_pcode, dac_ncode, adc_out;

// DUT
sar_dig_logic #(.CLK_DIV(CLK_DIV)) dut (
    .master_clk             (master_clk),
    .sar_pdnb               (sar_pdnb),
    .sar_cmp_out            (sar_cmp_out),
    .sarclk_cds_vref        (sarclk_cds_vref),
    .sar_cmp_pdnb          (sar_cmp_pdnb),
    .sar_cmp_cdsamp1         (sar_cmp_cdsamp1),
    .sar_cmp_cdsamp2         (sar_cmp_cdsamp2),
    .sar_cmp_cdsamp3         (sar_cmp_cdsamp3),
    .sar_dac_smp_vcm         (sar_dac_smp_vcm),
    .sar_BclK               (sar_BclK),
    .sar_Vrefset            (sar_Vrefset),
    .sar_cmp_clk            (sar_cmp_clk),
    .sar_cmp_ltch_disable   (sar_cmp_ltch_disable),
    .sar_data_samp          (sar_data_samp),
    .sar_smp_unitcap        (sar_smp_unitcap),
    .dac_pcode              (dac_pcode),
    .dac_ncode              (dac_ncode),
    .adc_out                (adc_out)
);

// Clock
initial master_clk = 0;
always #(CLK_PERIOD/2) master_clk = ~master_clk;

//cmp_out pattern control
// 0 = fixed LOW, 1 = fixed HIGH, 2 = alternating
reg [1:0] test_mode;
reg       alt_cmp; // alternates on each data_samp falling edge

// Alternating cmp_out — flips every time data_samp falls
always @(negedge sar_data_samp or negedge sar_pdnb) begin
    if (!sar_pdnb)
        alt_cmp <= 0;
    else
        alt_cmp <= ~alt_cmp;
end

// Drive cmp_out based on test mode
always @(*) begin
    case (test_mode)
        2'd0: sar_cmp_out = 1'b0; // always 0 → all bits should be 1
        2'd1: sar_cmp_out = 1'b1; // always 1 → all bits should be 0
        2'd2: sar_cmp_out = alt_cmp; // alternating 0,1,0,1
        default: sar_cmp_out = 1'b0;
    endcase
end

//Waveform dump
initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_sar_dig_logic);
end

//Conversion wait task
// Startup=20µs + conversion=120µs = 140µs
// At 8MHz: 140µs = 1120 cycles. Use 2000 for safety.
task wait_conversion;
    repeat(2000) @(posedge master_clk);
endtask

task do_reset;
    sar_pdnb = 0;
    repeat(20) @(posedge master_clk);
    sar_pdnb = 1;
    $display("[%0t ns] Reset released", $time/1000);
endtask

//Main test
integer pass_count, fail_count;

initial begin
    sar_pdnb   = 0;
    test_mode  = 0;
    pass_count = 0;
    fail_count = 0;

  $display("  SAR ADC: The 3 Verification Tests");

    // TEST 1: cmp_out = always 0
    // Expected: all bits = 1, adc_out = 0xFFF = 111111111111
    //data=0 → bit=1 → keep pcode HIGH for every bit
    $display("--- TEST 1: cmp_out always 0 ---");
    $display("  Expected: adc_out = 111111111111 (0xFFF)");
    $display("  Reason: data=0 → bit=1 → all bits kept HIGH");
    test_mode = 2'd0;
    do_reset;
    wait_conversion;

    $display("  Result:   adc_out = %b (0x%03X)", adc_out, adc_out);
    if (adc_out === 12'hFFF) begin
        $display("  PASS ✓\n"); pass_count = pass_count + 1;
    end else begin
        $display("  FAIL ✗ (got 0x%03X, expected 0xFFF)\n", adc_out);
        fail_count = fail_count + 1;
    end

    // TEST 2: cmp_out = always 1
    // Expected: all bits = 0, adc_out = 0x000 = 000000000000
    // data=1 → bit=0 → clear pcode for every bit
    $display("--- TEST 2: cmp_out always 1 ---");
    $display("  Expected: adc_out = 000000000000 (0x000)");
    $display("  Reason: data=1 → bit=0 → all bits cleared");
    test_mode = 2'd1;
    do_reset;
    wait_conversion;

    $display("  Result:   adc_out = %b (0x%03X)", adc_out, adc_out);
    if (adc_out === 12'h000) begin
        $display("  PASS ✓\n"); pass_count = pass_count + 1;
    end else begin
        $display("  FAIL ✗ (got 0x%03X, expected 0x000)\n", adc_out);
        fail_count = fail_count + 1;
    end

    // TEST 3: cmp_out alternating 0,1,0,1,0,1,0,1,0,1,0,1
    // Expected: bits 1,0,1,0,1,0,1,0,1,0,1,0
    //           adc_out = 101010101010 = 0xAAA
    $display("--- TEST 3: cmp_out alternating 0,1,0,1 ---");
    $display("  Expected: adc_out = 101010101010 (0xAAA)");
    $display("  Reason: cmp_out=0→bit=1, cmp_out=1→bit=0, alternating");
    test_mode = 2'd2;
    do_reset;
    wait_conversion;

    $display("  Result:   adc_out = %b (0x%03X)", adc_out, adc_out);
    if (adc_out === 12'hAAA) begin
      $display("  PASS :D\n"); pass_count = pass_count + 1;
    end else begin
      $display("  FAIL :(\n", adc_out);
        fail_count = fail_count + 1;
    end


    // SUMMARY
    $display("  PASSED: %0d / 3", pass_count);
    $display("  FAILED: %0d / 3", fail_count);
    if (fail_count == 0)
      $display("  ALL 3 TESTS PASSED :D");
    else
      $display("  SOME TESTS FAILED :( ");

    #1000; $finish;
end

// Per-sample monitor
always @(negedge sar_data_samp) begin
    $display("  [%0t ns] Sample b%0d: cmp_out=%b → bit=%b | pcode=%b",
             $time/1000, 11-dut.bit_idx, sar_cmp_out, ~sar_cmp_out, dac_pcode);
end

endmodule 
