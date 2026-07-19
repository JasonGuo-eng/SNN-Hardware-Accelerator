module tb_batch_top;

    parameter L1_IN      = 784;
    parameter L1_OUT     = 128;
    parameter L2_IN      = 128;
    parameter L2_OUT     = 10;
    parameter PES        = 8;
    parameter TSTEPS     = 20;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 16;
    parameter integer L1_THRESHOLD = 260;
    parameter integer L2_THRESHOLD = 165;

    // ── batch test config ───────────────────────────────────────
    // Start small (50-200) to keep sim runtime manageable, then
    // scale up once you trust the flow.
    parameter NUM_IMAGES     = 1000;
    parameter SPIKE_MEM_FILE = "mem/test_spike_trains.mem";
    parameter LABEL_MEM_FILE = "mem/test_labels.mem";

    reg          clk;
    reg          reset_n;
    reg          start;
    reg [L1_IN-1:0] input_spikes;

    wire [$clog2(L2_OUT)-1:0] predicted_class;
    wire                      done;

    // ── instantiate top ─────────────────────────────────────────
    top #(
        .L1_IN      (L1_IN),
        .L1_OUT     (L1_OUT),
        .L2_IN      (L2_IN),
        .L2_OUT     (L2_OUT),
        .PES        (PES),
        .TSTEPS     (TSTEPS),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .L1_THRESHOLD (L1_THRESHOLD),  
        .L2_THRESHOLD (L2_THRESHOLD) 
    ) dut (
        .clk            (clk),
        .reset_n        (reset_n),
        .start          (start),
        .input_spikes   (input_spikes),
        .predicted_class(predicted_class),
        .done           (done)
    );

    // ── clock ────────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── flattened spike memory: addr = img_idx*TSTEPS + timestep ──
    // Each line in SPIKE_MEM_FILE is a 784-bit binary string (0/1),
    // one line per (image, timestep) pair, in that nested order.
    reg [L1_IN-1:0] spike_mem [0:NUM_IMAGES*TSTEPS-1];

    // One hex digit (0-9) per line: the true label for each image.
    reg [3:0] labels [0:NUM_IMAGES-1];

    initial begin
        $readmemb(SPIKE_MEM_FILE, spike_mem);
        $readmemh(LABEL_MEM_FILE, labels);
    end

    integer img_idx;

    // feed the correct image/timestep slice based on the
    // controller's internal timestep counter, same pattern as
    // your single-image testbench
    always @(*) begin
        if (dut.ctrl.timestep < TSTEPS)
            input_spikes = spike_mem[img_idx*TSTEPS + dut.ctrl.timestep];
        else
            input_spikes = 0;
    end

    // ── accuracy tracking ───────────────────────────────────────
    integer correct_count;
    integer confusion [0:9][0:9];  // [actual][predicted]
    integer a, b;
    real    accuracy;

    initial begin
        correct_count = 0;
        for (a = 0; a < 10; a = a + 1)
            for (b = 0; b < 10; b = b + 1)
                confusion[a][b] = 0;

        reset_n      = 0;
        start        = 0;
        img_idx      = 0;
        input_spikes = 0;

        repeat(5) @(posedge clk);
        #1;
        reset_n = 1;
        repeat(2) @(posedge clk);
        #1;

        for (img_idx = 0; img_idx < NUM_IMAGES; img_idx = img_idx + 1) begin

            // full reset before each image so membrane potentials
            // don't carry over between inferences
            @(negedge clk);
            reset_n = 0;
            repeat(3) @(posedge clk);
            #1;
            reset_n = 1;
            repeat(2) @(posedge clk);
            #1;

            @(negedge clk);
            start = 1;
            @(posedge clk);
            #1;
            start = 0;

            wait(done == 1);
            #1;

            if (predicted_class == labels[img_idx])
                correct_count = correct_count + 1;

            confusion[labels[img_idx]][predicted_class] =
                confusion[labels[img_idx]][predicted_class] + 1;

            /*$display("Image %0d: predicted=%0d actual=%0d %s",
                      img_idx, predicted_class, labels[img_idx],
                      (predicted_class == labels[img_idx]) ? "CORRECT" : "WRONG"); */
        end

        accuracy = (correct_count * 100.0) / NUM_IMAGES;

        $display("=========================================");
        $display("Accuracy: %0d / %0d = %0.2f%%",
                  correct_count, NUM_IMAGES, accuracy);
        $display("=========================================");

        $display("Confusion matrix (rows=actual, cols=predicted):");
        $write("      ");
        for (b = 0; b < 10; b = b + 1) $write("%4d", b);
        $write("\n");
        for (a = 0; a < 10; a = a + 1) begin
            $write("act%0d: ", a);
            for (b = 0; b < 10; b = b + 1)
                $write("%4d", confusion[a][b]);
            $write("\n");
        end

        $display("=== BATCH TEST DONE ===");
        #20;
        $finish;
    end

    // timeout scales with number of images so it doesn't false-fire
    /* initial begin
        #(5000000 * NUM_IMAGES);
        $display("TIMEOUT — check FSM is not stuck");
        $finish;
    end */

    // NOTE: no $dumpfile/$dumpvars here on purpose. VCD generation
    // across a full batch run would be huge and isn't useful for
    // PowerPlay anyway — use your existing single-image tb_top.v
    // for VCD/power capture, and this testbench purely for accuracy.

endmodule