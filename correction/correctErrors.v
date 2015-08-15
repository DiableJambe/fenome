`timescale 1ns / 1ps

`ifndef NO_INTERNAL_FIFO
    `define NO_INTERNAL_FIFO
`endif

module correctErrors #(
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

//Internal state machine
localparam DO_LEFT_SHIFT    = 'h0;
localparam DO_CORRECTION    = 'h1;
localparam READ_OUTPUT_FIFO = 'h2;
localparam IDLE             = 'h3;
localparam DO_NOT_BOTHER    = 'h4;
localparam FIFO_EMPTY       = 'h5;

//Internal registers and wires
wire [QUALITY_WIDTH * MAX_READ_WIDTH - 1 : 0] qualityIn;
wire [2 * MAX_READ_WIDTH - 1 : 0] readIn;
wire [MAX_READ_BIT_WIDTH - 1 : 0] startPositionIn;
wire [MAX_READ_BIT_WIDTH - 1 : 0] endPositionIn;
wire [MAX_READ_BIT_WIDTH - 1 : 0] readLengthIn;
wire ready4Candidate1stKmerCorrect;
wire ready4Kmer1stKmerCorrect;
wire queryResult1stKmerCorrect;
wire queryResultValid1stKmerCorrect;
wire ready4Read1stKmerCorrect;
wire candidateValid1stKmerCorrect;
wire [2 * MAX_READ_WIDTH - 1 : 0] candidate1stKmerCorrect;
wire [NUM_CANDIDATES_BIT_WIDTH : 0] candidateNum1stKmerCorrect; //Warning!!! Fixed size
wire candidateNumValid1stKmerCorrect;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmer1stKmerCorrect;
wire kmerValid1stKmerCorrect;
wire successAfter1stKmerCorrect;
wire afterKmerCorrectFifoFull;
wire afterKmerCorrectFifoEmpty;
wire afterKmerCorrectValid;
wire [2 * MAX_READ_WIDTH - 1 : 0] readForCorrection;
wire [QUALITY_WIDTH * MAX_READ_WIDTH - 1 : 0] qualityForCorrection;
wire [MAX_READ_BIT_WIDTH - 1 : 0] startPositionForCorrection;
wire [MAX_READ_BIT_WIDTH - 1 : 0] endPositionForCorrection;
wire [MAX_READ_BIT_WIDTH - 1 : 0] readLengthForCorrection;
wire readAfterKmerFifo;
wire [2 * MAX_READ_WIDTH - 1 : 0] candidateForLeftShift;
wire candidateArrayForLeftShiftFull;
wire candidateArrayForLeftShiftEmpty;
wire candidateArrayForLeftShiftValid;
wire candidateArrayAfterLeftShiftEmpty;
wire candidateArrayAfterLeftShiftFull;
wire candidateArrayAfterLeftShiftValid;
wire candidateArrayAfterLeftShiftRead;
wire [2 * MAX_READ_WIDTH - 1 : 0] candidateFromInst;
wire [2 * MAX_READ_WIDTH - 1 : 0] candidateAfterLeftShift;
wire inputFifoFull;
wire inputFifoEmpty;
wire isNoSolid;
wire dontBother;
wire [NUM_CANDIDATES_BIT_WIDTH : 0] candidateNumForCorrection;
reg [2:0] state;
wire outputFifoEmpty;
wire outputFifoFull;
wire ready4ReadInst;
wire candidateValidInst;
wire candidateNumValidInst;
wire outputFifoRead;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerInst;
wire [2 * MAX_READ_WIDTH - 1 : 0] candidateForOutput;
reg candidateNumValidInst_del;
wire noCorrectionsInst;
wire ready4CandidateInst;
reg candidateNumValidSM;
wire candidateNumValidPS;
reg [NUM_CANDIDATES_BIT_WIDTH : 0] numCandidates;
reg ready4ReadInst_delayed;
wire readValidFirstKmerCorrect;
wire [2*MAX_READ_WIDTH-1:0] outputFifoData;
reg [NUM_CANDIDATES_BIT_WIDTH : 0] numCandidatesLeftShifted;
wire [2*MAX_READ_WIDTH-1:0] readInst;

//Name changes due to old code
assign ready4Read                = ready4Read1stKmerCorrect;
assign qualityIn                 = quality;
assign readIn                    = read;
assign startPositionIn           = startPosition;
assign endPositionIn             = endPosition;
assign readLengthIn              = readLength;
assign readValidFirstKmerCorrect = readValid;

//For no solid island correction, correct the 1st k-mer
correct1stKmer #(
    .MAX_READ_BIT_WIDTH(MAX_READ_BIT_WIDTH),
    .MAX_KMER_BIT_WIDTH(MAX_KMER_BIT_WIDTH),
    .MAX_READ_WIDTH(MAX_READ_WIDTH),
    .MAX_KMER_WIDTH(MAX_KMER_WIDTH),
    .QUALITY_WIDTH(QUALITY_WIDTH),
    .NUM_CANDIDATES_BIT_WIDTH(NUM_CANDIDATES_BIT_WIDTH)
) firstKmerCorrect (
    .clk(clk),
    .rstb(rstb),
    .read(readIn),
    .quality(qualityIn),
    .qualityThreshold(qualityThreshold),
    .startPosition(startPositionIn),
    .endPosition(endPositionIn),
    .readLength(readLengthIn),
    .kmerLength(kmerLength),
    .readValid(readValidFirstKmerCorrect),
    .success(successAfter1stKmerCorrect),
    .ready4Candidate(ready4Candidate1stKmerCorrect),
    .ready4Kmer(ready4Kmer1stKmerCorrect),  
    .queryResult(queryResult1stKmerCorrect),
    .queryResultValid(queryResultValid1stKmerCorrect),
    .ready4Read(ready4Read1stKmerCorrect),
    .candidateValid(candidateValid1stKmerCorrect),
    .candidate(candidate1stKmerCorrect),
    .candidateNum(candidateNum1stKmerCorrect),
    .candidateNumValid(candidateNumValid1stKmerCorrect),
    .kmer(kmer1stKmerCorrect), 
    .kmerValid(kmerValid1stKmerCorrect)
);

assign ready4Candidate1stKmerCorrect = ~(afterKmerCorrectFifoFull | candidateArrayForLeftShiftFull);

//Pull the read from inputFifo and keep it here when we are done with correcting the first k-mer
synchronousFifo #(
    .DATA_WIDTH(2 * MAX_READ_WIDTH + QUALITY_WIDTH * MAX_READ_WIDTH + (NUM_CANDIDATES_BIT_WIDTH+1) + 3 * MAX_READ_BIT_WIDTH),
    .POINTER_SIZE(5),
    .FIFO_DEPTH(16),
    .APPARENT_DEPTH(12)
) afterFirstKmerCorrect (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(afterKmerCorrectFifoFull),
    .fifoEmpty(afterKmerCorrectFifoEmpty),
    .data({readIn, qualityIn, candidateNum1stKmerCorrect, startPositionIn, endPositionIn, readLengthIn}),
    .out({readForCorrection, qualityForCorrection, candidateNumForCorrection, startPositionForCorrection, endPositionForCorrection, readLengthForCorrection}),
    .valid(afterKmerCorrectValid),
    .read(readAfterKmerFifo)
);

assign afterKmerCorrectValid = ready4Read1stKmerCorrect;
assign isNoSolid             = (startPositionForCorrection == 0) & (endPositionForCorrection == readLengthForCorrection - 1) & ~afterKmerCorrectFifoEmpty;

//Note that candidateArrayForLeftShift can contain candidates for multiple reads at any given time
synchronousFifo #(
    .DATA_WIDTH(2 * MAX_READ_WIDTH),
    .FIFO_DEPTH(256),
    .APPARENT_DEPTH(192), //64 * 3 = 192 :- this is the maximum number of candidates for the first k-mer for any read for max k-mer size of 64
                              //We add sufficient extra space for outstanding k-mer queries. The size of the k-mer array in correct1stKmer is 16
    .POINTER_SIZE(9)
) candidateArrayForLeftShift (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(candidateArrayForLeftShiftFull),
    .fifoEmpty(candidateArrayForLeftShiftEmpty),
    .out(candidateForLeftShift),
    .data(candidate1stKmerCorrect),
    .valid(candidateArrayForLeftShiftValid),
    .read(candidateArrayForLeftShiftRead)
);

assign candidateArrayForLeftShiftValid = candidateValid1stKmerCorrect & candidateNumValid1stKmerCorrect & ready4Candidate1stKmerCorrect;

//Count the number of candidates that have been left shifted - cannot just wait for the FIFO to go empty
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        numCandidatesLeftShifted <= {(NUM_CANDIDATES_BIT_WIDTH+1){1'b0}};
    end
    else begin
        if (state == DO_LEFT_SHIFT) begin
            if (ready4ReadInst) begin
                numCandidatesLeftShifted <= numCandidatesLeftShifted + 1;
            end
        end
        else begin
            numCandidatesLeftShifted <= {(NUM_CANDIDATES_BIT_WIDTH+1){1'b0}};
        end
    end
end

//State machine that controls post 1st k-mer correction
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        state <= IDLE;
    end
    else begin
        case (state)
            IDLE : begin
                if (~afterKmerCorrectFifoEmpty) begin
                    if (isNoSolid) begin
                        state <= DO_LEFT_SHIFT;
                        if (candidateNumForCorrection == 0) begin
                            state <= DO_NOT_BOTHER;
                        end
                    end
                    else begin
                        state <= DO_CORRECTION;
                    end
                end
            end
            DO_LEFT_SHIFT : begin
                if (numCandidatesLeftShifted == candidateNumForCorrection) begin
                    if (candidateArrayAfterLeftShiftEmpty) begin
                        state <= DO_NOT_BOTHER;
                    end
                    else begin
                        state <= DO_CORRECTION;
                    end
                end
            end
            DO_CORRECTION : begin //If correction fails, findCandidates sends out the input read - so that is taken care of here
                if (isNoSolid) begin
                    if (candidateArrayAfterLeftShiftEmpty) begin
                        state <= READ_OUTPUT_FIFO;
                    end
                end
                else begin
                    if (ready4ReadInst) begin
                        state <= READ_OUTPUT_FIFO;
                    end
                end
            end
            DO_NOT_BOTHER : begin
                if (~outputFifoFull) state <= READ_OUTPUT_FIFO; //Dummy check - just a cycle to push in the same input candidate
            end
            READ_OUTPUT_FIFO : begin
                if (outputFifoEmpty) begin
                    state <= FIFO_EMPTY;
                end
            end
            default : begin
                state <= IDLE;
            end
        endcase
    end
end

assign candidateArrayForLeftShiftRead  = ((state == DO_LEFT_SHIFT) | ((state == DO_CORRECTION) & ~isNoSolid)) & ready4ReadInst;
assign ready4CandidateInst             = candidateNumValidInst & candidateValidInst;

//This will store valid candidates after left-shifting
//Note that candidateArrayAfterLeftShift CANNOT contain candidates for more than one read at any point in time
synchronousFifo #(
    .DATA_WIDTH(2 * MAX_READ_WIDTH),
    .APPARENT_DEPTH(NUM_CANDIDATES - 4),
    .FIFO_DEPTH(NUM_CANDIDATES),
    .POINTER_SIZE(NUM_CANDIDATES_BIT_WIDTH + 1)
) candidateArrayAfterLeftShift (
    .clk(clk),
    .rstb(rstb),
    .fifoEmpty(candidateArrayAfterLeftShiftEmpty),
    .fifoFull(candidateArrayAfterLeftShiftFull),
    .data(candidateFromInst),
    .valid(candidateArrayAfterLeftShiftValid),
    .read(candidateArrayAfterLeftShiftRead),
    .out(candidateAfterLeftShift)
);

assign candidateArrayAfterLeftShiftValid = (state == DO_LEFT_SHIFT) & candidateValidInst & candidateNumValidInst & ~candidateArrayAfterLeftShiftFull;
assign candidateArrayAfterLeftShiftRead  = (state == DO_CORRECTION) & isNoSolid & ready4ReadInst;

assign readValidInst                     = (state == DO_LEFT_SHIFT) ? 
                                               ~candidateArrayForLeftShiftEmpty & (numCandidatesLeftShifted != candidateNumForCorrection): 
                                               (
                                                   (state == DO_CORRECTION) ? 
                                                       isNoSolid ? ~candidateArrayAfterLeftShiftEmpty : ~candidateArrayForLeftShiftEmpty :
                                                       'b0
                                               ); 
assign leftShift                         = (state == DO_LEFT_SHIFT);
assign readInst                          = (state == DO_CORRECTION) ? 
                                               (
                                                   isNoSolid ? candidateAfterLeftShift : candidateForLeftShift
                                               ) :
                                               (state == DO_LEFT_SHIFT) ? candidateForLeftShift : 512'b0;

//Find candidates
findCandidates #(
    .MAX_READ_BIT_WIDTH(MAX_READ_BIT_WIDTH),
    .MAX_KMER_BIT_WIDTH(MAX_KMER_BIT_WIDTH),
    .EXTENSION_WIDTH(EXTENSION_WIDTH),
    .MAX_READ_WIDTH(MAX_READ_WIDTH),
    .MIN_READ_WIDTH(MIN_READ_WIDTH),
    .MAX_KMER_WIDTH(MAX_KMER_WIDTH),
    .MIN_KMER_WIDTH(MIN_KMER_WIDTH),
    .QUALITY_WIDTH (QUALITY_WIDTH ),
    .NUM_CANDIDATES_BIT_WIDTH(NUM_CANDIDATES_BIT_WIDTH),
    .NUM_CANDIDATES(NUM_CANDIDATES),
    .CANDIDATE_REGISTER_WIDTH(CANDIDATE_REGISTER_WIDTH)
) findCandidatesInst (
    .clk(clk),
    .rstb(rstb),
    .readLength(readLengthForCorrection),
    .kmerLength(kmerLength),
    .read(readInst),
    .quality(qualityForCorrection),
    .qualityThreshold(qualityThreshold),
    .readValid(readValidInst),
    .ready4Kmer(ready4KmerInst),
    .queryResult(queryResultInst),
    .queryResultValid(queryResultValidInst),
    .ready4Candidate(ready4CandidateInst),
    .startPosition(isNoSolid ? kmerLength : startPositionForCorrection),
    .endPosition(isNoSolid ? readLengthForCorrection - {{(MAX_READ_BIT_WIDTH-1){1'b0}}, 1'b1} : endPositionForCorrection),
    .ready4Read(ready4ReadInst),
    .kmerValid(kmerValidInst),
    .kmer(kmerInst),
    .leftShift(leftShift),

    .unitEmpty(unitEmpty),
    .candidate(candidateFromInst),
    .candidateValid(candidateValidInst),
    .candidateNum(),
    .candidateNumValid(candidateNumValidInst),
    .success(successInst),
    .inputRead()
);

//Output FIFO
synchronousFifo #(
    .DATA_WIDTH(2 * MAX_READ_WIDTH),
    .FIFO_DEPTH(NUM_CANDIDATES),
    .APPARENT_DEPTH(NUM_CANDIDATES - 2),
    .POINTER_SIZE(NUM_CANDIDATES_BIT_WIDTH + 1)
) outputFifo (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(outputFifoFull),
    .fifoEmpty(outputFifoEmpty),
    .read(outputFifoRead),
    .valid(outputFifoValid),
    .data(outputFifoData),
    .out(candidateForOutput)
);

assign outputFifoValid = ((state == DO_NOT_BOTHER) | ((state == DO_CORRECTION) & candidateValidInst & candidateNumValidInst)) & ~outputFifoFull;
assign outputFifoData  = (state == DO_NOT_BOTHER) ? readForCorrection : candidateFromInst;
assign outputFifoRead  = ready4Candidate;

//Count the number of candidates
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        numCandidates <= 'b0;
    end
    else begin
        if (state == FIFO_EMPTY) begin
            numCandidates <= 'b0;
        end
        else begin
            if (outputFifoValid) begin
                numCandidates <= numCandidates + 1;
            end
        end
    end
end

assign candidateValid    = (state == READ_OUTPUT_FIFO) & ~outputFifoEmpty;
assign candidateNumValid = (state == READ_OUTPUT_FIFO);
assign candidate         = candidateForOutput;
assign candidateNum      = numCandidates;
assign readAfterKmerFifo = (state == FIFO_EMPTY);
assign inputRead         = readForCorrection;

//Arbitrate the kmer queries from findCandidates as well as from correct1stKmer
cbfArbitrator #(
    .TOKEN_WIDTH(1),
    .KMER_WIDTH(MAX_KMER_WIDTH)
) arb (
    .clk(clk),
    .rstb(rstb),
    .inKmers({kmerInst, kmer1stKmerCorrect}),
    .cbfReady(ready4Kmer),
    .kmerPositive(queryResult),
    .resultValid(queryResultValid),
    .kmerValid({kmerValidInst, kmerValid1stKmerCorrect}),
    .readyToMasters({ready4KmerInst, ready4Kmer1stKmerCorrect}),
    .kmerToCBF(kmer),
    .kmerValidToCBF(kmerValid),
    .positive({queryResultInst, queryResult1stKmerCorrect}),
    .resultValidM({queryResultValidInst, queryResultValid1stKmerCorrect})
);

endmodule
