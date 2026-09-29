// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Public-port ordered FP + LSU reservation and paired-retirement checks.
module tb_ppc_fpu_dual #(
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
    logic result_valid_o, result1_valid_o;
    ppc_fpu_result_t result_o, result1_o;
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
    logic forward_valid_o, forward1_valid_o;
    ppc_fpu_forward_t forward_o, forward1_o;
    ppc_fpu_forward_data_t forward_data_o, forward1_data_o;
    logic compare_payload_due, load_payload_due, load_payload_bus1;
    logic saw_compare_cr, saw_load_fpr, saw_dual_forward;
    int held_issue_accepts, held_mem_requests;
    int checks;

    ppc_fpu #(.CPU_602(CPU_602)) dut (.*);

    function automatic completion_tag_t tag(input logic [7:0] generation);
        completion_tag_t t;
        t.index = 3'(generation);
        t.generation = generation;
        return t;
    endfunction

    function automatic logic [31:0] dform(input logic [5:0] primary,
        input logic [4:0] target, input logic [15:0] displacement);
        return {primary, target, 5'd1, displacement};
    endfunction

    function automatic logic [31:0] add_insn(input logic [4:0] target);
        return {CPU_602 ? 6'd59 : 6'd63, target, 5'd1, 5'd2,
                5'd0, 5'd21, 1'b0};
    endfunction

    function automatic logic [31:0] compare_insn();
        return {6'd63, 5'd20, 5'd1, 5'd2, 10'd0, 1'b0};
    endfunction

    function automatic ppc_fpu_issue_t request(input logic [7:0] generation,
        input logic [31:0] instruction);
        ppc_fpu_issue_t p;
        p = '0;
        p.tag = tag(generation);
        p.insn = instruction;
        p.msr_fp = 1'b1;
        return p;
    endfunction

    // Notification payloads arrive on the following cycle.
    always @(posedge clk_i)
        if (!rst_ni) begin
            compare_payload_due <= 1'b0;
            load_payload_due <= 1'b0;
            load_payload_bus1 <= 1'b0;
        end else begin
            if (compare_payload_due && forward_data_o.cr_value != 4'h8)
                $fatal(1, "compare forward payload %h", forward_data_o);
            if (load_payload_due &&
                (load_payload_bus1 ? forward1_data_o.fpr_value :
                 forward_data_o.fpr_value) !=
                (CPU_602 ? 64'h000000003f800000 : 64'h3ff0000000000000))
                $fatal(1, "load forward payload %h/%h", forward_data_o,
                       forward1_data_o);
            compare_payload_due <= forward_valid_o && forward_o.tag == tag(90);
            load_payload_due <= (forward_valid_o && forward_o.tag == tag(91)) ||
                (forward1_valid_o && forward1_o.tag == tag(91));
            load_payload_bus1 <= forward1_valid_o && forward1_o.tag == tag(91);
        end

    always @(posedge clk_i)
        if (!rst_ni) begin
            saw_compare_cr <= 1'b0;
            saw_load_fpr <= 1'b0;
            saw_dual_forward <= 1'b0;
            held_issue_accepts <= 0;
            held_mem_requests <= 0;
        end else begin
            if (issue_valid_i && issue_ready_o && issue_i.tag == tag(120))
                held_issue_accepts <= held_issue_accepts + 1;
            if (mem_req_valid_o && mem_req_ready_i && mem_req_o.tag == tag(120))
                held_mem_requests <= held_mem_requests + 1;
            if (forward_valid_o && forward_o.tag == tag(90)) begin
                if (!forward_o.cr_write || forward_o.cr_field != 3'd5 ||
                    forward_o.fpr_write)
                    $fatal(1, "compare forward malformed %h", forward_o);
                saw_compare_cr <= 1'b1;
            end
            if (forward_valid_o && forward_o.tag == tag(91)) begin
                if (!forward_o.fpr_write || forward_o.fpr_index != 5'd4)
                    $fatal(1, "load forward malformed %h", forward_o);
                saw_load_fpr <= 1'b1;
            end
            if (forward1_valid_o) begin
                if (!forward_valid_o || forward1_o.tag == forward_o.tag)
                    $fatal(1, "second forward has no distinct older packet %h", forward1_o);
                if (forward1_o.tag == tag(91)) begin
                    if (!forward1_o.fpr_write || forward1_o.fpr_index != 5'd4)
                        $fatal(1, "paired load forward malformed %h", forward1_o);
                    saw_load_fpr <= 1'b1;
                    if (forward_o.tag == tag(90)) saw_dual_forward <= 1'b1;
                end
            end
        end

    task automatic issue_one(input ppc_fpu_issue_t packet);
        int attempts;
        bit accepted;
        @(negedge clk_i);
        issue_i = packet;
        issue_valid_i = 1'b1;
        attempts = 0;
        accepted = 1'b0;
        while (!accepted) begin
            @(posedge clk_i);
            accepted = issue_valid_i && issue_ready_o;
            #2;
            attempts++;
            if (attempts > 100) $fatal(1, "single issue timeout %h", packet);
        end
        issue_valid_i = 1'b0;
    endtask

    task automatic issue_pair(input ppc_fpu_issue_t older,
        input ppc_fpu_issue_t younger);
        bit accept0, accept1;
        @(negedge clk_i);
        issue_i = older;
        issue1_i = younger;
        issue_valid_i = 1'b1;
        issue1_valid_i = 1'b1;
        @(posedge clk_i);
        accept0 = issue_valid_i && issue_ready_o;
        accept1 = issue1_valid_i && issue1_ready_o;
        #2;
        issue_valid_i = 1'b0;
        issue1_valid_i = 1'b0;
        if (!accept0 || !accept1)
            $fatal(1, "%s ordered pair was not accepted same edge older=%h younger=%h ready=%b%b",
                   CPU_602 ? "602" : "603e", older, younger, accept0, accept1);
        checks++;
    endtask

    task automatic reply_memory(input completion_tag_t identity,
        input logic [63:0] data, input bit write_expected);
        int attempts;
        attempts = 0;
        while (!mem_req_valid_o) begin
            @(negedge clk_i);
            attempts++;
            if (attempts > 100)
                $fatal(1, "memory prepare timeout tag=%h descriptor=%h",
                       identity, mem_req_o);
        end
        if (mem_req_o.tag != identity || mem_req_o.write != write_expected)
            $fatal(1, "memory prepare tag/write mismatch descriptor=%h", mem_req_o);
        mem_req_ready_i = 1'b1;
        @(posedge clk_i);
        #2;
        mem_req_ready_i = 1'b0;
        // Align the compare/load pair's tagged LSU reply with the compare's
        // finish edge so both independent forward packets are required.
        if (identity == tag(91)) @(negedge clk_i);
        @(negedge clk_i);
        mem_rsp_i = '0;
        mem_rsp_i.tag = identity;
        mem_rsp_i.data = data;
        mem_rsp_valid_i = 1'b1;
        #1;
        if (!mem_rsp_ready_o)
            $fatal(1, "memory reply backpressured tag=%h", identity);
        @(posedge clk_i);
        #2;
        mem_rsp_valid_i = 1'b0;
    endtask

    task automatic await_head(input completion_tag_t identity);
        int attempts;
        attempts = 0;
        while (!result_valid_o) begin
            @(negedge clk_i);
            attempts++;
            if (attempts > 100) $fatal(1, "head result timeout tag=%h", identity);
        end
        if (result_o.tag != identity || result_o.exception != FPU_NO_EXCEPTION)
            $fatal(1, "head result tag/exception mismatch %h", result_o);
    endtask

    task automatic retire_one(input completion_tag_t identity);
        bit accepted;
        @(negedge clk_i);
        commit_tag_i = identity;
        commit_valid_i = 1'b1;
        @(posedge clk_i);
        accepted = commit_ready_o;
        #2;
        commit_valid_i = 1'b0;
        if (!accepted) $fatal(1, "commit rejected tag=%h result=%h", identity, result_o);
    endtask

    task automatic initialize_fpr(input logic [4:0] index,
        input logic [7:0] generation, input logic [63:0] data);
        completion_tag_t identity;
        identity = tag(generation);
        issue_one(request(generation,
            dform(CPU_602 ? 6'd48 : 6'd50, index, 16'd0)));
        reply_memory(identity, data, 1'b0);
        await_head(identity);
        retire_one(identity);
    endtask

    initial begin : run
        int attempts;
        bit accept0, accept1;
        rst_ni = 1'b0;
        issue_valid_i = 1'b0;
        issue_i = '0;
        issue1_valid_i = 1'b0;
        issue1_i = '0;
        commit_valid_i = 1'b0;
        commit_tag_i = '0;
        commit1_valid_i = 1'b0;
        commit1_tag_i = '0;
        abort_valid_i = 1'b0;
        abort_tag_i = '0;
        kill_all_i = 1'b0;
        mem_req_ready_i = 1'b0;
        mem_rsp_valid_i = 1'b0;
        mem_rsp_i = '0;
        store_ready_i = 1'b1;
        inspect_fpr_index_i = 5'd0;
        checks = 0;
        repeat (3) @(negedge clk_i);
        rst_ni = 1'b1;
        initialize_fpr(5'd1, 8'd1,
            CPU_602 ? 64'h000000003f800000 : 64'h3ff0000000000000);
        initialize_fpr(5'd2, 8'd2,
            CPU_602 ? 64'h0000000040000000 : 64'h4000000000000000);
        if (inspect_fpscr_o != 32'd0)
            $fatal(1, "initial FPSCR changed");

        // Ordered compare then load may retire together on 603e: the CR
        // packet and FPR packet must both reach the independent forward buses.
        issue_pair(request(8'd90, compare_insn()),
                   request(8'd91, dform(CPU_602 ? 6'd48 : 6'd50, 5'd4, 16'd0)));
        reply_memory(tag(91),
            CPU_602 ? 64'h000000003f800000 : 64'h3ff0000000000000, 1'b0);
        await_head(tag(90));
        if (result_o.cr_field != 3'd5 || result_o.cr_value != 4'h8 ||
            result_o.fpr_write)
            $fatal(1, "compare head did not produce CR5 less %h", result_o);
        if (!CPU_602) begin
            if (!result1_valid_o || result1_o.tag != tag(91) ||
                !result1_o.fpr_write || result1_o.fpr_index != 5'd4)
                $fatal(1, "603e paired compare/load result missing %h", result1_o);
            @(negedge clk_i);
            commit_tag_i = tag(90);
            commit_valid_i = 1'b1;
            commit1_tag_i = tag(91);
            commit1_valid_i = 1'b1;
            @(posedge clk_i);
            accept0 = commit_ready_o;
            accept1 = commit1_ready_o;
            #2;
            commit_valid_i = 1'b0;
            commit1_valid_i = 1'b0;
            if (!accept0 || !accept1)
                $fatal(1, "603e compare/load dual retirement rejected");
            if (!saw_compare_cr || !saw_load_fpr || !saw_dual_forward)
                $fatal(1, "603e lost paired compare/load forwarding cr=%b fpr=%b dual=%b",
                       saw_compare_cr, saw_load_fpr, saw_dual_forward);
            checks += 3;
        end else begin
            if (result1_valid_o || forward1_valid_o)
                $fatal(1, "602 exposed dual retirement/forwarding");
            retire_one(tag(90));
            await_head(tag(91));
            retire_one(tag(91));
            if (!saw_compare_cr || !saw_load_fpr)
                $fatal(1, "602 lost ordered compare/load forwards");
            checks += 2;
        end
        inspect_fpr_index_i = 5'd4;
        #1;
        if (inspect_fpr_o != (CPU_602 ? 64'h000000003f800000 :
                                      64'h3ff0000000000000))
            $fatal(1, "paired load failed to commit FPR4");
        checks++;

        // A prepared store and a younger load may share the 603e retirement
        // edge: the store's only side effect is the matching commit handshake.
        issue_one(request(8'd96, dform(6'd52, 5'd1, 16'd0)));
        reply_memory(tag(96), 64'd0, 1'b1);
        issue_one(request(8'd97, dform(CPU_602 ? 6'd48 : 6'd50,
                                       5'd7, 16'd0)));
        reply_memory(tag(97),
            CPU_602 ? 64'h000000003f800000 : 64'h3ff0000000000000, 1'b0);
        await_head(tag(96));
        if (!result_o.store || store_valid_o || !store_o.write ||
            store_o.data[31:0] != 32'h3f800000)
            $fatal(1, "prepared store published early or lost descriptor result=%h store=%h",
                   result_o, store_o);
        if (!CPU_602) begin
            if (!result1_valid_o || result1_o.tag != tag(97) ||
                !result1_o.fpr_write || result1_o.fpr_index != 5'd7)
                $fatal(1, "603e store/load dual result missing %h", result1_o);
            @(negedge clk_i);
            commit_tag_i = tag(96);
            commit_valid_i = 1'b1;
            commit1_tag_i = tag(97);
            commit1_valid_i = 1'b1;
            #1;
            if (!store_valid_o || store_o.tag != tag(96))
                $fatal(1, "603e store authorization missing exact commit %h", store_o);
            @(posedge clk_i);
            accept0 = commit_ready_o;
            accept1 = commit1_ready_o;
            #2;
            commit_valid_i = 1'b0;
            commit1_valid_i = 1'b0;
            if (!accept0 || !accept1)
                $fatal(1, "603e store/load paired retirement rejected");
            checks += 3;
        end else begin
            if (result1_valid_o)
                $fatal(1, "602 incorrectly offered dual store/load retirement");
            retire_one(tag(96));
            await_head(tag(97));
            retire_one(tag(97));
            checks += 2;
        end
        inspect_fpr_index_i = 5'd7;
        #1;
        if (inspect_fpr_o != (CPU_602 ? 64'h000000003f800000 :
                                      64'h3ff0000000000000))
            $fatal(1, "store/load pair did not commit load FPR7");
        checks++;

        // Reversed age order still accepts one LSU and one arithmetic
        // operation on the same edge and retires in program order.
        issue_pair(request(8'd98, dform(CPU_602 ? 6'd48 : 6'd50,
                                        5'd8, 16'd0)),
                   request(8'd99, add_insn(5'd9)));
        reply_memory(tag(98),
            CPU_602 ? 64'h000000003f800000 : 64'h3ff0000000000000, 1'b0);
        await_head(tag(98));
        retire_one(tag(98));
        await_head(tag(99));
        if (!result_o.fpr_write || result_o.fpr_value !=
            (CPU_602 ? 64'h0000000040400000 : 64'h4008000000000000))
            $fatal(1, "load-older arithmetic result incorrect %h", result_o);
        retire_one(tag(99));
        checks += 3;

        // The LSU reservation remains available behind an occupied divider.
        issue_one(request(8'd92, {CPU_602 ? 6'd59 : 6'd63,
                                  5'd5, 5'd2, 5'd1, 5'd0, 5'd18, 1'b0}));
        issue_one(request(8'd93,
            dform(CPU_602 ? 6'd48 : 6'd50, 5'd6, 16'd0)));
        reply_memory(tag(93),
            CPU_602 ? 64'h000000003f800000 : 64'h3ff0000000000000, 1'b0);
        if (result_valid_o && result_o.tag == tag(92))
            $fatal(1, "LSU reply occurred only after divider completion");
        await_head(tag(92));
        retire_one(tag(92));
        await_head(tag(93));
        retire_one(tag(93));
        checks += 3;

        // Abort at a middle generation cancels that entry and all younger
        // work, including a queued LSU request, but preserves the older
        // arithmetic result. Reuse the physical tag index with a fresh
        // generation and verify no stale completion can satisfy it.
        issue_one(request(8'd100, add_insn(5'd12)));
        issue_one(request(8'd101, add_insn(5'd13)));
        issue_one(request(8'd102,
            dform(CPU_602 ? 6'd48 : 6'd50, 5'd14, 16'd0)));
        @(negedge clk_i);
        abort_tag_i = tag(101);
        abort_valid_i = 1'b1;
        @(posedge clk_i);
        #2;
        abort_valid_i = 1'b0;
        await_head(tag(100));
        if (!result_o.fpr_write || result_o.fpr_value !=
            (CPU_602 ? 64'h0000000040400000 : 64'h4008000000000000))
            $fatal(1, "middle abort damaged older result %h", result_o);
        retire_one(tag(100));
        repeat (3) begin
            @(negedge clk_i);
            if (result_valid_o || mem_req_valid_o)
                $fatal(1, "middle abort retained canceled younger work result=%h memory=%h",
                       result_o, mem_req_o);
        end
        issue_one(request(8'd109, add_insn(5'd15)));
        await_head(tag(109));
        retire_one(tag(109));
        checks += 4;

        // A 602 serialized conversion cannot accept a paired LSU operation.
        if (CPU_602) begin
            @(negedge clk_i);
            issue_i = request(8'd94, {6'd63, 5'd7, 5'd0, 5'd1, 10'd15, 1'b0});
            issue1_i = request(8'd95, dform(6'd48, 5'd8, 16'd0));
            issue_valid_i = 1'b1;
            issue1_valid_i = 1'b1;
            @(posedge clk_i);
            accept0 = issue_ready_o;
            accept1 = issue1_ready_o;
            #2;
            issue_valid_i = 1'b0;
            issue1_valid_i = 1'b0;
            if (!accept0 || accept1)
                $fatal(1, "602 fctiwz incorrectly paired with LSU");
            await_head(tag(94));
            retire_one(tag(94));
            checks++;
        end

        // A full reservation queue must not issue a held LSU request before
        // its issue handshake. A same-edge retirement frees its credit.
        issue_one(request(8'd110, add_insn(5'd16)));
        issue_one(request(8'd111, add_insn(5'd17)));
        issue_one(request(8'd112, add_insn(5'd18)));
        issue_one(request(8'd113, add_insn(5'd19)));
        if (!CPU_602) issue_one(request(8'd114, compare_insn()));
        @(negedge clk_i);
        issue_i = request(8'd120,
            dform(CPU_602 ? 6'd48 : 6'd50, 5'd21, 16'd0));
        issue_valid_i = 1'b1;
        repeat (3) begin
            #1;
            if (issue_ready_o ||
                (mem_req_valid_o && mem_req_o.tag == tag(120)) ||
                (forward_valid_o && forward_o.tag == tag(120)) ||
                (forward1_valid_o && forward1_o.tag == tag(120)))
                $fatal(1, "blocked issue caused an early side effect");
            @(negedge clk_i);
        end
        if (held_issue_accepts != 0 || held_mem_requests != 0)
            $fatal(1, "blocked issue was accepted/launched early");
        commit_tag_i = tag(110);
        commit_valid_i = 1'b1;
        @(posedge clk_i);
        accept0 = commit_ready_o;
        accept1 = issue_ready_o;
        #2;
        commit_valid_i = 1'b0;
        issue_valid_i = 1'b0;
        if (!accept0 || !accept1 || held_issue_accepts != 1)
            $fatal(1, "same-edge retirement did not admit held LSU commit=%b issue=%b count=%0d",
                   accept0, accept1, held_issue_accepts);
        attempts = 0;
        while (!mem_req_valid_o || mem_req_o.tag != tag(120)) begin
            @(negedge clk_i);
            attempts++;
            if (attempts > 100) $fatal(1, "accepted held LSU never launched");
        end
        mem_req_ready_i = 1'b1;
        @(posedge clk_i);
        #2;
        mem_req_ready_i = 1'b0;
        @(negedge clk_i);
        mem_rsp_i = '0;
        mem_rsp_i.tag = tag(120);
        mem_rsp_i.data = CPU_602 ? 64'h000000003f800000 :
                                   64'h3ff0000000000000;
        mem_rsp_valid_i = 1'b1;
        @(posedge clk_i);
        #2;
        mem_rsp_valid_i = 1'b0;
        retire_one(tag(111));
        retire_one(tag(112));
        retire_one(tag(113));
        if (!CPU_602) retire_one(tag(114));
        await_head(tag(120));
        retire_one(tag(120));
        if (held_issue_accepts != 1 || held_mem_requests != 1)
            $fatal(1, "held LSU accepted or launched more than once issue=%0d memory=%0d",
                   held_issue_accepts, held_mem_requests);
        checks += 3;

        // Two 603e retirements free two queue slots on the same edge that
        // admits an ordered arithmetic/LSU pair; 602 remains single-issue.
        if (!CPU_602) begin
            issue_one(request(8'd130, compare_insn()));
            issue_one(request(8'd131, dform(6'd50, 5'd22, 16'd0)));
            reply_memory(tag(131), 64'h3ff0000000000000, 1'b0);
            issue_one(request(8'd132, add_insn(5'd23)));
            issue_one(request(8'd133, add_insn(5'd24)));
            issue_one(request(8'd134, compare_insn()));
            await_head(tag(130));
            if (!result1_valid_o || result1_o.tag != tag(131))
                $fatal(1, "dual-retire credit setup missing second result");
            @(negedge clk_i);
            issue_i = request(8'd135, add_insn(5'd25));
            issue1_i = request(8'd136, dform(6'd50, 5'd26, 16'd0));
            issue_valid_i = 1'b1;
            issue1_valid_i = 1'b1;
            commit_tag_i = tag(130);
            commit_valid_i = 1'b1;
            commit1_tag_i = tag(131);
            commit1_valid_i = 1'b1;
            @(posedge clk_i);
            accept0 = issue_ready_o && commit_ready_o;
            accept1 = issue1_ready_o && commit1_ready_o;
            #2;
            issue_valid_i = 1'b0;
            issue1_valid_i = 1'b0;
            commit_valid_i = 1'b0;
            commit1_valid_i = 1'b0;
            if (!accept0 || !accept1)
                $fatal(1, "full queue did not dual-retire and dual-admit");
            reply_memory(tag(136), 64'h3ff0000000000000, 1'b0);
            retire_one(tag(132));
            retire_one(tag(133));
            retire_one(tag(134));
            retire_one(tag(135));
            retire_one(tag(136));
            checks += 3;
        end

        // A rejected second LSU lane has no prepare or forward side effect;
        // issuing it later with the same tag produces one normal request.
        @(negedge clk_i);
        issue_i = request(8'd140,
            dform(CPU_602 ? 6'd48 : 6'd50, 5'd27, 16'd0));
        issue1_i = request(8'd141,
            dform(CPU_602 ? 6'd48 : 6'd50, 5'd28, 16'd0));
        issue_valid_i = 1'b1;
        issue1_valid_i = 1'b1;
        @(posedge clk_i);
        accept0 = issue_ready_o;
        accept1 = issue1_ready_o;
        #2;
        issue_valid_i = 1'b0;
        issue1_valid_i = 1'b0;
        if (!accept0 || accept1)
            $fatal(1, "same-class LSU pair acceptance incorrect");
        reply_memory(tag(140),
            CPU_602 ? 64'h000000003f800000 : 64'h3ff0000000000000,
            1'b0);
        repeat (3) begin
            @(negedge clk_i);
            if ((mem_req_valid_o && mem_req_o.tag == tag(141)) ||
                (forward_valid_o && forward_o.tag == tag(141)) ||
                (forward1_valid_o && forward1_o.tag == tag(141)))
                $fatal(1, "rejected second lane launched or forwarded");
        end
        await_head(tag(140));
        retire_one(tag(140));
        issue_one(request(8'd141,
            dform(CPU_602 ? 6'd48 : 6'd50, 5'd28, 16'd0)));
        reply_memory(tag(141),
            CPU_602 ? 64'h000000003f800000 : 64'h3ff0000000000000,
            1'b0);
        await_head(tag(141));
        retire_one(tag(141));
        checks += 2;

        // With VE enabled but FE0/FE1 clear, invalid arithmetic suppresses
        // the destination without a program trap. Its younger load can use
        // the 603e's second retirement slot because the older packet writes
        // no FPR. The 602 exception/tag matrix checks its distinct trap path.
        if (!CPU_602) begin
            initialize_fpr(5'd29, 8'd142, 64'h7ff0000000000001);
            issue_one(request(8'd143,
                {6'd63, 5'd24, 5'd0, 5'd0, 10'd38, 1'b0}));
            await_head(tag(143));
            retire_one(tag(143));
            if (!inspect_fpscr_o[7]) $fatal(1, "VE was not committed");
            issue_pair(request(8'd144,
                {6'd63, 5'd30, 5'd29, 5'd1, 5'd0, 5'd21, 1'b0}),
                request(8'd145, dform(6'd50, 5'd31, 16'd0)));
            reply_memory(tag(145), 64'h3ff0000000000000, 1'b0);
            await_head(tag(144));
            if (result_o.fpr_write || result_o.exception != FPU_NO_EXCEPTION ||
                !result1_valid_o || result1_o.tag != tag(145))
                $fatal(1, "enabled invalid dual-retire fpr_write=%b exception=%0d result1_valid=%b result1_tag=%h head=%h second=%h",
                       result_o.fpr_write, result_o.exception,
                       result1_valid_o, result1_o.tag, result_o, result1_o);
            @(negedge clk_i);
            commit_tag_i = tag(144);
            commit_valid_i = 1'b1;
            commit1_tag_i = tag(145);
            commit1_valid_i = 1'b1;
            @(posedge clk_i);
            accept0 = commit_ready_o;
            accept1 = commit1_ready_o;
            #2;
            commit_valid_i = 1'b0;
            commit1_valid_i = 1'b0;
            if (!accept0 || !accept1)
                $fatal(1, "suppressed-result/load dual retirement rejected");
            checks += 3;
        end

        attempts = 0;
        while (mem_req_valid_o || result_valid_o || result1_valid_o) begin
            @(negedge clk_i);
            attempts++;
            if (attempts > 8) $fatal(1, "dual bench left pending results");
        end
        if (store_valid_o || store_o.write)
            $fatal(1, "dual bench exposed unauthorized store %h", store_o);
        if (CPU_602 && (!inspect_sp_o[31-4] || inspect_lt_o[31-4]))
            $fatal(1, "602 dual load tag incorrect SP=%h LT=%h",
                   inspect_sp_o, inspect_lt_o);
        $display("%s FPU dual reservation checks PASS: %0d",
                 CPU_602 ? "602" : "603e", checks);
        $finish;
    end
endmodule
`default_nettype wire
