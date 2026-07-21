`timescale 1ns/1ps

module tb_pe;

    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 16;

    reg                          clk;
    reg                          reset_n;
    reg                          en;
    reg                          clear;
    reg                          spike_in;
    reg signed [DATA_WIDTH-1:0]  weight;

    wire signed [ACC_WIDTH-1:0]  cur_out;
    wire                         valid;

    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) dut (
        .clk      (clk),
        .reset_n  (reset_n),
        .en       (en),
        .clear    (clear),
        .spike_in (spike_in),
        .weight   (weight),
        .cur_out  (cur_out),
        .valid    (valid)
    );

    // clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // task: apply one weight+spike for one cycle
    task apply_input;
        input signed [DATA_WIDTH-1:0] w;
        input                         spk;
        begin
            @(negedge clk);
            en       = 1;
            clear    = 0;
            weight   = w;
            spike_in = spk;
            @(posedge clk);
            #1;
        end
    endtask

    // task: drop en and check valid pulses
    task finish_accumulation;
        begin
            @(negedge clk);
            en = 0;
            @(posedge clk);
            #1;
        end
    endtask

    // task: clear accumulator
    task clear_pe;
        begin
            @(negedge clk);
            clear = 1;
            en    = 0;
            @(posedge clk);
            #1;
            @(negedge clk);
            clear = 0;
        end
    endtask

    initial begin
        reset_n  = 0;
        en       = 0;
        clear    = 0;
        spike_in = 0;
        weight   = 0;

        repeat(3) @(posedge clk);
        #1;
        reset_n = 1;

        // TEST 1: spike=1 adds weight 
        $display("=== TEST 1: spike=1 adds weight ===");
        apply_input(5, 1);   // weight=5, spike=1 → accumulator += 5
        apply_input(5, 1);   // accumulator += 5
        apply_input(5, 1);   // accumulator += 5
        finish_accumulation;
        $display("after 3x(w=5,spk=1): cur_out=%0d valid=%0b (expect cur=15, valid=1)",
                  cur_out, valid);

        // TEST 2: clear resets accumulator
        $display("=== TEST 2: clear resets accumulator ===");
        clear_pe;
        #2;
        $display("after clear: cur_out=%0d (expect 0)", cur_out);

        // TEST 3: spike=0 does not add weight 
        $display("=== TEST 3: spike=0 does not add weight ===");
        apply_input(10, 0);  // weight=10 but spike=0 → accumulator stays 0
        apply_input(10, 0);
        finish_accumulation;
        $display("after 2x(w=10,spk=0): cur_out=%0d valid=%0b (expect cur=0, valid=1)",
                  cur_out, valid);

        // TEST 4: mixed spikes 
        $display("=== TEST 4: mixed spikes ===");
        clear_pe;
        apply_input(7, 1);   // += 7
        apply_input(7, 0);   // += 0
        apply_input(7, 1);   // += 7
        apply_input(7, 0);   // += 0
        apply_input(7, 1);   // += 7
        finish_accumulation;
        $display("after mixed spikes: cur_out=%0d valid=%0b (expect cur=21, valid=1)",
                  cur_out, valid);

        // TEST 5: negative weight 
        $display("=== TEST 5: negative weight ===");
        clear_pe;
        apply_input(10,  1);  // += 10
        apply_input(-3,  1);  // += -3
        apply_input(5,   1);  // += 5
        finish_accumulation;
        $display("after w=10,-3,5 all spike=1: cur_out=%0d valid=%0b (expect cur=12, valid=1)",
                  cur_out, valid);

        // TEST 6: valid pulses exactly one cycle
        $display("=== TEST 6: valid pulses one cycle only ===");
        clear_pe;
        apply_input(4, 1);
        finish_accumulation;
        $display("cycle 1 after en drops: valid=%0b (expect 1)", valid);
        @(posedge clk);
        #1;
        $display("cycle 2 after en drops: valid=%0b (expect 0)", valid);

        // TEST 7: reset_n clears everything 
        $display("=== TEST 7: reset_n clears everything ===");
        apply_input(20, 1);
        @(negedge clk);
        reset_n = 0;
        @(posedge clk);
        #1;
        $display("after reset: cur_out=%0d valid=%0b (expect cur=0, valid=0)",
                  cur_out, valid);
        reset_n = 1;

        $display("=== ALL TESTS DONE ===");
        #20;
        $finish;
    end

    initial begin
        #10000;
        $display("TIMEOUT");
        $finish;
    end

    initial begin
        $dumpfile("tb_pe.vcd");
        $dumpvars(0, tb_pe);
    end

endmodule
