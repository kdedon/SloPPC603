// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Arithmetic instructions under FPSCR enables and MSR FE0/FE1: exception
// kind, result suppression or delivery, committed FPR/FPSCR and CR1. A
// directed phase then checks operand binding when an older producer of the
// same register finishes while a younger one is outstanding, and (602) that
// consumers of a finishing value which traps are discarded by the abort.
`default_nettype none
module tb_ppc_fpu_enabled #(
    parameter bit CPU_602 = 1'b0
);
    import ppc_pkg::*;
    import ppc_fpu_pkg::*;

    localparam logic [63:0] SENTINEL = CPU_602 ? 64'h40490fdb :
        64'h400921fb54442d18;

    logic clk_i = 1'b0;
    // This bench checks the head result and committed state only; the
    // second lane, store and forwarding outputs are exercised elsewhere.
    /* verilator lint_off UNUSEDSIGNAL */
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
    logic [31:0] inspect_fpscr_o;
    logic [31:0] inspect_sp_o, inspect_lt_o;
    logic forward_valid_o;
    ppc_fpu_forward_t forward_o;
    logic forward1_valid_o;
    ppc_fpu_forward_t forward1_o;
    ppc_fpu_forward_data_t forward_data_o, forward1_data_o;
    /* verilator lint_on UNUSEDSIGNAL */

`ifdef FPU_COMPACT
    ppc_fpu_compact #(.CPU_602(CPU_602)) dut (.*);
`else
    ppc_fpu #(.CPU_602(CPU_602)) dut (.*);
`endif
    assign issue1_valid_i = 1'b0;
    assign issue1_i = '0;
    assign commit1_valid_i = 1'b0;
    assign commit1_tag_i = '0;
    assign kill_all_i = 1'b0;
    assign store_ready_i = 1'b1;

    localparam logic [63:0] ONE_HALF = CPU_602 ? 64'h3fc00000 : 64'h3ff8000000000000;
    localparam logic [63:0] TWO = CPU_602 ? 64'h40000000 : 64'h4000000000000000;
    localparam logic [63:0] QUARTER = CPU_602 ? 64'h3e800000 : 64'h3fd0000000000000;
    localparam logic [63:0] FIVE = CPU_602 ? 64'h40a00000 : 64'h4014000000000000;

    int serial_number;
    int checks;
    int overlapped[3];

    logic [63:0] last_store;
    always @(posedge clk_i)
        if (!rst_ni) last_store <= '0;
        else if (store_valid_o && store_ready_i)
            last_store <= CPU_602 ? {32'd0, store_o.data[31:0]} : store_o.data;

    // Coverage: the older producer finishes while the consumer is queued
    // behind the younger producer.
    logic watch;
    logic [1:0] watch_kind;
    completion_tag_t watch_tag;
    always @(posedge clk_i)
        if (!rst_ni) overlapped <= '{0, 0, 0};
        else if (watch && dut.arith_finish_valid &&
                 dut.arith_finish.tag == watch_tag)
            overlapped[watch_kind] <= overlapped[watch_kind] + 1;

    // Memory model: accepts one preparation at a time and answers after
    // mem_delay cycles with mem_data.
    logic [63:0] mem_data;
    int mem_delay, mem_wait, store_requests;
    logic mem_busy;
    completion_tag_t mem_tag;
    assign mem_req_ready_i = !mem_busy;
    always @(posedge clk_i)
        if (!rst_ni) begin
            mem_busy <= 1'b0;
            mem_rsp_valid_i <= 1'b0;
            mem_rsp_i <= '0;
            store_requests <= 0;
        end else begin
            if (mem_req_valid_o && mem_req_ready_i && mem_req_o.write)
                store_requests <= store_requests + 1;
            if (mem_rsp_valid_i && mem_rsp_ready_o) begin
                mem_rsp_valid_i <= 1'b0;
                mem_busy <= 1'b0;
            end else if (mem_busy && !mem_rsp_valid_i) begin
                if (mem_wait == 0) begin
                    mem_rsp_valid_i <= 1'b1;
                    mem_rsp_i <= '0;
                    mem_rsp_i.tag <= mem_tag;
                    mem_rsp_i.data <= mem_data;
                end else mem_wait <= mem_wait - 1;
            end
            if (!mem_busy && mem_req_valid_o) begin
                mem_busy <= 1'b1;
                mem_tag <= mem_req_o.tag;
                mem_wait <= mem_delay;
            end
        end

    function automatic logic [31:0] aform(input logic [4:0] xo,
        input logic [4:0] d, input logic [4:0] a, input logic [4:0] b,
        input logic [4:0] c);
        return {CPU_602 ? 6'd59 : 6'd63, d, a, b, c, xo, 1'b0};
    endfunction

    task automatic issue(input logic [31:0] instruction, input logic fe0,
                         input logic fe1, output completion_tag_t identity);
        int attempts;
        @(negedge clk_i);
        identity.index = 3'(serial_number % 4);
        identity.generation = 8'(serial_number / 4);
        serial_number++;
        issue_i = '0;
        issue_i.tag = identity;
        issue_i.insn = instruction;
        issue_i.gpr_a = 32'h00001000;
        issue_i.msr_fp = 1'b1;
        issue_i.msr_fe0 = fe0;
        issue_i.msr_fe1 = fe1;
        issue_valid_i = 1'b1;
        attempts = 0;
        #1;
        while (!issue_ready_o) begin
            @(negedge clk_i);
            #1;
            attempts++;
            if (attempts > 100) $fatal(1, "issue timeout insn=%h", instruction);
        end
        @(posedge clk_i);
        #1;
        issue_valid_i = 1'b0;
    endtask

    task automatic await_result(input completion_tag_t identity);
        int attempts;
        attempts = 0;
        while (!result_valid_o) begin
            @(negedge clk_i);
            attempts++;
            if (attempts > 200) $fatal(1, "result timeout tag=%h", identity);
        end
        if (result_o.tag !== identity) $fatal(1, "result tag mismatch");
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
    endtask

    task automatic load(input logic [4:0] target, input logic [63:0] bits);
        completion_tag_t identity;
        // 602 lfs keeps binary32 bits with the SP tag; 603e lfd copies bits.
        mem_data = bits;
        mem_delay = 0;
        issue({CPU_602 ? 6'd48 : 6'd50, target, 5'd1, 16'd0}, 1'b0, 1'b0,
              identity);
        await_result(identity);
        if (result_o.exception != FPU_NO_EXCEPTION || !result_o.fpr_write)
            $fatal(1, "setup load fr%0d exception=%0d", target, result_o.exception);
        commit(identity);
    endtask

    task automatic fpr(input logic [4:0] index, output logic [63:0] value);
        inspect_fpr_index_i = index;
        #1;
        value = inspect_fpr_o;
    endtask

    // kind 0: fmul, 1: load, 2: fmr as the younger producer of fr3.
    task automatic younger_producer(input bit divide, input int kind,
                                    input int gap1, input int gap2,
                                    input int delay, input bit store_consumer);
        completion_tag_t older, younger, consumer;
        logic [63:0] expected, committed;
        // fadd 3.5 or fdiv 0.75; fdiv holds the younger fmul behind it.
        issue(aform(divide ? 5'd18 : 5'd21, 5'd3, 5'd1, 5'd2, 5'd0),
              1'b0, 1'b0, older);
        repeat (gap1) @(negedge clk_i);
        mem_data = FIVE;
        mem_delay = delay;
        case (kind)
            0: issue(aform(5'd25, 5'd3, 5'd1, 5'd0, 5'd5), 1'b0, 1'b0, younger);
            1: issue({CPU_602 ? 6'd48 : 6'd50, 5'd3, 5'd1, 16'd0}, 1'b0, 1'b0,
                     younger);
            default: issue({6'd63, 5'd3, 5'd0, 5'd5, 10'd72, 1'b0}, 1'b0, 1'b0,
                           younger);
        endcase
        repeat (gap2) @(negedge clk_i);
        if (store_consumer)
            issue({CPU_602 ? 6'd52 : 6'd54, 5'd3, 5'd1, 16'd0}, 1'b0, 1'b0,
                  consumer);
        else
            issue(aform(5'd21, 5'd4, 5'd3, 5'd2, 5'd0), 1'b0, 1'b0, consumer);
        watch_tag = older;
        watch_kind = 2'(kind);
        watch = 1'b1;
        await_result(older);
        watch = 1'b0;
        commit(older);
        await_result(younger);
        commit(younger);
        await_result(consumer);
        if (store_consumer) begin
            // The stored value is the younger producer's: 0.375, 5 or 0.25.
            case (kind)
                0: expected = CPU_602 ? 64'h3ec00000 : 64'h3fd8000000000000;
                1: expected = FIVE;
                default: expected = QUARTER;
            endcase
            if (result_o.exception != FPU_NO_EXCEPTION || !result_o.store)
                $fatal(1, "store consumer divide=%0d kind=%0d exception=%0d",
                       divide, kind, result_o.exception);
            commit(consumer);
            if (last_store !== expected)
                $fatal(1, "store consumer divide=%0d kind=%0d gaps=%0d/%0d delay=%0d data=%h expected=%h",
                       divide, kind, gap1, gap2, delay, last_store, expected);
        end else begin
            // 0.375+2, 5+2 and 0.25+2; the older producer would give 3.5+2.
            case (kind)
                0: expected = CPU_602 ? 64'h40180000 : 64'h4003000000000000;
                1: expected = CPU_602 ? 64'h40e00000 : 64'h401c000000000000;
                default: expected = CPU_602 ? 64'h40100000 : 64'h4002000000000000;
            endcase
            if (result_o.exception != FPU_NO_EXCEPTION ||
                result_o.fpr_value !== expected)
                $fatal(1, "younger producer divide=%0d kind=%0d gaps=%0d/%0d delay=%0d value=%h expected=%h",
                       divide, kind, gap1, gap2, delay, result_o.fpr_value, expected);
            commit(consumer);
            fpr(5'd4, committed);
            if (committed !== expected) $fatal(1, "younger producer commit");
        end
        checks += 2;
    endtask

    // 602: fadds traps on enabled inexact; an arithmetic consumer that
    // starts from its finishing value and a store of it must both vanish
    // when the core aborts the trapping instruction.
    task automatic trapping_producer(input int gap, input bit store_consumer);
        completion_tag_t producer, consumer, store;
        logic [63:0] prior3, prior4, after3, after4;
        logic [31:0] prior_fpscr;
        int prior_stores;
        load(5'd3, ONE_HALF);
        load(5'd4, SENTINEL);
        set_fpscr(32'h0000000c);  // XE, NI
        fpr(5'd3, prior3);
        fpr(5'd4, prior4);
        prior_fpscr = inspect_fpscr_o;
        prior_stores = store_requests;
        issue(aform(5'd21, 5'd3, 5'd1, 5'd6, 5'd0), 1'b0, 1'b0, producer);
        repeat (gap) @(negedge clk_i);
        issue(aform(5'd21, 5'd4, 5'd3, 5'd2, 5'd0), 1'b0, 1'b0, consumer);
        store = '0;
        if (store_consumer)
            issue({6'd52, 5'd3, 5'd1, 16'd0}, 1'b0, 1'b0, store);
        await_result(producer);
        if (store_consumer && mem_req_valid_o && mem_req_o.tag == store)
            $fatal(1, "store of trapping value requested preparation gap=%0d", gap);
        if (result_o.exception != FPU_EMULATION_TRAP || result_o.fpr_write ||
            result_o.fpscr_write)
            $fatal(1, "trapping producer gap=%0d exception=%0d", gap,
                   result_o.exception);
        @(negedge clk_i);
        abort_tag_i = producer;
        abort_valid_i = 1'b1;
        @(posedge clk_i);
        #1;
        abort_valid_i = 1'b0;
        repeat (40) begin
            @(negedge clk_i);
            if (result_valid_o)
                $fatal(1, "consumer of trapping value survived abort gap=%0d store=%0d tag=%h",
                       gap, store_consumer, result_o.tag);
        end
        if (store_requests != prior_stores)
            $fatal(1, "store of trapping value prepared gap=%0d", gap);
        fpr(5'd3, after3);
        fpr(5'd4, after4);
        if (after3 !== prior3 || after4 !== prior4 ||
            inspect_fpscr_o !== prior_fpscr)
            $fatal(1, "aborted trap changed state gap=%0d", gap);
        // The machine resumes with the committed value.
        set_fpscr(32'h00000004);
        issue(aform(5'd21, 5'd4, 5'd3, 5'd2, 5'd0), 1'b0, 1'b0, consumer);
        await_result(consumer);
        if (result_o.exception != FPU_NO_EXCEPTION ||
            result_o.fpr_value !== 64'h40600000)
            $fatal(1, "resume after trap abort value=%h", result_o.fpr_value);
        commit(consumer);
        checks += 4;
    endtask

    task automatic set_fpscr(input logic [31:0] value);
        completion_tag_t identity;
        for (int field = 0; field < 8; field++) begin
            issue({6'd63, 3'(field), 7'd0, value[31-4*field -: 4], 1'b0,
                   10'd134, 1'b0}, 1'b0, 1'b0, identity);
            await_result(identity);
            commit(identity);
        end
        if (inspect_fpscr_o !== value)
            $fatal(1, "FPSCR setup got=%h expected=%h", inspect_fpscr_o, value);
    endtask

    initial begin : run
        string path;
        int file_handle, parsed, count, enabled_count, trap_count, suppressed;
        logic [31:0] insn, fpscr_old, fpscr_new, fpscr_mask;
        logic [63:0] a, b, c, value, mask;
        logic [2:0] exc_code;
        logic [3:0] cr_value;
        logic [1:0] fe;
        logic fpr_write, cr_write;
        completion_tag_t identity;
        ppc_fpu_exception_t expected_exception;

        issue_valid_i = 1'b0;
        issue_i = '0;
        commit_valid_i = 1'b0;
        commit_tag_i = '0;
        abort_valid_i = 1'b0;
        abort_tag_i = '0;
        watch = 1'b0;
        watch_kind = '0;
        watch_tag = '0;
        mem_data = '0;
        mem_delay = 0;
        inspect_fpr_index_i = 5'd4;
        serial_number = 0;
        checks = 0;
        count = 0;
        enabled_count = 0;
        trap_count = 0;
        suppressed = 0;
        rst_ni = 1'b0;
        repeat (3) @(posedge clk_i);
        rst_ni = 1'b1;
        if (!$value$plusargs("VECTORS=%s", path)) $fatal(1, "missing VECTORS");
        file_handle = $fopen(path, "r");
        if (file_handle == 0) $fatal(1, "cannot open %s", path);
        while (!$feof(file_handle)) begin
            parsed = $fscanf(file_handle, "%h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",
                insn, a, b, c, fpscr_old, fe, exc_code, fpr_write, value, mask,
                fpscr_new, fpscr_mask, cr_write, cr_value);
            if (parsed <= 0) break;
            if (parsed != 14) $fatal(1, "bad vector %0d fields=%0d", count, parsed);
            expected_exception = ppc_fpu_exception_t'(exc_code);
            load(5'd1, a);
            load(5'd2, b);
            load(5'd3, c);
            load(5'd4, SENTINEL);
            set_fpscr(fpscr_old);
            issue(insn, fe[1], fe[0], identity);
            await_result(identity);
            if (result_o.exception !== expected_exception ||
                result_o.fpr_write !== fpr_write ||
                (fpr_write && ((result_o.fpr_value ^ value) & mask) != 0) ||
                (expected_exception != FPU_EMULATION_TRAP &&
                 (!result_o.fpscr_write ||
                  ((result_o.fpscr_value ^ fpscr_new) & fpscr_mask) != 0)) ||
                (expected_exception == FPU_EMULATION_TRAP &&
                 (result_o.fpscr_write || result_o.cr_write)) ||
                result_o.cr_write !== cr_write ||
                (cr_write && (result_o.cr_field != 3'd1 ||
                              result_o.cr_value !== cr_value)) ||
                result_o.gpr_update || result_o.store)
                $fatal(1, "case %0d insn=%h a=%h b=%h c=%h fpscr=%h FE=%b: exception %0d/%0d write %b/%b value %h/%h fpscr %b %h/%h cr %b %h/%h",
                       count, insn, a, b, c, fpscr_old, fe,
                       result_o.exception, expected_exception,
                       result_o.fpr_write, fpr_write, result_o.fpr_value, value,
                       result_o.fpscr_write, result_o.fpscr_value, fpscr_new,
                       result_o.cr_write, result_o.cr_value, cr_value);
            commit(identity);
            #1;
            // A committed FP-enabled result keeps its FPR/FPSCR disposition;
            // an emulation trap leaves both unchanged.
            if (((inspect_fpr_o ^ (fpr_write ? value : SENTINEL)) &
                 (fpr_write ? mask : 64'hffffffffffffffff)) != 0 ||
                ((inspect_fpscr_o ^ (expected_exception == FPU_EMULATION_TRAP ?
                                     fpscr_old : fpscr_new)) & fpscr_mask) != 0 ||
                (CPU_602 && fpr_write &&
                 (inspect_sp_o[27] !== (insn[5:1] != 5'd15) ||
                  inspect_lt_o[27] !== (insn[5:1] == 5'd15))))
                $fatal(1, "case %0d commit fpr=%h fpscr=%h expected fpscr=%h",
                       count, inspect_fpr_o, inspect_fpscr_o, fpscr_new);
            if (expected_exception == FPU_FP_ENABLED) enabled_count++;
            if (expected_exception == FPU_EMULATION_TRAP) trap_count++;
            if (!fpr_write) suppressed++;
            checks += 2;
            count++;
        end
        $fclose(file_handle);
        if (count == 0) $fatal(1, "no vectors");
        begin : hazards
            int hazard_cases;
            hazard_cases = 0;
            set_fpscr(32'd0);
            load(5'd1, ONE_HALF);
            load(5'd2, TWO);
            load(5'd5, QUARTER);
            load(5'd6, CPU_602 ? 64'h30800000 : 64'h3e10000000000000);
`ifndef FPU_COMPACT
            // Overlapped producers and consumers need a pipelined shell.
            for (int divide = 0; divide < 2; divide++)
                for (int kind = 0; kind < 3; kind++)
                    for (int gap1 = 0; gap1 < 4; gap1++)
                        for (int gap2 = 0; gap2 < 4; gap2++)
                            for (int delay = 0; delay < (kind == 1 ? 8 : 1); delay++)
                                for (int store = 0; store < 2; store++) begin
                                    younger_producer(divide[0], kind, gap1, gap2,
                                                     delay * (divide + 1) * 3,
                                                     store[0]);
                                    hazard_cases++;
                                end
            if (overlapped[0] == 0 || overlapped[1] == 0 || overlapped[2] == 0)
                $fatal(1, "older producer never finished under a waiting consumer %0d/%0d/%0d",
                       overlapped[0], overlapped[1], overlapped[2]);
            if (CPU_602)
                for (int gap = 0; gap < 4; gap++)
                    for (int with_store = 0; with_store < 2; with_store++) begin
                        trapping_producer(gap, with_store[0]);
                        hazard_cases++;
                    end
            $display("PASS ppc_fpu operand-binding hazards cases=%0d overlapped fmul/load/fmr=%0d/%0d/%0d",
                     hazard_cases, overlapped[0], overlapped[1], overlapped[2]);
`else
            $display("SKIP ppc_fpu operand-binding hazards cases=%0d: one instruction in flight",
                     hazard_cases);
`endif
        end
        $display("PASS ppc_fpu enabled-exception %s cases=%0d fp_enabled=%0d emulation_traps=%0d suppressed=%0d checks=%0d",
                 CPU_602 ? "602" : "603e", count, enabled_count, trap_count,
                 suppressed, checks);
        $finish;
    end
endmodule
`default_nettype wire
