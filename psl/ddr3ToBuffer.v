`timescale 1ns / 1ps
module ddr3ToBuffer (
    input clk,
    input rstb,
    input [511:0] avl_rdata,
    input avl_rdata_valid,
    output [2047:0] buffer_data,
    output buffer_data_valid,
    input buffer_ready4_data 
);

wire fifoFull;
wire fifoEmpty;

//Serial to parallel - convert 512 bit bus to a 2048 bit bus
synchronousFifoSerialToParallelParameterized #(
    .SPLIT_WIDTH(512),
    .NUM_SPLITS_BIT_WIDTH(2),
    .NUM_SPLITS(4),
    .FIFO_DEPTH(32),      //8 items per sub fifo. Each sub fifo has pointer size of 4
    .APPARENT_DEPTH(28),
    .POINTER_SIZE(6),
    .SUB_FIFO_POINTER_SIZE(4)
) fifo (
    .clk(clk),
    .rstb(rstb),
    .data(avl_rdata),
    .fifoFull(fifoFull),
    .fifoEmpty(fifoEmpty),
    .out(buffer_data),
    .valid(avl_rdata_valid),
    .read(buffer_data_valid)    //This FIFO has no fifoEmpty checks
);

assign buffer_data_valid = ~fifoEmpty & buffer_ready4_data;

endmodule
