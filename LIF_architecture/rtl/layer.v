/*module layer #(
    parameter integer IN         = 784,
    parameter integer OUT        = 128,
    parameter integer PES        = 8,
    parameter integer DATA_WIDTH = 8,
    parameter integer ACC_WIDTH  = 16,
    parameter integer THRESHOLD  = 32,

    parameter MEM_FILE0 = "mem/fc1_weights_bank0.mem",
    parameter MEM_FILE1 = "mem/fc1_weights_bank1.mem",
    parameter MEM_FILE2 = "mem/fc1_weights_bank2.mem",
    parameter MEM_FILE3 = "mem/fc1_weights_bank3.mem",
    parameter MEM_FILE4 = "mem/fc1_weights_bank4.mem",
    parameter MEM_FILE5 = "mem/fc1_weights_bank5.mem",
    parameter MEM_FILE6 = "mem/fc1_weights_bank6.mem",
    parameter MEM_FILE7 = "mem/fc1_weights_bank7.mem"
)(
    input  wire                           clk,
    input  wire                           reset_n,

    // controller signals
    input  wire                           en,
    input  wire                           clear,
    input  wire                           neuron_en,
    input  wire [$clog2(IN)-1:0]          col_addr,
    input  wire [3:0]                     active_pes,
    input  wire [$clog2(IN*OUT/PES)-1:0]  base_addr,

    // spike data
    input  wire [IN-1:0]                  spikes_in,
    output wire [PES-1:0]                 spikes_out,
    output wire [PES-1:0]                 valid
);

    // ── timing documentation ──────────────────────────────────────────
    // cycle N:     controller sets base_addr, col_addr, en=1
    //              spike_in_reg latches spikes_in[col_addr]
    // cycle N+1:   BRAM outputs weight for col N (1 cycle read latency)
    //              spike_in_reg still holds spike for col N → correct alignment
    //              PE accumulates weight[N] × spike[N]
    // ...repeat for IN cycles...
    // cycle N+IN:  controller drops en=0
    //              valid pulses high on all PEs
    // cycle N+IN+1: controller asserts neuron_en
    //               IF neurons update membrane, output spikes
    // cycle N+IN+2: controller asserts clear
    //               PE accumulators reset for next group
    //               IF neurons do NOT reset — membrane persists across groups
    //               and timesteps, only cleared by reset_n

    // internal signals
    wire signed [DATA_WIDTH-1:0] weights         [0:PES-1];
    wire signed [ACC_WIDTH-1:0]  cur             [0:PES-1];
    wire [PES-1:0]               neuron_en_masked;

    // ── critical: spike delay register ───────────────────────────────
    // spikes_in[col_addr] updates instantly (combinational)
    // but BRAM weight output has 1 cycle latency
    // this register delays the spike by 1 cycle to align with weight arrival
    // ── critical: pipeline delay registers ───────────────────────────────
    reg spike_in_reg;
    reg pe_en;                  // NEW: Delayed enable for the PE

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            spike_in_reg <= 1'b0;
            pe_en        <= 1'b0;   // Reset delayed enable
        end
        else begin
            pe_en <= en;            // Delay the en signal by 1 clock cycle
            if (en)
                spike_in_reg <= spikes_in[col_addr];
        end
    end

    // mask neuron_en for invalid PEs in partial last group
    // e.g. layer 2 last group: only 2 valid neurons (10 mod 8 = 2)
    // PEs 2-7 stay disabled so they don't produce garbage spikes
    genvar i;
    generate
        for (i = 0; i < PES; i = i + 1) begin : mask_gen
            assign neuron_en_masked[i] = neuron_en & (i < active_pes);
        end
    endgenerate

    // ── 8 BRAM banks — one per PE ─────────────────────────────────────
    // each bank stores (OUT/PES) rows × IN cols
    // all banks share same base_addr and col_addr from controller
    // each bank returns a different weight (different row) simultaneously
    // explicit instantiation required — $sformatf not synthesizable in Quartus
    weight_bram #(.ROWS(OUT/PES),.COLS(IN),.DATA_WIDTH(DATA_WIDTH),.MEM_FILE(MEM_FILE0))
        bram0 (.clk(clk),.en(en),.base_addr(base_addr),.col_addr(col_addr),.weight_out(weights[0]));

    weight_bram #(.ROWS(OUT/PES),.COLS(IN),.DATA_WIDTH(DATA_WIDTH),.MEM_FILE(MEM_FILE1))
        bram1 (.clk(clk),.en(en),.base_addr(base_addr),.col_addr(col_addr),.weight_out(weights[1]));

    weight_bram #(.ROWS(OUT/PES),.COLS(IN),.DATA_WIDTH(DATA_WIDTH),.MEM_FILE(MEM_FILE2))
        bram2 (.clk(clk),.en(en),.base_addr(base_addr),.col_addr(col_addr),.weight_out(weights[2]));

    weight_bram #(.ROWS(OUT/PES),.COLS(IN),.DATA_WIDTH(DATA_WIDTH),.MEM_FILE(MEM_FILE3))
        bram3 (.clk(clk),.en(en),.base_addr(base_addr),.col_addr(col_addr),.weight_out(weights[3]));

    weight_bram #(.ROWS(OUT/PES),.COLS(IN),.DATA_WIDTH(DATA_WIDTH),.MEM_FILE(MEM_FILE4))
        bram4 (.clk(clk),.en(en),.base_addr(base_addr),.col_addr(col_addr),.weight_out(weights[4]));

    weight_bram #(.ROWS(OUT/PES),.COLS(IN),.DATA_WIDTH(DATA_WIDTH),.MEM_FILE(MEM_FILE5))
        bram5 (.clk(clk),.en(en),.base_addr(base_addr),.col_addr(col_addr),.weight_out(weights[5]));

    weight_bram #(.ROWS(OUT/PES),.COLS(IN),.DATA_WIDTH(DATA_WIDTH),.MEM_FILE(MEM_FILE6))
        bram6 (.clk(clk),.en(en),.base_addr(base_addr),.col_addr(col_addr),.weight_out(weights[6]));

    weight_bram #(.ROWS(OUT/PES),.COLS(IN),.DATA_WIDTH(DATA_WIDTH),.MEM_FILE(MEM_FILE7))
        bram7 (.clk(clk),.en(en),.base_addr(base_addr),.col_addr(col_addr),.weight_out(weights[7]));

    // ── 8 PEs ─────────────────────────────────────────────────────────
    // all PEs share the same spike_in_reg but each reads from its own BRAM bank
    // so same spike × different weight per PE each cycle
    generate
        for (i = 0; i < PES; i = i + 1) begin : pe_inst
            pe #(
                .DATA_WIDTH(DATA_WIDTH),
                .ACC_WIDTH (ACC_WIDTH)
            ) pe_unit (
                .clk      (clk),
                .reset_n  (reset_n),
                .en       (pe_en),
                .clear    (clear),
                .spike_in (spike_in_reg),  // delayed 1 cycle to match BRAM latency
                .weight   (weights[i]),    // each PE gets its own weight from its bank
                .cur_out  (cur[i]),
                .valid    (valid[i])
            );
        end
    endgenerate

    // ── 8 IF neurons ──────────────────────────────────────────────────
    // neurons do NOT receive clear signal
    // membrane potential persists across groups and across timesteps
    // only reset_n clears the membrane
    generate
        for (i = 0; i < PES; i = i + 1) begin : neuron_inst
            if_neuron #(
                .ACC_WIDTH (ACC_WIDTH),
                .THRESHOLD (THRESHOLD)
            ) neuron (
                .clk                (clk),
                .reset_n            (reset_n),
                .en                 (neuron_en_masked[i]),
                .cur_in             (cur[i]),
                .spike_out          (spikes_out[i]),
                .membrane_potential ()   // internal — not exposed outside layer
            );
        end
    endgenerate

endmodule */

module layer #(
    parameter integer IN         = 784,
    parameter integer OUT        = 128,
    parameter integer PES        = 8,
    parameter integer DATA_WIDTH = 8,
    parameter integer ACC_WIDTH  = 16,
    parameter integer THRESHOLD  = 32,

    // Explicit file parameters for Quartus synthesis
    parameter MEM_FILE0 = "mem/fc1_weights_bank0.mem",
    parameter MEM_FILE1 = "mem/fc1_weights_bank1.mem",
    parameter MEM_FILE2 = "mem/fc1_weights_bank2.mem",
    parameter MEM_FILE3 = "mem/fc1_weights_bank3.mem",
    parameter MEM_FILE4 = "mem/fc1_weights_bank4.mem",
    parameter MEM_FILE5 = "mem/fc1_weights_bank5.mem",
    parameter MEM_FILE6 = "mem/fc1_weights_bank6.mem",
    parameter MEM_FILE7 = "mem/fc1_weights_bank7.mem"
)(
    input  wire                                 clk,
    input  wire                                 reset_n,
    input  wire                                 en,
    input  wire                                 clear,
    input  wire                                 neuron_en,
    input  wire [$clog2(IN)-1:0]                col_addr,
    input  wire [3:0]                           active_pes,
    input  wire [$clog2(IN * ((OUT+PES-1)/PES))-1:0] base_addr,
    input  wire [IN-1:0]                        spikes_in,

    output wire [PES-1:0]                       spikes_out,
    output wire [PES-1:0]                       valid
);

    wire signed [DATA_WIDTH-1:0] weights [0:PES-1];
    wire signed [ACC_WIDTH-1:0]  cur     [0:PES-1]; // Connects PE output to Neuron input

    // ── pipeline delay registers (matches 1-cycle BRAM latency) ────
    reg spike_in_reg;
    reg pe_en;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            spike_in_reg <= 1'b0;
            pe_en        <= 1'b0;
        end else begin
            pe_en <= en;
            if (en) begin
                spike_in_reg <= spikes_in[col_addr];
            end
        end
    end

    // ── explicit BRAM instantiations ────────────────────────────────
    weight_bram #(.ROWS((OUT+PES-1)/PES), .COLS(IN), .DATA_WIDTH(DATA_WIDTH), .MEM_FILE(MEM_FILE0))
        bram0 (.clk(clk), .en(en), .base_addr(base_addr), .col_addr(col_addr), .weight_out(weights[0]));

    weight_bram #(.ROWS((OUT+PES-1)/PES), .COLS(IN), .DATA_WIDTH(DATA_WIDTH), .MEM_FILE(MEM_FILE1))
        bram1 (.clk(clk), .en(en), .base_addr(base_addr), .col_addr(col_addr), .weight_out(weights[1]));

    weight_bram #(.ROWS((OUT+PES-1)/PES), .COLS(IN), .DATA_WIDTH(DATA_WIDTH), .MEM_FILE(MEM_FILE2))
        bram2 (.clk(clk), .en(en), .base_addr(base_addr), .col_addr(col_addr), .weight_out(weights[2]));

    weight_bram #(.ROWS((OUT+PES-1)/PES), .COLS(IN), .DATA_WIDTH(DATA_WIDTH), .MEM_FILE(MEM_FILE3))
        bram3 (.clk(clk), .en(en), .base_addr(base_addr), .col_addr(col_addr), .weight_out(weights[3]));

    weight_bram #(.ROWS((OUT+PES-1)/PES), .COLS(IN), .DATA_WIDTH(DATA_WIDTH), .MEM_FILE(MEM_FILE4))
        bram4 (.clk(clk), .en(en), .base_addr(base_addr), .col_addr(col_addr), .weight_out(weights[4]));

    weight_bram #(.ROWS((OUT+PES-1)/PES), .COLS(IN), .DATA_WIDTH(DATA_WIDTH), .MEM_FILE(MEM_FILE5))
        bram5 (.clk(clk), .en(en), .base_addr(base_addr), .col_addr(col_addr), .weight_out(weights[5]));

    weight_bram #(.ROWS((OUT+PES-1)/PES), .COLS(IN), .DATA_WIDTH(DATA_WIDTH), .MEM_FILE(MEM_FILE6))
        bram6 (.clk(clk), .en(en), .base_addr(base_addr), .col_addr(col_addr), .weight_out(weights[6]));

    weight_bram #(.ROWS((OUT+PES-1)/PES), .COLS(IN), .DATA_WIDTH(DATA_WIDTH), .MEM_FILE(MEM_FILE7))
        bram7 (.clk(clk), .en(en), .base_addr(base_addr), .col_addr(col_addr), .weight_out(weights[7]));

    // ── PE and Neuron Arrays ────────────────────────────────────────
    genvar i;
    generate
        // 1. Processing Elements (Multiply & Accumulate current)
        for (i = 0; i < PES; i = i + 1) begin : pe_array
            wire active = (i < active_pes);
            
            pe #(
                .DATA_WIDTH(DATA_WIDTH),
                .ACC_WIDTH(ACC_WIDTH)
            ) pe_inst (
                .clk(clk),
                .reset_n(reset_n),
                .en(pe_en & active),
                .clear(clear),
                .spike_in(spike_in_reg),
                .weight(weights[i]),
                .cur_out(cur[i]),
                .valid(valid[i])
            );
        end

        // 2. IF Neurons (Threshold Check & Spike Generation)
        for (i = 0; i < PES; i = i + 1) begin : neuron_array
            wire active = (i < active_pes);
            
            lif_neuron #(
                .ACC_WIDTH(ACC_WIDTH),
                .THRESHOLD(THRESHOLD),
                .LEAK_SHIFT(3)
            ) neuron_inst (
                .clk(clk),
                .reset_n(reset_n),
                .en(neuron_en & active),
                .cur_in(cur[i]),
                .spike_out(spikes_out[i]),
                .membrane_potential()
            );
        end
    endgenerate

endmodule