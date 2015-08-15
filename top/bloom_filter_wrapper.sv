`timescale 1ns/1ps
module bloom_filter_wrapper #(
    parameter MAX_KMER_BIT_WIDTH = 6,
    parameter MAX_KMER_WIDTH     = {1'b1,{MAX_KMER_BIT_WIDTH{1'b0}}},
    parameter NUM_BITS_NUM_KMERS_PER_DATA = 3,
    parameter NUM_KMERS_PER_DATA = {1'b1,{NUM_BITS_NUM_KMERS_PER_DATA{1'b0}}}
) (
    input clk,
    input rstb,
    input Program,
    input [NUM_KMERS_PER_DATA*2*MAX_KMER_WIDTH-1:0] host_data,
    input host_data_valid,
    output ready4_host_data,
    input kmer_valid,
    input [2*MAX_KMER_WIDTH-1:0] kmer,
    input [MAX_KMER_BIT_WIDTH-1:0] kmer_length,
    output ready4Kmer,
    output queryResultValid,
    output queryResult,
    output idle,
    output [511:0] avl_wdata,
    input [511:0] avl_rdata,
    input avl_rdata_valid,
    input avl_ready,
    output wvalid,
    output rvalid,
    output [29:0] raddr,
    output [29:0] waddr
);

wire [2*MAX_KMER_WIDTH-1:0] kmer_program;
wire [2*MAX_KMER_WIDTH-1:0] kmer_query;
wire program_fifo_full;
wire program_fifo_empty;
wire kmer_fifo_full;
wire kmer_fifo_empty;
wire bloom_filter_idle;
wire bloom_filter_ready;

assign idle = program_fifo_empty & kmer_fifo_empty & bloom_filter_idle;

//Convert host data format to k-mer format
synchronousFifoParallelShiftParameterized #(
    .SPLIT_WIDTH(2*MAX_KMER_WIDTH),
    .NUM_SPLITS_BIT_WIDTH(NUM_BITS_NUM_KMERS_PER_DATA),
    .NUM_SPLITS(NUM_KMERS_PER_DATA),
    .SUB_FIFO_POINTER_SIZE(4),         //SubFIFO size is 8
    .FIFO_DEPTH(8*NUM_KMERS_PER_DATA),
    .APPARENT_DEPTH(8*(NUM_KMERS_PER_DATA-2))
) programFifo (
    .clk(clk),
    .rstb(rstb),
    .data(host_data),
    .valid(host_data_valid & Program),  //Need to cushion, so masking with fifoFull
    .fifoFull(program_fifo_full),
    .fifoEmpty(program_fifo_empty),
    .out(kmer_program),
    .read(bloom_filter_ready)
);

//k-mer FIFO for index finding and correction
synchronousFifo #(
    .DATA_WIDTH(2*MAX_KMER_WIDTH),
    .FIFO_DEPTH(16),
    .APPARENT_DEPTH(12),
    .POINTER_SIZE(5)
) kmerFifo (
    .clk(clk),
    .rstb(rstb),
    .data(kmer),
    .valid(kmer_valid & ~kmer_fifo_full), //No cushioning here
    .fifoFull(kmer_fifo_full),
    .fifoEmpty(kmer_fifo_empty),
    .out(kmer_query),
    .read(bloom_filter_ready)
);

bcbf #(
    .HASH_WIDTH(30), 
    .SUBSIDIARY_HASH_WIDTH(9),
    .BLOCK_SIZE(1),                                             //Number of data inputs that result in a block of data from memory
    .BLOCK_BIT_SIZE(0),
    .NUM_HASHES(7),
    .DATA_WIDTH(512),
    .CBF_WIDTH(1),
    .MAX_KMER_BIT_WIDTH(MAX_KMER_BIT_WIDTH),
    .MAX_KMER_WIDTH(MAX_KMER_WIDTH)
) bloom_filter (
    .clk(clk),                  
    .rstb(rstb),
    .ipValid((Program ? ~program_fifo_empty : ~kmer_fifo_empty) & bloom_filter_ready),              
    .pnr(Program),                  
    .kmer(Program ? kmer_program : kmer_query),                 
    .rdata(avl_rdata),                
    .controllerReadReady(avl_ready),  
    .controllerWriteReady(avl_ready), 
    .controllerDataValid(avl_rdata_valid),  
    .bcbfIdle(bloom_filter_idle),             
    .threshold(1'b0),            
    .kmerLength(kmer_length),
    .ready(bloom_filter_ready),                
    .opValid(queryResultValid),              
    .raddr(raddr),                
    .waddr(waddr),                
    .wdata(avl_wdata),                
    .rd(rvalid),                   
    .bcbfReady4Data(bcbfReady4Data),             //Signals that the BCBF is ready to accept data from controller ... this is to guard against spillage 
                                                                               //... but spillage cannot really happen
    .wr(wvalid),                   
    .histogram(histogram),
    .positive(queryResult)        
);

assign ready4Kmer = ~kmer_fifo_full;
assign ready4_host_data = ~program_fifo_full;

endmodule
