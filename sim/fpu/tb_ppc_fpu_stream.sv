// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Public-port dispatch, forward, and retirement throughput check.
module tb_ppc_fpu_stream #(
    parameter bit CPU_602 = 1'b0
);
    import ppc_pkg::*;
    import ppc_fpu_pkg::*;

    logic clk_i = 1'b0;
    always #5 clk_i <= ~clk_i;
    logic rst_ni;
    logic issue_valid_i, issue_ready_o;
    ppc_fpu_issue_t issue_i;
    logic issue1_valid_i, issue1_ready_o;
    ppc_fpu_issue_t issue1_i;
    logic result_valid_o;
    ppc_fpu_result_t result_o;
    logic result1_valid_o;
    ppc_fpu_result_t result1_o;
    logic commit_valid_i, commit_ready_o;
    completion_tag_t commit_tag_i;
    logic commit1_valid_i, commit1_ready_o;
    completion_tag_t commit1_tag_i;
    logic abort_valid_i, kill_all_i;
    completion_tag_t abort_tag_i;
    logic mem_req_valid_o, mem_req_ready_i;
    ppc_fpu_mem_t mem_req_o;
    logic mem_rsp_valid_i, mem_rsp_ready_o;
    ppc_fpu_mem_rsp_t mem_rsp_i;
    logic store_valid_o, store_ready_i;
    ppc_fpu_mem_t store_o;
    logic [4:0] inspect_fpr_index_i;
    logic [63:0] inspect_fpr_o;
    logic [31:0] inspect_fpscr_o, inspect_sp_o, inspect_lt_o;
    logic forward_valid_o;
    ppc_fpu_forward_t forward_o;
    logic forward1_valid_o;
    ppc_fpu_forward_t forward1_o;
    ppc_fpu_forward_data_t forward_data_o, forward1_data_o;
    logic payload_due, payload1_due;

    logic automatic_commit;
    logic auto_commit_valid;
    completion_tag_t auto_commit_tag;
    logic manual_commit_valid;
    completion_tag_t manual_commit_tag;
    int issued;
    int committed;
    int forwarded;
    int cycle_count;
    int issue_cycle [0:31];
    logic [63:0] expected_value;

    ppc_fpu #(.CPU_602(CPU_602)) dut (.*);
    assign issue1_valid_i = 1'b0;
    assign issue1_i = '0;
    assign commit1_valid_i = 1'b0;
    assign commit1_tag_i = '0;
    always @(posedge clk_i)
        if (rst_ni) begin
            if (issue1_ready_o || commit1_ready_o)
                $fatal(1, "stream used unrequested second lane");
            if (result1_valid_o && result1_o.tag == result_o.tag)
                $fatal(1, "stream second result duplicated first tag packet=%h", result1_o);
            if (forward1_valid_o &&
                (!forward_valid_o || forward1_o.tag == forward_o.tag ||
                 !(forward1_o.fpr_write || forward1_o.cr_write)))
                $fatal(1, "stream second forward malformed packet=%h", forward1_o);
        end
    // Register the eager retirement request at the intervening falling edge.
    // This presents it for the very next rising edge without a combinational
    // result/commit loop through the shell's credit-ready logic.
    always @(negedge clk_i) begin
        if (!rst_ni) begin
            auto_commit_valid <= 1'b0;
            auto_commit_tag <= '0;
        end else begin
            auto_commit_valid <= result_valid_o;
            auto_commit_tag <= result_o.tag;
        end
    end
    assign commit_valid_i = automatic_commit ? auto_commit_valid : manual_commit_valid;
    assign commit_tag_i = automatic_commit ? auto_commit_tag : manual_commit_tag;

    function automatic logic [31:0] dform(input logic [5:0] primary,
        input logic [4:0] target);
        return {primary, target, 5'd1, 16'd0};
    endfunction

    function automatic logic [31:0] add_insn(input logic [4:0] target);
        if (CPU_602)
            return {6'd59, target, 5'd1, 5'd2, 5'd0, 5'd21, 1'b0};
        return {6'd63, target, 5'd1, 5'd2, 5'd0, 5'd21, 1'b0};
    endfunction

    function automatic completion_tag_t stream_tag(input int ordinal);
        completion_tag_t value;
        value.index = 3'(ordinal % 4);
        value.generation = 8'(40 + ordinal / 4);
        return value;
    endfunction

    always @(posedge clk_i) begin : stream_monitor
        int ordinal;
        if (!rst_ni) begin
            cycle_count <= 0;
            committed <= 0;
            forwarded <= 0;
            payload_due <= 1'b0;
            payload1_due <= 1'b0;
        end else begin
            cycle_count <= cycle_count + 1;
            // A notification's payload arrives on the following cycle.
            payload_due <= automatic_commit && forward_valid_o;
            if (payload_due && forward_data_o.fpr_value != expected_value)
                $fatal(1, "%s stream forward payload %h",
                       CPU_602 ? "602" : "603e", forward_data_o);
            payload1_due <= automatic_commit && forward1_valid_o &&
                forward1_o.fpr_write;
            if (payload1_due && forward1_data_o.fpr_value != expected_value)
                $fatal(1, "%s stream second forward payload %h",
                       CPU_602 ? "602" : "603e", forward1_data_o);
            if (automatic_commit && issue_valid_i && issue_ready_o) begin
                ordinal = (int'(issue_i.tag.generation) - 32'd40) * 4 +
                          int'(issue_i.tag.index);
                if (ordinal < 0 || ordinal >= 32)
                    $fatal(1, "stream accepted unexpected tag %h", issue_i.tag);
                issue_cycle[ordinal] <= cycle_count + 1;
            end
            if (automatic_commit && result_valid_o && commit_ready_o) begin
                if (result_o.tag !== stream_tag(committed) ||
                    result_o.exception != FPU_NO_EXCEPTION ||
                    !result_o.fpr_write || result_o.fpr_value != expected_value)
                    $fatal(1, "%s stream result %0d tag/data/exception mismatch packet=%h",
                           CPU_602 ? "602" : "603e", committed, result_o);
                committed <= committed + 1;
            end
            if (automatic_commit && forward_valid_o) begin
                ordinal = (int'(forward_o.tag.generation) - 32'd40) * 4 +
                          int'(forward_o.tag.index);
                if (ordinal != forwarded || !forward_o.fpr_write)
                    $fatal(1, "%s stream forward tag/data/duplicate packet=%h",
                           CPU_602 ? "602" : "603e", forward_o);
                if (cycle_count + 1 - issue_cycle[ordinal] != 3)
                    $fatal(1, "%s stream forward ordinal=%0d delay=%0d expected=3",
                           CPU_602 ? "602" : "603e", ordinal,
                           cycle_count + 1 - issue_cycle[ordinal]);
                forwarded <= forwarded + 1;
            end
        end
    end

    task automatic initialize_fpr(input logic [4:0] destination,
        input logic [63:0] data, input logic [7:0] generation);
        completion_tag_t identity;
        int attempts;
        bit accepted;
        identity.index = 3'd0;
        identity.generation = generation;
        @(negedge clk_i);
        issue_i = '0;
        issue_i.tag = identity;
        issue_i.insn = dform(CPU_602 ? 6'd48 : 6'd50, destination);
        issue_i.msr_fp = 1'b1;
        issue_valid_i = 1'b1;
        accepted = 1'b0;
        attempts = 0;
        while (!accepted) begin
            @(posedge clk_i);
            accepted = issue_valid_i && issue_ready_o;
            #2;
            attempts++;
            if (attempts > 100) $fatal(1, "stream setup issue timeout");
        end
        issue_valid_i = 1'b0;
        attempts = 0;
        while (!mem_req_valid_o) begin
            @(negedge clk_i);
            attempts++;
            if (attempts > 100)
                $fatal(1, "stream setup memory request timeout descriptor=%h", mem_req_o);
        end
        mem_req_ready_i = 1'b1;
        @(posedge clk_i);
        #2;
        mem_req_ready_i = 1'b0;
        @(negedge clk_i);
        mem_rsp_i = '0;
        mem_rsp_i.tag = identity;
        mem_rsp_i.data = data;
        mem_rsp_valid_i = 1'b1;
        #1;
        if (!mem_rsp_ready_o)
            $fatal(1, "stream setup memory response was not accepted");
        @(posedge clk_i);
        #2;
        mem_rsp_valid_i = 1'b0;
        attempts = 0;
        while (!result_valid_o) begin
            @(negedge clk_i);
            attempts++;
            if (attempts > 100) $fatal(1, "stream setup result timeout");
        end
        if (result_o.tag !== identity || result_o.exception != FPU_NO_EXCEPTION)
            $fatal(1, "stream setup load result mismatch");
        @(negedge clk_i);
        manual_commit_tag = identity;
        manual_commit_valid = 1'b1;
        accepted = 1'b0;
        while (!accepted) begin
            @(posedge clk_i);
            accepted = commit_ready_o;
            #2;
        end
        manual_commit_valid = 1'b0;
    endtask

    initial begin : run
        int attempts;
        bit accepted;
        rst_ni = 1'b0;
        issue_valid_i = 1'b0;
        issue_i = '0;
        automatic_commit = 1'b0;
        manual_commit_valid = 1'b0;
        manual_commit_tag = '0;
        abort_valid_i = 1'b0;
        abort_tag_i = '0;
        kill_all_i = 1'b0;
        mem_req_ready_i = 1'b0;
        mem_rsp_valid_i = 1'b0;
        mem_rsp_i = '0;
        store_ready_i = 1'b1;
        inspect_fpr_index_i = 5'd0;
        issued = 0;
        for (int i = 0; i < 32; i++) begin
            issue_cycle[i] = 0;
        end
        repeat (3) @(negedge clk_i);
        rst_ni = 1'b1;
        initialize_fpr(5'd1, CPU_602 ? 64'h000000003f800000 :
                      64'h3ff0000000000000, 8'd1);
        initialize_fpr(5'd2, CPU_602 ? 64'h0000000040000000 :
                      64'h4000000000000000, 8'd2);
        inspect_fpr_index_i = 5'd1;
        #1;
        if (inspect_fpr_o != (CPU_602 ? 64'h000000003f800000 :
                                       64'h3ff0000000000000) ||
            inspect_fpscr_o != 32'd0)
            $fatal(1, "stream setup architectural state mismatch");
        expected_value = CPU_602 ? 64'h0000000040400000 :
                                   64'h4008000000000000;

        automatic_commit = 1'b1;
        for (int i = 0; i < 32; i++) begin
            @(negedge clk_i);
            issue_i = '0;
            issue_i.tag = stream_tag(i);
            issue_i.insn = add_insn(5'(3 + (i % 28)));
            issue_i.msr_fp = 1'b1;
            issue_valid_i = 1'b1;
            @(posedge clk_i);
            accepted = issue_valid_i && issue_ready_o;
            #2;
            if (!accepted)
                $fatal(1, "%s stream dispatch bubble at %0d",
                       CPU_602 ? "602" : "603e", i);
            issued++;
            issue_valid_i = 1'b0;
        end
        attempts = 0;
        while (committed != 32 || forwarded != 32) begin
            @(negedge clk_i);
            attempts++;
            if (attempts > 100)
                $fatal(1, "%s stream incomplete: issued=%0d forward=%0d commit=%0d",
                       CPU_602 ? "602" : "603e", issued, forwarded, committed);
        end
        if (CPU_602 && (inspect_sp_o[31-3] !== 1'b1 || inspect_lt_o[31-3] !== 1'b0))
            $fatal(1, "602 stream did not commit SP destination tag");
        if (!CPU_602 && (inspect_sp_o != 32'd0 || inspect_lt_o != 32'd0))
            $fatal(1, "603e stream exposed 602 tags");
        inspect_fpr_index_i = 5'd3;
        #1;
        if (inspect_fpr_o != expected_value || store_valid_o || store_o.write)
            $fatal(1, "stream final FPR/store state mismatch store=%h", store_o);
        $display("%s FPU shell stream PASS: %0d issued, %0d forwarded, %0d committed",
                 CPU_602 ? "602" : "603e", issued, forwarded, committed);
        $finish;
    end
endmodule
`default_nettype wire
