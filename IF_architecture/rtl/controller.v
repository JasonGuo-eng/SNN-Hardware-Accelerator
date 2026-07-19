module controller #(
    parameter integer L1_IN  = 784,
    parameter integer L1_OUT = 128,
    parameter integer L2_IN  = 128,
    parameter integer L2_OUT = 10,
    parameter integer PES    = 8,
    parameter integer TSTEPS = 10
)(
    input  wire clk,
    input  wire reset_n,
    input  wire start,

    output reg                              pe_en,
    output reg                              pe_clear,
    output reg                              neuron_en,
    output reg  [$clog2(L1_OUT/PES)-1:0]   group,
    output reg  [$clog2(L1_IN)-1:0]        col_addr,
    output reg                              layer_sel,
    output reg  [$clog2(TSTEPS)-1:0]       timestep,
    output reg  [3:0]                       active_pes,
    output reg                              done
);

    localparam L1_GROUPS = L1_OUT / PES;
    localparam L2_GROUPS = (L2_OUT + PES - 1) / PES;  // ceiling division fix

    // combinational base_addr — no runtime multiplier
    wire [$clog2(L1_IN * L1_OUT/PES)-1:0] base_addr;
    assign base_addr = (layer_sel == 0)
                     ? group * L1_IN   // Quartus optimizes since L1_IN is constant
                     : group * L2_IN;

    // FSM states
    localparam IDLE       = 4'd0;
    localparam L1_WAIT    = 4'd1;
    localparam L1_COMPUTE = 4'd2;
    localparam L1_FIRE    = 4'd3;
    localparam L1_CLEAR   = 4'd4;
    localparam L2_WAIT    = 4'd5;
    localparam L2_COMPUTE = 4'd6;
    localparam L2_FIRE    = 4'd7;
    localparam L2_CLEAR   = 4'd8;
    localparam DONE       = 4'd9;

    reg [3:0] state;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state      <= IDLE;
            pe_en      <= 0;
            pe_clear   <= 0;
            neuron_en  <= 0;
            col_addr   <= 0;
            group      <= 0;
            layer_sel  <= 0;
            timestep   <= 0;
            active_pes <= PES;
            done       <= 0;
        end else begin
            pe_en     <= 0;
            pe_clear  <= 0;
            neuron_en <= 0;
            done      <= 0;

            case (state)

                IDLE: begin
                    // explicit reset of all counters
                    group     <= 0;
                    col_addr  <= 0;
                    layer_sel <= 0;
                    timestep  <= 0;
                    if (start) state <= L1_WAIT;
                end

                L1_WAIT: begin
                    // absorb one cycle BRAM latency
                    col_addr   <= 0;
                    active_pes <= PES;  // full group for layer 1
                    state      <= L1_COMPUTE;
                end

                L1_COMPUTE: begin
                    pe_en <= 1;
                    if (col_addr == L1_IN - 1) begin
                        pe_en    <= 0;
                        col_addr <= 0;
                        state    <= L1_FIRE;
                    end else begin
                        col_addr <= col_addr + 1;
                    end
                end

                L1_FIRE: begin
                    neuron_en <= 1;
                    state     <= L1_CLEAR;
                end

                L1_CLEAR: begin
                    pe_clear <= 1;
                    if (group == L1_GROUPS - 1) begin
                        group     <= 0;
                        col_addr  <= 0;
                        layer_sel <= 1;
                        state     <= L2_WAIT;
                    end else begin
                        group    <= group + 1;
                        col_addr <= 0;
                        state    <= L1_WAIT;
                    end
                end

                L2_WAIT: begin
                    col_addr <= 0;
                    // handle partial last group — only 2 valid PEs for neurons 8,9
                    active_pes <= (group == L2_GROUPS - 1)
                                ? (L2_OUT % PES == 0 ? PES : L2_OUT % PES)
                                : PES;
                    state <= L2_COMPUTE;
                end

                L2_COMPUTE: begin
                    pe_en <= 1;
                    if (col_addr == L2_IN - 1) begin
                        pe_en    <= 0;
                        col_addr <= 0;
                        state    <= L2_FIRE;
                    end else begin
                        col_addr <= col_addr + 1;
                    end
                end

                L2_FIRE: begin
                    neuron_en <= 1;
                    state     <= L2_CLEAR;
                end

                L2_CLEAR: begin
                    pe_clear <= 1;
                    if (group == L2_GROUPS - 1) begin
                        if (timestep == TSTEPS - 1) begin
                            state <= DONE;
                        end else begin
                            timestep  <= timestep + 1;
                            group     <= 0;
                            col_addr  <= 0;
                            layer_sel <= 0;
                            state     <= L1_WAIT;
                        end
                    end else begin
                        group    <= group + 1;
                        col_addr <= 0;
                        state    <= L2_WAIT;
                    end
                end

                DONE: begin
                    done  <= 1;
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule