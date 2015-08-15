`timescale 1ns / 1ps
module correctErrorsWrapped #(
    parameter NUM_BITS_NUM_UNITS = 2,
    parameter NUM_UNITS = {1'b1, {NUM_BITS_NUM_UNITS{1'b0}}},
    parameter MAX_READ_BIT_WIDTH = 8,
    parameter MAX_KMER_BIT_WIDTH = 6,
    parameter EXTENSION_WIDTH = 5,
    parameter MAX_READ_WIDTH = {1'b1, {MAX_READ_BIT_WIDTH{1'b0}}},
    parameter MIN_READ_WIDTH = 60,
    parameter MAX_KMER_WIDTH = {1'b1, {MAX_KMER_BIT_WIDTH{1'b0}}},
    parameter MIN_KMER_WIDTH = 12,
    parameter QUALITY_WIDTH  = 2,
    parameter NUM_CANDIDATES_BIT_WIDTH = 5,
    parameter NUM_CANDIDATES = {1'b1, {NUM_CANDIDATES_BIT_WIDTH{1'b0}}},
    parameter CANDIDATE_REGISTER_WIDTH = MAX_READ_WIDTH + EXTENSION_WIDTH + MAX_KMER_WIDTH - MIN_KMER_WIDTH
) (
    input clk,
    input rstb,
    input [MAX_READ_BIT_WIDTH - 1 : 0] readLength,
    input [MAX_KMER_BIT_WIDTH - 1 : 0] kmerLength,
    input [2 * MAX_READ_WIDTH - 1 : 0] read,
    input [QUALITY_WIDTH * MAX_READ_WIDTH - 1 : 0] quality,
    input [QUALITY_WIDTH - 1 : 0] qualityThreshold,
    input readValid,
    input ready4Kmer,
    input queryResult,
    input queryResultValid,
    input ready4Candidate,
    input [MAX_READ_BIT_WIDTH - 1 : 0] startPosition,
    input [MAX_READ_BIT_WIDTH - 1 : 0] endPosition,

    output ready4Read,
    output kmerValid,
    output [2 * MAX_KMER_WIDTH - 1 : 0] kmer,
    output [2 * MAX_READ_WIDTH - 1 : 0] candidate,
    output candidateValid,
    output [NUM_CANDIDATES_BIT_WIDTH : 0] candidateNum,
    output candidateNumValid,
    output [2 * MAX_READ_WIDTH - 1 : 0] inputRead
);

//Internal signals and wires
wire [NUM_UNITS-1:0] kmerValidArb;
wire [NUM_UNITS-1:0] ready4KmerArb;
wire [NUM_UNITS-1:0] queryResultArb;
wire [NUM_UNITS-1:0] queryResultValidArb;
wire [NUM_UNITS*2*MAX_KMER_WIDTH-1:0] kmerArb;
wire [NUM_UNITS-1:0] token;
wire [NUM_UNITS-1:0] tokenIn;
wire [NUM_UNITS:0] maskedReady4Read;
wire tokensFifoFull;
wire tokensFifoEmpty;
wire tokensRead;
wire tokensValid;
wire inputFifoFull;
wire inputFifoEmpty;
wire [QUALITY_WIDTH * MAX_READ_WIDTH - 1 : 0] qualityFromIfifo;
wire [2*MAX_READ_WIDTH-1 : 0] readFromIfifo;
wire [MAX_READ_BIT_WIDTH-1:0] startPositionFromIfifo;
wire [MAX_READ_BIT_WIDTH-1:0] endPositionFromIfifo;
wire [MAX_READ_BIT_WIDTH-1:0] readLengthFromIfifo;
wire [NUM_UNITS-1:0] QValid;
wire [NUM_UNITS-1:0] QnValid;
wire [NUM_UNITS-1:0] tokenVal;
wire [NUM_UNITS-1:0] tokenInVal;
wire [2*MAX_READ_WIDTH-1:0] candidateArr[0:NUM_UNITS-1];
wire [NUM_CANDIDATES_BIT_WIDTH:0] candidateNumArr[0:NUM_UNITS-1];
wire [2*MAX_READ_WIDTH-1:0] inputReadArr[0:NUM_UNITS-1];
reg [NUM_CANDIDATES_BIT_WIDTH:0] candidateCount;
wire nextToken;
reg [NUM_BITS_NUM_UNITS-1:0] daisyChain;

assign ready4Read     = ~inputFifoFull;
assign inputFifoValid = readValid; //Need cushioning - do not force to 0 when FIFO is full

genvar m;
generate
    for (m=0;m<NUM_UNITS;m=m+1) begin:tokenValFind
        wire [NUM_UNITS-1:0] val;
        if (m > 0) begin
            assign val   = (token[m] ? m : 'b0) | tokenValFind[m-1].val; //Simpler coding, but not efficient hardware
        end
        else begin
            assign val   = (token[m] ? m : 'b0);
        end
    end
endgenerate

assign tokenVal   = tokenValFind[NUM_UNITS-1].val;

synchronousFifo #(
    .FIFO_DEPTH(8),
    .APPARENT_DEPTH(6),
    .POINTER_SIZE(4),
    .DATA_WIDTH(QUALITY_WIDTH * MAX_READ_WIDTH + 2 * MAX_READ_WIDTH + 3 * MAX_READ_BIT_WIDTH)
) inputFifo (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(inputFifoFull),
    .fifoEmpty(inputFifoEmpty),
    .valid(inputFifoValid),
    .read(inputFifoRead),
    .data({quality, read, startPosition, endPosition, readLength}),
    .out({qualityFromIfifo, readFromIfifo, startPositionFromIfifo, endPositionFromIfifo, readLengthFromIfifo})
);

assign maskedReady4Read[NUM_UNITS] = 1'b0;

genvar k;
generate
    for (k=0; k<NUM_UNITS; k=k+1) begin:PriorityEncode
        assign maskedReady4Read[k] = (daisyChain == k) & ~Wrapped[k].inFifoFull;
    end
endgenerate

assign tokenIn       = maskedReady4Read;
assign tokensValid   = ~inputFifoEmpty & |maskedReady4Read & ~tokensFifoFull;
assign inputFifoRead = tokensValid;
assign tokensRead    = nextToken;

synchronousFifo #(
    .DATA_WIDTH(NUM_UNITS),
    .FIFO_DEPTH(128),
    .APPARENT_DEPTH(120),
    .POINTER_SIZE(8)
) tokens (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(tokensFifoFull),
    .fifoEmpty(tokensFifoEmpty),
    .valid(tokensValid),
    .read(tokensRead),
    .data(tokenIn),
    .out(token)
);

genvar i;
generate
    for (i = 0; i < NUM_UNITS; i=i+1) begin:Wrapped
        wire inFifoFull, inFifoEmpty;
        wire inFifoValid, inFifoRead;
        wire [QUALITY_WIDTH * MAX_READ_WIDTH - 1 : 0] qualityIn;
        wire [2 * MAX_READ_WIDTH - 1 : 0] readIn;
        wire [MAX_READ_BIT_WIDTH - 1 : 0] startPositionIn;
        wire [MAX_READ_BIT_WIDTH - 1 : 0] endPositionIn;
        wire [MAX_READ_BIT_WIDTH - 1 : 0] readLengthIn;
        wire ready4Kmer;
        wire queryResult;
        wire queryResultValid;
        wire [2 * MAX_KMER_WIDTH - 1 : 0] kmer;
        wire kmerValid;
        wire ready4Read;
        wire readValidIn;
        wire [2*MAX_READ_WIDTH - 1 : 0] candidateFromCore;
        wire candidateValidFromCore;
        wire [5:0] candidateNumFromCore;
        wire candidateNumValidFromCore;
        wire [2*MAX_READ_WIDTH - 1 : 0] candidateFromQ;
        wire candidateValidFromQ;
        wire [5:0] candidateNumFromQ;
        wire candidateNumValidFromQ;
        wire ready4CandidateToQ;
        wire [2*MAX_READ_WIDTH-1:0] readBeingCorrected;
        wire [2*MAX_READ_WIDTH-1:0] inputReadFromQ;

        assign kmerArb[(i+1)*2*MAX_KMER_WIDTH-1:i*2*MAX_KMER_WIDTH] = kmer;
        assign kmerValidArb[i] = kmerValid;
        assign queryResultValid = queryResultValidArb[i];
        assign queryResult = queryResultArb[i];
        assign ready4Kmer = ready4KmerArb[i];

        synchronousFifo #(
            .FIFO_DEPTH(8),
            .APPARENT_DEPTH(6),
            .POINTER_SIZE(4),
            .DATA_WIDTH(QUALITY_WIDTH * MAX_READ_WIDTH + 2 * MAX_READ_WIDTH + 3 * MAX_READ_BIT_WIDTH)
        ) inFifo (
            .clk(clk),
            .rstb(rstb),
            .fifoFull(inFifoFull),
            .fifoEmpty(inFifoEmpty),
            .valid(inFifoValid),
            .read(inFifoRead),
            .data({qualityFromIfifo, readFromIfifo, startPositionFromIfifo, endPositionFromIfifo, readLengthFromIfifo}),
            .out({qualityIn, readIn, startPositionIn, endPositionIn, readLengthIn})
        );

        assign inFifoValid = tokensValid & tokenIn[i];
        assign inFifoRead  = ready4Read;
        assign readValidIn = ~inFifoEmpty;

        correctErrors #(
            .MAX_READ_BIT_WIDTH(MAX_READ_BIT_WIDTH),
            .MAX_KMER_BIT_WIDTH(MAX_KMER_BIT_WIDTH),
            .EXTENSION_WIDTH(EXTENSION_WIDTH),
            .MAX_READ_WIDTH(MAX_READ_WIDTH),
            .MIN_READ_WIDTH(MIN_READ_WIDTH),
            .MAX_KMER_WIDTH(MAX_KMER_WIDTH),
            .MIN_KMER_WIDTH(MIN_KMER_WIDTH),
            .QUALITY_WIDTH (QUALITY_WIDTH),
            .NUM_CANDIDATES_BIT_WIDTH(NUM_CANDIDATES_BIT_WIDTH),
            .NUM_CANDIDATES(NUM_CANDIDATES),
            .CANDIDATE_REGISTER_WIDTH(CANDIDATE_REGISTER_WIDTH)
        ) core (
            .clk(clk),
            .rstb(rstb),
            .readLength(readLengthIn),
            .kmerLength(kmerLength),
            .read(readIn),
            .quality(qualityIn),
            .qualityThreshold(qualityThreshold),
            .readValid(readValidIn),
            .ready4Kmer(ready4Kmer),
            .queryResult(queryResult),
            .queryResultValid(queryResultValid),
            .ready4Candidate(ready4Input),
            .startPosition(startPositionIn),
            .endPosition(endPositionIn),
            .ready4Read(ready4Read),
            .kmerValid(kmerValid),
            .kmer(kmer),
            .candidate(candidateFromCore),
            .candidateValid(candidateValidFromCore),
            .candidateNum(candidateNumFromCore),
            .candidateNumValid(candidateNumValidFromCore),
            .inputRead(readBeingCorrected)
        );

        outputQueue #(
            .MAX_READ_BIT_WIDTH(MAX_READ_BIT_WIDTH), 
            .MAX_READ_WIDTH(MAX_READ_WIDTH),
            .NUM_CANDIDATES_BIT_WIDTH(NUM_CANDIDATES_BIT_WIDTH),
            .NUM_CANDIDATES(NUM_CANDIDATES),
            .NUM_BITS_NUM_UNITS(NUM_BITS_NUM_UNITS),
            .NUM_UNITS(NUM_UNITS)
        ) opQ (
            .clk(clk),
            .rstb(rstb),
            .candidateFromCore(candidateFromCore),
            .candidateValidFromCore(candidateValidFromCore),
            .candidateNumFromCore(candidateNumFromCore),
            .candidateNumValidFromCore(candidateNumValidFromCore),
            .readBeingCorrected(readBeingCorrected),
            .ready4Candidate(ready4CandidateToQ),
            .candidate(candidateFromQ),
            .candidateValid(candidateValidFromQ),
            .candidateNum(candidateNumFromQ),
            .candidateNumValid(candidateNumValidFromQ),
            .ready4Input(ready4Input),
            .inputRead(inputReadFromQ)
        );

        assign QValid[i]          = candidateValidFromQ;
        assign QnValid[i]         = candidateNumValidFromQ;
        assign ready4CandidateToQ = (tokenVal == i) & ready4Candidate & ~tokensFifoEmpty;

        assign candidateArr[i]    = candidateFromQ;
        assign candidateNumArr[i] = candidateNumFromQ;
        assign inputReadArr[i]    = inputReadFromQ;
    end

endgenerate

cbfArbitrator #(
    .TOKEN_WIDTH(NUM_BITS_NUM_UNITS),
    .KMER_WIDTH(MAX_KMER_WIDTH)
) arb (
    .clk(clk),
    .rstb(rstb),
    .inKmers(kmerArb),
    .cbfReady(ready4Kmer),
    .kmerPositive(queryResult),
    .resultValid(queryResultValid),
    .kmerValid(kmerValidArb),
    .readyToMasters(ready4KmerArb),
    .kmerToCBF(kmer),
    .kmerValidToCBF(kmerValid),
    .positive(queryResultArb),
    .resultValidM(queryResultValidArb)
);

assign candidateValid    = |(token & QValid);
assign candidateNumValid = |(token & QnValid);
assign candidate         = candidateArr[tokenVal];
assign candidateNum      = candidateNumArr[tokenVal];
assign inputRead         = inputReadArr[tokenVal];

//daisyChain - randomly distribute reads to cores
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        daisyChain <= 'b0;
    end
    else begin
        if (~inputFifoEmpty) daisyChain <= daisyChain + 1;
    end
end

//Flush out a token when needed
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        candidateCount <= 'b0;
    end
    else begin
        if (candidateValid & candidateNumValid & ready4Candidate) begin
            if (candidateCount == candidateNum - 1) begin
                candidateCount <= 'b0;
            end
            else begin
                candidateCount <= candidateCount + 1;
            end
        end
    end
end

assign nextToken = candidateValid & candidateNumValid & ready4Candidate & (candidateCount == candidateNum-1);

endmodule
