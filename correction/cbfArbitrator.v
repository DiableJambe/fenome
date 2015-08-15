`timescale 1ps / 1ps
//Arbitrates between 'n' masters and slaves, yeah?
module cbfArbitrator #(
    parameter TOKEN_WIDTH               = 1,    //floor(log2(NUM_MASTERS)) + 1
    parameter NUM_MASTERS               = {1'b1, {TOKEN_WIDTH{1'b0}}},
    parameter KMER_WIDTH                = 45,
    parameter FLOPRESULT                = 0,
    parameter FLOPOUTPUTS               = 0,
    parameter TOKEN_FIFO_DEPTH_BITS     = 10,             //Don't let this be the bottle-neck
    parameter TOKEN_FIFO_DEPTH          = {1'b1, {TOKEN_FIFO_DEPTH_BITS{1'b0}}},
    parameter TOKEN_FIFO_APPARENT_DEPTH = TOKEN_FIFO_DEPTH - 4
) (
    input clk,
    input rstb,
    input [NUM_MASTERS * KMER_WIDTH * 2 - 1 : 0] inKmers,   //Incoming k-mers from the masters
    input cbfReady,                                     //Incoming cbfReady signal from the CBF
    input kmerPositive,                                 //Incoming kmerPositive from the CBF
    input resultValid,                                  //Incoming resultValid from the CBF
    input [NUM_MASTERS - 1 : 0] kmerValid,              //Incoming kmerValid from the masters
    output [NUM_MASTERS - 1 : 0] readyToMasters,        //Outgoing readyForKmer to the Masters
    output [2 * KMER_WIDTH - 1 : 0] kmerToCBF,          //Outgoing kmer to the CBF
    output kmerValidToCBF,                              //k-mer valid signal sent to CBF 
    output [NUM_MASTERS - 1 : 0] positive,              //k-mer positive to the masters
    output [NUM_MASTERS - 1 : 0] resultValidM           //resultValid to the masters
);

//Internal signals
wire tokenFifoFull;
wire tokenFifoEmpty;
wire [TOKEN_WIDTH - 1 : 0]     token;
wire [TOKEN_WIDTH - 1 : 0]     tokenData;
wire [TOKEN_WIDTH - 1 : 0]     tokenDataPrelim[0 : NUM_MASTERS - 1];
wire [NUM_MASTERS - 1 : 0]     tokenDataTranspose[0 : TOKEN_WIDTH - 1];
wire [2 * KMER_WIDTH - 1 : 0]  kmerToCBFPrelim[0 : NUM_MASTERS - 1];
wire [NUM_MASTERS - 1 : 0]     kmerToCBFPrelimTranspose[0 : 2 * KMER_WIDTH - 1];
wire [2 * KMER_WIDTH - 1 : 0]  kmerToCBFComb;
wire                           kmerValidToCBFComb;
wire [NUM_MASTERS - 1 : 0]     resultValidMComb;
reg  [NUM_MASTERS - 1 : 0]     resultValidMReg;
reg  [NUM_MASTERS - 1 : 0]     positiveReg;
wire [NUM_MASTERS - 1 : 0]     positiveComb;

//Note that we have a margin of more than one "full" value - so we can delay the outputs by one cycle
reg [2 * KMER_WIDTH - 1 : 0]   kmerToCBFFlopped;
reg                            kmerValidToCBFFlopped;

//When a kmerValid appears on a higher-priority bit, all lower priority readys are set to 0
//No combinational loop, you see ...
assign readyToMasters[NUM_MASTERS - 1] = cbfReady & ~tokenFifoFull;
genvar m;
generate
    for (m = 0; m < NUM_MASTERS - 1; m = m + 1) begin:readyAssignment
        assign readyToMasters[m] = ~(|kmerValid[NUM_MASTERS - 1 : m + 1]) ? cbfReady & ~tokenFifoFull : 1'b0;
    end
endgenerate

genvar i, j, k, l, n;
generate
    for (i = 0; i < NUM_MASTERS; i = i + 1) begin:tokenAndKmerDecode
        assign tokenDataPrelim[i] = (kmerValid[i] & readyToMasters[i]) ? i : {TOKEN_WIDTH{1'b0}};
        assign kmerToCBFPrelim[i] = (kmerValid[i] & readyToMasters[i]) ? inKmers[2 * KMER_WIDTH * (i + 1) - 1 : 2 * KMER_WIDTH * i] : {2 * KMER_WIDTH{1'b0}};
    end
    for (j = 0; j < TOKEN_WIDTH; j = j + 1) begin:tokenDataTransposeOuter
        for (k = 0; k < NUM_MASTERS; k = k + 1) begin:tokenDataTransposeInner
            assign tokenDataTranspose[j][k] = tokenDataPrelim[k][j];
        end
        assign tokenData[j] = |(tokenDataTranspose[j]);
    end
    for (l = 0; l < 2 * KMER_WIDTH; l = l + 1) begin:kmerToCBFTransposeOuter
        for (n = 0; n < NUM_MASTERS; n = n + 1) begin:kmerToCBFTranspose
            assign kmerToCBFPrelimTranspose[l][n] = kmerToCBFPrelim[n][l];
        end
        assign kmerToCBFComb[l] = |(kmerToCBFPrelimTranspose[l]);
    end
endgenerate

//Kmer Valid to CBF is not driven when token FIFO goes full. Ready is not driven to the masters either.
assign kmerValidToCBFComb = cbfReady & ~tokenFifoFull & |(kmerValid);

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        kmerToCBFFlopped      <= {2 * KMER_WIDTH{1'b0}};
        kmerValidToCBFFlopped <= 1'b0;
    end
    else begin
        kmerToCBFFlopped      <= kmerToCBFComb;
        kmerValidToCBFFlopped <= kmerValidToCBFComb;
    end
end

generate
    if (FLOPOUTPUTS == 1) begin:FLOPOUTBLOCKS
        assign kmerToCBF      = kmerToCBFFlopped;
        assign kmerValidToCBF = kmerValidToCBFFlopped;
    end
    else begin:NOFLOPOUT
        assign kmerToCBF         = kmerToCBFComb;
        assign kmerValidToCBF    = kmerValidToCBFComb;
    end
endgenerate

//Have a synchronous FIFO storing all outstanding transactions with ids
synchronousFifo #(
    .DATA_WIDTH(TOKEN_WIDTH),
    .APPARENT_DEPTH(TOKEN_FIFO_APPARENT_DEPTH),
    .FIFO_DEPTH(TOKEN_FIFO_DEPTH),
    .POINTER_SIZE(TOKEN_FIFO_DEPTH_BITS + 1)
) tokenFifo (
    .clk(clk),
    .rstb(rstb),
    .valid(kmerValidToCBFComb),
    .read(resultValid),
    .data(tokenData),
    .fifoFull(tokenFifoFull),
    .fifoEmpty(tokenFifoEmpty),
    .out(token)
);

//Control the valid signal to the output
genvar p;
generate
    for (p = 0; p < NUM_MASTERS; p = p + 1) begin:validGenerate
        assign resultValidMComb[p] = (token == p) ? resultValid : 1'b0;
    end
endgenerate

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        resultValidMReg <= {NUM_MASTERS{1'b0}};
        positiveReg     <= 1'b0;
    end
    else begin
        resultValidMReg <= resultValidMComb;
        positiveReg     <= positiveComb;
    end
end

assign positiveComb = {NUM_MASTERS{kmerPositive}};


generate
    if (FLOPRESULT == 1) begin:flopResult
        assign positive = positiveReg;
        assign resultValidM = resultValidMReg;
    end
    else begin:doNotFlopResult
        assign positive = positiveComb;
        assign resultValidM = resultValidMComb;
    end
endgenerate

endmodule
