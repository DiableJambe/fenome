`timescale 1ns/1ps
module bloom_filter_wrapper #(
    parameter MAX_KMER_BIT_WIDTH = 6,
    parameter MAX_KMER_WIDTH     = {1'b1,{MAX_KMER_BIT_WIDTH{1'b0}}},
    parameter NUM_BITS_NUM_KMERS_PER_DATA = 3,
    parameter NUM_KMERS_PER_DATA = {1'b1,{NUM_BITS_NUM_KMERS_PER_DATA{1'b0}}}
) (
    input clk,
    input rstb,
    input program,
    input [NUM_KMERS_PER_DATA*2*MAX_KMER_WIDTH-1:0] host_data,
    input host_data_valid,
    output ready4_host_data,
    input kmer_valid,
    input [2*MAX_KMER_WIDTH-1:0] kmer,
    input [MAX_KMER_BIT_WIDTH-1:0] kmer_length,
    output ready4_kmer,
    output queryResultValid,
    output queryResult
);

wire [2*MAX_KMER_WIDTH-1:0] kmer_program;
wire [2*MAX_KMER_WIDTH-1:0] kmer_query;
wire program_fifo_full;
wire program_fifo_empty;
wire kmer_fifo_full;
wire kmer_fifo_empty;

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
    .valid(host_data_valid & program),  //Need to cushion, so masking with fifoFull
    .fifoFull(program_fifo_full),
    .fifoEmpty(program_fifo_empty),
    .out(kmer_program),
    .read(ready4_kmer_filter)
);

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
    .ready(ready4_kmer_filter)
);

`ifdef VERIFICATION
bloom_filter test_filter (
    .clk(clk),
    .rstb(rstb),
    .rnw(~program),
    .valid(program ? ~program_fifo_empty : ~kmer_fifo_empty),
    .kmer(program ? kmer_program : kmer_query),
    .kmer_length(kmer_length),
    .ready4Kmer(ready4_kmer_filter),
    .queryResult(queryResult),
    .queryResultValid(queryResultValid)
);
`else
`endif

endmodule
