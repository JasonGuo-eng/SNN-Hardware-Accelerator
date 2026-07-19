  

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
