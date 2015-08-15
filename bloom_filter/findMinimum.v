`timescale 1ps / 1ps
module findMinimum #(
    parameter NUM_ITEMS = 7,
    parameter ITEM_WIDTH = 4
) ( 
    input [NUM_ITEMS * ITEM_WIDTH - 1 : 0] items,
    output [ITEM_WIDTH - 1 : 0] minimum
);

wire [ITEM_WIDTH - 1 : 0] minimumAtIndex[0 : NUM_ITEMS - 1];
wire [ITEM_WIDTH - 1 : 0] individualItems[0 : NUM_ITEMS - 1];

genvar m;
generate
    for (m = 0; m < NUM_ITEMS; m = m + 1) begin:extractItems
        assign individualItems[m] = items[(m + 1) * ITEM_WIDTH - 1 : m * ITEM_WIDTH];
    end
endgenerate

genvar k;
generate
    for (k = 1; k < NUM_ITEMS; k = k + 1) begin:minimumFindingLoop
        assign minimumAtIndex[k] = (individualItems[k] < minimumAtIndex[k - 1]) ? individualItems[k] : minimumAtIndex[k - 1];
    end
    assign minimumAtIndex[0] = individualItems[0];
endgenerate

assign minimum = minimumAtIndex[NUM_ITEMS - 1];

endmodule
