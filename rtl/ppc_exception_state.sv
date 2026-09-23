// Standalone 32-bit 603e exception state foundation.
//
// The caller presents one already-selected committed-boundary event. This unit
// does not detect the oldest fault or arbitrate simultaneous exception causes.
module ppc_exception_state #(
  parameter logic [31:0] RESET_MSR  = 32'b0,
  parameter logic [31:0] RESET_SRR0 = 32'b0,
  parameter logic [31:0] RESET_SRR1 = 32'b0,
  parameter bit ENABLE_TLB_MISS_EXCEPTIONS = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        event_valid_i,
  output logic        event_ready_o,
  input  logic [3:0]  event_kind_i,
  input  logic [31:0] event_pc_i,
  // Used only by EVENT_ISI: 1=protection, 2=guarded; others reject.
  input  logic [2:0]  event_isi_cause_i,
  // Miss-time fields are supplied by the selected oldest accepted request.
  input  logic [3:0]  event_miss_cr0_i,
  input  logic        event_miss_key_i,
  input  logic        event_miss_way_i,
  // Pending-exception priority after RFI is deliberately outside this unit.
  // Assert this input to reject, rather than misexecute, such an RFI request.
  input  logic        rfi_pending_exception_i,

  output logic        result_valid_o,
  input  logic        result_ready_i,
  output logic        result_supported_o,
  output logic        result_is_exception_o,
  output logic [31:0] result_target_o,

  // Atomic committed-state load for a future CSR/handler integration and for
  // direct verification. An event wins a same-edge collision; the load stalls.
  input  logic        state_load_valid_i,
  output logic        state_load_ready_o,
  input  logic [2:0]  state_load_enable_i,
  input  logic [31:0] state_load_msr_i,
  input  logic [31:0] state_load_srr0_i,
  input  logic [31:0] state_load_srr1_i,

  output logic [31:0] msr_o,
  output logic [31:0] srr0_o,
  output logic [31:0] srr1_o
);
  // These local encodings are part of this standalone module's interface.
  localparam logic [3:0] EVENT_SC             = 4'd0;
  localparam logic [3:0] EVENT_PROGRAM_ILLEGAL = 4'd1;
  localparam logic [3:0] EVENT_PROGRAM_PRIV    = 4'd2;
  localparam logic [3:0] EVENT_RFI             = 4'd3;
  localparam logic [3:0] EVENT_ALIGNMENT       = 4'd4;
  localparam logic [3:0] EVENT_ISI             = 4'd5;
  localparam logic [3:0] EVENT_EXTERNAL        = 4'd6;
  localparam logic [3:0] EVENT_DECREMENTER     = 4'd7;
  localparam logic [3:0] EVENT_DSI             = 4'd8;
  localparam logic [3:0] EVENT_TLB_I_MISS      = 4'd9;
  localparam logic [3:0] EVENT_TLB_D_LOAD      = 4'd10;
  localparam logic [3:0] EVENT_TLB_D_STORE     = 4'd11;

  // PowerPC manual bits 0, 5-9, and 16-31 become HDL bits 31, 26:22, 15:0.
  localparam logic [31:0] SRR_SAVE_RESTORE_MASK = 32'h87c0_ffff;
  // Program exception causes: manual bit 12 illegal and bit 13 privileged.
  localparam logic [31:0] SRR1_PROGRAM_ILLEGAL = 32'h0008_0000;
  localparam logic [31:0] SRR1_PROGRAM_PRIV    = 32'h0004_0000;

  logic [31:0] msr_q, srr0_q, srr1_q;
  logic result_valid_q, result_supported_q, result_is_exception_q;
  logic [31:0] result_target_q;
  logic slot_available, event_fire, state_load_fire;

  assign msr_o = msr_q;
  assign srr0_o = srr0_q;
  assign srr1_o = srr1_q;
  // Reset immediately withdraws an old response from the external handshake;
  // the registered state itself resets on the next active clock edge.
  assign result_valid_o = rst_ni && result_valid_q;
  assign result_supported_o = result_supported_q;
  assign result_is_exception_o = result_is_exception_q;
  assign result_target_o = result_target_q;

  assign slot_available = !result_valid_q || result_ready_i;
  assign event_ready_o = rst_ni && slot_available;
  assign state_load_ready_o = rst_ni && slot_available && !event_valid_i;
  assign event_fire = event_valid_i && event_ready_o;
  assign state_load_fire = state_load_valid_i && state_load_ready_o;

  function automatic logic [31:0] exception_srr1(
    input logic [31:0] old_msr,
    input logic [31:0] cause
  );
    return (old_msr & SRR_SAVE_RESTORE_MASK) | cause;
  endfunction

  function automatic logic [31:0] miss_srr1(
    input logic [4:0] saved_msr_high,
    input logic [15:0] saved_msr_low,
    input logic [3:0] cr0,
    input logic key,
    input logic instruction,
    input logic way,
    input logic store_access
  );
    // UM Table 4-4: CR0 replaces manual bits 0..3; bits 5..9 and 16..31
    // preserve old MSR, and bits 12..15 carry miss key/type/way/direction.
    return {cr0, 1'b0, saved_msr_high, 2'b0,
            key, instruction, way, store_access, saved_msr_low};
  endfunction

  function automatic logic [31:0] exception_msr(input logic [31:0] old_msr);
    logic [31:0] next_msr;
    begin
      next_msr = old_msr;
      // Manual bit numbers and HDL indices:
      // POW 13/18, TGPR 14/17, ILE 15/16, EE 16/15, PR 17/14,
      // FP 18/13, ME 19/12, FE0..FE1 20..23/11..8,
      // IP 25/6, IR 26/5, DR 27/4, RI 30/1, LE 31/0.
      next_msr[18] = 1'b0;
      next_msr[17] = 1'b0;
      next_msr[15] = 1'b0;
      next_msr[14] = 1'b0;
      next_msr[13] = 1'b0;
      next_msr[11:8] = 4'b0;
      next_msr[5] = 1'b0;
      next_msr[4] = 1'b0;
      next_msr[1] = 1'b0;
      next_msr[0] = old_msr[16];
      return next_msr;
    end
  endfunction

  function automatic logic [31:0] exception_vector(
    input logic ip,
    input logic [12:0] offset
  );
    return (ip ? 32'hfff0_0000 : 32'h0000_0000) |
           {19'b0, offset};
  endfunction

  function automatic logic [31:0] rfi_msr(
    input logic [31:0] old_msr,
    input logic [31:0] saved_srr1
  );
    logic [31:0] next_msr;
    begin
      next_msr = (old_msr & ~SRR_SAVE_RESTORE_MASK) |
                 (saved_srr1 & SRR_SAVE_RESTORE_MASK);
      // MSR[TGPR] is a 603e addition and RFI always clears it.
      next_msr[17] = 1'b0;
      return next_msr;
    end
  endfunction

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      msr_q <= RESET_MSR;
      srr0_q <= RESET_SRR0;
      srr1_q <= RESET_SRR1;
      result_valid_q <= 1'b0;
      result_supported_q <= 1'b0;
      result_is_exception_q <= 1'b0;
      result_target_q <= 32'b0;
    end else begin
      if (result_valid_q && result_ready_i) begin
        result_valid_q <= 1'b0;
      end

      if (state_load_fire) begin
        if (state_load_enable_i[0]) msr_q <= state_load_msr_i;
        if (state_load_enable_i[1]) srr0_q <= state_load_srr0_i;
        if (state_load_enable_i[2]) srr1_q <= state_load_srr1_i;
      end

      if (event_fire) begin
        result_valid_q <= 1'b1;
        result_supported_q <= 1'b0;
        result_is_exception_q <= 1'b0;
        result_target_q <= 32'b0;

        // All supported event PCs are committed instruction boundaries.
        if (event_pc_i[1:0] == 2'b00) begin
          unique case (event_kind_i)
            EVENT_SC: begin
              if (!msr_q[17]) begin
                srr0_q <= event_pc_i + 32'd4;
                srr1_q <= exception_srr1(msr_q, 32'b0);
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_is_exception_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[6], 13'h0c00);
              end
            end
            EVENT_PROGRAM_ILLEGAL: begin
              if (!msr_q[17]) begin
                srr0_q <= event_pc_i;
                srr1_q <= exception_srr1(msr_q, SRR1_PROGRAM_ILLEGAL);
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_is_exception_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[6], 13'h0700);
              end
            end
            EVENT_PROGRAM_PRIV: begin
              if (!msr_q[17]) begin
                srr0_q <= event_pc_i;
                srr1_q <= exception_srr1(msr_q, SRR1_PROGRAM_PRIV);
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_is_exception_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[6], 13'h0700);
              end
            end
            EVENT_ISI: begin
              if (!msr_q[17] && ((event_isi_cause_i == 3'd1) ||
                                (event_isi_cause_i == 3'd2))) begin
                srr0_q <= event_pc_i;
                // PEM Table 6-10: manual bit 4 protection, bit 3 guarded.
                srr1_q <= exception_srr1(msr_q,
                  event_isi_cause_i == 3'd1 ? 32'h0800_0000 : 32'h1000_0000);
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_is_exception_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[6], 13'h0400);
              end
            end
            EVENT_DECREMENTER: begin
              if (msr_q[15] && !msr_q[17]) begin
                srr0_q <= event_pc_i;
                // DEC follows full-function save, not external's low-half override.
                srr1_q <= msr_q & SRR_SAVE_RESTORE_MASK;
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_is_exception_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[6], 13'h0900);
              end
            end
            EVENT_EXTERNAL: begin
              if (msr_q[15] && !msr_q[17]) begin
                srr0_q <= event_pc_i;
                // UM Table 4-12: next instruction EA and low-half MSR only.
                srr1_q <= msr_q & 32'h0000_ffff;
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_is_exception_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[6], 13'h0500);
              end
            end
            EVENT_ALIGNMENT: begin
              if (!msr_q[17]) begin
                srr0_q <= event_pc_i;
                // Table 4-13 explicitly clears manual bits 0..15.
                srr1_q <= msr_q & 32'h0000_ffff;
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_is_exception_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[6], 13'h0600);
              end
            end
            EVENT_DSI: begin
              if (!msr_q[17]) begin
                srr0_q <= event_pc_i;
                // UM Table 4-11 clears manual SRR1 bits 0..15.
                srr1_q <= msr_q & 32'h0000_ffff;
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_is_exception_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[6], 13'h0300);
              end
            end
            EVENT_TLB_I_MISS, EVENT_TLB_D_LOAD,
            EVENT_TLB_D_STORE: begin
              if (ENABLE_TLB_MISS_EXCEPTIONS && !msr_q[17]) begin
                srr0_q <= event_pc_i;
                srr1_q <= miss_srr1(msr_q[26:22], msr_q[15:0], event_miss_cr0_i,
                  event_miss_key_i, event_kind_i == EVENT_TLB_I_MISS,
                  event_miss_way_i, event_kind_i == EVENT_TLB_D_STORE);
                // Table 4-16: miss entry uses the ordinary exception state
                // changes plus the separate temporary r0..r3 bank.
                msr_q <= exception_msr(msr_q) | 32'h0002_0000;
                result_supported_q <= 1'b1;
                result_is_exception_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[6],
                  event_kind_i == EVENT_TLB_I_MISS ? 13'h1000 :
                    (event_kind_i == EVENT_TLB_D_LOAD ? 13'h1100 :
                                                       13'h1200));
              end
            end
            EVENT_RFI: begin
              if (!rfi_pending_exception_i) begin
                if (msr_q[14]) begin
                  // RFI in problem state is itself a privileged instruction
                  // program exception; use the caller's faulting RFI PC.
                  if (!msr_q[17]) begin
                    srr0_q <= event_pc_i;
                    srr1_q <= exception_srr1(msr_q, SRR1_PROGRAM_PRIV);
                    msr_q <= exception_msr(msr_q);
                    result_supported_q <= 1'b1;
                    result_is_exception_q <= 1'b1;
                    result_target_q <= exception_vector(msr_q[6], 13'h0700);
                  end
                end else begin
                  msr_q <= rfi_msr(msr_q, srr1_q);
                  result_supported_q <= 1'b1;
                  result_is_exception_q <= 1'b0;
                  result_target_q <= {srr0_q[31:2], 2'b00};
                end
              end
            end
            default: begin
              // Unsupported causes complete as an explicit rejection with no
              // architectural state transition.
            end
          endcase
        end
      end

      // synthesis translate_off
      if (event_fire) begin
        assert (!$isunknown({event_kind_i, event_pc_i,
                             rfi_pending_exception_i}))
          else $error("accepted exception event contains unknown fields");
      end
      if (event_fire && (event_kind_i == EVENT_ISI)) begin
        assert (!$isunknown(event_isi_cause_i))
          else $error("accepted ISI event contains an unknown cause");
      end
      if (event_fire && ENABLE_TLB_MISS_EXCEPTIONS &&
          ((event_kind_i == EVENT_TLB_I_MISS) ||
           (event_kind_i == EVENT_TLB_D_LOAD) ||
           (event_kind_i == EVENT_TLB_D_STORE))) begin
        assert (!$isunknown({event_miss_cr0_i, event_miss_key_i,
                             event_miss_way_i}))
          else $error("accepted TLB miss event contains unknown fields");
      end
      if (state_load_fire) begin
        assert (!$isunknown({state_load_enable_i, state_load_msr_i,
                             state_load_srr0_i, state_load_srr1_i}))
          else $error("accepted exception state load contains unknown fields");
      end
      // synthesis translate_on
    end
  end

  // synthesis translate_off
  property held_result_stable;
    @(posedge clk_i) disable iff (!rst_ni)
      result_valid_o && !result_ready_i |=>
        result_valid_o && $stable({result_supported_o,
                                   result_is_exception_o,
                                   result_target_o});
  endproperty
  assert property (held_result_stable)
    else $error("stalled exception result changed or disappeared");
  // synthesis translate_on
endmodule
