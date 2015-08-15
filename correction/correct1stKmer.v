`timescale 1ns / 1ps

`define NO_INTERNAL_FIFO

module correct1stKmer #(
    parameter MAX_READ_BIT_WIDTH = 8,
    parameter MAX_KMER_BIT_WIDTH = 6,
    parameter MAX_READ_WIDTH = {1'b1, {MAX_READ_BIT_WIDTH{1'b0}}},
    parameter MAX_KMER_WIDTH = {1'b1, {MAX_KMER_BIT_WIDTH{1'b0}}},
    parameter QUALITY_WIDTH = 2,
    parameter NUM_CANDIDATES_BIT_WIDTH = 5,
    parameter NUM_CANDIDATES = {1'b1, {NUM_CANDIDATES_BIT_WIDTH{1'b0}}}
) (
    input clk,
    input rstb,
    input [2 * MAX_READ_WIDTH - 1 : 0] read,
    input [QUALITY_WIDTH * MAX_READ_WIDTH - 1 : 0] quality,
    input [QUALITY_WIDTH - 1 : 0] qualityThreshold,
    input [MAX_READ_BIT_WIDTH - 1 : 0] startPosition,
    input [MAX_READ_BIT_WIDTH - 1 : 0] endPosition,
    input [MAX_READ_BIT_WIDTH - 1 : 0] readLength,
    input [MAX_KMER_BIT_WIDTH - 1 : 0] kmerLength,
    input readValid,
    input ready4Candidate,
    input ready4Kmer,
    input queryResult,
    input queryResultValid,

    output success,
    output ready4Read,
    output candidateValid,
    output [2 * MAX_READ_WIDTH - 1 : 0] candidate,
    output [NUM_CANDIDATES_BIT_WIDTH : 0] candidateNum,
    output candidateNumValid,
    output [2 * MAX_KMER_WIDTH - 1 : 0] kmer,
    output kmerValid
);

localparam WAIT_FOR_CORRECTIONS = 'h0;
localparam WAIT_FOR_READOUT     = 'h1;
localparam STALL_FOR_FIFO_READY = 'h2;
localparam RAISE_NUM_VALID      = 'h3;
localparam FIFO_EMPTY           = 'h4;

wire [MAX_KMER_BIT_WIDTH - 1 : 0] numLowQBases;
wire lowQBaseCorrection;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerTryOneBase;
wire kmerValidTryOneBase;
wire [2 * MAX_READ_WIDTH - 1 : 0] candidateTryOneBase;
wire candidateValidTryOneBase;
wire ready4ReadTryOneBase;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerTry3Bases;
wire kmerValidTry3Bases;
wire [2 * MAX_READ_WIDTH - 1 : 0] candidateTry3Bases;
wire candidateValidTry3Bases;
wire ready4ReadTry3Bases;
wire [2 * MAX_READ_WIDTH - 1 : 0] readIn;
wire [QUALITY_WIDTH * MAX_READ_WIDTH - 1 : 0] qualityIn;
wire inputFifoFull;
wire inputFifoEmpty;
wire readInFifo;
wire readInValid;
wire correctFirstKmer;
wire [2 * MAX_READ_WIDTH - 1 : 0] startPositionIn;
wire [2 * MAX_READ_WIDTH - 1 : 0] endPositionIn;
wire [2 * MAX_READ_WIDTH - 1 : 0] readLengthIn;
reg [NUM_CANDIDATES_BIT_WIDTH : 0] numCandidates;
reg [2:0] state;
wire outputFifoEmpty;
wire [2 * MAX_READ_WIDTH - 1 : 0] candidateForOutput;
wire outputFifoFull;
wire outputFifoValid;
reg [2*MAX_READ_WIDTH-1:0] readStage0;
reg [2*MAX_READ_WIDTH-1:0] qualityStage0;
wire [MAX_KMER_BIT_WIDTH-1:0] num_low_q_bases;
wire score_valid;

`ifndef NO_INTERNAL_FIFO
//Input FIFO - like reservation stations
synchronousFifo #(
    .DATA_WIDTH(2 * MAX_READ_WIDTH + QUALITY_WIDTH * MAX_READ_WIDTH + 3 * MAX_READ_BIT_WIDTH),
    .FIFO_DEPTH(16),
    .POINTER_SIZE(5),
    .APPARENT_DEPTH(12)
) inputFifo (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(inputFifoFull),
    .data({read, startPosition, endPosition, readLength, quality}),
    .valid(ready4Read & readValid),
    .out({readIn, startPositionIn, endPositionIn, readLengthIn, qualityIn}),
    .fifoEmpty(inputFifoEmpty),
    .read(readInFifo)
);
assign ready4Read      = ~inputFifoFull;
assign readInValid     = ~inputFifoEmpty;
assign readInFifo      = (state == FIFO_EMPTY);
`else
assign ready4Read      = (state == FIFO_EMPTY);    
assign readInValid     = readValid;
assign readIn          = read;
assign startPositionIn = startPosition;
assign endPositionIn   = endPosition;
assign readLengthIn    = readLength;
assign qualityIn       = quality;
assign readInFifo      = ready4Read;
`endif

//state is used to control the valid signals to the individual blocks
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        state <= WAIT_FOR_CORRECTIONS;
    end
    else begin
        if (readInValid) begin
            case(state)
                WAIT_FOR_CORRECTIONS : begin
                    if (correctFirstKmer) begin
                        if ((lowQBaseCorrection & ready4ReadTry3Bases) | (~lowQBaseCorrection & ready4ReadTryOneBase)) begin
                            if (ready4Candidate) begin
                                state <= WAIT_FOR_READOUT;
                            end
                            else begin
                                state <= STALL_FOR_FIFO_READY;   //ready4Read* signals are single cycle pulses - need to capture it
                            end
                        end
                    end
                    else begin
                        if (~outputFifoFull) begin
                            if (ready4Candidate) begin
                                state <= WAIT_FOR_READOUT;
                            end
                            else begin
                                state <= STALL_FOR_FIFO_READY;    //Do not really need this here, but will anyway do it for uniformity
                            end
                        end
                    end
                end
                STALL_FOR_FIFO_READY : begin 
                        //This is exclusively for protecting afterKmerFifo - if it is full, I cannot control the pulse that goes to it - since its a ready4Read pulse
                                    //So I will check it beforehand
                    if (ready4Candidate) begin
                        state <= WAIT_FOR_READOUT;
                    end
                end
                WAIT_FOR_READOUT : begin
                    if (outputFifoEmpty) begin
                        state <= FIFO_EMPTY;
                    end
                end
                default : begin
                    state <= WAIT_FOR_CORRECTIONS;
                end
            endcase
        end
        else begin
            state <= WAIT_FOR_CORRECTIONS;
        end
    end
end

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        numCandidates <= {(NUM_CANDIDATES_BIT_WIDTH+1){1'b0}};
    end
    else begin
        if (readInFifo) begin
            numCandidates <= {(NUM_CANDIDATES_BIT_WIDTH+1){1'b0}};
        end
        else begin
            if (outputFifoValid) begin //Some candidates are discarded
                numCandidates <= numCandidates + 1;
            end
        end
    end
end

assign candidateNum      = correctFirstKmer ? numCandidates : 'b1;
assign candidateNumValid = (state == WAIT_FOR_READOUT); 
assign correctFirstKmer  = ((startPositionIn == 0) && (endPositionIn == readLengthIn - 1)) & readValid;

//Compute the number of low quality bases
numLowQBases #(
    .MAX_KMER_BIT_WIDTH(MAX_KMER_BIT_WIDTH),
    .MAX_KMER_WIDTH(MAX_KMER_WIDTH)
) lowQBaseCount (
    .clk(clk),
    .rstb(rstb),
    .valid(readInValid),
    .done(ready4Read),
    .kmer_length(kmerLength),
    .quality(quality[2*MAX_KMER_WIDTH-1:0]),
    .threshold(qualityThreshold),
    .num_low_q_bases(num_low_q_bases),
    .valid_score(score_valid)
);

assign numLowQBases = num_low_q_bases;
assign lowQBaseCorrection = ((numLowQBases <= 3) && (numLowQBases != 0)) & score_valid & readInValid;

//Flop the reads internally to help timing
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        readStage0 <= {MAX_READ_WIDTH{2'b0}};
        qualityStage0 <= {MAX_READ_WIDTH{2'b0}};
    end
    else begin
        readStage0 <= readIn;
        qualityStage0 <= qualityIn;
    end
end

fourKKmers #(
    .MAX_READ_BIT_WIDTH(MAX_READ_BIT_WIDTH),
    .MAX_KMER_BIT_WIDTH(MAX_KMER_BIT_WIDTH),
    .QUALITY_WIDTH(QUALITY_WIDTH)
) tryOneBaseAtATime (
    .clk(clk),
    .rstb(rstb),
    .read(readStage0),
    .quality(qualityStage0),
    .kmerLength(kmerLength),
    .readValid(readInValid & score_valid & ~lowQBaseCorrection & (state == 0)),
    .ready4Candidate(1'b1),
    .ready4Kmer(ready4Kmer),
    .queryResultValid(queryResultValid & ~lowQBaseCorrection),
    .queryResult(queryResult),

    .kmer(kmerTryOneBase),
    .kmerValid(kmerValidTryOneBase),
    .candidate(candidateTryOneBase),
    .candidateValid(candidateValidTryOneBase),
    .ready4Read(ready4ReadTryOneBase)
);

lowQBaseChangePipelined #(
    .MAX_READ_BIT_WIDTH(MAX_READ_BIT_WIDTH),
    .MAX_KMER_BIT_WIDTH(MAX_KMER_BIT_WIDTH),
    .QUALITY_WIDTH(QUALITY_WIDTH)
) try3Bases (
    .clk(clk),
    .rstb(rstb),
    .read(readStage0),
    .quality(qualityStage0[2*MAX_KMER_WIDTH-1:0]),
    .kmerLength(kmerLength),
    .qualityThreshold(qualityThreshold),
    .readValid(readInValid & score_valid & lowQBaseCorrection & (state == 0)),
    .ready4Candidate(1'b1),
    .ready4Kmer(ready4Kmer),
    .queryResult(queryResult),
    .queryResultValid(queryResultValid & lowQBaseCorrection),

    .kmer(kmerTry3Bases),
    .kmerValid(kmerValidTry3Bases),
    .candidate(candidateTry3Bases),
    .candidateValid(candidateValidTry3Bases),
    .ready4Read(ready4ReadTry3Bases)
);

assign kmer                = lowQBaseCorrection ? kmerTry3Bases : kmerTryOneBase;
assign kmerValid           = lowQBaseCorrection ? kmerValidTry3Bases : kmerValidTryOneBase;
assign candidateInter      = lowQBaseCorrection ? candidateTry3Bases : candidateTryOneBase;
assign candidateValidInter = lowQBaseCorrection ? candidateValidTry3Bases : candidateValidTryOneBase;
assign success             = (numCandidates != 0);

//We just throw away stuff if there are too many candidates, so don't worry
synchronousFifo #(
    .DATA_WIDTH(2 * MAX_READ_WIDTH),
    .APPARENT_DEPTH(NUM_CANDIDATES - 4),
    .FIFO_DEPTH(NUM_CANDIDATES),
    .POINTER_SIZE(NUM_CANDIDATES_BIT_WIDTH + 1)
) outputFifo (
    .clk(clk),
    .rstb(rstb),
    .data(correctFirstKmer ? (lowQBaseCorrection ? candidateTry3Bases : candidateTryOneBase) : readIn),
    .valid(outputFifoValid),
    .out(candidateForOutput),
    .fifoFull(outputFifoFull),
    .fifoEmpty(outputFifoEmpty),
    .read(ready4Candidate & candidateValid)
);

assign outputFifoValid = (candidateValidInter & ~outputFifoFull) | (~correctFirstKmer & readInValid & (state == WAIT_FOR_CORRECTIONS) & ~outputFifoFull);
assign candidateValid  = (state == WAIT_FOR_READOUT) & ~outputFifoEmpty;

//assign candidate = success ? candidateForOutput : readIn;
assign candidate = candidateForOutput;

//Solutions:
//1. Put a FIFO in the lowQBase* and fourKKmers* modules for collecting the outputs - more coherent interface design across all blocks
//2. Use a state-machine in this block to pull down readValid to either of the aforementioned blocks - uses less hardware
//Conclusion - going to go with '3' - the interface needn't be coherent EVERYWHERE. Only at higher levels of hierarchy

endmodule
