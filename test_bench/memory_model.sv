`timescale 1ns/1ps
module memory_model (
    input clk,
    input [29:0] raddr,
    input [29:0] waddr,
    input [511:0] wdata,
    output reg [511:0] rdata,
    output ready,
    input rvalid,
    input wvalid,
    output reg rddata_valid
);

localparam IDLE = 1;
localparam PROCESS_REQ = 2;
localparam ACK = 3;
localparam DONE = 4;

integer i;
integer delays[0:4];
wire [29:0] waddr_in;
wire [29:0] raddr_in;
wire [511:0] wdata_in;
wire rvalid_in, wvalid_in;
wire read_input_fifo;
integer delay_counter;
integer state;
reg rstb;

initial begin
    rstb <= 1'b0;
    repeat (10) @(posedge clk);
    rstb <= 1'b1;
end

reg [511:0] memory[0:{1'b1,16'b0}-1];

always @(posedge clk) begin
    if (rvalid) begin
        rdata <= memory[raddr[15:0]];
    end
    if (wvalid) begin
        memory[waddr[15:0]] <= wdata;
    end
    rddata_valid <= rvalid;
end

integer l;
initial begin
    for (l = 0; l < {1'b1, 16'b0}; l++) begin
        memory[l] <= 512'b0;
    end
end

assign ready = 1'b1;

/*
synchronousFifo #(
    .FIFO_DEPTH(16),
    .APPARENT_DEPTH(8),
    .POINTER_SIZE(5),
    .DATA_WIDTH(30+30+512+1+1)
) fifo (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(fifoFull),
    .fifoEmpty(fifoEmpty),
    .data({waddr,raddr,wdata,wvalid,rvalid}),
    .out({waddr_in,raddr_in,wdata_in,wvalid_in,rvalid_in}),
    .valid(ready & (rvalid | wvalid)),
    .read(read_input_fifo)
);

assign ready = ~fifoFull;

//assign read_input_fifo = (state == DONE);
assign read_input_fifo = (state == ACK);

initial begin
    delays[0] = 10;
    delays[1] = 99;
    delays[2] = 4;
    delays[3] = 3;
    delays[4] = 29;
end

always @(posedge clk) begin
    if (rstb) begin
        if (state == DONE) begin
            for (i = 0; i < 5; i++) begin
                delays[i] <= delays[(i+1)%5];
            end
        end
    end
end

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        state <= IDLE;
    end
    else begin
        case (state)
            //IDLE : begin
            //    if (delay_counter == delays[0]) begin
            //        state <= PROCESS_REQ;
            //    end
            //end
            //PROCESS_REQ : begin
            //    state <= ACK;
            //end
            //ACK : begin
            //    state <= DONE;
            //end
            //DONE : begin
            //    state <= IDLE;
            //end
            //default : begin
            //    state <= IDLE;
            //end
            IDLE: begin
                if (~fifoEmpty) state <= ACK;
            end
            ACK : begin
                state <= IDLE;
            end
        endcase
    end
end

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        delay_counter <= 'b0;
    end
    else begin
        if (state == IDLE) begin
            if (~fifoEmpty) begin
                delay_counter <= delay_counter + 1;
            end
        end
        else begin
            delay_counter <= 'b0;
        end
    end
end

assign rddata_valid = rvalid_in & (state == ACK);

always @(posedge clk) begin
    //if (state == PROCESS_REQ) begin
    if (state == IDLE) begin
        if (rvalid_in & ~fifoEmpty) begin
            rdata <= memory[raddr_in[15:0]];
        end
        else begin
            rdata <= 512'hx;
        end
        if (wvalid_in & ~fifoEmpty) begin
            memory[waddr_in[15:0]] <= wdata_in;
        end
        if (wvalid_in & rvalid_in & ~fifoEmpty) $display("ERROR!!! Both write and read valids active at the same time ...");
    end
end

wire [31:0] delays0 = delays[0];
wire [31:0] delays1 = delays[1];
wire [31:0] delays2 = delays[2];
wire [31:0] delays3 = delays[3];
wire [31:0] delays4 = delays[4];
*/

endmodule
