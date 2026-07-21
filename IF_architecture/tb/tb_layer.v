`timescale 1ns/1ps

module tb_layer;

    // parameters 
    parameter integer IN         = 784;
    parameter integer OUT        = 128;
    parameter integer PES        = 8;
    parameter integer DATA_WIDTH = 8;
    parameter integer ACC_WIDTH  = 16;
    parameter integer THRESHOLD  = 32;

    // DUT signals 
    reg         clk;
    reg         reset_n;
    reg         en;
    reg         clear;
    reg         neuron_en;
    reg [9:0]   col_addr;    // $clog2(784) = 10 bits
    reg [3:0]   active_pes;  // how many PEs valid this group
    reg [13:0]  base_addr;   // $clog2(784*16) = 14 bits

    reg [IN-1:0]  spikes_in;

    wire [PES-1:0] spikes_out;
    wire [PES-1:0] valid;

    // instantiate layer
    layer #(
        .IN         (IN),
        .OUT        (OUT),
        .PES        (PES),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .THRESHOLD  (THRESHOLD),
        .MEM_FILE0  ("mem/fc1_weights_bank0.mem"),
        .MEM_FILE1  ("mem/fc1_weights_bank1.mem"),
        .MEM_FILE2  ("mem/fc1_weights_bank2.mem"),
        .MEM_FILE3  ("mem/fc1_weights_bank3.mem"),
        .MEM_FILE4  ("mem/fc1_weights_bank4.mem"),
        .MEM_FILE5  ("mem/fc1_weights_bank5.mem"),
        .MEM_FILE6  ("mem/fc1_weights_bank6.mem"),
        .MEM_FILE7  ("mem/fc1_weights_bank7.mem")
    ) dut (
        .clk       (clk),
        .reset_n   (reset_n),
        .en        (en),
        .clear     (clear),
        .neuron_en (neuron_en),
        .col_addr  (col_addr),
        .active_pes(active_pes),
        .base_addr (base_addr),
        .spikes_in (spikes_in),
        .spikes_out(spikes_out),
        .valid     (valid)
    );

    // clock
    initial clk = 0;
    always #5 clk = ~clk;

    // loop variable 
    integer i;

    // task: run one full dot product (784 cycles)
    // simulates exactly what the controller does for one group
    task run_dot_product;
        input [13:0]    b_addr;     // base address for this group
        input [IN-1:0]  spikes;     // full 784-bit spike vector
        input [3:0]     num_pes;    // how many PEs are valid
        begin
            // load spike register and set base address
            @(negedge clk);
            spikes_in  = spikes;
            base_addr  = b_addr;
            active_pes = num_pes;
            clear      = 0;
            neuron_en  = 0;

            // one cycle BRAM latency — wait before asserting en
            @(posedge clk);
            @(negedge clk);

            // run 784 accumulation cycles
            en       = 1;
            col_addr = 0;

            repeat(IN) begin
                @(posedge clk);
                @(negedge clk);
                col_addr = col_addr + 1;
            end

            // drop en — valid will pulse on next cycle
            en = 0;
            @(posedge clk);
            @(negedge clk);

            // fire IF neurons
            neuron_en = 1;
            @(posedge clk);
            @(negedge clk);
            neuron_en = 0;

            // clear PEs for next round
            clear = 1;
            @(posedge clk);
            @(negedge clk);
            clear = 0;
        end
    endtask

    // main test
    initial begin
        reset_n    = 0;
        en         = 0;
        clear      = 0;
        neuron_en  = 0;
        col_addr   = 0;
        base_addr  = 0;
        active_pes = PES;
        spikes_in  = 0;

        repeat(3) @(posedge clk);
        #1;
        reset_n = 1;

        // TEST 1: all spikes=0, cur should be 0, no spikes out 
        $display("=== TEST 1: all spikes=0, expect cur=0, no output spikes ===");
        run_dot_product(0, {IN{1'b0}}, PES);
        $display("spikes_out = %08b (expect 00000000)", spikes_out);

        // TEST 2: all spikes=1, cur = sum of all weights in row 
        // this is the maximum possible accumulation
        $display("=== TEST 2: all spikes=1, maximum accumulation ===");
        run_dot_product(0, {IN{1'b1}}, PES);
        $display("spikes_out = %08b", spikes_out);
        $display("(check if neurons fired — depends on weight sum vs threshold=%0d)",
                  THRESHOLD);

        // TEST 3: run group 0 with real spike pattern
        // paste your spike_input vector from Python here
        // for now using a simple alternating pattern as placeholder
        $display("=== TEST 3: alternating spike pattern group 0 ===");
        run_dot_product(0,784'b0000000000000000000000000000000000000000000111000000000000000000000000111100000000000000000000000111110000000000000000000000001110000000000000000000000001110000000000000000000000001111000000000000000000000000111000000000000000000000000111000000000000000000000000011000000000000000000000000011100000000000000000000000011100000000000000000000000001110000000000000000000000001111000000000000000000000000111000000000000000000000000011000000000000000000000000011100000000000000000000000011101110110000000000000000001111111111111010000000000000111111111111111100000000000000000000001111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000, PES);
        $display("(check waveform: cur_out of pe_inst[0] should equal -684)");

        // TEST 4: run group 1 (neurons 8-15)
        // base_addr advances by IN=784 for each group
        $display("=== TEST 4: group 1, neurons 8-15, base_addr=784 ===");
        run_dot_product(784, {IN{1'b0}}, PES);
        $display("spikes_out group 1 = %08b (expect 00000000 since spikes=0)",
                  spikes_out);

        // TEST 5: membrane persists across groups 
        // run group 0 twice — membrane should accumulate across both runs
        $display("=== TEST 5: membrane accumulates across two rounds ===");
        run_dot_product(0, {IN{1'b1}}, PES);
        $display("after round 1: spikes_out = %08b", spikes_out);
        run_dot_product(0, {IN{1'b1}}, PES);
        $display("after round 2: spikes_out = %08b", spikes_out);
        $display("(more neurons should fire in round 2 as membrane builds up)");

        // TEST 6: reset clears all membrane state 
        $display("=== TEST 6: reset_n clears membrane ===");
        @(negedge clk);
        reset_n = 0;
        @(posedge clk);
        @(negedge clk);
        reset_n = 1;
        run_dot_product(0, {IN{1'b1}}, PES);
        $display("after reset + round: spikes_out = %08b", spikes_out);
        $display("(should match round 1 of TEST 5 — membrane was cleared)");

        $display("=== ALL TESTS DONE ===");
        #20;
        $finish;
    end

    initial begin
        #50000000;
        $display("TIMEOUT");
        $finish;
    end

    initial begin
        $dumpfile("tb_layer.vcd");
        $dumpvars(0, tb_layer);
    end

endmodule
