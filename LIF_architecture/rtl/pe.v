//only responsible for computing the dot product
/*module pe #(
    parameter integer DATA_WIDTH = 8,
    parameter integer ACC_WIDTH = 16
) (
    input wire clk,
    input wire reset_n,
    input wire en,
    input wire clear,
    input wire spike_in,
    input wire signed [DATA_WIDTH-1:0] weight,
    output wire signed [ACC_WIDTH-1:0] cur_out,
    output reg valid // a 1-bit signal that tells IF neuron and controller if the dot product is finished, and cur_out is ready to be read
) ;   //cur_out and accumulator (same thing) needs to be very big to hold enough accumulation

reg signed [ACC_WIDTH-1:0] accumulator;

always  @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        accumulator <= 0;
        valid <= 1'b0;
    end else if (clear) begin
        accumulator <= 0;
        valid <= 1'b0;
    end else if (en) begin
        if (spike_in) //if =0, don't do anything
            accumulator <= accumulator + weight;
        valid <= 1'b0;
    end else begin
        valid <= 1'b1;
    end

end

assign cur_out = accumulator;



endmodule */

module pe #(
    parameter integer DATA_WIDTH = 8,
    parameter integer ACC_WIDTH  = 16
)(
    input  wire                         clk,
    input  wire                         reset_n,
    input  wire                         en,
    input  wire                         clear,
    input  wire                         spike_in,
    input  wire signed [DATA_WIDTH-1:0] weight,
    output wire signed [ACC_WIDTH-1:0]  cur_out,
    output reg                          valid
);
    // PE accumulates weight × spike over IN cycles
    // spike is 1-bit so multiply reduces to conditional add — no multiplier needed
    // ACC_WIDTH > DATA_WIDTH to safely hold sum of up to 784 weights
    // valid pulses high for exactly one cycle when en falls 1→0
    // indicating cur_out is ready for the IF neuron to read

    reg signed [ACC_WIDTH-1:0] accumulator;
    reg                        en_q;        // one cycle delayed copy of en

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            accumulator <= 0;
            valid       <= 1'b0;
            en_q        <= 1'b0;
        end else begin
            en_q <= en;  // track previous state of en for edge detection

            if (clear) begin
                // clear takes priority over everything
                accumulator <= 0;
                valid       <= 1'b0;
            end else if (en) begin
                // accumulate: spike=1 adds weight, spike=0 adds nothing
                if (spike_in)
                    accumulator <= accumulator + weight;
                valid <= 1'b0;
            end else begin
                // en is low — check if it just fell from 1 to 0
                // if so pulse valid for exactly one cycle
                if (en_q == 1'b1 && en == 1'b0)
                    valid <= 1'b1;   // dot product just finished
                else
                    valid <= 1'b0;   // already been idle, stay low
            end
        end
    end

    assign cur_out = accumulator;

endmodule