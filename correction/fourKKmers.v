`timescale 1ns / 1ps
module fourKKmers #( //Its actually 3k + 1 you know ...
    parameter MAX_READ_BIT_WIDTH = 8,
    parameter MAX_KMER_BIT_WIDTH = 6,
    parameter MAX_READ_WIDTH     = {1'b1, {MAX_READ_BIT_WIDTH{1'b0}}},
    parameter MAX_KMER_WIDTH     = {1'b1, {MAX_KMER_BIT_WIDTH{1'b0}}},
    parameter QUALITY_WIDTH      = 2
) (
    input clk,
    input rstb,
    input [2 * MAX_READ_WIDTH - 1 : 0] read,
    input [QUALITY_WIDTH * MAX_READ_WIDTH - 1 : 0] quality,
    input [MAX_KMER_BIT_WIDTH - 1 : 0] kmerLength,
    input readValid,
    input ready4Candidate,
    input ready4Kmer,
    input queryResultValid,
    input queryResult,
    output [2 * MAX_KMER_WIDTH - 1 : 0] kmer,
    output kmerValid,
    output [2 * MAX_READ_WIDTH - 1 : 0] candidate,
    output candidateValid,
    output ready4Read
);

//Internal wires/registers
wire [1 : 0]                  altBases[0 : MAX_KMER_WIDTH - 1][0 : 2];
wire [2 * MAX_KMER_WIDTH - 1 : 0] allKmers[0 : MAX_KMER_WIDTH - 1][0 : 2];
wire [2 * MAX_KMER_WIDTH - 1 : 0] allKmersFlat[0 : 3 * MAX_KMER_WIDTH - 1];
reg [MAX_KMER_BIT_WIDTH + 1 : 0]  kmerCounter; //3 * MAX_KMER_WIDTH corresponds to approximately two left bit-shfits
wire [2 * MAX_KMER_WIDTH - 1 : 0] pushKmer;
wire [2 * MAX_READ_WIDTH - 1 : 0] pushRead;
wire                          push;
wire                          readFifoFull;
wire                          kmerFifoFull;
wire                          kmerFifoEmpty;
wire [MAX_KMER_BIT_WIDTH + 1 : 0] thriceKmerWidth;

assign thriceKmerWidth = kmerLength + kmerLength + kmerLength;

//Capture alternative bases for each position
genvar k, l;
generate
    for (k = 0; k < MAX_KMER_WIDTH; k = k + 1) begin:alternativeBases
        for (l = 0; l < 3; l = l + 1) begin:eachBase
            assign altBases[k][l] = read[2 * (k + 1) - 1 : 2 * k] + l[1 : 0] + 2'b01;
        end
    end
endgenerate

//Generate alternative all alternative k-mers for all positions
genvar m, n;
generate
    for (m = 0; m < MAX_KMER_WIDTH; m = m + 1) begin:generatKmersOuter
        for (n = 0; n < 3; n = n + 1) begin:substituteBases
            if (m == 0) begin:zeroCase
                assign allKmers[m][n] = {read[2 * MAX_KMER_WIDTH - 1 : 2], altBases[m][n]};
            end
            else if (m == MAX_KMER_WIDTH - 1) begin:msbCase
                assign allKmers[m][n] = {altBases[m][n], read[2 * MAX_KMER_WIDTH - 3 : 0]};
            end
            else begin:generalCases
                assign allKmers[m][n] = {read[2 * MAX_KMER_WIDTH - 1 : 2 * (m + 1)], altBases[m][n], read[2 * m - 1 : 0]};
            end
        end
    end
endgenerate

//Flatten out the k-mer representation
genvar o, p;
generate
    for (o = 0; o < MAX_KMER_WIDTH; o = o + 1) begin:flatOuter
        for (p = 0; p < 3; p = p + 1) begin:flatInner
            assign allKmersFlat[3 * o + p] = allKmers[o][p];
        end
    end
endgenerate

//There will be a total of 3 * MAX_KMER_WIDTH alternative k-mers (+1 for querying the original k-mer)
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        kmerCounter <= {(MAX_KMER_BIT_WIDTH + 2){1'b0}};
    end
    else begin
        if (ready4Read) begin
            kmerCounter <= {(MAX_KMER_BIT_WIDTH + 2){1'b0}};
        end
        else begin
            if (readValid) begin
                if (kmerCounter <= thriceKmerWidth) begin
                    if (~(readFifoFull | kmerFifoFull)) kmerCounter <= kmerCounter + 1;
                end
            end
            else begin
                kmerCounter <= {(MAX_KMER_BIT_WIDTH + 2){1'b0}};
            end
        end
    end
end

//No FIFO-full hazards here
assign push      = readValid & (kmerCounter <= thriceKmerWidth) & ~(kmerFifoFull | readFifoFull);
assign pushKmer  = (kmerCounter < thriceKmerWidth) ? allKmersFlat[kmerCounter] : read[2 * MAX_KMER_WIDTH - 1 : 0];
assign pushRead  = (kmerCounter < thriceKmerWidth) ? {read[2 * MAX_READ_WIDTH - 1 : 2 * MAX_KMER_WIDTH], pushKmer} : read;
assign kmerValid = ~kmerFifoEmpty & ready4Candidate; //Do not send k-mers out if not ready for candidates

//This FIFO need not be large
synchronousFifo #(
    .DATA_WIDTH(2 * MAX_KMER_WIDTH),
    .POINTER_SIZE(5),
    .FIFO_DEPTH(16),
    .APPARENT_DEPTH(12)
) kmerFifo (
    .clk(clk),
    .rstb(rstb),
    .data(pushKmer),
    .read(ready4Kmer & ready4Candidate), //Do not send k-mers out if not ready for candidates
    .valid(push),
    .fifoFull(kmerFifoFull),
    .fifoEmpty(kmerFifoEmpty),
    .out(kmer)
);

//This FIFO also need not be large
synchronousFifo #(
    .DATA_WIDTH(2 * MAX_READ_WIDTH),
    .POINTER_SIZE(5),
    .FIFO_DEPTH(16),
    .APPARENT_DEPTH(12)
) readFifo (
    .clk(clk),
    .rstb(rstb),
    .data(pushRead),
    .read(queryResultValid),
    .valid(push),
    .fifoFull(readFifoFull),
    .fifoEmpty(readFifoEmpty),
    .out(candidate)
);

//Note: candidateValid will precede ready4Read by one cycle
assign candidateValid = queryResultValid & queryResult & ~readFifoEmpty & readValid & ready4Candidate;
assign ready4Read     = readFifoEmpty & kmerFifoEmpty & (kmerCounter > thriceKmerWidth);

endmodule
