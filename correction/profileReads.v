`timescale 1ns / 1ps
module profileReads #(
    parameter MAX_READ_BIT_WIDTH = 8,
    parameter MAX_KMER_BIT_WIDTH = 6,
    parameter NUM_INDICES_BIT_WIDTH = 5,
    parameter NUM_INDICES = {1'b1, {NUM_INDICES_BIT_WIDTH{1'b0}}},
    parameter MAX_READ_WIDTH = {1'b1, {MAX_READ_BIT_WIDTH{1'b0}}},
    parameter MAX_KMER_WIDTH = {1'b1, {MAX_KMER_BIT_WIDTH{1'b0}}},
    parameter MIN_KMER_WIDTH = 12
) (
    input clk,
    input rstb,
    input [2*MAX_READ_WIDTH-1:0] read,
    input readValid,
    input ready4Kmer,
    input queryResult,
    input queryResultValid,
    input [MAX_KMER_BIT_WIDTH-1:0] kmerLength,
    input [MAX_READ_BIT_WIDTH-1:0] readLength,
    input ready4Indices,
    output [2 * MAX_KMER_WIDTH - 1 : 0] kmer,
    output ready4Read,
    output kmerValid,
    output [2*32*NUM_INDICES-1:0] islands,
    output islandsValid
);

//Internal registers and wires
reg [31:0] indices[0:NUM_INDICES-1];
reg [31:0] lengths[0:NUM_INDICES-1];
reg [9:0] islandTraverser;
reg [NUM_INDICES:0] islandCounter;
reg [9:0] readTraverser;
reg [9:0] resultCounter;
reg [31:0] lastWeakKmerPos;
wire [2*MAX_KMER_WIDTH-1:0] allKmers[0:MAX_READ_WIDTH-MIN_KMER_WIDTH];
wire [2*(MAX_READ_WIDTH+MAX_KMER_WIDTH-MIN_KMER_WIDTH)-1:0] extendedReadRegister;
wire [MAX_READ_BIT_WIDTH-1:0] numKmersToExtract;
wire allKmersQueried;
reg allKmersQueried_del;
wire [2*MAX_KMER_WIDTH-1:0] kmerPrelim;
wire kmerValidPrelim;
wire kmerFifoFull;
wire kmerFifoEmpty;

assign extendedReadRegister = {{(MAX_KMER_WIDTH-MIN_KMER_WIDTH){2'b0}},read};
assign numKmersToExtract    = readValid ? readLength-kmerLength : 'b0; //+1 - because of this, I am using "<=" below - though I don't know why I did that
assign allKmersQueried      = (resultCounter > numKmersToExtract);

//Count results and traverse k-mers
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        readTraverser <= 'b0;
        resultCounter <= 'b0;
        lastWeakKmerPos <= -1;
    end
    else begin
        if (ready4Read) begin
            readTraverser <= 'b0;
            resultCounter <= 'b0;
            lastWeakKmerPos <= -1;
        end
        else begin
            if (readValid) begin
                if (kmerValidPrelim) 
                    readTraverser <= readTraverser + 1;
                if (queryResultValid) begin
                    resultCounter <= resultCounter + 1;
                    if (~queryResult) begin
                        lastWeakKmerPos <= resultCounter;
                    end
                end
            end
            else begin
                readTraverser <= 'b0;
                resultCounter <= 'b0;
                lastWeakKmerPos <= -1;
            end
        end
    end
end

//Drive out a valid k-mer
//assign kmerValid = readValid & ready4Kmer & (readTraverser <= numKmersToExtract);
//assign kmer      = allKmers[readTraverser];
assign kmerValidPrelim = readValid & ~kmerFifoFull & (readTraverser <= numKmersToExtract);
assign kmerPrelim      = allKmers[readTraverser];

//Use a FIFO for k-mers - there is too much combinational delay otherwise
synchronousFifo #(
    .FIFO_DEPTH(8),
    .APPARENT_DEPTH(6),
    .POINTER_SIZE(4),
    .DATA_WIDTH(2*MAX_KMER_WIDTH)
) kmerFifo (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(kmerFifoFull),
    .fifoEmpty(kmerFifoEmpty),
    .data(kmerPrelim),
    .valid(kmerValidPrelim),
    .out(kmer),
    .read(ready4Kmer)
);

assign kmerValid = ~kmerFifoEmpty & ready4Kmer;

//Count the length of each island as well as the number of islands
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        islandCounter   <= 'b0;
        islandTraverser <= 'b0;
    end
    else begin
        if (ready4Read) begin
            islandCounter   <= 'b0;
            islandTraverser <= 'b0;
        end
        else begin
            if (queryResultValid) begin
                if (queryResult) begin
                    islandTraverser <= islandTraverser + 1;
                end
                else begin
                    islandTraverser <= 'b0;
                    if (islandTraverser > 0) begin
                        islandCounter <= islandCounter + 1;
                    end
                end
            end
        end
    end
end

genvar k;
generate
    for (k = 0; k < MAX_READ_WIDTH - MIN_KMER_WIDTH + 1; k = k + 1) begin:extractAllKmers
        assign allKmers[k] = extendedReadRegister[2*(MAX_KMER_WIDTH+k)-1:2*k];
    end
endgenerate

//Capture islands
genvar i;
generate
    for (i = 0; i < NUM_INDICES; i=i+1) begin:captureIslands
        always @(posedge clk or negedge rstb) begin
            if (~rstb) begin
                indices[i] <= -1;
                lengths[i] <= -1;
            end
            else begin
                if (ready4Read) begin
                    indices[i] <= -1;
                    lengths[i] <= -1;
                end
                else begin
                    if ((queryResultValid & ~queryResult) | allKmersQueried) begin
                        if (islandTraverser > 0) begin
                            if (islandCounter == i) begin
                                indices[i] <= lastWeakKmerPos + 1;
                                lengths[i] <= islandTraverser;
                            end
                        end
                    end
                end
            end
        end
    end
endgenerate

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        allKmersQueried_del <= 1'b0;
    end
    else begin
        allKmersQueried_del <= ready4Read ? 1'b0 : allKmersQueried;
    end
end

assign ready4Read   = allKmersQueried_del & ready4Indices;
assign islandsValid = ready4Read;

//Put together the output
genvar m;
generate
    for (m = 0; m < NUM_INDICES; m=m+1) begin:assembleOutput
        assign islands[2*32*(m+1)-1:2*32*m] = {lengths[m],indices[m]};
    end
endgenerate

`ifndef SYNTHESIS
wire [31:0] index0 = indices[0];
wire [31:0] index1 = indices[1];
wire [31:0] index2 = indices[2];
wire [31:0] index3 = indices[3];
wire [31:0] index4 = indices[4];
wire [31:0] index5 = indices[5];
wire [31:0] index6 = indices[6];
wire [31:0] index7 = indices[7];
wire [31:0] index8 = indices[8];
wire [31:0] index9 = indices[9];
wire [31:0] index10 = indices[10];
wire [31:0] index11 = indices[11];
wire [31:0] index12 = indices[12];
wire [31:0] index13 = indices[13];
wire [31:0] index14 = indices[14];
wire [31:0] index15 = indices[15];
wire [31:0] index16 = indices[16];
wire [31:0] index17 = indices[17];
wire [31:0] index18 = indices[18];
wire [31:0] index19 = indices[19];
wire [31:0] index20 = indices[20];
wire [31:0] index21 = indices[21];
wire [31:0] index22 = indices[22];
wire [31:0] index23 = indices[23];
wire [31:0] index24 = indices[24];
wire [31:0] index25 = indices[25];
wire [31:0] index26 = indices[26];
wire [31:0] index27 = indices[27];
wire [31:0] index28 = indices[28];
wire [31:0] index29 = indices[29];
wire [31:0] index30 = indices[30];
wire [31:0] index31 = indices[31];

wire [31:0] length0 = lengths[0];
wire [31:0] length1 = lengths[1];
wire [31:0] length2 = lengths[2];
wire [31:0] length3 = lengths[3];
wire [31:0] length4 = lengths[4];
wire [31:0] length5 = lengths[5];
wire [31:0] length6 = lengths[6];
wire [31:0] length7 = lengths[7];
wire [31:0] length8 = lengths[8];
wire [31:0] length9 = lengths[9];
wire [31:0] length10 = lengths[10];
wire [31:0] length11 = lengths[11];
wire [31:0] length12 = lengths[12];
wire [31:0] length13 = lengths[13];
wire [31:0] length14 = lengths[14];
wire [31:0] length15 = lengths[15];
wire [31:0] length16 = lengths[16];
wire [31:0] length17 = lengths[17];
wire [31:0] length18 = lengths[18];
wire [31:0] length19 = lengths[19];
wire [31:0] length20 = lengths[20];
wire [31:0] length21 = lengths[21];
wire [31:0] length22 = lengths[22];
wire [31:0] length23 = lengths[23];
wire [31:0] length24 = lengths[24];
wire [31:0] length25 = lengths[25];
wire [31:0] length26 = lengths[26];
wire [31:0] length27 = lengths[27];
wire [31:0] length28 = lengths[28];
wire [31:0] length29 = lengths[29];
wire [31:0] length30 = lengths[30];
`endif

endmodule
