`timescale 1ns/1ps

module afu(
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
    output wire [15:0]  mem_a,
    output wire [2:0]  mem_ba,
    output wire  mem_ck,
    output wire  mem_ck_n,
    output wire  mem_cke,
    output wire  mem_cs_n,
    output wire  [8:0] mem_dm,
    output wire  mem_ras_n,
    output wire  mem_cas_n,
    output wire  mem_we_n,
    output wire        mem_reset_n,
    inout  wire [71:0]  mem_dq,
    inout  wire [8:0]  mem_dqs,
    inout  wire [8:0]  mem_dqs_n,
    output wire  mem_odt,
    input wire oct_rzqin,
    input wire pll_ref_clk
);

parameter MAX_KMER_BIT_WIDTH       = 6;
parameter MAX_KMER_WIDTH           = {1'b1,{MAX_KMER_BIT_WIDTH{1'b0}}};
parameter MAX_READ_BIT_WIDTH       = 8;
parameter NUM_INDICES_BIT_WIDTH    = 5;
parameter NUM_INDICES              = {1'b1, {NUM_INDICES_BIT_WIDTH{1'b0}}};
parameter MAX_READ_WIDTH           = {1'b1, {MAX_READ_BIT_WIDTH{1'b0}}};
parameter MIN_KMER_WIDTH           = 12;
parameter CORRECTION               = 'b010;
parameter SOLID_ISLANDS            = 'b001;
parameter PROGRAM                  = 'b000;
parameter DDR3_INIT                = 'b100;
parameter DDR3_READ                = 'b101;
parameter DDR3_WRITE               = 'b110;
parameter NUM_BITS_NUM_UNITS       = 2;
parameter NUM_UNITS                = {1'b1, {NUM_BITS_NUM_UNITS{1'b0}}};
parameter EXTENSION_WIDTH          = 5;
parameter MIN_READ_WIDTH           = 60;
parameter QUALITY_WIDTH            = 2;
parameter NUM_CANDIDATES_BIT_WIDTH = 5;
parameter NUM_CANDIDATES           = {1'b1, {NUM_CANDIDATES_BIT_WIDTH{1'b0}}};

wire CPU_RESETn = 1'b1;
wire clk = ha_pclock;
wire [1023:0] host_data;
wire host_data_valid;
wire ready4_host_data;
wire [2:0] mode;
wire [MAX_READ_BIT_WIDTH-1:0] read_length_hi;
wire [MAX_READ_BIT_WIDTH-1:0] read_length_lo;
wire [MAX_READ_BIT_WIDTH-1:0] start_position;
wire [MAX_READ_BIT_WIDTH-1:0] end_position;
wire [2047:0] afu_data;
wire afu_data_valid;
wire [NUM_CANDIDATES_BIT_WIDTH:0] num_items_per_data;
wire num_items_per_data_valid;
wire read_afu_data;
wire [1:0] threshold;
wire [MAX_KMER_BIT_WIDTH-1:0] kmer_length;
wire core_rstb;
wire ready4_host_data_bfw;
wire ready4Kmer;
wire [2*32*NUM_INDICES-1:0] islandsProfileReads;
wire [2*MAX_READ_WIDTH-1:0] readProfileReads;
wire readValidProfileReads;
wire queryResult;
wire queryResultValid;
wire queryResultProfileReads;
wire queryResultValidProfileReads;
wire [MAX_READ_BIT_WIDTH-1:0] readLengthProfileReads;
wire [2*MAX_KMER_WIDTH-1:0] kmerProfileReads;
wire kmerValidProfileReads;
wire ready4KmerProfileReads;
wire islandsValid;
wire readSeparatorFull;
wire readSeparatorEmpty;
wire ready4IndicesReadProfiler;
wire [2*MAX_KMER_WIDTH-1:0] kmer;
wire [7:0] readLengthCorrection;
wire [2*MAX_READ_WIDTH-1:0] readCorrection;
wire [QUALITY_WIDTH*MAX_READ_WIDTH-1:0] qualityCorrection;
wire [1:0] qualityThresholdCorrection;
wire readValidCorrection;
wire ready4KmerCorrection;
wire queryResultCorrection;
wire queryResultValidCorrection;
wire ready4CandidateCorrection;
wire [7:0] startPositionCorrection;
wire [7:0] endPositionCorrection;
wire ready4ReadCorrection;
wire kmerValidCorrection;
wire [2*MAX_KMER_WIDTH-1:0] kmerCorrection;
wire [2*MAX_READ_WIDTH-1:0] candidateCorrection;
wire candidateValidCorrection;
wire [NUM_CANDIDATES_BIT_WIDTH:0] candidateNumCorrection;
wire candidateNumValidCorrection;
wire [2*MAX_READ_WIDTH-1:0] inputReadCorrection;
wire avl_ready;
wire avl_burstbegin;
wire [25:0] avl_addr;
wire avl_rdata_valid;
wire [511:0] avl_rdata;
wire [511:0] avl_wdata;
wire avl_read_req;
wire avl_write_req;
wire avl_read_req_raw;
wire avl_write_req_raw;
wire [2:0] avl_size;
wire local_init_done;
wire local_cal_success;
wire local_cal_fail;
wire [511:0] avl_wdata_bf;
wire [511:0] avl_rdata_bf;
wire avl_rdata_valid_bf;
wire avl_ready_bf;
wire wvalid;
wire rvalid;
wire [25:0] raddr;
wire [25:0] waddr;
wire cmd_fifo_empty;
wire cmd_fifo_full;
wire [3:0] cmd_fifo_num_data;
wire [25:0] cmd_fifo_raddr;
wire [25:0] cmd_fifo_waddr;
wire data_fifo_empty;
wire data_fifo_full;
wire [3:0] data_fifo_num_data;
wire [511:0] data_fifo_q;
reg [26:0] init_addr;
wire [511:0] init_data;
wire init_burst_begin;
wire init_write;
wire ddr3_init_done;
wire [511:0] avl_rdata_prelim;
wire psl_cmd_fifo_full;
wire [3:0] psl_cmd_fifo_num_data;
wire [25:0] avl_addr_from_psl;
wire psl_cmd_fifo_empty;
wire psl_data_fifo_full;
wire [3:0] psl_data_fifo_num_data;
wire psl_data_fifo_empty;
wire cmd_fifo_rd;
wire [3:0] token_fifo_usedw;
wire token_fifo_empty;
wire token_fifo_full;

/////////////////////This section is solely for simulation - but it won't hurt synthesis one bit
reg ha_jval_del;
reg [7:0] ha_jcom_del;
reg ha_jcompar_del;
reg [63:0] ha_jea_del;
reg ha_jeapar_del;
reg [7:0] ha_croom_del;
reg ha_rvalid_del;
reg [7:0] ha_rtag_del;
reg ha_rtagpar_del;
reg [7:0] ha_response_del;
reg [8:0] ha_rcredits_del;
reg [1:0] ha_rcachestate_del;
reg [12:0] ha_rcachepos_del;
reg ha_brvalid_del;
reg [7:0] ha_brtag_del;
reg ha_brtagpar_del;
reg [5:0] ha_brad_del;
reg ha_bwvalid_del;
reg [7:0] ha_bwtag_del;
reg ha_bwtagpar_del;
reg [5:0] ha_bwad_del;
reg [511:0] ha_bwdata_del;
reg [7:0] ha_bwpar_del;
reg ha_mmrnw_del;
reg ha_mmval_del;
reg [23:0] ha_mmad_del;
reg ha_mmadpar_del;
reg ha_mmdw_del;
reg [63:0] ha_mmdata_del;
reg ha_mmdatapar_del;
reg ha_mmcfg_del;
wire [25:0] avl_addr_psl;
wire avl_ready_psl;
wire avl_rdata_valid_psl;
wire avl_read_req_psl;
wire [511:0] avl_rdata_psl;
reg global_reset_n;
reg soft_reset_n;
reg [3:0] rstb_pll_ref_clk1;
reg [4:0] rstb_pll_ref_clk2;
wire [1023:0] host_data_synced;
wire host_data_valid_synced;
wire [MAX_READ_BIT_WIDTH-1:0] read_length_hi_synced;
wire [MAX_READ_BIT_WIDTH-1:0] read_length_lo_synced;
wire [MAX_READ_BIT_WIDTH-1:0] start_position_synced;
wire [MAX_READ_BIT_WIDTH-1:0] end_position_synced;
wire [3:0] psl_to_afu_num_words;
wire ready4_host_data_sync;
wire pll_100MHz;
wire afu_pll_locked;
wire core_rstb_synced;
reg [1:0] sync_core_rstb;
wire [2047:0] afu_data_synced;
wire [NUM_CANDIDATES_BIT_WIDTH:0] num_items_per_data_synced;
wire afu_to_psl_sync_empty;
wire [3:0] afu_to_psl_sync_num_words;
wire afu_to_psl_sync_full;
wire psl_to_afu_sync_empty;
wire psl_to_afu_sync_full;

always_comb {ha_jval_del, ha_jcom_del, ha_jcompar_del, ha_jea_del, ha_jeapar_del, ha_croom_del, ha_rvalid_del, ha_rtag_del, ha_rtagpar_del, ha_response_del, ha_rcredits_del, ha_rcachestate_del, ha_rcachepos_del, ha_brvalid_del, ha_brtag_del, ha_brtagpar_del, ha_brad_del, ha_bwvalid_del, ha_bwtag_del, ha_bwtagpar_del, ha_bwad_del, ha_bwdata_del, ha_bwpar_del, ha_mmrnw_del, ha_mmval_del, ha_mmad_del, ha_mmadpar_del, ha_mmdw_del, ha_mmdata_del, ha_mmdatapar_del, ha_mmcfg_del} <= {ha_jval, ha_jcom, ha_jcompar, ha_jea, ha_jeapar, ha_croom, ha_rvalid, ha_rtag, ha_rtagpar, ha_response, ha_rcredits, ha_rcachestate, ha_rcachepos, ha_brvalid, ha_brtag, ha_brtagpar, ha_brad, ha_bwvalid, ha_bwtag, ha_bwtagpar, ha_bwad, ha_bwdata, ha_bwpar, ha_mmrnw, ha_mmval, ha_mmad, ha_mmadpar, ha_mmdw, ha_mmdata, ha_mmdatapar, ha_mmcfg};
////////////////////////////////////////////////////////////////SEGMENT FOR SIMULATION ends

pslInterface psl (
    .CPU_RESETn(CPU_RESETn),
    .ha_pclock(ha_pclock),
    .ha_jval(ha_jval_del),
    .ha_jcom(ha_jcom_del),
    .ha_jcompar(ha_jcompar_del),
    .ha_jea(ha_jea_del),
    .ha_jeapar(ha_jeapar_del),
    .ah_jrunning(ah_jrunning),
    .ah_jdone(ah_jdone),
    .ah_jcack(ah_jcack),
    .ah_jerror(ah_jerror),
    .ah_jyield(ah_jyield),
    .ah_tbreq(ah_tbreq),
    .ah_paren(ah_paren),
    .ha_croom(ha_croom_del),
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
    .ha_rvalid(ha_rvalid_del),
    .ha_rtag(ha_rtag_del),
    .ha_rtagpar(ha_rtagpar_del),
    .ha_response(ha_response_del),
    .ha_rcredits(ha_rcredits_del),
    .ha_rcachestate(ha_rcachestate_del),
    .ha_rcachepos(ha_rcachepos_del),
    .ha_brvalid(ha_brvalid_del),
    .ha_brtag(ha_brtag_del),
    .ha_brtagpar(ha_brtagpar_del),
    .ha_brad(ha_brad_del),
    .ah_brlat(ah_brlat),
    .ah_brdata(ah_brdata),
    .ah_brpar(ah_brpar),
    .ha_bwvalid(ha_bwvalid_del),
    .ha_bwtag(ha_bwtag_del),
    .ha_bwtagpar(ha_bwtagpar_del),
    .ha_bwad(ha_bwad_del),
    .ha_bwdata(ha_bwdata_del),
    .ha_bwpar(ha_bwpar_del),
    .ha_mmrnw(ha_mmrnw_del),
    .ha_mmval(ha_mmval_del),
    .ha_mmad(ha_mmad_del),
    .ha_mmadpar(ha_mmadpar_del),
    .ha_mmdw(ha_mmdw_del),
    .ha_mmdata(ha_mmdata_del),
    .ha_mmdatapar(ha_mmdatapar_del),
    .ah_mmack(ah_mmack),
    .ah_mmdata(ah_mmdata),
    .ah_mmdatapar(ah_mmdatapar),
    .ha_mmcfg(ha_mmcfg_del),

    .output_lo(host_data[511:0]),
    .output_hi(host_data[1023:512]),
    .read_length_lo(read_length_lo),
    .read_length_hi(read_length_hi),
    .start_position(start_position),
    .end_position(end_position),
    .output_valid(host_data_valid),
    .ready(ready4_host_data_sync),
    .data(afu_data_synced),
    .data_valid(afu_data_valid_synced),
    .num_items_per_data(num_items_per_data_synced),
    .num_items_per_data_valid(num_items_per_data_valid_synced),
    .read_data(read_afu_data),
    .mode(mode),
    .threshold(threshold),
    .kmerLength(kmer_length),
    .core_rstb(core_rstb),
    .units_idle(bf_idle & psl_to_afu_sync_empty),
    .local_init_done(local_init_done),
    .local_cal_success(local_cal_success),
    .local_cal_fail(local_cal_fail),
    .pll_locked(pll_locked),
    .ddr3_init_done(ddr3_init_done),
    .avl_addr(avl_addr_psl),
    .avl_ready(avl_ready_psl),
    .avl_rdata_valid(avl_rdata_valid_psl),
    .avl_rdata(avl_rdata_psl),
    .avl_read_req(avl_read_req_psl),
    .afu_pll_locked(afu_pll_locked)
);

/////////////////////////////////////Synchronization between PSL and Accelerator
assign core_rstb_synced =  sync_core_rstb[1];

always @(posedge pll_100MHz or negedge core_rstb) begin
    if (~core_rstb) begin
        sync_core_rstb <= 2'b0;
    end
    else begin
        sync_core_rstb <= {sync_core_rstb[0],1'b1};
    end
end

pll afu_clocking (
    .refclk(ha_pclock),
    .rst(~core_rstb),
    .outclk_0(pll_100MHz),
    .locked(afu_pll_locked)                  //  locked.export
);

assign psl_to_afu_sync_full  = (psl_to_afu_num_words > 12);
assign ready4_host_data_sync = ~psl_to_afu_sync_full;
assign host_data_valid_synced = ~psl_to_afu_sync_empty & ready4_host_data;

//async_fifo_psl_to_afu psl_to_afu_sync (
async_fifo #(
    .DATA_WIDTH(1056)
) psl_to_afu_sync (
    .aclr(~core_rstb),
    .data({host_data,read_length_hi,read_length_lo,start_position,end_position}), //1024 + 8 + 8 + 8 + 8 = 1024 + 32 = 1056
    .rdclk(pll_100MHz),
    .rdreq(ready4_host_data),
    .wrclk(ha_pclock),
    .wrreq(host_data_valid),
    .q({host_data_synced,read_length_hi_synced,read_length_lo_synced,start_position_synced,end_position_synced}),
    .rdempty(psl_to_afu_sync_empty),
    .wrfull(),
    .wrusedw(psl_to_afu_num_words)
);

assign afu_to_psl_sync_full = (afu_to_psl_sync_num_words > 12);

//async_fifo_afu_to_psl afu_to_psl_sync (
async_fifo#(
    .DATA_WIDTH(2048+NUM_CANDIDATES_BIT_WIDTH+1)
) afu_to_psl_sync (
    .aclr(~core_rstb),
    .data({afu_data,num_items_per_data}),
    .rdclk(ha_pclock),
    .rdreq(read_afu_data),
    .wrclk(pll_100MHz),
    .wrreq(num_items_per_data_valid & afu_data_valid), //Masked at the interfaces when ready is low, no need to gate with full here ...
    .q({afu_data_synced,num_items_per_data_synced}),
    .rdempty(afu_to_psl_sync_empty),
    .wrfull(),
    .wrusedw(afu_to_psl_sync_num_words)
);

assign afu_data_valid_synced = ~afu_to_psl_sync_empty & read_afu_data;
assign num_items_per_data_valid_synced = afu_data_valid_synced;
////////////////////////////////////////////////////////////////////////////////


//////////////////////////////////////Synchronization between PSL and DDR3
assign psl_cmd_fifo_full = (psl_cmd_fifo_num_data >= 12);
assign avl_ready_psl = ~psl_cmd_fifo_full;

async_fifo psl_cmd_fifo (
    .aclr(~core_rstb),
    .data({avl_addr_psl}),
    .rdclk(afi_clk),
    .rdreq(avl_ready & ~psl_data_fifo_full & (mode == DDR3_READ)),
    .wrclk(ha_pclock),
    .wrreq(avl_read_req_psl & (mode == DDR3_READ)),
    .q({avl_addr_from_psl}),
    .rdempty(psl_cmd_fifo_empty),
    .wrfull(),
    .wrusedw(psl_cmd_fifo_num_data)
);

assign avl_addr            = (mode == DDR3_READ) ? avl_addr_from_psl : (avl_write_req ? cmd_fifo_waddr : cmd_fifo_raddr);
assign avl_burstbegin      = ((mode == DDR3_READ) ? (~psl_cmd_fifo_empty & ~psl_data_fifo_full) : (
                                                        (avl_write_req | avl_read_req) & ~data_fifo_full & ~cmd_fifo_empty
                                                    )
                             ) & avl_ready;
assign avl_read_req        = (mode == DDR3_READ) ? (~psl_cmd_fifo_empty & ~psl_data_fifo_full) :
                                                   avl_read_req_raw & ~cmd_fifo_empty & ~data_fifo_full & ~token_fifo_full;
                                                                      //Throttle with token-fifo-full

assign avl_rdata_valid_psl = ~psl_data_fifo_empty;
assign psl_data_fifo_full  = (psl_data_fifo_num_data >= 7);

//Make it large enough to carry all the data - buffer has been slowed down due to timing issues
async_fifo #(
    .DATA_WIDTH(512),
    .NUM_WORDS(512),
    .LOG_NUM_WORDS(9)
) psl_data_fifo (
    .aclr(~core_rstb),
    .data(avl_rdata),
    .rdclk(ha_pclock),
    .rdreq(1'b1),
    .wrclk(afi_clk),
    .wrreq(avl_rdata_valid & (mode == DDR3_READ)),
    .q(avl_rdata_psl),
    .rdempty(psl_data_fifo_empty),
    .wrfull(),
    .wrusedw(psl_data_fifo_num_data)
);
//////////////////////////////////////////////////////////////////////////Synchronization between PSL and DDR3 over

assign num_items_per_data = (mode == CORRECTION) ? candidateNumCorrection : 'h1;
assign num_items_per_data_valid = (mode == CORRECTION) ? candidateNumValidCorrection : afu_data_valid;

synchronousFifoParallelShiftParameterized #( //Needs to cushion the data
    .SPLIT_WIDTH(MAX_READ_WIDTH*2 + MAX_READ_BIT_WIDTH),
    .NUM_SPLITS_BIT_WIDTH(1),
    .NUM_SPLITS(2),
    .FIFO_DEPTH(32),
    .APPARENT_DEPTH(28),
    .SUB_FIFO_POINTER_SIZE(5),
    .POINTER_SIZE(6)
) readSeparator (
    .clk(pll_100MHz),
    .rstb(core_rstb_synced),
    .fifoFull(readSeparatorFull),
    .fifoEmpty(readSeparatorEmpty),
    .data({host_data_synced[511:0],read_length_lo_synced,host_data_synced[1023:512],read_length_hi_synced}),
    .valid(host_data_valid_synced & (mode == SOLID_ISLANDS)),
    .out({readProfileReads,readLengthProfileReads}),
    .read(ready4ReadProfileReads)
);

assign queryResultProfileReads      = queryResult;
assign queryResultValidProfileReads = queryResultValid & (mode == SOLID_ISLANDS);
assign ready4KmerProfileReads       = ready4Kmer & (mode == SOLID_ISLANDS);
assign readValidProfileReads        = ~readSeparatorEmpty;
assign ready4IndicesReadProfiler    = ~afu_to_psl_sync_full & (mode == SOLID_ISLANDS);

profileReads #(
    .MAX_READ_BIT_WIDTH(MAX_READ_BIT_WIDTH),
    .MAX_KMER_BIT_WIDTH(MAX_KMER_BIT_WIDTH),
    .NUM_INDICES_BIT_WIDTH(NUM_INDICES_BIT_WIDTH),
    .NUM_INDICES(NUM_INDICES),
    .MAX_READ_WIDTH(MAX_READ_WIDTH),
    .MAX_KMER_WIDTH(MAX_KMER_WIDTH),
    .MIN_KMER_WIDTH(MIN_KMER_WIDTH)
) readProfiler (
    .clk(pll_100MHz),
    .rstb(core_rstb_synced),
    .read(readProfileReads),
    .readValid(readValidProfileReads),
    .ready4Kmer(ready4KmerProfileReads),
    .queryResult(queryResultProfileReads),
    .queryResultValid(queryResultValidProfileReads),
    .kmerLength(kmer_length),
    .readLength(readLengthProfileReads),
    .kmer(kmerProfileReads),
    .ready4Indices(ready4IndicesReadProfiler),
    .ready4Read(ready4ReadProfileReads),
    .kmerValid(kmerValidProfileReads),
    .islands(islandsProfileReads),
    .islandsValid(islandsValidProfileReads)
);

assign kmer_valid     = (mode == SOLID_ISLANDS) ? kmerValidProfileReads : kmerValidCorrection;
assign kmer           = (mode == SOLID_ISLANDS) ? kmerProfileReads : kmerCorrection;
assign afu_data       = (mode == SOLID_ISLANDS) ? islandsProfileReads : {{(2048-NUM_CANDIDATES_BIT_WIDTH-2*MAX_READ_WIDTH){1'b0}}, candidateNumCorrection, candidateCorrection};
assign afu_data_valid = (mode == SOLID_ISLANDS) ? islandsValidProfileReads : candidateValidCorrection;

bloom_filter_wrapper #(
    .MAX_KMER_BIT_WIDTH(MAX_KMER_BIT_WIDTH),
    .MAX_KMER_WIDTH(MAX_KMER_WIDTH),
    .NUM_BITS_NUM_KMERS_PER_DATA(3)
) bfw (
    .clk(pll_100MHz),
    .rstb(core_rstb_synced),
    .Program(mode == PROGRAM),
    .host_data(host_data_synced),
    .host_data_valid(host_data_valid_synced),
    .ready4_host_data(ready4_host_data_bfw),
    .kmer_valid(kmer_valid),
    .kmer(kmer),
    .kmer_length(kmer_length),
    .ready4Kmer(ready4Kmer),
    .queryResultValid(queryResultValid),
    .queryResult(queryResult),
    .idle(bf_idle),
    .avl_wdata(avl_wdata_bf),
    .avl_rdata(avl_rdata_bf),
    .avl_rdata_valid(avl_rdata_valid_bf),
    .avl_ready(avl_ready_bf),
    .wvalid(wvalid),
    .rvalid(rvalid),
    .raddr(raddr),
    .waddr(waddr)
);

assign ready4_host_data = (mode == SOLID_ISLANDS) ? ~readSeparatorFull : (mode == CORRECTION) ? ready4ReadCorrection : ready4_host_data_bfw;

//correct_errors_test #(
correctErrorsWrapped #(
    .NUM_BITS_NUM_UNITS(NUM_BITS_NUM_UNITS),
    .NUM_UNITS(NUM_UNITS),
    .MAX_READ_BIT_WIDTH(MAX_READ_BIT_WIDTH),
    .MAX_KMER_BIT_WIDTH(MAX_KMER_BIT_WIDTH),
    .EXTENSION_WIDTH(EXTENSION_WIDTH),
    .MAX_READ_WIDTH(MAX_READ_WIDTH),
    .MIN_READ_WIDTH(MIN_READ_WIDTH),
    .MAX_KMER_WIDTH(MAX_KMER_WIDTH),
    .MIN_KMER_WIDTH(MIN_KMER_WIDTH),
    .QUALITY_WIDTH(QUALITY_WIDTH),
    .NUM_CANDIDATES_BIT_WIDTH(NUM_CANDIDATES_BIT_WIDTH),
    .NUM_CANDIDATES(NUM_CANDIDATES)
) correction (
    .clk(pll_100MHz),
    .rstb(core_rstb_synced),
    .readLength(readLengthCorrection),
    .kmerLength(kmer_length),
    .read(readCorrection),
    .quality(qualityCorrection),
    .qualityThreshold(qualityThresholdCorrection),
    .readValid(readValidCorrection),
    .ready4Kmer(ready4KmerCorrection),
    .queryResult(queryResultCorrection),
    .queryResultValid(queryResultValidCorrection),
    .ready4Candidate(ready4CandidateCorrection),
    .startPosition(startPositionCorrection),
    .endPosition(endPositionCorrection),
    .ready4Read(ready4ReadCorrection),
    .kmerValid(kmerValidCorrection),
    .kmer(kmerCorrection),
    .candidate(candidateCorrection),
    .candidateValid(candidateValidCorrection),
    .candidateNum(candidateNumCorrection),
    .candidateNumValid(candidateNumValidCorrection),
    .inputRead(inputReadCorrection)
);

assign readCorrection             = host_data_synced[511:0];
assign qualityCorrection          = host_data_synced[1023:512];
assign readLengthCorrection       = read_length_lo_synced;
assign startPositionCorrection    = start_position_synced;
assign endPositionCorrection      = end_position_synced;
assign readValidCorrection        = host_data_valid_synced & (mode == CORRECTION);
assign ready4CandidateCorrection  = (mode == CORRECTION) ? ~afu_to_psl_sync_full : 1'b0;
assign queryResultCorrection      = queryResult;
assign queryResultValidCorrection = queryResultValid & (mode == CORRECTION);
assign ready4KmerCorrection       = ready4Kmer & (mode == CORRECTION);
assign qualityThresholdCorrection = threshold;

////////////////////////Synchronize between bloom filter and DDR3
assign cmd_fifo_full = (cmd_fifo_num_data >= 12);
assign avl_ready_bf = ~cmd_fifo_full;
assign cmd_fifo_rd  = avl_ready & ~data_fifo_full & ~token_fifo_full;

async_fifo cmd_fifo (
    .aclr(~core_rstb),
    .data({avl_wdata_bf,raddr,waddr,wvalid,rvalid}),
    .rdclk(afi_clk),
    .rdreq(cmd_fifo_rd),
    .wrclk(pll_100MHz),
    .wrreq((wvalid | rvalid) & ~cmd_fifo_full),
    .q({avl_wdata,cmd_fifo_raddr,cmd_fifo_waddr,avl_write_req_raw,avl_read_req_raw}),
    .rdempty(cmd_fifo_empty),
    .wrfull(),
    .wrusedw(cmd_fifo_num_data)
);

//Token FIFO - will be useful also when we use dual rank DDR - currently throttles reads to match rates
async_fifo #(
    .DATA_WIDTH(2),
    .NUM_WORDS(16),
    .LOG_NUM_WORDS(4)
) token_fifo (
    .aclr(~core_rstb),
    .data(2'b11),             //This is just dummy for now - use MSB of address when 2 DDR memories are available
    .rdclk(pll_100MHz),
    .rdreq(data_fifo_rd),
    .wrclk(afi_clk),
    .wrreq(cmd_fifo_rd & ~cmd_fifo_empty & avl_read_req_raw),
    .q(),                     //Dummy for now
    .rdempty(token_fifo_empty),
    .wrfull(),
    .wrusedw(token_fifo_usedw));

assign token_fifo_full = (token_fifo_usedw >= 12);

assign avl_rdata_valid_bf = ~data_fifo_empty;
assign data_fifo_full     = (data_fifo_num_data >= 12);  //2-cycle latency to num_words from write signal. This leaves 18 locations for any outstanding reads at the time. tokenFifo becomes full before that.
assign avl_write_req      = avl_write_req_raw & ~cmd_fifo_empty & ~data_fifo_full;

async_fifo #(
    .DATA_WIDTH(512),
    .NUM_WORDS(32),
    .LOG_NUM_WORDS(5)
) data_fifo (
    .aclr(~core_rstb),
    .data(avl_rdata),
    .rdclk(pll_100MHz),
    .rdreq(data_fifo_rd),
    .wrclk(afi_clk),
    .wrreq(avl_rdata_valid & (mode != DDR3_READ)),
    .q(data_fifo_q),
    .rdempty(data_fifo_empty),
    .wrfull(),
    .wrusedw(data_fifo_num_data)
);
assign avl_rdata_bf = data_fifo_q;
assign data_fifo_rd = ~data_fifo_empty;
//////////////////////////////////////////Synchronize between Bloom filter and DDR3 over

`ifndef SYNTHESIS
wire blah;
genvar m;
generate
    for (m = 0; m < 512; m=m+1) begin:xto0
        assign avl_rdata[m] = ((avl_rdata_prelim[m] !== 1'b1) && (avl_rdata_prelim[m] !== 1'b0)) ? 1'b0 : avl_rdata_prelim[m];
    end
endgenerate
`else
        assign avl_rdata = avl_rdata_prelim;
`endif

ddr3_a ddr3_mem (
/*input  wire        */ .pll_ref_clk(pll_ref_clk),
/*input  wire        */ .global_reset_n(global_reset_n),
/*input  wire        */ .soft_reset_n(soft_reset_n),
/*output wire        */ .afi_clk(afi_clk),
/*output wire        */ .afi_half_clk(afi_half_clk),
/*output wire        */ .afi_reset_n(afi_reset_n),
/*output wire        */ .afi_reset_export_n(afi_reset_export_n),
/*output wire [15:0] */ .mem_a(mem_a),
/*output wire [2:0]  */ .mem_ba(mem_ba),
/*output wire [0:0]  */ .mem_ck(mem_ck),
/*output wire [0:0]  */ .mem_ck_n(mem_ck_n),
/*output wire [0:0]  */ .mem_cke(mem_cke),
/*output wire [0:0]  */ .mem_cs_n(mem_cs_n),
/*output wire [8:0]  */ .mem_dm(mem_dm),
/*output wire [0:0]  */ .mem_ras_n(mem_ras_n),
/*output wire [0:0]  */ .mem_cas_n(mem_cas_n),
/*output wire [0:0]  */ .mem_we_n(mem_we_n),
/*output wire        */ .mem_reset_n(mem_reset_n),
/*inout  wire [71:0] */ .mem_dq(mem_dq),
/*inout  wire [8:0]  */ .mem_dqs(mem_dqs),
/*inout  wire [8:0]  */ .mem_dqs_n(mem_dqs_n),
/*output wire [0:0]  */ .mem_odt(mem_odt),
/*output wire        */ .avl_ready(avl_ready),
/*input  wire        */ .avl_burstbegin((mode == DDR3_INIT) ? init_burst_begin : avl_burstbegin),
/*input  wire [25:0] */ .avl_addr(      (mode == DDR3_INIT) ? init_addr        : avl_addr),
/*input  wire [511:0]*/ .avl_wdata(     (mode == DDR3_INIT) ? init_data        : avl_wdata),
/*input  wire        */ .avl_read_req(  (mode == DDR3_INIT) ? 1'b0             : avl_read_req),
/*input  wire        */ .avl_write_req( (mode == DDR3_INIT) ? init_write       : avl_write_req),
/*output wire        */ .avl_rdata_valid(avl_rdata_valid),
/*output wire [511:0]*/ .avl_rdata(avl_rdata_prelim),
/*input  wire [2:0]  */ .avl_size(avl_size),
/*output wire        */ .local_init_done(local_init_done),
/*output wire        */ .local_cal_success(local_cal_success),
/*output wire        */ .local_cal_fail(local_cal_fail),
/*input  wire        */ .oct_rzqin(oct_rzqin),
/*output wire        */ .pll_mem_clk(pll_mem_clk),
/*output wire        */ .pll_write_clk(pll_write_clk),
/*output wire        */ .pll_locked(pll_locked),
/*output wire        */ .pll_write_clk_pre_phy_clk(pll_write_clk_pre_phy_clk),
/*output wire        */ .pll_addr_cmd_clk(pll_addr_cmd_clk),
/*output wire        */ .pll_avl_clk(pll_avl_clk),
/*output wire        */ .pll_config_clk(pll_config_clk),
/*output wire        */ .pll_hr_clk(pll_hr_clk),
/*output wire        */ .pll_p2c_read_clk(pll_p2c_read_clk),
/*output wire        */ .pll_c2p_write_clk(pll_c2p_write_clk)
);

assign avl_size = 3'b001;

//DDR3 initialization circuitry
assign init_write       = (mode == DDR3_INIT) & (init_addr <  27'b100_0000_0000_0000_0000_0000_0000);
assign init_burst_begin = init_write & avl_ready;
assign ddr3_init_done   = (init_addr >= 27'b100_0000_0000_0000_0000_0000_0000);


always @(posedge afi_clk or negedge global_reset_n) begin
    if (~global_reset_n) begin
        init_addr <= 'b0;
    end
    else begin
        if (mode == DDR3_INIT) begin
            if (local_cal_success & ~local_cal_fail & local_init_done & pll_locked) begin
                if (avl_ready) begin
                    if (init_addr < 27'b100_0000_0000_0000_0000_0000_0000) init_addr <= init_addr + 1;
                end
            end
        end
        else begin
            init_addr = 'b0;
        end
    end
end

always @(posedge pll_ref_clk or negedge core_rstb) begin
    if (~core_rstb) begin
        rstb_pll_ref_clk1 <= 'h1;
        rstb_pll_ref_clk2 <= 'h0;
        global_reset_n    <= 'b1;
        soft_reset_n      <= 'b1;
    end
    else begin
        rstb_pll_ref_clk1 <= {rstb_pll_ref_clk1[2:0],1'b0};
        rstb_pll_ref_clk2 <= {rstb_pll_ref_clk2[2:0],rstb_pll_ref_clk1[3:2] == 2'b10};
        soft_reset_n       <= ~(|rstb_pll_ref_clk1);
        global_reset_n     <= ~(|rstb_pll_ref_clk2[4:1]);
    end
end


endmodule
