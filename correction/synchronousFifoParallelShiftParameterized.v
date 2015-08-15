`timescale 1ps / 1ps
module synchronousFifoParallelShiftParameterized #(
    parameter SPLIT_WIDTH           = 32,
    parameter NUM_SPLITS_BIT_WIDTH  = 3,
    parameter NUM_SPLITS            = 8,
    parameter SUB_FIFO_POINTER_SIZE = 4,
    parameter FIFO_DEPTH            = 64,
    parameter APPARENT_DEPTH        = 48,
    parameter POINTER_SIZE          = 32,
    parameter FLOPOUTPUTS           = 0,           //Can be set to '1' in cases where the interfacing module uses the ~fifoFull signal from another FIFO
    parameter USE_ALTERA_DC_FIFO    = 0
) (
    input clk,
    input rstb,
    input valid,
    input read,
    input [NUM_SPLITS * SPLIT_WIDTH - 1 : 0] data,
    output fifoFull,
    output fifoEmpty,
    output [SPLIT_WIDTH - 1 : 0] out
);

//Internal signal definition
reg [NUM_SPLITS_BIT_WIDTH - 1 : 0] daisyChain;
wire [SPLIT_WIDTH - 1 : 0]         splitData[0 : NUM_SPLITS - 1];
wire [NUM_SPLITS - 1 : 0]          fifoEmptyFifos;
wire [NUM_SPLITS - 1 : 0]          fifoFullFifos;
wire [SPLIT_WIDTH - 1 : 0]         rddata[0 : NUM_SPLITS - 1];
wire                               currentFifoEmpty;
wire                               currentFifoFull;
wire [NUM_SPLITS - 1 : 0]          fifoEmptySOP;
wire [NUM_SPLITS - 1 : 0]          fifoFullSOP;
reg [SPLIT_WIDTH - 1 : 0]           outDataFlopped;
reg                                fifoEmptyFlopped;
wire [SPLIT_WIDTH - 1 : 0]          outComb;

//If Quartus can infer a decoder, it will be the biggest simplifying synthesizer work of all time
//assign currentFifoEmpty = fifoEmptyFifos[daisyChain];
//assign currentFifoFull  = fifoFullFifos[daisyChain];
assign outComb          = rddata[daisyChain]; //A lot of MUXes
assign currentFifoEmpty = |fifoEmptySOP;
assign currentFifoFull  = |fifoFullSOP;
//assign fifoEmpty        = currentFifoEmpty;
assign fifoFull         = |fifoFullFifos;


generate
    if (FLOPOUTPUTS == 1) begin:flopTheOutputs
        always @(posedge clk or negedge rstb) begin
            if (~rstb) begin
                outDataFlopped   <= {SPLIT_WIDTH{1'b0}};
                fifoEmptyFlopped <= 1'b0;
            end
            else begin
                if (read) begin
                    outDataFlopped   <= outComb;
                    fifoEmptyFlopped <= currentFifoEmpty;
                end
            end
        end
        assign out       = outDataFlopped;
        assign fifoEmpty = fifoEmptyFlopped;
    end
    else begin:dontFlopTheOutputs
        assign out       = outComb;
        assign fifoEmpty = currentFifoEmpty;
    end
endgenerate

//Decode FIFO-empty and FIFO-full
genvar a;
generate
    for (a = 0; a < NUM_SPLITS; a = a + 1) begin:fullSOP
        assign fifoEmptySOP[a] = fifoEmptyFifos[a] & (daisyChain == a);
        assign fifoFullSOP[a]  = fifoFullFifos[a] & (daisyChain == a);
    end
endgenerate

//Rotate the daisy-chain for read accesses. Push all the data into all the FIFOs.
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        daisyChain <= 1'b0;
    end
    else begin
        if (read & ~currentFifoEmpty) begin
            if (daisyChain != NUM_SPLITS - 1) begin
                daisyChain <= daisyChain + 1;
            end
            else begin
                daisyChain <= 'b0;
            end
        end
        else if (currentFifoEmpty) begin
            daisyChain <= 'b0;
        end
    end
end

genvar k;
generate
    for (k = 0; k < NUM_SPLITS; k = k + 1) begin:splitDataLoop
        assign splitData[k] = data[(k + 1) * SPLIT_WIDTH - 1 : k * SPLIT_WIDTH];
    end
endgenerate

genvar m;
generate
    for (m = 0; m < NUM_SPLITS; m = m + 1) begin:splitFifos
        synchronousFifo #(
            .DATA_WIDTH(SPLIT_WIDTH),
            .FIFO_DEPTH(FIFO_DEPTH/NUM_SPLITS),
            .APPARENT_DEPTH(APPARENT_DEPTH/NUM_SPLITS),
            .POINTER_SIZE(SUB_FIFO_POINTER_SIZE),
            .USE_ALTERA_DC_FIFO(USE_ALTERA_DC_FIFO)
        ) fifo (
            .clk(clk),
            .rstb(rstb),
            .read(read & (daisyChain == m)),
            .valid(valid),
            .data(splitData[m]),
            .fifoFull(fifoFullFifos[m]),
            .fifoEmpty(fifoEmptyFifos[m]),
            .out(rddata[m])
        );
    end
endgenerate

endmodule
