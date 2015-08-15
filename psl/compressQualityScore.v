`timescale 1ns / 1ps
module compressQualityScore #(
    parameter LENGTH = 64
) (
    input [7 : 0] qualityThreshold0,
    input [7 : 0] qualityThreshold1,
    input [7 : 0] qualityThreshold2,
    input [7 : 0] qualityThreshold3,
    input [LENGTH * 8 - 1 : 0] qualityString,
    output [LENGTH * 2 - 1 : 0] quality
);

genvar i;
generate
    for (i = 0; i < LENGTH; i++) begin:qScore
        wire [7 : 0] score = qualityString[8 * (i + 1) - 1 : 8 * i];
        assign quality[2 * (i + 1) - 1 : 2 * i] =
                     (qualityThreshold0 <= score) && (qualityThreshold1 > score) ? 2'b00 :
                     (qualityThreshold1 <= score) && (qualityThreshold2 > score) ? 2'b01 :
                     (qualityThreshold2 <= score) && (qualityThreshold3 > score) ? 2'b10 :
                                                                                   2'b11;
    end
endgenerate

endmodule
