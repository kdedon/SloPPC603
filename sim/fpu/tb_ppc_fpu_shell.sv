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

    function automatic logic [31:0] fp_aform(
        input logic [5:0] primary, input logic [4:0] destination,
        input logic [4:0] a, input logic [4:0] b,
        input logic [4:0] c, input logic [4:0] xo, input logic record_bit
    );
        return {primary, destination, a, b, c, xo, record_bit};
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

    task automatic load_single_fpr(
        input logic [4:0] register_index, input logic [31:0] bits,
        input logic [63:0] expected_bits, input logic [7:0] generation
    );
        completion_tag_t identity;
        logic [31:0] previous_fpscr;
        previous_fpscr = inspect_fpscr_o;
        identity = tag(3'(int'(register_index) % 5), generation);
        send_issue(dform(48, register_index, 1, 0), identity, 32'h00001000, 0, 1'b1);
        @(negedge clk_i);
        if (!mem_req_valid_o || mem_req_o.write || mem_req_o.size_bytes != 4'd4 ||
            mem_req_o.ea != 32'h00001000 || mem_req_o.tag != identity)
            $fatal(1, "lfs preparation packet");
        mem_req_ready_i = 1'b1;
        @(posedge clk_i);
        #1;
        mem_req_ready_i = 1'b0;
        @(negedge clk_i);
        mem_rsp_i = '0;
        mem_rsp_i.tag = identity;
        mem_rsp_i.data = {32'd0, bits};
        mem_rsp_valid_i = 1'b1;
        @(posedge clk_i);
        #1;
        mem_rsp_valid_i = 1'b0;
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value != expected_bits || result_o.fpscr_write)
            $fatal(1, "lfs raw widening result");
        commit(identity);
        inspect_fpr_index_i = register_index;
        #1;
        if (inspect_fpr_o != expected_bits || inspect_fpscr_o != previous_fpscr)
            $fatal(1, "lfs raw/FPSCR commit");
        checks = checks + 3;
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
        input logic [4:0] register_index, input logic [63:0] bits,
        input logic [7:0] generation
    );
        completion_tag_t identity;
        identity = tag(3'(int'(register_index) % 5), generation);
        send_issue(dform(50, 5'(register_index), 1, 0), identity, 32'h00001000, 0, 1'b1);
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

    task automatic prepare_store(
        input logic [31:0] instruction, input completion_tag_t identity,
        input logic [31:0] base, input logic [31:0] ea,
        input logic [3:0] size_bytes, input logic [63:0] bits,
        input logic fault
    );
        send_issue(instruction, identity, base, 0, 1'b1);
        @(negedge clk_i);
        if (!mem_req_valid_o || !mem_req_o.write || mem_req_o.tag != identity ||
            mem_req_o.ea != ea || mem_req_o.size_bytes != size_bytes ||
            mem_req_o.data != bits)
            $fatal(1, "store preparation packet");
        mem_req_ready_i = 1'b1;
        @(posedge clk_i);
        #1;
        mem_req_ready_i = 1'b0;
        @(negedge clk_i);
        mem_rsp_i = '0;
        mem_rsp_i.tag = identity;
        mem_rsp_i.fault = fault;
        mem_rsp_i.fault_code = 4'hb;
        mem_rsp_i.fault_info = 32'h12345678;
        mem_rsp_valid_i = 1'b1;
        #1;
        if (!mem_rsp_ready_o) $fatal(1, "store response not accepted");
        @(posedge clk_i);
        #1;
        mem_rsp_valid_i = 1'b0;
        await_result(identity);
        if (fault) begin
            if (result_o.exception != FPU_MEMORY_FAULT || result_o.store ||
                result_o.gpr_update || result_o.fault_code != 4'hb ||
                result_o.fault_info != 32'h12345678)
                $fatal(1, "store fault disposition");
        end else if (result_o.exception != FPU_NO_EXCEPTION || !result_o.store) begin
            $fatal(1, "prepared store result");
        end
        checks = checks + 4;
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
        if (store_valid_o || store_o != '0) $fatal(1, "spurious store after reset");

        load_fpr(1, 64'h3ff0_0000_0000_0000, 1);
        load_fpr(2, 64'h4000_0000_0000_0000, 2);
        load_fpr(3, 64'd0, 3);
        load_fpr(4, 64'd0, 4);
        load_single_fpr(5, 32'h7f80_0001, 64'h7ff0_0000_2000_0000, 15);
        load_fpr(6, 64'h8000_0000_0000_0000, 16);

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

        prepare_store(dform(54, 3, 1, 0), tag(4, 9), 32'h00002000,
                      32'h00002000, 4'd8, 64'h4008_0000_0000_0000, 1'b0);
        if (store_valid_o) $fatal(1, "store visible before commit");
        @(negedge clk_i);
        commit_valid_i = 1'b1;
        commit_tag_i = tag(4, 10);
        #1;
        if (store_valid_o || commit_ready_o) $fatal(1, "stale store commit");
        commit_tag_i = tag(4, 9);
        #1;
        if (!store_valid_o || commit_ready_o || store_o.data != 64'h4008_0000_0000_0000)
            $fatal(1, "store commit backpressure");
        kill_all_i = 1'b1;
        #1;
        if (store_valid_o || commit_ready_o) $fatal(1, "killed store exposed");
        @(posedge clk_i);
        #1;
        kill_all_i = 1'b0;
        commit_valid_i = 1'b0;
        if (result_valid_o) $fatal(1, "killed store result remains");
        checks = checks + 5;

        prepare_store(dform(54, 3, 1, 0), tag(0, 11), 32'h00002000,
                      32'h00002000, 4'd8, 64'h4008_0000_0000_0000, 1'b0);
        @(negedge clk_i);
        store_ready_i = 1'b1;
        commit_valid_i = 1'b1;
        commit_tag_i = tag(0, 11);
        #1;
        if (!store_valid_o || !commit_ready_o || store_o.tag != tag(0, 11))
            $fatal(1, "authorized store handshake");
        @(posedge clk_i);
        #1;
        commit_valid_i = 1'b0;
        store_ready_i = 1'b0;
        if (result_valid_o || store_valid_o) $fatal(1, "duplicate store");
        checks = checks + 3;

        prepare_store(dform(55, 3, 1, 4), tag(1, 12), 32'h00003000,
                      32'h00003004, 4'd8, 64'h4008_0000_0000_0000, 1'b1);
        if (store_valid_o) $fatal(1, "faulted store visible");
        commit(tag(1, 12));
        checks = checks + 1;

        send_issue(dform(51, 3, 0, 0), tag(2, 13), 0, 0, 1'b1);
        await_result(tag(2, 13));
        if (result_o.exception != FPU_ILLEGAL || result_o.gpr_update || mem_req_valid_o)
            $fatal(1, "update form with RA=0");
        commit(tag(2, 13));
        checks = checks + 1;

        send_issue(dform(50, 3, 1, 2), tag(3, 14), 32'h00004000, 0, 1'b1);
        await_result(tag(3, 14));
        if (result_o.exception != FPU_ALIGNMENT || result_o.gpr_update || mem_req_valid_o)
            $fatal(1, "misaligned floating load");
        commit(tag(3, 14));
        checks = checks + 1;

        prepare_store(dform(52, 5, 1, 0), tag(4, 17), 32'h00005000,
                      32'h00005000, 4'd4, 64'h0000_0000_7f80_0001, 1'b0);
        if (result_o.fpscr_write) $fatal(1, "stfs changed FPSCR");
        @(negedge clk_i);
        abort_valid_i = 1'b1;
        abort_tag_i = tag(4, 17);
        @(posedge clk_i);
        #1;
        abort_valid_i = 1'b0;
        if (store_valid_o) $fatal(1, "aborted stfs visible");
        checks = checks + 2;

        send_issue(fp_aform(63, 7, 6, 2, 5, 23, 1'b1), tag(0, 18), 0, 0, 1'b1);
        await_result(tag(0, 18));
        if (result_o.fpr_value != 64'h7ff0_0000_2000_0000 ||
            result_o.fpscr_write || !result_o.cr_write || result_o.cr_field != 3'd1 ||
            result_o.cr_value != inspect_fpscr_o[31:28])
            $fatal(1, "fsel negative zero/raw SNaN/Rc");
        commit(tag(0, 18));
        inspect_fpr_index_i = 5'd7;
        #1;
        if (inspect_fpr_o != 64'h7ff0_0000_2000_0000)
            $fatal(1, "fsel raw commit");
        checks = checks + 3;

        send_issue(fp_aform(63, 8, 5, 2, 1, 23, 1'b0), tag(1, 19), 0, 0, 1'b1);
        await_result(tag(1, 19));
        if (result_o.fpr_value != 64'h4000_0000_0000_0000 || result_o.fpscr_write)
            $fatal(1, "fsel NaN selector");
        commit(tag(1, 19));
        checks = checks + 2;

        send_issue(dform(50, 9, 1, 0), tag(2, 20), 32'h00006000, 0, 1'b1);
        @(negedge clk_i);
        mem_req_ready_i = 1'b1;
        mem_rsp_i = '0;
        mem_rsp_i.tag = tag(2, 20);
        mem_rsp_i.data = 64'h4008_0000_0000_0000;
        mem_rsp_valid_i = 1'b1;
        #1;
        if (!mem_req_valid_o || mem_rsp_ready_o)
            $fatal(1, "matching early LSU response was consumed");
        @(posedge clk_i);
        #1;
        mem_req_ready_i = 1'b0;
        if (!mem_rsp_ready_o) $fatal(1, "held LSU response not accepted");
        @(posedge clk_i);
        #1;
        mem_rsp_valid_i = 1'b0;
        await_result(tag(2, 20));
        if (result_o.fpr_value != 64'h4008_0000_0000_0000)
            $fatal(1, "early LSU response data");
        commit(tag(2, 20));
        checks = checks + 3;

        send_issue(fp_insn(63, 4, 1, 2, 18), tag(3, 21), 0, 0, 1'b1);
        repeat (5) @(negedge clk_i);
        if (result_valid_o) $fatal(1, "divide unexpectedly finished before kill");
        kill_all_i = 1'b1;
        @(posedge clk_i);
        #1;
        kill_all_i = 1'b0;
        repeat (80) begin
            @(posedge clk_i);
            #1;
            if (result_valid_o) $fatal(1, "killed divide completed");
        end
        checks = checks + 1;

        if (inspect_fpscr_o[25]) $fatal(1, "XX set before estimate test");
        send_issue(fp_insn(59, 10, 0, 3, 24), tag(4, 22), 0, 0, 1'b1);
        await_result(tag(4, 22));
        if (result_o.exception != FPU_NO_EXCEPTION || result_o.fpscr_value[25])
            $fatal(1, "fres set XX");
        commit(tag(4, 22));
        if (inspect_fpscr_o[25]) $fatal(1, "fres committed XX");
        checks = checks + 2;

        send_issue(fp_insn(63, 11, 0, 3, 26), tag(0, 23), 0, 0, 1'b1);
        await_result(tag(0, 23));
        if (result_o.exception != FPU_NO_EXCEPTION || result_o.fpscr_value[25])
            $fatal(1, "frsqrte set XX");
        commit(tag(0, 23));
        if (inspect_fpscr_o[25]) $fatal(1, "frsqrte committed XX");
        checks = checks + 2;

        $display("PASS PPC FPU shell checks=%0d", checks);
        $finish;
    end
endmodule
`default_nettype wire
