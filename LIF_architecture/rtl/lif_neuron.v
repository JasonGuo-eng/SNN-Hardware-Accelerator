module lif_neuron #(
    parameter integer ACC_WIDTH  = 16,
    parameter integer THRESHOLD  = 32,
    parameter integer LEAK_SHIFT = 3  // Beta approx: 1 - (1/2^3) = 0.875
)(
    input  wire                        clk,
    input  wire                        reset_n,
    input  wire                        en,
    input  wire signed [ACC_WIDTH-1:0] cur_in,
    output wire                        spike_out,
    output reg  signed [ACC_WIDTH-1:0] membrane_potential
);

    wire signed [ACC_WIDTH-1:0] leaked_potential;
    wire signed [ACC_WIDTH:0]   membrane_next;  // guard bit, same as if_neuron

    // Apply leak to the currently stored potential BEFORE adding new input
    assign leaked_potential = membrane_potential - (membrane_potential >>> LEAK_SHIFT);

    // Sign-extended add, mirrors if_neuron's overflow-safe computation
    assign membrane_next = {{1{leaked_potential[ACC_WIDTH-1]}}, leaked_potential}
                          + {{1{cur_in[ACC_WIDTH-1]}}, cur_in};

    // COMBINATIONAL SPIKE: visible immediately during the 'en' cycle
    assign spike_out = (en && (membrane_next >= THRESHOLD)) ? 1'b1 : 1'b0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            membrane_potential <= 0;
        end else if (en) begin
            if (membrane_next >= THRESHOLD) begin
                membrane_potential <= membrane_next - THRESHOLD; // Soft reset, matches if_neuron
            end else if (membrane_next < 0) begin
                membrane_potential <= 0; // Zero-clipping, matches if_neuron
            end else begin
                membrane_potential <= membrane_next[ACC_WIDTH-1:0];
            end
        end
    end

endmodule 

/* module lif_neuron #(
    parameter integer ACC_WIDTH  = 16,
    parameter integer THRESHOLD  = 32,
    parameter integer LEAK_SHIFT = 3  // Beta approx: 1 - (1/2^3) = 0.875
)(
    input  wire                        clk,
    input  wire                        reset_n,
    input  wire                        en,
    input  wire signed [ACC_WIDTH-1:0] cur_in,
    output wire                        spike_out,
    output reg  signed [ACC_WIDTH-1:0] membrane_potential
);

    wire signed [ACC_WIDTH-1:0] shifted_membrane;
    wire signed [ACC_WIDTH-1:0] leaked_potential;
    wire signed [ACC_WIDTH:0]   membrane_next;  // guard bit, same as if_neuron

    // Apply a rounding bias IF the membrane potential is negative. 
    // Adding ((1 << LEAK_SHIFT) - 1) before shifting forces Verilog 
    // to round negative numbers towards zero, matching PyTorch.
    assign shifted_membrane = (membrane_potential < 0) ? 
                              ((membrane_potential + ((1 << LEAK_SHIFT) - 1)) >>> LEAK_SHIFT) : 
                              (membrane_potential >>> LEAK_SHIFT);

    // Apply leak to the currently stored potential BEFORE adding new input
    assign leaked_potential = membrane_potential - shifted_membrane;

    // Sign-extended add, mirrors if_neuron's overflow-safe computation
    assign membrane_next = {{1{leaked_potential[ACC_WIDTH-1]}}, leaked_potential}
                         + {{1{cur_in[ACC_WIDTH-1]}}, cur_in};

    // COMBINATIONAL SPIKE: visible immediately during the 'en' cycle
    assign spike_out = (en && (membrane_next >= THRESHOLD)) ? 1'b1 : 1'b0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            membrane_potential <= 0;
        end else if (en) begin
            if (membrane_next >= THRESHOLD) begin
                membrane_potential <= membrane_next - THRESHOLD; // Soft reset, matches if_neuron
            end else if (membrane_next < 0) begin
                membrane_potential <= 0; // Zero-clipping, matches if_neuron
            end else begin
                membrane_potential <= membrane_next[ACC_WIDTH-1:0];
            end
        end
    end
   

endmodule */