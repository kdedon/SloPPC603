// Bounded cacheable 32-byte line-read master for a 64-bit 60x bus.
// Four physical beats are accepted in critical-doubleword-first wrap order
// and normalized into line-base order in the 256-bit response.
module ppc_bus60x_line_read (
  input  logic         clk_i,
  input  logic         rst_ni,

  input  logic         req_valid_i,
  output logic         req_ready_o,
  input  logic [31:0]  req_line_addr_i,
  input  logic [1:0]   req_critical_dw_i,
  input  logic         req_instruction_i,
  output logic         rsp_valid_o,
  input  logic         rsp_ready_i,
  output logic [255:0] rsp_line_o,
  output logic         rsp_error_o,
  output logic         busy_o,
  output logic         protocol_error_o,

  output logic         br_n_o,
  input  logic         bg_n_i,
  input  logic         abb_n_i,
  output logic         abb_n_o,
  output logic         abb_oe_o,
  output logic         ts_n_o,
  output logic         ts_oe_o,
  output logic [31:0]  a_o,
  output logic [4:0]   tt_o,
  output logic         tbst_n_o,
  output logic [2:0]   tsiz_o,
  output logic [1:0]   tc_o,
  output logic         ci_n_o,
  output logic         wt_n_o,
  output logic         gbl_n_o,
  output logic [1:0]   cse_o,
  output logic         addr_oe_o,
  input  logic         aack_n_i,
  input  logic         artry_n_i,

  input  logic         dbg_n_i,
  input  logic         dbb_n_i,
  output logic         dbb_n_o,
  output logic         dbb_oe_o,
  input  logic [63:0]  d_i,
  output logic [63:0]  d_o,
  output logic         d_oe_o,
  input  logic         ta_n_i,
  input  logic         drtry_n_i,
  input  logic         tea_n_i
);
  typedef enum logic [3:0] {
    LINE_IDLE,
    LINE_ADDR_REQUEST,
    LINE_ADDR_TRANSFER,
    LINE_ADDR_WAIT,
    LINE_ADDR_RETRY_SAMPLE,
    LINE_RETRY_GAP,
    LINE_DATA_REQUEST,
    LINE_DATA_WAIT,
    LINE_BEAT_CONFIRM,
    LINE_BEAT_REPLACEMENT,
    LINE_DATA_ERROR_RELEASE,
    LINE_FATAL_UNUSED
  } line_state_t;

  line_state_t state_q;
  logic [31:0] start_addr_q;
  logic [1:0] critical_dw_q;
  logic instruction_q;
  logic [1:0] beat_count_q;
  logic [63:0] provisional_q;
  logic [255:0] line_work_q;
  logic [255:0] rsp_line_q;
  logic rsp_valid_q, rsp_error_q, protocol_error_q;
  logic addr_release_pending_q, data_release_pending_q;
  logic addr_release_half_q, data_release_half_q;
  logic final_release_started_q, release_oe_cycle_q;
  logic [1:0] current_slot;

  function automatic logic [255:0] insert_doubleword(
    input logic [255:0] prior,
    input logic [1:0] slot,
    input logic [63:0] value
  );
    logic [255:0] result;
    begin
      result = prior;
      unique case (slot)
        2'd0: result[255:192] = value;
        2'd1: result[191:128] = value;
        2'd2: result[127:64] = value;
        2'd3: result[63:0] = value;
      endcase
      return result;
    end
  endfunction

  assign current_slot = critical_dw_q + beat_count_q;

  always_comb begin
    req_ready_o = rst_ni && (state_q == LINE_IDLE) && !rsp_valid_q;
    rsp_valid_o = rst_ni && rsp_valid_q;
    rsp_line_o = rsp_line_q;
    rsp_error_o = rsp_error_q;
    protocol_error_o = rst_ni && protocol_error_q;
    busy_o = rst_ni && ((state_q != LINE_IDLE) || rsp_valid_q);

    br_n_o = (rst_ni && (state_q == LINE_ADDR_REQUEST)) ? 1'b0 : 1'b1;
    abb_oe_o = rst_ni && ((state_q == LINE_ADDR_TRANSFER) ||
                          (state_q == LINE_ADDR_WAIT) ||
                          (state_q == LINE_ADDR_RETRY_SAMPLE));
    abb_n_o = addr_release_half_q ? 1'b1 : 1'b0;
    ts_oe_o = abb_oe_o;
    ts_n_o = (state_q == LINE_ADDR_TRANSFER) ? 1'b0 : 1'b1;
    addr_oe_o = abb_oe_o;

    a_o = start_addr_q;
    tt_o = 5'b01110;
    tbst_n_o = 1'b0;
    tsiz_o = 3'b010;
    tc_o = instruction_q ? 2'b10 : 2'b00;
    ci_n_o = 1'b1;
    wt_n_o = 1'b1;
    gbl_n_o = 1'b1;
    cse_o = 2'b00;

    dbb_oe_o = rst_ni &&
               ((state_q == LINE_DATA_WAIT) ||
                (state_q == LINE_BEAT_CONFIRM) ||
                ((state_q == LINE_BEAT_REPLACEMENT) &&
                 !final_release_started_q) ||
                ((state_q == LINE_DATA_ERROR_RELEASE) &&
                 !final_release_started_q)) &&
               (!final_release_started_q || release_oe_cycle_q);
    dbb_n_o = data_release_half_q ? 1'b1 : 1'b0;
    d_o = 64'b0;
    d_oe_o = 1'b0;
  end

  always_ff @(negedge clk_i) begin
    if (!rst_ni) begin
      addr_release_half_q <= 1'b0;
      data_release_half_q <= 1'b0;
    end else begin
      addr_release_half_q <= addr_release_pending_q;
      data_release_half_q <= data_release_pending_q;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= LINE_IDLE;
      start_addr_q <= 32'b0;
      critical_dw_q <= 2'b0;
      instruction_q <= 1'b0;
      beat_count_q <= 2'b0;
      provisional_q <= 64'b0;
      line_work_q <= 256'b0;
      rsp_line_q <= 256'b0;
      rsp_valid_q <= 1'b0;
      rsp_error_q <= 1'b0;
      protocol_error_q <= 1'b0;
      addr_release_pending_q <= 1'b0;
      data_release_pending_q <= 1'b0;
      final_release_started_q <= 1'b0;
      release_oe_cycle_q <= 1'b0;
    end else begin
      if (rsp_valid_q && rsp_ready_i)
        rsp_valid_q <= 1'b0;

      unique case (state_q)
        LINE_IDLE: begin
          addr_release_pending_q <= 1'b0;
          data_release_pending_q <= 1'b0;
          final_release_started_q <= 1'b0;
          release_oe_cycle_q <= 1'b0;
          if (req_valid_i && req_ready_o) begin
            if (req_line_addr_i[4:0] != 5'b00000) begin
              rsp_line_q <= 256'b0;
              rsp_error_q <= 1'b1;
              rsp_valid_q <= 1'b1;
              protocol_error_q <= 1'b1;
            end else begin
              start_addr_q <= req_line_addr_i +
                              {27'b0, req_critical_dw_i, 3'b000};
              critical_dw_q <= req_critical_dw_i;
              instruction_q <= req_instruction_i;
              beat_count_q <= 2'b0;
              provisional_q <= 64'b0;
              line_work_q <= 256'b0;
              rsp_error_q <= 1'b0;
              state_q <= LINE_ADDR_REQUEST;
            end
          end
        end

        LINE_ADDR_REQUEST: begin
          if (!bg_n_i && abb_n_i && artry_n_i)
            state_q <= LINE_ADDR_TRANSFER;
        end

        LINE_ADDR_TRANSFER: begin
          if (!aack_n_i) begin
            addr_release_pending_q <= 1'b1;
            state_q <= LINE_ADDR_RETRY_SAMPLE;
          end else begin
            state_q <= LINE_ADDR_WAIT;
          end
        end

        LINE_ADDR_WAIT: begin
          if (!aack_n_i) begin
            addr_release_pending_q <= 1'b1;
            state_q <= LINE_ADDR_RETRY_SAMPLE;
          end
        end

        LINE_ADDR_RETRY_SAMPLE: begin
          addr_release_pending_q <= 1'b0;
          if (!artry_n_i)
            state_q <= LINE_RETRY_GAP;
          else
            state_q <= LINE_DATA_REQUEST;
        end

        LINE_RETRY_GAP: begin
          state_q <= LINE_ADDR_REQUEST;
        end

        LINE_DATA_REQUEST: begin
          if (!dbg_n_i && dbb_n_i && drtry_n_i && artry_n_i)
            state_q <= LINE_DATA_WAIT;
        end

        LINE_DATA_WAIT: begin
          release_oe_cycle_q <= 1'b0;
          if (!tea_n_i) begin
            rsp_line_q <= 256'b0;
            rsp_error_q <= 1'b1;
            data_release_pending_q <= 1'b1;
            state_q <= LINE_DATA_ERROR_RELEASE;
          end else if (!drtry_n_i) begin
            rsp_line_q <= 256'b0;
            rsp_error_q <= 1'b1;
            protocol_error_q <= 1'b1;
            data_release_pending_q <= 1'b1;
            state_q <= LINE_DATA_ERROR_RELEASE;
          end else if (!ta_n_i) begin
            provisional_q <= d_i;
            if (beat_count_q == 2'd3) begin
              final_release_started_q <= 1'b1;
              release_oe_cycle_q <= 1'b1;
              data_release_pending_q <= 1'b1;
            end
            state_q <= LINE_BEAT_CONFIRM;
          end
        end

        LINE_BEAT_CONFIRM: begin
          data_release_pending_q <= 1'b0;
          release_oe_cycle_q <= 1'b0;
          if (!tea_n_i) begin
            rsp_line_q <= 256'b0;
            rsp_error_q <= 1'b1;
            if (final_release_started_q) begin
              rsp_valid_q <= 1'b1;
              state_q <= LINE_IDLE;
            end else begin
              data_release_pending_q <= 1'b1;
              state_q <= LINE_DATA_ERROR_RELEASE;
            end
          end else if (!drtry_n_i) begin
            // Cancel the preceding candidate.  Same-edge TA is a replacement
            // for this same logical beat, not the next beat.
            if (!ta_n_i) begin
              provisional_q <= d_i;
              state_q <= LINE_BEAT_CONFIRM;
            end else begin
              state_q <= LINE_BEAT_REPLACEMENT;
            end
          end else begin
            if (beat_count_q == 2'd3) begin
              // DBB has already been released after the final TA.  A low TA
              // on this confirmation edge is not qualified by this tenure;
              // only DRTRY/TEA judge the captured final candidate.
              rsp_line_q <= insert_doubleword(
                line_work_q, current_slot, provisional_q);
              rsp_error_q <= 1'b0;
              rsp_valid_q <= 1'b1;
              state_q <= LINE_IDLE;
            end else begin
              line_work_q <= insert_doubleword(
                line_work_q, current_slot, provisional_q);
              beat_count_q <= beat_count_q + 2'd1;
              if (!ta_n_i) begin
                provisional_q <= d_i;
                if (beat_count_q == 2'd2) begin
                  final_release_started_q <= 1'b1;
                  release_oe_cycle_q <= 1'b1;
                  data_release_pending_q <= 1'b1;
                end
                state_q <= LINE_BEAT_CONFIRM;
              end else begin
                state_q <= LINE_DATA_WAIT;
              end
            end
          end
        end

        LINE_BEAT_REPLACEMENT: begin
          release_oe_cycle_q <= 1'b0;
          if (!tea_n_i) begin
            rsp_line_q <= 256'b0;
            rsp_error_q <= 1'b1;
            if (final_release_started_q) begin
              rsp_valid_q <= 1'b1;
              state_q <= LINE_IDLE;
            end else begin
              data_release_pending_q <= 1'b1;
              state_q <= LINE_DATA_ERROR_RELEASE;
            end
          end else if (drtry_n_i) begin
            rsp_line_q <= 256'b0;
            rsp_error_q <= 1'b1;
            protocol_error_q <= 1'b1;
            if (final_release_started_q) begin
              rsp_valid_q <= 1'b1;
              state_q <= LINE_IDLE;
            end else begin
              data_release_pending_q <= 1'b1;
              state_q <= LINE_DATA_ERROR_RELEASE;
            end
          end else if (!ta_n_i) begin
            provisional_q <= d_i;
            state_q <= LINE_BEAT_CONFIRM;
          end
        end

        LINE_DATA_ERROR_RELEASE: begin
          data_release_pending_q <= 1'b0;
          release_oe_cycle_q <= 1'b0;
          rsp_valid_q <= 1'b1;
          rsp_line_q <= 256'b0;
          rsp_error_q <= 1'b1;
          state_q <= LINE_IDLE;
        end

        default: begin
          state_q <= LINE_IDLE;
          protocol_error_q <= 1'b1;
        end
      endcase
    end
  end
endmodule
