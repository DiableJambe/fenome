`timescale 1ns / 1ps
module synchronousFifoSerialToParallelParameterized #(
    parameter SPLIT_WIDTH = 128,
    parameter NUM_SPLITS = 2,
    parameter FIFO_DEPTH = 1024,
    parameter APPARENT_DEPTH = 800,
    parameter POINTER_SIZE = 11,
    parameter SUB_FIFO_POINTER_SIZE = 10,
    parameter NUM_SPLITS_BIT_WIDTH = 1
)(
    input clk,
    input rstb,
    input [SPLIT_WIDTH - 1 : 0] data,
    input valid,
    input read,
    output fifoEmpty,
    output fifoFull,
    output [NUM_SPLITS * SPLIT_WIDTH - 1 : 0] out
);

///////Internal signals
reg [NUM_SPLITS_BIT_WIDTH - 1 : 0]    daisyChain;
wire [SPLIT_WIDTH - 1 : 0]            partOut[0 : NUM_SPLITS - 1];
wire [NUM_SPLITS - 1 : 0]             fifoEmptyParts;
wire [NUM_SPLITS - 1 : 0]             fifoFullParts;

//Daisy chain to direct the inputs to the correct parallel FIFO
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        daisyChain <= {NUM_SPLITS_BIT_WIDTH{1'b0}};
    end
    else begin
        if (valid)
            if (daisyChain == NUM_SPLITS - 1)
                daisyChain <= {NUM_SPLITS_BIT_WIDTH{1'b0}};
            else
                daisyChain <= daisyChain + 1;
    end
end

assign fifoFull  = fifoFullParts[daisyChain];
assign fifoEmpty = |fifoEmptyParts;

genvar m;
generate
    for (m = 0; m < NUM_SPLITS; m = m + 1) begin:putTogetherOutputs
        assign out[(m + 1) * SPLIT_WIDTH - 1 : m * SPLIT_WIDTH] = partOut[m];
    end
endgenerate

genvar k;
generate
    for (k = 0; k < NUM_SPLITS; k = k + 1) begin:splitFifos
        synchronousFifo #(
            .DATA_WIDTH(SPLIT_WIDTH),
            .FIFO_DEPTH(FIFO_DEPTH/NUM_SPLITS),
            .APPARENT_DEPTH(APPARENT_DEPTH/NUM_SPLITS),
            .POINTER_SIZE(SUB_FIFO_POINTER_SIZE)
        ) splitFifo (
            .clk(clk),
            .rstb(rstb),
            .data(data),
            .valid(valid & (daisyChain == k)),
            .read(read),
            .fifoEmpty(fifoEmptyParts[k]),
            .fifoFull(fifoFullParts[k]),
            .out(partOut[k])
        );
    end
endgenerate

endmodule
