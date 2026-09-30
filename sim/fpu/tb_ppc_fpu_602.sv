// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
module tb_ppc_fpu_602;
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
    ppc_fpu_forward_data_t last_forward_data;
    logic payload_due, payload1_due;
    ppc_fpu_forward_t last_forward;
    ppc_fpu_result_t held_result;
    ppc_fpu_mem_t held_mem_req;
    int serial_number;
    int checks;

`ifdef FPU_COMPACT
    ppc_fpu_compact #(.CPU_602(1'b1)) dut (.*);
`else
    ppc_fpu #(.CPU_602(1'b1)) dut (.*);
`endif
    assign issue1_valid_i = 1'b0;
    assign issue1_i = '0;
    assign commit1_valid_i = 1'b0;
    assign commit1_tag_i = '0;

    always @(posedge clk_i)
        if (rst_ni) begin
            if (issue1_ready_o || commit1_ready_o)
                $fatal(1, "602 accepted an unrequested second lane");
            if (result1_valid_o)
                $fatal(1, "602 exposed second result packet=%h", result1_o);
            if (forward1_valid_o)
                $fatal(1, "602 exposed second forward packet=%h", forward1_o);
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
        else if (forward_valid_o) last_forward <= forward_o;

    function automatic logic [31:0] dform(input logic [5:0] primary,
        input logic [4:0] target, input logic [4:0] base,
        input logic [15:0] displacement);
        return {primary, target, base, displacement};
    endfunction

    function automatic logic [31:0] xform(input logic [5:0] primary,
        input logic [4:0] target, input logic [4:0] a, input logic [4:0] b,
        input logic [9:0] xo);
        return {primary, target, a, b, xo, 1'b0};
    endfunction

    function automatic logic [31:0] aform(input logic [5:0] primary,
        input logic [4:0] target, input logic [4:0] a, input logic [4:0] b,
        input logic [4:0] c, input logic [4:0] xo);
        return {primary, target, a, b, c, xo, 1'b0};
    endfunction

    function automatic logic [31:0] spr_insn(input logic [9:0] xo,
        input logic [4:0] gpr_index, input logic [9:0] spr);
        return {6'd31, gpr_index, spr[4:0], spr[9:5], xo, 1'b0};
    endfunction

    task automatic issue_word(input logic [31:0] instruction,
        input logic [31:0] source_gpr, input logic fe0, input logic fe1,
        input logic user_mode, output completion_tag_t identity);
        bit accepted;
        int attempts;
        @(negedge clk_i);
        issue_i = '0;
        identity.index = 3'(serial_number % 4);
        identity.generation = 8'(1 + serial_number / 4);
        serial_number++;
        issue_i.tag = identity;
        issue_i.insn = instruction;
        issue_i.gpr_b = source_gpr;
        issue_i.msr_fp = 1'b1;
        issue_i.msr_fe0 = fe0;
        issue_i.msr_fe1 = fe1;
        issue_i.msr_pr = user_mode;
        issue_valid_i = 1'b1;
        accepted = 1'b0;
        attempts = 0;
        while (!accepted) begin
            @(posedge clk_i);
            accepted = issue_valid_i && issue_ready_o;
            #2;
            attempts++;
            if (attempts > 100) $fatal(1, "602 issue timeout insn=%h", instruction);
        end
        issue_valid_i = 1'b0;
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
        int attempts;
        ppc_fpu_forward_t expected_forward;
        attempts = 0;
        while (!result_valid_o) begin
            @(negedge clk_i);
            attempts++;
            if (attempts > 120) $fatal(1, "602 result timeout");
        end
        if (result_o.tag !== identity)
            $fatal(1, "602 result tag mismatch got=%h expected=%h",
                   result_o.tag, identity);
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
                $fatal(1, "602 forward packet differs from result");
        end
        held_result = result_o;
        @(posedge clk_i);
        #2;
        if (!result_valid_o || result_o !== held_result)
            $fatal(1, "602 held result changed before commit");
    endtask

    task automatic commit(input completion_tag_t identity);
        bit accepted;
        int attempts;
        @(negedge clk_i);
        commit_tag_i = identity;
        commit_valid_i = 1'b1;
        #1;
        // Store data travels only in the authorized descriptor.
        if (result_o.store && (!store_valid_o ||
            {store_o.tag, store_o.ea, store_o.size_bytes, store_o.write} !==
            {held_mem_req.tag, held_mem_req.ea, held_mem_req.size_bytes,
             held_mem_req.write}))
            $fatal(1, "602 store not authorized by matching commit");
        accepted = 1'b0;
        attempts = 0;
        while (!accepted) begin
            @(posedge clk_i);
            accepted = commit_valid_i && commit_ready_o;
            #2;
            attempts++;
            if (attempts > 120) $fatal(1, "602 commit timeout");
        end
        commit_valid_i = 1'b0;
    endtask

    // Set to answer the next preparation with a fault.
    logic mem_fault_next;
`ifndef FPU_COMPACT
    int filled_stores;
    always @(posedge clk_i)
        if (dut.launch0.store_fill && dut.mem_launch && dut.exec_fire)
            filled_stores <= filled_stores + 1;
`endif

    task automatic reply_memory(input completion_tag_t identity,
        input logic [63:0] data);
        int attempts;
        attempts = 0;
        while (!mem_req_valid_o) begin
            @(negedge clk_i);
            attempts++;
            if (attempts > 120) $fatal(1, "602 memory request timeout");
        end
        if (mem_req_o.tag !== identity)
            $fatal(1, "602 memory request tag mismatch");
        held_mem_req = mem_req_o;
        @(negedge clk_i);
        if (!mem_req_valid_o || mem_req_o !== held_mem_req)
            $fatal(1, "602 memory preparation changed under backpressure");
        mem_req_ready_i = 1'b1;
        @(posedge clk_i);
        #2;
        mem_req_ready_i = 1'b0;
        @(negedge clk_i);
        mem_rsp_i = '0;
        mem_rsp_i.tag = identity;
        mem_rsp_i.data = data;
        mem_rsp_i.fault = mem_fault_next;
        mem_rsp_i.fault_code = mem_fault_next ? 4'd1 : 4'd0;
        mem_rsp_valid_i = 1'b1;
        #1;
        if (!mem_rsp_ready_o)
            $fatal(1, "602 tagged memory response not accepted");
        @(posedge clk_i);
        #2;
        mem_rsp_valid_i = 1'b0;
    endtask

    task automatic load_single(input logic [4:0] destination,
        input logic [31:0] bits);
        completion_tag_t identity;
        issue_word(dform(6'd48, destination, 5'd1, 16'd0), 32'd0,
                   1'b0, 1'b0, 1'b0, identity);
        reply_memory(identity, {32'd0, bits});
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION || !result_o.fpr_write ||
            result_o.fpr_value != {32'd0, bits} || !result_o.fpr_sp || result_o.fpr_lt)
            $fatal(1, "602 lfs result/tag mismatch fr%0d", destination);
        commit(identity);
        inspect_fpr_index_i = destination;
        #1;
        if (inspect_fpr_o != {32'd0, bits} || !inspect_sp_o[31-destination] ||
            inspect_lt_o[31-destination])
            $fatal(1, "602 lfs committed FPR/tag mismatch fr%0d", destination);
        checks += 2;
    endtask

    task automatic load_double(input logic [4:0] destination,
        input logic [63:0] bits, input logic trap_expected);
        completion_tag_t identity;
        issue_word(dform(6'd50, destination, 5'd1, 16'd4), 32'd0,
                   1'b0, 1'b0, 1'b0, identity);
        reply_memory(identity, bits);
        await_result(identity);
        if (trap_expected) begin
            if (result_o.exception != FPU_EMULATION_TRAP || result_o.fpr_write)
                $fatal(1, "602 lfd should emulation-trap value=%h", bits);
        end else if (result_o.exception != FPU_NO_EXCEPTION ||
                     result_o.fpr_value != 64'h000000003f800000 ||
                     !result_o.fpr_sp || result_o.fpr_lt) begin
            $fatal(1, "602 exact-fit lfd compression failed");
        end
        commit(identity);
        if (!trap_expected) begin
            inspect_fpr_index_i = destination;
            #1;
            if (inspect_fpr_o != 64'h000000003f800000 ||
                !inspect_sp_o[31-destination] || inspect_lt_o[31-destination])
                $fatal(1, "602 exact-fit lfd commit failed");
        end
        checks += 2;
    endtask

    task automatic write_tag_spr(input logic [9:0] spr,
        input logic [31:0] value);
        completion_tag_t identity;
        issue_word(spr_insn(10'd467, 5'd5, spr), value,
                   1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION)
            $fatal(1, "602 mtspr SP/LT failed spr=%0d", spr);
        commit(identity);
        checks++;
    endtask

    task automatic check_spr_latency(input logic [9:0] xo,
        input logic [9:0] spr, input logic [31:0] source_gpr,
        input logic [1:0] cycles);
        completion_tag_t identity;
        issue_word(spr_insn(xo, 5'd10, spr), source_gpr,
                   1'b0, 1'b0, 1'b0, identity);
`ifdef FPU_COMPACT
        // COMPACT does not keep the SPR transfer cycle counts.
        if (cycles == 2'd0) $fatal(1, "602 SPR latency code");
`else
        if ((cycles == 2'd1) != result_valid_o)
            $fatal(1, "602 SPR %0d wrong first-cycle result", spr);
        if (cycles == 2'd2) begin
            @(posedge clk_i);
            #2;
            if (!result_valid_o)
                $fatal(1, "602 SPR %0d missing second-cycle result", spr);
        end
`endif
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION)
            $fatal(1, "602 SPR %0d latency result trapped", spr);
        commit(identity);
        checks++;
    endtask

    task automatic expect_emulation(input logic [31:0] instruction,
        input logic fe0, input logic fe1);
        completion_tag_t identity;
        logic [31:0] prior_fpscr;
        prior_fpscr = inspect_fpscr_o;
        issue_word(instruction, 32'd0, fe0, fe1, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_EMULATION_TRAP || result_o.fpr_write ||
            result_o.fpscr_write || result_o.store || result_o.gpr_update ||
            store_valid_o || mem_req_valid_o)
            $fatal(1, "602 emulation disposition incorrect insn=%h exc=%0d",
                   instruction, result_o.exception);
        commit(identity);
        if (inspect_fpscr_o !== prior_fpscr)
            $fatal(1, "602 emulation trap changed FPSCR");
        checks += 2;
    endtask

    task automatic change_fpscr_bit(input logic [4:0] bit_number,
        input logic value);
        completion_tag_t identity;
        issue_word(xform(6'd63, bit_number, 5'd0, 5'd0,
                         value ? 10'd38 : 10'd70), 32'd0,
                   1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            !result_o.fpscr_write ||
            result_o.fpscr_value[31-bit_number] != value)
            $fatal(1, "602 FPSCR bit %0d update failed", bit_number);
        commit(identity);
        checks++;
    endtask

    task automatic expect_numeric_trap(input logic [31:0] instruction,
        input logic [4:0] destination, input logic fe0, input logic fe1);
        completion_tag_t identity;
        logic [63:0] prior_fpr;
        logic [31:0] prior_fpscr, prior_sp, prior_lt;
        inspect_fpr_index_i = destination;
        #1;
        prior_fpr = inspect_fpr_o;
        prior_fpscr = inspect_fpscr_o;
        prior_sp = inspect_sp_o;
        prior_lt = inspect_lt_o;
        issue_word(instruction, 32'd0, fe0, fe1, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_EMULATION_TRAP ||
            result_o.fpr_write || result_o.fpscr_write ||
            result_o.cr_write || result_o.gpr_update || result_o.store ||
            mem_req_valid_o || store_valid_o ||
            (forward_valid_o && forward_o.tag == identity) ||
            (forward1_valid_o && forward1_o.tag == identity) ||
            last_forward.tag == identity)
            $fatal(1, "602 numeric trap insn=%h FE=%b%b exc=%0d FPR=%b FPSCR=%b CR=%b GPR=%b store=%b mem=%b fwd=%b/%h fwd1=%b/%h last=%h",
                   instruction, fe0, fe1, result_o.exception,
                   result_o.fpr_write, result_o.fpscr_write,
                   result_o.cr_write, result_o.gpr_update, result_o.store,
                   mem_req_valid_o, forward_valid_o, forward_o.tag,
                   forward1_valid_o, forward1_o.tag, last_forward.tag);
        commit(identity);
        #1;
        if (inspect_fpr_o !== prior_fpr || inspect_fpscr_o !== prior_fpscr ||
            inspect_sp_o !== prior_sp || inspect_lt_o !== prior_lt)
            $fatal(1, "602 enabled numeric trap changed architectural state");
        checks += 2;
    endtask

    initial begin : run
        completion_tag_t identity;
        logic [31:0] sp_bits;
        logic [31:0] prior_fpscr;
        serial_number = 0;
        checks = 0;
        rst_ni = 1'b0;
        issue_valid_i = 1'b0;
        issue_i = '0;
        commit_valid_i = 1'b0;
        commit_tag_i = '0;
        abort_valid_i = 1'b0;
        abort_tag_i = '0;
        kill_all_i = 1'b0;
        mem_req_ready_i = 1'b0;
        mem_fault_next = 1'b0;
`ifndef FPU_COMPACT
        filled_stores = 0;
`endif
        mem_rsp_valid_i = 1'b0;
        mem_rsp_i = '0;
        store_ready_i = 1'b1;
        inspect_fpr_index_i = 5'd0;
        repeat (3) @(negedge clk_i);
        rst_ni = 1'b1;

        // Software initializes the 602 tags; hardware reset values are not
        // architecturally specified by the manual.
        write_tag_spr(10'd1021, 32'd0);
        write_tag_spr(10'd1022, 32'd0);
        // LT/SP use the non-BAT SPR timing: mfspr=1, mtspr=2.
        // 602 UM Table 6-2, physical PDF 312.
        check_spr_latency(10'd339, 10'd1021, 32'd0, 2'd1);
        check_spr_latency(10'd467, 10'd1022, 32'd0, 2'd2);
        load_single(5'd1, 32'h3f800000);
        load_single(5'd2, 32'h40000000);
        load_single(5'd0, 32'd0);
        load_single(5'd12, 32'h3f000000);
        load_single(5'd14, 32'h007fffff);
        load_single(5'd16, 32'h7f800001);
        load_single(5'd19, 32'h7f7fffff);
        load_single(5'd20, 32'h3f400000);
        load_single(5'd21, 32'h33000000);
        load_single(5'd22, 32'h3f800001);
        load_single(5'd23, 32'h807fffff);

        // 602 enabled numeric conditions trap to 0x1600 under every FE0/FE1
        // setting; the destination, tags, FPSCR, CR and base update are quiet.
        // §4.5.7.1, physical PDF 211–212; Table 2-23, PDF 117.
        change_fpscr_bit(5'd24, 1'b1);  // VE: signaling NaN in frsp.
        for (int mode = 0; mode < 4; mode++)
            expect_numeric_trap(xform(6'd63, 5'd20, 5'd0, 5'd16, 10'd12),
                5'd20, 1'(mode >> 1), 1'(mode));
        change_fpscr_bit(5'd24, 1'b0);
        change_fpscr_bit(5'd25, 1'b1);  // OE: largest finite times two.
        for (int mode = 0; mode < 4; mode++)
            expect_numeric_trap(aform(6'd59, 5'd20, 5'd19, 5'd0, 5'd2, 5'd25),
                5'd20, 1'(mode >> 1), 1'(mode));
        change_fpscr_bit(5'd25, 1'b0);
        change_fpscr_bit(5'd29, 1'b1);  // NI avoids NI=0 tiny trap.
        change_fpscr_bit(5'd26, 1'b1);  // UE: inexact tiny product.
        for (int mode = 0; mode < 4; mode++)
            expect_numeric_trap(aform(6'd59, 5'd20, 5'd14, 5'd0, 5'd12, 5'd25),
                5'd20, 1'(mode >> 1), 1'(mode));
        change_fpscr_bit(5'd26, 1'b0);
        change_fpscr_bit(5'd29, 1'b0);
        change_fpscr_bit(5'd27, 1'b1);  // ZE: finite divided by zero.
        for (int mode = 0; mode < 4; mode++)
            expect_numeric_trap(aform(6'd59, 5'd20, 5'd1, 5'd0, 5'd0, 5'd18),
                5'd20, 1'(mode >> 1), 1'(mode));
        change_fpscr_bit(5'd27, 1'b0);
        change_fpscr_bit(5'd28, 1'b1);  // XE: 1 + 2^-25 rounds inexact.
        for (int mode = 0; mode < 4; mode++)
            expect_numeric_trap(aform(6'd59, 5'd20, 5'd1, 5'd21, 5'd0, 5'd21),
                5'd20, 1'(mode >> 1), 1'(mode));
        change_fpscr_bit(5'd28, 1'b0);

        // (largest subnormal) × (1+2^-23) is tiny before rounding but
        // rounds up to minimum normal. NI=0 traps, NI=1 delivers signed zero.
        expect_numeric_trap(aform(6'd59, 5'd20, 5'd14, 5'd0, 5'd22, 5'd25),
                            5'd20, 1'b0, 1'b0);
        change_fpscr_bit(5'd29, 1'b1);
        issue_word(aform(6'd59, 5'd20, 5'd14, 5'd0, 5'd22, 5'd25),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value[31:0] != 32'h00000000)
            $fatal(1, "602 NI failed tiny round-up positive zero");
        commit(identity);
        issue_word(aform(6'd59, 5'd20, 5'd23, 5'd0, 5'd22, 5'd25),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value[31:0] != 32'h80000000)
            $fatal(1, "602 NI failed tiny round-up negative zero");
        commit(identity);
        change_fpscr_bit(5'd29, 1'b0);
        checks += 3;

        issue_word(aform(6'd59, 5'd3, 5'd1, 5'd2, 5'd0, 5'd21),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value != 64'h0000000040400000 ||
            !result_o.fpr_sp || result_o.fpr_lt)
            $fatal(1, "602 fadds raw result/tag");
        commit(identity);
        inspect_fpr_index_i = 5'd3;
        #1;
        if (inspect_fpr_o != 64'h0000000040400000 ||
            !inspect_sp_o[31-3] || inspect_lt_o[31-3])
            $fatal(1, "602 fadds commit/tag");
        checks += 2;

        issue_word(xform(6'd59, 5'd4, 5'd0, 5'd2, 10'd24),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value[31:0] != 32'h3f000000 ||
            !result_o.fpr_sp || result_o.fpr_lt)
            $fatal(1, "602 fres must be exact binary32 reciprocal");
        commit(identity);
        checks++;
        issue_word(xform(6'd63, 5'd5, 5'd0, 5'd1, 10'd26),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION || !result_o.fpr_sp ||
            result_o.fpr_value[31:0] < 32'h3f780000 ||
            result_o.fpr_value[31:0] > 32'h3f840000)
            $fatal(1, "602 frsqrte(1) outside 1/32 relative bound");
        commit(identity);
        checks++;

        expect_emulation(aform(6'd63, 5'd3, 5'd1, 5'd2, 5'd0, 5'd21), 0, 0);
        expect_emulation(xform(6'd63, 5'd5, 5'd0, 5'd1, 10'd14), 0, 0);

        // A missing source SP tag traps; an unselected fsel source does not.
        sp_bits = inspect_sp_o & ~(32'h80000000 >> 1);
        write_tag_spr(10'd1021, sp_bits);
        expect_emulation(aform(6'd59, 5'd3, 5'd1, 5'd2, 5'd0, 5'd21), 0, 0);
        write_tag_spr(10'd1021, sp_bits | (32'h80000000 >> 1));
        sp_bits = inspect_sp_o & ~(32'h80000000 >> 4);
        write_tag_spr(10'd1021, sp_bits);
        if (inspect_sp_o[31-4])
            $fatal(1, "602 fsel unselected B tag was not cleared");
        issue_word(aform(6'd63, 5'd6, 5'd1, 5'd4, 5'd2, 5'd23),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value != 64'h0000000040000000 || !result_o.fpr_sp)
            $fatal(1, "602 fsel incorrectly required unselected source SP");
        commit(identity);
        checks++;
        sp_bits = inspect_sp_o & ~(32'h80000000 >> 2);
        write_tag_spr(10'd1021, sp_bits);
        expect_emulation(aform(6'd63, 5'd6, 5'd1, 5'd4, 5'd2, 5'd23), 0, 0);
        write_tag_spr(10'd1021, sp_bits | (32'h80000000 >> 2));
        load_single(5'd6, 32'hbf800000);
        expect_emulation(aform(6'd63, 5'd7, 5'd6, 5'd4, 5'd2, 5'd23), 0, 0);
        sp_bits = inspect_sp_o & ~(32'h80000000 >> 6);
        write_tag_spr(10'd1021, sp_bits);
        expect_emulation(aform(6'd63, 5'd7, 5'd6, 5'd4, 5'd2, 5'd23), 0, 0);

        issue_word(xform(6'd63, 5'd7, 5'd0, 5'd1, 10'd15),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value[31:0] != 32'd1 ||
            result_o.fpr_sp || !result_o.fpr_lt)
            $fatal(1, "602 fctiwz integer/tag result");
        commit(identity);
        if (inspect_sp_o[31-7] || !inspect_lt_o[31-7])
            $fatal(1, "602 fctiwz committed tag");
        checks += 2;

        issue_word(xform(6'd63, 5'd8, 5'd0, 5'd0, 10'd583),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_sp || !result_o.fpr_lt)
            $fatal(1, "602 mffs LT result");
        commit(identity);
        if (inspect_sp_o[31-8] || !inspect_lt_o[31-8])
            $fatal(1, "602 mffs committed tag");
        checks += 2;

        issue_word(spr_insn(10'd339, 5'd10, 10'd1021), 32'd0,
                   1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            !result_o.gpr_update || result_o.gpr_index != 5'd10 ||
            result_o.gpr_value != inspect_sp_o)
            $fatal(1, "602 mfspr SP readback");
        commit(identity);
        checks++;
        issue_word(spr_insn(10'd467, 5'd10, 10'd1022), 32'hffffffff,
                   1'b0, 1'b0, 1'b1, identity);
        await_result(identity);
        if (result_o.exception != FPU_PRIVILEGED ||
            result_o.gpr_update || result_o.fpr_write || result_o.fpscr_write)
            $fatal(1, "602 user-mode tag SPR access did not trap");
        commit(identity);
        checks++;

        // SP and LT are independent architectural bits. A source with both
        // set satisfies an SP consumer; its new destination clears LT.
        // 602 UM §2.1.2.4.1, physical PDF 97.
        write_tag_spr(10'd1022, inspect_lt_o | (32'h80000000 >> 1));
        if (!inspect_sp_o[31-1] || !inspect_lt_o[31-1])
            $fatal(1, "602 could not represent simultaneous SP/LT tags");
        issue_word(xform(6'd63, 5'd24, 5'd0, 5'd1, 10'd72),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value[31:0] != 32'h3f800000 ||
            !result_o.fpr_sp || result_o.fpr_lt)
            $fatal(1, "602 fmr rejected SP+LT source or retained LT");
        commit(identity);
        inspect_fpr_index_i = 5'd24;
        #1;
        if (inspect_fpr_o[31:0] != 32'h3f800000 ||
            !inspect_sp_o[31-24] || inspect_lt_o[31-24])
            $fatal(1, "602 fmr SP+LT destination tags incorrect");
        issue_word(aform(6'd59, 5'd25, 5'd1, 5'd2, 5'd0, 5'd21),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value[31:0] != 32'h40400000 ||
            !result_o.fpr_sp || result_o.fpr_lt)
            $fatal(1, "602 arithmetic rejected SP+LT source");
        commit(identity);
        if (!inspect_sp_o[31-25] || inspect_lt_o[31-25])
            $fatal(1, "602 arithmetic SP+LT destination tags incorrect");
        write_tag_spr(10'd1022, inspect_lt_o & ~(32'h80000000 >> 1));
        checks += 5;

        expect_emulation(xform(6'd63, 5'd0, 5'd0, 5'd1, 10'd711), 0, 0);

        // Binary64 loads compress only exact finite, non-denormal binary32
        // values. EA=4 is word aligned and need not be doubleword aligned.
        load_double(5'd9, 64'h3ff0000000000000, 1'b0);
        load_double(5'd10, 64'h3ff0000000000001, 1'b1);
        load_double(5'd10, 64'h7ff8000000000001, 1'b1);
        load_double(5'd10, 64'h36a0000000000000, 1'b1);

        issue_word(dform(6'd54, 5'd9, 5'd1, 16'd4), 32'd0,
                   1'b0, 1'b0, 1'b0, identity);
        reply_memory(identity, 64'd0);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION || !result_o.store ||
            store_o.data != 64'h3ff0000000000000 || store_o.size_bytes != 4'd8)
            $fatal(1, "602 stfd exact SP expansion failed");
        commit(identity);
        checks++;
        issue_word(dform(6'd52, 5'd1, 5'd1, 16'd0), 32'd0,
                   1'b0, 1'b0, 1'b0, identity);
        reply_memory(identity, 64'd0);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION || !result_o.store ||
            store_o.data[31:0] != 32'h3f800000 || store_o.size_bytes != 4'd4)
            $fatal(1, "602 stfs raw SP store failed");
        commit(identity);
        checks++;

        // An stfdu of an infinite sum traps. Accepted in the sum's finish
        // cycle, it prepares from the forwarded value and checks the filled
        // word, and the trap outranks a preparation fault; a backpressured
        // offer stays offered and traps from the register value.
        load_single(5'd16, 32'h7f800000);
`ifdef FPU_COMPACT
        // COMPACT holds one instruction, so the store reads the written
        // sum and traps without preparing.
        begin
            completion_tag_t producer;
            issue_word(aform(6'd59, 5'd17, 5'd16, 5'd9, 5'd0, 5'd21), 32'd0,
                       1'b0, 1'b0, 1'b0, producer);
            await_result(producer);
            if (result_o.exception != FPU_NO_EXCEPTION ||
                result_o.fpr_value[31:0] != 32'h7f800000)
                $fatal(1, "602 infinite fadds failed");
            commit(producer);
            issue_word(dform(6'd55, 5'd17, 5'd1, 16'd8), 32'd0,
                       1'b0, 1'b0, 1'b0, identity);
            await_result(identity);
            if (result_o.exception != FPU_EMULATION_TRAP || result_o.store ||
                result_o.gpr_update || store_valid_o)
                $fatal(1, "602 stfdu of infinity exc=%0d", result_o.exception);
            commit(identity);
            checks += 3;
        end
`else
        for (int variant = 0; variant < 3; variant++) begin
            completion_tag_t producer;
            int prior_filled;
            int attempts;
            prior_filled = filled_stores;
            mem_fault_next = variant == 2;
            mem_req_ready_i = variant != 0;
            issue_word(aform(6'd59, 5'd17, 5'd16, 5'd9, 5'd0, 5'd21), 32'd0,
                       1'b0, 1'b0, 1'b0, producer);
            issue_word(dform(6'd55, 5'd17, 5'd1, 16'd8), 32'd0,
                       1'b0, 1'b0, 1'b0, identity);
            if (variant == 0) reply_memory(identity, 64'd0);
            else begin
                attempts = 0;
                while (!(mem_req_valid_o && mem_req_o.tag == identity)) begin
                    @(negedge clk_i);
                    attempts++;
                    if (attempts > 120) $fatal(1, "602 stfdu preparation timeout");
                end
                held_mem_req = mem_req_o;
                @(posedge clk_i);
                #2;
                mem_req_ready_i = 1'b0;
                @(negedge clk_i);
                mem_rsp_i = '0;
                mem_rsp_i.tag = identity;
                mem_rsp_i.fault = mem_fault_next;
                mem_rsp_i.fault_code = mem_fault_next ? 4'd1 : 4'd0;
                mem_rsp_valid_i = 1'b1;
                @(posedge clk_i);
                #2;
                mem_rsp_valid_i = 1'b0;
            end
            mem_fault_next = 1'b0;
            await_result(producer);
            if (result_o.exception != FPU_NO_EXCEPTION ||
                result_o.fpr_value[31:0] != 32'h7f800000)
                $fatal(1, "602 infinite fadds failed");
            commit(producer);
            await_result(identity);
            if (result_o.exception != FPU_EMULATION_TRAP || result_o.store ||
                result_o.gpr_update || store_valid_o)
                $fatal(1, "602 stfdu of infinity variant=%0d exc=%0d",
                       variant, result_o.exception);
            commit(identity);
            if (filled_stores != prior_filled + (variant != 0 ? 1 : 0))
                $fatal(1, "602 stfdu variant=%0d fill count", variant);
            checks += 3;
        end
`endif

        // Unlike 603e, a misaligned 602 FP load still reaches the LSU.
        issue_word(dform(6'd48, 5'd10, 5'd1, 16'd1), 32'd0,
                   1'b0, 1'b0, 1'b0, identity);
        reply_memory(identity, 64'h000000003f800000);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.ea != 32'd1 || result_o.fpr_value[31:0] != 32'h3f800000)
            $fatal(1, "602 misaligned lfs incorrectly rejected");
        commit(identity);
        checks++;
        issue_word(dform(6'd52, 5'd1, 5'd1, 16'd1), 32'd0,
                   1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_ALIGNMENT || mem_req_valid_o)
            $fatal(1, "602 misaligned stfs was not rejected");
        commit(identity);
        checks++;

        // The 602 permits stfiwx only from an LT-tagged integer FPR.
        issue_word(xform(6'd31, 5'd7, 5'd0, 5'd0, 10'd983),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        reply_memory(identity, 64'd0);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION || !result_o.store ||
            store_o.data[31:0] != 32'd1 || store_o.size_bytes != 4'd4)
            $fatal(1, "602 stfiwx LT store failed");
        commit(identity);
        checks++;
        expect_emulation(xform(6'd31, 5'd1, 5'd0, 5'd0, 10'd983), 0, 0);

        load_single(5'd11, 32'h00800000);
        load_single(5'd12, 32'h3f000000);
        load_single(5'd13, 32'h00000001);
        load_single(5'd14, 32'h007fffff);
        expect_emulation(dform(6'd54, 5'd13, 5'd1, 16'd4), 0, 0);
        expect_emulation(aform(6'd59, 5'd15, 5'd11, 5'd0, 5'd12, 5'd25), 0, 0);
        expect_emulation(aform(6'd59, 5'd15, 5'd13, 5'd0, 5'd1, 5'd25), 0, 0);
        expect_emulation(aform(6'd59, 5'd15, 5'd13, 5'd14, 5'd12, 5'd29), 0, 0);
        issue_word(aform(6'd59, 5'd15, 5'd13, 5'd13, 5'd0, 5'd20),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value[31:0] != 32'd0)
            $fatal(1, "602 exact cancellation incorrectly trapped");
        commit(identity);
        checks += 4;

        // NI flushes arithmetic denormal results, while a raw move retains
        // the operand bits. Neither behavior depends on a runtime CPU mode.
        issue_word(xform(6'd63, 5'd29, 5'd0, 5'd0, 10'd38),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        commit(identity);
        issue_word(aform(6'd59, 5'd15, 5'd11, 5'd0, 5'd12, 5'd25),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value[31:0] != 32'd0 || !result_o.fpr_sp)
            $fatal(1, "602 NI arithmetic denormal flush failed");
        commit(identity);
        issue_word(xform(6'd63, 5'd15, 5'd0, 5'd13, 10'd72),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value[31:0] != 32'h00000001)
            $fatal(1, "602 NI move incorrectly flushed subnormal");
        commit(identity);
        checks += 3;

        load_single(5'd0, 32'd0);
        issue_word(xform(6'd63, 5'd27, 5'd0, 5'd0, 10'd38),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        commit(identity);
        expect_emulation(aform(6'd59, 5'd15, 5'd1, 5'd0, 5'd0, 5'd18), 0, 0);
        expect_emulation(aform(6'd59, 5'd15, 5'd1, 5'd0, 5'd0, 5'd18), 1, 1);

        // Round-to-single quiets an SNaN and records VXSNAN. A bit move
        // preserves its signaling payload and does not touch FPSCR.
        load_single(5'd16, 32'h7f800001);
        issue_word(xform(6'd63, 5'd17, 5'd0, 5'd16, 10'd12),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value[31:0] != 32'h7fc00001 ||
            !result_o.fpscr_value[24-0])
            $fatal(1, "602 frsp SNaN quiet/cause failed");
        commit(identity);
        checks++;
        issue_word(xform(6'd63, 5'd18, 5'd0, 5'd16, 10'd72),
                   32'd0, 1'b0, 1'b0, 1'b0, identity);
        prior_fpscr = inspect_fpscr_o;
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value[31:0] != 32'h7f800001 ||
            result_o.fpscr_write)
            $fatal(1, "602 fmr changed signaling payload/status");
        commit(identity);
        if (inspect_fpscr_o !== prior_fpscr)
            $fatal(1, "602 fmr changed FPSCR after commit");
        checks++;

        $display("602 FPU architectural checks PASS: %0d", checks);
        $finish;
    end
endmodule
`default_nettype wire
