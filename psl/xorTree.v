`timescale 1ns / 1ps
module xorTree #(
    parameter BIT_WIDTH = 6,
    parameter WIDTH = {1'b1, {BIT_WIDTH{1'b0}}}
) (
    input [WIDTH - 1 : 0] signal,
    output par 
);

genvar i, j;
generate
    for (i = 0; i <= BIT_WIDTH; i++) begin:xorTree
        wire [WIDTH / {1'b1, {i{1'b0}}} - 1 : 0] partialParity;
        for (j = 0; j < WIDTH / {1'b1, {i{1'b0}}}; j++) begin:some_name
            if (i == 0) begin
                assign partialParity[j] = signal[j];
            end
            else begin
                assign partialParity[j] = xorTree[i - 1].partialParity[2 * (j + 1)] ^ xorTree[i - 1].partialParity[2 * j];
            end
        end
    end
endgenerate

assign par = xorTree[BIT_WIDTH].partialParity[0];

endmodule
