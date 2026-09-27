`default_nettype none
package ppc_fpu_pkg;
  import ppc_pkg::completion_tag_t;

  // invalid[n] corresponds to the architected FPSCR cause named here.
  typedef enum logic [3:0] {
    INV_SNAN = 4'd0,
    INV_ISI = 4'd1,
    INV_IDI = 4'd2,
    INV_ZDZ = 4'd3,
    INV_IMZ = 4'd4,
    INV_VC = 4'd5,
    INV_SOFT = 4'd6,
    INV_SQRT = 4'd7,
    INV_CVI = 4'd8
  } ppc_fpu_invalid_t;

  typedef enum logic [4:0] {
    FP_ADD = 5'd0,
    FP_SUB = 5'd1,
    FP_MUL = 5'd2,
    FP_DIV = 5'd3,
    FP_MADD = 5'd4,
    FP_MSUB = 5'd5,
    FP_NMADD = 5'd6,
    FP_NMSUB = 5'd7,
    FP_FRSP = 5'd8,
    FP_FCTIW = 5'd9,
    FP_FCTIWZ = 5'd10,
    FP_CMPU = 5'd11,
    FP_CMPO = 5'd12,
    FP_FRES = 5'd13,
    FP_FRSQRTE = 5'd14
  } ppc_fpu_op_t;

  typedef struct packed {
    completion_tag_t tag;
    ppc_fpu_op_t op;
    logic [63:0] a;
    logic [63:0] b;
    logic [63:0] c;
    logic [1:0] rn;
    logic ni;
    logic ve;
    logic oe;
    logic ue;
    logic ze;
    logic single_result;
  } ppc_fpu_arith_req_t;

  typedef struct packed {
    completion_tag_t tag;
    logic [63:0] result;
    logic write_result;
    logic [8:0] invalid;
    logic ox;
    logic ux;
    logic zx;
    logic xx;
    logic fr;
    logic fi;
    logic frfi_valid;
    logic [4:0] fprf;
    logic fprf_valid;
    logic [3:0] fpcc;
    logic compare_valid;
  } ppc_fpu_arith_rsp_t;

  typedef struct packed {
    completion_tag_t tag;
    logic [31:0] insn;
    logic [31:0] gpr_a;
    logic [31:0] gpr_b;
    logic msr_fp;
    logic msr_fe0;
    logic msr_fe1;
  } ppc_fpu_issue_t;

  typedef enum logic [2:0] {
    FPU_NO_EXCEPTION = 3'd0,
    FPU_ILLEGAL = 3'd1,
    FPU_UNAVAILABLE = 3'd2,
    FPU_ALIGNMENT = 3'd3,
    FPU_MEMORY_FAULT = 3'd4,
    FPU_FP_ENABLED = 3'd5
  } ppc_fpu_exception_t;

  typedef struct packed {
    completion_tag_t tag;
    ppc_fpu_exception_t exception;
    logic [31:0] ea;
    logic [3:0] fault_code;
    logic [31:0] fault_info;
    logic [4:0] fpr_index;
    logic fpr_write;
    logic [63:0] fpr_value;
    logic fpscr_write;
    logic [31:0] fpscr_value;
    logic cr_write;
    logic [2:0] cr_field;
    logic [3:0] cr_value;
    logic gpr_update;
    logic [4:0] gpr_index;
    logic [31:0] gpr_value;
    logic store;
  } ppc_fpu_result_t;

  typedef struct packed {
    completion_tag_t tag;
    logic [31:0] ea;
    logic [3:0] size_bytes;
    logic write;
    logic [63:0] data;
  } ppc_fpu_mem_t;

  typedef struct packed {
    completion_tag_t tag;
    logic [63:0] data;
    logic fault;
    logic [3:0] fault_code;
    logic [31:0] fault_info;
  } ppc_fpu_mem_rsp_t;
endpackage
`default_nettype wire
