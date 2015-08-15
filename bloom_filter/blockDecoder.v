`timescale 1ps / 1ps
//Accept packed input, send out packed outputs
module blockDecoder #(
    parameter NUM_HASHES = 6,                     //Number of hash functions addressing into the vector
    parameter VECTOR_WIDTH = 1024,                //Number of CBF entries per vector
    parameter NUM_BITS_TO_ADDRESS_VECTOR = 10,    //Number of bits to address each vector
    parameter CBF_WIDTH = 4                       //Width of each CBF entry
) (
    input [NUM_BITS_TO_ADDRESS_VECTOR * NUM_HASHES - 1 : 0] hashes, 
    input [CBF_WIDTH * VECTOR_WIDTH - 1 : 0]                block,
    output [CBF_WIDTH * NUM_HASHES - 1 : 0]                 elements,
    output [CBF_WIDTH * VECTOR_WIDTH - 1 : 0]               incrementedBlock
);

//Internal signal definition
wire [NUM_BITS_TO_ADDRESS_VECTOR - 1 : 0]     hash[0 : NUM_HASHES - 1];
wire [CBF_WIDTH - 1 : 0]                      cbfItems[0 : VECTOR_WIDTH - 1];
wire [NUM_HASHES - 1 : 0]                     hashEqualsValue[0 : VECTOR_WIDTH - 1];
wire [VECTOR_WIDTH - 1 : 0]                   anyHashEqualsValue;

//Does any hash value equal a particular vector index?
genvar i, j;
generate
    for (j = 0; j < VECTOR_WIDTH; j = j + 1) begin:unpackHashEquivalence
        for (i = 0; i < NUM_HASHES; i = i + 1) begin:innerLoop
            assign hashEqualsValue[j][i] = (hash[i] == j);
        end
        assign anyHashEqualsValue[j] = |(hashEqualsValue[j]);
    end
endgenerate

//Incementing individual blocks
genvar m, n;
generate
    for (m = 0; m < VECTOR_WIDTH; m = m + 1) begin:incrementingBlocks
        if (CBF_WIDTH>1) begin
            assign incrementedBlock[(m+1)*CBF_WIDTH-1:m*CBF_WIDTH] = (anyHashEqualsValue[m]==1'b1) && (block[(m+1)*CBF_WIDTH-1:m*CBF_WIDTH] != {CBF_WIDTH{1'b1}}) ? 
                                                 block[(m + 1) * CBF_WIDTH - 1 : m * CBF_WIDTH] + 1 : 
                                                 block[(m + 1) * CBF_WIDTH - 1 : m * CBF_WIDTH];
        end
        else begin
            assign incrementedBlock[m] = block[m] | (anyHashEqualsValue[m] == 1'b1);
        end
    end
endgenerate

//Unpack the hashes and the individual CBF items
genvar k, l;
generate
    for (k = 0; k < VECTOR_WIDTH; k = k + 1) begin:unpackCbfItems
        if (CBF_WIDTH>1) begin
            assign cbfItems[k]    = block[(k + 1) * CBF_WIDTH - 1 : k * CBF_WIDTH];
        end
        else begin
            assign cbfItems[k]    = block[k];
        end
    end

    for (l = 0; l < NUM_HASHES; l = l + 1) begin:unpackIndividualHashes
        assign hash[l]        = hashes[(l + 1) * NUM_BITS_TO_ADDRESS_VECTOR - 1 : l * NUM_BITS_TO_ADDRESS_VECTOR];

        if (CBF_WIDTH > 1) begin
            assign elements[(l + 1) * CBF_WIDTH - 1 : l * CBF_WIDTH] = cbfItems[hash[l]];
        end
        else begin
            assign elements[l] = cbfItems[hash[l]];
        end
    end
endgenerate

endmodule
