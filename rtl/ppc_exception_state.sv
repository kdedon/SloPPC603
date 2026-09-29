// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 603e MSR/SRR0/SRR1 (and 602 ESASRR) state for one caller-selected
// committed-boundary event.
// The caller detects the oldest fault and arbitrates simultaneous causes.
module ppc_exception_state #(
  // Part the build models; the 603 has no SRR1[KEY] (UM C.2).
  parameter ppc_pkg::cpu_variant_e CPU_VARIANT = ppc_pkg::CPU_PID7V_603E,
  parameter logic [31:0] RESET_MSR  = ppc_pkg::MSR_RESET,
  parameter logic [31:0] RESET_SRR0 = 32'b0,
  parameter logic [31:0] RESET_SRR1 = 32'b0,
  parameter bit ENABLE_TLB_MISS_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_MACHINE_CHECK = 1'b0,
  parameter bit ENABLE_DEBUG_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_FULL_DECODE = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        event_valid_i,
  output logic        event_ready_o,
  input  ppc_pkg::exception_event_t event_kind_i,
  input  logic [31:0] event_pc_i,
  // Used only by EVENT_ISI; causes other than protection and guarded reject.
  input  ppc_pkg::fetch_fault_t event_isi_cause_i,
  // Miss-time fields are supplied by the selected oldest accepted request.
  input  logic [3:0]  event_miss_cr0_i,
  input  logic        event_miss_key_i,
  input  logic        event_miss_way_i,
  // 602 esa: the SE bit of the page or block holding the esa.
  input  logic        event_esa_enable_i,

  output logic        result_valid_o,
  input  logic        result_ready_i,
  output logic        result_supported_o,
  output logic [31:0] result_target_o,

  // Atomic committed-state load. An event wins a same-edge collision; the
  // load stalls.
  input  logic        state_load_valid_i,
  output logic        state_load_ready_o,
  // Enables: MSR, SRR0, SRR1, ESASRR.
  input  logic [3:0]  state_load_enable_i,
  input  logic [31:0] state_load_msr_i,
  input  logic [31:0] state_load_srr0_i,
  input  logic [31:0] state_load_srr1_i,
  input  logic [31:0] state_load_esasrr_i,

  output logic [31:0] msr_o,
  output logic [31:0] srr0_o,
  output logic [31:0] srr1_o,
  output logic [31:0] esasrr_o
);
  import ppc_pkg::*;
  localparam cpu_cfg_t CPU_CFG = cpu_cfg(CPU_VARIANT);

  // Program exception causes: manual bit 12 illegal and bit 13 privileged.
  localparam logic [31:0] SRR1_PROGRAM_ILLEGAL = 32'h0008_0000;
  localparam logic [31:0] SRR1_PROGRAM_PRIV    = 32'h0004_0000;
  localparam logic [31:0] SRR1_PROGRAM_TRAP    = 32'h0002_0000;
  localparam logic [31:0] MSR_MASK = msr_implemented(CPU_CFG.has_602_ext);
  // Full decode has no FPU: MSR[FP] never sets, as on the EC603e (UM 4.5.8).
  localparam logic [31:0] MSR_STORED_MASK = ENABLE_FULL_DECODE ?
    (MSR_MASK & ~(32'd1 << MSR_FP)) : MSR_MASK;
  // MSR bits an exception saves in SRR1; never the 602 AP and SA.
  localparam logic [31:0] SRR1_SAVE_MASK = MSR_SRR1_MASK & ~MSR_602_MASK;
  // Machine check causes: manual bit 12 MCP, bit 13 TEA.
  localparam logic [31:0] SRR1_MACHINE_CHECK_TEA = 32'h0004_0000;
  localparam logic [31:0] SRR1_MACHINE_CHECK_MCP = 32'h0008_0000;
  localparam logic [31:0] SRR1_MACHINE_CHECK_APE = 32'h0001_0000;

  logic [31:0] msr_q, srr0_q, srr1_q, esasrr_q;
  logic result_valid_q, result_supported_q;
  logic [31:0] result_target_q;
  logic slot_available, event_fire, state_load_fire;

  assign msr_o = msr_q;
  assign srr0_o = srr0_q;
  assign srr1_o = srr1_q;
  assign esasrr_o = esasrr_q;
  // Reset immediately withdraws an old response from the external handshake;
  // the registered state itself resets on the next active clock edge.
  assign result_valid_o = rst_ni && result_valid_q;
  assign result_supported_o = result_supported_q;
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
    return (old_msr & SRR1_SAVE_MASK) | cause;
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

  // UM Table 4-7: every entry clears TGPR, whatever its old value; only the
  // TLB misses set it again.
  function automatic logic [31:0] exception_msr(input logic [31:0] old_msr);
    logic [31:0] next_msr;
    begin
      next_msr = old_msr;
      next_msr[MSR_AP] = 1'b0;
      next_msr[MSR_SA] = 1'b0;
      next_msr[MSR_POW] = 1'b0;
      next_msr[MSR_TGPR] = 1'b0;
      next_msr[MSR_EE] = 1'b0;
      next_msr[MSR_PR] = 1'b0;
      next_msr[MSR_FP] = 1'b0;
      next_msr[11:8] = 4'b0;  // FE0, SE, BE, FE1
      next_msr[MSR_IR] = 1'b0;
      next_msr[MSR_DR] = 1'b0;
      next_msr[MSR_RI] = 1'b0;
      next_msr[MSR_LE] = old_msr[MSR_ILE];
      return next_msr & MSR_MASK;
    end
  endfunction

  function automatic logic [31:0] exception_vector(
    input logic ip,
    input logic [12:0] offset
  );
    return (ip ? 32'hfff0_0000 : 32'h0000_0000) |
           {19'b0, offset};
  endfunction

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      msr_q <= RESET_MSR & MSR_MASK;
      srr0_q <= RESET_SRR0;
      srr1_q <= RESET_SRR1;
      esasrr_q <= 32'b0;
      result_valid_q <= 1'b0;
      result_supported_q <= 1'b0;
      result_target_q <= 32'b0;
    end else begin
      if (result_valid_q && result_ready_i) begin
        result_valid_q <= 1'b0;
      end

      if (state_load_fire) begin
        if (state_load_enable_i[0])
          msr_q <= state_load_msr_i & MSR_STORED_MASK;
        if (state_load_enable_i[1]) srr0_q <= state_load_srr0_i;
        if (state_load_enable_i[2]) srr1_q <= state_load_srr1_i;
        if (state_load_enable_i[3] && CPU_CFG.has_602_ext)
          esasrr_q <= state_load_esasrr_i & ESASRR_WMASK;
      end

      if (event_fire) begin
        result_valid_q <= 1'b1;
        result_supported_q <= 1'b0;
        result_target_q <= 32'b0;

        // All supported event PCs are committed instruction boundaries.
        if (event_pc_i[1:0] == 2'b00) begin
          unique case (event_kind_i)
            EVENT_SC: begin
              srr0_q <= event_pc_i + 32'd4;
              srr1_q <= exception_srr1(msr_q, 32'b0);
              msr_q <= exception_msr(msr_q);
              result_supported_q <= 1'b1;
              result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0c00);
            end
            EVENT_PROGRAM_ILLEGAL: begin
              srr0_q <= event_pc_i;
              srr1_q <= exception_srr1(msr_q, SRR1_PROGRAM_ILLEGAL);
              msr_q <= exception_msr(msr_q);
              result_supported_q <= 1'b1;
              result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0700);
            end
            EVENT_PROGRAM_PRIV: begin
              srr0_q <= event_pc_i;
              srr1_q <= exception_srr1(msr_q, SRR1_PROGRAM_PRIV);
              msr_q <= exception_msr(msr_q);
              result_supported_q <= 1'b1;
              result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0700);
            end
            EVENT_PROGRAM_TRAP: begin
              srr0_q <= event_pc_i;
              srr1_q <= exception_srr1(msr_q, SRR1_PROGRAM_TRAP);
              msr_q <= exception_msr(msr_q);
              result_supported_q <= 1'b1;
              result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0700);
            end
            EVENT_FP_UNAVAILABLE: begin
              // PEM Table 6-15: SRR1 1-4 and 10-15 clear.
              srr0_q <= event_pc_i;
              srr1_q <= exception_srr1(msr_q, 32'b0);
              msr_q <= exception_msr(msr_q);
              result_supported_q <= 1'b1;
              result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0800);
            end
            EVENT_ISI: begin
              if (((event_isi_cause_i == FETCH_ISI_PROTECTION) ||
                                (event_isi_cause_i == FETCH_ISI_GUARDED))) begin
                srr0_q <= event_pc_i;
                // PEM Table 6-10: manual bit 4 protection, bit 3 guarded.
                srr1_q <= exception_srr1(msr_q,
                  event_isi_cause_i == FETCH_ISI_PROTECTION ? 32'h0800_0000 :
                                                             32'h1000_0000);
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0400);
              end
            end
            EVENT_DECREMENTER: begin
              if (msr_q[MSR_EE]) begin
                srr0_q <= event_pc_i;
                // DEC saves the full SRR1 MSR subset; external saves the low half.
                srr1_q <= msr_q & SRR1_SAVE_MASK;
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0900);
              end
            end
            EVENT_EXTERNAL: begin
              if (msr_q[MSR_EE]) begin
                srr0_q <= event_pc_i;
                // UM Table 4-12: next instruction EA and low-half MSR only.
                srr1_q <= msr_q & 32'h0000_ffff;
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0500);
              end
            end
            EVENT_ALIGNMENT: begin
              srr0_q <= event_pc_i;
              // Table 4-13 explicitly clears manual bits 0..15.
              srr1_q <= msr_q & 32'h0000_ffff;
              msr_q <= exception_msr(msr_q);
              result_supported_q <= 1'b1;
              result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0600);
            end
            EVENT_DSI: begin
              srr0_q <= event_pc_i;
              // UM Table 4-11 clears manual SRR1 bits 0..15.
              srr1_q <= msr_q & 32'h0000_ffff;
              msr_q <= exception_msr(msr_q);
              result_supported_q <= 1'b1;
              result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0300);
            end
            EVENT_TLB_I_MISS, EVENT_TLB_D_LOAD,
            EVENT_TLB_D_STORE: begin
              if (ENABLE_TLB_MISS_EXCEPTIONS) begin
                srr0_q <= event_pc_i;
                srr1_q <= miss_srr1(msr_q[26:22] & SRR1_SAVE_MASK[26:22],
                  msr_q[15:0], event_miss_cr0_i,
                  CPU_CFG.has_srr1_key && event_miss_key_i,
                  event_kind_i == EVENT_TLB_I_MISS,
                  event_miss_way_i, event_kind_i == EVENT_TLB_D_STORE);
                // Table 4-16: miss entry uses the ordinary exception state
                // changes plus the separate temporary r0..r3 bank.
                msr_q <= exception_msr(msr_q) | (32'd1 << MSR_TGPR);
                result_supported_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[MSR_IP],
                  event_kind_i == EVENT_TLB_I_MISS ? 13'h1000 :
                    (event_kind_i == EVENT_TLB_D_LOAD ? 13'h1100 :
                                                       13'h1200));
              end
            end
            EVENT_MACHINE_CHECK: begin
              // Checkstop (ME=0) belongs to the caller. Clearing ME follows
              // the UM Table 4-10 note that a second TEA checkstops until the
              // handler sets ME.
              if (ENABLE_MACHINE_CHECK && msr_q[MSR_ME]) begin
                srr0_q <= event_pc_i;
                srr1_q <= (msr_q & 32'h0000_ffff) | SRR1_MACHINE_CHECK_TEA;
                msr_q <= exception_msr(msr_q) & ~(32'd1 << MSR_ME);
                result_supported_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0200);
              end
            end
            EVENT_MACHINE_CHECK_PIN, EVENT_MACHINE_CHECK_APE: begin
              // UM Table 4-10: SRR1 bit 12 (MCP) or 15 (APE); ME as for TEA.
              if (msr_q[MSR_ME]) begin
                srr0_q <= event_pc_i;
                srr1_q <= (msr_q & 32'h0000_ffff) |
                  (event_kind_i == EVENT_MACHINE_CHECK_APE ?
                   SRR1_MACHINE_CHECK_APE : SRR1_MACHINE_CHECK_MCP);
                msr_q <= exception_msr(msr_q) & ~(32'd1 << MSR_ME);
                result_supported_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0200);
              end
            end
            EVENT_SOFT_RESET: begin
              // UM Table 4-9: nonmaskable, taken in any state.
              srr0_q <= event_pc_i;
              srr1_q <= msr_q & 32'h0000_ffff;
              msr_q <= exception_msr(msr_q);
              result_supported_q <= 1'b1;
              result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0100);
            end
            EVENT_SMI: begin
              // UM Table 4-19: as external, at 0x1400.
              if (msr_q[MSR_EE] && !msr_q[MSR_TGPR]) begin
                srr0_q <= event_pc_i;
                srr1_q <= msr_q & 32'h0000_ffff;
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[MSR_IP], 13'h1400);
              end
            end
            EVENT_TRACE, EVENT_IABR: begin
              // UM Tables 4-15 and 4-17: manual SRR1 bits 0..15 clear.
              if (ENABLE_DEBUG_EXCEPTIONS) begin
                srr0_q <= event_pc_i;
                srr1_q <= msr_q & 32'h0000_ffff;
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[MSR_IP],
                  event_kind_i == EVENT_TRACE ? 13'h0d00 : 13'h1300);
              end
            end
            EVENT_RFI: begin
              if (msr_q[MSR_PR]) begin
                // RFI in problem state is itself a privileged instruction
                // program exception; use the caller's faulting RFI PC.
                srr0_q <= event_pc_i;
                srr1_q <= exception_srr1(msr_q, SRR1_PROGRAM_PRIV);
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0700);
              end else begin
                msr_q <= rfi_msr(msr_q, srr1_q, MSR_MASK) & MSR_STORED_MASK;
                result_supported_q <= 1'b1;
                result_target_q <= {srr0_q[31:2], 2'b00};
              end
            end
            EVENT_EMULATION_TRAP: begin
              // 602UM Table 4-23. The IBR vector prefix is not modelled.
              if (CPU_CFG.has_602_ext) begin
                srr0_q <= event_pc_i;
                srr1_q <= msr_q & 32'h0000_ffff;
                msr_q <= exception_msr(msr_q);
                result_supported_q <= 1'b1;
                result_target_q <= exception_vector(msr_q[MSR_IP], 13'h1600);
              end
            end
            EVENT_ESA, EVENT_DSA: begin
              // 602UM 2.3.7: esa saves PR, AP, SA, EE in ESASRR and enters
              // supervisor access; dsa restores them. esa with SA set or off
              // an SE page, and dsa with SA clear, take a program exception;
              // the manual names no SRR1 cause, the privileged one is used.
              if (CPU_CFG.has_602_ext) begin
                result_supported_q <= 1'b1;
                if ((event_kind_i == EVENT_ESA) ?
                    (msr_q[MSR_SA] || !event_esa_enable_i) : !msr_q[MSR_SA]) begin
                  srr0_q <= event_pc_i;
                  srr1_q <= exception_srr1(msr_q, SRR1_PROGRAM_PRIV);
                  msr_q <= exception_msr(msr_q);
                  result_target_q <= exception_vector(msr_q[MSR_IP], 13'h0700);
                end else begin
                  if (event_kind_i == EVENT_ESA) begin
                    esasrr_q <= {28'b0, msr_q[MSR_PR], msr_q[MSR_AP],
                                 msr_q[MSR_SA], msr_q[MSR_EE]};
                    msr_q[MSR_PR] <= 1'b0;
                    msr_q[MSR_AP] <= 1'b0;
                    msr_q[MSR_SA] <= 1'b1;
                    msr_q[MSR_EE] <= 1'b0;
                  end else begin
                    msr_q[MSR_PR] <= esasrr_q[3];
                    msr_q[MSR_AP] <= esasrr_q[2];
                    msr_q[MSR_SA] <= esasrr_q[1];
                    msr_q[MSR_EE] <= esasrr_q[0];
                  end
                  result_target_q <= event_pc_i + 32'd4;
                end
              end
            end
            default: begin
              // Unsupported causes reject and leave state unchanged.
            end
          endcase
        end
      end

      // synthesis translate_off
      if (event_fire) begin
        assert (!$isunknown({event_kind_i, event_pc_i}))
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
                             state_load_srr0_i, state_load_srr1_i,
                             state_load_esasrr_i}))
          else $error("accepted exception state load contains unknown fields");
      end
      // synthesis translate_on
    end
  end

  // synthesis translate_off
  property held_result_stable;
    @(posedge clk_i) disable iff (!rst_ni)
      result_valid_o && !result_ready_i |=>
        result_valid_o && $stable({result_supported_o, result_target_o});
  endproperty
  assert property (held_result_stable)
    else $error("stalled exception result changed or disappeared");
  // synthesis translate_on
endmodule
`default_nettype wire
