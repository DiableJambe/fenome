`timescale 1ns / 1ps
module pslCommand #(
    parameter Read_cl_s   = 'h0a50,
    parameter Read_cl_m   = 'h0a60,
    parameter Read_cl_lck = 'h0a6b,
    parameter Read_cl_res = 'h0a67,
    parameter touch_i     = 'h0240,
    parameter touch_s     = 'h0250,
    parameter touch_m     = 'h0260,
    parameter Write_mi    = 'h0d60,
    parameter Write_ms    = 'h0d70,
    parameter Write_unlock= 'h0d6b,
    parameter Write_c     = 'h0d67,
    parameter push_i      = 'h0140,
    parameter push_s      = 'h0150,
    parameter evict_s     = 'h1140,
    parameter lock        = 'h016b,
    parameter unlock      = 'h017b,
    parameter Read_cl_na  = 'h0a00,
    parameter Read_pna    = 'h0e00,
    parameter Write_na    = 'h0d00,
    parameter Write_inj   = 'h0d10,
    parameter flush       = 'h0100,
    parameter intreq      = 'h0000,
    parameter restart     = 'h0001,
    parameter DONE        = 'h00,
    parameter AERROR      = 'h01,
    parameter DERROR      = 'h03,
    parameter NLOCK       = 'h04,
    parameter NRES        = 'h05,
    parameter FLUSHED     = 'h06,
    parameter FAULT       = 'h07,
    parameter FAILED      = 'h08,
    parameter PAGED       = 'h0a,

    parameter CORRECTION    = 'b010,
    parameter SOLID_ISLANDS = 'b001,
    parameter PROGRAM       = 'b000,
    parameter DDR3_INIT     = 'b100,
    parameter DDR3_READ     = 'b101,
    parameter DDR3_WRITE    = 'b110
) (
    input clk,
    input rstb,
    input start,
    input [7:0] num_credits,                //From the Accelerator Control Interface
    input resp_valid,
    input [7:0] resp_tag,
    input resp_tag_par,
    input [7:0] resp_code,
    input [8:0] resp_credits,               //What is this???
    input [1:0] resp_cache_state,
    input [12:0] resp_cache_pos,
    output reg ah_cvalid,
    output reg [7:0] ah_ctag,
    output reg ah_ctagpar,
    output reg [12:0] ah_com,
    output reg ah_compar,
    output reg [2:0] ah_cabt,
    output reg [63:0] ah_cea,
    output reg ah_ceapar,
    output reg [15:0] ah_cch,
    output reg [11:0] ah_csize,

    //Control signals
    output abort,                           //Send to control interface
    output finished,                        //Send to control interface and external world
    input [31:0] num_items_to_process,      //Programmed value
    input [63:0] write_base_address,        //Programmed credits
    input [63:0] read_base_address,         //Programmed credits
    input wbuffer_item_available,           //From buffer interface FIFO
    input [5:0] num_sub_items_per_item,     //From buffer interface FIFO
    output write_cmd_issued,                //To buffer interface FIFO
    input reset_cmd_received,               //Signal from PSL Control interface
    input [2:0] mode,                       //Signal output for various purposes
    output [7:0] free_location,             //Address to be freed in the write buffer
    output free_signal,                     //Signal to free address in write buffer
    output [31:0] num_reads_read_active,    //Number of reads read from the host
    output [31:0] num_reads_written_active, //Number of reads written into the host
    output psl_read_state,                  //Signal to indicate that current state is READ - required by buffer
    output psl_idle_state,                  //Signal to indicate that current state is IDLE - required by buffer
    input last_workload,                    //Signal indicating that this is the final workload
    output finish,                          //Indicating that the finish state has been reached - this will be used by the MMIO
    input units_idle,                       //Signal indicating that all functional units in the AFU are idle
    input input_buffer_empty,               //Input buffer is empty so if you want you can continue to read other stuff
    output reg [9:0] iteration_limit,       //The number of read-buffer items in the present iteration
    output reg avl_read_req,                //DDR3 interface read request
    output reg [29:0] avl_addr,             //DDR3 interface address
    input avl_ready,                        //DDR3 interface ready
    input [31:0] ddr3_base_address          //Base address from which to start DDR3 reads or writes
);

////State definitions
//Main state machine
localparam IDLE             = 4'b0111;
localparam READ             = 4'b0000;
localparam READ_IDLE        = 4'b0100;
localparam WRITE            = 4'b0001;
localparam WRITE_IDLE       = 4'b0101;
localparam ERROR            = 4'b0010;
localparam FINISH           = 4'b0110;
localparam WAIT_FOR_RESET   = 4'b1000;
localparam ABORT            = 4'b1010;
localparam SETUP_READ_STATE = 4'b1011;
//ERR state machine
localparam ERR_WAIT         = 3'b000;
localparam ERR_RESET        = 3'b001;
localparam ERR_RESET_ISSUED = 3'b010;
localparam ERR_REISSUE      = 3'b011;
localparam ERR_WAIT_REISSUE = 3'b100;
localparam PAGING_LIMIT     = 16;

//Internal wires and register definition
reg cmd_valid;
reg [7:0] cmd_tag;
wire cmd_tagpar;
reg [12:0] cmd;
wire cmd_par;
wire [2:0] cabt;
reg [63:0] addr;
wire addr_par;
wire [15:0] cch;
wire [11:0] size;
wire [6:0] wtag;
wire [6:0] rtag;
reg [3:0] state; 
reg pastError;   
reg [7:0] credits_left;
reg [3:0] state_ns;
reg [31:0] num_items_read;
reg [31:0] num_items_written;
wire [7:0] err_fifo_tag;
wire err_fifo_full;
wire err_fifo_empty;
wire err_fifo_rd;
reg [2:0] err_sm;
reg [2:0] err_sm_ns;
reg [3:0] restoreState;
wire read_cmd;
reg [8:0] items_read_in_current_state;
wire write_cmd;
reg [8:0] items_written_in_current_state;
reg [8:0] sub_items_written;
wire err_fifo_valid;
reg [63:0] addr_buffer[0:255];
reg [63:0] addr_from_buffer;
reg [7:0] err_fifo_tag_del;
reg cmd_valid_err;
reg [3:0] restoreState_ns;
wire [31:0] projected_num_buffer_items;
wire [31:0] iteration_limit_comb;
reg [31:0] num_paged;
reg [9:0] num_ddr_items_read;

//Flop out all PSL interface signals to help timing
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        {ah_cvalid, ah_ctag, ah_ctagpar, ah_com, ah_compar, ah_cabt, ah_cea, ah_ceapar, ah_cch, ah_csize} <= 120'b0;
    end
    else begin
        {ah_cvalid, ah_ctag, ah_ctagpar, ah_com, ah_compar, ah_cabt, ah_cea, ah_ceapar, ah_cch, ah_csize} <=
                 {cmd_valid, cmd_tag, cmd_tagpar, cmd, cmd_par, cabt, addr, addr_par, cch, size};
    end
end

//Find out the number of buffer items to be read out
     //In correction mode, each item is a read and a quality score - that is 4 cache lines. Thus 4 * 2 buffer lines per item here.
     //In other modes, each item is 2 cache lines. That is 2 * 2 buffer lines per item.
assign projected_num_buffer_items = (mode == CORRECTION) ? {(num_items_to_process - num_items_read), 2'b0, 1'b0} : {(num_items_to_process - num_items_read),1'b0,1'b0};
assign iteration_limit_comb       = (projected_num_buffer_items >= 512) ? 512 : projected_num_buffer_items;

//Flop the actual output
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        iteration_limit <= 10'b0;
    end
    else begin
        if (state == SETUP_READ_STATE) begin //SETUP_READ_STATE may have to be extended to accomodate timing
            iteration_limit <= iteration_limit_comb;
        end
    end
end

//How many times is the current block paged
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        num_paged <= 'b0;
    end
    else begin
        if (state_ns != ERROR) begin
            num_paged <= 'b0;
        end
        else begin
            if (num_paged != PAGING_LIMIT) begin
                if (resp_valid & ((resp_code == PAGED) || (resp_code == FAULT))) begin
                    num_paged <= num_paged + 1;
                end
            end
        end
    end
end

//Free signal
assign free_signal    = resp_valid & (resp_code == DONE) & (
                                    (state == WRITE) || (state == WRITE_IDLE) ||
                                    ((state == ERROR) & ((restoreState == WRITE) || (restoreState == WRITE_IDLE)) & ((err_sm == ERR_WAIT) || (err_sm == ERR_REISSUE) || (err_sm == ERR_WAIT_REISSUE)))
                                                             );
assign free_location  = resp_tag;

//State signals to send out
assign psl_read_state = ((state == READ) || ((state == ERROR) && (restoreState == READ)));
assign psl_idle_state = (state == IDLE);

//Track number of reads written and read
assign num_reads_written_active = num_items_written;
assign num_reads_read_active    = num_items_read;

//Manage credits
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        credits_left <= 8'b0;
    end
    else begin
        if (state != IDLE) begin
            if (cmd_valid) begin
                if (~resp_valid) begin
                    credits_left <= credits_left - 1;
                end
            end
            else begin
                if (resp_valid) begin
                    credits_left <= credits_left + 1;
                end
            end
        end
        else begin
            credits_left <= num_credits;
        end
    end
end

wire increment_num_items_read    = ((mode == CORRECTION) ? items_read_in_current_state[1:0] == 2'b11 : items_read_in_current_state[0] == 1) & cmd_valid & read_cmd;
wire increment_num_items_written = (state == WRITE) & write_cmd & (items_written_in_current_state[0] == 1) & (sub_items_written == num_sub_items_per_item - 1);

//Reading data from processor - there can be 256 bytes or 512 bytes of data to be read, depending on the mode
               //256 bytes = 2 cache lines (2048 bits). 512 bytes = 4 cache lines
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        num_items_read              <= 32'b0;
        items_read_in_current_state <= 9'b0;
    end
    else begin
        if (state == READ) begin
            if (read_cmd) begin
                if (increment_num_items_read) begin
                    num_items_read <= num_items_read + 1;
                end
                items_read_in_current_state <= items_read_in_current_state + 1;
            end
        end
        else begin
            if (state != ERROR) begin
                items_read_in_current_state <= 9'b0; 
            end
            if ((state == FINISH) || (state == IDLE)) begin
                num_items_read <= 32'b0;
            end
        end
    end
end

//Writing data to processor - always only 256 bytes to write back per sub-item (2048 bits = 2 cache lines)
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        sub_items_written <= 9'b0;
        items_written_in_current_state <= 9'b0;
        num_items_written <= 'b0;
    end
    else begin
        if (state == WRITE) begin
            if (write_cmd) begin
                if (items_written_in_current_state[0] == 1) begin
                    if (sub_items_written == num_sub_items_per_item - 1) begin
                        num_items_written <= num_items_written + 1;
                        sub_items_written <= 9'b0;
                    end
                    else begin
                        sub_items_written <= sub_items_written + 1;
                    end
                end
                items_written_in_current_state <= items_written_in_current_state + 1;
            end
        end
        else begin
            if ((state == FINISH) || (state == IDLE)) begin
                num_items_written <= 'b0;
                items_written_in_current_state <= 9'b0;   //Reset later - write state doesn't depend on this
            end
        end
    end
end

assign write_cmd_issued = write_cmd;

//When to finish the workload
assign finish    = (state == FINISH);

//When to abort the workload - when an error happens when re-issuing the commands
assign abort     = (state == ABORT);

//When to write, and when not to write
assign read_cmd  = (state == READ) && (credits_left >= num_credits - 4) && (num_items_read < num_items_to_process) && (items_read_in_current_state < 256);
assign write_cmd = (state == WRITE) && (credits_left >= num_credits - 4) && (wbuffer_item_available) && (num_items_written < ((mode == DDR3_READ) ? 128 : num_items_read));

wire [63:0] val = {num_items_read, items_read_in_current_state[0], 7'b0};
//Drive command - there is combinational delay in these outputs
//always @* begin
always_comb begin
    case (state)
        READ : begin
            cmd_valid <= read_cmd;
            cmd_tag   <= items_read_in_current_state[7:0];
            cmd       <= Read_cl_na;
            if (mode == CORRECTION) begin
                addr  <= read_base_address + {num_items_read, items_read_in_current_state[1:0], 7'b0};
                                     //Each item is 4 cache lines = 512 byte addresses
            end
            else begin
                addr  <= read_base_address + {num_items_read, items_read_in_current_state[0], 7'b0};
                                     //Each item is 2 cache lines = 256 byte addresses
            end
        end
        WRITE: begin
            cmd_valid <= write_cmd;
            cmd_tag   <= items_written_in_current_state[7:0];
            cmd       <= Write_na; 
 
            if (mode == CORRECTION) begin
                addr  <= write_base_address + {num_items_written, sub_items_written[4:0], items_written_in_current_state[0], 7'b0};
                                      //Each item is 32 candidates = 64 cache lines = 8192 byte addresses
                                         //5-bits for sub-items
                                           //Each sub-item is 2 cache-lines
            end
            else begin
                addr  <= write_base_address + {num_items_written, items_written_in_current_state[0], 7'b0};
                                      //Each items is 256 bytes = 2 cache lines
            end
        end
        ERROR: begin
            cmd_tag   <= err_fifo_tag_del;
            addr      <= addr_from_buffer;

            case (err_sm)
                ERR_RESET : begin
                    cmd_valid <= (credits_left != 0);
                    cmd       <= restart;
                end
                ERR_REISSUE : begin
                    cmd_valid <= cmd_valid_err;
                    cmd       <= ((restoreState == READ) || (restoreState == READ_IDLE)) ? Read_cl_na : Write_na;
                end
                default : begin
                    cmd_valid <= 1'b0;
                    cmd       <= Read_cl_na;
                end
            endcase
        end
        default: begin //WAIT_FOR_RESET is folded in here
            cmd_valid <= 1'b0;
            cmd_tag   <= items_read_in_current_state[7:0];
            cmd       <= Read_cl_na;
            addr      <= 64'h0;
        end
    endcase
end

//State stuff
//always @* begin
always_comb begin
    case(state)
        IDLE : begin
            if (start) begin //full_if
                if (mode != DDR3_READ) begin //full_if
                    state_ns <= SETUP_READ_STATE;
                end
                else begin
                    state_ns <= WRITE;
                end
            end
            else begin
                state_ns <= state;
            end
            err_sm_ns       <= ERR_WAIT;
            restoreState_ns <= IDLE;
        end
        READ: begin
            if (reset_cmd_received) begin //full_if
                state_ns        <= WAIT_FOR_RESET;
                err_sm_ns       <= ERR_WAIT;
                restoreState_ns <= IDLE;
            end
            else begin
                if (resp_valid & (resp_code != DONE)) begin //full_if
                    if ((resp_code == PAGED) || (resp_code == FAULT)) begin //full_if
                        state_ns     <= ERROR;
                    end
                    else begin
                        state_ns     <= ABORT;
                    end
                end
                else begin
                    if ( //full_if
                        (items_read_in_current_state > 255) ||                //For returning from an error state
                        (num_items_read > num_items_to_process) ||            //For returning from an error state
                        ((items_read_in_current_state == 255) & cmd_valid) || 
                        ((num_items_read == num_items_to_process - 1) & increment_num_items_read)
                    ) begin
                        state_ns <= READ_IDLE;
                    end
                    else begin
                        state_ns <= state;
                    end
                end
                err_sm_ns       <= ERR_WAIT;
                restoreState_ns <= READ;
            end
        end
        READ_IDLE: begin //Wait for all reads to complete
            if (reset_cmd_received) begin //full_if
                state_ns        <= WAIT_FOR_RESET;
                err_sm_ns       <= ERR_WAIT;
                restoreState_ns <= IDLE;
            end
            else begin
                if (resp_valid & (resp_code != DONE)) begin //full_if
                    if ((resp_code == PAGED) || (resp_code == FAULT)) begin //full_if
                        state_ns     <= ERROR;
                    end
                    else begin
                        state_ns     <= ABORT;
                    end
                end
                else begin
                    if (credits_left == num_credits) begin //full_if
                        if (mode != PROGRAM) begin //full_if
                            state_ns <= WRITE;
                        end
                        else begin
                            if (num_items_read != num_items_to_process) begin //full_if
                                if (input_buffer_empty) begin //full_if
                                    state_ns <= SETUP_READ_STATE;
                                end
                                else begin
                                    state_ns <= state;
                                end
                            end
                            else begin
                                if (units_idle) begin //full_if
                                    state_ns <= FINISH;
                                end
                                else begin
                                    state_ns <= state;
                                end
                            end
                        end
                    end
                    else begin
                        state_ns <= state;
                    end
                end
                err_sm_ns       <= ERR_WAIT;
                restoreState_ns <= READ_IDLE;
            end
        end
        WRITE: begin
            if (reset_cmd_received) begin //full_if
                state_ns        <= WAIT_FOR_RESET;
                err_sm_ns       <= ERR_WAIT;
                restoreState_ns <= IDLE;
            end
            else begin
                if (resp_valid & (resp_code != DONE)) begin //full_if
                    if ((resp_code == PAGED) || (resp_code == FAULT)) begin //full_if
                        state_ns     <= ERROR;
                    end
                    else begin
                        state_ns     <= ABORT;
                    end
                end
                else begin
                    if (mode == DDR3_READ) begin //full_if
                        if ( //full_if
                               (num_items_written >= 128) ||
                               ((num_items_written == 127) & increment_num_items_written)
                        ) begin
                            state_ns <= WRITE_IDLE;
                        end
                        else begin
                            state_ns <= state;
                        end
                    end
                    else begin
                        if ( //full_if
                                 (num_items_written >= num_items_read) || //For returning from an error state
                                 ((num_items_written == num_items_read - 1) & increment_num_items_written)
                        ) begin
                            state_ns <= WRITE_IDLE;
                        end
                        else begin
                            state_ns <= state;
                        end
                    end
                end
                err_sm_ns       <= ERR_WAIT;
                restoreState_ns <= WRITE;
            end
        end
        WRITE_IDLE: begin
            if (reset_cmd_received) begin //full_if
                state_ns        <= WAIT_FOR_RESET;
                err_sm_ns       <= ERR_WAIT;
                restoreState_ns <= IDLE;
            end
            else begin
                if (resp_valid & (resp_code != DONE)) begin //full_if
                    if ((resp_code == PAGED) || (resp_code == FAULT)) begin //full_if
                        state_ns     <= ERROR;
                    end
                    else begin
                        state_ns     <= ABORT;
                    end
                end
                else begin
                    if (credits_left == num_credits) begin //full_if
                        if ((num_items_written == num_items_to_process) || (mode == DDR3_READ)) begin //full_if
                            state_ns <= FINISH;
                        end
                        else begin
                            state_ns <= SETUP_READ_STATE;
                        end
                    end
                    else begin
                        state_ns <= state;
                    end
                end
                err_sm_ns       <= ERR_WAIT;
                restoreState_ns <= WRITE_IDLE;
            end
        end
        ERROR: begin
            if (reset_cmd_received) begin //full_if
                state_ns        <= WAIT_FOR_RESET;
                err_sm_ns       <= ERR_WAIT;
                restoreState_ns <= IDLE;
            end
            else begin //TBD: What about FAILED etc during ERR_WAIT etc
                case(err_sm)
                    ERR_WAIT : begin       //Wait for all credits to be returned
                        if (credits_left == num_credits) begin //full_if
                            err_sm_ns <= ERR_RESET;
                            state_ns  <= ERROR;
                        end
                        else begin
                            err_sm_ns <= err_sm;
                            state_ns  <= state;
                        end
                    end
                    ERR_RESET : begin      //Send reset command
                        err_sm_ns <= ERR_RESET_ISSUED;
                        state_ns  <= ERROR;
                    end
                    ERR_RESET_ISSUED : begin //Wait for reset response
                        if (resp_valid && (resp_code != DONE)) begin //full_if
                            if ((resp_code == PAGED) || (resp_code == FAULT)) begin //full_if
                                if (num_paged == PAGING_LIMIT) begin //full_if
                                    state_ns  <= ABORT;
                                    err_sm_ns <= ERR_WAIT;
                                end
                                else begin
                                    state_ns  <= state;
                                    err_sm_ns <= ERR_WAIT;
                                end
                            end
                            else begin
                                state_ns  <= ABORT;
                                err_sm_ns <= ERR_WAIT;
                            end
                        end
                        else begin
                            if (resp_valid && (resp_code == DONE)) begin //full_if
                                err_sm_ns <= ERR_REISSUE;
                                state_ns  <= ERROR;
                            end
                            else begin
                                err_sm_ns <= err_sm;
                                state_ns  <= state;
                            end
                        end
                    end
                    ERR_REISSUE : begin    //Reissue all the commands until the error fifo is empty
                        if (resp_valid && (resp_code != DONE)) begin //full_if
                            if ((resp_code == PAGED) || (resp_code == FAULT)) begin //full_if
                                if (num_paged == PAGING_LIMIT) begin //full_if
                                    state_ns  <= ABORT;
                                    err_sm_ns <= ERR_WAIT;
                                end
                                else begin
                                    state_ns  <= state;
                                    err_sm_ns <= ERR_WAIT;
                                end
                            end
                            else begin
                                state_ns  <= ABORT;
                                err_sm_ns <= ERR_WAIT;
                            end
                        end
                        else begin
                            if (err_fifo_empty) begin //full_if
                                err_sm_ns <= ERR_WAIT_REISSUE; 
                                state_ns  <= ERROR;
                            end
                            else begin
                                err_sm_ns <= err_sm;
                                state_ns  <= state;
                            end
                        end
                    end
                    ERR_WAIT_REISSUE : begin     //Wait for all reissued commands to complete before proceeding
                        if (resp_valid && (resp_code != DONE)) begin //full_if
                            if ((resp_code == PAGED) || (resp_code == FAULT)) begin //full_if
                                if (num_paged == PAGING_LIMIT) begin //full_if
                                    state_ns  <= ABORT;
                                    err_sm_ns <= ERR_WAIT;
                                end
                                else begin
                                    state_ns  <= state;
                                    err_sm_ns <= ERR_WAIT;
                                end
                            end
                            else begin
                                state_ns  <= ABORT;
                                err_sm_ns <= ERR_WAIT;
                            end
                        end
                        else begin
                            if (credits_left == num_credits) begin //full_if
                                err_sm_ns <= ERR_WAIT;
                                state_ns  <= restoreState;
                            end
                            else begin
                                err_sm_ns <= err_sm;
                                state_ns  <= state;
                            end
                        end
                    end
                    default : begin
                        err_sm_ns <= err_sm;
                        state_ns  <= state;
                    end
                endcase
                restoreState_ns <= restoreState;
            end
        end
        WAIT_FOR_RESET : begin
            state_ns        <= (credits_left == num_credits) ? IDLE : WAIT_FOR_RESET;
            err_sm_ns       <= ERR_WAIT;
            restoreState_ns <= WAIT_FOR_RESET;
        end
        SETUP_READ_STATE : begin
            state_ns        <= READ;
            err_sm_ns       <= ERR_WAIT;
            restoreState_ns <= SETUP_READ_STATE;
        end
        default: begin //Also handles the FINISH and ABORT states
            state_ns        <= IDLE;
            err_sm_ns       <= ERR_WAIT;
            restoreState_ns <= IDLE;
        end
    endcase
end

//The actual flop state machines
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        state        <= IDLE;
        err_sm       <= ERR_WAIT;
        restoreState <= IDLE;
    end
    else begin
        state        <= state_ns;
        err_sm       <= err_sm_ns;
        restoreState <= restoreState_ns;
    end
end

//Capture the erroneous responses
synchronousFifo #(
    .DATA_WIDTH(8),
    .FIFO_DEPTH(256),
    .APPARENT_DEPTH(254),
    .POINTER_SIZE(9)
) err_fifo (
    .clk(clk),
    .rstb(rstb),
    .fifoFull(err_fifo_full),
    .fifoEmpty(err_fifo_empty),
    .valid(err_fifo_valid),
    .data(resp_tag),
    .out(err_fifo_tag),
    .read(err_fifo_rd)
);

assign err_fifo_rd    = (state == ERROR) & (err_sm == ERR_REISSUE) & ~err_fifo_empty & (credits_left > num_credits - 1); //Do this one by one
assign err_fifo_valid = resp_valid & ((resp_code == AERROR) || (resp_code == DERROR) || (resp_code == PAGED) || (resp_code == FLUSHED));

//Buffer for addresses with tags
always @(posedge clk) begin
    if (cmd_valid & (state != ERROR)) begin
        addr_buffer[cmd_tag] <= addr;
    end
end

//Read out the address buffer
always @(posedge clk) begin
    //if (err_fifo_rd) begin - always read the memory
        addr_from_buffer <= addr_buffer[err_fifo_tag];
    //end
end

//Actual cmd_valid during error
always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        err_fifo_tag_del <= 8'b0;
        cmd_valid_err    <= 1'b0;
    end
    else begin
        err_fifo_tag_del <= err_fifo_tag;
        cmd_valid_err    <= err_fifo_rd;
    end
end

//Parities
//xorTree #(.BIT_WIDTH(3)) tagparity(.signal(cmd_tag), .par(cmd_tagpar));
//xorTree #(.BIT_WIDTH(3)) cmdparity(.signal(cmd), .par(cmd_par));
//xorTree #(.BIT_WIDTH(6)) addrparity(.signal(addr), .par(addrpar));
assign cmd_tagpar = 'b0;
assign cmd_par    = 'b0;
assign addr_par   = 'b0;

//Driven to 0 for "Strict" Translation ordering
assign cabt = 2'b00;
assign cch  = 'b0;
assign size = 128;

assign finished = finish & last_workload;

always @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        num_ddr_items_read <= 'b0;
        avl_read_req <= 1'b0;
        avl_addr <= 'b0;
    end
    else begin
        if (mode == DDR3_READ) begin
            if ((state == WRITE) || ((state == ERROR) && (restoreState == WRITE))) begin
                if (avl_read_req) begin //Do not pulse it on two consecutive cycles - always make only one request after checking it is ready
                    avl_read_req <= 1'b0;
                    num_ddr_items_read <= num_ddr_items_read + 1;
                end
                else begin
                    if (num_ddr_items_read < 512) begin
                        if (avl_ready) begin
                            avl_read_req       <= 1'b1;
                            avl_addr           <= ddr3_base_address + num_ddr_items_read;
                        end
                    end
                end
            end
            else begin
                num_ddr_items_read <= 'b0;
            end
        end
        else begin
            num_ddr_items_read <= 'b0;
        end
    end
end

`ifndef SYNTHESIS
wire [63:0] addr_buffer0x0 = addr_buffer[0];
wire [63:0] addr_buffer0x1 = addr_buffer[1];
wire [63:0] addr_buffer0x2 = addr_buffer[2];
wire [63:0] addr_buffer0x3 = addr_buffer[3];
wire [63:0] addr_buffer0x4 = addr_buffer[4];
wire [63:0] addr_buffer0x5 = addr_buffer[5];
wire [63:0] addr_buffer0x6 = addr_buffer[6];
wire [63:0] addr_buffer0x7 = addr_buffer[7];
wire [63:0] addr_buffer0x8 = addr_buffer[8];
wire [63:0] addr_buffer0x9 = addr_buffer[9];
wire [63:0] addr_buffer0xa = addr_buffer[10];
wire [63:0] addr_buffer0xb = addr_buffer[11];
wire [63:0] addr_buffer0xc = addr_buffer[12];
wire [63:0] addr_buffer0xd = addr_buffer[13];
wire [63:0] addr_buffer0xe = addr_buffer[14];
wire [63:0] addr_buffer0xf = addr_buffer[15];
wire [63:0] addr_buffer0x10 = addr_buffer[16];
wire [63:0] addr_buffer0x11 = addr_buffer[17];
wire [63:0] addr_buffer0x12 = addr_buffer[18];
wire [63:0] addr_buffer0x13 = addr_buffer[19];
wire [63:0] addr_buffer0x14 = addr_buffer[20];
wire [63:0] addr_buffer0x15 = addr_buffer[21];
wire [63:0] addr_buffer0x16 = addr_buffer[22];
wire [63:0] addr_buffer0x17 = addr_buffer[23];
wire [63:0] addr_buffer0x18 = addr_buffer[24];
wire [63:0] addr_buffer0x19 = addr_buffer[25];
wire [63:0] addr_buffer0x1a = addr_buffer[26];
wire [63:0] addr_buffer0x1b = addr_buffer[27];
wire [63:0] addr_buffer0x1c = addr_buffer[28];
wire [63:0] addr_buffer0x1d = addr_buffer[29];
wire [63:0] addr_buffer0x1e = addr_buffer[30];
wire [63:0] addr_buffer0x1f = addr_buffer[31];
wire [63:0] addr_buffer0x20 = addr_buffer[32];
wire [63:0] addr_buffer0x21 = addr_buffer[33];
wire [63:0] addr_buffer0x22 = addr_buffer[34];
wire [63:0] addr_buffer0x23 = addr_buffer[35];
wire [63:0] addr_buffer0x24 = addr_buffer[36];
wire [63:0] addr_buffer0x25 = addr_buffer[37];
wire [63:0] addr_buffer0x26 = addr_buffer[38];
wire [63:0] addr_buffer0x27 = addr_buffer[39];
wire [63:0] addr_buffer0x28 = addr_buffer[40];
wire [63:0] addr_buffer0x29 = addr_buffer[41];
wire [63:0] addr_buffer0x2a = addr_buffer[42];
wire [63:0] addr_buffer0x2b = addr_buffer[43];
wire [63:0] addr_buffer0x2c = addr_buffer[44];
wire [63:0] addr_buffer0x2d = addr_buffer[45];
wire [63:0] addr_buffer0x2e = addr_buffer[46];
wire [63:0] addr_buffer0x2f = addr_buffer[47];
wire [63:0] addr_buffer0x30 = addr_buffer[48];
wire [63:0] addr_buffer0x31 = addr_buffer[49];
wire [63:0] addr_buffer0x32 = addr_buffer[50];
wire [63:0] addr_buffer0x33 = addr_buffer[51];
wire [63:0] addr_buffer0x34 = addr_buffer[52];
wire [63:0] addr_buffer0x35 = addr_buffer[53];
wire [63:0] addr_buffer0x36 = addr_buffer[54];
wire [63:0] addr_buffer0x37 = addr_buffer[55];
wire [63:0] addr_buffer0x38 = addr_buffer[56];
wire [63:0] addr_buffer0x39 = addr_buffer[57];
wire [63:0] addr_buffer0x3a = addr_buffer[58];
wire [63:0] addr_buffer0x3b = addr_buffer[59];
wire [63:0] addr_buffer0x3c = addr_buffer[60];
wire [63:0] addr_buffer0x3d = addr_buffer[61];
wire [63:0] addr_buffer0x3e = addr_buffer[62];
wire [63:0] addr_buffer0x3f = addr_buffer[63];
wire [63:0] addr_buffer0x40 = addr_buffer[64];
wire [63:0] addr_buffer0x41 = addr_buffer[65];
wire [63:0] addr_buffer0x42 = addr_buffer[66];
wire [63:0] addr_buffer0x43 = addr_buffer[67];
wire [63:0] addr_buffer0x44 = addr_buffer[68];
wire [63:0] addr_buffer0x45 = addr_buffer[69];
wire [63:0] addr_buffer0x46 = addr_buffer[70];
wire [63:0] addr_buffer0x47 = addr_buffer[71];
wire [63:0] addr_buffer0x48 = addr_buffer[72];
wire [63:0] addr_buffer0x49 = addr_buffer[73];
wire [63:0] addr_buffer0x4a = addr_buffer[74];
wire [63:0] addr_buffer0x4b = addr_buffer[75];
wire [63:0] addr_buffer0x4c = addr_buffer[76];
wire [63:0] addr_buffer0x4d = addr_buffer[77];
wire [63:0] addr_buffer0x4e = addr_buffer[78];
wire [63:0] addr_buffer0x4f = addr_buffer[79];
wire [63:0] addr_buffer0x50 = addr_buffer[80];
wire [63:0] addr_buffer0x51 = addr_buffer[81];
wire [63:0] addr_buffer0x52 = addr_buffer[82];
wire [63:0] addr_buffer0x53 = addr_buffer[83];
wire [63:0] addr_buffer0x54 = addr_buffer[84];
wire [63:0] addr_buffer0x55 = addr_buffer[85];
wire [63:0] addr_buffer0x56 = addr_buffer[86];
wire [63:0] addr_buffer0x57 = addr_buffer[87];
wire [63:0] addr_buffer0x58 = addr_buffer[88];
wire [63:0] addr_buffer0x59 = addr_buffer[89];
wire [63:0] addr_buffer0x5a = addr_buffer[90];
wire [63:0] addr_buffer0x5b = addr_buffer[91];
wire [63:0] addr_buffer0x5c = addr_buffer[92];
wire [63:0] addr_buffer0x5d = addr_buffer[93];
wire [63:0] addr_buffer0x5e = addr_buffer[94];
wire [63:0] addr_buffer0x5f = addr_buffer[95];
wire [63:0] addr_buffer0x60 = addr_buffer[96];
wire [63:0] addr_buffer0x61 = addr_buffer[97];
wire [63:0] addr_buffer0x62 = addr_buffer[98];
wire [63:0] addr_buffer0x63 = addr_buffer[99];
wire [63:0] addr_buffer0x64 = addr_buffer[100];
wire [63:0] addr_buffer0x65 = addr_buffer[101];
wire [63:0] addr_buffer0x66 = addr_buffer[102];
wire [63:0] addr_buffer0x67 = addr_buffer[103];
wire [63:0] addr_buffer0x68 = addr_buffer[104];
wire [63:0] addr_buffer0x69 = addr_buffer[105];
wire [63:0] addr_buffer0x6a = addr_buffer[106];
wire [63:0] addr_buffer0x6b = addr_buffer[107];
wire [63:0] addr_buffer0x6c = addr_buffer[108];
wire [63:0] addr_buffer0x6d = addr_buffer[109];
wire [63:0] addr_buffer0x6e = addr_buffer[110];
wire [63:0] addr_buffer0x6f = addr_buffer[111];
wire [63:0] addr_buffer0x70 = addr_buffer[112];
wire [63:0] addr_buffer0x71 = addr_buffer[113];
wire [63:0] addr_buffer0x72 = addr_buffer[114];
wire [63:0] addr_buffer0x73 = addr_buffer[115];
wire [63:0] addr_buffer0x74 = addr_buffer[116];
wire [63:0] addr_buffer0x75 = addr_buffer[117];
wire [63:0] addr_buffer0x76 = addr_buffer[118];
wire [63:0] addr_buffer0x77 = addr_buffer[119];
wire [63:0] addr_buffer0x78 = addr_buffer[120];
wire [63:0] addr_buffer0x79 = addr_buffer[121];
wire [63:0] addr_buffer0x7a = addr_buffer[122];
wire [63:0] addr_buffer0x7b = addr_buffer[123];
wire [63:0] addr_buffer0x7c = addr_buffer[124];
wire [63:0] addr_buffer0x7d = addr_buffer[125];
wire [63:0] addr_buffer0x7e = addr_buffer[126];
wire [63:0] addr_buffer0x7f = addr_buffer[127];
wire [63:0] addr_buffer0x80 = addr_buffer[128];
wire [63:0] addr_buffer0x81 = addr_buffer[129];
wire [63:0] addr_buffer0x82 = addr_buffer[130];
wire [63:0] addr_buffer0x83 = addr_buffer[131];
wire [63:0] addr_buffer0x84 = addr_buffer[132];
wire [63:0] addr_buffer0x85 = addr_buffer[133];
wire [63:0] addr_buffer0x86 = addr_buffer[134];
wire [63:0] addr_buffer0x87 = addr_buffer[135];
wire [63:0] addr_buffer0x88 = addr_buffer[136];
wire [63:0] addr_buffer0x89 = addr_buffer[137];
wire [63:0] addr_buffer0x8a = addr_buffer[138];
wire [63:0] addr_buffer0x8b = addr_buffer[139];
wire [63:0] addr_buffer0x8c = addr_buffer[140];
wire [63:0] addr_buffer0x8d = addr_buffer[141];
wire [63:0] addr_buffer0x8e = addr_buffer[142];
wire [63:0] addr_buffer0x8f = addr_buffer[143];
wire [63:0] addr_buffer0x90 = addr_buffer[144];
wire [63:0] addr_buffer0x91 = addr_buffer[145];
wire [63:0] addr_buffer0x92 = addr_buffer[146];
wire [63:0] addr_buffer0x93 = addr_buffer[147];
wire [63:0] addr_buffer0x94 = addr_buffer[148];
wire [63:0] addr_buffer0x95 = addr_buffer[149];
wire [63:0] addr_buffer0x96 = addr_buffer[150];
wire [63:0] addr_buffer0x97 = addr_buffer[151];
wire [63:0] addr_buffer0x98 = addr_buffer[152];
wire [63:0] addr_buffer0x99 = addr_buffer[153];
wire [63:0] addr_buffer0x9a = addr_buffer[154];
wire [63:0] addr_buffer0x9b = addr_buffer[155];
wire [63:0] addr_buffer0x9c = addr_buffer[156];
wire [63:0] addr_buffer0x9d = addr_buffer[157];
wire [63:0] addr_buffer0x9e = addr_buffer[158];
wire [63:0] addr_buffer0x9f = addr_buffer[159];
wire [63:0] addr_buffer0xa0 = addr_buffer[160];
wire [63:0] addr_buffer0xa1 = addr_buffer[161];
wire [63:0] addr_buffer0xa2 = addr_buffer[162];
wire [63:0] addr_buffer0xa3 = addr_buffer[163];
wire [63:0] addr_buffer0xa4 = addr_buffer[164];
wire [63:0] addr_buffer0xa5 = addr_buffer[165];
wire [63:0] addr_buffer0xa6 = addr_buffer[166];
wire [63:0] addr_buffer0xa7 = addr_buffer[167];
wire [63:0] addr_buffer0xa8 = addr_buffer[168];
wire [63:0] addr_buffer0xa9 = addr_buffer[169];
wire [63:0] addr_buffer0xaa = addr_buffer[170];
wire [63:0] addr_buffer0xab = addr_buffer[171];
wire [63:0] addr_buffer0xac = addr_buffer[172];
wire [63:0] addr_buffer0xad = addr_buffer[173];
wire [63:0] addr_buffer0xae = addr_buffer[174];
wire [63:0] addr_buffer0xaf = addr_buffer[175];
wire [63:0] addr_buffer0xb0 = addr_buffer[176];
wire [63:0] addr_buffer0xb1 = addr_buffer[177];
wire [63:0] addr_buffer0xb2 = addr_buffer[178];
wire [63:0] addr_buffer0xb3 = addr_buffer[179];
wire [63:0] addr_buffer0xb4 = addr_buffer[180];
wire [63:0] addr_buffer0xb5 = addr_buffer[181];
wire [63:0] addr_buffer0xb6 = addr_buffer[182];
wire [63:0] addr_buffer0xb7 = addr_buffer[183];
wire [63:0] addr_buffer0xb8 = addr_buffer[184];
wire [63:0] addr_buffer0xb9 = addr_buffer[185];
wire [63:0] addr_buffer0xba = addr_buffer[186];
wire [63:0] addr_buffer0xbb = addr_buffer[187];
wire [63:0] addr_buffer0xbc = addr_buffer[188];
wire [63:0] addr_buffer0xbd = addr_buffer[189];
wire [63:0] addr_buffer0xbe = addr_buffer[190];
wire [63:0] addr_buffer0xbf = addr_buffer[191];
wire [63:0] addr_buffer0xc0 = addr_buffer[192];
wire [63:0] addr_buffer0xc1 = addr_buffer[193];
wire [63:0] addr_buffer0xc2 = addr_buffer[194];
wire [63:0] addr_buffer0xc3 = addr_buffer[195];
wire [63:0] addr_buffer0xc4 = addr_buffer[196];
wire [63:0] addr_buffer0xc5 = addr_buffer[197];
wire [63:0] addr_buffer0xc6 = addr_buffer[198];
wire [63:0] addr_buffer0xc7 = addr_buffer[199];
wire [63:0] addr_buffer0xc8 = addr_buffer[200];
wire [63:0] addr_buffer0xc9 = addr_buffer[201];
wire [63:0] addr_buffer0xca = addr_buffer[202];
wire [63:0] addr_buffer0xcb = addr_buffer[203];
wire [63:0] addr_buffer0xcc = addr_buffer[204];
wire [63:0] addr_buffer0xcd = addr_buffer[205];
wire [63:0] addr_buffer0xce = addr_buffer[206];
wire [63:0] addr_buffer0xcf = addr_buffer[207];
wire [63:0] addr_buffer0xd0 = addr_buffer[208];
wire [63:0] addr_buffer0xd1 = addr_buffer[209];
wire [63:0] addr_buffer0xd2 = addr_buffer[210];
wire [63:0] addr_buffer0xd3 = addr_buffer[211];
wire [63:0] addr_buffer0xd4 = addr_buffer[212];
wire [63:0] addr_buffer0xd5 = addr_buffer[213];
wire [63:0] addr_buffer0xd6 = addr_buffer[214];
wire [63:0] addr_buffer0xd7 = addr_buffer[215];
wire [63:0] addr_buffer0xd8 = addr_buffer[216];
wire [63:0] addr_buffer0xd9 = addr_buffer[217];
wire [63:0] addr_buffer0xda = addr_buffer[218];
wire [63:0] addr_buffer0xdb = addr_buffer[219];
wire [63:0] addr_buffer0xdc = addr_buffer[220];
wire [63:0] addr_buffer0xdd = addr_buffer[221];
wire [63:0] addr_buffer0xde = addr_buffer[222];
wire [63:0] addr_buffer0xdf = addr_buffer[223];
wire [63:0] addr_buffer0xe0 = addr_buffer[224];
wire [63:0] addr_buffer0xe1 = addr_buffer[225];
wire [63:0] addr_buffer0xe2 = addr_buffer[226];
wire [63:0] addr_buffer0xe3 = addr_buffer[227];
wire [63:0] addr_buffer0xe4 = addr_buffer[228];
wire [63:0] addr_buffer0xe5 = addr_buffer[229];
wire [63:0] addr_buffer0xe6 = addr_buffer[230];
wire [63:0] addr_buffer0xe7 = addr_buffer[231];
wire [63:0] addr_buffer0xe8 = addr_buffer[232];
wire [63:0] addr_buffer0xe9 = addr_buffer[233];
wire [63:0] addr_buffer0xea = addr_buffer[234];
wire [63:0] addr_buffer0xeb = addr_buffer[235];
wire [63:0] addr_buffer0xec = addr_buffer[236];
wire [63:0] addr_buffer0xed = addr_buffer[237];
wire [63:0] addr_buffer0xee = addr_buffer[238];
wire [63:0] addr_buffer0xef = addr_buffer[239];
wire [63:0] addr_buffer0xf0 = addr_buffer[240];
wire [63:0] addr_buffer0xf1 = addr_buffer[241];
wire [63:0] addr_buffer0xf2 = addr_buffer[242];
wire [63:0] addr_buffer0xf3 = addr_buffer[243];
wire [63:0] addr_buffer0xf4 = addr_buffer[244];
wire [63:0] addr_buffer0xf5 = addr_buffer[245];
wire [63:0] addr_buffer0xf6 = addr_buffer[246];
wire [63:0] addr_buffer0xf7 = addr_buffer[247];
wire [63:0] addr_buffer0xf8 = addr_buffer[248];
wire [63:0] addr_buffer0xf9 = addr_buffer[249];
wire [63:0] addr_buffer0xfa = addr_buffer[250];
wire [63:0] addr_buffer0xfb = addr_buffer[251];
wire [63:0] addr_buffer0xfc = addr_buffer[252];
wire [63:0] addr_buffer0xfd = addr_buffer[253];
wire [63:0] addr_buffer0xfe = addr_buffer[254];
wire [63:0] addr_buffer0xff = addr_buffer[255];
`endif

endmodule

//    output ah_cvalid,            //1
//    output [7:0] ah_ctag,        //9
//    output ah_ctagpar,           //10
//    output [12:0] ah_com,        //23
//    output ah_compar,            //24
//    output [2:0] ah_cabt,        //27
//    output [63:0] ah_cea,        //91
//    output ah_ceapar,            //92
//    output [15:0] ah_cch,        //108
//    output [11:0] ah_csize,      //120
//
