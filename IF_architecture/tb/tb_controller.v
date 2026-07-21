`timescale 1ns/1ps

module tb_controller;

    // Parameters 
    parameter integer L1_IN  = 784;
    parameter integer L1_OUT = 128;
    parameter integer L2_IN  = 128;
    parameter integer L2_OUT = 10;
    parameter integer PES    = 8;
    parameter integer TSTEPS = 10;

    // DUT Signals
    reg clk;
    reg reset_n;
    reg start;

    wire pe_en;
    wire pe_clear;
    wire neuron_en;
    wire [$clog2(L1_OUT/PES)-1:0] group;
    wire [$clog2(L1_IN)-1:0]      col_addr;
    wire layer_sel;
    wire [$clog2(TSTEPS)-1:0]     timestep;
    wire [3:0]                    active_pes;
    wire done;

    //  Instantiate the Controller 
    controller #(
        .L1_IN(L1_IN),
        .L1_OUT(L1_OUT),
        .L2_IN(L2_IN),
        .L2_OUT(L2_OUT),
        .PES(PES),
        .TSTEPS(TSTEPS)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .start(start),
        .pe_en(pe_en),
        .pe_clear(pe_clear),
        .neuron_en(neuron_en),
        .group(group),
        .col_addr(col_addr),
        .layer_sel(layer_sel),
        .timestep(timestep),
        .active_pes(active_pes),
        .done(done)
    );

    // Clock Generation
    initial clk = 0;
    always #5 clk = ~clk; // 10ns clock period (100 MHz)

    // Simulation Stimulus 
    initial begin
        // 1. Initialize Inputs
        reset_n = 0;
        start   = 0;

        // 2. Hold reset for a few cycles
        repeat(5) @(posedge clk);
        reset_n = 1;
        
        $display("=== Controller Reset Complete ===");
        
        // 3. Pulse the Start signal
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        $display("=== Controller Started ===");

        // 4. Wait for the controller to finish all timesteps
        wait(done == 1'b1);
        
        $display("=== Controller Finished Successfully! ===");
        
        // Let it rest for a moment, then end simulation
        repeat(10) @(posedge clk);
        $finish;
    end

    // Progress Monitor 
    // This will print to the console whenever the timestep or layer changes
    // so you don't have to guess what the simulation is doing.
    reg prev_layer;
    reg [$clog2(TSTEPS)-1:0] prev_timestep;
    
    initial begin
        prev_layer = 0;
        prev_timestep = 0;
    end

    always @(posedge clk) begin
        if (timestep != prev_timestep) begin
            $display("[%0t ns] Advanced to Timestep: %0d", $time, timestep);
            prev_timestep = timestep;
        end
        if (layer_sel != prev_layer) begin
            $display("[%0t ns] Switched to Layer: %0d (Group 0)", $time, layer_sel + 1);
            prev_layer = layer_sel;
        end
    end

    // Timeout Safeguard 
    // A full network run is ~128,000 cycles. We set a timeout at 200,000.
    initial begin
        #2000000; 
        $display("TIMEOUT: Simulation took too long. Check your state machine!");
        $finish;
    end

endmodule
