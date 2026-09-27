`default_nettype none
module tb_ppc_fpu_estimates;
    import ppc_pkg::*;
    import ppc_fpu_pkg::*;

    logic clk_i = 1'b0;
    always #5 clk_i <= ~clk_i;
    logic rst_ni;
    logic req_valid_i, req_ready_o;
    ppc_fpu_arith_req_t req_i;
    logic rsp_valid_o, rsp_ready_i;
    ppc_fpu_arith_rsp_t rsp_o;
    logic flush_i;
    logic [4:0] op_bits;
    logic [63:0] input_bits;
    logic [1:0] rn_bits;
    logic ni_bit, ve_bit, oe_bit, ue_bit, ze_bit;
    logic [2:0] mode_bits;
    string input_path, output_path;
    int input_file, output_file, parsed, count, waited;
    int latency_count [0:1][0:1];
    int latency_min [0:1][0:1];
    int latency_max [0:1][0:1];
    ppc_fpu_arith_rsp_t held;

    ppc_fpu_arith dut (.*);

    initial begin
        if (!$value$plusargs("VECTORS=%s", input_path) ||
            !$value$plusargs("OUTPUT=%s", output_path))
            $fatal(1, "missing estimate file argument");
        input_file = $fopen(input_path, "r");
        output_file = $fopen(output_path, "w");
        if (input_file == 0 || output_file == 0) $fatal(1, "estimate file open failed");
        rst_ni = 1'b0;
        req_valid_i = 1'b0;
        req_i = '0;
        rsp_ready_i = 1'b0;
        flush_i = 1'b0;
        count = 0;
        for (int operation = 0; operation < 2; operation++)
            for (int special = 0; special < 2; special++) begin
                latency_count[operation][special] = 0;
                latency_min[operation][special] = 1025;
                latency_max[operation][special] = 0;
            end
        repeat (3) @(negedge clk_i);
        rst_ni = 1'b1;
        while (!$feof(input_file)) begin
            parsed = $fscanf(input_file, "%h %h %h %h %h %h %h %h %h\n",
                op_bits, input_bits, rn_bits, ni_bit, ve_bit, oe_bit,
                ue_bit, ze_bit, mode_bits);
            if (parsed == -1) break;
            if (parsed != 9) $fatal(1, "estimate vector format");
            if (mode_bits > 3'd5) $fatal(1, "estimate mode format");
            @(negedge clk_i);
            req_i = '0;
            req_i.tag.index = 3'(count % 5);
            req_i.tag.generation = 8'(count / 5);
            req_i.op = ppc_fpu_op_t'(op_bits);
            req_i.b = input_bits;
            req_i.rn = rn_bits;
            req_i.ni = ni_bit;
            req_i.ve = ve_bit;
            req_i.oe = oe_bit;
            req_i.ue = ue_bit;
            req_i.ze = ze_bit;
            req_valid_i = 1'b1;
            waited = 0;
            while (!req_ready_o) begin
                @(negedge clk_i);
                waited = waited + 1;
                if (waited > 1024) $fatal(1, "estimate request timeout %0d", count);
            end
            @(posedge clk_i);
            #1;
            req_valid_i = 1'b0;
            waited = 0;
            while (!rsp_valid_o) begin
                @(posedge clk_i);
                #1;
                waited = waited + 1;
                if (waited > 1024) $fatal(1, "estimate response timeout %0d", count);
            end
            latency_count[int'(op_bits)-13][int'(mode_bits == 3'd3)]++;
            if (waited < latency_min[int'(op_bits)-13][int'(mode_bits == 3'd3)])
                latency_min[int'(op_bits)-13][int'(mode_bits == 3'd3)] = waited;
            if (waited > latency_max[int'(op_bits)-13][int'(mode_bits == 3'd3)])
                latency_max[int'(op_bits)-13][int'(mode_bits == 3'd3)] = waited;
            if (rsp_o.tag !== req_i.tag)
                $fatal(1, "estimate response tag %0d", count);
            $fdisplay(output_file, "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                      op_bits, input_bits, rsp_o.result, rsp_o.invalid,
                      rsp_o.ox, rsp_o.ux, rsp_o.zx, rsp_o.xx,
                      rsp_o.fr, rsp_o.fi, rsp_o.frfi_valid,
                      rsp_o.fprf_valid, rsp_o.fprf, rsp_o.write_result,
                      rsp_o.compare_valid, rsp_o.fpcc);
            held = rsp_o;
            @(posedge clk_i);
            #1;
            if (!rsp_valid_o || rsp_o !== held)
                $fatal(1, "estimate response changed under backpressure %0d", count);
            rsp_ready_i = 1'b1;
            @(posedge clk_i);
            #1;
            rsp_ready_i = 1'b0;
            count++;
            @(negedge clk_i);
            if (rsp_valid_o) $fatal(1, "duplicate estimate response %0d", count);
        end
        $fclose(input_file);
        $fclose(output_file);
        $display("PASS estimate transport vectors=%0d", count);
        for (int operation = 0; operation < 2; operation++)
            for (int special = 0; special < 2; special++)
                if (latency_count[operation][special] != 0)
                    $display("ESTIMATE_LATENCY op=%0d special=%0d vectors=%0d latency_min=%0d latency_max=%0d",
                             operation + 13, special, latency_count[operation][special],
                             latency_min[operation][special], latency_max[operation][special]);
        $finish;
    end
endmodule
`default_nettype wire
