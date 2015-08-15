//Design notes: Keep input FIFO for all parameters and the read. Read from the FIFO when the final candidate has been read out.
`timescale 1ns / 1ps

`ifndef NO_INTERNAL_FIFO
    `define NO_INTERNAL_FIFO
`endif

module findCandidates #(
    parameter MAX_READ_BIT_WIDTH = 8,
    parameter MAX_KMER_BIT_WIDTH = 5,
    parameter EXTENSION_WIDTH = 3,
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
    input leftShift,

    output unitEmpty,
    output ready4Read,
    output kmerValid,
    output [2 * MAX_KMER_WIDTH - 1 : 0] kmer,
    output [2 * MAX_READ_WIDTH - 1 : 0] candidate,
    output candidateValid,
    output [NUM_CANDIDATES_BIT_WIDTH - 1 : 0] candidateNum,
    output candidateNumValid,
    output success,
    output [2 * MAX_READ_WIDTH - 1 : 0] inputRead
);

wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidateRegister;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidateRegister0;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidateRegister1;
wire candidateFifo0Empty;
wire candidateFifo0Full;
wire candidateFifo1Empty;
wire candidateFifo1Full;
reg [MAX_READ_BIT_WIDTH : 0] position;
wire [MAX_READ_BIT_WIDTH : 0] negPosition;
wire [MAX_READ_BIT_WIDTH : 0] lhs;
wire [2 * MAX_READ_WIDTH - 1 : 0] readIn;
wire [MAX_READ_BIT_WIDTH - 1 : 0] startPositionIn;
wire [MAX_READ_BIT_WIDTH - 1 : 0] endPositionIn;
wire [MAX_READ_BIT_WIDTH - 1 : 0] readLengthIn;
wire inputFifoValid;
wire inputFifoRead;
wire betweenIslandsCorrection;
wire fivePrimeCorrection;
wire threePrimeCorrection;
wire direction;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerCandidate0_0;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerCandidate1_0;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerCandidate2_0;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerCandidate3_0;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerCandidate0_1;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerCandidate1_1;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerCandidate2_1;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerCandidate3_1;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate0_0;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate1_0;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate2_0;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate3_0;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate0_1;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate1_1;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate2_1;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate3_1;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidateStation0Out;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidateStation1Out;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidateSelected;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidateToWrite;
wire inputFifoFull;
wire inputFifoEmpty;
wire idle;
reg idle_del;
wire readInValid;
reg readInValid_del;
wire newReadIn;
reg inputFifoRead_del;
reg lastPosition_del;
wire noCorrections;
reg [1:0] fifoSelector;
reg [1:0] resultSelector;
wire readKmerStation0;
wire readKmerStation1;
wire extensionPhase;
reg [2 * MAX_READ_WIDTH - 1 : 0] previousCandidate;
wire candidateRead;
wire [2 * MAX_READ_WIDTH - 1 : 0] candidateIntoOutputFifo;
wire previousCandidateEqCurrentCandidate;
wire eqArray[0 : MAX_READ_WIDTH - MIN_READ_WIDTH - 1];
wire kmerStation0Valid;
wire kmerStation1Valid;
wire [MAX_READ_BIT_WIDTH : 0] positionExtract;
wire candidateStation0Empty;
wire candidateStation0Full;
wire candidateStation1Empty;
wire candidateStation1Full;
wire kmerStation0Full;
wire kmerStation0Empty;
wire kmerStation1Empty;
wire kmerStation1Full;
wire lastPosition;
wire queryResult0;
wire queryResult1;
wire queryResultValid0;
wire queryResultValid1;
reg simultaneous;
wire outputFifoFull;
wire outputFifoEmpty;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmer0;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmer1;
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerArbitrated;
wire [QUALITY_WIDTH * MAX_READ_WIDTH - 1 : 0] qualityIn;
wire [QUALITY_WIDTH - 1 : 0] qualityArray[0 : MAX_READ_WIDTH];
wire [MAX_READ_WIDTH - MIN_READ_WIDTH - 1 : 0] eqArrayVerf;
wire outputFifoValid;
wire [2 * MAX_READ_WIDTH - 1 : 0] candidateOut;
wire leftShiftIn;

genvar m;
generate
    for (m = 0; m < MAX_READ_WIDTH; m=m+1) begin:extractIndividualQScore
        assign qualityArray[m] = qualityIn[QUALITY_WIDTH * (m + 1) - 1 : QUALITY_WIDTH * m];
    end
endgenerate

`ifndef NO_INTERNAL_FIFO
//Input FIFO
synchronousFifo #(
    .DATA_WIDTH(QUALITY_WIDTH * MAX_READ_WIDTH + 2 * MAX_READ_WIDTH + 3 * MAX_READ_BIT_WIDTH + 1),
    .FIFO_DEPTH(16),
    .APPARENT_DEPTH(12),
    .POINTER_SIZE(5)
) inputFifo (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(inputFifoFull),
    .fifoEmpty(inputFifoEmpty),
    .data({quality, read, leftShift ? 0 : startPosition, leftShift ? 0 : endPosition, readLength, leftShift}),
    .out({qualityIn, readIn, startPositionIn, endPositionIn, readLengthIn, leftShiftIn}),
    .valid(inputFifoValid),  //Protect this FIFO
    .read(inputFifoRead)
);
assign ready4Read     = ~inputFifoFull;
assign unitEmpty      = inputFifoEmpty & kmerStation0Empty & kmerStation1Empty & candidateStation0Empty & candidateStation1Empty & outputFifoEmpty;
assign readInValid    = ~inputFifoEmpty;
assign inputFifoValid = ready4Read & readValid;
assign inputFifoRead  = idle & ~idle_del;
`else
assign qualityIn       = quality;
assign readIn          = read;
assign startPositionIn = leftShiftIn ? 0 : startPosition;
assign endPositionIn   = leftShiftIn ? 0 : endPosition;
assign readLengthIn    = readLength;
assign leftShiftIn     = leftShift;
assign unitEmpty       = ~readValid & outputFifoEmpty;

assign readInValid     = readValid;
assign ready4Read      = idle & ~idle_del;
`endif

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        idle_del           <= 1'b0;
        readInValid_del    <= 1'b0;
        inputFifoRead_del  <= 1'b0;
    end
    else begin
        idle_del           <= idle;
        readInValid_del    <= readInValid;
        inputFifoRead_del  <= ready4Read; //Sorry the name is misleading!!! :-|
    end
end

assign idle           = lastPosition & (position[0] ? candidateFifo1Empty : candidateFifo0Empty) & outputFifoEmpty;
assign newReadIn      = (readInValid & ~readInValid_del) | (inputFifoRead_del & readInValid);

//False paths to these signals
assign betweenIslandsCorrection = readInValid & (endPositionIn != 0) && (endPositionIn != readLengthIn - 1);
assign fivePrimeCorrection      = readInValid & (endPositionIn == 0);
assign threePrimeCorrection     = readInValid & (endPositionIn == readLengthIn - 1);

//Direction of correction
assign direction = (endPositionIn > startPositionIn) ? readInValid : 1'b0;

//Select candidate 0 in even positions, and candidate 1 in odd positions
assign candidateSelected = ~position[0] ? candidateRegister0 : candidateRegister1;

//Handle position of correction
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        position <= {(MAX_READ_WIDTH + 1){1'b0}};
    end
    else begin
        if (~readInValid) begin
            position <= {MAX_READ_WIDTH{1'b0}};
        end
        else begin
            if (newReadIn) begin
                if (~leftShiftIn) 
                    position <= {(MAX_READ_WIDTH + 1){1'b0}};
                else
                    position <= -1;
            end
            else begin
                if (~lastPosition) begin
                    if (direction) begin
                        if ((position[0] ? candidateFifo1Empty : candidateFifo0Empty) & candidateStation0Empty & candidateStation1Empty) begin
                            position <= position + 1;
                        end
                    end
                    else begin //Only one type of correction has this, direction = 0, for now
                        if ((position[0] ? candidateFifo1Empty : candidateFifo0Empty) & candidateStation0Empty & candidateStation1Empty) begin
                            position <= position - 1;
                        end
                    end
                end
            end
        end
    end
end

//Reading a candidate FIFO read - read Fifo0 when position is even, else read Fifo1. Read when the next stations are not full. A read here must result in a write there
//assign candidateFifoRead = ~lastPosition & ((~position[0] ? ~candidateFifo0Empty : ~candidateFifo1Empty) & ~kmerStation0Full  & ~candidateStation0Full & (simultaneous ? ~kmerStation1Full & ~candidateStation1Full : 1'b1));
assign candidateFifoRead = ~lastPosition & ((~position[0] ? ~candidateFifo0Empty : ~candidateFifo1Empty) & extract0Ready);
//The good thing is, the FIFO widths do not need to be matched for this - as k-mer queries come back, we can empty out the downstream FIFOs to make space
//Recommended - do not keep these downstream FIFOs too big

//Candidate set 0
synchronousFifo #(
    .DATA_WIDTH(2 * (CANDIDATE_REGISTER_WIDTH + EXTENSION_WIDTH)),
    .FIFO_DEPTH(NUM_CANDIDATES),
    .APPARENT_DEPTH(NUM_CANDIDATES - 4),
    .POINTER_SIZE(NUM_CANDIDATES_BIT_WIDTH + 1)
) candidateFifo0 (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(candidateFifo0Full),
    .fifoEmpty(candidateFifo0Empty),
    .data(candidateToWrite),
    .out(candidateRegister0),
    .read(~position[0] & (candidateFifoRead | candidateRead)),
    .valid(candidateFifo0Write & ~candidateFifo0Full) //Discard candidates beyond a certain number
);

//Candidate set 1
synchronousFifo #(
    .DATA_WIDTH(2 * (CANDIDATE_REGISTER_WIDTH + EXTENSION_WIDTH)),
    .FIFO_DEPTH(NUM_CANDIDATES),
    .APPARENT_DEPTH(NUM_CANDIDATES - 4),
    .POINTER_SIZE(NUM_CANDIDATES_BIT_WIDTH + 1)
) candidateFifo1 (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(candidateFifo1Full),
    .fifoEmpty(candidateFifo1Empty),
    .data(candidateToWrite),
    .out(candidateRegister1),
    .read(position[0] & (candidateFifoRead | candidateRead)),
    .valid(candidateFifo1Write & ~candidateFifo1Full) //Discard candidates beyond a certain number
);

assign candidateToWrite    = newReadIn ? { {(2 * (MAX_KMER_WIDTH - MIN_KMER_WIDTH + EXTENSION_WIDTH)){1'b0}}   , readIn, {(2 * EXTENSION_WIDTH){1'b0}}} : (queryResult0 & queryResultValid0 ? candidateStation0Out : candidateStation1Out);

assign candidateFifo0Write = (newReadIn & ~leftShiftIn) | (position[0] & ((queryResult0 & queryResultValid0) | (queryResult1 & queryResultValid1)));
assign candidateFifo1Write = (newReadIn & leftShiftIn) | (~position[0] & ((queryResult0 & queryResultValid0) | (queryResult1 & queryResultValid1)));

//Extracting candidates for station 0
extractKmersFromCandidatesPipelined #(
    .MAX_READ_BIT_WIDTH(MAX_READ_BIT_WIDTH),
    .MAX_KMER_BIT_WIDTH(MAX_KMER_BIT_WIDTH),
    .EXTENSION_WIDTH(EXTENSION_WIDTH),
    .MAX_READ_WIDTH(MAX_READ_WIDTH),
    .MAX_KMER_WIDTH(MAX_KMER_WIDTH),
    .MIN_KMER_WIDTH(MIN_KMER_WIDTH),
    .CANDIDATE_REGISTER_WIDTH(MAX_READ_WIDTH + EXTENSION_WIDTH + MAX_KMER_WIDTH - MIN_KMER_WIDTH)
) candidateKmerExtract0 (
    .clk(clk),
    .rstb(rstb),
    .ip_valid(candidateFifoRead),
    .ready4_ip(extract0Ready),
    .op_valid(extract0Valid),
    .ready4_op(ready4_extract0),
    .kmerCandidate0(kmerCandidate0_0),
    .kmerCandidate1(kmerCandidate1_0),
    .kmerCandidate2(kmerCandidate2_0),
    .kmerCandidate3(kmerCandidate3_0),
    .candidate0(candidate0_0),
    .candidate1(candidate1_0),
    .candidate2(candidate2_0),
    .candidate3(candidate3_0),
    .kmerLength(kmerLength),
    .candidate(candidateSelected),
    .position(positionExtract),
    .direction(direction)
);

assign ready4_extract0 = ~kmerStation0Full  & ~candidateStation0Full & (simultaneous ? ~kmerStation1Full & ~candidateStation1Full : 1'b1)); 

synchronousFifo #(
    .DATA_WIDTH(2 * MAX_KMER_WIDTH),
    .FIFO_DEPTH(16),
    .APPARENT_DEPTH(12),
    .POINTER_SIZE(5)
) kmerStation0 (
    .clk(clk),
    .rstb(rstb),
    .data(kmerCandidate0_0),
    .fifoFull(kmerStation0Full),
    .fifoEmpty(kmerStation0Empty),
    .read(/*ready4Kmer0 & (~simultaneous ? ~(candidateStation1Full | kmerStation1Full) : 1'b1)*/kmerStation0Valid & ready4Kmer0),
    .valid(extract0Valid),
    .out(kmer0)
);

//The number of outstanding k-mer requests cannot be more than the size of candidateStation0 (call it size), because the number of outstanding requests is the same as the number of items in candidateStation0.
assign kmerStation0Valid = ~betweenIslandsCorrection & extensionPhase ? (fifoSelector == 2'b0 ? ~kmerStation0Empty : 1'b0) : ~kmerStation0Empty & (~simultaneous ? ~(candidateStation1Full | kmerStation1Full) : 1'b1);
assign kmerStation1Valid = ~betweenIslandsCorrection & extensionPhase ? (fifoSelector != 2'b0 ? ~kmerStation1Empty : 1'b0) : ~kmerStation1Empty;

//Candidate moves here after the first test
synchronousFifo #(
    .DATA_WIDTH(2 * (CANDIDATE_REGISTER_WIDTH + EXTENSION_WIDTH)),
    .FIFO_DEPTH(16),
    .APPARENT_DEPTH(12),
    .POINTER_SIZE(5)
) candidateStation0 (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(candidateStation0Full),
    .fifoEmpty(candidateStation0Empty),
    .data(candidate0_0),
    .out(candidateStation0Out),
    .read(candidateStation0Read),
    .valid(extract0Valid)
);

//You have sent out a k-mer from the candidate FIFO successfully
assign candidateStation0Read  = queryResultValid0;


wire [MAX_READ_BIT_WIDTH - MAX_KMER_BIT_WIDTH - 1 : 0] enoughZeroes = 0;
assign positionExtract = direction ? startPositionIn - {enoughZeroes, kmerLength} + position + {{(MAX_READ_BIT_WIDTH - 1){1'b0}}, 1'b1} : startPositionIn + position;

//Extracting candidates for station 1
extractKmersFromCandidatesPipelined #(
    .MAX_READ_BIT_WIDTH(MAX_READ_BIT_WIDTH),
    .MAX_KMER_BIT_WIDTH(MAX_KMER_BIT_WIDTH),
    .EXTENSION_WIDTH(EXTENSION_WIDTH),
    .MAX_READ_WIDTH(MAX_READ_WIDTH),
    .MAX_KMER_WIDTH(MAX_KMER_WIDTH),
    .MIN_KMER_WIDTH(MIN_KMER_WIDTH),
    .CANDIDATE_REGISTER_WIDTH(MAX_READ_WIDTH + EXTENSION_WIDTH + MAX_KMER_WIDTH - MIN_KMER_WIDTH)
) candidateKmerExtract1 (
    .clk(clk),
    .rstb(rstb),
    .ip_valid(),
    .kmerCandidate0(kmerCandidate0_1),
    .kmerCandidate1(kmerCandidate1_1),
    .kmerCandidate2(kmerCandidate2_1),
    .kmerCandidate3(kmerCandidate3_1),
    .candidate0(candidate0_1),
    .candidate1(candidate1_1),
    .candidate2(candidate2_1),
    .candidate3(candidate3_1),
    .kmerLength(kmerLength),
    .candidate(candidateStation0Out),
    .position(positionExtract),
    .direction(direction)
);

//Examine all k-mers simultaneously or not ...
always @* begin
    if (position == 0) begin
        simultaneous <= 1'b1;
    end
    else begin
        if (~extensionPhase) begin
            if (qualityArray[startPositionIn + position] < qualityThreshold) begin //TBD: Add to FIFO
                simultaneous <= 1'b1;
            end
            else begin
                simultaneous <= 1'b0;
            end
        end
        else begin //In extension phase, just barrel through all possibilities unless you are in between islands correction phase
            simultaneous <= ~betweenIslandsCorrection;
        end
    end
end

assign candidateStation1Valid = simultaneous ?  extract0Valid : extract1Valid; //(queryResultValid0 & ~queryResult0 & ~(betweenIslandsCorrection & extensionPhase));
                                                                                                                     //In between islands correction you don't check multiple possibilities for extension

synchronousFifoParallelShiftParameterized #(
    .SPLIT_WIDTH(2 * (MAX_KMER_WIDTH)),
    .NUM_SPLITS_BIT_WIDTH(2),
    .NUM_SPLITS(3),
    .FIFO_DEPTH(96),       //32 * 3 = 96
    .APPARENT_DEPTH(48),   //16 * 3 = 48; full at 16, 16 more outstanding possible
    .POINTER_SIZE(8),
    .SUB_FIFO_POINTER_SIZE(6)
) kmerStation1 (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(kmerStation1Full),
    .fifoEmpty(kmerStation1Empty),
    .valid(candidateStation1Valid),
    .read(kmerStation1Valid & ready4Kmer1),
    .data(simultaneous ? {kmerCandidate1_0, kmerCandidate2_0, kmerCandidate3_0} : {kmerCandidate1_1, kmerCandidate2_1, kmerCandidate3_1}),
    .out(kmer1)
);

//Candidate moves here after the second test
synchronousFifoParallelShiftParameterized #(
    .SPLIT_WIDTH(2 * (CANDIDATE_REGISTER_WIDTH + EXTENSION_WIDTH)),
    .NUM_SPLITS_BIT_WIDTH(2),
    .NUM_SPLITS(3),
    .FIFO_DEPTH(96),       //32 * 3 = 96
    .APPARENT_DEPTH(48),   //16 * 3 = 48; full at 16, 16 more outstanding possible
    .POINTER_SIZE(8),
    .SUB_FIFO_POINTER_SIZE(6)
) candidateStation1 (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(candidateStation1Full),
    .fifoEmpty(candidateStation1Empty),
    .data(simultaneous ? {candidate1_0, candidate2_0, candidate3_0} : {candidate1_1, candidate2_1, candidate3_1}),
    .out(candidateStation1Out),
    .read(queryResultValid1),
    .valid(candidateStation1Valid)
);

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        fifoSelector   <= 2'b0;
    end
    else begin
        if (extensionPhase & ~betweenIslandsCorrection) begin
            if ((ready4Kmer0 & kmerStation0Valid) | (ready4Kmer1 & kmerStation1Valid)) begin
                fifoSelector <= fifoSelector + 1;
            end
        end
        else begin
            fifoSelector   <= 2'b0;
        end

    end
end

assign readKmerStation0 = fifoSelector == 0;
assign readKmerStation1 = fifoSelector != 0;

//assign extensionPhase = ~threePrimeCorrection & ~(direction ? (startPositionIn + position <= endPositionIn) : (startPositionIn - endPositionIn >= -position));
assign extensionPhase = readInValid & ~(direction ? (startPositionIn + position <= endPositionIn) : (startPositionIn - endPositionIn >= -position));

cbfArbitrator #(
    .TOKEN_WIDTH(1),
    .KMER_WIDTH(MAX_KMER_WIDTH),
    /*.FLOPRESULT(1),
    .FLOPOUTPUTS1(1),*/
    .TOKEN_FIFO_DEPTH_BITS(8)
) arbitrateStation0Station1 (
    .clk(clk),
    .rstb(rstb),
    .inKmers({kmer0, kmer1}),
    .cbfReady(ready4Kmer),
    .kmerPositive(queryResult),
    .resultValid(queryResultValid),
    .kmerValid({kmerStation0Valid, kmerStation1Valid}),
    .readyToMasters({ready4Kmer0Arbitrated, ready4Kmer1Arbitrated}),
    .kmerToCBF(kmerArbitrated),
    .kmerValidToCBF(kmerValidArbitrated),
    .positive({queryResult0Arbitrated, queryResult1Arbitrated}),
    .resultValidM({queryResultValid0Arbitrated, queryResultValid1Arbitrated})
);

assign kmerValidExtensionPhase = fifoSelector ? ~kmerStation0Empty : ~kmerStation1Empty;
assign kmerValid               = kmerValidArbitrated;
assign queryResultValid0       = queryResultValid0Arbitrated;
assign queryResultValid1       = queryResultValid1Arbitrated;
assign ready4Kmer0             = ~betweenIslandsCorrection & extensionPhase ? readKmerStation0 & ready4Kmer0Arbitrated : ready4Kmer0Arbitrated;
assign ready4Kmer1             = ~betweenIslandsCorrection & extensionPhase ? readKmerStation1 & ready4Kmer1Arbitrated : ready4Kmer1Arbitrated;
assign kmer                    = kmerArbitrated;
assign queryResult0            = queryResult0Arbitrated;
assign queryResultValid0       = queryResultValid0Arbitrated;
assign queryResult1            = queryResult1Arbitrated;
assign queryResultValid1       = queryResultValid1Arbitrated;
assign negPosition             = -position;
assign lhs                     = startPositionIn - endPositionIn + EXTENSION_WIDTH + 1;

assign lastPosition = (direction ? (betweenIslandsCorrection ? startPositionIn + position == endPositionIn + kmerLength : startPositionIn + position == endPositionIn + EXTENSION_WIDTH + 1) : startPositionIn - endPositionIn + EXTENSION_WIDTH + 1 == negPosition) & readInValid;

assign candidateIntoOutputFifo = position[0] ? candidateRegister1[2 * MAX_READ_WIDTH - 1 : 0] : candidateRegister0[2 * MAX_READ_WIDTH - 1 : 0];
assign candidateRead           = lastPosition & (position[0] ? ~candidateFifo1Empty : ~candidateFifo0Empty);

reg firstCandidate;
reg [NUM_CANDIDATES_BIT_WIDTH - 1 : 0] numCandidates;

//Capture the previous candidate to uniquify
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        previousCandidate <= {MAX_READ_WIDTH{1'b0}};
        firstCandidate    <= 1'b1;
    end
    else begin
        if (newReadIn) begin
            previousCandidate <= {MAX_READ_WIDTH{1'b0}};
            firstCandidate    <= 1'b1;
        end
        else begin
            if (candidateRead) begin
                previousCandidate <= candidateIntoOutputFifo;
            end
            if (outputFifoValid) begin
                firstCandidate <= 1'b0;
            end
        end
    end
end

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        numCandidates <= {NUM_CANDIDATES_BIT_WIDTH{1'b0}};
    end
    else begin
        if (newReadIn) begin
            numCandidates <= {NUM_CANDIDATES_BIT_WIDTH{1'b0}};
        end
        else begin
            if (outputFifoValid) begin
                numCandidates <= numCandidates + 1;
            end
        end
    end
end

assign outputFifoValid = candidateRead & (~previousCandidateEqCurrentCandidate | firstCandidate);
genvar k;
generate
    for (k = 0; k < MAX_READ_WIDTH - MIN_READ_WIDTH; k = k + 1) begin:eqArrayEval
        assign eqArray[k] = (previousCandidate[2 * (MIN_READ_WIDTH + k) - 1 : 0] == candidateIntoOutputFifo[2 * (MIN_READ_WIDTH + k) - 1 : 0]);
        assign eqArrayVerf[k] = eqArray[k];
    end
endgenerate

assign previousCandidateEqCurrentCandidate = eqArray[readLengthIn - MIN_READ_WIDTH];

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        lastPosition_del <= 1'b0;
    end
    else begin
        lastPosition_del <= lastPosition;
    end
end

assign noCorrections     = lastPosition & ~lastPosition_del & ~candidateRead;

synchronousFifo #(
    .DATA_WIDTH(2 * MAX_READ_WIDTH),
    .FIFO_DEPTH(NUM_CANDIDATES),
    .POINTER_SIZE(NUM_CANDIDATES_BIT_WIDTH + 1),
    .APPARENT_DEPTH(NUM_CANDIDATES - 4)
) outputFifo (
    .clk(clk),
    .rstb(rstb),
    .read(ready4Candidate),
    .valid(outputFifoValid & ~outputFifoFull), //Discard the remaining candidates
    .data(candidateIntoOutputFifo),
    .out(candidateOut),
    .fifoFull(outputFifoFull),
    .fifoEmpty(outputFifoEmpty)
);

assign candidate         = noCorrections ? readIn : candidateOut;
assign candidateValid    = ~outputFifoEmpty | noCorrections;
assign candidateNum      = numCandidates;
assign candidateNumValid = lastPosition & (position[0] ? candidateFifo1Empty : candidateFifo0Empty);
assign success           = ~noCorrections;

endmodule
