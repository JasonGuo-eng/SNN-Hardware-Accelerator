/*module weight_bram #(
    parameter integer ROWS = 16, //rows per bank, divided into 8 groups, row 0,8,16...
    //second group: 1,9,17.., third group: 2,10,18...
    parameter integer COLS = 784,
    parameter integer DATA_WIDTH = 8,
    parameter MEM_FILE = "mem/fc1_weights_bank0.mem" //different bram load different files
) (
    input wire clk,
    input wire en,
    input  wire [$clog2(ROWS*COLS)-1:0] base_addr,  // points to the start of the current row, computed by controller
    input  wire [$clog2(COLS)-1:0]      col_addr,
    output reg  signed [DATA_WIDTH-1:0] weight_out
);
    reg signed [DATA_WIDTH-1:0] mem [0:ROWS*COLS-1]; //a flat 1D array of weights
    initial $readmemh(MEM_FILE, mem); 

    always @(posedge clk) begin
        if (en)
            weight_out <= mem[base_addr + col_addr]; //computes which weight to read from that array
    end

endmodule */



module weight_bram #(
    parameter integer ROWS = 16,
    parameter integer COLS = 784,
    parameter integer DATA_WIDTH = 8,
    parameter MEM_FILE = "mem/fc1_weights_bank0.mem" 
) (
    input  wire clk,
    input  wire en,
    input  wire [$clog2(ROWS*COLS)-1:0] base_addr,
    input  wire [$clog2(COLS)-1:0]      col_addr,
    output reg  signed [DATA_WIDTH-1:0] weight_out
);
    
    reg signed [DATA_WIDTH-1:0] mem [0:ROWS*COLS-1];
    
    initial begin
        $readmemh(MEM_FILE, mem); 
    end

    always @(posedge clk) begin
        if (en) begin
            weight_out <= mem[base_addr + col_addr];
        end
    end

endmodule