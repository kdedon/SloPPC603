// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
module tb_ppc_fpu_arith #(
    parameter bit CPU_602 = 1'b0
);
    import ppc_pkg::*;
    import ppc_fpu_pkg::*;

    logic clk_i = 1'b0;
    always #5 clk_i <= ~clk_i;
    logic rst_ni;
    logic req_valid_i;
    logic req_ready_o;
    logic div_busy_o;
    ppc_fpu_arith_req_t req_i;
    logic rsp_valid_o;
    logic rsp_held_o;
    always @(posedge clk_i)
        if (rst_ni && !flush_i && rsp_held_o !== rsp_valid_o)
            $fatal(1, "held reply differs from valid reply");
    logic rsp_ready_i;
    ppc_fpu_arith_rsp_t rsp_o;
    logic finish_valid_o;
    ppc_fpu_arith_rsp_t finish_o;
    logic flush_i;
    ppc_fpu_arith_rsp_t expected;

    // The 602 shell's operand encoding: a binary32 denormal keeps a zero
    // exponent field and its raw fraction. Other values pass unchanged.
    function automatic logic [63:0] encode_602(input logic [63:0] d);
        logic [52:0] sig;
        logic [52:0] kept;
        int shift;
        if (!CPU_602 || d[62:52] < 11'd874 || d[62:52] > 11'd896) return d;
        sig = {1'b1, d[51:0]};
        shift = 926 - int'(d[62:52]);
        kept = sig >> shift;
        if ((kept << shift) != sig) return d;
        return {d[63], 11'd0, kept[22:0], 29'd0};
    endfunction
    logic [63:0] result_mask;
    logic [4:0] op_bits;
    logic [63:0] read_a, read_b, read_c;
    logic [1:0] read_rn;
    logic read_single, read_ni, read_ve, read_oe, read_ue, read_ze;
    logic [63:0] read_result;
    logic read_write_result;
    logic [8:0] read_invalid;
    logic read_ox, read_ux, read_zx, read_xx;
    logic read_fr, read_fi, read_frfi_valid;
    logic read_tiny_before_round;
    logic [4:0] read_fprf;
    logic read_fprf_valid;
    logic [3:0] read_fpcc;
    logic read_compare_valid;
    int file_handle;
    int parsed;
    int count;
    int failures;
    int waited;
    int op_count [0:13];
    int op_failures [0:13];
    int op_latency_min [0:13];
    int op_latency_max [0:13];
    int precision_count [0:13][0:1];
    int precision_latency_min [0:13][0:1];
    int precision_latency_max [0:13][0:1];
    int result_failures, invalid_failures, flag_failures, class_failures;
    logic bad_result, bad_invalid, bad_flags, bad_class;
    string vectors_path;
    ppc_fpu_arith_rsp_t held;
    ppc_fpu_arith_rsp_t finished_packet;
    logic finished_seen;

    task automatic cancel_at_offset(
        input ppc_fpu_op_t operation, input int offset, input logic [7:0] generation
    );
        int local_wait;
        @(negedge clk_i);
        req_i = '0;
        req_i.op = operation;
        req_i.single_result = CPU_602;
        req_i.a = 64'h3ff0000000000000;
        req_i.b = 64'h4000000000000000;
        req_i.c = 64'h4000000000000000;
        req_i.tag.index = 3'd2;
        req_i.tag.generation = generation;
        req_valid_i = 1'b1;
        if (!req_ready_o) $fatal(1, "cancel sweep request not ready");
        @(posedge clk_i);
        #1;
        req_valid_i = 1'b0;
        repeat (offset) @(negedge clk_i);
        if ((offset & 1) != 0) rst_ni = 1'b0;
        else flush_i = 1'b1;
        #1;
        if (rsp_valid_o) $fatal(1, "cancel sweep published flushed result");
        if (!rst_ni && req_ready_o)
            $fatal(1, "cancel sweep reset accepted request");
        @(posedge clk_i);
        #1;
        flush_i = 1'b0;
        rst_ni = 1'b1;
        if (rsp_valid_o) $fatal(1, "cancel sweep retained flushed result");

        @(negedge clk_i);
        req_i = '0;
        req_i.op = FP_ADD;
        req_i.single_result = CPU_602;
        req_i.a = 64'h3ff0000000000000;
        req_i.b = 64'h4000000000000000;
        req_i.tag.index = 3'd4;
        req_i.tag.generation = generation;
        req_valid_i = 1'b1;
        if (!req_ready_o) $fatal(1, "cancel sweep fresh request not ready");
        @(posedge clk_i);
        #1;
        req_valid_i = 1'b0;
        local_wait = 0;
        while (!rsp_valid_o) begin
            @(posedge clk_i);
            #1;
            local_wait++;
            if (local_wait > 32) $fatal(1, "cancel sweep fresh result timeout");
        end
        if (rsp_o.tag != req_i.tag || rsp_o.result != 64'h4008000000000000)
            $fatal(1, "cancel sweep returned stale tag/data");
        @(negedge clk_i);
        rsp_ready_i = 1'b1;
        @(posedge clk_i);
        #1;
        rsp_ready_i = 1'b0;
        if (rsp_valid_o) $fatal(1, "cancel sweep duplicate result");
    endtask

    wire [2:0] req_fwd_i = 3'b000;
    logic finish_write_o;
    logic next_finish_valid_o;
    completion_tag_t next_finish_tag_o;
    ppc_fpu_arith #(.CPU_602(CPU_602)) dut (.*);

    // Every finish is announced one cycle earlier with its tag.
    logic predicted_q;
    completion_tag_t predicted_tag_q;
    int predicted_finishes = 0;
    always @(posedge clk_i) begin
        if (!rst_ni) begin
            predicted_q <= 1'b0;
        end else begin
            if (finish_valid_o !== (predicted_q && !flush_i) ||
                (finish_valid_o && finish_o.tag !== predicted_tag_q) ||
                finish_write_o !== (finish_valid_o && finish_o.write_result))
                $fatal(1, "finish prediction mismatch");
            if (finish_valid_o) predicted_finishes <= predicted_finishes + 1;
            predicted_q <= next_finish_valid_o;
            predicted_tag_q <= next_finish_tag_o;
        end
    end

    always @(posedge clk_i)
        if (div_busy_o && req_ready_o)
            $fatal(1, "divider busy advertised new arithmetic credit");

    always @(posedge clk_i)
        if (!rst_ni || (req_valid_i && req_ready_o)) begin
            finished_seen <= 1'b0;
        end else if (finish_valid_o) begin
            if (finish_o.tag !== req_i.tag)
                $fatal(1, "arithmetic finish tag differs from outstanding request");
            finished_packet <= finish_o;
            finished_seen <= 1'b1;
        end

    initial begin
        if (!$value$plusargs("VECTORS=%s", vectors_path))
            $fatal(1, "missing VECTORS argument");
        file_handle = $fopen(vectors_path, "r");
        if (file_handle == 0) $fatal(1, "cannot open vectors");
        rst_ni = 1'b0;
        req_valid_i = 1'b0;
        req_i = '0;
        rsp_ready_i = 1'b0;
        flush_i = 1'b0;
        count = 0;
        failures = 0;
        result_failures = 0;
        invalid_failures = 0;
        flag_failures = 0;
        class_failures = 0;
        for (int i = 0; i <= 13; i++) begin
            op_count[i] = 0;
            op_failures[i] = 0;
            op_latency_min[i] = 1025;
            op_latency_max[i] = 0;
            for (int precision = 0; precision < 2; precision++) begin
                precision_count[i][precision] = 0;
                precision_latency_min[i][precision] = 1025;
                precision_latency_max[i][precision] = 0;
            end
        end
        expected = '0;
        repeat (3) @(negedge clk_i);
        rst_ni = 1'b1;
        #1;
        while (!$feof(file_handle)) begin
            parsed = $fscanf(file_handle,
                "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",
                op_bits, read_a, read_b, read_c, read_rn, read_single,
                read_ni, read_ve, read_oe, read_ue, read_ze,
                read_result, read_write_result, read_invalid,
                read_ox, read_ux, read_zx, read_xx,
                read_fr, read_fi, read_frfi_valid,
                read_fprf, read_fprf_valid, read_fpcc,
                read_compare_valid, read_tiny_before_round, result_mask);
            if (parsed == -1) break;
            if (parsed != 27) $fatal(1, "invalid vector %0d fields=%0d", count, parsed);
            expected = '0;
            expected.result = read_result;
            expected.write_result = read_write_result;
            expected.invalid = read_invalid;
            expected.ox = read_ox;
            expected.ux = read_ux;
            expected.zx = read_zx;
            expected.xx = read_xx;
            expected.fr = read_fr;
            expected.fi = read_fi;
            expected.frfi_valid = read_frfi_valid;
            expected.fprf = read_fprf;
            expected.fprf_valid = read_fprf_valid;
            expected.fpcc = read_fpcc;
            expected.compare_valid = read_compare_valid;
            expected.tiny_before_round = read_tiny_before_round;
            req_i = '0;
            req_i.tag.index = 3'(count % 5);
            req_i.tag.generation = 8'(count / 5);
            expected.tag = req_i.tag;
            req_i.op = ppc_fpu_op_t'(op_bits);
            req_i.a = encode_602(read_a);
            req_i.b = encode_602(read_b);
            req_i.c = encode_602(read_c);
            req_i.rn = read_rn;
            req_i.single_result = read_single;
            req_i.ni = read_ni;
            req_i.ve = read_ve;
            req_i.oe = read_oe;
            req_i.ue = read_ue;
            req_i.ze = read_ze;
            req_valid_i = 1'b1;
            waited = 0;
            while (!req_ready_o) begin
                @(negedge clk_i);
                waited = waited + 1;
                if (waited > 1024) $fatal(1, "request timeout vector %0d", count);
            end
            @(posedge clk_i);
            #1;
            req_valid_i = 1'b0;
            waited = 0;
            while (!rsp_valid_o) begin
                @(posedge clk_i);
                #1;
                waited = waited + 1;
                if (waited > 1024) $fatal(1, "response timeout vector %0d", count);
            end
            if (!finished_seen || rsp_o !== finished_packet)
                $fatal(1, "arithmetic finish bypass differs from held response %0d seen=%b live_valid=%b live=%h captured=%h response=%h",
                       count, finished_seen, finish_valid_o, finish_o,
                       finished_packet, rsp_o);
            op_count[int'(op_bits)]++;
            precision_count[int'(op_bits)][int'(read_single)]++;
            if (waited < precision_latency_min[int'(op_bits)][int'(read_single)])
                precision_latency_min[int'(op_bits)][int'(read_single)] = waited;
            if (waited > precision_latency_max[int'(op_bits)][int'(read_single)])
                precision_latency_max[int'(op_bits)][int'(read_single)] = waited;
            if (waited < op_latency_min[int'(op_bits)])
                op_latency_min[int'(op_bits)] = waited;
            if (waited > op_latency_max[int'(op_bits)])
                op_latency_max[int'(op_bits)] = waited;
            bad_result = (((rsp_o.result ^ expected.result) & result_mask) != 64'd0) ||
                         rsp_o.write_result !== expected.write_result;
            bad_invalid = rsp_o.invalid !== expected.invalid;
            bad_flags = (rsp_o.ox !== expected.ox || rsp_o.ux !== expected.ux ||
                        rsp_o.zx !== expected.zx || rsp_o.xx !== expected.xx ||
                        rsp_o.frfi_valid !== expected.frfi_valid ||
                        rsp_o.tiny_before_round !== expected.tiny_before_round ||
                        (expected.frfi_valid && rsp_o.fi !== expected.fi) ||
                        (expected.frfi_valid && !(expected.ox && !read_oe) &&
                         rsp_o.fr !== expected.fr));
            bad_class = rsp_o.fprf_valid !== expected.fprf_valid ||
                        (expected.fprf_valid && rsp_o.fprf !== expected.fprf) ||
                        rsp_o.compare_valid !== expected.compare_valid ||
                        (expected.compare_valid && rsp_o.fpcc !== expected.fpcc);
            if (rsp_o.tag !== expected.tag || bad_result || bad_invalid || bad_flags || bad_class) begin
                failures++;
                op_failures[int'(op_bits)]++;
                result_failures += int'(bad_result);
                invalid_failures += int'(bad_invalid);
                flag_failures += int'(bad_flags);
                class_failures += int'(bad_class);
                if (failures <= 12)
                    $display("MISMATCH n=%0d op=%0d rn=%0d a=%h b=%h c=%h got_result=%h expected_result=%h got_invalid=%h expected_invalid=%h got_flags=%b%b%b%b/%b%b expected_flags=%b%b%b%b/%b%b got_fprf=%h expected_fprf=%h kinds=%b%b%b%b",
                             count, op_bits, read_rn, read_a, read_b, read_c,
                             rsp_o.result, expected.result, rsp_o.invalid, expected.invalid,
                             rsp_o.ox, rsp_o.ux, rsp_o.zx, rsp_o.xx, rsp_o.fr, rsp_o.fi,
                             expected.ox, expected.ux, expected.zx, expected.xx,
                             expected.fr, expected.fi, rsp_o.fprf, expected.fprf,
                             bad_result, bad_invalid, bad_flags, bad_class);
            end
            held = rsp_o;
            repeat (2) begin
                @(posedge clk_i);
                #1;
                if (!rsp_valid_o || rsp_o !== held)
                    $fatal(1, "response changed under backpressure vector %0d", count);
            end
            rsp_ready_i = 1'b1;
            @(posedge clk_i);
            #1;
            rsp_ready_i = 1'b0;
            count++;
            @(negedge clk_i);
            if (rsp_valid_o) $fatal(1, "duplicate response vector %0d", count);
        end
        $fclose(file_handle);
        // A held response must disappear immediately when flushed, even if
        // the consumer presents ready on the same edge.
        @(negedge clk_i);
        req_i = '0;
        req_i.op = FP_ADD;
        req_i.single_result = CPU_602;
        req_i.a = 64'h3ff0000000000000;
        req_i.b = 64'h4000000000000000;
        req_i.tag.index = 3'd1;
        req_i.tag.generation = 8'hfb;
        req_valid_i = 1'b1;
        if (!req_ready_o) $fatal(1, "flush test request not ready");
        @(posedge clk_i);
        #1;
        req_valid_i = 1'b0;
        waited = 0;
        while (!rsp_valid_o) begin
            @(posedge clk_i);
            #1;
            waited++;
            if (waited > 64) $fatal(1, "flush test response timeout");
        end
        @(negedge clk_i);
        flush_i = 1'b1;
        rsp_ready_i = 1'b1;
        #1;
        if (rsp_valid_o) $fatal(1, "flushed response accepted");
        @(posedge clk_i);
        #1;
        flush_i = 1'b0;
        rsp_ready_i = 1'b0;
        if (rsp_valid_o) $fatal(1, "flushed response remained");

        @(negedge clk_i);
        req_i.tag.generation = 8'hfc;
        req_valid_i = 1'b1;
        if (!req_ready_o) $fatal(1, "reset test request not ready");
        @(posedge clk_i);
        #1;
        req_valid_i = 1'b0;
        waited = 0;
        while (!rsp_valid_o) begin
            @(posedge clk_i);
            #1;
            waited++;
            if (waited > 64) $fatal(1, "reset test response timeout");
        end
        @(negedge clk_i);
        rst_ni = 1'b0;
        rsp_ready_i = 1'b1;
        req_valid_i = 1'b1;
        #1;
        if (rsp_valid_o || req_ready_o)
            $fatal(1, "reset exposed arithmetic handshake");
        @(posedge clk_i);
        #1;
        req_valid_i = 1'b0;
        rsp_ready_i = 1'b0;
        rst_ni = 1'b1;
        #1;
        if (rsp_valid_o) $fatal(1, "reset response remained");
        $display("PASS PPC arithmetic flush/reset held-response checks=4");
        for (int offset = 0; offset <= 26; offset++)
            cancel_at_offset(FP_MADD, offset, 8'(offset + 16));
        for (int offset = 0; offset <= 48; offset++)
            cancel_at_offset(FP_DIV, offset, 8'(offset + 32));
        $display("PASS PPC arithmetic cancel-offset sweeps=76");
        $display("PPC_ARITH_RESULT vectors=%0d mismatches=%0d", count, failures);
        $display("PPC_ARITH_DOMAINS result=%0d invalid=%0d flags=%0d class=%0d",
                 result_failures, invalid_failures, flag_failures, class_failures);
        for (int i = 0; i <= 13; i++)
            if (op_count[i] != 0)
                $display("PPC_ARITH_OP op=%0d vectors=%0d mismatches=%0d latency_min=%0d latency_max=%0d",
                         i, op_count[i], op_failures[i], op_latency_min[i], op_latency_max[i]);
        for (int i = 0; i <= 13; i++)
            for (int precision = 0; precision < 2; precision++)
                if (precision_count[i][precision] != 0)
                    $display("PPC_ARITH_PRECISION op=%0d single=%0d vectors=%0d latency_min=%0d latency_max=%0d",
                             i, precision, precision_count[i][precision],
                             precision_latency_min[i][precision],
                             precision_latency_max[i][precision]);
        if (failures != 0) $fatal(1, "PPC arithmetic qualification failed");
        $display("PASS PPC arithmetic finish predictions=%0d", predicted_finishes);
        $display("PASS PPC arithmetic raw packets");
        $finish;
    end
endmodule
`default_nettype wire
