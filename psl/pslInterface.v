`timescale 1ns / 1ps
module pslInterface #(
    parameter CORRECTION    = 'b010,
    parameter SOLID_ISLANDS = 'b001,
    parameter PROGRAM       = 'b000,
    parameter DDR3_INIT     = 'b100,
    parameter DDR3_READ     = 'b101,
    parameter DDR3_WRITE    = 'b110
) (
    input CPU_RESETn,

//PSL Control interface
    input ha_pclock,
    input ha_jval,
    input [7:0] ha_jcom,
    input ha_jcompar,
    input [63:0] ha_jea,
    input ha_jeapar,
    output ah_jrunning,
    output reg ah_jdone,
    output ah_jcack,
    output [63:0] ah_jerror,
    output ah_jyield,
    output ah_tbreq,
    output ah_paren,
    input [7:0] ha_croom,

//PSL command-response interface
    output ah_cvalid,
    output [7:0] ah_ctag,
    output ah_ctagpar,
    output [12:0] ah_com,
    output ah_compar,
    output [2:0] ah_cabt,
    output [63:0] ah_cea,
    output ah_ceapar,
    output [15:0] ah_cch,
    output [11:0] ah_csize,
    input ha_rvalid,
    input [7:0] ha_rtag,
    input ha_rtagpar,
    input [7:0] ha_response,
    input [8:0] ha_rcredits,
    input [1:0] ha_rcachestate,
    input [12:0] ha_rcachepos,

//PSL buffer interface
    input ha_brvalid,
    input [7:0] ha_brtag,
    input ha_brtagpar,
    input [5:0] ha_brad,
    output [3:0] ah_brlat,
    output [511:0] ah_brdata,
    output [7:0] ah_brpar,
    input ha_bwvalid,
    input [7:0] ha_bwtag,
    input ha_bwtagpar,
    input [5:0] ha_bwad,
    input [511:0] ha_bwdata,
    input [7:0] ha_bwpar,

//PSL MMIO interface
    input ha_mmrnw,
    input ha_mmval,
    input [23:0] ha_mmad,
    input ha_mmadpar,
    input ha_mmdw,
    input [63:0] ha_mmdata,
    input ha_mmdatapar,
    output ah_mmack,
    output [63:0] ah_mmdata,
    output ah_mmdatapar,
    input ha_mmcfg,

//Interace with read error correction unit
    //From PSL Buffer
    output [511 : 0] output_lo,
    output [511 : 0] output_hi,
    output [7:0] read_length_lo,
    output [7:0] read_length_hi,
    output [7:0] start_position,
    output [7:0] end_position,
    output output_valid,
    input ready,
    input [2047 : 0] data,
    input data_valid,
    input [5:0] num_items_per_data,
    input num_items_per_data_valid,
    output read_data,

    //From PSL MMIO
    output [2:0] mode,
    output [1:0] threshold,
    output [5:0] kmerLength,
    input units_idle,

    //Core Reset
    output reg core_rstb,

    //DDR2 init status
    input local_init_done,
    input local_cal_success,
    input local_cal_fail,
    input pll_locked,
    input ddr3_init_done,

    //DDR3 control signals
    output reg [29:0] avl_addr,
    input avl_ready,
    input avl_rdata_valid,
    input [511:0] avl_rdata,
    input avl_read_req,

    input afu_pll_locked
);

//Internal registers/wires
wire [7:0] qThreshold0;
wire [7:0] qThreshold1;
wire [7:0] qThreshold2;
wire [7:0] qThreshold3;
wire [63:0] read_base_address;
wire [63:0] write_base_address;
wire [31:0] num_reads_read_active;
wire [31:0] num_reads_written_active;
wire [31:0] num_items_to_process;
wire [5:0] num_sub_items_per_item;
reg [5:0] num_items_per_data_del;
wire write_cmd_issued;
wire psl_read_state;
wire abort;
wire rstb;
wire [63:0] wed;
wire reset_cmd_received;
wire wbuffer_item_available;
wire [7:0] free_location;
wire free_signal;
wire [7:0] num_credits;
wire clk;
wire MMIO_RSTb;
wire last_workload;
wire finished;
wire finish_mmio;
wire core_rstb_comb;
wire input_buffer_empty;
wire psl_idle_state;
wire [9:0] iteration_limit;
wire [31:0] ddr3_base_address;
reg [2047:0] buffer_data;
reg buffer_data_valid;
wire [2047:0] buffer_data_ddr3;
wire buffer_data_valid_ddr3;
reg num_items_per_data_valid_del;

//Internal signal assignments
assign clk = ha_pclock;

//Route the appropriate buffer data - flop it for good measure - this is a HUGE number of flops ... :-|
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        buffer_data <= 2048'b0;
        buffer_data_valid <= 1'b0;
        num_items_per_data_valid_del <= 1'b0;
        num_items_per_data_del <= 'b0;
    end
    else begin
        buffer_data <= (mode == DDR3_READ) ? buffer_data_ddr3 : data;
        buffer_data_valid <= (mode == DDR3_READ) ? buffer_data_valid_ddr3 : data_valid;
        num_items_per_data_valid_del <= num_items_per_data_valid;
        num_items_per_data_del <= num_items_per_data;
    end
end

//Data buffers from/to host
pslBuffer #(
    .CORRECTION(CORRECTION),
    .SOLID_ISLANDS(SOLID_ISLANDS),
    .PROGRAM(PROGRAM)
) buffer (
//PSL interface
    .clk(clk),
    .rstb(rstb),
    .rvalid(ha_brvalid),
    .rtag(ha_brtag),
    .rtagpar(ha_brtagpar),
    .rad(ha_brad),
    .rlat(ah_brlat),
    .rdata(ah_brdata),
    .rpar(ah_brpar),
    .wvalid(ha_bwvalid),
    .wtag(ha_bwtag),
    .wtagpar(ha_bwtagpar),
    .wad(ha_bwad),
    .wdata(ha_bwdata),
    .wpar(ha_bwpar),
//Interface with internal modules
    .output_lo(output_lo),
    .output_hi(output_hi),
    .read_length_lo(read_length_lo),
    .read_length_hi(read_length_hi),
    .start_position(start_position),
    .end_position(end_position),
    .output_valid(output_valid),
    .ready(ready),
    .data(buffer_data),
    .data_valid(buffer_data_valid),
    .num_items_per_data(num_items_per_data_del),
    .num_items_per_data_valid(num_items_per_data_valid_del),
    .read_data(read_data),
    .psl_read_state(psl_read_state),
    .psl_idle_state(psl_idle_state),
    .mode(mode),
    .num_items_to_cmd(num_sub_items_per_item),
    .write_cmd_issued(write_cmd_issued),
    .wbuffer_item_available(wbuffer_item_available),
    .free_location(free_location),
    .free_signal(free_signal),
    .qualityThreshold0(qThreshold0),
    .qualityThreshold1(qThreshold1),
    .qualityThreshold2(qThreshold2),
    .qualityThreshold3(qThreshold3),
    .input_buffer_empty(input_buffer_empty),
    .iteration_limit(iteration_limit)
);

//Command interface controlling everything
pslCommand #(
    .CORRECTION(CORRECTION),
    .SOLID_ISLANDS(SOLID_ISLANDS),
    .PROGRAM(PROGRAM)
) command (
//PSL interface
    .clk(clk),
    .rstb(rstb),
    .ah_cvalid(ah_cvalid),
    .ah_ctag(ah_ctag),
    .ah_ctagpar(ah_ctagpar),
    .ah_com(ah_com),
    .ah_compar(ah_compar),
    .ah_cabt(ah_cabt),
    .ah_cea(ah_cea),
    .ah_ceapar(ah_ceapar),
    .ah_cch(ah_cch),
    .ah_csize(ah_csize),
    .num_credits(num_credits),
    .resp_valid(ha_rvalid),
    .resp_tag(ha_rtag),
    .resp_tag_par(ha_rtagpar),
    .resp_code(ha_response),
    .resp_credits(ha_rcredits),
    .resp_cache_state(ha_rcachestate),
    .resp_cache_pos(ha_rcachepos),
//Interface with internal modules
    .start(start),
    .abort(abort),
    .finished(finished),
    .num_items_to_process(num_items_to_process),
    .num_sub_items_per_item(num_sub_items_per_item),
    .write_base_address(write_base_address),
    .read_base_address(read_base_address),
    .write_cmd_issued(write_cmd_issued),
    .psl_read_state(psl_read_state),
    .psl_idle_state(psl_idle_state),
    .mode(mode),
    .wbuffer_item_available(wbuffer_item_available),
    .free_location(free_location),
    .free_signal(free_signal),
    .num_reads_read_active(num_reads_read_active),
    .num_reads_written_active(num_reads_written_active),
    .reset_cmd_received(reset_cmd_received),
    .last_workload(last_workload),
    .finish(finish),
    .units_idle(units_idle),
    .input_buffer_empty(input_buffer_empty),
    .iteration_limit(iteration_limit),
    .ddr3_base_address(ddr3_base_address),
    .avl_read_req(avl_read_req),
    .avl_addr(avl_addr),             
    .avl_ready(avl_ready)
);

//MMIO interface for registers
pslMMIO mmio (
//PSL interface
    .clk(clk),
    .rstb(rstb),
    .rnw(ha_mmrnw),
    .valid(ha_mmval),
    .addr(ha_mmad),
    .addrpar(ha_mmadpar),
    .dw(ha_mmdw),
    .wdata(ha_mmdata),
    .wpar(ha_mmdatapar),
    .ack(ah_mmack),
    .rdata(ah_mmdata),
    .rpar(ah_mmdatapar),
    .afu_desc(ha_mmcfg),
//Interface with internal modules
    .kmerLength(kmerLength),
    .mode(mode),
    .threshold(threshold),
    .qThreshold0(qThreshold0),
    .qThreshold1(qThreshold1),
    .qThreshold2(qThreshold2),
    .qThreshold3(qThreshold3),
    .read_base_addr(read_base_address),
    .write_base_addr(write_base_address),
    .num_reads_read_active(num_reads_read_active),
    .num_reads_written_active(num_reads_written_active),
    .num_items_to_process(num_items_to_process),
    .start_pls(start),
    .MMIO_RSTb(MMIO_RSTb),
    .last_workload(last_workload),
    .finish(finish_mmio),
//DDR3 status bits
    .local_init_done(local_init_done),
    .local_cal_success(local_cal_success),
    .local_cal_fail(local_cal_fail),
    .pll_locked(pll_locked),
    .ddr3_init_done(ddr3_init_done),
    .ddr3_base_address(ddr3_base_address),
    .afu_pll_locked(afu_pll_locked)
);

//PSL Control interface
pslControl control (
    .CPU_RESETn(CPU_RESETn),
    .ha_pclock(ha_pclock),
    .ha_jval(ha_jval),
    .ha_jcom(ha_jcom),
    .ha_jcompar(ha_jcompar),
    .ha_jea(ha_jea),
    .ha_jeapar(ha_jeapar),
    .ah_jrunning(ah_jrunning),
    .ah_jdone(ah_jdone),
    .ah_jcack(ah_jcack),
    .ah_jerror(ah_jerror),
    .ah_jyield(ah_jyield),
    .ah_tbreq(ah_tbreq),
    .ah_paren(ah_paren),
    .rstb(rstb),
    .wed(wed),
    .abort(abort),
    .ha_croom(ha_croom),
    .num_credits(num_credits),
    .reset_cmd_received(reset_cmd_received),
    .finished(finished)
);

//DDR3 to buffer format
ddr3ToBuffer buffer_data_format (
    .clk(clk),
    .rstb(rstb),
    .avl_rdata(avl_rdata),
    .avl_rdata_valid(avl_rdata_valid),
    .buffer_data(buffer_data_ddr3),
    .buffer_data_valid(buffer_data_valid_ddr3),
    .buffer_ready4_data(read_data)
);

//Synchronized to 250MHz clock
assign core_rstb_comb = MMIO_RSTb & rstb;
always @(posedge clk or negedge core_rstb_comb) begin
    if (~core_rstb_comb) begin
        core_rstb <= 1'b0;
    end
    else begin
        core_rstb <= 1'b1;
    end
end

//FINISH MMIO transactions
assign finish_mmio = finish;

endmodule
