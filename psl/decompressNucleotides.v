`timescale 1ns / 1ps
module decompressNucleotides #(
    parameter LENGTH = 256
) (
    input [LENGTH * 2 - 1 : 0] read,
    output reg [LENGTH * 8 - 1 : 0] readString
);

parameter A = 65;
parameter C = 67;
parameter G = 71;
parameter T = 84;

genvar i;
generate
    for (i = 0; i < LENGTH; i++) begin:bases
        always @* begin
            case (read[2 * (i + 1) - 1 : 2 * i])
                'b00 : readString[8 * (i + 1) - 1 : 8 * i] <= A;
                'b01 : readString[8 * (i + 1) - 1 : 8 * i] <= C;
                'b10 : readString[8 * (i + 1) - 1 : 8 * i] <= G;
                'b11 : readString[8 * (i + 1) - 1 : 8 * i] <= T;
                default : readString[8 * (i + 1) - 1 : 8 * i] <= A;
            endcase
        end
    end
endgenerate

endmodule
