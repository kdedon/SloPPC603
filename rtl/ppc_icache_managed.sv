// Local maintenance and enable/bypass control around ppc_icache.
// This is an integration control interface, not a HID0 or icbi implementation.
module ppc_icache_managed #(
  parameter logic RESET_CACHE_ENABLE = 1'b1
) (
  input  logic         clk_i,
  input  logic         rst_ni,

  input  logic         fetch_valid_i,
  output logic         fetch_ready_o,
  input  logic [31:0]  fetch_addr_i,
  output logic         fetch_rsp_valid_o,
  input  logic         fetch_rsp_ready_i,
  output logic [31:0]  fetch_rsp_insn_o,
  output logic         fetch_rsp_error_o,

  input  logic         maintenance_valid_i,
  output logic         maintenance_ready_o,
  input  logic         maintenance_invalidate_i,
  input  logic         maintenance_cache_enable_i,
  output logic         maintenance_done_valid_o,
  input  logic         maintenance_done_ready_i,
  output logic         cache_enabled_o,
  output logic         maintenance_busy_o,

  output logic         bypass_req_valid_o,
  input  logic         bypass_req_ready_i,
  output logic [31:0]  bypass_req_addr_o,
  input  logic         bypass_rsp_valid_i,
  output logic         bypass_rsp_ready_o,
  input  logic [31:0]  bypass_rsp_insn_i,
  input  logic         bypass_ifetch_error_i,

  output logic         line_req_valid_o,
  input  logic         line_req_ready_i,
  output logic [31:0]  line_req_line_addr_o,
  output logic [1:0]   line_req_critical_dw_o,
  output logic         line_req_instruction_o,
  input  logic         line_rsp_valid_i,
  output logic         line_rsp_ready_o,
  input  logic [255:0] line_rsp_line_i,
  input  logic         line_rsp_error_i,

  output logic         busy_o,
  output logic         hit_o,
  output logic         miss_o,
  output logic         protocol_error_o
);
  typedef enum logic [2:0] {
    MANAGED_RUN,
    MANAGED_DRAIN,
    MANAGED_INVALIDATE_PULSE,
    MANAGED_INVALIDATE_WAIT,
    MANAGED_DONE,
    MANAGED_INVALID
  } managed_state_t;

  managed_state_t state_q;
  logic cache_enabled_q;
  logic target_enable_q, invalidate_required_q;
  logic fetch_outstanding_q;
  logic protocol_error_q;

  logic cache_fetch_valid, cache_fetch_ready;
  logic cache_rsp_valid, cache_rsp_ready, cache_rsp_error;
  logic [31:0] cache_rsp_insn;
  logic cache_invalidate, cache_invalidate_done;
  logic cache_busy, cache_protocol_error;
  logic cache_hit, cache_miss;
  logic accept_fetch, complete_fetch;
  logic command_priority;
  logic fetch_accept_enable;

  ppc_icache cache (
    .clk_i, .rst_ni,
    .fetch_valid_i(cache_fetch_valid), .fetch_ready_o(cache_fetch_ready),
    .fetch_addr_i(fetch_addr_i), .fetch_rsp_valid_o(cache_rsp_valid),
    .fetch_rsp_ready_i(cache_rsp_ready), .fetch_rsp_insn_o(cache_rsp_insn),
    .fetch_rsp_error_o(cache_rsp_error), .kill_i(1'b0),
    .invalidate_i(cache_invalidate),
    .invalidate_done_o(cache_invalidate_done),
    .line_req_valid_o, .line_req_ready_i, .line_req_line_addr_o,
    .line_req_critical_dw_o, .line_req_instruction_o,
    .line_rsp_valid_i, .line_rsp_ready_o, .line_rsp_line_i,
    .line_rsp_error_i, .busy_o(cache_busy), .hit_o(cache_hit),
    .miss_o(cache_miss), .protocol_error_o(cache_protocol_error)
  );

  assign maintenance_ready_o = rst_ni && state_q == MANAGED_RUN;
  assign maintenance_done_valid_o = rst_ni && state_q == MANAGED_DONE;
  assign maintenance_busy_o = rst_ni && state_q != MANAGED_RUN;
  assign cache_enabled_o = rst_ni && cache_enabled_q;
  assign command_priority = maintenance_valid_i && maintenance_ready_o;
  assign fetch_accept_enable = rst_ni && state_q == MANAGED_RUN &&
                               !fetch_outstanding_q && !command_priority;
  assign cache_fetch_valid = fetch_accept_enable && cache_enabled_q &&
                             fetch_valid_i;
  assign bypass_req_valid_o = fetch_accept_enable && !cache_enabled_q &&
                              fetch_valid_i;
  assign bypass_req_addr_o = fetch_addr_i;
  assign fetch_ready_o = fetch_accept_enable &&
    (cache_enabled_q ? cache_fetch_ready : bypass_req_ready_i);

  always_comb begin
    fetch_rsp_valid_o = 1'b0;
    fetch_rsp_insn_o = 32'b0;
    fetch_rsp_error_o = 1'b0;
    cache_rsp_ready = 1'b0;
    bypass_rsp_ready_o = 1'b0;
    if (rst_ni && fetch_outstanding_q) begin
      if (cache_enabled_q) begin
        fetch_rsp_valid_o = cache_rsp_valid;
        fetch_rsp_insn_o = cache_rsp_insn;
        fetch_rsp_error_o = cache_rsp_error;
        cache_rsp_ready = fetch_rsp_ready_i;
      end else begin
        fetch_rsp_valid_o = bypass_rsp_valid_i;
        fetch_rsp_insn_o = bypass_rsp_insn_i;
        bypass_rsp_ready_o = fetch_rsp_ready_i;
      end
    end

  end

  assign cache_invalidate = state_q == MANAGED_INVALIDATE_PULSE;
  assign accept_fetch = fetch_valid_i && fetch_ready_o;
  assign complete_fetch = fetch_rsp_valid_o && fetch_rsp_ready_i;
  assign hit_o = cache_enabled_q && cache_hit;
  assign miss_o = cache_enabled_q && cache_miss;
  assign busy_o = rst_ni && (state_q != MANAGED_RUN || fetch_outstanding_q ||
                             cache_busy);
  assign protocol_error_o = rst_ni &&
                            (protocol_error_q || cache_protocol_error);

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= MANAGED_RUN;
      cache_enabled_q <= RESET_CACHE_ENABLE;
      target_enable_q <= RESET_CACHE_ENABLE;
      invalidate_required_q <= 1'b0;
      fetch_outstanding_q <= 1'b0;
      protocol_error_q <= 1'b0;
    end else begin
      if (accept_fetch)
        fetch_outstanding_q <= 1'b1;
      if (complete_fetch ||
          (fetch_outstanding_q && !cache_enabled_q &&
           bypass_ifetch_error_i))
        fetch_outstanding_q <= 1'b0;

      if ((cache_rsp_valid || bypass_rsp_valid_i) &&
          !fetch_outstanding_q)
        protocol_error_q <= 1'b1;

      unique case (state_q)
        MANAGED_RUN: begin
          if (command_priority) begin
            target_enable_q <= maintenance_cache_enable_i;
            // Changing modes always invalidates.  This prevents a line filled
            // before bypass from becoming visible again after re-enable.
            invalidate_required_q <= maintenance_invalidate_i ||
              (maintenance_cache_enable_i != cache_enabled_q);
            state_q <= MANAGED_DRAIN;
          end
        end

        MANAGED_DRAIN: begin
          if (!fetch_outstanding_q && !cache_busy) begin
            if (invalidate_required_q)
              state_q <= MANAGED_INVALIDATE_PULSE;
            else begin
              cache_enabled_q <= target_enable_q;
              state_q <= MANAGED_DONE;
            end
          end
        end

        MANAGED_INVALIDATE_PULSE: begin
          state_q <= MANAGED_INVALIDATE_WAIT;
        end

        MANAGED_INVALIDATE_WAIT: begin
          if (cache_invalidate_done) begin
            cache_enabled_q <= target_enable_q;
            state_q <= MANAGED_DONE;
          end
        end

        MANAGED_DONE: begin
          if (maintenance_done_ready_i)
            state_q <= MANAGED_RUN;
        end

        default: begin
          protocol_error_q <= 1'b1;
          state_q <= MANAGED_INVALID;
        end
      endcase
    end
  end
endmodule
