`timescale 1ns / 1ps

`define little_to_big_endian512(data) {data[7:0], data[15:8], data[23:16], data[31:24], data[39:32], data[47:40], data[55:48], data[63:56], data[71:64], data[79:72], data[87:80], data[95:88], data[103:96], data[111:104], data[119:112], data[127:120], data[135:128], data[143:136], data[151:144], data[159:152], data[167:160], data[175:168], data[183:176], data[191:184], data[199:192], data[207:200], data[215:208], data[223:216], data[231:224], data[239:232], data[247:240], data[255:248], data[263:256], data[271:264], data[279:272], data[287:280], data[295:288], data[303:296], data[311:304], data[319:312], data[327:320], data[335:328], data[343:336], data[351:344], data[359:352], data[367:360], data[375:368], data[383:376], data[391:384], data[399:392], data[407:400], data[415:408], data[423:416], data[431:424], data[439:432], data[447:440], data[455:448], data[463:456], data[471:464], data[479:472], data[487:480], data[495:488], data[503:496], data[511:504]}

`define big_to_little_endian512(data) `little_to_big_endian512(data)

module pslBuffer #(
    parameter CORRECTION    = 'b010,
    parameter SOLID_ISLANDS = 'b001,
    parameter PROGRAM       = 'b000,
    parameter DDR3_INIT     = 'b100,
    parameter DDR3_READ     = 'b101,
    parameter DDR3_WRITE    = 'b110
) (
//Interface with PSL
    input clk,
    input rstb,
    input rvalid,
    input [7:0] rtag,
    input rtagpar,
    input [5:0] rad,
    output [3:0] rlat,
    output reg [511:0] rdata,
    output [7:0] rpar,
    input wvalid,
    input [7:0] wtag,
    input wtagpar,
    input [5:0] wad,
    input [511:0] wdata,
    input [7:0] wpar,

//Interface with other stuff
    output [511 : 0] output_lo,          //Read
    output [511 : 0] output_hi,          //Quality scores in Correction mode, a second read otherwise
    output reg [7:0] read_length_lo,     //For correction mode, only this matters
    output reg [7:0] read_length_hi,     //For obtaining solid islands list, this also matters
    output reg [7:0] start_position,     //Start position in correction mode
    output reg [7:0] end_position,       //End position in correction mode
    output output_valid,                 //The outputs are valid
    input ready,                         //Accepting the current output
    input [2047 : 0] data,               //Could be a corrected candidate or a list of indices (64 integers, 32 indices)
    input data_valid,                    //The data bus is valid
    input [5:0] num_items_per_data,      //The number of candidates per read for example - basically number of "items" per data
    input num_items_per_data_valid,      //Valid signal for number of items
    output read_data,                    //Accepting the current contents on the data bus
    input psl_read_state,                //State of PSL command
    input psl_idle_state,                //State of PSL command
    input [2:0] mode,                    //Mode of the AFU
    output [5:0] num_items_to_cmd,       //This goes to the PSL Command
    input write_cmd_issued,              //write_cmd has been issued by pslCommand
    output wbuffer_item_available,       //Item available in write buffer
    input [7:0] free_location,           //The write buffer location may be freed
    input free_signal,                   //The write buffer location free signal
    input [7:0] qualityThreshold0,       //Quality Threshold from MMIO
    input [7:0] qualityThreshold1,       //Quality Threshold from MMIO
    input [7:0] qualityThreshold2,       //Quality Threshold from MMIO
    input [7:0] qualityThreshold3,       //Quality Threshold from MMIO
    output input_buffer_empty,           //Signals the PSL command interface that the input buffer is empty and has been read out
    input [9:0] iteration_limit          //The number of buffer items expected to be read out in this iteration
);

localparam TRANSFER = 'h1;
localparam CHECK    = 'h2;

//Internal registers and wires
reg ready_delayed;
reg write_buffer_location_occupied[0 : 511];
reg write_buffer_read_del;
reg [8:0] read_addr_del;
reg lane_valid;
reg [9:0] read_buffer_rdptr; //Read pointer for keeping track of reads from the read buffer by functional units
reg [511 : 0] read_buffer_data;
reg [1:0] output_valid_pls;
reg [9:0] write_buffer_wptr;
reg [1023:0] read_lane;
reg [511:0] read_buffer[0:256 * 2 - 1]; 
reg [511:0] write_buffer[0 : 511];
reg [9:0] read_buffer_rdptr_stage2;
wire candidateShiftFull;
wire candidateShiftEmpty;
wire load_into_write_buffer;
wire candidateShiftValid;
wire candidateShiftRead;
wire candidateNumStation0Full;
wire candidateNumStation0Empty;
wire candidateNumStation1Full;
wire candidateNumStation1Empty;
wire [127 : 0] read_buffer_compressed_read;
wire [127 : 0] read_buffer_compressed_quality;
wire [256 * 8 - 1 : 0] candidate;
wire [511 : 0] candidate_buffered;
wire [5:0] num_candidates;
wire [5:0] num_candidates_station0_out;
wire [5:0] num_candidates_station1_in;
wire [11:0] num_candidates_station1_out;
wire [5:0] num_candidates_station0_in;
reg [1:0] transferToWbuffer_state;
reg free_signal_del;
reg [7:0] free_location_del;

//For timing purposes ...
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        free_signal_del <= 1'b0;
        free_location_del <= 8'b0;
    end
    else begin
        free_signal_del <= free_signal;
	free_location_del <= free_location;
    end
end

//Read buffer
always @(posedge clk) begin
    if (wvalid) begin //One port of the read buffer
        read_buffer[{wtag, wad[0]}] <= `big_to_little_endian512(wdata);
    end
end

//Read buffer read pointer
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        read_buffer_rdptr        <= 10'b0;
        read_buffer_rdptr_stage2 <= 10'b0;
    end
    else begin
        if (~psl_read_state & (read_buffer_rdptr < iteration_limit) & ~psl_idle_state) begin
                                          //Is this that much of a performance issue - I am reading all data first before sending anything out?
            if (ready) begin
                read_buffer_rdptr        <= read_buffer_rdptr + 1;
                read_buffer_data         <= read_buffer[read_buffer_rdptr[8:0]]; //Anand - 8:0 is not really necessary because its reset to 0 in the end
                read_buffer_rdptr_stage2 <= read_buffer_rdptr;
            end
        end
        else begin
            //if (psl_idle_state | (read_buffer_rdptr == 512)) begin
                //if (psl_read_state | psl_idle_state) begin
                if (psl_read_state | psl_idle_state) begin
                    read_buffer_rdptr <= 10'b0;
                end
                //end
            //end
            //read_buffer_rdptr_stage2 <= psl_idle_state ? 10'b0 : read_buffer_rdptr;
            read_buffer_rdptr_stage2 <= psl_idle_state ? 10'b0 : read_buffer_rdptr;
        end
    end
end

assign input_buffer_empty = read_buffer_rdptr == iteration_limit;

////////////////////////////////////////////////////////////Output Valid Control Signal////////////////////////////////////////////////////////////
//                   ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___
//clk            ___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \
//                   _______________________________________________________________                         ____________________________________
//ready          ___/                                                               \_______________________/
//               ___________ _______ _______ _______ _______ _______ _______ _______ _______________________________ _______ _______ _______
//RdPointer      _____0_____|___1___|___2___|___3___|___4___|___5___|___6___|___7___|_______________8_______________|___9___|__10___|__11___|               
//               ___________________ _______ _______ _______ _______ _______ _______ _______________________________ _______ _______ _______
//ReadBufData    _________0_________|___1___|___2___|___3___|___4___|___5___|___6___|_______________7_______________|___8___|___9___|__10___|
//               ___________________ _______ _______ _______ _______ _______ _______ _______________________________ _______ _______ _______
//Rdptr_stg2     _________0_________|___1___|___2___|___3___|___4___|___5___|___6___|_______________7_______________|___8___|___9___|__10___|
//               ___________________________ _______ _______ _______ _______ _______ _______________________________________ _______ _______
//read_lane      _____________0_____________|___1___|___2___|___3___|___4___|___5___|_______________6_______________|___7___|___8___|___9___|
//                                                                                                                   _______
//output_valid   ___________________________________________________________________________________________________|       |________________    
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////Output Valid Control Signal////////////////////////////////////////////////////////////
//                   ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___     ___
//clk            ___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \
//                   _______________________________________________________                         ____________________________________
//ready          ___/                                                       \_______________________/
//               ___________ _______ _______ _______ _______ _______ _______ _______________________________ _______ _______ _______
//RdPointer      _____0_____|___1___|___2___|___3___|___4___|___5___|___6___|________________7______________|___8___|___9___|__10___|               
//               ___________________ _______ _______ _______ _______ _______ _______________________________ _______ _______ _______
//ReadBufData    _________0_________|___1___|___2___|___3___|___4___|___5___|________________6______________|___7___|___8___|___9___|
//               ___________________ _______ _______ _______ _______ _______ _______________________________ _______ _______ _______
//Rdptr_stg2     _________0_________|___1___|___2___|___3___|___4___|___5___|________________6______________|___7___|___8___|___9___|
//               ___________________________ _______ _______ _______ _______ _______________________________ _______ _______ _______
//read_lane      _____x_____|___0___|___0___|___1___|___2___|___3___|___4___|________________5______________|___6___|___7___|___8___|
//                                                                                                                   _______
//output_valid   ___________________________________________________________________________________________________|       |________________    
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//Compress bases and quality scores
compressNucleotides #(
    .LENGTH(64)
) baseCompress (
    .readString(read_buffer_data),
    .read(read_buffer_compressed_read)
);

//Compress bases and quality scores
compressQualityScore #(
    .LENGTH(64)
) qScoreCompress (
    .qualityString(read_buffer_data),
    .quality(read_buffer_compressed_quality),
    .qualityThreshold0(qualityThreshold0),
    .qualityThreshold1(qualityThreshold1),
    .qualityThreshold2(qualityThreshold2),
    .qualityThreshold3(qualityThreshold3)
);

//Decode based on mode
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        read_lane      <= 4096'b0;
        lane_valid     <= 1'b0;
        read_length_hi <= 'b0;
        read_length_lo <= 'b0;
        start_position <= 'b0;
        end_position   <= 'b0;
    end
    else begin
        if (lane_valid == 1) begin
            lane_valid <= 1'b0;
        end
        else begin
            if (ready & read_buffer_rdptr_stage2[2:0] == 'h7) begin
                lane_valid <= 1'b1;
            end
        end
        if (ready) begin
            case (read_buffer_rdptr_stage2[2:0])
                'h0 : read_lane[128 * (0 + 1) - 1 : 128 * 0] <= read_buffer_compressed_read;
                'h1 : read_lane[128 * (1 + 1) - 1 : 128 * 1] <= read_buffer_compressed_read;
                'h2 : read_lane[128 * (2 + 1) - 1 : 128 * 2] <= read_buffer_compressed_read;
                'h3 : begin
                    read_lane[128 * (3 + 1) - 1 : 128 * 3] <= read_buffer_compressed_read;
                    read_length_lo <= read_buffer_data[511:504];
                    start_position <= read_buffer_data[503:496];
                    end_position   <= read_buffer_data[495:488];
                 end
                'h4 : read_lane[128 * (4 + 1) - 1 : 128 * 4] <= (mode == CORRECTION) ? read_buffer_compressed_quality : read_buffer_compressed_read;
                'h5 : read_lane[128 * (5 + 1) - 1 : 128 * 5] <= (mode == CORRECTION) ? read_buffer_compressed_quality : read_buffer_compressed_read;
                'h6 : read_lane[128 * (6 + 1) - 1 : 128 * 6] <= (mode == CORRECTION) ? read_buffer_compressed_quality : read_buffer_compressed_read;
                'h7 : begin
                     read_lane[128 * (7 + 1) - 1 : 128 * 7] <= (mode == CORRECTION) ? read_buffer_compressed_quality : read_buffer_compressed_read;
                     read_length_hi <= read_buffer_data[511:504];
                end
            endcase
        end
    end
end

//Organization of data - 256 bytes of data
//<read_length:8bits>,<start_position:8bits>,<end_position:8bits><read:253bytes>
//<quality_score>

//Drive outputs
assign output_valid = lane_valid;
assign output_hi    = (mode != PROGRAM) ? {6'b0, read_lane[1017:512]} : read_lane[1023:512];
assign output_lo    = (mode != PROGRAM) ? {6'b0, read_lane[505:0]} : read_lane[511:0];       

//Occupied flag for each location in the write buffer
genvar k;
generate
    for (k = 0; k < 256; k = k+1) begin:occupied_status
        always @(posedge clk or negedge rstb) begin
            if (~rstb) begin
                write_buffer_location_occupied[2 * k]     <= 1'b0;
                write_buffer_location_occupied[2 * k + 1] <= 1'b0;
            end
            else begin
                if (free_signal_del && (free_location_del == k)) begin
                    write_buffer_location_occupied[2 * k]     <= 1'b0;
                    write_buffer_location_occupied[2 * k + 1] <= 1'b0;
                end
                else begin
                    if (load_into_write_buffer) begin
                        if (write_buffer_wptr[8:0] == 2 * k) begin
                            write_buffer_location_occupied[2 * k]     <= 1'b1;
                        end
                        if (write_buffer_wptr[8:0] == 2 * k + 1) begin
                            write_buffer_location_occupied[2 * k + 1] <= 1'b1;
                        end
                    end
                end
            end
        end
    end
endgenerate

//Write into write-buffer
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        write_buffer_wptr              <= 10'b0;
        write_buffer_read_del          <= 1'b0;
        read_addr_del                  <= 9'b0;
    end
    else begin
        if (load_into_write_buffer) begin
            write_buffer[write_buffer_wptr[8:0]] <= `little_to_big_endian512(candidate_buffered);
            write_buffer_wptr                    <= write_buffer_wptr + 1;
        end
        write_buffer_read_del <= rvalid;
        read_addr_del         <= {rtag, rad[0]};
    end
end

//assign load_into_write_buffer = ~write_buffer_location_occupied[write_buffer_wptr[8:0]] & ~candidateShiftEmpty & ~candidateNumStation1Full & ~candidateNumStation0Empty;
//               //Don't worry about half the data being taken

assign load_into_write_buffer = (transferToWbuffer_state == TRANSFER);

//State machine for checking and transferring items to wbuffer - done in two steps because of timing
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        transferToWbuffer_state <= CHECK;
    end
    else begin
        case (transferToWbuffer_state)
            CHECK: begin
                if (~candidateShiftEmpty & ~candidateNumStation1Full & ~candidateNumStation0Empty) begin
                    if (~write_buffer_location_occupied[write_buffer_wptr[8:0]]) begin
                        transferToWbuffer_state <= TRANSFER;
                    end
                end
            end
            TRANSFER : begin
                transferToWbuffer_state <= CHECK;
            end
            default : begin
                transferToWbuffer_state <= CHECK;
            end
        endcase
    end
end

////### Waveform for reading from write-buffer and writing into the same location
//                   ___     ___     ___     ___     ___     ___     ___     ___
//clk            ___|   |___|   |___|   |___|   |___|   |___|   |___|   |___|   |
//                           _______
//rvalid         ___________|       |____________________________________________
//                           _______
//addr           ______x____|_______|____________________x_______________________
//                                   _______
//data           _________x_________|_______|______________x_____________________
//                                   ____________________________________________
//location free  ___________________|       
//                                   _______
//load_into_wbuf ___________________|       |____________________________________
//                                          |<- writes will be attempted starting from this clock edge

//Read from write-buffer
always @(posedge clk) begin
    if (write_buffer_read_del) begin
        rdata <= write_buffer[read_addr_del];
    end
end

//Read data parity
//xorTree#(.BIT_WIDTH(9)) rdata_parity (.signal(rdata), .par(rpar));
assign rpar = 'b0;

//Take in candidates of width (256 * 8 =) 2048 and convert to format applicable for the write_buffer (512 bits wide)
synchronousFifoParallelShiftParameterized #(
    .SPLIT_WIDTH(512),
    .NUM_SPLITS_BIT_WIDTH(2),
    .NUM_SPLITS(4),
    .SUB_FIFO_POINTER_SIZE(4), //SubFIFO size is 8
    .FIFO_DEPTH(32),           //Four splits, that makes it 32 overall
    .APPARENT_DEPTH(24),
    .POINTER_SIZE(6)
) candidateShift (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(candidateShiftFull),
    .fifoEmpty(candidateShiftEmpty),
    .valid(candidateShiftValid),
    .data((mode == CORRECTION) ? {2'b0, num_items_per_data, candidate[2048-8-1:0]} : data), //Fix the number of candidates into the MSB
    .read(candidateShiftRead),
    .out(candidate_buffered)
);

assign candidateShiftValid    = (mode == CORRECTION) ? (data_valid /*& read_data*/ & num_items_per_data_valid) : data_valid /*& read_data*/;
                                                                                              //This will cushion data from now - cushioning needed because of intermediate flop
assign candidateShiftRead     = load_into_write_buffer; 

//Each candidate is associated with num_candidates. Conver this to an association with each 512-bit write_buffer item - this corresponds to the candidateShift FIFO above
synchronousFifoParallelShiftParameterized #(
    .SPLIT_WIDTH(6),
    .NUM_SPLITS_BIT_WIDTH(2),
    .NUM_SPLITS(4),
    .SUB_FIFO_POINTER_SIZE(4), //SubFIFO size is 8
    .FIFO_DEPTH(32),           //Four splits, that makes it 32 overall
    .APPARENT_DEPTH(24),
    .POINTER_SIZE(6)
) candidateNumStation0 (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(candidateNumStation0Full),
    .fifoEmpty(candidateNumStation0Empty),
    .valid(candidateNumStation0Valid),
    .read(candidateNumStation0Read),
    .data({num_candidates_station0_in,num_candidates_station0_in,num_candidates_station0_in,num_candidates_station0_in}),
    .out(num_candidates_station0_out)
);

assign candidateNumStation0Valid  = candidateShiftValid;
assign candidateNumStation0Read   = candidateShiftRead;
assign num_candidates             = num_candidates_station0_out;
assign num_items_to_cmd           = num_candidates_station1_out[5:0];
assign num_candidates_station0_in = (mode == CORRECTION) ? num_items_per_data : 1;

//This corresponds to the write_buffer. The moment an item is pushed into write_buffer, push an item from candidateNumStation0 into here
synchronousFifoSerialToParallelParameterized #(
    .SPLIT_WIDTH(6),
    .NUM_SPLITS(2),
    .FIFO_DEPTH(512),
    .APPARENT_DEPTH(500),
    .POINTER_SIZE(10),
    .SUB_FIFO_POINTER_SIZE(9),
    .NUM_SPLITS_BIT_WIDTH(1)
) candidateNumStation1 (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(candidateNumStation1Full),
    .fifoEmpty(candidateNumStation1Empty),
    .valid(candidateNumStation1Valid),
    .read(candidateNumStation1Read),
    .data(num_candidates_station1_in),
    .out(num_candidates_station1_out)
);

assign candidateNumStation1Valid  = candidateNumStation0Read;
//assign read_data                  = ~candidateShiftFull & ~candidateNumStation0Full & (mode == CORRECTION ? data_valid & num_items_per_data_valid : 1'b1);
assign read_data                  = ~candidateShiftFull & ~candidateNumStation0Full; //It's gated outside with read_data whatever is the mode (except DDR_READ mode)
assign candidateNumStation1Read   = write_cmd_issued;
assign num_candidates_station1_in = num_candidates_station0_out;
assign wbuffer_item_available     = ~candidateNumStation1Empty;

//The corrected reads are in 4 alphabets. Convert them to Ascii.
decompressNucleotides #(
    .LENGTH(256)
) expandBases (
    .read(data[511:0]),
    .readString(candidate)
);

assign rlat = 1;

`ifndef SYNTHESIS
wire [511:0] occupied;

genvar o;
generate
for (o = 0; o < 512; o++) begin:verf
    assign occupied[o] =  write_buffer_location_occupied[o];
end
endgenerate

wire [511:0] write_buffer_0x0 = write_buffer[0];
wire [511:0] write_buffer_0x1 = write_buffer[1];
wire [511:0] write_buffer_0x2 = write_buffer[2];
wire [511:0] write_buffer_0x3 = write_buffer[3];
wire [511:0] write_buffer_0x4 = write_buffer[4];
wire [511:0] write_buffer_0x5 = write_buffer[5];
wire [511:0] write_buffer_0x6 = write_buffer[6];
wire [511:0] write_buffer_0x7 = write_buffer[7];
wire [511:0] write_buffer_0x8 = write_buffer[8];
wire [511:0] write_buffer_0x9 = write_buffer[9];
wire [511:0] write_buffer_0xa = write_buffer[10];
wire [511:0] write_buffer_0xb = write_buffer[11];
wire [511:0] write_buffer_0xc = write_buffer[12];
wire [511:0] write_buffer_0xd = write_buffer[13];
wire [511:0] write_buffer_0xe = write_buffer[14];
wire [511:0] write_buffer_0xf = write_buffer[15];
wire [511:0] write_buffer_0x10 = write_buffer[16];
wire [511:0] write_buffer_0x11 = write_buffer[17];
wire [511:0] write_buffer_0x12 = write_buffer[18];
wire [511:0] write_buffer_0x13 = write_buffer[19];
wire [511:0] write_buffer_0x14 = write_buffer[20];
wire [511:0] write_buffer_0x15 = write_buffer[21];
wire [511:0] write_buffer_0x16 = write_buffer[22];
wire [511:0] write_buffer_0x17 = write_buffer[23];
wire [511:0] write_buffer_0x18 = write_buffer[24];
wire [511:0] write_buffer_0x19 = write_buffer[25];
wire [511:0] write_buffer_0x1a = write_buffer[26];
wire [511:0] write_buffer_0x1b = write_buffer[27];
wire [511:0] write_buffer_0x1c = write_buffer[28];
wire [511:0] write_buffer_0x1d = write_buffer[29];
wire [511:0] write_buffer_0x1e = write_buffer[30];
wire [511:0] write_buffer_0x1f = write_buffer[31];
wire [511:0] write_buffer_0x20 = write_buffer[32];
wire [511:0] write_buffer_0x21 = write_buffer[33];
wire [511:0] write_buffer_0x22 = write_buffer[34];
wire [511:0] write_buffer_0x23 = write_buffer[35];
wire [511:0] write_buffer_0x24 = write_buffer[36];
wire [511:0] write_buffer_0x25 = write_buffer[37];
wire [511:0] write_buffer_0x26 = write_buffer[38];
wire [511:0] write_buffer_0x27 = write_buffer[39];
wire [511:0] write_buffer_0x28 = write_buffer[40];
wire [511:0] write_buffer_0x29 = write_buffer[41];
wire [511:0] write_buffer_0x2a = write_buffer[42];
wire [511:0] write_buffer_0x2b = write_buffer[43];
wire [511:0] write_buffer_0x2c = write_buffer[44];
wire [511:0] write_buffer_0x2d = write_buffer[45];
wire [511:0] write_buffer_0x2e = write_buffer[46];
wire [511:0] write_buffer_0x2f = write_buffer[47];
wire [511:0] write_buffer_0x30 = write_buffer[48];
wire [511:0] write_buffer_0x31 = write_buffer[49];
wire [511:0] write_buffer_0x32 = write_buffer[50];
wire [511:0] write_buffer_0x33 = write_buffer[51];
wire [511:0] write_buffer_0x34 = write_buffer[52];
wire [511:0] write_buffer_0x35 = write_buffer[53];
wire [511:0] write_buffer_0x36 = write_buffer[54];
wire [511:0] write_buffer_0x37 = write_buffer[55];
wire [511:0] write_buffer_0x38 = write_buffer[56];
wire [511:0] write_buffer_0x39 = write_buffer[57];
wire [511:0] write_buffer_0x3a = write_buffer[58];
wire [511:0] write_buffer_0x3b = write_buffer[59];
wire [511:0] write_buffer_0x3c = write_buffer[60];
wire [511:0] write_buffer_0x3d = write_buffer[61];
wire [511:0] write_buffer_0x3e = write_buffer[62];
wire [511:0] write_buffer_0x3f = write_buffer[63];
wire [511:0] write_buffer_0x40 = write_buffer[64];
wire [511:0] write_buffer_0x41 = write_buffer[65];
wire [511:0] write_buffer_0x42 = write_buffer[66];
wire [511:0] write_buffer_0x43 = write_buffer[67];
wire [511:0] write_buffer_0x44 = write_buffer[68];
wire [511:0] write_buffer_0x45 = write_buffer[69];
wire [511:0] write_buffer_0x46 = write_buffer[70];
wire [511:0] write_buffer_0x47 = write_buffer[71];
wire [511:0] write_buffer_0x48 = write_buffer[72];
wire [511:0] write_buffer_0x49 = write_buffer[73];
wire [511:0] write_buffer_0x4a = write_buffer[74];
wire [511:0] write_buffer_0x4b = write_buffer[75];
wire [511:0] write_buffer_0x4c = write_buffer[76];
wire [511:0] write_buffer_0x4d = write_buffer[77];
wire [511:0] write_buffer_0x4e = write_buffer[78];
wire [511:0] write_buffer_0x4f = write_buffer[79];
wire [511:0] write_buffer_0x50 = write_buffer[80];
wire [511:0] write_buffer_0x51 = write_buffer[81];
wire [511:0] write_buffer_0x52 = write_buffer[82];
wire [511:0] write_buffer_0x53 = write_buffer[83];
wire [511:0] write_buffer_0x54 = write_buffer[84];
wire [511:0] write_buffer_0x55 = write_buffer[85];
wire [511:0] write_buffer_0x56 = write_buffer[86];
wire [511:0] write_buffer_0x57 = write_buffer[87];
wire [511:0] write_buffer_0x58 = write_buffer[88];
wire [511:0] write_buffer_0x59 = write_buffer[89];
wire [511:0] write_buffer_0x5a = write_buffer[90];
wire [511:0] write_buffer_0x5b = write_buffer[91];
wire [511:0] write_buffer_0x5c = write_buffer[92];
wire [511:0] write_buffer_0x5d = write_buffer[93];
wire [511:0] write_buffer_0x5e = write_buffer[94];
wire [511:0] write_buffer_0x5f = write_buffer[95];
wire [511:0] write_buffer_0x60 = write_buffer[96];
wire [511:0] write_buffer_0x61 = write_buffer[97];
wire [511:0] write_buffer_0x62 = write_buffer[98];
wire [511:0] write_buffer_0x63 = write_buffer[99];
wire [511:0] write_buffer_0x64 = write_buffer[100];
wire [511:0] write_buffer_0x65 = write_buffer[101];
wire [511:0] write_buffer_0x66 = write_buffer[102];
wire [511:0] write_buffer_0x67 = write_buffer[103];
wire [511:0] write_buffer_0x68 = write_buffer[104];
wire [511:0] write_buffer_0x69 = write_buffer[105];
wire [511:0] write_buffer_0x6a = write_buffer[106];
wire [511:0] write_buffer_0x6b = write_buffer[107];
wire [511:0] write_buffer_0x6c = write_buffer[108];
wire [511:0] write_buffer_0x6d = write_buffer[109];
wire [511:0] write_buffer_0x6e = write_buffer[110];
wire [511:0] write_buffer_0x6f = write_buffer[111];
wire [511:0] write_buffer_0x70 = write_buffer[112];
wire [511:0] write_buffer_0x71 = write_buffer[113];
wire [511:0] write_buffer_0x72 = write_buffer[114];
wire [511:0] write_buffer_0x73 = write_buffer[115];
wire [511:0] write_buffer_0x74 = write_buffer[116];
wire [511:0] write_buffer_0x75 = write_buffer[117];
wire [511:0] write_buffer_0x76 = write_buffer[118];
wire [511:0] write_buffer_0x77 = write_buffer[119];
wire [511:0] write_buffer_0x78 = write_buffer[120];
wire [511:0] write_buffer_0x79 = write_buffer[121];
wire [511:0] write_buffer_0x7a = write_buffer[122];
wire [511:0] write_buffer_0x7b = write_buffer[123];
wire [511:0] write_buffer_0x7c = write_buffer[124];
wire [511:0] write_buffer_0x7d = write_buffer[125];
wire [511:0] write_buffer_0x7e = write_buffer[126];
wire [511:0] write_buffer_0x7f = write_buffer[127];
wire [511:0] write_buffer_0x80 = write_buffer[128];
wire [511:0] write_buffer_0x81 = write_buffer[129];
wire [511:0] write_buffer_0x82 = write_buffer[130];
wire [511:0] write_buffer_0x83 = write_buffer[131];
wire [511:0] write_buffer_0x84 = write_buffer[132];
wire [511:0] write_buffer_0x85 = write_buffer[133];
wire [511:0] write_buffer_0x86 = write_buffer[134];
wire [511:0] write_buffer_0x87 = write_buffer[135];
wire [511:0] write_buffer_0x88 = write_buffer[136];
wire [511:0] write_buffer_0x89 = write_buffer[137];
wire [511:0] write_buffer_0x8a = write_buffer[138];
wire [511:0] write_buffer_0x8b = write_buffer[139];
wire [511:0] write_buffer_0x8c = write_buffer[140];
wire [511:0] write_buffer_0x8d = write_buffer[141];
wire [511:0] write_buffer_0x8e = write_buffer[142];
wire [511:0] write_buffer_0x8f = write_buffer[143];
wire [511:0] write_buffer_0x90 = write_buffer[144];
wire [511:0] write_buffer_0x91 = write_buffer[145];
wire [511:0] write_buffer_0x92 = write_buffer[146];
wire [511:0] write_buffer_0x93 = write_buffer[147];
wire [511:0] write_buffer_0x94 = write_buffer[148];
wire [511:0] write_buffer_0x95 = write_buffer[149];
wire [511:0] write_buffer_0x96 = write_buffer[150];
wire [511:0] write_buffer_0x97 = write_buffer[151];
wire [511:0] write_buffer_0x98 = write_buffer[152];
wire [511:0] write_buffer_0x99 = write_buffer[153];
wire [511:0] write_buffer_0x9a = write_buffer[154];
wire [511:0] write_buffer_0x9b = write_buffer[155];
wire [511:0] write_buffer_0x9c = write_buffer[156];
wire [511:0] write_buffer_0x9d = write_buffer[157];
wire [511:0] write_buffer_0x9e = write_buffer[158];
wire [511:0] write_buffer_0x9f = write_buffer[159];
wire [511:0] write_buffer_0xa0 = write_buffer[160];
wire [511:0] write_buffer_0xa1 = write_buffer[161];
wire [511:0] write_buffer_0xa2 = write_buffer[162];
wire [511:0] write_buffer_0xa3 = write_buffer[163];
wire [511:0] write_buffer_0xa4 = write_buffer[164];
wire [511:0] write_buffer_0xa5 = write_buffer[165];
wire [511:0] write_buffer_0xa6 = write_buffer[166];
wire [511:0] write_buffer_0xa7 = write_buffer[167];
wire [511:0] write_buffer_0xa8 = write_buffer[168];
wire [511:0] write_buffer_0xa9 = write_buffer[169];
wire [511:0] write_buffer_0xaa = write_buffer[170];
wire [511:0] write_buffer_0xab = write_buffer[171];
wire [511:0] write_buffer_0xac = write_buffer[172];
wire [511:0] write_buffer_0xad = write_buffer[173];
wire [511:0] write_buffer_0xae = write_buffer[174];
wire [511:0] write_buffer_0xaf = write_buffer[175];
wire [511:0] write_buffer_0xb0 = write_buffer[176];
wire [511:0] write_buffer_0xb1 = write_buffer[177];
wire [511:0] write_buffer_0xb2 = write_buffer[178];
wire [511:0] write_buffer_0xb3 = write_buffer[179];
wire [511:0] write_buffer_0xb4 = write_buffer[180];
wire [511:0] write_buffer_0xb5 = write_buffer[181];
wire [511:0] write_buffer_0xb6 = write_buffer[182];
wire [511:0] write_buffer_0xb7 = write_buffer[183];
wire [511:0] write_buffer_0xb8 = write_buffer[184];
wire [511:0] write_buffer_0xb9 = write_buffer[185];
wire [511:0] write_buffer_0xba = write_buffer[186];
wire [511:0] write_buffer_0xbb = write_buffer[187];
wire [511:0] write_buffer_0xbc = write_buffer[188];
wire [511:0] write_buffer_0xbd = write_buffer[189];
wire [511:0] write_buffer_0xbe = write_buffer[190];
wire [511:0] write_buffer_0xbf = write_buffer[191];
wire [511:0] write_buffer_0xc0 = write_buffer[192];
wire [511:0] write_buffer_0xc1 = write_buffer[193];
wire [511:0] write_buffer_0xc2 = write_buffer[194];
wire [511:0] write_buffer_0xc3 = write_buffer[195];
wire [511:0] write_buffer_0xc4 = write_buffer[196];
wire [511:0] write_buffer_0xc5 = write_buffer[197];
wire [511:0] write_buffer_0xc6 = write_buffer[198];
wire [511:0] write_buffer_0xc7 = write_buffer[199];
wire [511:0] write_buffer_0xc8 = write_buffer[200];
wire [511:0] write_buffer_0xc9 = write_buffer[201];
wire [511:0] write_buffer_0xca = write_buffer[202];
wire [511:0] write_buffer_0xcb = write_buffer[203];
wire [511:0] write_buffer_0xcc = write_buffer[204];
wire [511:0] write_buffer_0xcd = write_buffer[205];
wire [511:0] write_buffer_0xce = write_buffer[206];
wire [511:0] write_buffer_0xcf = write_buffer[207];
wire [511:0] write_buffer_0xd0 = write_buffer[208];
wire [511:0] write_buffer_0xd1 = write_buffer[209];
wire [511:0] write_buffer_0xd2 = write_buffer[210];
wire [511:0] write_buffer_0xd3 = write_buffer[211];
wire [511:0] write_buffer_0xd4 = write_buffer[212];
wire [511:0] write_buffer_0xd5 = write_buffer[213];
wire [511:0] write_buffer_0xd6 = write_buffer[214];
wire [511:0] write_buffer_0xd7 = write_buffer[215];
wire [511:0] write_buffer_0xd8 = write_buffer[216];
wire [511:0] write_buffer_0xd9 = write_buffer[217];
wire [511:0] write_buffer_0xda = write_buffer[218];
wire [511:0] write_buffer_0xdb = write_buffer[219];
wire [511:0] write_buffer_0xdc = write_buffer[220];
wire [511:0] write_buffer_0xdd = write_buffer[221];
wire [511:0] write_buffer_0xde = write_buffer[222];
wire [511:0] write_buffer_0xdf = write_buffer[223];
wire [511:0] write_buffer_0xe0 = write_buffer[224];
wire [511:0] write_buffer_0xe1 = write_buffer[225];
wire [511:0] write_buffer_0xe2 = write_buffer[226];
wire [511:0] write_buffer_0xe3 = write_buffer[227];
wire [511:0] write_buffer_0xe4 = write_buffer[228];
wire [511:0] write_buffer_0xe5 = write_buffer[229];
wire [511:0] write_buffer_0xe6 = write_buffer[230];
wire [511:0] write_buffer_0xe7 = write_buffer[231];
wire [511:0] write_buffer_0xe8 = write_buffer[232];
wire [511:0] write_buffer_0xe9 = write_buffer[233];
wire [511:0] write_buffer_0xea = write_buffer[234];
wire [511:0] write_buffer_0xeb = write_buffer[235];
wire [511:0] write_buffer_0xec = write_buffer[236];
wire [511:0] write_buffer_0xed = write_buffer[237];
wire [511:0] write_buffer_0xee = write_buffer[238];
wire [511:0] write_buffer_0xef = write_buffer[239];
wire [511:0] write_buffer_0xf0 = write_buffer[240];
wire [511:0] write_buffer_0xf1 = write_buffer[241];
wire [511:0] write_buffer_0xf2 = write_buffer[242];
wire [511:0] write_buffer_0xf3 = write_buffer[243];
wire [511:0] write_buffer_0xf4 = write_buffer[244];
wire [511:0] write_buffer_0xf5 = write_buffer[245];
wire [511:0] write_buffer_0xf6 = write_buffer[246];
wire [511:0] write_buffer_0xf7 = write_buffer[247];
wire [511:0] write_buffer_0xf8 = write_buffer[248];
wire [511:0] write_buffer_0xf9 = write_buffer[249];
wire [511:0] write_buffer_0xfa = write_buffer[250];
wire [511:0] write_buffer_0xfb = write_buffer[251];
wire [511:0] write_buffer_0xfc = write_buffer[252];
wire [511:0] write_buffer_0xfd = write_buffer[253];
wire [511:0] write_buffer_0xfe = write_buffer[254];
wire [511:0] write_buffer_0xff = write_buffer[255];
wire [511:0] write_buffer_0x100 = write_buffer[256];
wire [511:0] write_buffer_0x101 = write_buffer[257];
wire [511:0] write_buffer_0x102 = write_buffer[258];
wire [511:0] write_buffer_0x103 = write_buffer[259];
wire [511:0] write_buffer_0x104 = write_buffer[260];
wire [511:0] write_buffer_0x105 = write_buffer[261];
wire [511:0] write_buffer_0x106 = write_buffer[262];
wire [511:0] write_buffer_0x107 = write_buffer[263];
wire [511:0] write_buffer_0x108 = write_buffer[264];
wire [511:0] write_buffer_0x109 = write_buffer[265];
wire [511:0] write_buffer_0x10a = write_buffer[266];
wire [511:0] write_buffer_0x10b = write_buffer[267];
wire [511:0] write_buffer_0x10c = write_buffer[268];
wire [511:0] write_buffer_0x10d = write_buffer[269];
wire [511:0] write_buffer_0x10e = write_buffer[270];
wire [511:0] write_buffer_0x10f = write_buffer[271];
wire [511:0] write_buffer_0x110 = write_buffer[272];
wire [511:0] write_buffer_0x111 = write_buffer[273];
wire [511:0] write_buffer_0x112 = write_buffer[274];
wire [511:0] write_buffer_0x113 = write_buffer[275];
wire [511:0] write_buffer_0x114 = write_buffer[276];
wire [511:0] write_buffer_0x115 = write_buffer[277];
wire [511:0] write_buffer_0x116 = write_buffer[278];
wire [511:0] write_buffer_0x117 = write_buffer[279];
wire [511:0] write_buffer_0x118 = write_buffer[280];
wire [511:0] write_buffer_0x119 = write_buffer[281];
wire [511:0] write_buffer_0x11a = write_buffer[282];
wire [511:0] write_buffer_0x11b = write_buffer[283];
wire [511:0] write_buffer_0x11c = write_buffer[284];
wire [511:0] write_buffer_0x11d = write_buffer[285];
wire [511:0] write_buffer_0x11e = write_buffer[286];
wire [511:0] write_buffer_0x11f = write_buffer[287];
wire [511:0] write_buffer_0x120 = write_buffer[288];
wire [511:0] write_buffer_0x121 = write_buffer[289];
wire [511:0] write_buffer_0x122 = write_buffer[290];
wire [511:0] write_buffer_0x123 = write_buffer[291];
wire [511:0] write_buffer_0x124 = write_buffer[292];
wire [511:0] write_buffer_0x125 = write_buffer[293];
wire [511:0] write_buffer_0x126 = write_buffer[294];
wire [511:0] write_buffer_0x127 = write_buffer[295];
wire [511:0] write_buffer_0x128 = write_buffer[296];
wire [511:0] write_buffer_0x129 = write_buffer[297];
wire [511:0] write_buffer_0x12a = write_buffer[298];
wire [511:0] write_buffer_0x12b = write_buffer[299];
wire [511:0] write_buffer_0x12c = write_buffer[300];
wire [511:0] write_buffer_0x12d = write_buffer[301];
wire [511:0] write_buffer_0x12e = write_buffer[302];
wire [511:0] write_buffer_0x12f = write_buffer[303];
wire [511:0] write_buffer_0x130 = write_buffer[304];
wire [511:0] write_buffer_0x131 = write_buffer[305];
wire [511:0] write_buffer_0x132 = write_buffer[306];
wire [511:0] write_buffer_0x133 = write_buffer[307];
wire [511:0] write_buffer_0x134 = write_buffer[308];
wire [511:0] write_buffer_0x135 = write_buffer[309];
wire [511:0] write_buffer_0x136 = write_buffer[310];
wire [511:0] write_buffer_0x137 = write_buffer[311];
wire [511:0] write_buffer_0x138 = write_buffer[312];
wire [511:0] write_buffer_0x139 = write_buffer[313];
wire [511:0] write_buffer_0x13a = write_buffer[314];
wire [511:0] write_buffer_0x13b = write_buffer[315];
wire [511:0] write_buffer_0x13c = write_buffer[316];
wire [511:0] write_buffer_0x13d = write_buffer[317];
wire [511:0] write_buffer_0x13e = write_buffer[318];
wire [511:0] write_buffer_0x13f = write_buffer[319];
wire [511:0] write_buffer_0x140 = write_buffer[320];
wire [511:0] write_buffer_0x141 = write_buffer[321];
wire [511:0] write_buffer_0x142 = write_buffer[322];
wire [511:0] write_buffer_0x143 = write_buffer[323];
wire [511:0] write_buffer_0x144 = write_buffer[324];
wire [511:0] write_buffer_0x145 = write_buffer[325];
wire [511:0] write_buffer_0x146 = write_buffer[326];
wire [511:0] write_buffer_0x147 = write_buffer[327];
wire [511:0] write_buffer_0x148 = write_buffer[328];
wire [511:0] write_buffer_0x149 = write_buffer[329];
wire [511:0] write_buffer_0x14a = write_buffer[330];
wire [511:0] write_buffer_0x14b = write_buffer[331];
wire [511:0] write_buffer_0x14c = write_buffer[332];
wire [511:0] write_buffer_0x14d = write_buffer[333];
wire [511:0] write_buffer_0x14e = write_buffer[334];
wire [511:0] write_buffer_0x14f = write_buffer[335];
wire [511:0] write_buffer_0x150 = write_buffer[336];
wire [511:0] write_buffer_0x151 = write_buffer[337];
wire [511:0] write_buffer_0x152 = write_buffer[338];
wire [511:0] write_buffer_0x153 = write_buffer[339];
wire [511:0] write_buffer_0x154 = write_buffer[340];
wire [511:0] write_buffer_0x155 = write_buffer[341];
wire [511:0] write_buffer_0x156 = write_buffer[342];
wire [511:0] write_buffer_0x157 = write_buffer[343];
wire [511:0] write_buffer_0x158 = write_buffer[344];
wire [511:0] write_buffer_0x159 = write_buffer[345];
wire [511:0] write_buffer_0x15a = write_buffer[346];
wire [511:0] write_buffer_0x15b = write_buffer[347];
wire [511:0] write_buffer_0x15c = write_buffer[348];
wire [511:0] write_buffer_0x15d = write_buffer[349];
wire [511:0] write_buffer_0x15e = write_buffer[350];
wire [511:0] write_buffer_0x15f = write_buffer[351];
wire [511:0] write_buffer_0x160 = write_buffer[352];
wire [511:0] write_buffer_0x161 = write_buffer[353];
wire [511:0] write_buffer_0x162 = write_buffer[354];
wire [511:0] write_buffer_0x163 = write_buffer[355];
wire [511:0] write_buffer_0x164 = write_buffer[356];
wire [511:0] write_buffer_0x165 = write_buffer[357];
wire [511:0] write_buffer_0x166 = write_buffer[358];
wire [511:0] write_buffer_0x167 = write_buffer[359];
wire [511:0] write_buffer_0x168 = write_buffer[360];
wire [511:0] write_buffer_0x169 = write_buffer[361];
wire [511:0] write_buffer_0x16a = write_buffer[362];
wire [511:0] write_buffer_0x16b = write_buffer[363];
wire [511:0] write_buffer_0x16c = write_buffer[364];
wire [511:0] write_buffer_0x16d = write_buffer[365];
wire [511:0] write_buffer_0x16e = write_buffer[366];
wire [511:0] write_buffer_0x16f = write_buffer[367];
wire [511:0] write_buffer_0x170 = write_buffer[368];
wire [511:0] write_buffer_0x171 = write_buffer[369];
wire [511:0] write_buffer_0x172 = write_buffer[370];
wire [511:0] write_buffer_0x173 = write_buffer[371];
wire [511:0] write_buffer_0x174 = write_buffer[372];
wire [511:0] write_buffer_0x175 = write_buffer[373];
wire [511:0] write_buffer_0x176 = write_buffer[374];
wire [511:0] write_buffer_0x177 = write_buffer[375];
wire [511:0] write_buffer_0x178 = write_buffer[376];
wire [511:0] write_buffer_0x179 = write_buffer[377];
wire [511:0] write_buffer_0x17a = write_buffer[378];
wire [511:0] write_buffer_0x17b = write_buffer[379];
wire [511:0] write_buffer_0x17c = write_buffer[380];
wire [511:0] write_buffer_0x17d = write_buffer[381];
wire [511:0] write_buffer_0x17e = write_buffer[382];
wire [511:0] write_buffer_0x17f = write_buffer[383];
wire [511:0] write_buffer_0x180 = write_buffer[384];
wire [511:0] write_buffer_0x181 = write_buffer[385];
wire [511:0] write_buffer_0x182 = write_buffer[386];
wire [511:0] write_buffer_0x183 = write_buffer[387];
wire [511:0] write_buffer_0x184 = write_buffer[388];
wire [511:0] write_buffer_0x185 = write_buffer[389];
wire [511:0] write_buffer_0x186 = write_buffer[390];
wire [511:0] write_buffer_0x187 = write_buffer[391];
wire [511:0] write_buffer_0x188 = write_buffer[392];
wire [511:0] write_buffer_0x189 = write_buffer[393];
wire [511:0] write_buffer_0x18a = write_buffer[394];
wire [511:0] write_buffer_0x18b = write_buffer[395];
wire [511:0] write_buffer_0x18c = write_buffer[396];
wire [511:0] write_buffer_0x18d = write_buffer[397];
wire [511:0] write_buffer_0x18e = write_buffer[398];
wire [511:0] write_buffer_0x18f = write_buffer[399];
wire [511:0] write_buffer_0x190 = write_buffer[400];
wire [511:0] write_buffer_0x191 = write_buffer[401];
wire [511:0] write_buffer_0x192 = write_buffer[402];
wire [511:0] write_buffer_0x193 = write_buffer[403];
wire [511:0] write_buffer_0x194 = write_buffer[404];
wire [511:0] write_buffer_0x195 = write_buffer[405];
wire [511:0] write_buffer_0x196 = write_buffer[406];
wire [511:0] write_buffer_0x197 = write_buffer[407];
wire [511:0] write_buffer_0x198 = write_buffer[408];
wire [511:0] write_buffer_0x199 = write_buffer[409];
wire [511:0] write_buffer_0x19a = write_buffer[410];
wire [511:0] write_buffer_0x19b = write_buffer[411];
wire [511:0] write_buffer_0x19c = write_buffer[412];
wire [511:0] write_buffer_0x19d = write_buffer[413];
wire [511:0] write_buffer_0x19e = write_buffer[414];
wire [511:0] write_buffer_0x19f = write_buffer[415];
wire [511:0] write_buffer_0x1a0 = write_buffer[416];
wire [511:0] write_buffer_0x1a1 = write_buffer[417];
wire [511:0] write_buffer_0x1a2 = write_buffer[418];
wire [511:0] write_buffer_0x1a3 = write_buffer[419];
wire [511:0] write_buffer_0x1a4 = write_buffer[420];
wire [511:0] write_buffer_0x1a5 = write_buffer[421];
wire [511:0] write_buffer_0x1a6 = write_buffer[422];
wire [511:0] write_buffer_0x1a7 = write_buffer[423];
wire [511:0] write_buffer_0x1a8 = write_buffer[424];
wire [511:0] write_buffer_0x1a9 = write_buffer[425];
wire [511:0] write_buffer_0x1aa = write_buffer[426];
wire [511:0] write_buffer_0x1ab = write_buffer[427];
wire [511:0] write_buffer_0x1ac = write_buffer[428];
wire [511:0] write_buffer_0x1ad = write_buffer[429];
wire [511:0] write_buffer_0x1ae = write_buffer[430];
wire [511:0] write_buffer_0x1af = write_buffer[431];
wire [511:0] write_buffer_0x1b0 = write_buffer[432];
wire [511:0] write_buffer_0x1b1 = write_buffer[433];
wire [511:0] write_buffer_0x1b2 = write_buffer[434];
wire [511:0] write_buffer_0x1b3 = write_buffer[435];
wire [511:0] write_buffer_0x1b4 = write_buffer[436];
wire [511:0] write_buffer_0x1b5 = write_buffer[437];
wire [511:0] write_buffer_0x1b6 = write_buffer[438];
wire [511:0] write_buffer_0x1b7 = write_buffer[439];
wire [511:0] write_buffer_0x1b8 = write_buffer[440];
wire [511:0] write_buffer_0x1b9 = write_buffer[441];
wire [511:0] write_buffer_0x1ba = write_buffer[442];
wire [511:0] write_buffer_0x1bb = write_buffer[443];
wire [511:0] write_buffer_0x1bc = write_buffer[444];
wire [511:0] write_buffer_0x1bd = write_buffer[445];
wire [511:0] write_buffer_0x1be = write_buffer[446];
wire [511:0] write_buffer_0x1bf = write_buffer[447];
wire [511:0] write_buffer_0x1c0 = write_buffer[448];
wire [511:0] write_buffer_0x1c1 = write_buffer[449];
wire [511:0] write_buffer_0x1c2 = write_buffer[450];
wire [511:0] write_buffer_0x1c3 = write_buffer[451];
wire [511:0] write_buffer_0x1c4 = write_buffer[452];
wire [511:0] write_buffer_0x1c5 = write_buffer[453];
wire [511:0] write_buffer_0x1c6 = write_buffer[454];
wire [511:0] write_buffer_0x1c7 = write_buffer[455];
wire [511:0] write_buffer_0x1c8 = write_buffer[456];
wire [511:0] write_buffer_0x1c9 = write_buffer[457];
wire [511:0] write_buffer_0x1ca = write_buffer[458];
wire [511:0] write_buffer_0x1cb = write_buffer[459];
wire [511:0] write_buffer_0x1cc = write_buffer[460];
wire [511:0] write_buffer_0x1cd = write_buffer[461];
wire [511:0] write_buffer_0x1ce = write_buffer[462];
wire [511:0] write_buffer_0x1cf = write_buffer[463];
wire [511:0] write_buffer_0x1d0 = write_buffer[464];
wire [511:0] write_buffer_0x1d1 = write_buffer[465];
wire [511:0] write_buffer_0x1d2 = write_buffer[466];
wire [511:0] write_buffer_0x1d3 = write_buffer[467];
wire [511:0] write_buffer_0x1d4 = write_buffer[468];
wire [511:0] write_buffer_0x1d5 = write_buffer[469];
wire [511:0] write_buffer_0x1d6 = write_buffer[470];
wire [511:0] write_buffer_0x1d7 = write_buffer[471];
wire [511:0] write_buffer_0x1d8 = write_buffer[472];
wire [511:0] write_buffer_0x1d9 = write_buffer[473];
wire [511:0] write_buffer_0x1da = write_buffer[474];
wire [511:0] write_buffer_0x1db = write_buffer[475];
wire [511:0] write_buffer_0x1dc = write_buffer[476];
wire [511:0] write_buffer_0x1dd = write_buffer[477];
wire [511:0] write_buffer_0x1de = write_buffer[478];
wire [511:0] write_buffer_0x1df = write_buffer[479];
wire [511:0] write_buffer_0x1e0 = write_buffer[480];
wire [511:0] write_buffer_0x1e1 = write_buffer[481];
wire [511:0] write_buffer_0x1e2 = write_buffer[482];
wire [511:0] write_buffer_0x1e3 = write_buffer[483];
wire [511:0] write_buffer_0x1e4 = write_buffer[484];
wire [511:0] write_buffer_0x1e5 = write_buffer[485];
wire [511:0] write_buffer_0x1e6 = write_buffer[486];
wire [511:0] write_buffer_0x1e7 = write_buffer[487];
wire [511:0] write_buffer_0x1e8 = write_buffer[488];
wire [511:0] write_buffer_0x1e9 = write_buffer[489];
wire [511:0] write_buffer_0x1ea = write_buffer[490];
wire [511:0] write_buffer_0x1eb = write_buffer[491];
wire [511:0] write_buffer_0x1ec = write_buffer[492];
wire [511:0] write_buffer_0x1ed = write_buffer[493];
wire [511:0] write_buffer_0x1ee = write_buffer[494];
wire [511:0] write_buffer_0x1ef = write_buffer[495];
wire [511:0] write_buffer_0x1f0 = write_buffer[496];
wire [511:0] write_buffer_0x1f1 = write_buffer[497];
wire [511:0] write_buffer_0x1f2 = write_buffer[498];
wire [511:0] write_buffer_0x1f3 = write_buffer[499];
wire [511:0] write_buffer_0x1f4 = write_buffer[500];
wire [511:0] write_buffer_0x1f5 = write_buffer[501];
wire [511:0] write_buffer_0x1f6 = write_buffer[502];
wire [511:0] write_buffer_0x1f7 = write_buffer[503];
wire [511:0] write_buffer_0x1f8 = write_buffer[504];
wire [511:0] write_buffer_0x1f9 = write_buffer[505];
wire [511:0] write_buffer_0x1fa = write_buffer[506];
wire [511:0] write_buffer_0x1fb = write_buffer[507];
wire [511:0] write_buffer_0x1fc = write_buffer[508];
wire [511:0] write_buffer_0x1fd = write_buffer[509];
wire [511:0] write_buffer_0x1fe = write_buffer[510];
wire [511:0] write_buffer_0x1ff = write_buffer[511];
`endif

endmodule
