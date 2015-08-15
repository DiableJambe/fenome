`timescale 1ps / 1ps
module kmerReverseComplement #(
    parameter MAX_KMER_BIT_WIDTH = 6,
    parameter MAX_KMER_WIDTH = {1'b1,{MAX_KMER_BIT_WIDTH{1'b0}}}
) (
    input clk,
    input rstb,
    input kmerValid,
    input ready,
    input [2 * MAX_KMER_WIDTH - 1 : 0] kmer,
    input [MAX_KMER_BIT_WIDTH-1:0] kmerLength,
    output reg [2 * MAX_KMER_WIDTH - 1 : 0] out,
    output empty,
    output opValid
);

wire [1 : 0] nucleotides[0 : MAX_KMER_WIDTH - 1];
wire [1 : 0] complements[0 : MAX_KMER_WIDTH - 1];
wire [1 : 0] reverseComplementArray[0 : MAX_KMER_WIDTH - 1];
wire [2*MAX_KMER_WIDTH-1:0] reverseComplement;
wire [2*MAX_KMER_WIDTH-1:0] kmer_reverse[1:MAX_KMER_WIDTH];
wire [2*MAX_KMER_WIDTH-1:0] kmer_forward[1:MAX_KMER_WIDTH];
reg [2*MAX_KMER_WIDTH-1:0] kmer_forward_stage1;
reg [2*MAX_KMER_WIDTH-1:0] kmer_reverse_stage1;
reg [1:0] valid;

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        valid[0]            <= 1'b0;
        kmer_forward_stage1 <= 128'b0;
        kmer_reverse_stage1 <= 128'b0;
    end
    else begin
        if (ready) begin
            valid[0]            <= kmerValid;
            kmer_forward_stage1 <= kmer_forward[kmerLength];
            kmer_reverse_stage1 <= kmer_reverse[kmerLength];
        end
    end
end

//Shift reverseComplement right by MAX_KMER_WIDTH - kmerLength positions
genvar i, j;
generate
    for (i = 1; i <= MAX_KMER_WIDTH; i=i+1) begin:some_name
        assign kmer_reverse[i] = {{(MAX_KMER_WIDTH-i){2'b0}}, reverseComplement[2*MAX_KMER_WIDTH-1:2*(MAX_KMER_WIDTH-i)]};
        assign kmer_forward[i] = {{(MAX_KMER_WIDTH-i){2'b0}}, kmer[2*i-1:0]};
    end
endgenerate

genvar m;
generate
    for (m = 0; m < MAX_KMER_WIDTH; m = m + 1) begin:nucleotideGenerate
        assign nucleotides[m] = kmer[2 * (m + 1) - 1 : 2 * m];
        assign complements[m] = (nucleotides[m] == 2'b00) ? 2'b11 : //A->T
                                (nucleotides[m] == 2'b01) ? 2'b10 : //C->G
                                (nucleotides[m] == 2'b10) ? 2'b01 : //G->C
                            /*(nucleotide[m] == 2'b11) ?*/ 2'b00 ; //T->A

        assign reverseComplementArray[m]        = complements[MAX_KMER_WIDTH - m - 1];
        assign reverseComplement[2*(m+1)-1:2*m] = reverseComplementArray[m];
    end
endgenerate

//Log reduction of priority encoding
genvar p,q,r;
generate
    for (p=0; p <= MAX_KMER_BIT_WIDTH; p=p+1) begin:lexicalOrder
        wire [1:0] encode_stage[0:MAX_KMER_WIDTH/{1'b1,{p{1'b0}}}-1];
                                                 //encode: 00 is lt; 10,01 is non committal; 11 is greater than

        wire [(MAX_KMER_WIDTH/{1'b1,{p{1'b0}}})*2-1:0] encode_stage_waveform;
                                                 
        if (p==0) begin
            for (r=0; r<MAX_KMER_WIDTH; r=r+1) begin:some_name
                assign encode_stage[r] =(kmerLength > r) ? (
                                             kmer_forward_stage1[2*(r+1)-1:2*r] < kmer_reverse_stage1[2*(r+1)-1:2*r] ?  
                                                 2'b00 :
                                                 kmer_forward_stage1[2*(r+1)-1:2*r] > kmer_reverse_stage1[2*(r+1)-1:2*r] ?
                                                     2'b11 :
                                                     2'b01
                                        ) : 2'b01;
            end
        end
        else begin
            for (q=0; q<MAX_KMER_WIDTH/{1'b1,{p{1'b0}}}; q=q+1) begin:some_name
                assign encode_stage[q] = (lexicalOrder[p-1].encode_stage[2*q+1] == 2'b11) | (lexicalOrder[p-1].encode_stage[2*q+1] == 2'b00) ?
                                               lexicalOrder[p-1].encode_stage[2*q+1] :
                                               lexicalOrder[p-1].encode_stage[2*q];

                assign encode_stage_waveform[2*(q+1)-1:2*q] = encode_stage[q];
            end
        end
    end
endgenerate

//Send out the smaller one - flop for timing
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        out      <= {(2*MAX_KMER_WIDTH){1'b0}};
        valid[1] <= 1'b0;
    end
    else begin
        if (ready) begin
            out      <= |(lexicalOrder[MAX_KMER_BIT_WIDTH].encode_stage[0]) ? kmer_reverse_stage1 : kmer_forward_stage1;
            valid[1] <= valid[0];
        end
    end
end

assign opValid = valid[1] & ready;

assign empty = ~|valid;

`ifndef SYNTHESIS
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_1 = kmer_forward[1];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_2 = kmer_forward[2];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_3 = kmer_forward[3];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_4 = kmer_forward[4];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_5 = kmer_forward[5];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_6 = kmer_forward[6];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_7 = kmer_forward[7];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_8 = kmer_forward[8];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_9 = kmer_forward[9];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_10 = kmer_forward[10];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_11 = kmer_forward[11];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_12 = kmer_forward[12];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_13 = kmer_forward[13];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_14 = kmer_forward[14];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_15 = kmer_forward[15];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_16 = kmer_forward[16];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_17 = kmer_forward[17];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_18 = kmer_forward[18];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_19 = kmer_forward[19];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_20 = kmer_forward[20];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_21 = kmer_forward[21];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_22 = kmer_forward[22];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_23 = kmer_forward[23];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_24 = kmer_forward[24];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_25 = kmer_forward[25];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_26 = kmer_forward[26];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_27 = kmer_forward[27];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_28 = kmer_forward[28];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_29 = kmer_forward[29];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_30 = kmer_forward[30];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_31 = kmer_forward[31];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_32 = kmer_forward[32];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_33 = kmer_forward[33];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_34 = kmer_forward[34];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_35 = kmer_forward[35];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_36 = kmer_forward[36];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_37 = kmer_forward[37];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_38 = kmer_forward[38];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_39 = kmer_forward[39];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_40 = kmer_forward[40];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_41 = kmer_forward[41];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_42 = kmer_forward[42];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_43 = kmer_forward[43];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_44 = kmer_forward[44];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_45 = kmer_forward[45];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_46 = kmer_forward[46];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_47 = kmer_forward[47];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_48 = kmer_forward[48];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_49 = kmer_forward[49];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_50 = kmer_forward[50];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_51 = kmer_forward[51];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_52 = kmer_forward[52];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_53 = kmer_forward[53];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_54 = kmer_forward[54];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_55 = kmer_forward[55];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_56 = kmer_forward[56];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_57 = kmer_forward[57];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_58 = kmer_forward[58];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_59 = kmer_forward[59];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_60 = kmer_forward[60];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_61 = kmer_forward[61];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_62 = kmer_forward[62];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_63 = kmer_forward[63];
wire [2*MAX_KMER_WIDTH-1:0] kmerLength_64 = kmer_forward[64];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_1 = kmer_reverse[1];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_2 = kmer_reverse[2];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_3 = kmer_reverse[3];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_4 = kmer_reverse[4];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_5 = kmer_reverse[5];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_6 = kmer_reverse[6];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_7 = kmer_reverse[7];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_8 = kmer_reverse[8];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_9 = kmer_reverse[9];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_10 = kmer_reverse[10];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_11 = kmer_reverse[11];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_12 = kmer_reverse[12];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_13 = kmer_reverse[13];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_14 = kmer_reverse[14];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_15 = kmer_reverse[15];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_16 = kmer_reverse[16];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_17 = kmer_reverse[17];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_18 = kmer_reverse[18];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_19 = kmer_reverse[19];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_20 = kmer_reverse[20];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_21 = kmer_reverse[21];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_22 = kmer_reverse[22];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_23 = kmer_reverse[23];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_24 = kmer_reverse[24];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_25 = kmer_reverse[25];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_26 = kmer_reverse[26];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_27 = kmer_reverse[27];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_28 = kmer_reverse[28];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_29 = kmer_reverse[29];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_30 = kmer_reverse[30];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_31 = kmer_reverse[31];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_32 = kmer_reverse[32];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_33 = kmer_reverse[33];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_34 = kmer_reverse[34];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_35 = kmer_reverse[35];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_36 = kmer_reverse[36];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_37 = kmer_reverse[37];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_38 = kmer_reverse[38];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_39 = kmer_reverse[39];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_40 = kmer_reverse[40];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_41 = kmer_reverse[41];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_42 = kmer_reverse[42];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_43 = kmer_reverse[43];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_44 = kmer_reverse[44];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_45 = kmer_reverse[45];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_46 = kmer_reverse[46];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_47 = kmer_reverse[47];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_48 = kmer_reverse[48];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_49 = kmer_reverse[49];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_50 = kmer_reverse[50];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_51 = kmer_reverse[51];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_52 = kmer_reverse[52];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_53 = kmer_reverse[53];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_54 = kmer_reverse[54];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_55 = kmer_reverse[55];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_56 = kmer_reverse[56];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_57 = kmer_reverse[57];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_58 = kmer_reverse[58];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_59 = kmer_reverse[59];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_60 = kmer_reverse[60];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_61 = kmer_reverse[61];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_62 = kmer_reverse[62];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_63 = kmer_reverse[63];
wire [2*MAX_KMER_WIDTH-1:0] kmerReverseLength_64 = kmer_reverse[64];
`endif

endmodule
