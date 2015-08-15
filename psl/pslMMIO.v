`timescale 1ns/1ps

`define BigEndian64(data) {data[7:0],data[15:8],data[23:16],data[31:24],data[39:32],data[47:40],data[55:48],data[63:56]}

module pslMMIO #(
    parameter MAX_READ_BIT_WIDTH = 8,
    parameter MAX_KMER_BIT_WIDTH = 6
) (
    input clk,
    input rstb,
    input rnw,
    input valid,
    input [23:0] addr,
    input addrpar,
    input dw,
    input [63:0] wdata,
    input wpar,
    input afu_desc,
    output reg ack,
    output reg [63:0] rdata,
    output reg rpar,
    output reg [MAX_KMER_BIT_WIDTH - 1 : 0] kmerLength,
    output reg [2:0] mode,
    output reg [1:0] threshold,
    output reg [7:0] qThreshold0,
    output reg [7:0] qThreshold1,
    output reg [7:0] qThreshold2,
    output reg [7:0] qThreshold3,
    output reg [63:0] read_base_addr,
    output reg [63:0] write_base_addr,
    output reg [31:0] num_items_to_process,
    output reg [31:0] ddr3_base_address,
    input [31:0] num_reads_read_active,
    input [31:0] num_reads_written_active,
    output start_pls,
    output reg MMIO_RSTb,
    input finish,
    output reg last_workload,
    input local_init_done,
    input local_cal_success,
    input local_cal_fail,
    input pll_locked,
    input ddr3_init_done,
    input afu_pll_locked
);

//Local parameters
localparam CONTROL        = 'h2;
localparam THRESHOLD      = 'h3;
localparam READ_BASE      = 'h4;
localparam WRITE_BASE     = 'h6;
localparam READS_RECEIVED = 'h8;
localparam READS_WRITTEN  = 'h9;
localparam NUM_ITEMS      = 'ha;
localparam START          = 'h10;
localparam RESET          = 'h20;
localparam STATUS         = 'h30;
localparam DDR3_BASE      = 'h40;

//Current configuration register set
wire [31:0] r0;
wire [31:0] r1;
reg [63:0] rdataPrelim;
wire parityPrelim;
wire [0:63] afu[0 : 'h48];
wire reset_signal;
reg [3:0] rstb_mmio;
reg [31:0] num_reads_read;
reg [31:0] num_reads_written;
reg status;
reg [4:0] DDR_STATUS;
reg rnw_del;
reg valid_del;
reg [23:0] addr_del;
reg addrpar_del;
reg dw_del;
reg [63:0] wdata_del;
reg wpar_del;
reg afu_desc_del;

//Flop signals so that we are not affected by combinational delay at the PSL output
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        rnw_del <= 'b0;
        valid_del <= 'b0;
        addr_del <= 'b0;
        addrpar_del <= 'b0;
        dw_del <= 'b0;
        wdata_del <= 'b0;
        wpar_del <= 'b0;
        afu_desc_del <= 'b0;
    end
    else begin
        rnw_del <= rnw;
        valid_del <= valid;
        addr_del <= addr;
        addrpar_del <= addrpar;
        dw_del <= dw;
        wdata_del <= wdata;
        wpar_del <= wpar;
        afu_desc_del <= afu_desc;
    end
end

//Register write
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        mode                  <= 3'b0;
        last_workload         <= 1'b0;
        kmerLength            <= {MAX_KMER_BIT_WIDTH{1'b0}};
        threshold             <= 2'b0;
        qThreshold0           <= 8'b0;
        qThreshold1           <= 8'd40;
        qThreshold2           <= 8'd80;
        qThreshold3           <= 8'd127;
        read_base_addr        <= 64'b0;
        write_base_addr       <= 64'b0;
        num_items_to_process  <= 32'b0;
        num_reads_read        <= 32'b0;
        num_reads_written     <= 32'b0;
        status                <= 1'b1;
        DDR_STATUS            <= 5'b0;
        ddr3_base_address     <= 32'b0;
    end
    else begin
        if (valid_del & ~rnw_del) begin
            case (addr_del)
                CONTROL : begin
                    mode          <= wdata_del[2:0];
                    threshold     <= wdata_del[3:2];
                    kmerLength    <= wdata_del[MAX_KMER_BIT_WIDTH + 8 - 1 : 8];
                    last_workload <= wdata_del[31];
                    if (dw_del) begin
                        qThreshold0 <= wdata_del[39:32];
                        qThreshold1 <= wdata_del[47:40];
                        qThreshold2 <= wdata_del[55:48];
                        qThreshold3 <= wdata_del[63:56];
                    end
                end
                THRESHOLD : begin
                    qThreshold0 <= wdata_del[7:0];
                    qThreshold1 <= wdata_del[15:8];
                    qThreshold2 <= wdata_del[23:16];
                    qThreshold3 <= wdata_del[31:24];
                end
                READ_BASE : begin
                    read_base_addr[31:0] <= wdata_del[31:0];
                    if (dw_del) begin
                        read_base_addr[63:32] <= wdata_del[63:32];
                    end
                end
                WRITE_BASE : begin
                    write_base_addr[31:0] <= wdata_del[31:0];
                    if (dw_del) begin
                        write_base_addr[63:32] <= wdata_del[63:32];
                    end
                end
                READS_RECEIVED : begin
                    num_reads_read <= wdata_del[31:0];
                    if (dw_del) begin
                        num_reads_written <= wdata_del[63:32];
                    end
                end
                READS_WRITTEN : begin
                    num_reads_written <= wdata_del[31:0];
                end
                NUM_ITEMS : begin
                    num_items_to_process <= wdata_del[31:0];
                end
                STATUS : begin
                    status <= 1'b0;
                end
                DDR3_BASE : begin
                    ddr3_base_address <= wdata_del[31:0];
                end
            endcase
        end
        else begin
            num_reads_read    <= num_reads_read_active;
            num_reads_written <= num_reads_written_active;
            status            <= finish | status;
        end
        DDR_STATUS <= {ddr3_init_done,pll_locked,local_cal_fail,local_cal_success,local_init_done};
    end
end

//Start and reset
assign start_pls    = valid_del & ~rnw_del & (addr_del == START);
assign reset_signal = valid_del & ~rnw_del & (addr_del == RESET);

//Synchronize the reset
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        rstb_mmio[3:0] <= 4'hf;
    end
    else begin
        rstb_mmio[3:0] <= {rstb_mmio[2:0], ~reset_signal};
    end
end

//Reset by MMIO writes
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        MMIO_RSTb <= 1'b1;
    end
    else begin
        MMIO_RSTb <= &rstb_mmio; //Avoid glitches
    end
end

//Putting together some splintered registers
assign r0          = {qThreshold3, qThreshold2, qThreshold1, qThreshold0};
assign r1          =  {{(32 - (MAX_KMER_BIT_WIDTH + 8)){1'b0}}, kmerLength, 3'b0, threshold, mode};

//Register reads
always @* begin
    case (addr_del)
        CONTROL : begin
            rdataPrelim <= {dw_del ? r1 : r0, r0};
        end
        THRESHOLD : begin
            rdataPrelim <= {r1, r1};
        end
        READ_BASE : begin
            rdataPrelim <= {dw_del ? read_base_addr[63:32] : read_base_addr[31:0], read_base_addr[31:0]};
        end
        WRITE_BASE : begin
            rdataPrelim <= {dw_del ? write_base_addr[63:32] : write_base_addr[31:0], write_base_addr[31:0]};
        end
        READS_RECEIVED : begin
            rdataPrelim <= {dw_del ? num_reads_written : num_reads_read, num_reads_read};
        end
        READS_WRITTEN : begin
            rdataPrelim <= {num_reads_written, num_reads_written};
        end
        NUM_ITEMS : begin
            rdataPrelim <= {num_items_to_process, num_items_to_process};
        end
        STATUS : begin
            rdataPrelim <= {{25'b0, afu_pll_locked, DDR_STATUS, status}, {25'b0, afu_pll_locked, DDR_STATUS, status}};
        end
        DDR3_BASE : begin
            rdataPrelim <= {ddr3_base_address, ddr3_base_address};
        end
        default : begin
            rdataPrelim <= 64'h0;
        end
    endcase
end

//Flop out read data and parity
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        rdata <= 64'b0;
        rpar  <= 1'b0;
    end
    else begin
        rdata <= afu_desc_del ? (dw_del ? afu[{addr_del,2'b0}] : {afu[{addr_del,2'b0}][0:31], afu[{addr_del,2'b0}][0:31]}) : rdataPrelim; //TBD - not too sure of this part ...
        rpar  <= parityPrelim;
    end
end

//Tree based XOR for parity
//xorTree #(.BIT_WIDTH(6)) rdataParity(.signal(rdataPrelim), .par(parityPrelim));
assign parityPrelim = 'b0;

//ACK is delayed valid_del - give one cycle
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        ack <= 1'b0;
    end 
    else begin
        ack <= valid_del;
    end
end

//AFU Descriptor
assign afu['h0][0:15]  = 'h0;         //Number of interrupts per process (min)
assign afu['h0][16:31] = 'h1;         //Number of processes (max)
assign afu['h0][32:47] = 'h0;         //Number of configuration records
assign afu['h0][48:63] = 'h8010;      //Required Programming model - this sets it to dedicated process model

assign afu['h1] = 64'h0;
assign afu['h2] = 64'h0;
assign afu['h3] = 64'h0;
assign afu['h4] = 64'h0;
assign afu['h5] = 64'h0;
assign afu['h6] = 64'h0;
assign afu['h7] = 64'h0;

assign afu['h8] = 64'h0;
assign afu['h9] = 64'h0;
assign afu['ha] = 64'h0;
assign afu['hb] = 64'h0;
assign afu['hc] = 64'h0;
assign afu['hd] = 64'h0;
assign afu['he] = 64'h0;
assign afu['hf] = 64'h0;
assign afu['h10] = 64'h0;
assign afu['h11] = 64'h0;
assign afu['h12] = 64'h0;
assign afu['h13] = 64'h0;
assign afu['h14] = 64'h0;
assign afu['h15] = 64'h0;
assign afu['h16] = 64'h0;
assign afu['h17] = 64'h0;
assign afu['h18] = 64'h0;
assign afu['h19] = 64'h0;
assign afu['h1a] = 64'h0;
assign afu['h1b] = 64'h0;
assign afu['h1c] = 64'h0;
assign afu['h1d] = 64'h0;
assign afu['h1e] = 64'h0;
assign afu['h1f] = 64'h0;

assign afu['h20] = 64'h0;             //No AFU configuration record

assign afu['h21] = 64'h0;
assign afu['h22] = 64'h0;
assign afu['h23] = 64'h0;
assign afu['h24] = 64'h0;
assign afu['h25] = 64'h0;
assign afu['h26] = 64'h0;
assign afu['h27] = 64'h0;

assign afu['h28] = 64'h0;             //Offset of the AFU configuration record - not valid_del I guess

assign afu['h29] = 64'h0;
assign afu['h2a] = 64'h0;
assign afu['h2b] = 64'h0;
assign afu['h2c] = 64'h0;
assign afu['h2d] = 64'h0;
assign afu['h2e] = 64'h0;
assign afu['h2f] = 64'h0;

assign afu['h30][0:5]  = 'h0;        //A problem state area is required
assign afu['h30][6]    = 'h1;
assign afu['h30][7]    = 'h1;
assign afu['h30][8:63] = 4 * 1024;    //Size (in multiples of 4k bytes) of problem state area

assign afu['h31] = 64'h0;
assign afu['h32] = 64'h0;
assign afu['h33] = 64'h0;
assign afu['h34] = 64'h0;
assign afu['h35] = 64'h0;
assign afu['h36] = 64'h0;
assign afu['h37] = 64'h0;

assign afu['h38] = 64'h0;             //Offset of the per-problem problem state area

assign afu['h39] = 64'h0;
assign afu['h3a] = 64'h0;
assign afu['h3b] = 64'h0;
assign afu['h3c] = 64'h0;
assign afu['h3d] = 64'h0;
assign afu['h3e] = 64'h0;
assign afu['h3f] = 64'h0;

assign afu['h40] = 64'h0;             //Length of the AFU error buffer (in mulitples of 4k offsets)

assign afu['h41] = 64'h0;
assign afu['h42] = 64'h0;
assign afu['h43] = 64'h0;
assign afu['h44] = 64'h0;
assign afu['h45] = 64'h0;
assign afu['h46] = 64'h0;
assign afu['h47] = 64'h0;

assign afu['h48] = 64'h0;             //Offset of the error buffer

endmodule
