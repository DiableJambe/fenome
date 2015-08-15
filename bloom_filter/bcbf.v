`timescale 1ps/1ps
//The BCBF is not agnostic of the number of data items to be read from the external memory
//But it is agnostic of the number of memory modules on the board - that has to be handled outside
module bcbf #(
    parameter HASH_WIDTH            = 30, 
    parameter SUBSIDIARY_HASH_WIDTH = 9,  
    parameter BLOCK_SIZE            = 1,                                             //Number of data inputs that result in a block of data from memory
    parameter BLOCK_BIT_SIZE        = 0,
    parameter NUM_HASHES            = 7,
    parameter ADDR_WIDTH            = HASH_WIDTH + BLOCK_BIT_SIZE,
    parameter DATA_WIDTH            = 1024,
    parameter CBF_WIDTH             = 1,
    parameter MAX_KMER_BIT_WIDTH    = 6,
    parameter MAX_KMER_WIDTH        = {1'b1,{MAX_KMER_BIT_WIDTH{1'b0}}}
) (
    input clk,                                                    //Clock
    input rstb,                                                   //Reset
    input ipValid,                                                //Input k-mer valid
    input pnr,                                                    //Program Not Read
    input [2 * MAX_KMER_WIDTH - 1 : 0] kmer,                      //The input k-mer
    input [DATA_WIDTH - 1 : 0] rdata,                             //Input data from the external memory interface
    input controllerReadReady,                                    //The memory controller is ready for reads
    input controllerWriteReady,                                   //The memory controller is ready for writes
    input controllerDataValid,                                    //Input data valid from the external memory interface
    output bcbfIdle,                                              //All FIFOs are empty
    input [CBF_WIDTH - 1 : 0] threshold,                          //CBF threshold value
    input [MAX_KMER_BIT_WIDTH-1:0] kmerLength,                    //k-mer length as programmed into the MMIO registers
    output ready,                                                 //CBF is ready to accept inputs
    output opValid,                                               //Output valid
    output [ADDR_WIDTH - 1 : 0] raddr,                            //Read address to be sent out to the external memory interface
    output [ADDR_WIDTH - 1 : 0] waddr,                            //Write address to be sent out to the external memory interface
    output [DATA_WIDTH - 1 : 0] wdata,                            //Write data to be sent out to the external memory interface
    output rd,                                                    //Read signal sent out to the external memory interface
    output bcbfReady4Data,                                        //BCBF is ready to accept external data - for an external FIFO interface
    output wr,                                                    //Write signal sent out to the external memory interface
    output [({CBF_WIDTH{1'b1}} + 1) * 32 - 1 : 0] histogram,      //Histogram data to be sent to the PC interface
    output positive                                               //k-mer is positive, or solid
);

//Internal signals
wire [2 * MAX_KMER_WIDTH - 1: 0]       inputKmer;                                              //k-mer from the input fifo output
wire [HASH_WIDTH - 1 : 0]              hash;                                                   //The hash function outputs
wire [SUBSIDIARY_HASH_WIDTH - 1 : 0]   subsidiaryHash[0 : NUM_HASHES - 2];                     //Subsidiary Hash values
wire                                   readInputFifo;                                          //Signals the input fifo that the current output data has been read
wire                                   inputFifoEmpty;                                         //Output of input fifo signalling that the input fifo is empty
wire                                   inputFifoFull;                                          //Output of the input fifo signalling that it is empty
wire                                   validOut;                                               //Valid out from the MISR banks
wire [2 * MAX_KMER_WIDTH - 1 : 0]      readKmer;                                               //The output of the k-mer FIFO (parallel with the address FIFO)
wire                                   readPnr;                                                //The output program/read of the k-mer FIFO
wire [DATA_WIDTH - 1 : 0]              writeData;                                              //The data stored in the write-data FIFO
wire [HASH_WIDTH - 1 : 0]              writeAddress;                                           //The output of the write address FIFO
wire [NUM_HASHES - 2 : 0]              partPositive;                                           //Holds whether each count is positive
wire                                   readFifoFull;                                           //Indicates that the read address FIFO is full
wire                                   writeDataFifoFull;                                      //Write data fifo full
wire                                   writeAddressFifoFull;                                   //Write address fifo full
reg                                    dataValidDelayed;                                       //Delayed read data valid to correctly schedule the output valid signal
wire [SUBSIDIARY_HASH_WIDTH * (NUM_HASHES - 1) - 1 : 0]   hashLineOut;                         //The output of the FIFOs that store the hash values
wire [BLOCK_SIZE * DATA_WIDTH - 1 : 0] incrementedBlock;                                       //The incremented write-back data
wire                                   pause;                                                  //Pause the pipeline
wire [2 * MAX_KMER_WIDTH - 1 : 0]      reverseComplimentedKmer;                                //k-mer reverse compliment
wire [BLOCK_BIT_SIZE - 1 : 0]          lowerAddressBits[0 : BLOCK_SIZE - 1];                   //The lower DDR3 address bits
wire [ADDR_WIDTH * BLOCK_SIZE - 1 : 0] addressesForHash;                                       //The final address to be sent to the hash
wire [BLOCK_SIZE * DATA_WIDTH - 1 : 0] block;                                                  //A complete block of the blocked bloom filter
wire [CBF_WIDTH * (NUM_HASHES - 1) - 1 : 0] cbfItems;                                          //CBF fields extracted from the hash line
wire                                   check;                                                  //Check whether the current read address is in the write address FIFO 
wire                                   otherHashFull;
wire                                   otherHashEmpty;
wire                                   readDataFifoEmpty;
wire                                   readDataFifoFull;
reg [31 : 0]                           histogramRegisters[0 : {CBF_WIDTH{1'b1}}];
wire [CBF_WIDTH - 1 : 0]               minimum;
wire                                   ready4_data_hash_function;
wire                                   readFifoEmpty;
wire                                   writeDataFifoEmpty;
wire                                   testFifoFull;
wire [SUBSIDIARY_HASH_WIDTH * (NUM_HASHES - 1) - 1 : 0] subsidiaryHashCollated;
wire                                   revValid;
wire                                   hashEmpty;
wire                                   kmerReverseEmpty;

//Create static lower bits - bit size is fixed this way
genvar k;
generate
    for (k = 0; k < BLOCK_SIZE; k = k + 1) begin:generateLowerAddressBits
        assign lowerAddressBits[k] = k;
    end
endgenerate

//Well, histogram stuff
genvar p;
generate
    if (CBF_WIDTH > 1) begin:histogramStuff
        findMinimum #(
            .NUM_ITEMS(NUM_HASHES - 1),
            .ITEM_WIDTH(CBF_WIDTH)
        ) findMin (
            .items(cbfItems),
            .minimum(minimum)
        );

        for (p = 1; p <= {CBF_WIDTH{1'b1}}; p = p + 1) begin:some_name //How many k-mers occur zero times? no need :-)
            always @(posedge clk or negedge rstb) begin
                if (~rstb) begin
                    histogramRegisters[p] <= 32'b0;
                end
                else begin
                    if (opValid & pnr) begin
                        if (minimum == p - 1) begin //minimum is going to be 'p' after this k-mer is programmed
                            histogramRegisters[p] <= histogramRegisters[p] + 32'b1;
                        end
                        if ((minimum == p) && (p != {CBF_WIDTH{1'b1}})) begin
                            histogramRegisters[p] <= histogramRegisters[p] - 32'b1;
                        end
                    end
                end
            end

            assign histogram[(p + 1) * 32 - 1 : p * 32] = histogramRegisters[p];
        end
        assign histogram[31:0] = 32'b0;
    end
endgenerate

///Take the reverse compliment of incoming k-mer if necessary and use that
kmerReverseComplement #(
    .MAX_KMER_WIDTH(MAX_KMER_WIDTH)
) reverseTheKmerIfNecessary (
    .clk(clk),
    .rstb(rstb),
    .kmerValid(ipValid),
    .kmer(kmer),
    .ready(ready),
    .kmerLength(kmerLength),
    .opValid(revValid),
    .empty(kmerReverseEmpty),
    .out(reverseComplimentedKmer)
);

///The reverse complimented input is sent to a FIFO first
synchronousFifo #(
    .DATA_WIDTH(2 * MAX_KMER_WIDTH),
    .FIFO_DEPTH(16),
    .APPARENT_DEPTH(12),
    .POINTER_SIZE(5)
) inputDataFifo (
    .clk(clk),
    .rstb(rstb),
    .valid(revValid),
    .read(readInputFifo),
    .data(reverseComplimentedKmer),
    .fifoFull(inputFifoFull),
    .fifoEmpty(inputFifoEmpty),
    .out(inputKmer)
);

//If the input fifo is full, the module feeding data to the CBF shouldn't speak
assign ready = ~inputFifoFull & ~testFifoFull;

//Generation of the "read" signal for the inputDataFifo
assign readInputFifo = ready4_data_hash_function;

//Ready for data or not, from the memory controller interface
assign bcbfReady4Data = ~readDataFifoFull;

////Signalling diagram of how the output FIFO controls the hash functions and the input FIFO (assuming inputFifoEmpty is zero)
//                 ______     ______     ______     ______     ______     ______     ______
//clk          ___|      |___|      |___|      |___|      |___|      |___|      |___|      |___
//                                       ________________________________
//readFifoFull _________________________|                                |_____________________
//             ___ __________ __________ ___________________________________________ __________
//out          ___|__________|__________|___________________________________________|__________
//             ___ __________ __________ ___________________________________________ __________
//hash         ___|__________|__________|___________________________________________|__________
//             _________________________                                  _____________________
//validOut                              |________________________________|                      (validOut should be gated with pause)

////Note: The read address FIFO needs to stop the input FIFO and the hash functions when it gets full
   //The fifo-full signal of the read address FIFO stops the input FIFO from shifting data out (through the "read" input)
   //The fifo-full signal of the read address FIFO stops the hash functions through the "pause" signal
////Note: The input FIFO needs to stop the subsequent data path
   //The fifo-empty signal of the input FIFO renders the hash output invalid (through validIn)
   //When validIn is zero, the corresponding hash outputs have validOut = 0 and hence do not force a data shift into the read address FIFO

hash_function #(
    .DATA_WIDTH(2*MAX_KMER_WIDTH),
    .MAIN_HASH_WIDTH(HASH_WIDTH),
    .SUBSIDIARY_HASH_WIDTH(SUBSIDIARY_HASH_WIDTH),
    .NUM_SUBSIDIARY_HASH(NUM_HASHES-1),
    .NUM_STAGES(8),
    .LAST_STAGE_SIZE(16)
) hash_gen (
    .clk(clk),
    .rstb(rstb),
    .data(inputKmer[2*MAX_KMER_WIDTH-1:0]),
    .data_valid(~inputFifoEmpty),
    .ready4_hash(~pause),
    .hash_valid(validOut),
    .ready4_data(ready4_data_hash_function),
    .main_hash(hash),
    .empty(hashEmpty),
    .subsidiary_hash_values(subsidiaryHashCollated)
);

//Pause MISR operation when downstream FIFOs are full; otherHashFull implies outstanding reads, lets get them done before requesting more hash values
assign pause = readFifoFull | otherHashFull;

//Generate BLOCK_SIZE number of addresses for each hash value
genvar m;
generate
    if (BLOCK_SIZE > 1) begin:blockBiggerThan1
        for (m = 0; m < BLOCK_SIZE; m = m + 1) begin:addressesGeneratedFromHash
            assign addressesForHash[ADDR_WIDTH * (m + 1) - 1 : ADDR_WIDTH * m] = {hash, lowerAddressBits[m]};
        end
    end
    else begin:blockSmallerThan1
        assign addressesForHash = hash;
    end
endgenerate

generate
    if (BLOCK_SIZE > 1) begin:generateParallelFifoForAddress
        synchronousFifoParallelShiftParameterized #(
            .SPLIT_WIDTH(ADDR_WIDTH),
            .NUM_SPLITS(BLOCK_SIZE),
            .NUM_SPLITS_BIT_WIDTH(BLOCK_BIT_SIZE),
            .SUB_FIFO_POINTER_SIZE(6),
            .POINTER_SIZE(6 + BLOCK_BIT_SIZE),
            .APPARENT_DEPTH(28 * BLOCK_SIZE),
            .FIFO_DEPTH(32 * BLOCK_SIZE)
        ) addressShift (
            .clk(clk),
            .rstb(rstb),
            .valid(validOut),
            .read(rd & controllerReadReady),
            .data(addressesForHash),
            .fifoFull(readFifoFull),
            .fifoEmpty(readFifoEmpty),
            .out(raddr)
        );
    end
    else begin:generateSerialFifoForAddress
        synchronousFifo #(
            .DATA_WIDTH(ADDR_WIDTH),
            .POINTER_SIZE(6),
            .APPARENT_DEPTH(28),
            .FIFO_DEPTH(32)
        ) addressShift (
            .clk(clk),
            .rstb(rstb),
            .valid(validOut),
            .read(rd & controllerReadReady),
            .data(addressesForHash),
            .fifoFull(readFifoFull),
            .fifoEmpty(readFifoEmpty),
            .out(raddr)
        );
    end
endgenerate

//The subsidiary hashes are stored here and used as and when a block of data is available
synchronousFifo #(
    .DATA_WIDTH(SUBSIDIARY_HASH_WIDTH * (NUM_HASHES - 1)),
    .APPARENT_DEPTH(28),
    .FIFO_DEPTH(32),
    .POINTER_SIZE(6)
) otherHashShift (
    .clk(clk),
    .rstb(rstb),
    .valid(validOut),
    .read(~readDataFifoEmpty & ~writeDataFifoFull),
    .data(subsidiaryHashCollated),
    .fifoFull(otherHashFull),
    .fifoEmpty(otherHashEmpty),
    .out(hashLineOut)
);

assign rd    = ~readFifoEmpty & ~readDataFifoFull & ~writeAddressFifoFull & ~otherHashEmpty & ~wr; //Finish writes before you read
               //Explanations: If either of readFifo or otherHash FIFO is empty, there are no addresses to send out for the bloom filter.
               //Explanations: writeDataFifo, writeAddress, and readDataFifo FIFOs are filled by read operations and emptied by write operations. If full, wait for some writes to happen.
               //Not gating with ready - we don't know what sits outside yet


//NOTE: <Number of items in the otherHashShift FIFO>  - <Number of items in the addressShift FIFO> = <Number of outstanding read requests>
//NOTE: <Number of outstanding read requests> <= <Number of items in the otherHashShift FIFO> = <Depth of the otherHashShift FIFO>
//NOTE: <Number of items in the otherHashShift FIFO>  - <Number of items in the addressShift FIFO> = <Number of outstanding read requests>
//NOTE: <Number of outstanding read requests> <= <Number of items in the otherHashShift FIFO> = <Depth of the otherHashShift FIFO>
//NOTE: <Number of extra spots in readDataFifo after FIFO full> = <Number of outstanding read requests> <= <Depth of otherHashShift FIFO>
//NOTE: <Number of extra spots in readDataFifo after FIFO full> = <Number of outstanding read requests> <= <Depth of otherHashShift FIFO>
//NOTE: <Depth of otherHashShift FIFO> = 32. Hence have 32 extra spots in readDataFifo after full (this is actually a hysteresis)

generate
if (BLOCK_SIZE > 1) begin:manyBlocksPerBlock
    synchronousFifoSerialToParallelParameterized #(
        .SPLIT_WIDTH(DATA_WIDTH),
        .NUM_SPLITS(BLOCK_SIZE),
        .NUM_SPLITS_BIT_WIDTH(BLOCK_BIT_SIZE),
        .SUB_FIFO_POINTER_SIZE(7),
        .POINTER_SIZE(7 + BLOCK_BIT_SIZE),
        .APPARENT_DEPTH(32 * BLOCK_SIZE),
        .FIFO_DEPTH(64 * BLOCK_SIZE)
    ) readDataFifo (
        .clk(clk),
        .rstb(rstb),
        .valid(controllerDataValid),
        .read(~writeDataFifoFull & ~readDataFifoEmpty),
        .data(rdata),
        .fifoFull(readDataFifoFull),
        .fifoEmpty(readDataFifoEmpty),
        .out(block)
    );
end
else begin:oneLinePerBlock
    synchronousFifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .POINTER_SIZE(7),
        .APPARENT_DEPTH(32),
        .FIFO_DEPTH(64)
    ) readDataFifo (
        .clk(clk),
        .rstb(rstb),
        .valid(controllerDataValid),
        .read(~writeDataFifoFull & ~readDataFifoEmpty),
        .data(rdata),
        .fifoFull(readDataFifoFull),
        .fifoEmpty(readDataFifoEmpty),
        .out(block)
    );
end
endgenerate

//Decode the received line
blockDecoder #(
    .NUM_HASHES(NUM_HASHES - 1),
    .VECTOR_WIDTH(DATA_WIDTH * BLOCK_SIZE / CBF_WIDTH), //Total block size divided by the width of the CBF
    .NUM_BITS_TO_ADDRESS_VECTOR(SUBSIDIARY_HASH_WIDTH),
    .CBF_WIDTH(CBF_WIDTH)
) decodeBlock (
    .hashes(hashLineOut),
    .block(block),
    .elements(cbfItems),
    .incrementedBlock(incrementedBlock)
);

`ifdef VERIFICATION
wire [CBF_WIDTH * (NUM_HASHES - 1) - 1 : 0] elements;                                          //CBF fields extracted from the hash line
wire [2 * MAX_KMER_WIDTH - 1 : 0] testKmer;
blockDecoder #(
    .NUM_HASHES(NUM_HASHES - 1),
    .VECTOR_WIDTH(DATA_WIDTH * BLOCK_SIZE / CBF_WIDTH), //Total block size divided by the width of the CBF
    .NUM_BITS_TO_ADDRESS_VECTOR(SUBSIDIARY_HASH_WIDTH),
    .CBF_WIDTH(CBF_WIDTH)
) checkDecodeBlock (
    .hashes(hashLineOut),
    .block(incrementedBlock),
    .elements(),
    .incrementedBlock()
);
synchronousFifo #(
    .DATA_WIDTH(2 * MAX_KMER_WIDTH),
    .APPARENT_DEPTH(510),
    .FIFO_DEPTH(512),
    .POINTER_SIZE(10)
) testFifo (
    .clk(clk),
    .rstb(rstb),
    .valid(ipValid),
    .read(opValid),
    .data(kmer),
    .fifoFull(testFifoFull),
    .fifoEmpty(testFifoEmpty),
    .out(testKmer)
);
always @(posedge clk) begin
    if (opValid) begin
        $display("Kmer %090b is %0128b at time %d", testKmer, positive, $time);
    end
end
`else
    assign testFifoFull = 1'b0;
`endif

//Generate results for both reads and writes
genvar n;
generate
    for (n = 0; n < NUM_HASHES - 1; n = n + 1) begin:partPositiveGeneration
        if (CBF_WIDTH>1) begin
            assign partPositive[n] = (cbfItems[(n + 1) * CBF_WIDTH - 1 : n * CBF_WIDTH] >= threshold);
        end
        else begin
            assign partPositive[n] = cbfItems[n]; //These statements are equivalent - the bloom filter is portrayed as a special case for ... well no particular reason
        end
    end
endgenerate

assign positive = &partPositive;
assign opValid  = ~readDataFifoEmpty; 

//Incremented block stored into the FIFO
generate
    if (BLOCK_SIZE > 1) begin:generateParallelFifoForData
        synchronousFifoParallelShiftParameterized #(
            .SPLIT_WIDTH(DATA_WIDTH),
            .NUM_SPLITS(BLOCK_SIZE),
            .FIFO_DEPTH(16 * BLOCK_SIZE),
            .APPARENT_DEPTH(12 * BLOCK_SIZE),
            .POINTER_SIZE(5 + BLOCK_BIT_SIZE),
            .SUB_FIFO_POINTER_SIZE(5)
        ) writeDataFifo (
            .clk(clk),
            .rstb(rstb),
            .valid(pnr & ~readDataFifoEmpty & ~writeDataFifoFull),
            .read(wr & controllerWriteReady),
            .data(incrementedBlock),
            .fifoFull(writeDataFifoFull),
            .fifoEmpty(writeDataFifoEmpty),
            .out(wdata)
        );
    end
    else begin:generateSerialFifoForData
        synchronousFifo #(
            .DATA_WIDTH(DATA_WIDTH),
            .FIFO_DEPTH(16),
            .APPARENT_DEPTH(12),
            .POINTER_SIZE(5)
        ) writeDataFifo (
            .clk(clk),
            .rstb(rstb),
            .valid(pnr & ~readDataFifoEmpty & ~writeDataFifoFull),
            .read(wr & controllerWriteReady),
            .data(incrementedBlock),
            .fifoFull(writeDataFifoFull),
            .fifoEmpty(writeDataFifoEmpty),
            .out(wdata)
        );
    end
endgenerate

synchronousFifo #(
    .DATA_WIDTH(ADDR_WIDTH),
    .FIFO_DEPTH(64),
    .APPARENT_DEPTH(62),
    .POINTER_SIZE(7)
) writeAddressFifo (
    .clk(clk),
    .rstb(rstb),
    .valid(pnr & rd & controllerReadReady),
    .read(wr & controllerWriteReady),
    .data(raddr),
    .fifoFull(writeAddressFifoFull),
    .fifoEmpty(writeAddressFifoEmpty),
    .out(waddr)
);

assign wr       = ~(writeAddressFifoEmpty | writeDataFifoEmpty); 
                                                     //We are not ANDing with ready yet - we don't know what sits outside as of now
                                                     //Note to self Use dual rank DDR memory

assign bcbfIdle = inputFifoEmpty & writeAddressFifoEmpty & writeDataFifoEmpty & otherHashEmpty & readFifoEmpty & readDataFifoEmpty & hashEmpty & kmerReverseEmpty;
 
endmodule
