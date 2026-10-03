// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// FPU fit measurement. Every port passes through one boundary register
// standing in for the integrator's flop (port P: P_ibq or P_obq).
`default_nettype none
module ppc_fpu_measure #(
    parameter bit CPU_602 = 1'b0,
    // Measures ppc_fpu_compact instead of ppc_fpu.
    parameter bit COMPACT = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,
    input logic issue_valid_i,
    output logic issue_ready_o,
    input ppc_fpu_pkg::ppc_fpu_issue_t issue_i,
    input logic issue1_valid_i,
    output logic issue1_ready_o,
    input ppc_fpu_pkg::ppc_fpu_issue_t issue1_i,
    output logic result_valid_o,
    output ppc_fpu_pkg::ppc_fpu_result_t result_o,
    output logic result1_valid_o,
    output ppc_fpu_pkg::ppc_fpu_result_t result1_o,
    input logic commit_valid_i,
    input ppc_pkg::completion_tag_t commit_tag_i,
    output logic commit_ready_o,
    input logic commit1_valid_i,
    input ppc_pkg::completion_tag_t commit1_tag_i,
    output logic commit1_ready_o,
    input logic abort_valid_i,
    input ppc_pkg::completion_tag_t abort_tag_i,
    input logic kill_all_i,
    output logic mem_req_valid_o,
    input logic mem_req_ready_i,
    output ppc_fpu_pkg::ppc_fpu_mem_t mem_req_o,
    input logic mem_rsp_valid_i,
    output logic mem_rsp_ready_o,
    input ppc_fpu_pkg::ppc_fpu_mem_rsp_t mem_rsp_i,
    output logic store_valid_o,
    input logic store_ready_i,
    output ppc_fpu_pkg::ppc_fpu_mem_t store_o,
    input logic [4:0] inspect_fpr_index_i,
    output logic [63:0] inspect_fpr_o,
    output logic [31:0] inspect_fpscr_o,
    output logic [31:0] inspect_sp_o,
    output logic [31:0] inspect_lt_o,
    output logic forward_valid_o,
    output ppc_fpu_pkg::ppc_fpu_forward_t forward_o,
    output logic forward1_valid_o,
    output ppc_fpu_pkg::ppc_fpu_forward_t forward1_o,
    output ppc_fpu_pkg::ppc_fpu_forward_data_t forward_data_o,
    output ppc_fpu_pkg::ppc_fpu_forward_data_t forward1_data_o
);
    logic rst_ni_ibq;
    logic issue_valid_i_ibq;
    ppc_fpu_pkg::ppc_fpu_issue_t issue_i_ibq;
    logic issue1_valid_i_ibq;
    ppc_fpu_pkg::ppc_fpu_issue_t issue1_i_ibq;
    logic commit_valid_i_ibq;
    ppc_pkg::completion_tag_t commit_tag_i_ibq;
    logic commit1_valid_i_ibq;
    ppc_pkg::completion_tag_t commit1_tag_i_ibq;
    logic abort_valid_i_ibq;
    ppc_pkg::completion_tag_t abort_tag_i_ibq;
    logic kill_all_i_ibq;
    logic mem_req_ready_i_ibq;
    logic mem_rsp_valid_i_ibq;
    ppc_fpu_pkg::ppc_fpu_mem_rsp_t mem_rsp_i_ibq;
    logic store_ready_i_ibq;
    logic [4:0] inspect_fpr_index_i_ibq;

    logic issue_ready;
    logic issue1_ready;
    logic result_valid;
    ppc_fpu_pkg::ppc_fpu_result_t result;
    logic result1_valid;
    ppc_fpu_pkg::ppc_fpu_result_t result1;
    logic commit_ready;
    logic commit1_ready;
    logic mem_req_valid;
    ppc_fpu_pkg::ppc_fpu_mem_t mem_req;
    logic mem_rsp_ready;
    logic store_valid;
    ppc_fpu_pkg::ppc_fpu_mem_t store;
    logic [63:0] inspect_fpr;
    logic [31:0] inspect_fpscr;
    logic [31:0] inspect_sp;
    logic [31:0] inspect_lt;
    logic forward_valid;
    ppc_fpu_pkg::ppc_fpu_forward_t forward;
    logic forward1_valid;
    ppc_fpu_pkg::ppc_fpu_forward_t forward1;
    ppc_fpu_pkg::ppc_fpu_forward_data_t forward_data;
    ppc_fpu_pkg::ppc_fpu_forward_data_t forward1_data;

    logic issue_ready_o_obq;
    logic issue1_ready_o_obq;
    logic result_valid_o_obq;
    ppc_fpu_pkg::ppc_fpu_result_t result_o_obq;
    logic result1_valid_o_obq;
    ppc_fpu_pkg::ppc_fpu_result_t result1_o_obq;
    logic commit_ready_o_obq;
    logic commit1_ready_o_obq;
    logic mem_req_valid_o_obq;
    ppc_fpu_pkg::ppc_fpu_mem_t mem_req_o_obq;
    logic mem_rsp_ready_o_obq;
    logic store_valid_o_obq;
    ppc_fpu_pkg::ppc_fpu_mem_t store_o_obq;
    logic [63:0] inspect_fpr_o_obq;
    logic [31:0] inspect_fpscr_o_obq;
    logic [31:0] inspect_sp_o_obq;
    logic [31:0] inspect_lt_o_obq;
    logic forward_valid_o_obq;
    ppc_fpu_pkg::ppc_fpu_forward_t forward_o_obq;
    logic forward1_valid_o_obq;
    ppc_fpu_pkg::ppc_fpu_forward_t forward1_o_obq;
    ppc_fpu_pkg::ppc_fpu_forward_data_t forward_data_o_obq;
    ppc_fpu_pkg::ppc_fpu_forward_data_t forward1_data_o_obq;

    always_ff @(posedge clk_i) begin
        rst_ni_ibq <= rst_ni;
        issue_valid_i_ibq <= issue_valid_i;
        issue_i_ibq <= issue_i;
        issue1_valid_i_ibq <= issue1_valid_i;
        issue1_i_ibq <= issue1_i;
        commit_valid_i_ibq <= commit_valid_i;
        commit_tag_i_ibq <= commit_tag_i;
        commit1_valid_i_ibq <= commit1_valid_i;
        commit1_tag_i_ibq <= commit1_tag_i;
        abort_valid_i_ibq <= abort_valid_i;
        abort_tag_i_ibq <= abort_tag_i;
        kill_all_i_ibq <= kill_all_i;
        mem_req_ready_i_ibq <= mem_req_ready_i;
        mem_rsp_valid_i_ibq <= mem_rsp_valid_i;
        mem_rsp_i_ibq <= mem_rsp_i;
        store_ready_i_ibq <= store_ready_i;
        inspect_fpr_index_i_ibq <= inspect_fpr_index_i;

        issue_ready_o_obq <= issue_ready;
        issue1_ready_o_obq <= issue1_ready;
        result_valid_o_obq <= result_valid;
        result_o_obq <= result;
        result1_valid_o_obq <= result1_valid;
        result1_o_obq <= result1;
        commit_ready_o_obq <= commit_ready;
        commit1_ready_o_obq <= commit1_ready;
        mem_req_valid_o_obq <= mem_req_valid;
        mem_req_o_obq <= mem_req;
        mem_rsp_ready_o_obq <= mem_rsp_ready;
        store_valid_o_obq <= store_valid;
        store_o_obq <= store;
        inspect_fpr_o_obq <= inspect_fpr;
        inspect_fpscr_o_obq <= inspect_fpscr;
        inspect_sp_o_obq <= inspect_sp;
        inspect_lt_o_obq <= inspect_lt;
        forward_valid_o_obq <= forward_valid;
        forward_o_obq <= forward;
        forward1_valid_o_obq <= forward1_valid;
        forward1_o_obq <= forward1;
        forward_data_o_obq <= forward_data;
        forward1_data_o_obq <= forward1_data;
    end

    assign issue_ready_o = issue_ready_o_obq;
    assign issue1_ready_o = issue1_ready_o_obq;
    assign result_valid_o = result_valid_o_obq;
    assign result_o = result_o_obq;
    assign result1_valid_o = result1_valid_o_obq;
    assign result1_o = result1_o_obq;
    assign commit_ready_o = commit_ready_o_obq;
    assign commit1_ready_o = commit1_ready_o_obq;
    assign mem_req_valid_o = mem_req_valid_o_obq;
    assign mem_req_o = mem_req_o_obq;
    assign mem_rsp_ready_o = mem_rsp_ready_o_obq;
    assign store_valid_o = store_valid_o_obq;
    assign store_o = store_o_obq;
    assign inspect_fpr_o = inspect_fpr_o_obq;
    assign inspect_fpscr_o = inspect_fpscr_o_obq;
    assign inspect_sp_o = inspect_sp_o_obq;
    assign inspect_lt_o = inspect_lt_o_obq;
    assign forward_valid_o = forward_valid_o_obq;
    assign forward_o = forward_o_obq;
    assign forward1_valid_o = forward1_valid_o_obq;
    assign forward1_o = forward1_o_obq;
    assign forward_data_o = forward_data_o_obq;
    assign forward1_data_o = forward1_data_o_obq;

    generate
        if (COMPACT) begin : g_compact
            ppc_fpu_compact #(.CPU_602(CPU_602)) fpu (
                .clk_i(clk_i),
                .rst_ni(rst_ni_ibq),
                .issue_valid_i(issue_valid_i_ibq),
                .issue_ready_o(issue_ready),
                .issue_i(issue_i_ibq),
                .issue1_valid_i(issue1_valid_i_ibq),
                .issue1_ready_o(issue1_ready),
                .issue1_i(issue1_i_ibq),
                .result_valid_o(result_valid),
                .result_o(result),
                .result1_valid_o(result1_valid),
                .result1_o(result1),
                .commit_valid_i(commit_valid_i_ibq),
                .commit_tag_i(commit_tag_i_ibq),
                .commit_ready_o(commit_ready),
                .commit1_valid_i(commit1_valid_i_ibq),
                .commit1_tag_i(commit1_tag_i_ibq),
                .commit1_ready_o(commit1_ready),
                .abort_valid_i(abort_valid_i_ibq),
                .abort_tag_i(abort_tag_i_ibq),
                .kill_all_i(kill_all_i_ibq),
                .mem_req_valid_o(mem_req_valid),
                .mem_req_ready_i(mem_req_ready_i_ibq),
                .mem_req_o(mem_req),
                .mem_rsp_valid_i(mem_rsp_valid_i_ibq),
                .mem_rsp_ready_o(mem_rsp_ready),
                .mem_rsp_i(mem_rsp_i_ibq),
                .store_valid_o(store_valid),
                .store_ready_i(store_ready_i_ibq),
                .store_o(store),
                .inspect_fpr_index_i(inspect_fpr_index_i_ibq),
                .inspect_fpr_o(inspect_fpr),
                .inspect_fpscr_o(inspect_fpscr),
                .inspect_sp_o(inspect_sp),
                .inspect_lt_o(inspect_lt),
                .forward_valid_o(forward_valid),
                .forward_o(forward),
                .forward1_valid_o(forward1_valid),
                .forward1_o(forward1),
                .forward_data_o(forward_data),
                .forward1_data_o(forward1_data)
            );
        end else begin : g_full
            ppc_fpu #(.CPU_602(CPU_602)) fpu (
                .clk_i(clk_i),
                .rst_ni(rst_ni_ibq),
                .issue_valid_i(issue_valid_i_ibq),
                .issue_ready_o(issue_ready),
                .issue_i(issue_i_ibq),
                .issue1_valid_i(issue1_valid_i_ibq),
                .issue1_ready_o(issue1_ready),
                .issue1_i(issue1_i_ibq),
                .result_valid_o(result_valid),
                .result_o(result),
                .result1_valid_o(result1_valid),
                .result1_o(result1),
                .commit_valid_i(commit_valid_i_ibq),
                .commit_tag_i(commit_tag_i_ibq),
                .commit_ready_o(commit_ready),
                .commit1_valid_i(commit1_valid_i_ibq),
                .commit1_tag_i(commit1_tag_i_ibq),
                .commit1_ready_o(commit1_ready),
                .abort_valid_i(abort_valid_i_ibq),
                .abort_tag_i(abort_tag_i_ibq),
                .kill_all_i(kill_all_i_ibq),
                .mem_req_valid_o(mem_req_valid),
                .mem_req_ready_i(mem_req_ready_i_ibq),
                .mem_req_o(mem_req),
                .mem_rsp_valid_i(mem_rsp_valid_i_ibq),
                .mem_rsp_ready_o(mem_rsp_ready),
                .mem_rsp_i(mem_rsp_i_ibq),
                .store_valid_o(store_valid),
                .store_ready_i(store_ready_i_ibq),
                .store_o(store),
                .inspect_fpr_index_i(inspect_fpr_index_i_ibq),
                .inspect_fpr_o(inspect_fpr),
                .inspect_fpscr_o(inspect_fpscr),
                .inspect_sp_o(inspect_sp),
                .inspect_lt_o(inspect_lt),
                .forward_valid_o(forward_valid),
                .forward_o(forward),
                .forward1_valid_o(forward1_valid),
                .forward1_o(forward1),
                .forward_data_o(forward_data),
                .forward1_data_o(forward1_data)
            );
        end
    endgenerate
endmodule
`default_nettype wire
