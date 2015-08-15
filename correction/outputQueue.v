`timescale 1ns / 1ps
module outputQueue #(
    parameter MAX_READ_BIT_WIDTH = 8,
    parameter MAX_READ_WIDTH = {1'b1, {MAX_READ_BIT_WIDTH{1'b0}}},
    parameter NUM_CANDIDATES_BIT_WIDTH = 5,
    parameter NUM_CANDIDATES = {1'b1,{NUM_CANDIDATES_BIT_WIDTH{1'b0}}},
    parameter NUM_BITS_NUM_UNITS = 3,
    parameter NUM_UNITS = {1'b1,{NUM_BITS_NUM_UNITS{1'b0}}}
) (
    input clk,
    input rstb,
    input [2*MAX_READ_WIDTH-1:0] candidateFromCore,
    input [2*MAX_READ_WIDTH-1:0] readBeingCorrected,
    input candidateValidFromCore,
    input [NUM_CANDIDATES_BIT_WIDTH:0] candidateNumFromCore,
    input candidateNumValidFromCore,
    input ready4Candidate,
    output [2*MAX_READ_WIDTH-1:0] candidate,
    output candidateValid,
    output candidateNumValid,
    output [NUM_CANDIDATES_BIT_WIDTH:0] candidateNum,
    output [2*MAX_READ_WIDTH-1:0] inputRead,
    output ready4Input
);

//Internal wires/registers
reg [NUM_UNITS-1:0] fifoOccupied;
reg [NUM_BITS_NUM_UNITS-1:0] daisyChainIn;
reg [NUM_BITS_NUM_UNITS-1:0] daisyChainOut;
wire outputFifoSelectedEmpty;
wire outputFifoSelectedFull;
wire [NUM_UNITS-1:0] fifoFull;
wire [NUM_UNITS-1:0] fifoEmpty;
wire [NUM_UNITS-1:0] maskOut;
wire [NUM_UNITS-1:0] maskIn;
reg [NUM_CANDIDATES_BIT_WIDTH:0] numCandidatesCounter;
wire writeIntoFifo;
wire readFromFifo;
reg [NUM_UNITS-1:0] read_active;

wire [2*MAX_READ_WIDTH-1:0] candidatesArray[0:NUM_UNITS-1];
wire [2*MAX_READ_WIDTH-1:0] inputReadsArray[0:NUM_UNITS-1];
wire [NUM_CANDIDATES_BIT_WIDTH:0] candidatesNumArray[0:NUM_UNITS-1];

//Control the FIFO occupied signal
genvar i;
generate
    for (i = 0; i < NUM_UNITS; i = i + 1) begin:occupiedStatus
        always @(posedge clk or negedge rstb) begin
            if (~rstb) begin
                fifoOccupied[i] <= 1'b0;
            end
            else begin
                if (writeIntoFifo && (daisyChainIn == i)) begin
                    if (numCandidatesCounter == candidateNumFromCore - 1) begin
                        fifoOccupied[i] <= 1'b1;
                    end
                end
                else begin
                    if ((daisyChainOut == i) & |(maskOut & fifoEmpty)) begin
                        fifoOccupied[i] <= 1'b0;
                    end
                end
            end
        end
    end //end for
endgenerate

assign writeIntoFifo = |(maskIn & ~fifoOccupied) & candidateValidFromCore & candidateNumValidFromCore;
assign readFromFifo  = |(maskOut) & ready4Candidate;

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        numCandidatesCounter <= 'b0;
        daisyChainIn         <= 'b0;
    end
    else begin
        if (candidateValidFromCore & candidateNumValidFromCore) begin
            if (writeIntoFifo) begin
                if (numCandidatesCounter == candidateNumFromCore - 1) begin
                    numCandidatesCounter <= 'b0;
                    daisyChainIn         <= daisyChainIn + 1;
                end
                else begin
                    numCandidatesCounter <= numCandidatesCounter + 1;
                end
            end
        end
        else begin
            numCandidatesCounter <= 'b0;
        end
    end
end

genvar k;
generate
    for (k = 0; k < NUM_UNITS; k = k + 1) begin:outputFifos
        wire [2*MAX_READ_WIDTH-1:0] candidateFifo;
        wire [NUM_CANDIDATES_BIT_WIDTH:0] candidateNumFifo;
        wire [2*MAX_READ_WIDTH-1:0] readBeingCorrectedToFifo;
        wire [2*MAX_READ_WIDTH-1:0] readBeingCorrectedFromFifo;

        assign readBeingCorrectedToFifo = readBeingCorrected;
       
        synchronousFifo #(
            .DATA_WIDTH(4 * (MAX_READ_WIDTH) + (NUM_CANDIDATES_BIT_WIDTH+1)),
            .FIFO_DEPTH(NUM_CANDIDATES),
            .APPARENT_DEPTH(NUM_CANDIDATES-2),
            .POINTER_SIZE(NUM_CANDIDATES_BIT_WIDTH+1)
        ) fifo (
            .clk(clk),
            .rstb(rstb),
            .valid(maskIn[k] & ~fifoOccupied[k] & ~fifoFull[k] & candidateValidFromCore & candidateNumValidFromCore),
            .fifoFull(fifoFull[k]),
            .fifoEmpty(fifoEmpty[k]),
            .read((daisyChainOut == k) & ready4Candidate & candidateValid & candidateNumValid),
            .data({candidateFromCore, readBeingCorrectedToFifo, candidateNumFromCore}),
            .out({candidateFifo, readBeingCorrectedFromFifo, candidateNumFifo})
        );

        assign maskOut[k] = (k == daisyChainOut);
        assign maskIn[k]  = (k == daisyChainIn);
 
        assign candidatesArray[k] = candidateFifo;
        assign candidatesNumArray[k] = candidateNumFifo;
        assign inputReadsArray[k] = readBeingCorrectedFromFifo;
    end
endgenerate

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        daisyChainOut <= 'b0;
        read_active <= 'b0;
    end
    else begin
        if (ready4Candidate) begin
            read_active <= maskOut & ~fifoEmpty;
        end
        else begin
            if (|(maskOut & fifoEmpty & read_active)) begin
                daisyChainOut <= daisyChainOut + 1;
                read_active   <= 'b0;
            end
        end
    end
end

assign candidateValid     = |(maskOut & ~fifoEmpty & fifoOccupied) & ready4Candidate;
assign candidateNumValid  = |(maskOut & ~fifoEmpty & fifoOccupied) & ready4Candidate;
assign ready4Input        = |(maskIn & ~fifoOccupied) & candidateValidFromCore & candidateNumValidFromCore;
assign candidate          = candidatesArray[daisyChainOut];
assign candidateNum       = candidatesNumArray[daisyChainOut];
assign inputRead          = inputReadsArray[daisyChainOut];


endmodule
