`timescale 1ns /1ps

// Testbench

module tb_cic_decimator;


    parameter IN_WIDTH   = cic_parameters_pkg::IN_WIDTH;
    parameter OUT_WIDTH  = cic_parameters_pkg::FULL_WIDTH;
    parameter R          = cic_parameters_pkg::R;
    parameter M          = cic_parameters_pkg::M;
    parameter N          = cic_parameters_pkg::N;
    parameter OUTPUT_MODE = cic_parameters_pkg::OUTPUT_MODE;
    parameter ROUND_MODE  = cic_parameters_pkg::ROUND_MODE;
    parameter NORMALIZE   = cic_parameters_pkg::NORMALIZE;

    parameter INPUT_FILE  = "C:/CIC/Programmy_moi/cic_decimator_project/rtl_test_case/input.txt";
    parameter OUTPUT_FILE = "C:/CIC/Programmy_moi/cic_decimator_project/rtl_test_case/rtl_output.txt";


    localparam LOG2_RM    = $clog2(R * M);
    localparam GROWTH_W   = (N * LOG2_RM) + (((R*M) != (2**LOG2_RM)) ? 1 : 0);
    localparam FULL_W     = IN_WIDTH + GROWTH_W;

    localparam TDATA_IN_W  = ((IN_WIDTH  + 7) / 8) * 8;
    localparam TDATA_OUT_W = ((OUT_WIDTH + 7) / 8) * 8;


    logic clk = 0;
    logic rst_n;

    logic [TDATA_IN_W-1:0]  s_din_tdata;
    logic                   s_din_tvalid;
    logic                   s_din_tready;

    logic [TDATA_OUT_W-1:0] m_dout_tdata;
    logic                   m_dout_tvalid;
    logic                   m_dout_tready;


    always #5 clk = ~clk;


    cic_decimator_top #(
        .IN_WIDTH    (IN_WIDTH),
        .OUT_WIDTH   (OUT_WIDTH),
        .R           (R),
        .M           (M),
        .N           (N),
        .OUTPUT_MODE (OUTPUT_MODE),
        .ROUND_MODE  (ROUND_MODE),
        .NORMALIZE   (NORMALIZE)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_din_tdata  (s_din_tdata),
        .s_din_tvalid (s_din_tvalid),
        .s_din_tready (s_din_tready),
        .m_dout_tdata (m_dout_tdata),
        .m_dout_tvalid(m_dout_tvalid),
        .m_dout_tready(m_dout_tready)
    );


    int input_fd, output_fd;
    int sample_val;
    int input_queue[$];
    int output_queue[$];
    int input_idx = 0;
    int output_idx = 0;
    int expected_output_len;

    bit input_done  = 0;
    bit output_done = 0;
    int idle_cycles = 0;
    localparam MAX_IDLE_CYCLES = 10000;

    initial begin
        $display("============================================================");
        $display("  CIC Decimator Testbench");
        $display("============================================================");
        $display("  IN_WIDTH=%0d OUT_WIDTH=%0d R=%0d M=%0d N=%0d", IN_WIDTH, OUT_WIDTH, R, M, N);
        $display("  OUTPUT_MODE=%s ROUND_MODE=%s NORMALIZE=%0b", OUTPUT_MODE, ROUND_MODE, NORMALIZE);
        $display("  FULL_WIDTH=%0d", FULL_W);
        $display("============================================================");

        rst_n = 0;
        s_din_tvalid = 0;
        s_din_tdata  = 0;
        m_dout_tready = 1'b1;

        repeat(20) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        $display("[TB] Reset released");

        input_fd = $fopen(INPUT_FILE, "r");
        if (input_fd == 0) begin
            $error("[TB] ERROR: Cannot open input file: %s", INPUT_FILE);
            $finish;
        end

        while (!$feof(input_fd)) begin
            int scan_result;
            scan_result = $fscanf(input_fd, "%d\n", sample_val);
            if (scan_result == 1) begin
                if (sample_val < -(2**(IN_WIDTH-1)) || sample_val > (2**(IN_WIDTH-1))-1) begin
                    $warning("[TB] Input value %0d out of range for %0d-bit signed", sample_val, IN_WIDTH);
                end
                input_queue.push_back(sample_val);
            end
        end
        $fclose(input_fd);

        expected_output_len = input_queue.size() / R;

        $display("[TB] Read %0d input samples", input_queue.size());
        $display("[TB] Expected output length: %0d samples", expected_output_len);


        fork
            begin : input_thread
                while (input_idx < input_queue.size()) begin
                    @(posedge clk);
                    if (s_din_tready) begin
                        s_din_tvalid <= 1'b1;
                        s_din_tdata  <= {{(TDATA_IN_W-IN_WIDTH){input_queue[input_idx][IN_WIDTH-1]}},
                                         input_queue[input_idx][IN_WIDTH-1:0]};
                        input_idx++;
                    end
                end

                repeat(R * N * M) begin
                    @(posedge clk);
                    if (s_din_tready) begin
                        s_din_tvalid <= 1'b1;
                        s_din_tdata  <= '0;
                    end
                end

                @(posedge clk);
                s_din_tvalid <= 1'b0;
                s_din_tdata  <= '0;
                input_done   = 1'b1;
                $display("[TB] Input thread finished, %0d samples sent", input_idx);
            end

            begin : output_thread
                forever begin
                    @(posedge clk);
                    if (m_dout_tvalid && m_dout_tready) begin
                        int captured;
                        captured = int'($signed(m_dout_tdata[OUT_WIDTH-1:0]));
                        output_queue.push_back(captured);
                        output_idx++;
                    end

                    if (input_done && !m_dout_tvalid) begin
                        idle_cycles++;
                        if (idle_cycles > MAX_IDLE_CYCLES) begin
                            $display("[TB] No more output after %0d idle cycles", MAX_IDLE_CYCLES);
                            output_done = 1'b1;
                            break;
                        end
                    end else begin
                        idle_cycles = 0;
                    end

                    if (output_idx >= expected_output_len && input_done) begin
                        repeat(R * N * 2) @(posedge clk);
                        output_done = 1'b1;
                        break;
                    end
                end
            end
        join

        $display("[TB] Collected %0d output samples (expected: %0d)",
                 output_queue.size(), expected_output_len);

        if (output_queue.size() != expected_output_len) begin
            $warning("[TB] MISMATCH: got %0d samples, expected %0d",
                     output_queue.size(), expected_output_len);
        end

        output_fd = $fopen(OUTPUT_FILE, "w");
        if (output_fd == 0) begin
            $error("[TB] ERROR: Cannot create output file: %s", OUTPUT_FILE);
            $finish;
        end

        foreach (output_queue[i]) begin
            $fdisplay(output_fd, "%0d", output_queue[i]);
        end
        $fclose(output_fd);

        $display("[TB] Written %0d samples to %s", output_queue.size(), OUTPUT_FILE);
        $display("[TB] ============================================================");
        $display("[TB]  NEXT STEP: run_compare_rtl_output.m in MATLAB");
        $display("[TB] ============================================================");

        $finish;
    end

    initial begin
        repeat(1000000) @(posedge clk);
        $error("[TB] TIMEOUT after 1M cycles");
        $finish;
    end

endmodule