
/* module top #(
parameter integer L1_IN      = 784,
parameter integer L1_OUT     = 128,
parameter integer L2_IN      = 128,
parameter integer L2_OUT     = 10,
parameter integer PES        = 8,
parameter integer TSTEPS     = 20,
parameter integer DATA_WIDTH = 8,
parameter integer ACC_WIDTH  = 16,
parameter integer THRESHOLD  = 283
)(
input  wire                        clk,
input  wire                        reset_n,
input  wire                        start,

// input spike train from outside
input  wire [L1_IN-1:0]            input_spikes,

// final output
output reg  [$clog2(L2_OUT)-1:0]   predicted_class,
output reg                         done


);

// ─── controller signals ───────────────────────────────────────────
wire                            pe_en;
wire                            pe_clear;
wire                            neuron_en;
wire [$clog2(L1_OUT/PES)-1:0]   group;
wire [$clog2(L1_IN)-1:0]        col_addr;
wire                            layer_sel;
wire [$clog2(TSTEPS)-1:0]       timestep;
wire [3:0]                      active_pes;
wire                            ctrl_done;

// ─── spike register ───────────────────────────────────────────────
reg [L1_OUT-1:0] spike_register;

// ─── layer 1 & 2 outputs ──────────────────────────────────────────
wire [PES-1:0]   l1_spikes_out;
wire [PES-1:0]   l1_valid;
wire [PES-1:0]   l2_spikes_out;
wire [PES-1:0]   l2_valid;

// ─── output membrane accumulator ──────────────────────────────────
reg signed [ACC_WIDTH-1:0] output_membrane [0:L2_OUT-1];

// ─── col_addr and base_addr routing ───────────────────────────────
wire [$clog2(L1_IN)-1:0] l1_col_addr = col_addr;
wire [$clog2(L2_IN)-1:0] l2_col_addr = col_addr[$clog2(L2_IN)-1:0];

wire [$clog2(L1_IN * L1_OUT/PES)-1:0] l1_base_addr = group * L1_IN;
wire [$clog2(L2_IN * ((L2_OUT+PES-1)/PES))-1:0] l2_base_addr = group * L2_IN;

// ─── instantiate controller ───────────────────────────────────────
controller #(
    .L1_IN  (L1_IN),
    .L1_OUT (L1_OUT),
    .L2_IN  (L2_IN),
    .L2_OUT (L2_OUT),
    .PES    (PES),
    .TSTEPS (TSTEPS)
) ctrl (
    .clk       (clk),
    .reset_n   (reset_n),
    .start     (start),
    .pe_en     (pe_en),
    .pe_clear  (pe_clear),
    .neuron_en (neuron_en),
    .group     (group),
    .col_addr  (col_addr),
    .layer_sel (layer_sel),
    .timestep  (timestep),
    .active_pes(active_pes),
    .done      (ctrl_done)
);

// ─── instantiate layer 1 ──────────────────────────────────────────
layer #(
    .IN         (L1_IN),
    .OUT        (L1_OUT),
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
) layer1 (
    .clk        (clk),
    .reset_n    (reset_n),
    .en         (pe_en    & ~layer_sel),
    .clear      (pe_clear & ~layer_sel),
    .neuron_en  (neuron_en & ~layer_sel),
    .col_addr   (l1_col_addr),
    .active_pes (active_pes),       
    .base_addr  (l1_base_addr),     
    .spikes_in  (input_spikes),     
    .spikes_out (l1_spikes_out),
    .valid      (l1_valid)
);

// ─── instantiate layer 2 ──────────────────────────────────────────
layer #(
    .IN         (L2_IN),
    .OUT        (L2_OUT),
    .PES        (PES),
    .DATA_WIDTH (DATA_WIDTH),
    .ACC_WIDTH  (ACC_WIDTH),
    .THRESHOLD  (THRESHOLD),
    .MEM_FILE0  ("mem/fc2_weights_bank0.mem"),
    .MEM_FILE1  ("mem/fc2_weights_bank1.mem"),
    .MEM_FILE2  ("mem/fc2_weights_bank2.mem"),
    .MEM_FILE3  ("mem/fc2_weights_bank3.mem"),
    .MEM_FILE4  ("mem/fc2_weights_bank4.mem"),
    .MEM_FILE5  ("mem/fc2_weights_bank5.mem"),
    .MEM_FILE6  ("mem/fc2_weights_bank6.mem"),
    .MEM_FILE7  ("mem/fc2_weights_bank7.mem")
) layer2 (
    .clk        (clk),
    .reset_n    (reset_n),
    .en         (pe_en    & layer_sel),
    .clear      (pe_clear & layer_sel),
    .neuron_en  (neuron_en & layer_sel),
    .col_addr   (l2_col_addr),
    .active_pes (active_pes),       
    .base_addr  (l2_base_addr),     
    .spikes_in  (spike_register),   
    .spikes_out (l2_spikes_out),
    .valid      (l2_valid)
);

// ─── spike register update ────────────────────────────────────────
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        spike_register <= 0;
    end else if (neuron_en && ~layer_sel) begin
        spike_register[group * PES +: PES] <= l1_spikes_out;
    end
end

// ─── output membrane accumulator ──────────────────────────────────
integer i;
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        for (i = 0; i < L2_OUT; i = i + 1)
            output_membrane[i] <= 0;
    end else if (start) begin
        for (i = 0; i < L2_OUT; i = i + 1)
            output_membrane[i] <= 0;
    end else if (neuron_en && layer_sel) begin
        for (i = 0; i < PES; i = i + 1) begin
            if ((group * PES + i) < L2_OUT) 
                output_membrane[group * PES + i] <= 
                    output_membrane[group * PES + i] + l2_spikes_out[i];
        end
    end
end

// ─── argmax ───────────────────────────────────────────────────────
integer j;
reg signed [ACC_WIDTH-1:0] max_val;
reg [$clog2(L2_OUT)-1:0]   max_idx;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        predicted_class <= 0;
        done            <= 0;
    end else if (ctrl_done) begin
        max_val = output_membrane[0]; 
        max_idx = 0;
        for (j = 1; j < L2_OUT; j = j + 1) begin
            if (output_membrane[j] > max_val) begin
                max_val = output_membrane[j]; 
                max_idx = j;
            end
        end
        predicted_class <= max_idx;
        done <= 1;
    end else begin
        done <= 0;
    end
end


endmodule  */

module top #(
parameter integer L1_IN        = 784,
parameter integer L1_OUT       = 128,
parameter integer L2_IN        = 128,
parameter integer L2_OUT       = 10,
parameter integer PES          = 8,
parameter integer TSTEPS       = 20,
parameter integer DATA_WIDTH   = 8,
parameter integer ACC_WIDTH    = 16,
parameter integer L1_THRESHOLD = 283,  // <-- Split and restored L1 Threshold
parameter integer L2_THRESHOLD = 169   // <-- Split and restored L2 Threshold
)(
input  wire                        clk,
input  wire                        reset_n,
input  wire                        start,

// input spike train from outside
input  wire [L1_IN-1:0]            input_spikes,

// final output
output reg  [$clog2(L2_OUT)-1:0]   predicted_class,
output reg                         done


);

// ─── controller signals ───────────────────────────────────────────
wire                            pe_en;
wire                            pe_clear;
wire                            neuron_en;
wire [$clog2(L1_OUT/PES)-1:0]   group;
wire [$clog2(L1_IN)-1:0]        col_addr;
wire                            layer_sel;
wire [$clog2(TSTEPS)-1:0]       timestep;
wire [3:0]                      active_pes;
wire                            ctrl_done;

// ─── spike register ───────────────────────────────────────────────
reg [L1_OUT-1:0] spike_register;

// ─── layer 1 & 2 outputs ──────────────────────────────────────────
wire [PES-1:0]   l1_spikes_out;
wire [PES-1:0]   l1_valid;
wire [PES-1:0]   l2_spikes_out;
wire [PES-1:0]   l2_valid;

// ─── output membrane accumulator ──────────────────────────────────
reg signed [ACC_WIDTH-1:0] output_membrane [0:L2_OUT-1];

// ─── col_addr and base_addr routing ───────────────────────────────
wire [$clog2(L1_IN)-1:0] l1_col_addr = col_addr;
wire [$clog2(L2_IN)-1:0] l2_col_addr = col_addr[$clog2(L2_IN)-1:0];

wire [$clog2(L1_IN * L1_OUT/PES)-1:0] l1_base_addr = group * L1_IN;
wire [$clog2(L2_IN * ((L2_OUT+PES-1)/PES))-1:0] l2_base_addr = group * L2_IN;

// ─── instantiate controller ───────────────────────────────────────
controller #(
    .L1_IN  (L1_IN),
    .L1_OUT (L1_OUT),
    .L2_IN  (L2_IN),
    .L2_OUT (L2_OUT),
    .PES    (PES),
    .TSTEPS (TSTEPS)
) ctrl (
    .clk       (clk),
    .reset_n   (reset_n),
    .start     (start),
    .pe_en     (pe_en),
    .pe_clear  (pe_clear),
    .neuron_en (neuron_en),
    .group     (group),
    .col_addr  (col_addr),
    .layer_sel (layer_sel),
    .timestep  (timestep),
    .active_pes(active_pes),
    .done      (ctrl_done)
);

// ─── instantiate layer 1 ──────────────────────────────────────────
layer #(
    .IN         (L1_IN),
    .OUT        (L1_OUT),
    .PES        (PES),
    .DATA_WIDTH (DATA_WIDTH),
    .ACC_WIDTH  (ACC_WIDTH),
    .THRESHOLD  (L1_THRESHOLD),      // <-- Passed L1_THRESHOLD specifically
    .MEM_FILE0  ("mem/fc1_weights_bank0.mem"),
    .MEM_FILE1  ("mem/fc1_weights_bank1.mem"),
    .MEM_FILE2  ("mem/fc1_weights_bank2.mem"),
    .MEM_FILE3  ("mem/fc1_weights_bank3.mem"),
    .MEM_FILE4  ("mem/fc1_weights_bank4.mem"),
    .MEM_FILE5  ("mem/fc1_weights_bank5.mem"),
    .MEM_FILE6  ("mem/fc1_weights_bank6.mem"),
    .MEM_FILE7  ("mem/fc1_weights_bank7.mem")
) layer1 (
    .clk        (clk),
    .reset_n    (reset_n),
    .en         (pe_en    & ~layer_sel),
    .clear      (pe_clear & ~layer_sel),
    .neuron_en  (neuron_en & ~layer_sel),
    .col_addr   (l1_col_addr),
    .active_pes (active_pes),       
    .base_addr  (l1_base_addr),     
    .spikes_in  (input_spikes),     
    .spikes_out (l1_spikes_out),
    .valid      (l1_valid)
);

// ─── instantiate layer 2 ──────────────────────────────────────────
layer #(
    .IN         (L2_IN),
    .OUT        (L2_OUT),
    .PES        (PES),
    .DATA_WIDTH (DATA_WIDTH),
    .ACC_WIDTH  (ACC_WIDTH),
    .THRESHOLD  (L2_THRESHOLD),      // <-- Passed L2_THRESHOLD specifically
    .MEM_FILE0  ("mem/fc2_weights_bank0.mem"),
    .MEM_FILE1  ("mem/fc2_weights_bank1.mem"),
    .MEM_FILE2  ("mem/fc2_weights_bank2.mem"),
    .MEM_FILE3  ("mem/fc2_weights_bank3.mem"),
    .MEM_FILE4  ("mem/fc2_weights_bank4.mem"),
    .MEM_FILE5  ("mem/fc2_weights_bank5.mem"),
    .MEM_FILE6  ("mem/fc2_weights_bank6.mem"),
    .MEM_FILE7  ("mem/fc2_weights_bank7.mem")
) layer2 (
    .clk        (clk),
    .reset_n    (reset_n),
    .en         (pe_en    & layer_sel),
    .clear      (pe_clear & layer_sel),
    .neuron_en  (neuron_en & layer_sel),
    .col_addr   (l2_col_addr),
    .active_pes (active_pes),       
    .base_addr  (l2_base_addr),     
    .spikes_in  (spike_register),   
    .spikes_out (l2_spikes_out),
    .valid      (l2_valid)
);

// ─── spike register update ────────────────────────────────────────
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        spike_register <= 0;
    end else if (neuron_en && ~layer_sel) begin
        spike_register[group * PES +: PES] <= l1_spikes_out;
    end
end

// ─── output membrane accumulator ──────────────────────────────────
integer i;
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        for (i = 0; i < L2_OUT; i = i + 1)
            output_membrane[i] <= 0;
    end else if (start) begin
        for (i = 0; i < L2_OUT; i = i + 1)
            output_membrane[i] <= 0;
    end else if (neuron_en && layer_sel) begin
        for (i = 0; i < PES; i = i + 1) begin
            if ((group * PES + i) < L2_OUT) 
                output_membrane[group * PES + i] <= 
                    output_membrane[group * PES + i] + l2_spikes_out[i];
        end
    end
end

// ─── argmax ───────────────────────────────────────────────────────
integer j;
reg signed [ACC_WIDTH-1:0] max_val;
reg [$clog2(L2_OUT)-1:0]   max_idx;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        predicted_class <= 0;
        done            <= 0;
    end else if (ctrl_done) begin
        max_val = output_membrane[0]; 
        max_idx = 0;
        for (j = 1; j < L2_OUT; j = j + 1) begin
            if (output_membrane[j] > max_val) begin
                max_val = output_membrane[j]; 
                max_idx = j;
            end
        end
        predicted_class <= max_idx;
        done <= 1;
    end else begin
        done <= 0;
    end
end


endmodule