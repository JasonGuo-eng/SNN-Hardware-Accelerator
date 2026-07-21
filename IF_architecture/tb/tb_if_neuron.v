`timescale 1ns/1ps

module tb_if_neuron;

    //  parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 16;
    parameter THRESHOLD  = 32;

    //  DUT signals
    reg                        clk;
    reg                        reset_n;
    reg                        en;
    reg signed [ACC_WIDTH-1:0] cur_in;

    wire                         spike_out;
    wire signed [ACC_WIDTH-1:0] membrane_potential;

    // instantiate the module under test
    if_neuron #(
        //.DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .THRESHOLD (THRESHOLD)
    ) dut (
        .clk                (clk),
        .reset_n            (reset_n),
        .en                 (en),
        .cur_in             (cur_in),
        .spike_out          (spike_out),
        .membrane_potential (membrane_potential)
    );

    // clock generation — 10ns period (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    //  helper task: apply one cur_in for one cycle 
    task apply_current;
        input signed [ACC_WIDTH-1:0] current;
        begin
            @(negedge clk);  // apply on falling edge so it's stable at rising
            en     = 1;
            cur_in = current;
            @(posedge clk);  // wait for rising edge to latch
            #1;              // small delay to let outputs settle
        end
    endtask

    // helper task: idle for N cycles
    task idle_cycles;
        input integer n;
        integer k;
        begin
            @(negedge clk);
            en = 0;
            repeat(n) @(posedge clk);
            #1;
        end
    endtask

    // main test sequence 
    initial begin
        // initialise
        reset_n = 0;
        en      = 0;
        cur_in  = 0;

        // hold reset for 3 cycles
        repeat(3) @(posedge clk);
        #1;
        reset_n = 1;

        $display("=== TEST 1: membrane accumulates correctly ===");
        // apply cur_in=8 four times → membrane should reach 32 = threshold
        // expected: membrane = 8, 16, 24, then spike on 32
        apply_current(8);
        $display("after cur=8:  membrane=%0d spike=%0b (expect mem=8,  spike=0)",
                  membrane_potential, spike_out);

        apply_current(8);
        $display("after cur=8:  membrane=%0d spike=%0b (expect mem=16, spike=0)",
                  membrane_potential, spike_out);

        apply_current(8);
        $display("after cur=8:  membrane=%0d spike=%0b (expect mem=24, spike=0)",
                  membrane_potential, spike_out);

        $display("=== TEST 2: spike fires at threshold ===");
        apply_current(8);
        $display("after cur=8:  membrane=%0d spike=%0b (expect mem=0,  spike=1)",
                  membrane_potential, spike_out);
        // soft reset: membrane = 32 - 32 = 0

        $display("=== TEST 3: soft reset — leftover charge preserved ===");
        // membrane=0, apply cur=40 → exceeds threshold by 8
        // expected: spike=1, membrane = 40 - 32 = 8
        apply_current(40);
        $display("after cur=40: membrane=%0d spike=%0b (expect mem=8,  spike=1)",
                  membrane_potential, spike_out);

        $display("=== TEST 4: membrane holds when en=0 ===");
        idle_cycles(3);
        $display("after 3 idle: membrane=%0d spike=%0b (expect mem=8,  spike=0)",
                  membrane_potential, spike_out);

        $display("=== TEST 5: negative current reduces membrane ===");
        // apply negative cur — membrane should decrease
        apply_current(-4);
        $display("after cur=-4: membrane=%0d spike=%0b (expect mem=4,  spike=0)",
                  membrane_potential, spike_out);

        $display("=== TEST 6: reset_n clears everything ===");
        @(negedge clk);
        reset_n = 0;
        @(posedge clk);
        #1;
        $display("after reset:  membrane=%0d spike=%0b (expect mem=0,  spike=0)",
                  membrane_potential, spike_out);
        reset_n = 1;

        $display("=== ALL TESTS DONE ===");
        #20;
        $finish;
    end

    // timeout watchdog — kills sim if it hangs 
    initial begin
        #10000;
        $display("TIMEOUT — simulation took too long");
        $finish;
    end

    // optional: dump waveforms for ModelSim viewer
    initial begin
        $dumpfile("tb_if_neuron.vcd");
        $dumpvars(0, tb_if_neuron);
    end

endmodule
