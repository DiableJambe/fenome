`timescale 1ns / 1ps
module compressNucleotides #(
    parameter LENGTH = 64
) (
    input [LENGTH * 8 - 1 : 0] readString,
    output reg [LENGTH * 2 - 1 : 0] read
);

parameter A = 65;
parameter C = 67;
parameter G = 71;
parameter T = 84;

genvar i;
generate
    for (i = 0; i < LENGTH; i++) begin:bases
        always @* begin
            case (readString[8 * (i + 1) - 1 : 8 * i])
                A : read[2 * (i + 1) - 1 : 2 * i] <= 2'b00;
                C : read[2 * (i + 1) - 1 : 2 * i] <= 2'b01;
                G : read[2 * (i + 1) - 1 : 2 * i] <= 2'b10;
                T : read[2 * (i + 1) - 1 : 2 * i] <= 2'b11;
                default: read[2 * (i + 1) - 1 : 2 * i] <= 2'b00;
            endcase
        end
    end
endgenerate

endmodule
