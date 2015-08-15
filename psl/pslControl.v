`timescale 1ns / 1ps
module pslControl #(
    parameter Start = 'h90,
    parameter Reset = 'h80,
    parameter Timebase = 'h42
) (
    input ha_pclock,
    input CPU_RESETn,                 //This is a reset from the FPGA board if one is available, otherwise tie this to '1'
    input ha_jval,
    input [7:0] ha_jcom,
    input ha_jcompar,
    input [63:0] ha_jea,
    input ha_jeapar,
    output reg ah_jrunning,
    output reg ah_jdone,
    output ah_jcack,
    output [63:0] ah_jerror,
    output ah_jyield,
    output ah_tbreq,
    output ah_paren,
    output reg rstb,
    output reg [63:0] wed,
    input finished,
    input abort,
    input [7:0] ha_croom,
    output reg [7:0] num_credits,
    output reset_cmd_received
);

//Reset state-machine states
localparam IDLE = 2'b00;
localparam WAIT_FOR_COUNT = 2'b01;
localparam WAIT_FOR_FOUR_CYCLES = 2'b10;
localparam DO_RESET = 2'b11;

//Internal wires and registers
reg [10:0] reset_counter;
reg [1:0] reset_state_ns;
reg [1:0] reset_state;
wire clk;

assign all_resetb = CPU_RESETn & ~reset_cmd_received;

//All signals currently driven to zero
assign ah_jerror = 64'b0;
assign ah_jcack  = 1'b0;
assign ah_jyield = 1'b0;
assign ah_tbreq  = 1'b0;
assign ah_paren  = 1'b0;

//For convenience
assign clk = ha_pclock;

//Reset is driven combinatorially now - actually good to meet recovery and removal timings
always @(posedge clk or negedge all_resetb) begin
    if (~all_resetb) begin
        rstb <= 1'b1;
    end
    else begin
        rstb <= ~((reset_state == DO_RESET) && (reset_counter != 7));
    end
end

//Capture WED, drive ah_jrunning high
always @(posedge clk or negedge all_resetb) begin
    if (~all_resetb) begin
        wed          <= 64'b0;
        ah_jrunning  <= 1'b0;
        ah_jdone     <= 1'b0;
        num_credits  <= 8'b0;
    end
    else begin
        if (ah_jdone) begin
            ah_jdone <= 1'b0;
        end
        else begin
            if ((reset_state == DO_RESET) && (reset_counter[3:0] == 7)) begin
                ah_jdone <= 1'b1;
            end
        end

        if (ha_jval && (ha_jcom == Reset)) begin
            ah_jrunning <= 1'b0;
        end
        else begin
            if (ha_jval && (ha_jcom == Start)) begin
                wed         <= ha_jea;
                ah_jrunning <= 1'b1;
                num_credits <= ha_croom;
            end
            else begin
                if (finished | abort) begin
                    ah_jrunning <= 1'b0;
                end
            end
        end
    end
end

//Reset state - will eventually reset if there is a Reset Command at that happens after CPU_RESETn - may take a different number of cycles each time
always @* begin
    case (reset_state)
        IDLE : begin
            reset_state_ns <= reset_cmd_received ? WAIT_FOR_COUNT : reset_state;
        end
        WAIT_FOR_COUNT : begin
            reset_state_ns <= ~reset_cmd_received & (reset_counter == 1023) ? WAIT_FOR_FOUR_CYCLES : reset_state;
        end
        WAIT_FOR_FOUR_CYCLES : begin
            reset_state_ns <= reset_cmd_received ? WAIT_FOR_COUNT : (reset_counter[3:0] == 3) ? DO_RESET : reset_state;
        end
        DO_RESET : begin
            reset_state_ns <= reset_cmd_received ? WAIT_FOR_COUNT : (reset_counter[3:0] == 7) ? IDLE : reset_state;
        end
        default : begin
            reset_state_ns <= reset_cmd_received ? WAIT_FOR_COUNT : IDLE;
        end
    endcase
end

////////////State machine for reset etc//////////////
//                 ___     ___     ___     ___     ___     ___     ___     ___     ___
//clk          ___|   |___|   |___|   |___|   |___|   |___|   |___|   |___|   |___|   |
//
//state           |WAIT4CY|                 DO_RESET              |      IDLE     |       
//
//counter         |   0   |  ...  |   4   |   5   |   6   |   7   |   8   |   1   |
//                                                                 _______
//ah_jdone           ________________________________________________|       |________
/////////////////////////////////////////////////////

//Pulse to PSL command to stop issuing any more commands
assign reset_cmd_received = (ha_jval && (ha_jcom == Reset));

//Reset state and flop out reset
always @(posedge clk or negedge CPU_RESETn) begin
    if (~CPU_RESETn) begin
        reset_state <= IDLE;
    end
    else begin
        reset_state <= reset_state_ns;
    end
end

//Reset counter
always @(posedge clk or negedge CPU_RESETn) begin
    if (~CPU_RESETn) begin
        reset_counter <= 'b0;
    end
    else begin
        if ((reset_state == IDLE) | reset_cmd_received) begin
            reset_counter <= 'b0;
        end
        else begin
            reset_counter <= reset_counter + 1;
        end
    end
end

endmodule
