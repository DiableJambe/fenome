`timescale 1ns / 1ps
module extractKmersFromCandidates #(
    parameter MAX_READ_BIT_WIDTH = 8,
    parameter MAX_KMER_BIT_WIDTH = 6,
    parameter EXTENSION_WIDTH = 5,
    parameter MAX_READ_WIDTH = {1'b1, {MAX_READ_BIT_WIDTH{1'b0}}},
    parameter MAX_KMER_WIDTH = {1'b1, {MAX_KMER_BIT_WIDTH{1'b0}}},
    parameter MIN_KMER_WIDTH = 12,
    parameter CANDIDATE_REGISTER_WIDTH = MAX_READ_WIDTH + EXTENSION_WIDTH + MAX_KMER_WIDTH - MIN_KMER_WIDTH
) (
    output [2 * MAX_KMER_WIDTH - 1 : 0] kmerCandidate0,
    output [2 * MAX_KMER_WIDTH - 1 : 0] kmerCandidate1,
    output [2 * MAX_KMER_WIDTH - 1 : 0] kmerCandidate2,
    output [2 * MAX_KMER_WIDTH - 1 : 0] kmerCandidate3,
    output [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate0,
    output [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate1,
    output [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate2,
    output [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate3,
    input [MAX_KMER_BIT_WIDTH - 1 : 0] kmerLength,
    input [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] candidate,
    input [MAX_READ_BIT_WIDTH : 0] position,
    input direction
);

wire [2 * MAX_KMER_WIDTH - 1 : 0] allKmers[-EXTENSION_WIDTH + EXTENSION_WIDTH : MAX_READ_WIDTH + EXTENSION_WIDTH - MIN_KMER_WIDTH + EXTENSION_WIDTH];
wire [2 * MAX_KMER_WIDTH - 1 : 0] kmerPicked;
wire [31 : 0] positionX;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] allMasks[-EXTENSION_WIDTH + EXTENSION_WIDTH: CANDIDATE_REGISTER_WIDTH - 1 + EXTENSION_WIDTH];
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] maskPicked;
wire [1 : 0] bases[-EXTENSION_WIDTH + EXTENSION_WIDTH : CANDIDATE_REGISTER_WIDTH - 1 + EXTENSION_WIDTH];
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] A;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] C;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] G;
wire [2 * CANDIDATE_REGISTER_WIDTH - 1 : -2 * EXTENSION_WIDTH] T;
wire [31 : 0] positionCorrected;
wire [1:0] offsetBy1;
wire [1:0] offsetBy2;
wire [1:0] offsetBy3;
wire [2 * MAX_KMER_WIDTH - 1 : 0] allKmerMasks[1 : MAX_KMER_WIDTH];
wire [1:0] basesInKmer[1 : MAX_KMER_WIDTH];

genvar i;
generate
    for (i = -EXTENSION_WIDTH; i < MAX_READ_WIDTH + EXTENSION_WIDTH - MIN_KMER_WIDTH + 1; i = i + 1) begin:extractKmers
        assign allKmers[i + EXTENSION_WIDTH] = candidate[2 * (MAX_KMER_WIDTH + i) - 1 : 2 * i];
        if ((i >= 0) && (i < MAX_KMER_WIDTH)) begin:kmerMasks
            assign allKmerMasks[i + 1] = {{(2 * (MAX_KMER_WIDTH - (i + 1))){1'b0}}, 2'b11, {(2 * i){1'b0}}}; 
            assign basesInKmer[i + 1] = kmerPicked[2 * (i + 1) - 1 : 2 * i];
        end
    end
endgenerate

genvar j;
generate
    for (j = -EXTENSION_WIDTH; j < CANDIDATE_REGISTER_WIDTH; j = j + 1) begin:extractMasks
        if (j >= 0) begin:oneCase
            assign allMasks[j + EXTENSION_WIDTH][2 * CANDIDATE_REGISTER_WIDTH - 1 : 0] = {{2 * (CANDIDATE_REGISTER_WIDTH - (j + 1)){1'b0}}, 2'b11, {(2 * j){1'b0}}};
            assign allMasks[j + EXTENSION_WIDTH][-1 : -2 * EXTENSION_WIDTH] = {2 * EXTENSION_WIDTH{1'b0}};
        end
        else begin:twoCase
            assign allMasks[j + EXTENSION_WIDTH][2 * CANDIDATE_REGISTER_WIDTH - 1 : 0] = {(2 * CANDIDATE_REGISTER_WIDTH){1'b0}};
            assign allMasks[j + EXTENSION_WIDTH][-1 : -2 * EXTENSION_WIDTH]    = {{(2 * (-j - 1)){1'b0}}, 2'b11, {2 * (EXTENSION_WIDTH + j){1'b0}}};
        end
        assign bases[j + EXTENSION_WIDTH] = candidate[2 * (j + 1) - 1 : 2 * j];
        assign A[2 * (j + 1) - 1 : 2 * j] = 2'b00;
        assign C[2 * (j + 1) - 1 : 2 * j] = 2'b01;
        assign G[2 * (j + 1) - 1 : 2 * j] = 2'b10;
        assign T[2 * (j + 1) - 1 : 2 * j] = 2'b11;
    end
endgenerate

assign positionX  = {{(32 - MAX_READ_BIT_WIDTH - 1){position[MAX_READ_BIT_WIDTH]}}, position};
assign kmerPicked = allKmers[positionX + EXTENSION_WIDTH];

assign offsetBy1 = 2'b01 + (direction ? kmerPicked[2 * MAX_KMER_WIDTH - 1 : 2 * MAX_KMER_WIDTH - 2] : kmerPicked[1 : 0]);
assign offsetBy2 = 2'b10 + (direction ? kmerPicked[2 * MAX_KMER_WIDTH - 1 : 2 * MAX_KMER_WIDTH - 2] : kmerPicked[1 : 0]);
assign offsetBy3 = 2'b11 + (direction ? kmerPicked[2 * MAX_KMER_WIDTH - 1 : 2 * MAX_KMER_WIDTH - 2] : kmerPicked[1 : 0]);

assign kmerCandidate0 = kmerPicked;

assign kmerCandidate1 = direction ?
    basesInKmer[kmerLength] == 2'b00 ? (~allKmerMasks[kmerLength] & kmerPicked) | (allKmerMasks[kmerLength] & C[2 * MAX_KMER_WIDTH - 1 : 0]) :
    basesInKmer[kmerLength] == 2'b01 ? (~allKmerMasks[kmerLength] & kmerPicked) | (allKmerMasks[kmerLength] & G[2 * MAX_KMER_WIDTH - 1 : 0]) :
    basesInKmer[kmerLength] == 2'b10 ? (~allKmerMasks[kmerLength] & kmerPicked) | (allKmerMasks[kmerLength] & T[2 * MAX_KMER_WIDTH - 1 : 0]) :
                                       (~allKmerMasks[kmerLength] & kmerPicked) | (allKmerMasks[kmerLength] & A[2 * MAX_KMER_WIDTH - 1 : 0]) :
    {kmerPicked[2 * MAX_KMER_WIDTH - 1 : 2], offsetBy1};

assign kmerCandidate2 = direction ?
    basesInKmer[kmerLength] == 2'b00 ? (~allKmerMasks[kmerLength] & kmerPicked) | (allKmerMasks[kmerLength] & G[2 * MAX_KMER_WIDTH - 1 : 0]) :
    basesInKmer[kmerLength] == 2'b01 ? (~allKmerMasks[kmerLength] & kmerPicked) | (allKmerMasks[kmerLength] & T[2 * MAX_KMER_WIDTH - 1 : 0]) :
    basesInKmer[kmerLength] == 2'b10 ? (~allKmerMasks[kmerLength] & kmerPicked) | (allKmerMasks[kmerLength] & A[2 * MAX_KMER_WIDTH - 1 : 0]) :
                                       (~allKmerMasks[kmerLength] & kmerPicked) | (allKmerMasks[kmerLength] & C[2 * MAX_KMER_WIDTH - 1 : 0]) :
    {kmerPicked[2 * MAX_KMER_WIDTH - 1 : 2], offsetBy2};

assign kmerCandidate3 = direction ?
    basesInKmer[kmerLength] == 2'b00 ? (~allKmerMasks[kmerLength] & kmerPicked) | (allKmerMasks[kmerLength] & T[2 * MAX_KMER_WIDTH - 1 : 0]) :
    basesInKmer[kmerLength] == 2'b01 ? (~allKmerMasks[kmerLength] & kmerPicked) | (allKmerMasks[kmerLength] & A[2 * MAX_KMER_WIDTH - 1 : 0]) :
    basesInKmer[kmerLength] == 2'b10 ? (~allKmerMasks[kmerLength] & kmerPicked) | (allKmerMasks[kmerLength] & C[2 * MAX_KMER_WIDTH - 1 : 0]) :
                                       (~allKmerMasks[kmerLength] & kmerPicked) | (allKmerMasks[kmerLength] & G[2 * MAX_KMER_WIDTH - 1 : 0]) :
    {kmerPicked[2 * MAX_KMER_WIDTH - 1 : 2], offsetBy3};

//assign positionCorrected = EXTENSION_WIDTH + (direction ? positionX + kmerLength - 1 : positionX);
assign positionCorrected = direction ? positionX + kmerLength - 1 : positionX;

assign maskPicked = allMasks[positionCorrected + EXTENSION_WIDTH];

assign candidate0 = (candidate & ~maskPicked) | (maskPicked & (
                           bases[positionCorrected + EXTENSION_WIDTH] == 2'b00 ? A :
                           bases[positionCorrected + EXTENSION_WIDTH] == 2'b01 ? C :
                           bases[positionCorrected + EXTENSION_WIDTH] == 2'b10 ? G :
                       /*bases[positionCorrected] == 2'b11 ?*/ T
));
assign candidate1 = (candidate & ~maskPicked) | (maskPicked & (
                           bases[positionCorrected + EXTENSION_WIDTH] == 2'b00 ? C :
                           bases[positionCorrected + EXTENSION_WIDTH] == 2'b01 ? G :
                           bases[positionCorrected + EXTENSION_WIDTH] == 2'b10 ? T :
                       /*bases[positionCorrected] == 2'b11 ?*/ A
));
assign candidate2 = (candidate & ~maskPicked) | (maskPicked & (
                           bases[positionCorrected + EXTENSION_WIDTH] == 2'b00 ? G :
                           bases[positionCorrected + EXTENSION_WIDTH] == 2'b01 ? T :
                           bases[positionCorrected + EXTENSION_WIDTH] == 2'b10 ? A :
                       /*bases[positionCorrected] == 2'b11 ?*/ C
));
assign candidate3 = (candidate & ~maskPicked) | (maskPicked & (
                           bases[positionCorrected + EXTENSION_WIDTH] == 2'b00 ? T :
                           bases[positionCorrected + EXTENSION_WIDTH] == 2'b01 ? A :
                           bases[positionCorrected + EXTENSION_WIDTH] == 2'b10 ? C :
                       /*bases[positionCorrected] == 2'b11 ?*/ G
));

endmodule
