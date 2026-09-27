`default_nettype none
module tb_ppc_fpu_shell;
    import ppc_pkg::*;
    import ppc_fpu_pkg::*;

    logic clk_i = 1'b0;
    always #5 clk_i <= ~clk_i;
    logic rst_ni;
    logic issue_valid_i, issue_ready_o;
    ppc_fpu_issue_t issue_i;
    logic result_valid_o;
    ppc_fpu_result_t result_o;
    logic commit_valid_i, commit_ready_o;
    completion_tag_t commit_tag_i;
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
    logic [31:0] inspect_fpscr_o;
    int checks;
    ppc_fpu_result_t held;

    ppc_fpu dut (.*);

    function automatic completion_tag_t tag(input logic [2:0] index, input logic [7:0] generation);
        completion_tag_t value;
        value.index = index;
        value.generation = generation;
        return value;
    endfunction

    function automatic logic [31:0] fp_insn(
        input logic [5:0] primary, input logic [4:0] destination,
        input logic [4:0] a, input logic [4:0] b, input logic [9:0] xo
    );
        return {primary, destination, a, b, xo, 1'b0};
    endfunction

    function automatic logic [31:0] dform(
        input logic [5:0] primary, input logic [4:0] target,
        input logic [4:0] base, input logic [15:0] displacement
    );
        return {primary, target, base, displacement};
    endfunction

    task automatic send_issue(
        input logic [31:0] instruction, input completion_tag_t identity,
        input logic [31:0] base, input logic [31:0] index, input logic msr_fp
    );
        @(negedge clk_i);
        if (!issue_ready_o) $fatal(1, "issue busy");
        issue_i = '0;
        issue_i.tag = identity;
        issue_i.insn = instruction;
        issue_i.gpr_a = base;
        issue_i.gpr_b = index;
        issue_i.msr_fp = msr_fp;
        issue_valid_i = 1'b1;
        @(posedge clk_i);
        #1;
        issue_valid_i = 1'b0;
    endtask

    task automatic await_result(input completion_tag_t identity);
        int waited;
        waited = 0;
        while (!result_valid_o) begin
            @(negedge clk_i);
            waited = waited + 1;
            if (waited > 1024) $fatal(1, "result timeout tag=%h", identity);
        end
        if (result_o.tag !== identity) $fatal(1, "result tag mismatch");
        held = result_o;
        repeat (2) begin
            @(posedge clk_i);
            #1;
            if (!result_valid_o || result_o !== held)
                $fatal(1, "held result changed");
        end
        checks = checks + 1;
    endtask

    task automatic commit(input completion_tag_t identity);
        @(negedge clk_i);
        commit_tag_i = identity;
        commit_valid_i = 1'b1;
        #1;
        if (!commit_ready_o) $fatal(1, "matching commit not ready");
        @(posedge clk_i);
        #1;
        commit_valid_i = 1'b0;
        checks = checks + 1;
    endtask

    task automatic load_fpr(
        input int register_index, input logic [63:0] bits,
        input int generation
    );
        completion_tag_t identity;
        identity = tag(register_index % 5, generation);
        send_issue(dform(50, register_index, 1, 0), identity, 32'h00001000, 0, 1'b1);
        @(negedge clk_i);
        if (!mem_req_valid_o || mem_req_o.write || mem_req_o.size_bytes != 4'd8 ||
            mem_req_o.ea != 32'h00001000 || mem_req_o.tag != identity ||
            mem_req_o.data != 64'd0)
            $fatal(1, "lfd preparation packet");
        mem_req_ready_i = 1'b1;
        @(posedge clk_i);
        #1;
        mem_req_ready_i = 1'b0;
        @(negedge clk_i);
        mem_rsp_i = '0;
        mem_rsp_i.tag = identity;
        mem_rsp_i.data = bits;
        mem_rsp_valid_i = 1'b1;
        #1;
        if (!mem_rsp_ready_o) $fatal(1, "load response not accepted");
        @(posedge clk_i);
        #1;
        mem_rsp_valid_i = 1'b0;
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            !result_o.fpr_write || result_o.fpr_value != bits)
            $fatal(1, "lfd raw result");
        commit(identity);
        inspect_fpr_index_i = 5'(register_index);
        #1;
        if (inspect_fpr_o !== bits) $fatal(1, "lfd commit value");
        checks = checks + 3;
    endtask

    initial begin
        rst_ni = 1'b0;
        issue_valid_i = 1'b0;
        issue_i = '0;
        commit_valid_i = 1'b0;
        commit_tag_i = '0;
        abort_valid_i = 1'b0;
        abort_tag_i = '0;
        kill_all_i = 1'b0;
        mem_req_ready_i = 1'b0;
        mem_rsp_valid_i = 1'b0;
        mem_rsp_i = '0;
        store_ready_i = 1'b0;
        inspect_fpr_index_i = '0;
        checks = 0;
        repeat (3) @(negedge clk_i);
        rst_ni = 1'b1;
        #1;
        if (store_valid_o || store_o.write) $fatal(1, "spurious store after reset");

        load_fpr(1, 64'h3ff0_0000_0000_0000, 1);
        load_fpr(2, 64'h4000_0000_0000_0000, 2);
        load_fpr(3, 64'd0, 3);
        load_fpr(4, 64'd0, 4);

        send_issue(fp_insn(63, 3, 1, 2, 21), tag(0, 5), 0, 0, 1'b1);
        await_result(tag(0, 5));
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value != 64'h4008_0000_0000_0000)
            $fatal(1, "fadd result");
        inspect_fpr_index_i = 5'd3;
        #1;
        if (inspect_fpr_o != 64'd0 || inspect_fpscr_o != 32'd0)
            $fatal(1, "architectural state changed before commit");
        @(negedge clk_i);
        commit_valid_i = 1'b1;
        commit_tag_i = tag(0, 6);
        #1;
        if (commit_ready_o || !result_valid_o) $fatal(1, "stale commit accepted");
        commit_valid_i = 1'b0;
        commit(tag(0, 5));
        #1;
        if (inspect_fpr_o != 64'h4008_0000_0000_0000)
            $fatal(1, "fadd commit value");
        checks = checks + 4;

        send_issue(fp_insn(63, 4, 1, 2, 21), tag(1, 6), 0, 0, 1'b1);
        await_result(tag(1, 6));
        @(negedge clk_i);
        abort_tag_i = tag(1, 6);
        abort_valid_i = 1'b1;
        @(posedge clk_i);
        #1;
        abort_valid_i = 1'b0;
        inspect_fpr_index_i = 5'd4;
        #1;
        if (inspect_fpr_o != 64'd0 || result_valid_o)
            $fatal(1, "abort changed FPR or left result");
        checks = checks + 2;

        send_issue(fp_insn(63, 4, 1, 2, 21), tag(2, 7), 0, 0, 1'b0);
        await_result(tag(2, 7));
        if (result_o.exception != FPU_UNAVAILABLE || result_o.fpr_write)
            $fatal(1, "MSR FP unavailable");
        commit(tag(2, 7));
        checks = checks + 1;

        send_issue(fp_insn(63, 4, 1, 2, 22), tag(3, 8), 0, 0, 1'b1);
        await_result(tag(3, 8));
        if (result_o.exception != FPU_ILLEGAL) $fatal(1, "fsqrt must be illegal");
        commit(tag(3, 8));
        checks = checks + 1;

        $display("PASS PPC FPU shell checks=%0d", checks);
        $finish;
    end
endmodule
`default_nettype wire
