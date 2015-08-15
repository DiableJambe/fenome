`timescale 1ns / 1ps
module numLowQBases #(
    parameter MAX_KMER_BIT_WIDTH = 6,
    parameter MAX_KMER_WIDTH = (1 << MAX_KMER_BIT_WIDTH)
) (
    input clk,
    input rstb,
    input valid,
    input done,
    input [MAX_KMER_BIT_WIDTH-1:0] kmer_length,
    input [2*MAX_KMER_WIDTH-1:0] quality,
    input [1:0] threshold,
    output reg [MAX_KMER_BIT_WIDTH-1:0] num_low_q_bases,
    output reg valid_score
);

//Log solution
genvar k,j;
generate
    for (k = 0; k < MAX_KMER_BIT_WIDTH; k++) begin:stages
        wire [k:0] lowQSums[0:MAX_KMER_WIDTH/{1'b1,{k{1'b0}}}-1];
        for (j=0; j < MAX_KMER_WIDTH/{1'b1,{k{1'b0}}}; j++) begin:sub_stages
            if (k == 0) begin
                assign lowQSums[j] = (kmer_length > j) ? quality[2*(j+1)-1:2*j] < threshold : 1'b0;
            end
            else begin
                assign lowQSums[j] = stages[k-1].lowQSums[2*j+1] + stages[k-1].lowQSums[2*j];
            end
        end
    end
endgenerate

//flop the outputs
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        num_low_q_bases <= 'b0;
        valid_score <= 'b0;
    end
    else begin
        if (done) begin
            valid_score     <= 'b0;
            num_low_q_bases <= 'b0;
        end
        else begin
            valid_score     <= valid;
            num_low_q_bases <= stages[MAX_KMER_BIT_WIDTH-1].lowQSums[0];
        end 
    end
end

endmodule
