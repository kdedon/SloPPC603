// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Independent acceptance checks for the 603e FPU execution pipeline.
// Cycle zero is the rising edge at which a request is accepted. A result
// registered at the third following rising edge has latency three.
module tb_ppc_fpu_timing #(
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
    logic rsp_ready_i;
    ppc_fpu_arith_rsp_t rsp_o;
    logic finish_valid_o;
    ppc_fpu_arith_rsp_t finish_o;
    logic flush_i;

    wire [2:0] req_fwd_i = 3'b000;
    logic rsp_held_o;
    always @(posedge clk_i)
        if (rst_ni && !flush_i && rsp_held_o !== rsp_valid_o)
            $fatal(1, "held reply differs from valid reply");
    logic finish_write_o;
    logic next_finish_valid_o;
    completion_tag_t next_finish_tag_o;
    ppc_fpu_arith #(.CPU_602(CPU_602)) dut (
        .clk_i(clk_i), .rst_ni(rst_ni), .req_valid_i(req_valid_i),
        .req_ready_o(req_ready_o), .req_i(req_i), .req_fwd_i(req_fwd_i), .rsp_valid_o(rsp_valid_o),
        .rsp_held_o(rsp_held_o),
        .div_busy_o(div_busy_o),
        .rsp_ready_i(rsp_ready_i), .rsp_o(rsp_o),
        .finish_valid_o(finish_valid_o), .finish_o(finish_o),
        .finish_write_o(finish_write_o),
        .next_finish_valid_o(next_finish_valid_o),
        .next_finish_tag_o(next_finish_tag_o),
        .flush_i(flush_i)
    );

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

    int cycle_count;
    int accepted_cycle [0:2047];
    int expected_latency [0:2047];
    logic [63:0] expected_result [0:2047];
    logic [63:0] expected_mask [0:2047];
    ppc_fpu_arith_rsp_t finished_packet [0:2047];
    bit finished_seen [0:2047];
    bit active [0:2047];
    bit seen [0:2047];
    int checked;
    int retired;
    bit allow_response_delay;

    function automatic logic [10:0] key(input completion_tag_t tag);
        return {tag.generation, tag.index};
    endfunction

    always @(posedge clk_i) begin : monitor
        logic [10:0] response_key;
        logic [10:0] consumed_key;
        logic [10:0] finished_key;
        bit consumed;
        bit finishing;
        ppc_fpu_arith_rsp_t finishing_packet;
        consumed = rst_ni && rsp_valid_o && rsp_ready_i;
        consumed_key = key(rsp_o.tag);
        finishing = rst_ni && finish_valid_o;
        finishing_packet = finish_o;
        if (div_busy_o && req_ready_o)
            $fatal(1, "divider occupied but accepted a new request");
        cycle_count <= cycle_count + 1;
        if (consumed) begin
            if (!active[consumed_key] || !seen[consumed_key])
                $fatal(1, "duplicate or unobserved response handshake, key %0d",
                       consumed_key);
            active[consumed_key] <= 1'b0;
            retired <= retired + 1;
        end
        if (finishing) begin
            finished_key = key(finishing_packet.tag);
            if (!active[finished_key] || finished_seen[finished_key])
                $fatal(1, "duplicate or unknown finish bypass tag");
            if (cycle_count + 1 - accepted_cycle[finished_key] !=
                expected_latency[finished_key])
                $fatal(1, "finish-edge latency tag %d:%d was %0d expected %0d",
                       finishing_packet.tag.index,
                       finishing_packet.tag.generation,
                       cycle_count + 1 - accepted_cycle[finished_key],
                       expected_latency[finished_key]);
            finished_packet[finished_key] <= finishing_packet;
            finished_seen[finished_key] <= 1'b1;
        end
        #1;
        if (rst_ni && rsp_valid_o) begin
            response_key = key(rsp_o.tag);
            if (!active[response_key])
                $fatal(1, "unexpected response tag %d:%d at cycle %0d",
                       rsp_o.tag.index, rsp_o.tag.generation, cycle_count);
            if (!seen[response_key]) begin
                if (!finished_seen[response_key] ||
                    rsp_o !== finished_packet[response_key])
                    $fatal(1, "finish bypass differs from queued response");
                if ((rsp_o.result & expected_mask[response_key]) !==
                    (expected_result[response_key] & expected_mask[response_key]))
                    $fatal(1, "result mismatch tag %d:%d got %h expected %h",
                           rsp_o.tag.index, rsp_o.tag.generation,
                           rsp_o.result, expected_result[response_key]);
                if ((!allow_response_delay &&
                     cycle_count - accepted_cycle[response_key] != expected_latency[response_key]) ||
                    (allow_response_delay &&
                     cycle_count - accepted_cycle[response_key] < expected_latency[response_key]))
                    $fatal(1, "latency tag %d:%d was %0d, expected %0d",
                           rsp_o.tag.index, rsp_o.tag.generation,
                           cycle_count - accepted_cycle[response_key],
                           expected_latency[response_key]);
                seen[response_key] <= 1'b1;
                checked <= checked + 1;
            end
        end
    end

    task automatic send_when_ready(
        input logic [7:0] generation,
        input ppc_fpu_op_t operation,
        input bit single_result,
        input logic [63:0] a,
        input logic [63:0] b,
        input logic [63:0] c,
        input logic [63:0] result,
        input int latency,
        output int accepted_at
    );
        logic [10:0] request_key;
        int attempts;
        bit accepted;
        @(negedge clk_i);
        req_i = '0;
        req_i.tag.index = 3'd0;
        req_i.tag.generation = generation;
        req_i.op = operation;
        req_i.single_result = single_result;
        req_i.a = a;
        req_i.b = b;
        req_i.c = c;
        req_valid_i = 1'b1;
        attempts = 0;
        accepted = 1'b0;
        while (!accepted) begin
            @(posedge clk_i);
            // Sample the actual transfer before this edge updates RTL state.
            accepted = req_valid_i && req_ready_o;
            #2;
            attempts++;
            if (attempts > 80) $fatal(1, "request timed out");
        end
        accepted_at = cycle_count;
        request_key = key(req_i.tag);
        if (active[request_key]) $fatal(1, "reused active tag");
        active[request_key] = 1'b1;
        seen[request_key] = 1'b0;
        finished_seen[request_key] = 1'b0;
        accepted_cycle[request_key] = accepted_at;
        expected_latency[request_key] = latency;
        expected_result[request_key] = result;
        // Estimate instructions constrain an error bound, not fixed output
        // bits. The separate rational estimate suite checks their values.
        expected_mask[request_key] = (operation == FP_FRES ||
                                      operation == FP_FRSQRTE) ? 64'd0 :
                                     ((operation == FP_FCTIW || operation == FP_FCTIWZ) ?
                                      64'h0000_0000_ffff_ffff : 64'hffff_ffff_ffff_ffff);
        req_valid_i = 1'b0;
    endtask

    task automatic wait_for_checked(input int target);
        int attempts;
        attempts = 0;
        while (checked < target) begin
            @(negedge clk_i);
            attempts++;
            if (attempts > 100) $fatal(1, "only %0d/%0d results observed", checked, target);
        end
        repeat (2) @(negedge clk_i);
        if (retired < target)
            $fatal(1, "only %0d/%0d response handshakes retired", retired, target);
    endtask

    initial begin : run
        int first_cycle;
        int second_cycle;
        int base_count;
        ppc_fpu_arith_rsp_t held_response;
        cycle_count = 0;
        checked = 0;
        retired = 0;
        rst_ni = 1'b0;
        req_valid_i = 1'b0;
        req_i = '0;
        rsp_ready_i = 1'b1;
        flush_i = 1'b0;
        allow_response_delay = 1'b0;
        for (int i = 0; i < 2048; i++) begin
            active[i] = 1'b0;
            seen[i] = 1'b0;
            finished_seen[i] = 1'b0;
        end
        repeat (3) @(negedge clk_i);
        rst_ni = 1'b1;

        // Independent basic arithmetic must accept an instruction each cycle.
        base_count = checked;
        for (int i = 0; i < 4; i++) begin
            send_when_ready(8'(i + 1), FP_ADD, CPU_602,
                            64'h3ff0000000000000, 64'h4000000000000000,
                            64'd0, 64'h4008000000000000, 3, second_cycle);
            if (i == 0) first_cycle = second_cycle;
            else if (second_cycle != first_cycle + i)
                $fatal(1, "basic arithmetic issue interval exceeded one cycle");
        end
        wait_for_checked(base_count + 4);

        // Single multiply is 1-1-1; double multiply occupies its first
        // pipeline stage for two clocks (2-1-1).
        base_count = checked;
        send_when_ready(8'd5, FP_MUL, 1'b1,
                        64'h4000000000000000, 64'd0,
                        64'h4008000000000000, 64'h4018000000000000,
                        3, first_cycle);
        send_when_ready(8'd6, FP_MUL, 1'b1,
                        64'h4000000000000000, 64'd0,
                        64'h4008000000000000, 64'h4018000000000000,
                        3, second_cycle);
        if (second_cycle != first_cycle + 1)
            $fatal(1, "single multiply issue interval exceeded one cycle");
        wait_for_checked(base_count + 2);

        if (!CPU_602) begin
        base_count = checked;
        send_when_ready(8'd7, FP_MUL, 1'b0,
                        64'h4000000000000000, 64'd0,
                        64'h4008000000000000, 64'h4018000000000000,
                        4, first_cycle);
        send_when_ready(8'd8, FP_MUL, 1'b0,
                        64'h4000000000000000, 64'd0,
                        64'h4008000000000000, 64'h4018000000000000,
                        4, second_cycle);
        if (second_cycle != first_cycle + 2)
            $fatal(1, "double multiply issue interval was %0d, expected two",
                   second_cycle - first_cycle);
        wait_for_checked(base_count + 2);
        end

        base_count = checked;
        send_when_ready(8'd12, FP_MADD, 1'b1,
                        64'h4000000000000000, 64'h3ff0000000000000,
                        64'h4008000000000000, 64'h401c000000000000,
                        3, first_cycle);
        send_when_ready(8'd13, FP_MADD, 1'b1,
                        64'h4000000000000000, 64'h3ff0000000000000,
                        64'h4008000000000000, 64'h401c000000000000,
                        3, second_cycle);
        if (second_cycle != first_cycle + 1)
            $fatal(1, "single fused issue interval exceeded one cycle");
        wait_for_checked(base_count + 2);

        if (!CPU_602) begin
        base_count = checked;
        send_when_ready(8'd14, FP_MADD, 1'b0,
                        64'h4000000000000000, 64'h3ff0000000000000,
                        64'h4008000000000000, 64'h401c000000000000,
                        4, first_cycle);
        send_when_ready(8'd15, FP_MADD, 1'b0,
                        64'h4000000000000000, 64'h3ff0000000000000,
                        64'h4008000000000000, 64'h401c000000000000,
                        4, second_cycle);
        if (second_cycle != first_cycle + 2)
            $fatal(1, "double fused issue interval was %0d, expected two",
                   second_cycle - first_cycle);
        wait_for_checked(base_count + 2);
        end

        // Sustained trains cross response-credit recycle boundaries. A
        // four-operation burst alone cannot detect a bubble every fifth op.
        base_count = checked;
        for (int i = 0; i < 32; i++) begin
            send_when_ready(8'(32 + i), FP_ADD, CPU_602,
                            64'h3ff0000000000000, 64'h4000000000000000,
                            64'd0, 64'h4008000000000000, 3, second_cycle);
            if (i == 0) first_cycle = second_cycle;
            else if (second_cycle != first_cycle + i)
                $fatal(1, "sustained basic issue bubble at operation %0d", i);
        end
        wait_for_checked(base_count + 32);

        if (!CPU_602) begin
        base_count = checked;
        for (int i = 0; i < 12; i++) begin
            send_when_ready(8'(64 + i), FP_MUL, 1'b0,
                            64'h4000000000000000, 64'd0,
                            64'h4008000000000000, 64'h4018000000000000,
                            4, second_cycle);
            if (i == 0) first_cycle = second_cycle;
            else if (second_cycle != first_cycle + (2 * i))
                $fatal(1, "sustained double-multiply issue bubble at %0d", i);
        end
        wait_for_checked(base_count + 12);
        end

        // Four accepted operations may occupy completion credits while the
        // consumer stalls. The fifth must wait; a held response remains stable.
        base_count = checked;
        allow_response_delay = 1'b1;
        rsp_ready_i = 1'b0;
        for (int i = 0; i < 4; i++) begin
            send_when_ready(8'(16 + i), FP_ADD, CPU_602,
                            64'h3ff0000000000000, 64'h4000000000000000,
                            64'd0, 64'h4008000000000000, 3, second_cycle);
            if (i == 0) first_cycle = second_cycle;
            else if (second_cycle != first_cycle + i)
                $fatal(1, "credit train issue interval exceeded one cycle");
        end
        @(negedge clk_i);
        if (req_ready_o) $fatal(1, "fifth operation accepted beyond four credits");
        if (!rsp_valid_o) $fatal(1, "held response disappeared");
        held_response = rsp_o;
        repeat (2) begin
            @(negedge clk_i);
            if (!rsp_valid_o || rsp_o !== held_response)
                $fatal(1, "stalled response changed");
        end
        rsp_ready_i = 1'b1;
        send_when_ready(8'd20, FP_ADD, CPU_602,
                        64'h3ff0000000000000, 64'h4000000000000000,
                        64'd0, 64'h4008000000000000, 3, second_cycle);
        wait_for_checked(base_count + 5);
        allow_response_delay = 1'b0;

        // A flushed in-flight tag must never reappear after a fresh request.
        send_when_ready(8'd21, FP_ADD, CPU_602,
                        64'h3ff0000000000000, 64'h4000000000000000,
                        64'd0, 64'h4008000000000000, 3, first_cycle);
        @(negedge clk_i);
        flush_i = 1'b1;
        #1;
        if (rsp_valid_o || req_ready_o)
            $fatal(1, "flush edge published or accepted an operation");
        @(posedge clk_i);
        #2;
        active[21 * 8] = 1'b0;
        flush_i = 1'b0;
        base_count = checked;
        send_when_ready(8'd22, FP_ADD, CPU_602,
                        64'h3ff0000000000000, 64'h4000000000000000,
                        64'd0, 64'h4008000000000000, 3, first_cycle);
        wait_for_checked(base_count + 1);

        base_count = checked;
        send_when_ready(8'd9, FP_DIV, 1'b1,
                        64'h4018000000000000, 64'h4000000000000000,
                        64'd0, 64'h4008000000000000, 18, first_cycle);
        wait_for_checked(base_count + 1);
        if (!CPU_602) begin
        base_count = checked;
        send_when_ready(8'd10, FP_DIV, 1'b0,
                        64'h4018000000000000, 64'h4000000000000000,
                        64'd0, 64'h4008000000000000, 33, first_cycle);
        wait_for_checked(base_count + 1);
        end
        base_count = checked;
        send_when_ready(8'd23, FP_FRES, 1'b1,
                        64'd0, 64'h4000000000000000,
                        64'd0, 64'h3fe0000000000000, 18, first_cycle);
        wait_for_checked(base_count + 1);

        // The divider is nonpipelined, yet terminal-edge enqueue admits
        // the next divide. This checks initiation interval independently of
        // individual completion latency, for finite and special inputs.
        base_count = checked;
        send_when_ready(8'd80, FP_DIV, 1'b1,
                        64'h4018000000000000, 64'h4000000000000000,
                        64'd0, 64'h4008000000000000, 18, first_cycle);
        send_when_ready(8'd81, FP_DIV, 1'b1,
                        64'h4018000000000000, 64'd0,
                        64'd0, 64'h7ff0000000000000, 18, second_cycle);
        if (second_cycle - first_cycle != 18)
            $fatal(1, "single divide initiation interval was %0d, expected 18",
                   second_cycle - first_cycle);
        wait_for_checked(base_count + 2);

        base_count = checked;
        send_when_ready(8'd82, FP_FRES, 1'b1,
                        64'd0, 64'h4000000000000000,
                        64'd0, 64'h3fe0000000000000, 18, first_cycle);
        send_when_ready(8'd83, FP_FRES, 1'b1,
                        64'd0, 64'd0, 64'd0,
                        64'h7ff0000000000000, 18, second_cycle);
        if (second_cycle - first_cycle != 18)
            $fatal(1, "reciprocal initiation interval was %0d, expected 18",
                   second_cycle - first_cycle);
        wait_for_checked(base_count + 2);

        if (!CPU_602) begin
            base_count = checked;
            send_when_ready(8'd84, FP_DIV, 1'b0,
                            64'h4018000000000000, 64'h4000000000000000,
                            64'd0, 64'h4008000000000000, 33, first_cycle);
            send_when_ready(8'd85, FP_DIV, 1'b0,
                            64'h4018000000000000, 64'd0,
                            64'd0, 64'h7ff0000000000000, 33, second_cycle);
            if (second_cycle - first_cycle != 33)
                $fatal(1, "double divide initiation interval was %0d, expected 33",
                       second_cycle - first_cycle);
            wait_for_checked(base_count + 2);
        end

        $display("%s FPU finish predictions PASS: %0d",
                 CPU_602 ? " 602" : "603e", predicted_finishes);
        $display("%s FPU timing checks PASS: %0d responses",
                 CPU_602 ? "602" : "603e", checked);
        $finish;
    end
endmodule
`default_nettype wire
