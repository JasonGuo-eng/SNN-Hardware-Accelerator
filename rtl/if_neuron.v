// IF neuron module
// no multiplier needed — input spikes are 1-bit so weight×spike = conditional add
// dynamics: V(t) = V(t-1) + I(t)
// if V(t) >= THRESHOLD: spike=1, soft reset V(t) = V(t) - THRESHOLD
// else:                 spike=0, V(t) unchanged
// receives completed cur_in from PE and updates membrane potential

/* module if_neuron #(
    parameter integer ACC_WIDTH = 16,
    parameter integer THRESHOLD  = 32
) (
    input wire clk, 
    input wire reset_n,
    input wire en, // will be set to high when the processing element finished dot product
    input wire signed [ACC_WIDTH-1:0] cur_in, // output from PE, now it is input
    output reg spike_out,
    output reg signed [ACC_WIDTH-1:0] membrane_potential // Great for testbench visibility
);

    // Fixed: Changed DATA_WIDTH to ACC_WIDTH
    wire signed [ACC_WIDTH:0] membrane_next; 
    
    // Sign extend these two, then add them. The extra bit width prevents overflow.
    assign membrane_next = {{1{membrane_potential[ACC_WIDTH-1]}}, membrane_potential} 
                         + {{1{cur_in[ACC_WIDTH-1]}}, cur_in}; 

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin  // level 1, reset is active, clear everything
            membrane_potential <= 0;
            spike_out <= 1'b0;
        end else if (en) begin // level 1, reset inactive, enabled, do neuron logic
            if (membrane_next >= THRESHOLD) begin
                membrane_potential <= membrane_next - THRESHOLD; // Soft reset
                spike_out <= 1'b1;
            end else begin
                spike_out <= 1'b0;
                membrane_potential <= membrane_next;  // update potential
            end
        end else begin // level 1, reset inactive, disabled, idle state
            spike_out <= 1'b0;
        end
    end
endmodule */      

//clipping is added as we don't want negatie numbers to accumulate forever
module if_neuron #(
    parameter integer ACC_WIDTH = 16,
    parameter integer THRESHOLD  = 32
) (
    input wire clk, 
    input wire reset_n,
    input wire en, 
    input wire signed [ACC_WIDTH-1:0] cur_in, 
    output wire spike_out, // <--- CHANGED TO WIRE
    output reg signed [ACC_WIDTH-1:0] membrane_potential 
);

    wire signed [ACC_WIDTH:0] membrane_next; 
    
    // Calculate what the membrane will be
    assign membrane_next = {{1{membrane_potential[ACC_WIDTH-1]}}, membrane_potential} 
                         + {{1{cur_in[ACC_WIDTH-1]}}, cur_in}; 

    // COMBINATIONAL SPIKE: Spike is visible IMMEDIATELY during the 'en' cycle
    assign spike_out = (en && (membrane_next >= THRESHOLD)) ? 1'b1 : 1'b0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin  
            membrane_potential <= 0;
        end else if (en) begin 
            if (membrane_next >= THRESHOLD) begin
                membrane_potential <= membrane_next - THRESHOLD; // Soft reset
            end else if (membrane_next < 0) begin
                membrane_potential <= 0; // Zero-clipping
            end else begin
                membrane_potential <= membrane_next;  // update potential
            end
        end
    end
endmodule