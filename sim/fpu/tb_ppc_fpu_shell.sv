// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
module tb_ppc_fpu_shell;
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
    completion_tag_t store_peek_tag_i;
    logic store_peek_valid_o;
    logic [63:0] store_peek_data_o;
    // A publishing store, looked up by tag, matches the store port.
    assign store_peek_tag_i = store_o.tag;
    always @(posedge clk_i)
        if (store_valid_o && (!store_peek_valid_o || store_peek_data_o != store_o.data))
            $fatal(1, "store peek %h disagrees with store port %h", store_peek_data_o, store_o.data);
    logic [4:0] inspect_fpr_index_i;
    logic [63:0] inspect_fpr_o;
    logic [31:0] inspect_fpscr_o;
    logic [31:0] inspect_sp_o, inspect_lt_o;
    logic forward_valid_o;
    ppc_fpu_forward_t forward_o;
    logic forward1_valid_o;
    ppc_fpu_forward_t forward1_o;
    ppc_fpu_forward_data_t forward_data_o, forward1_data_o;
    ppc_fpu_forward_data_t last_forward_data;
    logic payload_due, payload1_due;
    int checks;
    ppc_fpu_result_t held;
    ppc_fpu_forward_t last_forward;
    logic [31:0] expected_status;
    completion_tag_t status_tag;

`ifdef FPU_COMPACT
    ppc_fpu_compact dut (.*);
`else
    ppc_fpu dut (.*);
`endif
    assign issue1_valid_i = 1'b0;
    assign issue1_i = '0;
    assign commit1_valid_i = 1'b0;
    assign commit1_tag_i = '0;

    always @(posedge clk_i)
        if (rst_ni) begin
            if (issue1_ready_o || commit1_ready_o)
                $fatal(1, "unrequested second lane handshake");
            if (result1_valid_o && result1_o.tag == result_o.tag)
                $fatal(1, "second result reused first tag packet=%h", result1_o);
            if (forward1_valid_o &&
                (!forward_valid_o || forward1_o.tag == forward_o.tag ||
                 !(forward1_o.fpr_write || forward1_o.cr_write)))
                $fatal(1, "invalid second forward packet=%h", forward1_o);
        end


    // A notification's payload arrives on the following cycle.
    always @(posedge clk_i)
        if (!rst_ni) begin
            payload_due <= 1'b0;
            payload1_due <= 1'b0;
            last_forward_data <= '0;
        end else begin
            if (!payload1_due && forward1_data_o != '0)
                $fatal(1, "second forward payload without notification");
            payload_due <= forward_valid_o;
            payload1_due <= forward1_valid_o;
            if (payload_due) last_forward_data <= forward_data_o;
        end

    always @(posedge clk_i)
        if (!rst_ni) last_forward <= '0;
        else if (forward_valid_o) begin
            if (!(forward_o.fpr_write || forward_o.cr_write))
                $fatal(1, "603e forward packet without a destination");
            last_forward <= forward_o;
        end

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

    task automatic check_arith_opcode(
        input logic [5:0] primary, input logic [4:0] xo,
        input logic [63:0] expected_bits, input logic [7:0] generation
    );
        logic [31:0] instruction;
        completion_tag_t identity;
        identity = tag(3'd2, generation);
        if (xo == 5'd25)
            instruction = fp_aform(primary, 15, 1, 0, 3, xo, 1'b0);
        else if (xo >= 5'd28)
            instruction = fp_aform(primary, 15, 1, 2, 3, xo, 1'b0);
        else
            instruction = fp_aform(primary, 15, 1, 2, 0, xo, 1'b0);
        send_issue(instruction, identity, 0, 0, 1'b1);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION || !result_o.fpr_write ||
            result_o.fpr_value != expected_bits)
            $fatal(1, "decoded arithmetic primary=%0d xo=%0d got=%h expected=%h",
                   primary, xo, result_o.fpr_value, expected_bits);
        commit(identity);
        inspect_fpr_index_i = 5'd15;
        #1;
        if (inspect_fpr_o != expected_bits)
            $fatal(1, "decoded arithmetic commit primary=%0d xo=%0d", primary, xo);
        checks += 2;
    endtask

    task automatic check_illegal_fp0(
        input logic [31:0] instruction, input logic [7:0] generation
    );
        completion_tag_t identity;
        identity = tag(3'd4, generation);
        send_issue(instruction, identity, 0, 0, 1'b0);
        await_result(identity);
        if (result_o.exception != FPU_ILLEGAL || result_o.fpr_write ||
            result_o.fpscr_write || result_o.store || mem_req_valid_o)
            $fatal(1, "illegal FP encoding lost priority to MSR[FP]=0 insn=%h",
                   instruction);
        commit(identity);
        checks++;
    endtask

    task automatic send_issue_fe(
        input logic [31:0] instruction, input completion_tag_t identity,
        input logic fe0, input logic fe1
    );
        @(negedge clk_i);
        if (!issue_ready_o) $fatal(1, "issue busy with FE mode");
        issue_i = '0;
        issue_i.tag = identity;
        issue_i.insn = instruction;
        issue_i.msr_fp = 1'b1;
        issue_i.msr_fe0 = fe0;
        issue_i.msr_fe1 = fe1;
        issue_valid_i = 1'b1;
        @(posedge clk_i);
        #1;
        issue_valid_i = 1'b0;
    endtask

    task automatic seed_frfi(input logic [7:0] generation);
        completion_tag_t identity;
        identity = tag(3'd1, generation);
        send_issue(fp_insn(63, 5'd13, 0, 0, 38), identity, 0, 0, 1'b1);
        await_result(identity);
        commit(identity);
        identity = tag(3'd1, generation + 8'd1);
        send_issue(fp_insn(63, 5'd14, 0, 0, 38), identity, 0, 0, 1'b1);
        await_result(identity);
        commit(identity);
        if (inspect_fpscr_o[18:17] != 2'b11)
            $fatal(1, "estimate FR/FI seeding failed");
        checks += 2;
    endtask

    task automatic check_estimate_frfi(
        input logic [5:0] primary, input logic [9:0] xo,
        input logic [4:0] source, input logic expected_write,
        input logic [4:0] cause_physical_bit, input logic [7:0] generation
    );
        completion_tag_t identity;
        identity = tag(3'd2, generation);
        send_issue(fp_insn(primary, 28, 0, source, xo), identity, 0, 0, 1'b1);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_write != expected_write ||
            result_o.fpscr_value[18:17] != 2'b00 ||
            !result_o.fpscr_value[cause_physical_bit])
            $fatal(1, "estimate exceptional FR/FI primary=%0d xo=%0d source=%0d",
                   primary, xo, source);
        commit(identity);
        if (inspect_fpscr_o[18:17] != 2'b00)
            $fatal(1, "estimate FR/FI not cleared on commit");
        checks += 2;
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

    function automatic logic forward_payload_matches(
        input ppc_fpu_forward_data_t data);
        return (!last_forward.fpr_write ||
                (data.fpr_value == result_o.fpr_value &&
                 data.fpr_sp == result_o.fpr_sp &&
                 data.fpr_lt == result_o.fpr_lt)) &&
               (!last_forward.cr_write || data.cr_value == result_o.cr_value);
    endfunction

    task automatic await_result(input completion_tag_t identity);
        int waited;
        ppc_fpu_forward_t expected_forward;
        waited = 0;
        while (!result_valid_o) begin
            @(negedge clk_i);
            waited = waited + 1;
            if (waited > 1024) $fatal(1, "result timeout tag=%h", identity);
        end
        if (result_o.tag !== identity) $fatal(1, "result tag mismatch");
        if (last_forward.tag == identity) begin
            expected_forward = '0;
            expected_forward.tag = result_o.tag;
            expected_forward.fpr_write = result_o.fpr_write;
            expected_forward.fpr_index = result_o.fpr_index;
            expected_forward.cr_write = result_o.cr_write;
            expected_forward.cr_field = result_o.cr_field;
            if (last_forward !== expected_forward ||
                !forward_payload_matches(payload_due ? forward_data_o :
                                         last_forward_data))
                $fatal(1, "forward packet differs from completed result tag=%h", identity);
        end
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
            $fatal(1, "lfd preparation packet %h", mem_req_o);
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

    task automatic load_memory_form(
        input logic [31:0] instruction, input completion_tag_t identity,
        input logic [31:0] base, input logic [31:0] index,
        input logic [31:0] ea, input logic [3:0] size_bytes,
        input logic [63:0] memory_bits, input logic [63:0] expected_fpr,
        input logic expected_update
    );
        send_issue(instruction, identity, base, index, 1'b1);
        @(negedge clk_i);
        if (!mem_req_valid_o || mem_req_o.write ||
            mem_req_o.ea != ea || mem_req_o.tag != identity ||
            mem_req_o.size_bytes != size_bytes)
            $fatal(1, "indexed/update load prepare");
        mem_req_ready_i = 1'b1;
        @(posedge clk_i);
        #1;
        mem_req_ready_i = 1'b0;
        @(negedge clk_i);
        mem_rsp_i = '0;
        mem_rsp_i.tag = identity;
        mem_rsp_i.data = memory_bits;
        mem_rsp_valid_i = 1'b1;
        @(posedge clk_i);
        #1;
        mem_rsp_valid_i = 1'b0;
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            !result_o.fpr_write || result_o.fpr_value != expected_fpr ||
            result_o.gpr_update != expected_update ||
            (expected_update && (result_o.gpr_value != ea ||
                                 result_o.gpr_index != 5'd1)))
            $fatal(1, "indexed/update load result");
        commit(identity);
        inspect_fpr_index_i = instruction[25:21];
        #1;
        if (inspect_fpr_o != expected_fpr)
            $fatal(1, "indexed/update load commit");
        checks += 3;
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
            mem_req_o.data != 64'd0)
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
        end else if (result_o.exception != FPU_NO_EXCEPTION || !result_o.store ||
                     store_o.data != bits) begin
            $fatal(1, "prepared store result data %h", store_o.data);
        end
        checks = checks + 4;
    endtask

    // Store rule for exponents above single range: WORD = FRS[0:1] || FRS[5:34].
    task automatic stfs_large(input logic [4:0] register_index,
                              input logic [63:0] bits, input logic [31:0] word,
                              input logic [7:0] generation);
        load_fpr(register_index, bits, generation);
        prepare_store(dform(52, register_index, 1, 0), tag(0, generation + 8'd1),
                      32'h00005000, 32'h00005000, 4'd4, {32'd0, word}, 1'b0);
        @(negedge clk_i);
        abort_valid_i = 1'b1;
        abort_tag_i = tag(0, generation + 8'd1);
        @(posedge clk_i);
        #1;
        abort_valid_i = 1'b0;
        if (store_valid_o) $fatal(1, "aborted large-exponent stfs visible");
        checks = checks + 1;
    endtask

    // Forward-bus and store-launch cycles for the dependent-distance test.
    localparam int FMR_DISTANCE = 3;
    localparam int STFD_DISTANCE = 0;
    int cycle_now = 0;
    int forward_cycle [0:255];
    int store_launch_cycle = -1;
    always @(posedge clk_i) begin
        cycle_now <= cycle_now + 1;
        if (forward_valid_o) forward_cycle[forward_o.tag.generation] <= cycle_now;
        if (forward1_valid_o) forward_cycle[forward1_o.tag.generation] <= cycle_now;
        if (mem_req_valid_o && mem_req_o.write && mem_req_o.tag.generation == 8'd253 &&
            store_launch_cycle < 0)
            store_launch_cycle <= cycle_now;
    end

    task automatic send_when_ready(input logic [31:0] instruction,
                                   input completion_tag_t identity,
                                   input logic [31:0] base);
        int attempts;
        @(negedge clk_i);
        issue_i = '0;
        issue_i.tag = identity;
        issue_i.insn = instruction;
        issue_i.gpr_a = base;
        issue_i.msr_fp = 1'b1;
        issue_valid_i = 1'b1;
        attempts = 0;
        #1;
        while (!issue_ready_o) begin
            @(negedge clk_i);
            #1;
            attempts++;
            if (attempts > 40) $fatal(1, "dependent issue timeout tag=%h", identity);
        end
        @(posedge clk_i);
        #1;
        issue_valid_i = 1'b0;
    endtask

    // Back-to-back consumers of an arithmetic result: fadd, fmr and stfd.
    task automatic dependent_distances();
        int attempts;
        send_issue(fp_insn(63, 21, 28, 28, 21), tag(0, 250), 0, 0, 1'b1);
        send_when_ready(fp_insn(63, 22, 21, 28, 21), tag(1, 251), 0);
        send_when_ready(fp_insn(63, 23, 0, 22, 72), tag(2, 252), 0);
        send_when_ready(dform(54, 22, 1, 0), tag(3, 253), 32'h00006000);
        attempts = 0;
        while (!(mem_req_valid_o && mem_req_o.tag == tag(3, 253))) begin
            @(negedge clk_i);
            attempts++;
            if (attempts > 40) $fatal(1, "dependent stfd did not launch");
        end
        if (mem_req_o.data != 64'd0)
            $fatal(1, "dependent stfd preparation data %h", mem_req_o.data);
        mem_req_ready_i = 1'b1;
        @(posedge clk_i);
        #1;
        mem_req_ready_i = 1'b0;
        @(negedge clk_i);
        mem_rsp_i = '0;
        mem_rsp_i.tag = tag(3, 253);
        mem_rsp_valid_i = 1'b1;
        @(posedge clk_i);
        #1;
        mem_rsp_valid_i = 1'b0;
        await_result(tag(0, 250));
        if (result_o.fpr_value != 64'h4810_0000_0000_0000) $fatal(1, "dependent producer");
        commit(tag(0, 250));
        await_result(tag(1, 251));
        if (result_o.fpr_value != 64'h4818_0000_0000_0000) $fatal(1, "dependent fadd");
        commit(tag(1, 251));
        await_result(tag(2, 252));
        if (result_o.fpr_value != 64'h4818_0000_0000_0000) $fatal(1, "dependent fmr");
        commit(tag(2, 252));
        await_result(tag(3, 253));
        if (!result_o.store || store_o.data != 64'h4818_0000_0000_0000)
            $fatal(1, "dependent stfd result data %h", store_o.data);
        @(negedge clk_i);
        abort_valid_i = 1'b1;
        abort_tag_i = tag(3, 253);
        @(posedge clk_i);
        #1;
        abort_valid_i = 1'b0;
        $display("DEPENDENT fadd->fadd=%0d fadd->fmr=%0d fadd->stfd=%0d",
                 forward_cycle[251] - forward_cycle[250],
                 forward_cycle[252] - forward_cycle[251],
                 store_launch_cycle - forward_cycle[251]);
        if (forward_cycle[251] - forward_cycle[250] != 3 ||
            forward_cycle[252] - forward_cycle[251] != FMR_DISTANCE ||
            store_launch_cycle - forward_cycle[251] != STFD_DISTANCE)
            $fatal(1, "dependent distance changed");
        checks = checks + 8;
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
        if (inspect_sp_o != 32'd0 || inspect_lt_o != 32'd0)
            $fatal(1, "603e elaboration exposed 602 tag state");

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
        check_illegal_fp0(fp_insn(63, 4, 1, 2, 22), 100);
        check_illegal_fp0(fp_insn(59, 4, 1, 2, 22), 101);
        check_illegal_fp0(fp_insn(63, 4, 1, 2, 19), 102);
        check_illegal_fp0(fp_insn(59, 4, 1, 2, 19), 103);
        check_illegal_fp0(fp_aform(63, 4, 1, 2, 1, 21, 1'b0), 104);
        check_illegal_fp0(fp_aform(63, 4, 1, 2, 0, 25, 1'b0), 105);

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
        stfs_large(5'd28, 64'h4800_0000_0000_0000, 32'h4000_0000, 8'd242);
        stfs_large(5'd29, 64'h7e37_e43c_8800_759c, 32'h71bf_21e4, 8'd244);
        stfs_large(5'd30, 64'hfe37_e43c_8800_759c, 32'hf1bf_21e4, 8'd246);
        stfs_large(5'd31, 64'h7fef_ffff_ffff_ffff, 32'h7f7f_ffff, 8'd248);
`ifndef FPU_COMPACT
        // Overlapped dependent issue and its cycle distances are FULL only.
        dependent_distances();
`endif

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

        // Each architected bit is set and cleared through its own FPSCR
        // instruction.  Field-zero writes clear the prior sticky state, so
        // the expected summaries here come from the manual's OR rules.
        for (int bit_number = 0; bit_number < 32; bit_number++) begin
            status_tag = tag(3'd1, 8'(40 + 2*bit_number));
            send_issue(fp_insn(63, 0, 0, 4, 711) | 32'h01fe0000,
                       status_tag, 0, 0, 1'b1);
            await_result(status_tag);
            if (result_o.exception != FPU_NO_EXCEPTION ||
                result_o.fpscr_value != 32'd0)
                $fatal(1, "mtfsf all-field zero bit=%0d", bit_number);
            commit(status_tag);
            if (inspect_fpscr_o != 32'd0)
                $fatal(1, "mtfsf all-field commit bit=%0d", bit_number);

            status_tag = tag(3'd2, 8'(41 + 2*bit_number));
            send_issue(fp_insn(63, 5'(bit_number), 0, 0, 38),
                       status_tag, 0, 0, 1'b1);
            await_result(status_tag);
            expected_status = 32'd0;
            if (bit_number != 1 && bit_number != 2 && bit_number != 20)
                expected_status[31-bit_number] = 1'b1;
            if ((bit_number >= 3 && bit_number <= 12) ||
                (bit_number >= 21 && bit_number <= 23))
                expected_status[31] = 1'b1;
            if ((bit_number >= 7 && bit_number <= 12) ||
                (bit_number >= 21 && bit_number <= 23))
                expected_status[29] = 1'b1;
            if (result_o.exception != FPU_NO_EXCEPTION ||
                result_o.fpscr_value != expected_status)
                $fatal(1, "mtfsb1 bit=%0d got=%h expected=%h",
                       bit_number, result_o.fpscr_value, expected_status);
            commit(status_tag);
            if (inspect_fpscr_o != expected_status)
                $fatal(1, "mtfsb1 commit bit=%0d", bit_number);

            status_tag = tag(3'd3, 8'(120 + bit_number));
            send_issue(fp_insn(63, 5'(bit_number), 0, 0, 70),
                       status_tag, 0, 0, 1'b1);
            await_result(status_tag);
            expected_status = 32'd0;
            if ((bit_number >= 3 && bit_number <= 12) ||
                (bit_number >= 21 && bit_number <= 23))
                expected_status[31] = 1'b1;
            if (result_o.exception != FPU_NO_EXCEPTION ||
                result_o.fpscr_value != expected_status)
                $fatal(1, "mtfsb0 bit=%0d got=%h expected=%h",
                       bit_number, result_o.fpscr_value, expected_status);
            commit(status_tag);
            if (inspect_fpscr_o != expected_status)
                $fatal(1, "mtfsb0 commit bit=%0d", bit_number);
            checks = checks + 6;
        end

        send_issue(fp_insn(63, 5'd7, 0, 0, 38), tag(1, 190), 0, 0, 1'b1);
        await_result(tag(1, 190));
        if (result_o.fpscr_value != 32'ha1000000)
            $fatal(1, "invalid cause did not set FX/VX");
        commit(tag(1, 190));
        send_issue(fp_insn(63, 5'd12, 5'd4, 0, 64), tag(2, 191), 0, 0, 1'b1);
        await_result(tag(2, 191));
        if (result_o.cr_field != 3'd3 || result_o.cr_value != 4'h1 ||
            result_o.fpscr_value != 32'h80000000)
            $fatal(1, "mcrfs did not copy source field and clear its cause");
        commit(tag(2, 191));
        checks = checks + 4;

        send_issue(fp_insn(63, 5'd3, 0, 0, 38), tag(3, 192), 0, 0, 1'b1);
        await_result(tag(3, 192));
        commit(tag(3, 192));
        send_issue_fe(fp_insn(63, 5'd25, 0, 0, 38), tag(4, 193), 1'b1, 1'b0);
        await_result(tag(4, 193));
        if (result_o.exception != FPU_FP_ENABLED ||
            result_o.fpscr_value != 32'hd0000040)
            $fatal(1, "FE0/FEX enabled on consecutive FPSCR writers");
        commit(tag(4, 193));
        send_issue(fp_insn(63, 5'd20, 0, 0, 64), tag(0, 194), 0, 0, 1'b1);
        await_result(tag(0, 194));
        if (result_o.cr_field != 3'd5 || result_o.cr_value != 4'hd ||
            result_o.fpscr_value != 32'h00000040)
            $fatal(1, "mcrfs field zero/FEX recompute");
        commit(tag(0, 194));
        send_issue_fe(fp_insn(63, 5'd3, 0, 0, 38), tag(1, 195), 1'b0, 1'b0);
        await_result(tag(1, 195));
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpscr_value != 32'hd0000040)
            $fatal(1, "FE00 must ignore enabled FPSCR cause");
        commit(tag(1, 195));
        send_issue(fp_insn(63, 5'd0, 0, 0, 64), tag(2, 196), 0, 0, 1'b1);
        await_result(tag(2, 196));
        commit(tag(2, 196));
        send_issue_fe(fp_insn(63, 5'd3, 0, 0, 38), tag(3, 197), 1'b0, 1'b1);
        await_result(tag(3, 197));
        if (result_o.exception != FPU_FP_ENABLED ||
            result_o.fpscr_value != 32'hd0000040)
            $fatal(1, "FE1/FEX enabled route");
        commit(tag(3, 197));
        checks = checks + 8;

        send_issue(fp_insn(63, 5'd20, 1, 2, 0), tag(4, 198), 0, 0, 1'b1);
        await_result(tag(4, 198));
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.cr_field != 3'd5 || result_o.cr_value != 4'h8 ||
            result_o.fpscr_value[15:12] != 4'h8)
            $fatal(1, "fcmpu ordered CR5 and FPCC");
        commit(tag(4, 198));
        send_issue(fp_insn(63, 5'd8, 5, 1, 0), tag(0, 199), 0, 0, 1'b1);
        await_result(tag(0, 199));
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.cr_field != 3'd2 || result_o.cr_value != 4'h1 ||
            !result_o.fpscr_value[24] || result_o.fpscr_value[19] ||
            result_o.fpscr_value[15:12] != 4'h1)
            $fatal(1, "fcmpu SNaN invalid cause/CR2/FPCC");
        commit(tag(0, 199));
        send_issue(fp_insn(63, 5'd16, 5, 1, 32), tag(1, 200), 0, 0, 1'b1);
        await_result(tag(1, 200));
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.cr_field != 3'd4 || result_o.cr_value != 4'h1 ||
            !result_o.fpscr_value[24] || !result_o.fpscr_value[19])
            $fatal(1, "fcmpo SNaN must add VXVC when VE=0");
        commit(tag(1, 200));
        send_issue(fp_insn(63, 12, 1, 2, 21) | 32'd1,
                   tag(2, 201), 0, 0, 1'b1);
        await_result(tag(2, 201));
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value != 64'h4008000000000000 ||
            !result_o.cr_write || result_o.cr_field != 3'd1 ||
            result_o.cr_value != result_o.fpscr_value[31:28])
            $fatal(1, "arithmetic Rc must copy final FPSCR field zero");
        commit(tag(2, 201));
        checks = checks + 8;

        prepare_store(dform(54, 3, 1, 0), tag(3, 202), 32'h00007000,
                      32'h00007000, 4'd8, 64'h4008000000000000, 1'b0);
        @(negedge clk_i);
        commit_valid_i = 1'b1;
        commit_tag_i = tag(3, 202);
        store_ready_i = 1'b1;
        #1;
        if (!store_valid_o || !commit_ready_o)
            $fatal(1, "held store not eligible before reset");
        rst_ni = 1'b0;
        #1;
        if (store_valid_o || commit_ready_o || result_valid_o || issue_ready_o ||
            mem_req_valid_o)
            $fatal(1, "reset exposed held store or public handshake");
        @(posedge clk_i);
        #1;
        commit_valid_i = 1'b0;
        store_ready_i = 1'b0;
        rst_ni = 1'b1;
        #1;
        if (result_valid_o || store_valid_o || inspect_fpscr_o != 32'd0)
            $fatal(1, "reset did not discard held store/status");
        checks = checks + 3;

        load_fpr(1, 64'h3ff0000000000000, 203);
        load_fpr(2, 64'h4000000000000000, 204);
        send_issue(fp_insn(63, 13, 1, 2, 18), tag(4, 205), 0, 0, 1'b1);
        repeat (4) @(negedge clk_i);
        if (result_valid_o) $fatal(1, "divide completed before reset test");
        rst_ni = 1'b0;
        #1;
        if (issue_ready_o || result_valid_o || mem_req_valid_o ||
            store_valid_o || commit_ready_o)
            $fatal(1, "reset published pending arithmetic");
        @(posedge clk_i);
        #1;
        rst_ni = 1'b1;
        repeat (35) begin
            @(posedge clk_i);
            #1;
            if (result_valid_o) $fatal(1, "reset divide returned stale result");
        end
        checks = checks + 2;

        send_issue(dform(50, 14, 1, 0), tag(0, 206), 32'h00008000, 0, 1'b1);
        @(negedge clk_i);
        if (!mem_req_valid_o || mem_req_o.tag != tag(0, 206))
            $fatal(1, "pending memory request absent before reset");
        rst_ni = 1'b0;
        #1;
        if (mem_req_valid_o || issue_ready_o || result_valid_o)
            $fatal(1, "reset published pending memory request");
        @(posedge clk_i);
        #1;
        rst_ni = 1'b1;
        mem_rsp_i = '0;
        mem_rsp_i.tag = tag(0, 206);
        mem_rsp_i.data = 64'h7ff0000000000001;
        mem_rsp_valid_i = 1'b1;
        #1;
        if (!mem_rsp_ready_o) $fatal(1, "stale memory reply did not drain");
        @(posedge clk_i);
        #1;
        mem_rsp_valid_i = 1'b0;
        if (result_valid_o) $fatal(1, "stale memory reply completed after reset");
        checks = checks + 3;

        load_fpr(1, 64'h3ff0000000000000, 207);
        load_fpr(2, 64'h4000000000000000, 208);
        load_fpr(3, 64'h4008000000000000, 209);
        for (int precision = 0; precision < 2; precision++) begin
            check_arith_opcode(precision == 0 ? 6'd63 : 6'd59,
                               5'd21, 64'h4008000000000000,
                               8'(210 + 8*precision));
            check_arith_opcode(precision == 0 ? 6'd63 : 6'd59,
                               5'd20, 64'hbff0000000000000,
                               8'(211 + 8*precision));
            check_arith_opcode(precision == 0 ? 6'd63 : 6'd59,
                               5'd25, 64'h4008000000000000,
                               8'(212 + 8*precision));
            check_arith_opcode(precision == 0 ? 6'd63 : 6'd59,
                               5'd18, 64'h3fe0000000000000,
                               8'(213 + 8*precision));
            check_arith_opcode(precision == 0 ? 6'd63 : 6'd59,
                               5'd29, 64'h4014000000000000,
                               8'(214 + 8*precision));
            check_arith_opcode(precision == 0 ? 6'd63 : 6'd59,
                               5'd28, 64'h3ff0000000000000,
                               8'(215 + 8*precision));
            check_arith_opcode(precision == 0 ? 6'd63 : 6'd59,
                               5'd31, 64'hc014000000000000,
                               8'(216 + 8*precision));
            check_arith_opcode(precision == 0 ? 6'd63 : 6'd59,
                               5'd30, 64'hbff0000000000000,
                               8'(217 + 8*precision));
        end

        load_fpr(6, 64'hbff0000000000000, 226);
        for (int move_index = 0; move_index < 4; move_index++) begin
            logic [9:0] move_xo;
            logic [4:0] move_source;
            logic [63:0] move_expected;
            completion_tag_t move_tag;
            case (move_index)
                0: begin move_xo=10'd72; move_source=5'd1;
                         move_expected=64'h3ff0000000000000; end
                1: begin move_xo=10'd40; move_source=5'd1;
                         move_expected=64'hbff0000000000000; end
                2: begin move_xo=10'd136; move_source=5'd1;
                         move_expected=64'hbff0000000000000; end
                default: begin move_xo=10'd264; move_source=5'd6;
                               move_expected=64'h3ff0000000000000; end
            endcase
            move_tag = tag(3'd3, 8'(227 + move_index));
            expected_status = inspect_fpscr_o;
            send_issue(fp_insn(63, 16, 0, move_source, move_xo) | 32'd1,
                       move_tag, 0, 0, 1'b1);
            await_result(move_tag);
            if (result_o.exception != FPU_NO_EXCEPTION ||
                result_o.fpr_value != move_expected || result_o.fpscr_write ||
                result_o.cr_field != 3'd1 ||
                result_o.cr_value != expected_status[31:28])
                $fatal(1, "move opcode/Rc index=%0d", move_index);
            commit(move_tag);
            inspect_fpr_index_i = 5'd16;
            #1;
            if (inspect_fpr_o != move_expected ||
                inspect_fpscr_o != expected_status)
                $fatal(1, "move opcode commit index=%0d", move_index);
            checks += 2;
        end

        send_issue(fp_insn(63, 17, 0, 0, 583), tag(4, 231), 0, 0, 1'b1);
        await_result(tag(4, 231));
        if (result_o.exception != FPU_NO_EXCEPTION || !result_o.fpr_write ||
            result_o.fpr_value[31:0] != inspect_fpscr_o || result_o.fpscr_write)
            $fatal(1, "mffs FPSCR word");
        commit(tag(4, 231));
        checks += 2;

        expected_status = inspect_fpscr_o;
        expected_status[3:0] = 4'h2;
        send_issue(fp_insn(63, 5'd28, 0, 0, 134) | 32'h00002001,
                   tag(0, 232), 0, 0, 1'b1);
        await_result(tag(0, 232));
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpscr_value != expected_status ||
            result_o.cr_value != expected_status[31:28])
            $fatal(1, "mtfsfi field7/Rc");
        commit(tag(0, 232));
        if (inspect_fpscr_o != expected_status)
            $fatal(1, "mtfsfi committed field7");
        checks += 2;

        load_fpr(18, 64'h0000000000000003, 233);
        expected_status = inspect_fpscr_o;
        expected_status[3:0] = 4'h3;
        send_issue(fp_insn(63, 0, 0, 18, 711) | 32'h00020000,
                   tag(1, 234), 0, 0, 1'b1);
        await_result(tag(1, 234));
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpscr_value != expected_status)
            $fatal(1, "mtfsf selective field7");
        commit(tag(1, 234));
        if (inspect_fpscr_o != expected_status)
            $fatal(1, "mtfsf selective commit");
        checks += 2;

        load_memory_form(fp_insn(31, 19, 1, 2, 599), tag(2, 235),
                         32'h00009000, 32'd8, 32'h00009008, 4'd8,
                         64'h4008000000000000, 64'h4008000000000000, 1'b0);
        load_memory_form(fp_insn(31, 20, 1, 2, 535), tag(3, 236),
                         32'h00009000, 32'd4, 32'h00009004, 4'd4,
                         64'h000000003f800000, 64'h3ff0000000000000, 1'b0);
        load_memory_form(dform(51, 21, 1, 8), tag(4, 237),
                         32'h0000a000, 32'd0, 32'h0000a008, 4'd8,
                         64'h4000000000000000, 64'h4000000000000000, 1'b1);
        load_memory_form(fp_insn(31, 22, 1, 2, 567), tag(0, 238),
                         32'h0000b000, 32'd4, 32'h0000b004, 4'd4,
                         64'h0000000040000000, 64'h4000000000000000, 1'b1);

        prepare_store(fp_insn(31, 18, 1, 2, 983), tag(1, 239),
                      32'h0000c000, 32'h0000c000, 4'd4,
                      64'h0000000000000003, 1'b0);
        @(negedge clk_i);
        store_ready_i = 1'b1;
        commit(tag(1, 239));
        store_ready_i = 1'b0;
        checks++;
        prepare_store(fp_insn(31, 20, 1, 2, 695), tag(2, 240),
                      32'h0000d000, 32'h0000d000, 4'd4,
                      64'h000000003f800000, 1'b0);
        if (!result_o.gpr_update || result_o.gpr_value != 32'h0000d000)
            $fatal(1, "stfsux update result");
        @(negedge clk_i);
        store_ready_i = 1'b1;
        commit(tag(2, 240));
        store_ready_i = 1'b0;
        checks++;
        prepare_store(dform(55, 19, 1, 8), tag(3, 241),
                      32'h0000e000, 32'h0000e008, 4'd8,
                      64'h4008000000000000, 1'b0);
        if (!result_o.gpr_update || result_o.gpr_value != 32'h0000e008)
            $fatal(1, "stfdu update result");
        @(negedge clk_i);
        store_ready_i = 1'b1;
        commit(tag(3, 241));
        store_ready_i = 1'b0;
        checks++;

        load_fpr(23, 64'h3ff8000000000000, 242);
        for (int rounding = 0; rounding < 4; rounding++) begin
            completion_tag_t rn_tag;
            completion_tag_t convert_tag;
            rn_tag = tag(3'd4, 8'(243 + 2*rounding));
            convert_tag = tag(3'd0, 8'(244 + 2*rounding));
            send_issue(fp_insn(63, 5'd28, 0, 0, 134) |
                       (32'(rounding) << 12), rn_tag, 0, 0, 1'b1);
            await_result(rn_tag);
            if (result_o.exception != FPU_NO_EXCEPTION ||
                result_o.fpscr_value[1:0] != 2'(rounding))
                $fatal(1, "mtfsfi RN control=%0d", rounding);
            commit(rn_tag);
            send_issue(fp_insn(63, 24, 0, 23, 14), convert_tag, 0, 0, 1'b1);
            await_result(convert_tag);
            if (result_o.exception != FPU_NO_EXCEPTION ||
                !result_o.fpr_write || result_o.fpr_value[31:0] !=
                ((rounding == 0 || rounding == 2) ? 32'd2 : 32'd1) ||
                result_o.fpscr_value[1:0] != 2'(rounding))
                $fatal(1, "FPSCR RN did not control fctiw rounding=%0d", rounding);
            commit(convert_tag);
            checks += 4;
        end

        load_fpr(25, 64'd0, 41);
        load_fpr(26, 64'h7ff0000000000001, 42);
        load_fpr(27, 64'hbff0000000000000, 43);
        seed_frfi(44);
        check_estimate_frfi(6'd59, 10'd24, 5'd25, 1'b1, 26, 46);
        send_issue(fp_insn(63, 5'd27, 0, 0, 38), tag(3, 47), 0, 0, 1'b1);
        await_result(tag(3, 47));
        commit(tag(3, 47));
        seed_frfi(48);
        check_estimate_frfi(6'd59, 10'd24, 5'd25, 1'b0, 26, 50);
        seed_frfi(51);
        check_estimate_frfi(6'd63, 10'd26, 5'd25, 1'b0, 26, 53);
        seed_frfi(54);
        check_estimate_frfi(6'd59, 10'd24, 5'd26, 1'b1, 24, 56);
        send_issue(fp_insn(63, 5'd24, 0, 0, 38), tag(4, 57), 0, 0, 1'b1);
        await_result(tag(4, 57));
        commit(tag(4, 57));
        seed_frfi(58);
        check_estimate_frfi(6'd59, 10'd24, 5'd26, 1'b0, 24, 60);
        seed_frfi(61);
        check_estimate_frfi(6'd63, 10'd26, 5'd27, 1'b0, 9, 63);
        checks += 2;

        $display("PASS PPC FPU shell checks=%0d", checks);
        $finish;
    end
endmodule
`default_nettype wire
