// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Decodes the implemented ISA. With ENABLE_FULL_DECODE every other encoding
// takes the illegal-instruction program exception; otherwise it produces a
// diagnostic.
module ppc_decode #(
  parameter bit ENABLE_SUPERVISOR_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_LIVE_CONTEXT = 1'b0,
  parameter bit ENABLE_TIMERS = 1'b0,
  parameter bit ENABLE_RUNTIME_BAT = 1'b0,
  parameter bit ENABLE_SEGMENT_REGISTERS = 1'b0,
  parameter bit ENABLE_TLB_INVALIDATE = 1'b0,
  parameter bit ENABLE_TLB_LOAD = 1'b0,
  parameter bit ENABLE_SDR1 = 1'b0,
  parameter bit ENABLE_TLB_MISS_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_CACHE_INSTRUCTIONS = 1'b0,
  // Cache-block instructions, lwarx/stwcx. and sync go to a data cache.
  parameter bit ENABLE_DATA_CACHE = 1'b0,
  parameter bit ENABLE_BYTE_REVERSE = 1'b0,
  parameter bit ENABLE_MULTIPLE_STRING = 1'b0,
  parameter bit ENABLE_RESERVATION = 1'b0,
  parameter bit ENABLE_DEBUG_EXCEPTIONS = 1'b0,
  // Illegal and invalid forms, traps, FP class, PVR/HID0/HID1/EAR and
  // eciwx/ecowx.
  parameter bit ENABLE_FULL_DECODE = 1'b0,
  // Part the build models; HID1 and EAR exist only where cpu_cfg() says so.
  parameter ppc_pkg::cpu_variant_e CPU_VARIANT = ppc_pkg::CPU_PID7V_603E
) (
  input logic [31:0] insn_i,
  output ppc_pkg::uop_t uop_o
);
  import ppc_pkg::*;
  localparam cpu_cfg_t CPU_CFG = cpu_cfg(CPU_VARIANT);

  function automatic logic [31:0] make_rotate_mask(
    input logic [4:0] mb,
    input logic [4:0] me
  );
    logic [31:0] mask;
    mask = '0;
    for (int ppc_bit = 0; ppc_bit < 32; ppc_bit++) begin
      if ((mb <= me && ppc_bit >= int'(mb) && ppc_bit <= int'(me)) ||
          (mb > me && (ppc_bit >= int'(mb) || ppc_bit <= int'(me))))
        mask[31-ppc_bit] = 1'b1;
    end
    return mask;
  endfunction

  function automatic logic valid_bo(input logic [4:0] bo);
    case (bo)
      5'd0, 5'd1, 5'd2, 5'd3, 5'd4, 5'd5,
      5'd8, 5'd9, 5'd10, 5'd11, 5'd12, 5'd13,
      5'd16, 5'd17, 5'd18, 5'd19, 5'd20: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  // UM Table A-1: 603e floating-point arithmetic, move and FPSCR forms.
  // fsqrt/fsqrts (A-form XO 22) are unimplemented optional instructions.
  function automatic logic fp_a_form(input logic [5:0] primary,
                                     input logic [4:0] xo);
    case (xo)
      5'd18, 5'd20, 5'd21, 5'd25, 5'd28, 5'd29, 5'd30, 5'd31: return 1'b1;
      5'd24: return primary == 6'd59;  // fres
      5'd23, 5'd26: return primary == 6'd63;  // fsel, frsqrte
      default: return 1'b0;
    endcase
  endfunction
  function automatic logic fp_x_form(input logic [9:0] xo);
    case (xo)
      10'd0, 10'd12, 10'd14, 10'd15, 10'd32, 10'd38, 10'd40, 10'd64,
      10'd70, 10'd72, 10'd134, 10'd136, 10'd264, 10'd583, 10'd711:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction
  // Opcode-31 FP loads/stores and stfiwx.
  function automatic logic fp_indexed(input logic [9:0] xo);
    case (xo)
      10'd535, 10'd567, 10'd599, 10'd631, 10'd663, 10'd695, 10'd727,
      10'd759, 10'd983: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  logic spr_form_privileged;

  always_comb begin
    spr_form_privileged = 1'b0;
    uop_o = '0;
    uop_o.illegal = 1'b1;
    uop_o.src_a = insn_i[20:16];
    uop_o.src_b = insn_i[15:11];
    uop_o.src_c = insn_i[25:21];
    uop_o.dst = insn_i[25:21];

    case (insn_i[31:26])
      6'd0: begin
        // The all-zero word is architecturally illegal.
        if (ENABLE_SUPERVISOR_EXCEPTIONS && (insn_i == 32'b0)) begin
          uop_o.illegal = 1'b0;
          uop_o.special_op = SPECIAL_PROGRAM_ILLEGAL;
        end
      end
      6'd3: begin
        if (ENABLE_FULL_DECODE) begin
          uop_o.illegal = 1'b0;
          uop_o.special_op = SPECIAL_TRAP;
          uop_o.branch_bo = insn_i[25:21];
          uop_o.use_imm = 1'b1;
          uop_o.imm = {{16{insn_i[15]}}, insn_i[15:0]};
        end
      end
      6'd48, 6'd49, 6'd50, 6'd51, 6'd52, 6'd53, 6'd54, 6'd55: begin
        // FP loads/stores are classified by opcode alone (UM 2.3.4.3.9).
        if (ENABLE_FULL_DECODE) begin
          uop_o.illegal = 1'b0;
          uop_o.special_op = SPECIAL_FPU;
        end
      end
      6'd59, 6'd63: begin
        // Reserved fields of FP forms are not checked: the class follows
        // the primary and extended opcode (UM 2.3.1).
        if (ENABLE_FULL_DECODE &&
            (fp_a_form(insn_i[31:26], insn_i[5:1]) ||
             ((insn_i[31:26] == 6'd63) && fp_x_form(insn_i[10:1])))) begin
          uop_o.illegal = 1'b0;
          uop_o.special_op = SPECIAL_FPU;
        end
      end
      6'd7: begin
        uop_o.illegal = 1'b0;
        uop_o.gpr_write = 1'b1;
        // Keep MULLI distinct internally because Table 6-4 gives it a
        // shorter reservation class than register MULLW.
        uop_o.op = ALU_MULLI;
        uop_o.use_imm = 1'b1;
        uop_o.imm = {{16{insn_i[15]}}, insn_i[15:0]};
      end
      6'd8: begin
        uop_o.illegal = 1'b0;
        uop_o.gpr_write = 1'b1;
        uop_o.op = ALU_ADD;
        uop_o.invert_a = 1'b1;
        uop_o.carry_in = CARRY_ONE;
        uop_o.use_imm = 1'b1;
        uop_o.imm = {{16{insn_i[15]}}, insn_i[15:0]};
        uop_o.needs_flags = 1'b1;
        uop_o.write_ca = 1'b1;
      end
      6'd12, 6'd13: begin
        uop_o.illegal = 1'b0;
        uop_o.gpr_write = 1'b1;
        uop_o.op = ALU_ADD;
        uop_o.use_imm = 1'b1;
        uop_o.imm = {{16{insn_i[15]}}, insn_i[15:0]};
        uop_o.needs_flags = 1'b1;
        uop_o.write_ca = 1'b1;
        // Record is selected by primary opcode, not an immediate-data bit.
        uop_o.read_so = insn_i[26];
        uop_o.write_cr_field = insn_i[26];
      end
      6'd14, 6'd15: begin
        uop_o.illegal = 1'b0;
        uop_o.gpr_write = 1'b1;
        uop_o.op = ALU_ADD;
        uop_o.zero_a = (insn_i[20:16] == 0);
        uop_o.use_imm = 1'b1;
        uop_o.imm = (insn_i[31:26] == 6'd15) ?
          {insn_i[15:0], 16'b0} : {{16{insn_i[15]}}, insn_i[15:0]};
      end
      6'd28, 6'd29: begin
        uop_o.illegal = 1'b0;
        uop_o.gpr_write = 1'b1;
        uop_o.op = ALU_AND;
        uop_o.src_a = insn_i[25:21];
        uop_o.dst = insn_i[20:16];
        uop_o.use_imm = 1'b1;
        uop_o.imm = insn_i[26] ? {insn_i[15:0], 16'b0} :
                                 {16'b0, insn_i[15:0]};
        uop_o.needs_flags = 1'b1;
        uop_o.read_so = 1'b1;
        uop_o.write_cr_field = 1'b1;
      end
      6'd24, 6'd25, 6'd26, 6'd27: begin
        uop_o.illegal = 1'b0;
        uop_o.gpr_write = 1'b1;
        uop_o.op = insn_i[27] ? ALU_XOR : ALU_OR;
        uop_o.src_a = insn_i[25:21];
        uop_o.dst = insn_i[20:16];
        uop_o.use_imm = 1'b1;
        uop_o.imm = insn_i[26] ? {insn_i[15:0], 16'b0} :
                                 {16'b0, insn_i[15:0]};
      end
      6'd20: begin
        uop_o.illegal = 1'b0;
        uop_o.gpr_write = 1'b1;
        uop_o.op = ALU_RLWIMI;
        uop_o.src_a = insn_i[25:21];
        uop_o.src_b = insn_i[20:16];
        uop_o.dst = insn_i[20:16];
        uop_o.mask = make_rotate_mask(insn_i[10:6], insn_i[5:1]);
        uop_o.shift = insn_i[15:11];
        uop_o.read_so = insn_i[0];
        uop_o.needs_flags = insn_i[0];
        uop_o.write_cr_field = insn_i[0];
      end
      6'd21, 6'd23: begin
        uop_o.illegal = 1'b0;
        uop_o.gpr_write = 1'b1;
        uop_o.op = ALU_ROTATE;
        uop_o.src_a = insn_i[25:21];
        uop_o.dst = insn_i[20:16];
        uop_o.mask = make_rotate_mask(insn_i[10:6], insn_i[5:1]);
        uop_o.read_so = insn_i[0];
        uop_o.needs_flags = insn_i[0];
        uop_o.write_cr_field = insn_i[0];
        if (insn_i[31:26] == 6'd21) begin
          uop_o.use_imm = 1'b1;
          uop_o.imm = {27'b0, insn_i[15:11]};
        end
      end
      6'd18: begin
        uop_o.illegal = 1'b0;
        uop_o.special_op = SPECIAL_B;
        uop_o.branch_disp = {{6{insn_i[25]}}, insn_i[25:2], 2'b0};
        uop_o.branch_aa = insn_i[1];
        uop_o.branch_lk = insn_i[0];
      end
      6'd16: begin
        if (valid_bo(insn_i[25:21])) begin
          uop_o.illegal = 1'b0;
          uop_o.special_op = SPECIAL_BC;
          uop_o.branch_disp = {{16{insn_i[15]}}, insn_i[15:2], 2'b0};
          uop_o.branch_aa = insn_i[1];
          uop_o.branch_lk = insn_i[0];
          uop_o.branch_bo = insn_i[25:21];
          uop_o.branch_bi = insn_i[20:16];
        end
      end
      6'd17: begin
        // SC form: every field is fixed in the selected 32-bit form.
        if (ENABLE_SUPERVISOR_EXCEPTIONS &&
            (insn_i == 32'h4400_0002)) begin
          uop_o.illegal = 1'b0;
          uop_o.special_op = SPECIAL_SC;
        end
      end
      6'd19: begin
        case (insn_i[10:1])
          10'd0: begin
            if (!insn_i[0] && (insn_i[22:21] == 0) &&
                (insn_i[17:16] == 0) && (insn_i[15:11] == 0)) begin
              uop_o.illegal = 1'b0;
              uop_o.special_op = SPECIAL_MCRF;
              uop_o.needs_flags = 1'b1;
              uop_o.write_cr_field = 1'b1;
              uop_o.cr_field = insn_i[25:23];
              uop_o.cr_source_field = insn_i[20:18];
            end
          end
          10'd16, 10'd528: begin
            if ((insn_i[15:11] == 0) && valid_bo(insn_i[25:21]) &&
                ((insn_i[10:1] == 10'd16) || insn_i[23])) begin
              uop_o.illegal = 1'b0;
              uop_o.special_op = (insn_i[10:1] == 10'd16) ?
                                  SPECIAL_BCLR : SPECIAL_BCCTR;
              uop_o.branch_lk = insn_i[0];
              uop_o.branch_bo = insn_i[25:21];
              uop_o.branch_bi = insn_i[20:16];
            end
          end
          10'd50: begin
            // RFI has no operand fields and bit 31 (HDL bit 0) is reserved.
            if (ENABLE_SUPERVISOR_EXCEPTIONS &&
                (insn_i == 32'h4c00_0064)) begin
              uop_o.illegal = 1'b0;
              uop_o.special_op = SPECIAL_RFI;
            end
          end
          10'd150: begin
            // ISYNC is an operand-free XL-form with every non-opcode bit fixed.
            if (ENABLE_SUPERVISOR_EXCEPTIONS &&
                (insn_i == 32'h4c00_012c)) begin
              uop_o.illegal = 1'b0;
              uop_o.special_op = SPECIAL_ISYNC;
            end
          end
          10'd257, 10'd129, 10'd289, 10'd225,
          10'd33, 10'd449, 10'd417, 10'd193: begin
            if (!insn_i[0]) begin
              uop_o.illegal = 1'b0;
              uop_o.special_op = SPECIAL_CR_LOGIC;
              uop_o.needs_flags = 1'b1;
              uop_o.write_cr_bit = 1'b1;
              uop_o.cr_bit = insn_i[25:21];
              uop_o.cr_bit_a = insn_i[20:16];
              uop_o.cr_bit_b = insn_i[15:11];
              case (insn_i[10:1])
                10'd257: uop_o.cr_logic = CR_LOGIC_AND;
                10'd129: uop_o.cr_logic = CR_LOGIC_ANDC;
                10'd289: uop_o.cr_logic = CR_LOGIC_EQV;
                10'd225: uop_o.cr_logic = CR_LOGIC_NAND;
                10'd33: uop_o.cr_logic = CR_LOGIC_NOR;
                10'd449: uop_o.cr_logic = CR_LOGIC_OR;
                10'd417: uop_o.cr_logic = CR_LOGIC_ORC;
                10'd193: uop_o.cr_logic = CR_LOGIC_XOR;
                default: ;
              endcase
            end
          end
          default: ;
        endcase
      end
      6'd10, 6'd11: begin
        if (!insn_i[22] && !insn_i[21]) begin
          uop_o.illegal = 1'b0;
          uop_o.op = (insn_i[31:26] == 6'd10) ? ALU_CMPL : ALU_CMP;
          uop_o.invert_a = 1'b1;
          uop_o.carry_in = CARRY_ONE;
          uop_o.src_a = insn_i[20:16];
          uop_o.use_imm = 1'b1;
          uop_o.imm = (insn_i[31:26] == 6'd10) ?
            {16'b0, insn_i[15:0]} : {{16{insn_i[15]}}, insn_i[15:0]};
          uop_o.read_so = 1'b1;
          uop_o.needs_flags = 1'b1;
          uop_o.write_cr_field = 1'b1;
          uop_o.cr_field = insn_i[25:23];
        end
      end
      6'd32, 6'd33, 6'd34, 6'd35, 6'd36, 6'd37, 6'd38,
      6'd39, 6'd40, 6'd41, 6'd42, 6'd43, 6'd44, 6'd45: begin
        logic is_store, is_update, valid_update;
        is_store = (insn_i[31:26] == 6'd36) ||
                   (insn_i[31:26] == 6'd37) ||
                   (insn_i[31:26] == 6'd38) ||
                   (insn_i[31:26] == 6'd39) ||
                   (insn_i[31:26] == 6'd44) ||
                   (insn_i[31:26] == 6'd45);
        is_update = insn_i[26];
        valid_update = !is_update ||
          ((insn_i[20:16] != 0) &&
           (is_store || (insn_i[20:16] != insn_i[25:21])));
        if (valid_update) begin
          uop_o.illegal = 1'b0;
          uop_o.special_op = is_store ? SPECIAL_STORE : SPECIAL_LOAD;
          uop_o.gpr_write = !is_store;
          uop_o.mem_update = is_update;
          uop_o.zero_a = !is_update && (insn_i[20:16] == 0);
          uop_o.use_imm = 1'b1;
          uop_o.imm = {{16{insn_i[15]}}, insn_i[15:0]};
          case (insn_i[31:26])
            6'd34, 6'd35, 6'd38, 6'd39: uop_o.mem_size = MEM_BYTE;
            6'd40, 6'd41, 6'd42, 6'd43,
            6'd44, 6'd45: uop_o.mem_size = MEM_HALF;
            default: uop_o.mem_size = MEM_WORD;
          endcase
          uop_o.mem_signed = (insn_i[31:26] == 6'd42) ||
                              (insn_i[31:26] == 6'd43);
        end
      end
      6'd46, 6'd47: begin
        // lmw with rA in the loaded range (rA >= rD, including rA = rD = 0)
        // is an invalid form (UM 2.3.4.3.6).
        if (ENABLE_MULTIPLE_STRING && ENABLE_SUPERVISOR_EXCEPTIONS &&
            (insn_i[26] || (insn_i[20:16] < insn_i[25:21]))) begin
          uop_o.illegal = 1'b0;
          uop_o.special_op = insn_i[26] ? SPECIAL_STORE : SPECIAL_LOAD;
          uop_o.gpr_write = !insn_i[26];
          uop_o.zero_a = insn_i[20:16] == 5'b0;
          uop_o.use_imm = 1'b1;
          uop_o.imm = {{16{insn_i[15]}}, insn_i[15:0]};
          uop_o.mem_size = MEM_WORD;
          uop_o.mem_left = 1'b1;
          uop_o.mem_seq = SEQ_MULTIPLE;
        end
      end
      6'd31: begin
        if ((insn_i[9:1] == 9'd266) || (insn_i[9:1] == 9'd10) ||
            (insn_i[9:1] == 9'd138) || (insn_i[9:1] == 9'd234) ||
            (insn_i[9:1] == 9'd202) || (insn_i[9:1] == 9'd40) ||
            (insn_i[9:1] == 9'd104) || (insn_i[9:1] == 9'd8) ||
            (insn_i[9:1] == 9'd136) || (insn_i[9:1] == 9'd232) ||
            (insn_i[9:1] == 9'd200) || (insn_i[9:1] == 9'd235) ||
            (insn_i[9:1] == 9'd459) || (insn_i[9:1] == 9'd491)) begin
          if (((insn_i[9:1] != 9'd234) &&
               (insn_i[9:1] != 9'd202) &&
               (insn_i[9:1] != 9'd104) &&
               (insn_i[9:1] != 9'd232) &&
               (insn_i[9:1] != 9'd200)) || (insn_i[15:11] == 0)) begin
            uop_o.illegal = 1'b0;
            uop_o.gpr_write = 1'b1;
            case (insn_i[9:1])
              9'd235: uop_o.op = ALU_MULLW;
              9'd459: uop_o.op = ALU_DIVWU;
              9'd491: uop_o.op = ALU_DIVW;
              default: uop_o.op = ALU_ADD;
            endcase
            uop_o.read_ca = (insn_i[9:1] == 9'd138) ||
                             (insn_i[9:1] == 9'd136) ||
                             (insn_i[9:1] == 9'd232) ||
                             (insn_i[9:1] == 9'd200) ||
                             (insn_i[9:1] == 9'd234) ||
                             (insn_i[9:1] == 9'd202);
            // subf* forms add ~rA; subf/neg/subfc add one, extended forms CA.
            uop_o.invert_a = (insn_i[9:1] == 9'd40) ||
                              (insn_i[9:1] == 9'd104) ||
                              (insn_i[9:1] == 9'd8) ||
                              (insn_i[9:1] == 9'd136) ||
                              (insn_i[9:1] == 9'd232) ||
                              (insn_i[9:1] == 9'd200);
            uop_o.carry_in = uop_o.read_ca ? CARRY_CA :
                             (uop_o.invert_a ? CARRY_ONE : CARRY_ZERO);
            uop_o.read_so = insn_i[10] || insn_i[0];
            uop_o.write_ca = (insn_i[9:1] == 9'd8) ||
                              (insn_i[9:1] == 9'd136) ||
                              (insn_i[9:1] == 9'd232) ||
                              (insn_i[9:1] == 9'd200) ||
                              (insn_i[9:1] == 9'd10) ||
                              (insn_i[9:1] == 9'd138) ||
                              (insn_i[9:1] == 9'd234) ||
                              (insn_i[9:1] == 9'd202);
            uop_o.write_ov_so = insn_i[10];
            uop_o.write_cr_field = insn_i[0];
            uop_o.needs_flags = uop_o.read_ca || uop_o.read_so ||
                                 uop_o.write_ca;
            if ((insn_i[9:1] == 9'd234) ||
                (insn_i[9:1] == 9'd202) ||
                (insn_i[9:1] == 9'd104) ||
                (insn_i[9:1] == 9'd232) ||
                (insn_i[9:1] == 9'd200)) begin
              uop_o.use_imm = 1'b1;
              uop_o.imm = ((insn_i[9:1] == 9'd234) ||
                            (insn_i[9:1] == 9'd232)) ?
                           32'hffff_ffff : 32'b0;
            end
          end
        end else begin
          case (insn_i[10:1])
            10'd4: begin
              if (ENABLE_FULL_DECODE && !insn_i[0]) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = SPECIAL_TRAP;
                uop_o.branch_bo = insn_i[25:21];
              end
            end
            10'd310, 10'd438: begin
              // eciwx/ecowx: word access, EA = (rA|0) + rB, Rc reserved.
              // Parts without EAR lack them (602UM 2.3.7).
              if (ENABLE_FULL_DECODE && CPU_CFG.has_ear && !insn_i[0]) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = insn_i[8] ? SPECIAL_STORE : SPECIAL_LOAD;
                uop_o.gpr_write = !insn_i[8];
                uop_o.zero_a = insn_i[20:16] == 5'b0;
                uop_o.mem_size = MEM_WORD;
                uop_o.mem_external = 1'b1;
              end
            end
            10'd535, 10'd567, 10'd599, 10'd631, 10'd663, 10'd695, 10'd727,
            10'd759, 10'd983: begin
              if (ENABLE_FULL_DECODE && fp_indexed(insn_i[10:1])) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = SPECIAL_FPU;
              end
            end
            10'd75, 10'd11: begin
              uop_o.illegal = 1'b0;
              uop_o.gpr_write = 1'b1;
              uop_o.op = (insn_i[10:1] == 10'd75) ?
                          ALU_MULHW : ALU_MULHWU;
              uop_o.read_so = insn_i[0];
              uop_o.needs_flags = insn_i[0];
              uop_o.write_cr_field = insn_i[0];
            end
            10'd512: begin
              if (!insn_i[0] && (insn_i[22:21] == 0) &&
                  (insn_i[20:11] == 0)) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = SPECIAL_MCRXR;
                uop_o.needs_flags = 1'b1;
                uop_o.read_ca = 1'b1;
                uop_o.read_so = 1'b1;
                uop_o.write_ca = 1'b1;
                uop_o.write_ov_so = 1'b1;
                uop_o.write_cr_field = 1'b1;
                uop_o.cr_field = insn_i[25:23];
              end
            end
            10'd19: begin
              if (!insn_i[0] && (insn_i[20:11] == 0)) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = SPECIAL_MFCR;
                uop_o.gpr_write = 1'b1;
              end
            end
            10'd146: begin
              if (ENABLE_SUPERVISOR_EXCEPTIONS && ENABLE_LIVE_CONTEXT &&
                  !insn_i[0] && (insn_i[20:11] == 0)) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = SPECIAL_MTMSR;
                uop_o.src_a = insn_i[25:21];
              end
            end
            10'd83: begin
              if (ENABLE_SUPERVISOR_EXCEPTIONS && !insn_i[0] &&
                  (insn_i[20:11] == 0)) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = SPECIAL_MFMSR;
                uop_o.gpr_write = 1'b1;
              end
            end
            10'd598, 10'd854: begin
              // The selected 603e SYNC/EIEIO forms have no operands or hint
              // fields. Require the complete fixed instruction word.
              if (ENABLE_SUPERVISOR_EXCEPTIONS &&
                  (((insn_i[10:1] == 10'd598) &&
                    ((insn_i == 32'h7c00_04ac) ||
                     // Later architecture levels define L (bits 9-10) as
                     // weaker forms of sync; a full sync satisfies them.
                     (ENABLE_FULL_DECODE &&
                      ((insn_i & ~32'h0060_0000) == 32'h7c00_04ac)))) ||
                   ((insn_i[10:1] == 10'd854) &&
                    (insn_i == 32'h7c00_06ac)))) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = (insn_i[10:1] == 10'd598) ?
                                    SPECIAL_SYNC : SPECIAL_EIEIO;
              end
            end
            10'd144: begin
              if (!insn_i[0] && !insn_i[20] && !insn_i[11]) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = SPECIAL_MTCRF;
                uop_o.src_a = insn_i[25:21];
                uop_o.needs_flags = 1'b1;
                uop_o.write_cr_fields = 1'b1;
                uop_o.cr_mask = insn_i[19:12];
              end
            end
            10'd26, 10'd954, 10'd922: begin
              // X-form bits 16:20 (HDL 15:11) are reserved, not a source.
              if (insn_i[15:11] == 5'b0) begin
                uop_o.illegal = 1'b0;
                uop_o.gpr_write = 1'b1;
                case (insn_i[10:1])
                  10'd26: uop_o.op = ALU_CNTLZW;
                  10'd954: uop_o.op = ALU_EXTSB;
                  default: uop_o.op = ALU_EXTSH;
                endcase
                uop_o.src_a = insn_i[25:21];
                uop_o.dst = insn_i[20:16];
                uop_o.use_imm = 1'b1;
                uop_o.imm = 32'b0;
                uop_o.read_so = insn_i[0];
                uop_o.needs_flags = insn_i[0];
                uop_o.write_cr_field = insn_i[0];
              end
            end
            10'd792, 10'd824: begin
              uop_o.illegal = 1'b0;
              uop_o.gpr_write = 1'b1;
              uop_o.op = ALU_SRAW;
              uop_o.src_a = insn_i[25:21];
              uop_o.dst = insn_i[20:16];
              uop_o.read_so = insn_i[0];
              uop_o.needs_flags = 1'b1;
              uop_o.write_ca = 1'b1;
              uop_o.write_cr_field = insn_i[0];
              if (insn_i[10:1] == 10'd824) begin
                uop_o.use_imm = 1'b1;
                uop_o.imm = {27'b0, insn_i[15:11]};
              end
            end
            10'd24, 10'd536: begin
              uop_o.illegal = 1'b0;
              uop_o.gpr_write = 1'b1;
              uop_o.op = (insn_i[10:1] == 10'd24) ? ALU_SLW : ALU_SRW;
              uop_o.src_a = insn_i[25:21];
              uop_o.dst = insn_i[20:16];
              uop_o.read_so = insn_i[0];
              uop_o.needs_flags = insn_i[0];
              uop_o.write_cr_field = insn_i[0];
            end
            10'd28, 10'd60, 10'd444, 10'd412,
            10'd316, 10'd476, 10'd124, 10'd284: begin
              uop_o.illegal = 1'b0;
              uop_o.gpr_write = 1'b1;
              uop_o.src_a = insn_i[25:21];
              uop_o.dst = insn_i[20:16];
              uop_o.read_so = insn_i[0];
              uop_o.needs_flags = insn_i[0];
              uop_o.write_cr_field = insn_i[0];
              case (insn_i[10:1])
                10'd28: uop_o.op = ALU_AND;
                10'd60: uop_o.op = ALU_ANDC;
                10'd444: uop_o.op = ALU_OR;
                10'd412: uop_o.op = ALU_ORC;
                10'd316: uop_o.op = ALU_XOR;
                10'd476: uop_o.op = ALU_NAND;
                10'd124: uop_o.op = ALU_NOR;
                10'd284: uop_o.op = ALU_EQV;
                default: ;
              endcase
            end
            10'd0, 10'd32: begin
              if (!insn_i[0] && !insn_i[22] && !insn_i[21]) begin
                uop_o.illegal = 1'b0;
                uop_o.op = (insn_i[10:1] == 10'd0) ? ALU_CMP : ALU_CMPL;
                uop_o.invert_a = 1'b1;
                uop_o.carry_in = CARRY_ONE;
                uop_o.read_so = 1'b1;
                uop_o.needs_flags = 1'b1;
                uop_o.write_cr_field = 1'b1;
                uop_o.cr_field = insn_i[25:23];
              end
            end
            10'd978, 10'd1010: begin
              // 603e TLB load: only rB (HDL bits 15:11) is defined.
              if (ENABLE_TLB_LOAD && !insn_i[0] &&
                  (insn_i[25:16] == 10'b0)) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = (insn_i[10:1] == 10'd978) ?
                                    SPECIAL_TLBLD : SPECIAL_TLBLI;
                uop_o.src_a = 5'b0;
                uop_o.src_b = insn_i[15:11];
              end
            end
            10'd86, 10'd54, 10'd470, 10'd1014, 10'd278, 10'd246, 10'd982: begin
              // Cache control X-forms: EA = (rA|0) + rB; RT and Rc reserved.
              if (ENABLE_CACHE_INSTRUCTIONS && ENABLE_SUPERVISOR_EXCEPTIONS &&
                  !insn_i[0] && (insn_i[25:21] == 5'b0)) begin
                uop_o.illegal = 1'b0;
                uop_o.zero_a = insn_i[20:16] == 5'b0;
                case (insn_i[10:1])
                  10'd278, 10'd246: begin
                    if (ENABLE_DATA_CACHE) begin
                      // dcbt/dcbtst: a load-translated touch; any fault
                      // makes it a no-op.
                      uop_o.special_op = SPECIAL_LOAD;
                      uop_o.mem_size = MEM_BYTE;
                      uop_o.cache_probe = 1'b1;
                      uop_o.cache_op = (insn_i[10:1] == 10'd278) ?
                                       CACHE_OP_DCBT : CACHE_OP_DCBTST;
                    end else begin
                      // dcbt/dcbtst: with no data cache the touch is a no-op.
                      uop_o.op = ALU_OR;
                      uop_o.zero_a = 1'b1;
                      uop_o.use_imm = 1'b1;
                    end
                  end
                  10'd982: uop_o.special_op = SPECIAL_ICBI;
                  default: begin
                    // dcbf/dcbst translate as loads; dcbi/dcbz as stores.
                    uop_o.special_op = ((insn_i[10:1] == 10'd470) ||
                                        (insn_i[10:1] == 10'd1014)) ?
                                       SPECIAL_STORE : SPECIAL_LOAD;
                    uop_o.mem_size = MEM_BYTE;
                    uop_o.cache_probe = 1'b1;
                    uop_o.block_zero = insn_i[10:1] == 10'd1014;
                    uop_o.privileged = insn_i[10:1] == 10'd470;
                    if (ENABLE_DATA_CACHE)
                      case (insn_i[10:1])
                        10'd86: uop_o.cache_op = CACHE_OP_DCBF;
                        10'd54: uop_o.cache_op = CACHE_OP_DCBST;
                        10'd470: uop_o.cache_op = CACHE_OP_DCBI;
                        default: uop_o.cache_op = CACHE_OP_DCBZ;
                      endcase
                  end
                endcase
              end
            end
            10'd306: begin
              // 603e TLBIE: only rB is defined; RT, RA and Rc are reserved.
              if (ENABLE_TLB_INVALIDATE && !insn_i[0] &&
                  (insn_i[25:16] == 10'b0)) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = SPECIAL_TLBIE;
                uop_o.src_a = 5'b0;
                uop_o.src_b = insn_i[15:11];
              end
            end
            10'd566: begin
              // TLBSYNC has no operands. TLBISYNC is treated as negated, so
              // it completes as a serialized supervisor no-op.
              if (ENABLE_TLB_INVALIDATE && (insn_i == 32'h7c00_046c)) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = SPECIAL_TLBSYNC;
              end
            end
            10'd595, 10'd659, 10'd210, 10'd242: begin
              logic direct_form, read_form;
              direct_form = (insn_i[10:1] == 10'd595) ||
                            (insn_i[10:1] == 10'd210);
              read_form = (insn_i[10:1] == 10'd595) ||
                          (insn_i[10:1] == 10'd659);
              if (ENABLE_SEGMENT_REGISTERS && !insn_i[0] &&
                  (direct_form ? (!insn_i[20] && (insn_i[15:11] == 5'b0)) :
                                 (insn_i[20:16] == 5'b0))) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = read_form ? SPECIAL_MFSR : SPECIAL_MTSR;
                uop_o.gpr_write = read_form;
                uop_o.src_a = read_form ? 5'b0 : insn_i[25:21];
                uop_o.src_b = direct_form ? 5'b0 : insn_i[15:11];
                uop_o.sr_index = insn_i[19:16];
                uop_o.sr_indexed = !direct_form;
              end
            end
            10'd339, 10'd371, 10'd467: begin
              logic read_form, selector_supported;
              logic [9:0] selector;
              read_form = insn_i[10:1] != 10'd467;
              selector = {insn_i[15:11], insn_i[20:16]};
              selector_supported =
                (selector == SPR_LR) || (selector == SPR_CTR) ||
                (ENABLE_SUPERVISOR_EXCEPTIONS &&
                 ((selector == SPR_XER) || (selector == SPR_DSISR) ||
                  (selector == SPR_DAR) || (selector == SPR_SRR0) ||
                  (selector == SPR_SRR1) ||
                  ((selector >= SPR_SPRG0) && (selector <= SPR_SPRG3)))) ||
                (ENABLE_TIMERS &&
                 ((selector == SPR_DEC) ||
                  (read_form && ((selector == SPR_TBL_READ) ||
                                 (selector == SPR_TBU_READ))) ||
                  (!read_form && ((selector == SPR_TBL_WRITE) ||
                                  (selector == SPR_TBU_WRITE))))) ||
                (ENABLE_SDR1 && (selector == SPR_SDR1)) ||
                (ENABLE_RUNTIME_BAT &&
                 (selector >= SPR_IBAT0U) && (selector <= SPR_DBAT3L)) ||
                (ENABLE_TLB_MISS_EXCEPTIONS && read_form &&
                 ((selector == SPR_DMISS) || (selector == SPR_HASH1) ||
                  (selector == SPR_HASH2) || (selector == SPR_IMISS))) ||
                (ENABLE_TLB_LOAD &&
                 ((selector == SPR_DCMP) || (selector == SPR_ICMP) ||
                  (selector == SPR_RPA))) ||
                (ENABLE_DEBUG_EXCEPTIONS && (selector == SPR_IABR)) ||
                (ENABLE_FULL_DECODE &&
                 ((selector == SPR_HID0) ||
                  (CPU_CFG.has_hid1 && (selector == SPR_HID1)) ||
                  (CPU_CFG.has_ear && (selector == SPR_EAR)) ||
                  (read_form && (selector == SPR_PVR))));
              spr_form_privileged = selector[SPR_PRIV_BIT];
              // 603e ignores the MFTB/MFSPR XO difference, so XO 371 reads every
              // supported selector. Privilege is checked in the core.
              if (!insn_i[0] && selector_supported) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = read_form ? SPECIAL_MFSPR : SPECIAL_MTSPR;
                uop_o.spr = selector;
                if (selector == SPR_XER) begin
                  uop_o.needs_flags = 1'b1;
                  uop_o.write_xer = !read_form;
                end
                uop_o.gpr_write = read_form;
                uop_o.src_a = insn_i[25:21];
              end
            end
            10'd23, 10'd55, 10'd87, 10'd119,
            10'd151, 10'd183, 10'd215, 10'd247,
            10'd279, 10'd311, 10'd343, 10'd375,
            10'd407, 10'd439: begin
              logic is_store, is_update, valid_update;
              is_store = (insn_i[10:1] == 10'd151) ||
                         (insn_i[10:1] == 10'd183) ||
                         (insn_i[10:1] == 10'd215) ||
                         (insn_i[10:1] == 10'd247) ||
                         (insn_i[10:1] == 10'd407) ||
                         (insn_i[10:1] == 10'd439);
              is_update = (insn_i[10:1] == 10'd55) ||
                          (insn_i[10:1] == 10'd119) ||
                          (insn_i[10:1] == 10'd183) ||
                          (insn_i[10:1] == 10'd247) ||
                          (insn_i[10:1] == 10'd311) ||
                          (insn_i[10:1] == 10'd375) ||
                          (insn_i[10:1] == 10'd439);
              valid_update = !is_update ||
                ((insn_i[20:16] != 0) &&
                 (is_store || (insn_i[20:16] != insn_i[25:21])));
              if (!insn_i[0] && valid_update) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = is_store ? SPECIAL_STORE : SPECIAL_LOAD;
                uop_o.gpr_write = !is_store;
                uop_o.mem_update = is_update;
                uop_o.zero_a = !is_update && (insn_i[20:16] == 0);
                case (insn_i[10:1])
                  10'd87, 10'd119, 10'd215, 10'd247:
                    uop_o.mem_size = MEM_BYTE;
                  10'd279, 10'd311, 10'd343, 10'd375,
                  10'd407, 10'd439: uop_o.mem_size = MEM_HALF;
                  default: uop_o.mem_size = MEM_WORD;
                endcase
                uop_o.mem_signed = (insn_i[10:1] == 10'd343) ||
                                    (insn_i[10:1] == 10'd375);
              end
            end
            10'd597, 10'd725, 10'd533, 10'd661: begin
              // lswi/stswi/lswx/stswx. The 603e accepts rA or rB in the
              // loaded range and a zero XER count (UM 2.3.4.3.7).
              if (ENABLE_MULTIPLE_STRING && ENABLE_SUPERVISOR_EXCEPTIONS &&
                  !insn_i[0]) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = insn_i[8] ? SPECIAL_STORE : SPECIAL_LOAD;
                uop_o.gpr_write = !insn_i[8];
                uop_o.zero_a = insn_i[20:16] == 5'b0;
                uop_o.use_imm = insn_i[7];
                uop_o.mem_size = MEM_WORD;
                uop_o.mem_left = 1'b1;
                uop_o.mem_seq = insn_i[7] ? SEQ_STRING_IMM : SEQ_STRING_INDEXED;
              end
            end
            10'd20, 10'd150: begin
              // lwarx has Rc reserved; stwcx. exists only with Rc = 1.
              if (ENABLE_RESERVATION && ENABLE_SUPERVISOR_EXCEPTIONS &&
                  (insn_i[0] == insn_i[8])) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = insn_i[8] ? SPECIAL_STORE : SPECIAL_LOAD;
                uop_o.gpr_write = !insn_i[8];
                uop_o.zero_a = insn_i[20:16] == 5'b0;
                uop_o.mem_size = MEM_WORD;
                uop_o.mem_reserve = !insn_i[8];
                uop_o.mem_conditional = insn_i[8];
                uop_o.needs_flags = insn_i[8];
                uop_o.write_cr_field = insn_i[8];
              end
            end
            10'd790, 10'd534, 10'd918, 10'd662: begin
              if (ENABLE_BYTE_REVERSE && ENABLE_SUPERVISOR_EXCEPTIONS &&
                  !insn_i[0]) begin
                uop_o.illegal = 1'b0;
                uop_o.special_op = insn_i[8] ? SPECIAL_STORE : SPECIAL_LOAD;
                uop_o.gpr_write = !insn_i[8];
                uop_o.zero_a = insn_i[20:16] == 5'b0;
                uop_o.mem_size = insn_i[9] ? MEM_HALF : MEM_WORD;
                uop_o.mem_reverse = 1'b1;
              end
            end
            default: ;
          endcase
        end
      end
      default: ;
    endcase
    // Illegal opcodes and invalid forms take the illegal-instruction program
    // exception (UM 4.5.7, PEM 6.4.7). An undefined SPR with spr[0] = 1 is
    // privileged in problem state; the core raises that from privileged.
    if (ENABLE_FULL_DECODE && uop_o.illegal) begin
      uop_o = '0;
      uop_o.special_op = SPECIAL_PROGRAM_ILLEGAL;
      uop_o.privileged = spr_form_privileged;
    end
    // MPC603e UM Table 4-13: instruction-derived alignment syndrome. Keep
    // metadata separate from ordinary operands so immediate low bits cannot
    // accidentally select indexed-form syndrome fields.
    if (!uop_o.illegal && ((uop_o.special_op == SPECIAL_LOAD) ||
                          (uop_o.special_op == SPECIAL_STORE))) begin
      if (insn_i[31:26] == 6'd31)
        uop_o.alignment_dsisr = {insn_i[2:1], insn_i[6], insn_i[10:7],
                                insn_i[25:21], insn_i[20:16]};
      else
        uop_o.alignment_dsisr = {2'b0, insn_i[26], insn_i[30:27],
                                insn_i[25:21], insn_i[20:16]};
    end
  end
endmodule
`default_nettype wire
