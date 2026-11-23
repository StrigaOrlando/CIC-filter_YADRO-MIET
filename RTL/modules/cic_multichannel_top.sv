// FIFO одного логического канала
module cic_channel_fifo #(
    parameter int DATA_WIDTH  = 16,
    parameter int DEPTH       = 16,
    parameter int LEVEL_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)
) (
    input  logic                   clk      ,
    input  logic                   rst_n    ,

    input  logic                   i_wr_en  ,
    input  logic [DATA_WIDTH-1:0]  i_wr_data,

    input  logic                   i_rd_en  ,
    output logic [DATA_WIDTH-1:0]  o_rd_data,

    output logic                   o_empty  ,
    output logic                   o_full   ,
    output logic [LEVEL_WIDTH-1:0] o_level
);

    localparam int PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    logic [DATA_WIDTH-1:0]  mem [0:DEPTH-1];
    logic [PTR_WIDTH-1:0]   wr_ptr_ff      ;
    logic [PTR_WIDTH-1:0]   rd_ptr_ff      ;
    logic [LEVEL_WIDTH-1:0] count_ff       ;

    logic do_write;
    logic do_read ;

    assign o_empty = (count_ff == 0)    ;
    assign o_full  = (count_ff == DEPTH);
    assign o_level = count_ff           ;

    assign o_rd_data = o_empty ? '0 : mem[rd_ptr_ff];

    assign do_read  = i_rd_en && !o_empty            ;
    assign do_write = i_wr_en && (!o_full || do_read);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_ff <= '0;
            rd_ptr_ff <= '0;
            count_ff  <= '0;
        end else begin
            if (do_write) begin
                mem[wr_ptr_ff] <= i_wr_data;

                if (wr_ptr_ff == DEPTH - 1)
                    wr_ptr_ff <= '0;
                else
                    wr_ptr_ff <= wr_ptr_ff + 1'b1;
            end

            if (do_read) begin
                if (rd_ptr_ff == DEPTH - 1)
                    rd_ptr_ff <= '0;
                else
                    rd_ptr_ff <= rd_ptr_ff + 1'b1;
            end

            case ({do_write, do_read})
                2'b10: count_ff <= count_ff + 1'b1;
                2'b01: count_ff <= count_ff - 1'b1;
                default: count_ff <= count_ff;
            endcase
        end
    end

endmodule : cic_channel_fifo


// Простая реализация арбитра c0 -> c1 -> ... -> cN-1 -> c0
module cic_simple_arbiter #(
    parameter int NUM_CHANNELS = 4,
    parameter int TID_WIDTH    = (NUM_CHANNELS <= 1) ? 1 : $clog2(NUM_CHANNELS)
) (
    input  logic                    clk          ,
    input  logic                    rst_n        ,

    input  logic [NUM_CHANNELS-1:0] i_empty      ,

    output logic                    o_grant_valid,
    output logic [TID_WIDTH-1:0]    o_grant_tid  ,

    input  logic                    i_grant_take
);

    logic [TID_WIDTH-1:0] channel_ff;

    assign o_grant_tid   = channel_ff          ;
    assign o_grant_valid = !i_empty[channel_ff];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            channel_ff <= '0;
        end else if (!o_grant_valid || i_grant_take) begin
            if (channel_ff == NUM_CHANNELS - 1)
                channel_ff <= '0;
            else
                channel_ff <= channel_ff + 1'b1;
        end
    end

endmodule : cic_simple_arbiter


// Сложная реализация арбитра
module cic_load_aware_arbiter #(
    parameter int NUM_CHANNELS   = 4                                             ,
    parameter int TID_WIDTH      = (NUM_CHANNELS <= 1) ? 1 : $clog2(NUM_CHANNELS),
    parameter int LEVEL_WIDTH    = 5                                             ,
    parameter int AGE_LIMIT      = 32                                            ,
    parameter int HIGH_WATERMARK = 12
) (
    input  logic                 clk                               ,
    input  logic                 rst_n                             ,

    input  logic [LEVEL_WIDTH-1:0]       i_level [0:NUM_CHANNELS-1],

    output logic                 o_grant_valid                     ,
    output logic [TID_WIDTH-1:0] o_grant_tid                       ,

    input  logic                 i_grant_take
);

    localparam int AGE_WIDTH =
        (AGE_LIMIT <= 1) ? 1 : $clog2(AGE_LIMIT + 1);

    logic [TID_WIDTH-1:0] rr_ptr_ff                 ;
    logic [AGE_WIDTH-1:0] age_ff [0:NUM_CHANNELS-1] ;

    logic urgent_exists  ;
    logic pressure_exists;

    always_comb begin
        urgent_exists   = 1'b0;
        pressure_exists = 1'b0;

        for (int c = 0; c < NUM_CHANNELS; c = c + 1) begin
            if (i_level[c] != 0) begin
                if (age_ff[c] >= AGE_LIMIT)
                    urgent_exists = 1'b1;

                if (i_level[c] >= HIGH_WATERMARK)
                    pressure_exists = 1'b1;
            end
        end
    end

    always_comb begin
        int idx                           ;
        logic found                       ;
        logic [AGE_WIDTH-1:0]   best_age  ;
        logic [LEVEL_WIDTH-1:0] best_level;

        o_grant_valid = 1'b0     ;
        o_grant_tid   = rr_ptr_ff;

        found      = 1'b0;
        best_age   = '0  ;
        best_level = '0  ;

        for (int offset = 0; offset < NUM_CHANNELS; offset = offset + 1) begin
            idx = rr_ptr_ff + offset;
            if (idx >= NUM_CHANNELS)
                idx = idx - NUM_CHANNELS;

            if (i_level[idx] != 0) begin
                if (urgent_exists) begin
                    if ((age_ff[idx] >= AGE_LIMIT) &&
                        (!found || (age_ff[idx] > best_age))) begin
                        found       = 1'b1              ;
                        best_age    = age_ff[idx]       ;
                        o_grant_tid = idx[TID_WIDTH-1:0];
                    end
                end else if (pressure_exists) begin
                    if (!found || (i_level[idx] > best_level)) begin
                        found       = 1'b1              ;
                        best_level  = i_level[idx]      ;
                        o_grant_tid = idx[TID_WIDTH-1:0];
                    end
                end else if (!found) begin
                    found       = 1'b1              ;
                    o_grant_tid = idx[TID_WIDTH-1:0];
                end
            end
        end

        o_grant_valid = found;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr_ff <= '0;

            for (int c = 0; c < NUM_CHANNELS; c = c + 1)
                age_ff[c] <= '0;
        end else begin
            for (int c = 0; c < NUM_CHANNELS; c = c + 1) begin
                if (i_level[c] == 0) begin
                    age_ff[c] <= '0;
                end else if (i_grant_take && (o_grant_tid == c)) begin
                    age_ff[c] <= '0;
                end else if (&age_ff[c]) begin
                    age_ff[c] <= age_ff[c];
                end else begin
                    age_ff[c] <= age_ff[c] + 1'b1;
                end
            end

            if (i_grant_take) begin
                if (o_grant_tid == NUM_CHANNELS - 1)
                    rr_ptr_ff <= '0;
                else
                    rr_ptr_ff <= o_grant_tid + 1'b1;
            end
        end
    end

endmodule : cic_load_aware_arbiter


// Общий многоканальный top
module cic_multichannel_top #(
    parameter int NUM_CHANNELS   = cic_parameters_pkg::NUM_CHANNELS              ,
    parameter int TID_WIDTH      = (NUM_CHANNELS <= 1) ? 1 : $clog2(NUM_CHANNELS),
    parameter int FIFO_DEPTH     = cic_parameters_pkg::CHANNEL_FIFO_DEPTH        ,
    parameter bit LOAD_AWARE_ARB = cic_parameters_pkg::LOAD_AWARE_ARB            ,

    parameter int AGE_LIMIT      = cic_parameters_pkg::ARB_AGE_LIMIT             ,
    parameter int HIGH_WATERMARK = cic_parameters_pkg::ARB_HIGH_WATERMARK        ,

    parameter int TDATA_OUT_W =
        (((cic_parameters_pkg::OUTPUT_MODE == 0
            ? cic_parameters_pkg::OUT_WIDTH
            : ((cic_parameters_pkg::NORMALIZE
                ? cic_parameters_pkg::IN_WIDTH
                : cic_parameters_pkg::FULL_WIDTH)
               + (cic_parameters_pkg::COMP_AFR
                   ? cic_parameters_pkg::COMP_GROWTH_W : 0))) + 7) / 8) * 8
) (
    input  logic                                              i_clk        ,
    input  logic                                              i_rst_n      ,

    input  logic [((cic_parameters_pkg::IN_WIDTH+7)/8)*8-1:0] i_din_tdata  ,
    input  logic [TID_WIDTH-1:0]                              i_din_tid    ,
    input  logic                                              i_din_vld    ,
    output logic                                              o_din_tready ,

    output logic [TDATA_OUT_W-1:0]                            o_dout_tdata ,
    output logic [TID_WIDTH-1:0]                              o_dout_tid   ,
    output logic                                              o_dout_vld   ,
    input  logic                                              i_dout_tready
);

    localparam int TDATA_IN_W = ((cic_parameters_pkg::IN_WIDTH + 7) / 8) * 8;

    localparam int LEVEL_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH + 1);

    logic [TDATA_IN_W-1:0]    fifo_dout [0:NUM_CHANNELS-1] ;
    logic [LEVEL_WIDTH-1:0]   fifo_level [0:NUM_CHANNELS-1];

    logic [NUM_CHANNELS-1:0]  fifo_wr_en;
    logic [NUM_CHANNELS-1:0]  fifo_rd_en;
    logic [NUM_CHANNELS-1:0]  fifo_empty;
    logic [NUM_CHANNELS-1:0]  fifo_full ;

    logic grant_valid                  ;
    logic [TID_WIDTH-1:0]     grant_tid;
    logic grant_take                   ;

    logic [TDATA_IN_W-1:0]    core_din_tdata;
    logic [TID_WIDTH-1:0]     core_din_tid  ;
    logic core_din_vld                      ;
    logic core_din_tready                   ;

    logic                     input_tid_valid;

    logic [TDATA_IN_W-1:0] dispatch_data_ff;
    logic [TID_WIDTH-1:0]  dispatch_tid_ff ;
    logic dispatch_vld_ff                  ;
    logic dispatch_ready                   ;

    // Проверка TID и входной ready
    always_comb begin
        input_tid_valid = 1'b0;
        o_din_tready    = 1'b1;

        if (i_din_vld) begin
            input_tid_valid = (i_din_tid < NUM_CHANNELS);

            if (!input_tid_valid)
                o_din_tready = 1'b0;
            else
                o_din_tready = !fifo_full[i_din_tid];
        end
    end

    // Демультиплексирование входа по TID
    always_comb begin
        fifo_wr_en = '0;

        if (i_din_vld && o_din_tready) begin
            for (int c = 0; c < NUM_CHANNELS; c = c + 1) begin
                if (i_din_tid == c)
                    fifo_wr_en[c] = 1'b1;
            end
        end
    end

    // FIFO каждого логического канала
    generate
        for (genvar c = 0; c < NUM_CHANNELS; c = c + 1) begin : gen_channel_fifo
            cic_channel_fifo #(
                .DATA_WIDTH  (TDATA_IN_W) ,
                .DEPTH       (FIFO_DEPTH) ,
                .LEVEL_WIDTH (LEVEL_WIDTH)
            ) u_fifo (
                .clk       (i_clk),
                .rst_n     (i_rst_n),
                .i_wr_en   (fifo_wr_en[c]),
                .i_wr_data (i_din_tdata)  ,
                .i_rd_en   (fifo_rd_en[c]),
                .o_rd_data (fifo_dout[c]) ,
                .o_empty   (fifo_empty[c]),
                .o_full    (fifo_full[c]) ,
                .o_level   (fifo_level[c])
            );
        end
    endgenerate

    // Выбор сложности арбитра на этапе elaboration
    generate
        if (LOAD_AWARE_ARB) begin : gen_load_aware_arbiter
            cic_load_aware_arbiter #(
                .NUM_CHANNELS   (NUM_CHANNELS),
                .TID_WIDTH      (TID_WIDTH)   ,
                .LEVEL_WIDTH    (LEVEL_WIDTH) ,
                .AGE_LIMIT      (AGE_LIMIT)   , 
                .HIGH_WATERMARK (HIGH_WATERMARK)
            ) u_arbiter (
                .clk           (i_clk)      ,
                .rst_n         (i_rst_n)    ,
                .i_level       (fifo_level) ,
                .o_grant_valid (grant_valid),
                .o_grant_tid   (grant_tid)  ,
                .i_grant_take  (grant_take)
            );
        end else begin : gen_simple_arbiter
            cic_simple_arbiter #(
                .NUM_CHANNELS (NUM_CHANNELS),
                .TID_WIDTH    (TID_WIDTH)
            ) u_arbiter (
                .clk           (i_clk)      ,
                .rst_n         (i_rst_n)    ,
                .i_empty       (fifo_empty) ,
                .o_grant_valid (grant_valid),
                .o_grant_tid   (grant_tid)  ,
                .i_grant_take  (grant_take)
            );
        end
    endgenerate

    // Передача выбранного отсчёта в общий CIC
    assign dispatch_ready = !dispatch_vld_ff || core_din_tready;

    assign grant_take = grant_valid && dispatch_ready;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            dispatch_data_ff <= '0  ;
            dispatch_tid_ff  <= '0  ;
            dispatch_vld_ff  <= 1'b0;
        end
        else if (dispatch_ready) begin
            dispatch_vld_ff <= grant_take;

            if (grant_take) begin
                dispatch_data_ff <= fifo_dout[grant_tid];
                dispatch_tid_ff  <= grant_tid           ;
            end
        end
    end

    assign core_din_tdata = dispatch_data_ff;
    assign core_din_tid   = dispatch_tid_ff ;
    assign core_din_vld   = dispatch_vld_ff ;


    always_comb begin
        fifo_rd_en = '0;

        if (grant_take)
            fifo_rd_en[grant_tid] = 1'b1;
    end

    // Общий вычислительный тракт CIC
    cic_decimator_top #(
        .NUM_CHANNELS (NUM_CHANNELS),
        .TID_WIDTH    (TID_WIDTH)   ,
        .TDATA_OUT_W  (TDATA_OUT_W)
    ) u_cic (
        .i_clk         (i_clk)          ,
        .i_rst_n       (i_rst_n)        ,
        .i_din_tdata   (core_din_tdata) ,
        .i_din_tid     (core_din_tid)   ,
        .i_din_vld     (core_din_vld)   ,
        .o_din_tready  (core_din_tready),
        .o_dout_tdata  (o_dout_tdata)   ,
        .o_dout_tid    (o_dout_tid)     ,
        .o_dout_vld    (o_dout_vld)     ,
        .i_dout_tready (i_dout_tready)
    );

endmodule : cic_multichannel_top
