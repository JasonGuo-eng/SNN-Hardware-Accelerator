`timescale 1ns/1ps

module tb_weight_bram;

    parameter ROWS       = 16;
    parameter COLS       = 784;
    parameter DATA_WIDTH = 8;

    reg                          clk;
    reg                          en;
    reg [$clog2(ROWS*COLS)-1:0]  base_addr;
    reg [$clog2(COLS)-1:0]       col_addr;

    wire signed [DATA_WIDTH-1:0] weight_out;

    weight_bram #(
        .ROWS      (ROWS),
        .COLS      (COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_FILE  ("mem/fc1_weights_bank0.mem")
    ) dut (
        .clk       (clk),
        .en        (en),
        .base_addr (base_addr),
        .col_addr  (col_addr),
        .weight_out(weight_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // corrected task — samples on negedge to avoid race condition
    task read_weight;
        input [$clog2(ROWS*COLS)-1:0] b_addr;
        input [$clog2(COLS)-1:0]      c_addr;
        begin
            @(negedge clk);    // drive address on falling edge
            en        = 1;
            base_addr = b_addr;
            col_addr  = c_addr;
            @(posedge clk);    // BRAM captures address here (cycle N)
            @(negedge clk);    // sample output here — data settled (cycle N+1)
        end
    endtask

    initial begin
        en        = 0;
        base_addr = 0;
        col_addr  = 0;

        repeat(3) @(posedge clk);
        #1;

        // TEST 1: BRAM read latency is exactly 1 cycle 
        $display("=== TEST 1: BRAM read latency is exactly 1 cycle ===");
        @(negedge clk);
        en        = 1;
        base_addr = 0;
        col_addr  = 0;
        @(posedge clk);   // cycle N: address captured
        #1;
        $display("cycle N   (address just captured): weight_out=%0d (stale value)",
                  weight_out);
        @(posedge clk);   // cycle N+1: data valid
        #1;
        $display("cycle N+1 (data valid):            weight_out=%0d (real value)",
                  weight_out);

        //  TEST 2: read first weight of row 0 
        $display("=== TEST 2: read weight at base=0 col=0 ===");
        read_weight(0, 0);
        $display("weight[0][0] = %0d", weight_out);

        // TEST 3: read second weight of row 0 
        $display("=== TEST 3: read weight at base=0 col=1 ===");
        read_weight(0, 1);
        $display("weight[0][1] = %0d", weight_out);

        // TEST 4: read first weight of row 1
        // base_addr=784 advances to next row in this bank
        $display("=== TEST 4: read weight at base=784 col=0 ===");
        read_weight(784, 0);
        $display("weight[1][0] = %0d", weight_out);

        // TEST 5: en=0 holds output stable
        $display("=== TEST 5: en=0 holds weight_out ===");
        @(negedge clk);
        en = 0;
        @(posedge clk);
        #1;
        $display("after en=0 cycle 1: weight_out=%0d (expect unchanged)", weight_out);
        @(posedge clk);
        #1;
        $display("after en=0 cycle 2: weight_out=%0d (expect unchanged)", weight_out);

        // TEST 6: read first 5 weights and verify against .mem file
        $display("=== TEST 6: address traversal — verify against mem file ===");
        $display("reading first 5 weights of row 0 from bank 0:");
        read_weight(0, 0); $display("  col=0: %0d", weight_out);
        read_weight(0, 1); $display("  col=1: %0d", weight_out);
        read_weight(0, 2); $display("  col=2: %0d", weight_out);
        read_weight(0, 3); $display("  col=3: %0d", weight_out);
        read_weight(0, 4); $display("  col=4: %0d", weight_out);
        $display("open mem/fc1_weights_bank0.mem and verify lines 1-5 match");

        $display("=== ALL TESTS DONE ===");
        #20;
        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

    initial begin
        $dumpfile("tb_weight_bram.vcd");
        $dumpvars(0, tb_weight_bram);
    end

endmodule
