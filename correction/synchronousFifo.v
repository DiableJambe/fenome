`timescale 1ns/1ps
module synchronousFifo #(
    parameter DATA_WIDTH      = 91,  //The width of the data that the fifo holds
    parameter FIFO_DEPTH      = 16,  //Number of shift-registers in the FIFO
    parameter POINTER_SIZE    = 5,  //The FIFO pointer size (can be obtained from FIFO_DEPTH, but hey, no logarithms!)
    parameter APPARENT_DEPTH  = 12, //The fifo is declared full at this depth
    parameter CHECK_DATA      = 0,
    parameter USE_ALTERA_DC_FIFO = 0
)(
    input clk,                               //Clock
    input rstb,                              //Reset
    input valid,                             //Data input valid
    input read,                              //Read output - when this signal is high, the fifo shifts out data
    input [DATA_WIDTH - 1 : 0] data,         //Input data to be shifted into the FIFO
    output reg fifoFull,                     //Signals that FIFO is full. Goes high when there are a few elements left
    output reg fifoEmpty,                    //Fifo is empty
    output [DATA_WIDTH - 1 : 0] out          //The first in data that is going out
);

generate
if (USE_ALTERA_DC_FIFO==0) begin:myFifo
//Internal signal definitions
reg [DATA_WIDTH - 1 : 0]   fifo [0 : FIFO_DEPTH]; //We have one dummy register field at the end, which is not even reset
reg [POINTER_SIZE - 1 : 0] fifoReadPointer;       //Points to the position of the current data being output
reg [POINTER_SIZE - 1 : 0] fifoWritePointer;      //Points to the position of the current index where write has to happen
reg [DATA_WIDTH - 1 : 0]   dataRegister;
reg conditionHappened;
reg [DATA_WIDTH - 1 : 0]   outReg;
reg [POINTER_SIZE : 0] currentFifoSize;  //A little bigger than pointer size -> must fix many timing issues
wire [FIFO_DEPTH - 1 : 0]  checkPartResult;

//A read waveform
//                    ___     ___     ___     ___     ___     ___     ___     ___     ___     ___
//clk             ___|   |___|   |___|   |___|   |___|   |___|   |___|   |___|   |___|   |___|   |
//                                    _______
//read            ___________________|       |____________________________________________________
//                ___________________________ ____________________________________________________
//fifoReadPointer ___________________________|_________________fifoReadPointer + 1________________  //I know, I shouldn't use the variable name here
//                ___________________________ ____________________________________________________
//out             ___________________________|______________fifo[fifoReadPointer + 1]_____________
//
//
//
wire [POINTER_SIZE - 2 : 0] fifoReadPointerPlus1   = fifoReadPointer[POINTER_SIZE - 2 : 0] + 1;
wire [POINTER_SIZE - 1 : 0] fifoWritePointerMinus1 = fifoWritePointer - 1;

//Fix the FIFO output
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
         outReg <= {DATA_WIDTH{1'b0}};
     end
     else begin
         if (read & ~fifoEmpty) 
            outReg <= fifo[fifoReadPointerPlus1];
         else
            outReg <= fifo[fifoReadPointer[POINTER_SIZE - 2 : 0]];
     end
end

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        dataRegister      <= {DATA_WIDTH{1'b0}};
        conditionHappened <= 1'b0;
    end
    else begin
        dataRegister      <= valid ? data : {DATA_WIDTH{1'b0}};
        conditionHappened <= ((valid & fifoEmpty) | (valid & read & (fifoReadPointer == fifoWritePointerMinus1))) | (conditionHappened & read);
    end
end

assign out = conditionHappened ? dataRegister : outReg;

//The synchronous FIFO code
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
         fifoReadPointer  <= 'b0; //Maybe this should have been made -1 at the start
         fifoWritePointer <= 'b0;
         fifoEmpty <= 1'b1;
     end
     else begin
          if (valid) begin //valid implies a write
              fifo[fifoWritePointer[POINTER_SIZE - 2 : 0]] <= data;
              fifoWritePointer       <= fifoWritePointer + 1;
          end
          if (read) begin
              if (~fifoEmpty) begin
                  fifoReadPointer    <= fifoReadPointer + 1;
              end
          end
          if (valid & ~(read & ~fifoEmpty)) begin
              fifoEmpty <= 1'b0;
          end
          else if ((read  & ~fifoEmpty) & ~valid) begin
              if (fifoReadPointer == fifoWritePointerMinus1) begin
                  fifoEmpty <= 1'b1;
              end
          end
          else if (read & valid) begin //Even if fifo is empty, this will not let the read happen, only the write, so FIFO becomes un-empty
              fifoEmpty <= 1'b0;
          end
     end
end

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        currentFifoSize <= 'b0;
        fifoFull <= 1'b0;
    end
    else begin
        if ((read & ~fifoEmpty) & ~valid) begin
            currentFifoSize <= currentFifoSize - 1;
        end
        if (valid & ~(read & ~fifoEmpty)) begin
            currentFifoSize <= currentFifoSize + 1;
        end
        if (currentFifoSize >= APPARENT_DEPTH) fifoFull <= 1'b1; 
        else fifoFull <= 1'b0;
    end
end
end
else begin:alteraFifo
wire [POINTER_SIZE-2:0] num_words_used;

scfifo	scfifo_component (
    .clock (clk),
    .wrreq (valid),
    .aclr (~rstb),
    .data (data),
    .rdreq (read),
    .usedw (num_words_used),
    .empty (fifoEmpty),
    .full (),
    .q (out),
    .almost_empty (),
    .almost_full (),
    .sclr (1'b0));
defparam
    scfifo_component.add_ram_output_register = "ON",
    scfifo_component.intended_device_family = "Stratix V",
    scfifo_component.lpm_numwords = FIFO_DEPTH,//256,
    scfifo_component.lpm_showahead = "ON",
    scfifo_component.lpm_type = "scfifo",
    scfifo_component.lpm_width = DATA_WIDTH,//4,                     //data width
    scfifo_component.lpm_widthu = POINTER_SIZE-1,//8,                    //log(fifo_depth)
    scfifo_component.overflow_checking = "OFF",
    scfifo_component.underflow_checking = "ON",
    scfifo_component.use_eab = "ON";

assign fifoFull = (num_words_used >= APPARENT_DEPTH);
end
endgenerate

endmodule
