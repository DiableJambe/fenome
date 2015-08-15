`timescale 1ps/1ps
module cbfWrapperForAltera #(
    parameter KMER_WIDTH            = 45,
    parameter HASH_WIDTH            = 30, 
    parameter SUBSIDIARY_HASH_WIDTH = 9,  
    parameter BLOCK_SIZE            = 1,
    parameter BLOCK_BIT_SIZE        = 0,
    parameter ADDR_WIDTH            = HASH_WIDTH + BLOCK_BIT_SIZE,
    parameter NUM_HASHES            = 8,
    parameter NUM_DIMMS             = 2,
    parameter DATA_WIDTH            = 512,
    parameter NUM_BITS_DATA         = 9,
    parameter NUM_BITS_DIMMS        = 1,
    parameter CBF_WIDTH             = 2,
    parameter CBF_BIT_WIDTH         = 1
) (
    input clk,                                                     //Clock
    input rstb,                                                    //Reset
    input ipValid,                                                 //Input k-mer valid
    input pnr,                                                     //Program Not Read
    input [2 * KMER_WIDTH - 1 : 0] kmer,                           //The input k-mer
    input [DATA_WIDTH * NUM_DIMMS - 1 : 0] data,                   //Input data from the external memory interfaces
    input [NUM_DIMMS - 1 : 0] avl_ready,                           //Avalon ready for input
    input [NUM_DIMMS - 1 : 0] controllerDataValid,                 //Input data valid from the external memory interface
    input [CBF_WIDTH - 1 : 0] threshold,
    input halt,

    output ready,                                                  //CBF is ready to accept inputs
    output reg opValid,                                            //Output valid
    output [NUM_DIMMS * ADDR_WIDTH - 1 : 0] addr,                  //Address to be sent out to the avalon interface
    output [NUM_DIMMS * DATA_WIDTH - 1 : 0] wdata,                 //Write data to be sent out to the external memory interface
    output [NUM_DIMMS - 1 : 0] rd,                                 //Read signal sent out to the external memory interface
    output [NUM_DIMMS - 1 : 0] wr,                                 //Write signal sent out to the external memory interface
    output bcbfIdle,                                               //The blocked bloom is idle
    output [({CBF_WIDTH{1'b1}} + 1) * 32 - 1 : 0] histogram,       //The current histogram of k-mers
    output reg positive,                                           //K-mer is positive, or solid
    output bcbfReady4Data
);

//Internal wires and signals
wire [ADDR_WIDTH - 1 : 0] raddr;
wire [ADDR_WIDTH - 1 : 0] waddr;
wire [NUM_DIMMS - 1 : 0]  dimmFifoFull;
wire [NUM_DIMMS - 1 : 0]  dimmFifoEmpty;
wire [NUM_DIMMS * DATA_WIDTH - 1 : 0] readData;
wire [NUM_DIMMS - 1 : 0] commandFifoFull;
wire [NUM_DIMMS - 1 : 0] commandFifoEmpty;
wire [NUM_DIMMS - 1 : 0] cmd;
wire [NUM_DIMMS * DATA_WIDTH - 1 : 0] wdataCbf;
wire cbfWr;
wire cbfRd;
wire controllerDataValidInternal;
wire controllerWriteReadyInternal;
wire controllerReadReadyInternal;
wire bcbfReady4DataInternal;
wire cbfReady;
wire kmerValid;
wire [2 * KMER_WIDTH - 1 : 0] kmerInternal;
wire fifoFull;
wire fifoEmpty;

//Input FIFO for kmers
synchronousFifo #(
    .DATA_WIDTH(2 * KMER_WIDTH),
    .FIFO_DEPTH(32),
    .APPARENT_DEPTH(28),
    .POINTER_SIZE(6)
) inputKmerFifo (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(fifoFull),
    .fifoEmpty(fifoEmpty),
    .valid(/*ready &*/ ipValid), //Gated appropriately outside - need cushioning actually, so don't gate
    .read(cbfReady),
    .data(kmer),
    .out(kmerInternal)
);

assign ready     = ~fifoFull;
assign kmerValid = cbfReady & ~fifoEmpty;

//The read data path. The two controllers can give data in slightly different cycles because of on-board timing variations
genvar k;
generate
    if (NUM_DIMMS > 1) begin:multipleDIMMsReturnPath
        for (k = 0; k < NUM_DIMMS; k = k + 1) begin:loopings
            synchronousFifo #(
                .DATA_WIDTH(DATA_WIDTH),
                .FIFO_DEPTH(16),
                .APPARENT_DEPTH(12),
                .POINTER_SIZE(5)
            ) dataDIMMFifo (
                .clk(clk),
                .rstb(rstb),
                .read(~(|dimmFifoEmpty) & bcbfReady4DataInternal),
                .data(data[(k + 1) * DATA_WIDTH - 1 : k * DATA_WIDTH]),
                .valid(controllerDataValid[k] & bcbfReady4Data),
                .fifoFull(dimmFifoFull[k]),
                .fifoEmpty(dimmFifoEmpty[k]),
                .out(readData[(k + 1) * DATA_WIDTH - 1 : k * DATA_WIDTH])
            );
        end
        assign controllerDataValidInternal = ~(|dimmFifoEmpty);
        assign bcbfReady4Data              = ~(|dimmFifoFull);
    end
    else begin:singleDIMMReturnPath
        assign readData                    = data;
        assign controllerDataValidInternal = controllerDataValid;
        assign bcbfReady4Data              = bcbfReady4DataInternal;
    end
endgenerate

//Command output FIFOs. This FIFO enforces ordering between writes and reads.  So a read-write ordering check is required only inside the BCBF.
genvar l;
generate
    if (NUM_DIMMS > 1) begin:multipleDIMMsCommandPath
        for (l = 0; l < NUM_DIMMS; l = l + 1) begin:commandOutput
            synchronousFifo #(
                .DATA_WIDTH(ADDR_WIDTH + DATA_WIDTH + 1), //The address, data and command
                .FIFO_DEPTH(16),
                .APPARENT_DEPTH(12),
                .POINTER_SIZE(5)
            ) commandDIMMFIFO (
                .clk(clk), 
                .rstb(rstb),
                .data(cbfWr ? {waddr, wdataCbf[(l + 1) * DATA_WIDTH - 1 : l * DATA_WIDTH], 1'b1} : {raddr, {DATA_WIDTH{1'b0}}, 1'b0}),
                .read(avl_ready[l] & (~(dimmFifoFull[l]) | cmd[l]) & ~commandFifoEmpty[l] & ~halt),
                .valid((cbfWr | cbfRd) & ~(|commandFifoFull)),
                .fifoFull(commandFifoFull[l]),
                .fifoEmpty(commandFifoEmpty[l]),
                .out({addr[(l + 1) * ADDR_WIDTH - 1 : l * ADDR_WIDTH], wdata[(l + 1) * DATA_WIDTH - 1 : l * DATA_WIDTH], cmd[l]})
            );

            //Decode commands -> assuming that inputs to the controller are synchronous!!!
            assign wr[l] =  cmd[l] & ~commandFifoEmpty[l] & ~halt;
            assign rd[l] = ~(cmd[l] | commandFifoEmpty[l]) & ~(dimmFifoFull[l]) & ~halt;
        end
        assign controllerReadReadyInternal  = ~(|dimmFifoFull) & ~(|commandFifoFull);
        assign controllerWriteReadyInternal = ~(|commandFifoFull);
    end
    else begin:singleDIMMCommandPath
        assign wr                           = cbfWr;
        assign rd                           = cbfRd;
        assign addr                         = cbfWr ? waddr : raddr;
        assign wdata                        = wdataCbf;
        assign controllerReadReadyInternal  = avl_ready & ~halt;
        assign controllerWriteReadyInternal = avl_ready & ~halt;
    end
endgenerate

//Instanciate the CBF
bcbf #(
    .KMER_WIDTH(KMER_WIDTH),
    .HASH_WIDTH(HASH_WIDTH), 
    .BLOCK_SIZE(BLOCK_SIZE),
    .SUBSIDIARY_HASH_WIDTH(NUM_BITS_DATA + NUM_BITS_DIMMS + BLOCK_BIT_SIZE - CBF_BIT_WIDTH),  //This maybe done inside the blocked counting bloom filter as well
    .BLOCK_BIT_SIZE(BLOCK_BIT_SIZE),
    .NUM_HASHES(NUM_HASHES),
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH * NUM_DIMMS),
    .CBF_WIDTH(CBF_WIDTH)
) cbfInst (
    .clk(clk),
    .rstb(rstb),
    .ipValid(kmerValid),
    .pnr(pnr),
    .kmer(kmerInternal),
    .rdata(readData),
    .threshold(threshold),
    .controllerReadReady(controllerReadReadyInternal),     //Do not read if there is too much read data to process, or if too many commands not yet accepted by even one of the memory controllers
    .controllerWriteReady(controllerWriteReadyInternal),                       //Too many commands not yet accepted by the controller
    .controllerDataValid(controllerDataValidInternal),
    .ready(cbfReady),
    .bcbfReady4Data(bcbfReady4DataInternal),
    .opValid(opValidNET),
    .raddr(raddr),
    .waddr(waddr),
    .wdata(wdataCbf),
    .bcbfIdle(bcbfIdle),
    .histogram(histogram),
    .rd(cbfRd),
    .wr(cbfWr),
    .positive(positiveNET)
);

//Pipeline stage to error correction blocks
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        opValid  <= 1'b0;
        positive <= 1'b0;
    end
    else begin
        opValid  <= opValidNET;
        positive <= positiveNET;
    end
end

endmodule
