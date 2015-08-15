`timescale 1ps/1ps
//Since this module is serially fed we can easily bypass the module from the outside without affecting the order.
//Keep a counter outside to keep track of the number of reads.
//If the counter returns zero, we know that there were no solid candidates.
module lowQBaseChangePipelined #(
    parameter MAX_READ_BIT_WIDTH = 8,
    parameter MAX_KMER_BIT_WIDTH = 6,
    parameter MAX_READ_WIDTH    = {1'b1, {MAX_READ_BIT_WIDTH{1'b0}}},
    parameter MAX_KMER_WIDTH    = {1'b1, {MAX_KMER_BIT_WIDTH{1'b0}}},
    parameter QUALITY_WIDTH     = 2,
    parameter NUM_PIPELINES     = 8,
    parameter LAST_STAGE        = 8
) (
    input clk,
    input rstb,
    input [2 * MAX_READ_WIDTH - 1 : 0] read,
    input [QUALITY_WIDTH * MAX_KMER_WIDTH - 1 : 0] quality,
    input [QUALITY_WIDTH - 1 : 0] qualityThreshold,            //Programmable Quality cut-off
    input readValid,
    input ready4Candidate,
    input ready4Kmer,
    input queryResult,
    input queryResultValid,
    input [MAX_KMER_BIT_WIDTH - 1 : 0] kmerLength,
    output [2 * MAX_KMER_WIDTH - 1 : 0] kmer,
    output kmerValid,
    output [2 * MAX_READ_WIDTH - 1 : 0] candidate,
    output candidateValid,
    output ready4Read
);

//Internal wires and registers
reg [1 : 0]                   counters[0 : NUM_PIPELINES - 1][0 : MAX_KMER_WIDTH - 1];
wire [2 * MAX_KMER_WIDTH - 1 : 0] allCounterBits;
wire [MAX_KMER_WIDTH - 1 : 0]     threshold;
reg  [MAX_KMER_WIDTH - 1 : 0]     increment[0 : NUM_PIPELINES - 1];
wire [2 * MAX_KMER_WIDTH - 1 : 0] firstKmer;
wire                          allKmersGeneratedForCurrentRead; 
reg [NUM_PIPELINES - 1 : 0]   firstKmerGeneratedForCurrentRead;
wire                          kmerFifoFull;
wire                          readFifoFull;
wire                          readFifoEmpty;
wire [2 * MAX_KMER_WIDTH - 1 : 0] pushKmer;
wire [2 * MAX_READ_WIDTH - 1 : 0] pushRead;
wire                          push;

//Flatten out all counter bits
genvar z;
generate
    for (z = 0; z < MAX_KMER_WIDTH; z = z + 1) begin:unrollKmer
        assign allCounterBits[2 * (z + 1) - 1 : 2 * z] = counters[NUM_PIPELINES - 1][z];
    end
endgenerate

//After the first k-mer is generated and all counters become zero, we are done
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        firstKmerGeneratedForCurrentRead <= {NUM_PIPELINES{1'b0}};
    end
    else begin
        if (ready4Read) begin
            firstKmerGeneratedForCurrentRead <= {NUM_PIPELINES{1'b0}}; 
        end
        else begin
            firstKmerGeneratedForCurrentRead[0]                     <= readValid;
            firstKmerGeneratedForCurrentRead[NUM_PIPELINES - 1 : 1] <= firstKmerGeneratedForCurrentRead[NUM_PIPELINES - 2 : 0];
        end
    end
end

//When the first k-mer has been generated for a given input read, and all counter bits go back to zero for the first time, we have generated all k-mers needed
assign allKmersGeneratedForCurrentRead = firstKmerGeneratedForCurrentRead[NUM_PIPELINES - 1] & ~(|allCounterBits);

//Run counters on requisite positions. Each counter's increment pulse will be MUXED out of the most significant lower order counter that has low quality score
genvar k, a, b, c, d, e, p, q, r;
generate
    for (k = 0; k < MAX_KMER_WIDTH; k = k + 1) begin:thresholdCutOff
        assign threshold[k] = (quality[(k + 1) * QUALITY_WIDTH - 1 : k * QUALITY_WIDTH] < qualityThreshold);
    end

    always @* increment[0][0] <= readValid & ~allKmersGeneratedForCurrentRead & ~(kmerFifoFull | readFifoFull) & threshold[0];

    for (p = 0; p < NUM_PIPELINES - 1; p = p + 1) begin:INITIALPIPELINESTAGES

        //At the beginning of each pipeline stage, latch the results from the previous stage on to here
        for (q = 0; q < p * (MAX_KMER_WIDTH - LAST_STAGE)/(NUM_PIPELINES - 1); q = q + 1) begin:baseline
            always @(posedge clk or negedge rstb) begin
                if (~rstb) begin
                    counters[p][q]  <= 2'b0;
                    increment[p][q] <= 1'b0;
                end
                else begin
                    if (~allKmersGeneratedForCurrentRead) begin
                        counters[p][q]  <= counters[p - 1][q];
                        increment[p][q] <= increment[p - 1][q];
                    end
                end
            end
        end

        //Now build the current stage
        for (a = p * (MAX_KMER_WIDTH - LAST_STAGE)/(NUM_PIPELINES - 1); a < (p + 1) * (MAX_KMER_WIDTH - LAST_STAGE)/(NUM_PIPELINES - 1); a = a + 1) begin:eachPosition
            always @(posedge clk or negedge rstb) begin
                if (~rstb) begin
                    counters[p][a] <= 2'b00;
                end
                else begin
                    if (ready4Read)
                        counters[p][a] <= 2'b00;
                    else
                        counters[p][a] <= increment[p][a] ? ((counters[p][a] == 2'b11) ? 2'b00 : counters[p][a] + 2'b1) : counters[p][a];
                end
            end
            if ((a > 0) || (p > 0)) begin:checkForTheBaseline
                wire [a - 1 : 0]                priorityEncoded;
                wire [1 : 0]                    countersForA[0 : a - 1];
                wire [a - 1 : 0]                countersForATranspose[0 : 1];
                wire [1 : 0]                    counterForA;
                assign priorityEncoded[a - 1] = threshold[a - 1];
                if (a > 1) begin:conditions
                    for (b = 2; b <= a; b = b + 1) begin:priorityEncode
                        assign priorityEncoded[b - 2] = ~(|threshold[a - 1 : b - 2 + 1]) & threshold[b - 2];
                    end
                end

                for (c = 0; c < a; c = c + 1) begin:countersForALoop
                    assign countersForA[c] = (priorityEncoded[c] & increment[p][c]) ? counters[p][c] : 2'b00; //Only when a counter reaches 2'b11 and itself increments should the increment propagate
                end
                for (d = 0; d < a; d = d + 1) begin:transposeOuter     //Decoding logic would be too much I think - hence doing it "one-hot"
                    for (e = 0; e < 2; e = e + 1) begin:transposeInner
                        assign countersForATranspose[e][d] = countersForA[d][e];  //Verilog's syntactical short-comings
                    end
                end
                assign counterForA[1 : 0] = {|(countersForATranspose[1]), |(countersForATranspose[0])}; //Phew! At least this is always 2 bits
                if (p == 0) begin:incrementForStage0
                    always @* increment[p][a] <= (((counterForA == 2'b11) | ~(|increment[p][a - 1 : 0])) & readValid & ~allKmersGeneratedForCurrentRead & ~(kmerFifoFull | readFifoFull) & threshold[a]) & (a < kmerLength); //Don't increment unnecessarily
                end
                else begin:incrementForOtherStages
                    always @* increment[p][a] <= (((counterForA == 2'b11) | ~(|increment[p][a - 1 : 0])) & readValid & ~allKmersGeneratedForCurrentRead & ~(kmerFifoFull | readFifoFull) & threshold[a] & firstKmerGeneratedForCurrentRead[p - 1]) & (a < kmerLength); //Don't increment unnecessarily
                end
            end
        end
    end

    //LAST STAGE
    for (p = NUM_PIPELINES - 1; p < NUM_PIPELINES; p = p + 1) begin:FINALPIPELINESTAGES

        for (q = 0; q < p * (MAX_KMER_WIDTH - LAST_STAGE)/(NUM_PIPELINES - 1); q = q + 1) begin:baseline
            always @(posedge clk or negedge rstb) begin
                if (~rstb) begin
                    counters[p][q]  <= 2'b0;
                    increment[p][q] <= 1'b0;
                end
                else begin
                    if (~allKmersGeneratedForCurrentRead) begin
                        counters[p][q]  <= counters[p - 1][q];
                        increment[p][q] <= increment[p - 1][q];
                    end
                end
            end
        end

        for (a = p * (MAX_KMER_WIDTH - LAST_STAGE)/(NUM_PIPELINES - 1); a < MAX_KMER_WIDTH; a = a + 1) begin:eachPosition
            always @(posedge clk or negedge rstb) begin
                if (~rstb) begin
                    counters[p][a] <= 2'b00;
                end
                else begin
                    if (ready4Read)
                        counters[p][a] <= 2'b00;
                    else
                        counters[p][a] <= increment[p][a] ? ((counters[p][a] == 2'b11) ? 2'b00 : counters[p][a] + 2'b1) : counters[p][a];
                end
            end
            if ((a > 0) || (p > 0)) begin:checkForTheBaseline
                wire [a - 1 : 0]                priorityEncoded;
                wire [1 : 0]                    countersForA[0 : a - 1];
                wire [a - 1 : 0]                countersForATranspose[0 : 1];
                wire [1 : 0]                    counterForA;
                assign priorityEncoded[a - 1] = threshold[a - 1];
                if (a > 1) begin:conditions
                    for (b = 2; b <= a; b = b + 1) begin:priorityEncode
                        assign priorityEncoded[b - 2] = ~(|threshold[a - 1 : b - 2 + 1]) & threshold[b - 2];
                    end
                end

                for (c = 0; c < a; c = c + 1) begin:countersForALoop
                    assign countersForA[c] = (priorityEncoded[c] & increment[p][c]) ? counters[p][c] : 2'b00; //Only when a counter reaches 2'b11 and itself increments should the increment propagate
                end
                for (d = 0; d < a; d = d + 1) begin:transposeOuter     //Decoding logic would be too much I think - hence doing it "one-hot"
                    for (e = 0; e < 2; e = e + 1) begin:transposeInner
                        assign countersForATranspose[e][d] = countersForA[d][e];  //Verilog's syntactical short-comings
                    end
                end
                assign counterForA[1 : 0] = {|(countersForATranspose[1]), |(countersForATranspose[0])}; //Phew! At least this is always 2 bits
                //Increment is the recursive element here - that has been reduced now by having 15 stages at the maximum, the rest is only 5 or 6 gate stages
                always @* increment[p][a] <= ((counterForA == 2'b11) | ~(|increment[p][a - 1 : 0])) & readValid & ~allKmersGeneratedForCurrentRead & ~(kmerFifoFull | readFifoFull) & threshold[a] & firstKmerGeneratedForCurrentRead[p - 1]; //Don't increment unnecessarily
            end
        end
    end
endgenerate

//Generate Increment a counter if the increment pulse goes high
genvar x, y;
generate
    for (x = 0; x < MAX_KMER_WIDTH; x = x + 1) begin:createFirstKmer
        assign firstKmer[2 * (x + 1) - 1 : 2 * x] = ~threshold[x] ? read[2 * (x + 1) - 1 : 2 * x] : counters[NUM_PIPELINES - 1][x]; 
    end
endgenerate

//At the end of the whole thing, push the original k-mer in as well
assign pushKmer = allKmersGeneratedForCurrentRead ? read[2 * MAX_KMER_WIDTH - 1 : 0] : firstKmer;
assign pushRead = allKmersGeneratedForCurrentRead ? read : {read[2 * MAX_READ_WIDTH - 1 : 2 * MAX_KMER_WIDTH], firstKmer};
generate
    if (NUM_PIPELINES > 1) begin:MultipleStages //NUM_PIPELINES < 1 doesn't make sense
        assign push     = ((readValid & ~allKmersGeneratedForCurrentRead)) & ~(kmerFifoFull | readFifoFull) & firstKmerGeneratedForCurrentRead[NUM_PIPELINES - 2];
    end
    else begin
        assign push     = ((readValid & ~allKmersGeneratedForCurrentRead)) & ~(kmerFifoFull | readFifoFull);
    end
endgenerate

//Push k-mers into synchronousFifo
synchronousFifo #(
    .DATA_WIDTH(2 * MAX_KMER_WIDTH),
    .POINTER_SIZE(6),
    .APPARENT_DEPTH(28),
    .FIFO_DEPTH(32)
) kmerFifo (
    .clk(clk),
    .rstb(rstb),
    .data(pushKmer),
    .read(ready4Kmer & ready4Candidate),
    .valid(push),
    .fifoFull(kmerFifoFull),
    .fifoEmpty(kmerFifoEmpty),
    .out(kmer)
);

//Keep reads in another FIFO so that you can take the read out when the k-mer returns from the counting bloom filter
synchronousFifo #(
    .DATA_WIDTH(2 * MAX_READ_WIDTH),
    .POINTER_SIZE(7),
    .APPARENT_DEPTH(60),
    .FIFO_DEPTH(64)
) readFifo (
    .clk(clk),
    .rstb(rstb),
    .data(pushRead),
    .valid(push),
    .read(queryResultValid),
    .fifoFull(readFifoFull),
    .fifoEmpty(readFifoEmpty),
    .out(candidate)
);

//Interface signals
assign kmerValid      = ~kmerFifoEmpty & ready4Candidate;
assign candidateValid = ~readFifoEmpty & queryResultValid & queryResult & ready4Candidate;
assign ready4Read     =  readFifoEmpty & allKmersGeneratedForCurrentRead;

`ifdef VERIFICATION
    wire [1:0] counter_0_0 = counters[0][0];
    wire [1:0] counter_0_1 = counters[0][1];
    wire [1:0] counter_0_2 = counters[0][2];
    wire [1:0] counter_0_3 = counters[0][3];
    wire [1:0] counter_0_4 = counters[0][4];
    wire [1:0] counter_0_5 = counters[0][5];
    wire [1:0] counter_0_6 = counters[0][6];
    wire [1:0] counter_0_7 = counters[0][7];
    wire [1:0] counter_0_8 = counters[0][8];
    wire [1:0] counter_0_9 = counters[0][9];
    wire [1:0] counter_0_10 = counters[0][10];
    wire [1:0] counter_0_11 = counters[0][11];
    wire [1:0] counter_0_12 = counters[0][12];
    wire [1:0] counter_0_13 = counters[0][13];
    wire [1:0] counter_0_14 = counters[0][14];
    wire [1:0] counter_0_15 = counters[0][15];
    wire [1:0] counter_0_16 = counters[0][16];
    wire [1:0] counter_0_17 = counters[0][17];
    wire [1:0] counter_0_18 = counters[0][18];
    wire [1:0] counter_0_19 = counters[0][19];
    wire [1:0] counter_0_20 = counters[0][20];
    wire [1:0] counter_1_0 = counters[1][0];
    wire [1:0] counter_1_1 = counters[1][1];
    wire [1:0] counter_1_2 = counters[1][2];
    wire [1:0] counter_1_3 = counters[1][3];
    wire [1:0] counter_1_4 = counters[1][4];
    wire [1:0] counter_1_5 = counters[1][5];
    wire [1:0] counter_1_6 = counters[1][6];
    wire [1:0] counter_1_7 = counters[1][7];
    wire [1:0] counter_1_8 = counters[1][8];
    wire [1:0] counter_1_9 = counters[1][9];
    wire [1:0] counter_1_10 = counters[1][10];
    wire [1:0] counter_1_11 = counters[1][11];
    wire [1:0] counter_1_12 = counters[1][12];
    wire [1:0] counter_1_13 = counters[1][13];
    wire [1:0] counter_1_14 = counters[1][14];
    wire [1:0] counter_1_15 = counters[1][15];
    wire [1:0] counter_1_16 = counters[1][16];
    wire [1:0] counter_1_17 = counters[1][17];
    wire [1:0] counter_1_18 = counters[1][18];
    wire [1:0] counter_1_19 = counters[1][19];
    wire [1:0] counter_1_20 = counters[1][20];
    wire [1:0] counter_2_0 = counters[2][0];
    wire [1:0] counter_2_1 = counters[2][1];
    wire [1:0] counter_2_2 = counters[2][2];
    wire [1:0] counter_2_3 = counters[2][3];
    wire [1:0] counter_2_4 = counters[2][4];
    wire [1:0] counter_2_5 = counters[2][5];
    wire [1:0] counter_2_6 = counters[2][6];
    wire [1:0] counter_2_7 = counters[2][7];
    wire [1:0] counter_2_8 = counters[2][8];
    wire [1:0] counter_2_9 = counters[2][9];
    wire [1:0] counter_2_10 = counters[2][10];
    wire [1:0] counter_2_11 = counters[2][11];
    wire [1:0] counter_2_12 = counters[2][12];
    wire [1:0] counter_2_13 = counters[2][13];
    wire [1:0] counter_2_14 = counters[2][14];
    wire [1:0] counter_2_15 = counters[2][15];
    wire [1:0] counter_2_16 = counters[2][16];
    wire [1:0] counter_2_17 = counters[2][17];
    wire [1:0] counter_2_18 = counters[2][18];
    wire [1:0] counter_2_19 = counters[2][19];
    wire [1:0] counter_2_20 = counters[2][20];
    wire [1:0] counter_3_0 = counters[3][0];
    wire [1:0] counter_3_1 = counters[3][1];
    wire [1:0] counter_3_2 = counters[3][2];
    wire [1:0] counter_3_3 = counters[3][3];
    wire [1:0] counter_3_4 = counters[3][4];
    wire [1:0] counter_3_5 = counters[3][5];
    wire [1:0] counter_3_6 = counters[3][6];
    wire [1:0] counter_3_7 = counters[3][7];
    wire [1:0] counter_3_8 = counters[3][8];
    wire [1:0] counter_3_9 = counters[3][9];
    wire [1:0] counter_3_10 = counters[3][10];
    wire [1:0] counter_3_11 = counters[3][11];
    wire [1:0] counter_3_12 = counters[3][12];
    wire [1:0] counter_3_13 = counters[3][13];
    wire [1:0] counter_3_14 = counters[3][14];
    wire [1:0] counter_3_15 = counters[3][15];
    wire [1:0] counter_3_16 = counters[3][16];
    wire [1:0] counter_3_17 = counters[3][17];
    wire [1:0] counter_3_18 = counters[3][18];
    wire [1:0] counter_3_19 = counters[3][19];
    wire [1:0] counter_3_20 = counters[3][20];
    wire [1:0] counter_4_0 = counters[4][0];
    wire [1:0] counter_4_1 = counters[4][1];
    wire [1:0] counter_4_2 = counters[4][2];
    wire [1:0] counter_4_3 = counters[4][3];
    wire [1:0] counter_4_4 = counters[4][4];
    wire [1:0] counter_4_5 = counters[4][5];
    wire [1:0] counter_4_6 = counters[4][6];
    wire [1:0] counter_4_7 = counters[4][7];
    wire [1:0] counter_4_8 = counters[4][8];
    wire [1:0] counter_4_9 = counters[4][9];
    wire [1:0] counter_4_10 = counters[4][10];
    wire [1:0] counter_4_11 = counters[4][11];
    wire [1:0] counter_4_12 = counters[4][12];
    wire [1:0] counter_4_13 = counters[4][13];
    wire [1:0] counter_4_14 = counters[4][14];
    wire [1:0] counter_4_15 = counters[4][15];
    wire [1:0] counter_4_16 = counters[4][16];
    wire [1:0] counter_4_17 = counters[4][17];
    wire [1:0] counter_4_18 = counters[4][18];
    wire [1:0] counter_4_19 = counters[4][19];
    wire [1:0] counter_4_20 = counters[4][20];
`endif

endmodule
