// Current integrated subset measurement: all runtime controls and outputs remain ports.
// No behavioral responder, constant memory inputs, or folded retirement digest.
module ppc_integrated_measure (
  input  logic clk_i,
  input  logic rst_ni,

  output logic                    retire_valid_o,
  input  logic                    retire_ready_i,
  output ppc_pkg::retire_packet_t retire_o,
  output logic                    halted_o,
  output logic                    ifetch_error_o,
  output logic                    bus_protocol_error_o,
  output logic                    bus_busy_o,
  output logic                    icache_hit_o,
  output logic                    icache_miss_o,
  output logic                    icache_busy_o,

  input  logic                    maintenance_valid_i,
  output logic                    maintenance_ready_o,
  input  logic                    maintenance_invalidate_i,
  input  logic                    maintenance_cache_enable_i,
  output logic                    maintenance_done_valid_o,
  input  logic                    maintenance_done_ready_i,
  output logic                    cache_enabled_o,
  output logic                    maintenance_busy_o,

  input  logic                     redirect_valid_i,
  input  logic                     redirect_all_i,
  input  logic                     redirect_keep_pivot_i,
  input  ppc_pkg::completion_tag_t redirect_pivot_i,
  input  logic [31:0]              redirect_target_i,
  output logic                     redirect_accepted_o,

  output logic        br_n_o,
  input  logic        bg_n_i,
  input  logic        abb_n_i,
  output logic        abb_n_o,
  output logic        abb_oe_o,
  output logic        ts_n_o,
  output logic        ts_oe_o,
  output logic [31:0] a_o,
  output logic [4:0]  tt_o,
  output logic        tbst_n_o,
  output logic [2:0]  tsiz_o,
  output logic [1:0]  tc_o,
  output logic        ci_n_o,
  output logic        wt_n_o,
  output logic        gbl_n_o,
  output logic [1:0]  cse_o,
  output logic        addr_oe_o,
  input  logic        aack_n_i,
  input  logic        artry_n_i,
  input  logic        dbg_n_i,
  input  logic        dbb_n_i,
  output logic        dbb_n_o,
  output logic        dbb_oe_o,
  input  logic [63:0] d_i,
  output logic [63:0] d_o,
  output logic        d_oe_o,
  input  logic        ta_n_i,
  input  logic        drtry_n_i,
  input  logic        tea_n_i
);
  ppc_core_cached_bus60x_managed #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .RESET_CACHE_ENABLE(1'b0)
  ) dut (.*);
endmodule
