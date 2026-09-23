// Actual-core BAT translation, redirect drain, relocated memory, and bypass.
/* verilator lint_off BLKSEQ */
module tb_core_bat;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk_i = 1'b0, rst_ni = 1'b0;
  always #5 clk_i = ~clk_i;

  logic bat_write_valid_i, bat_write_ready_o;
  logic [9:0] bat_write_spr_i;
  logic [31:0] bat_write_data_i;
  logic bat_write_rsp_valid_o, bat_write_rsp_ready_i;
  logic bat_write_rsp_rejected_o, bat_write_rsp_unsupported_o;
  logic bat_write_rsp_config_error_o, bat_write_rsp_overlap_o;
  logic [3:0] bat_write_rsp_invalid_entry_o;
  logic start_valid_i, start_ready_o, start_ir_i, start_dr_i, start_pr_i;
  logic running_o, context_ir_o, context_dr_o, context_pr_o;
  logic pimem_req_valid_o, pimem_req_ready_i;
  logic [31:0] pimem_req_addr_o;
  logic [3:0] pimem_req_wimg_o;
  logic pimem_rsp_valid_i, pimem_rsp_ready_o, pimem_rsp_error_i;
  logic [31:0] pimem_rsp_insn_i;
  logic pdmem_req_valid_o, pdmem_req_ready_i, pdmem_req_write_o;
  logic [31:0] pdmem_req_addr_o, pdmem_req_wdata_o;
  logic [3:0] pdmem_req_wstrb_o, pdmem_req_wimg_o;
  logic pdmem_rsp_valid_i, pdmem_rsp_ready_o, pdmem_rsp_error_i;
  logic [31:0] pdmem_rsp_rdata_i;
  logic retire_valid_o, retire_ready_i;
  /* verilator lint_off UNUSEDSIGNAL */
  retire_packet_t retire_o;
  /* verilator lint_on UNUSEDSIGNAL */
  logic halted_o, redirect_valid_i, redirect_all_i, redirect_keep_pivot_i;
  completion_tag_t redirect_pivot_i;
  logic [31:0] redirect_target_i;
  logic redirect_accepted_o;
  logic translation_fault_o, fault_instruction_o, fault_write_o;
  logic [31:0] fault_ea_o;
  logic fault_miss_o, fault_protection_o, fault_guarded_o, fault_config_o;
  logic fault_invalid_input_o;
  logic [3:0] fault_invalid_entry_o;
  logic pimem_error_o, busy_o;

  logic [31:0] imem [0:255];
  logic [7:0] data_mem [0:255];
  integer i_state = 0, d_state = 0, i_delay = 0, d_delay = 0;
  logic [31:0] held_i_pa, held_d_pa, held_d_wdata;
  logic [3:0] held_d_wstrb;
  logic held_d_write;
  logic i_rsp_accepted, d_rsp_accepted;
  logic hold_first_instruction = 1'b0;
  integer checks = 0, cycles = 0, phase = 0, phase_retires = 0;
  integer physical_i = 0, physical_d = 0, physical_writes = 0;
  integer forbidden_physical = 0, retire_stalls = 0;

  localparam logic [31:0] I_WRONG =
    (32'd14 << 26) | (32'd7 << 21) | 32'h77;
  localparam logic [31:0] I_ADDI_R1 =
    (32'd14 << 26) | (32'd1 << 21) | 32'h1000;
  localparam logic [31:0] I_LWZ_R2 =
    (32'd32 << 26) | (32'd2 << 21) | (32'd1 << 16);
  localparam logic [31:0] I_ADDI_R2 =
    (32'd14 << 26) | (32'd2 << 21) | (32'd2 << 16) | 32'd1;
  localparam logic [31:0] I_STW_R2 =
    (32'd36 << 26) | (32'd2 << 21) | (32'd1 << 16) | 32'd4;
  localparam logic [31:0] I_LWZ_R3 =
    (32'd32 << 26) | (32'd3 << 21) | (32'd1 << 16) | 32'd4;
  localparam logic [31:0] I_BYPASS =
    (32'd14 << 26) | (32'd4 << 21) | 32'd9;

  logic [49:0] unused_page_ports;
  ppc_core_bat #(.RESET_PC(32'b0)) dut (
    .tlb_mgmt_req_valid_i('0),
    .tlb_mgmt_req_ready_o(unused_page_ports[0]),
    .tlb_mgmt_req_kind_i('0),
    .tlb_mgmt_req_bank_i('0),
    .tlb_mgmt_req_ea_i('0),
    .tlb_mgmt_req_vsid_i('0),
    .tlb_mgmt_req_pr_i('0),
    .tlb_mgmt_req_way_i('0),
    .tlb_mgmt_req_rpn_i('0),
    .tlb_mgmt_req_c_i('0),
    .tlb_mgmt_req_wimg_i('0),
    .tlb_mgmt_req_pp_i('0),
    .tlb_mgmt_rsp_valid_o(unused_page_ports[1]),
    .tlb_mgmt_rsp_ready_i('0),
    .tlb_mgmt_rsp_kind_o(unused_page_ports[3:2]),
    .tlb_mgmt_rsp_bank_o(unused_page_ports[4]),
    .tlb_mgmt_rsp_ea_o(unused_page_ports[36:5]),
    .tlb_mgmt_rsp_privileged_o(unused_page_ports[37]),
    .tlb_mgmt_rsp_refill_rejected_o(unused_page_ports[38]),
    .tlb_mgmt_rsp_unsupported_o(unused_page_ports[39]),
    .tlb_mgmt_rsp_invalid_input_o(unused_page_ports[40]),
    .tlb_mgmt_idle_o(unused_page_ports[41]),
    .page_fault_o(unused_page_ports[42]),
    .page_miss_o(unused_page_ports[43]),
    .page_protection_o(unused_page_ports[44]),
    .page_no_execute_o(unused_page_ports[45]),
    .page_guarded_o(unused_page_ports[46]),
    .page_direct_store_o(unused_page_ports[47]),
    .page_needs_changed_o(unused_page_ports[48]),
    .page_config_o(unused_page_ports[49]),.timer_tick_i(1'b0),
    .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .*);

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition)
      $fatal(1, "core BAT check %0d failed: %s phase=%0d retire=%0d",
             checks, message, phase, phase_retires);
  endtask

  function automatic logic [31:0] instruction_at_pa(input logic [31:0] pa);
    if (pa >= 32'h4000_0000 && pa < 32'h4000_0400)
      return imem[(pa - 32'h4000_0000) >> 2];
    return imem[pa >> 2];
  endfunction

  function automatic logic [31:0] data_word(input integer offset);
    return {data_mem[offset], data_mem[offset+1],
            data_mem[offset+2], data_mem[offset+3]};
  endfunction

  // Independent abstract physical instruction/data responders with varying
  // request grants and held responses.
  always @(negedge clk_i) begin
    if (!rst_ni) begin
      i_state = 0;
      d_state = 0;
      pimem_req_ready_i = 1'b0;
      pimem_rsp_valid_i = 1'b0;
      pimem_rsp_error_i = 1'b0;
      pdmem_req_ready_i = 1'b0;
      pdmem_rsp_valid_i = 1'b0;
      pdmem_rsp_error_i = 1'b0;
      i_delay = 0;
      d_delay = 0;
    end else begin
      case (i_state)
        0: begin
          pimem_req_ready_i = 1'b0;
          if (pimem_req_valid_o && (cycles % 3) != 1) begin
            held_i_pa = pimem_req_addr_o;
            check(pimem_req_wimg_o == (phase == 2 ? 4'b0001 : 4'b0000),
                  "physical instruction WIMG mismatch");
            if ((phase == 1 && (held_i_pa < 32'h4000_0000 ||
                                held_i_pa >= 32'h4000_0400)) ||
                (phase == 2 && held_i_pa >= 32'h0000_0400)) begin
              forbidden_physical++;
              check(1'b0, "instruction PA escaped configured region");
            end
            pimem_req_ready_i = 1'b1;
            i_state = 1;
          end
        end
        1: begin
          // Request was sampled at the intervening rising edge.
          pimem_req_ready_i = 1'b0;
          physical_i++;
          i_delay = 2 + (physical_i & 1);
          i_state = 2;
        end
        2: begin
          if (!(hold_first_instruction && physical_i == 1)) begin
            if (i_delay != 0)
              i_delay--;
            else begin
              pimem_rsp_insn_i = instruction_at_pa(held_i_pa);
              pimem_rsp_valid_i = 1'b1;
              i_state = 3;
            end
          end
        end
        3: begin
          if (i_rsp_accepted) begin
            pimem_rsp_valid_i = 1'b0;
            i_state = 0;
          end
        end
        default: i_state = 0;
      endcase

      case (d_state)
        0: begin
          pdmem_req_ready_i = 1'b0;
          if (pdmem_req_valid_o && (cycles % 4) != 2) begin
            held_d_pa = pdmem_req_addr_o;
            held_d_write = pdmem_req_write_o;
            held_d_wdata = pdmem_req_wdata_o;
            held_d_wstrb = pdmem_req_wstrb_o;
            check(pdmem_req_wimg_o == 4'b0000 &&
                  held_d_pa >= 32'h8000_1000 &&
                  held_d_pa < 32'h8000_1100,
                  "physical data PA/WIMG escaped DBAT mapping");
            pdmem_req_ready_i = 1'b1;
            d_state = 1;
          end
        end
        1: begin
          // Request was sampled at the intervening rising edge.
          pdmem_req_ready_i = 1'b0;
          physical_d++;
          if (held_d_write) physical_writes++;
          d_delay = 1 + (physical_d & 3);
          d_state = 2;
        end
        2: begin
          if (d_delay != 0)
            d_delay--;
          else begin
            integer word_offset;
            word_offset = int'(held_d_pa - 32'h8000_1000);
            if (held_d_write) begin
              for (integer lane = 0; lane < 4; lane++) begin
                if (held_d_wstrb[3-lane])
                  data_mem[word_offset+lane] = held_d_wdata[31-8*lane -: 8];
              end
              pdmem_rsp_rdata_i = 32'b0;
            end else begin
              pdmem_rsp_rdata_i = data_word(word_offset);
            end
            pdmem_rsp_valid_i = 1'b1;
            d_state = 3;
          end
        end
        3: begin
          if (d_rsp_accepted) begin
            pdmem_rsp_valid_i = 1'b0;
            d_state = 0;
          end
        end
        default: d_state = 0;
      endcase
    end
  end

  always @(posedge clk_i) begin
    logic retired_now;
    logic [31:0] retire_pc, retire_insn;
    retired_now = retire_valid_o && retire_ready_i;
    i_rsp_accepted = pimem_rsp_valid_i && pimem_rsp_ready_o;
    d_rsp_accepted = pdmem_rsp_valid_i && pdmem_rsp_ready_o;
    retire_pc = retire_o.pc;
    retire_insn = retire_o.insn;
    cycles++;
    if (cycles > 8000) begin
      $display("watchdog phase=%0d retire=%0d running=%0b halted=%0b router_state=%0d i_state=%0d d_state=%0d phys_i=%0d phys_d=%0d imem_req=%0b pimem_req=%0b pimem_rsp=%0b",
               phase, phase_retires, running_o, halted_o, dut.router.state_q,
               i_state, d_state, physical_i, physical_d,
               dut.imem_req_valid, pimem_req_valid_o, pimem_rsp_valid_i);
      $fatal(1, "core BAT watchdog");
    end
    if (rst_ni) begin
      #1;
      if (retire_valid_o && !retire_ready_i) retire_stalls++;
      if (retired_now) begin
        phase_retires++;
        if (phase == 1) begin
          check(retire_pc == 32'h80 + 4*(phase_retires-1) &&
                retire_insn == imem[32+phase_retires-1],
                "translated program retirement order mismatch");
        end else if (phase == 2) begin
          check(retire_pc == 4*(phase_retires-1) &&
                retire_insn == imem[phase_retires-1],
                "real-mode bypass retirement mismatch");
        end else begin
          check(1'b0, "retirement in translation-fault phase");
        end
      end
      check(!(pimem_req_valid_o && pdmem_req_valid_o),
            "two physical channels offered together");
      if (busy_o) check(running_o || bat_write_rsp_valid_o,
                        "busy outside setup response or running phase");
    end
  end

  always @(negedge clk_i) begin
    if (rst_ni && running_o)
      retire_ready_i = (cycles % 5) != 2;
    else
      retire_ready_i = 1'b0;
  end

  task automatic reset_wrapper;
    begin
      @(negedge clk_i);
      rst_ni = 1'b0;
      bat_write_valid_i = 1'b0;
      bat_write_rsp_ready_i = 1'b0;
      start_valid_i = 1'b0;
      redirect_valid_i = 1'b0;
      redirect_all_i = 1'b0;
      redirect_keep_pivot_i = 1'b0;
      redirect_target_i = 32'b0;
      redirect_pivot_i = '0;
      hold_first_instruction = 1'b0;
      phase_retires = 0;
      repeat (4) @(posedge clk_i);
      @(negedge clk_i);
      rst_ni = 1'b1;
      #1;
      check(start_ready_o && !running_o && !translation_fault_o,
            "wrapper did not reset to setup phase");
    end
  endtask

  task automatic write_bat(input logic [9:0] spr,
                           input logic [31:0] value);
    begin
      @(negedge clk_i);
      bat_write_spr_i = spr;
      bat_write_data_i = value;
      bat_write_valid_i = 1'b1;
      #1;
      check(bat_write_ready_o, "BAT setup write not ready");
      @(posedge clk_i);
      @(negedge clk_i);
      bat_write_valid_i = 1'b0;
      check(bat_write_rsp_valid_o && !bat_write_rsp_rejected_o &&
            !bat_write_rsp_unsupported_o && !bat_write_rsp_config_error_o &&
            !bat_write_rsp_overlap_o && bat_write_rsp_invalid_entry_o == 0,
            "valid BAT setup write rejected");
      repeat (2) @(posedge clk_i);
      #1;
      check(bat_write_rsp_valid_o, "BAT response did not hold");
      @(negedge clk_i);
      bat_write_rsp_ready_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      bat_write_rsp_ready_i = 1'b0;
    end
  endtask

  task automatic start_core(input logic ir, input logic dr, input logic pr);
    begin
      @(negedge clk_i);
      start_ir_i = ir;
      start_dr_i = dr;
      start_pr_i = pr;
      start_valid_i = 1'b1;
      #1;
      check(start_ready_o, "wrapper start not ready");
      @(posedge clk_i);
      @(negedge clk_i);
      start_valid_i = 1'b0;
      check(running_o && context_ir_o == ir && context_dr_o == dr &&
            context_pr_o == pr,
            "wrapper start context mismatch");
    end
  endtask

  task automatic redirect_to(input logic [31:0] target);
    integer timeout;
    begin
      @(negedge clk_i);
      redirect_target_i = target;
      redirect_all_i = 1'b1;
      redirect_valid_i = 1'b1;
      timeout = 0;
      while (!redirect_accepted_o && timeout < 100) begin
        @(negedge clk_i);
        timeout++;
      end
      check(redirect_accepted_o, "external redirect not accepted");
      @(posedge clk_i);
      @(negedge clk_i);
      redirect_valid_i = 1'b0;
      redirect_all_i = 1'b0;
    end
  endtask

  initial begin
    for (integer word = 0; word < 256; word++) imem[word] = 32'b0;
    for (integer byte_index = 0; byte_index < 256; byte_index++)
      data_mem[byte_index] = 8'b0;
    imem[0] = I_WRONG;
    imem[1] = 32'b0;
    imem[32] = I_ADDI_R1;
    imem[33] = I_LWZ_R2;
    imem[34] = I_ADDI_R2;
    imem[35] = I_STW_R2;
    imem[36] = I_LWZ_R3;
    imem[37] = 32'b0;
    data_mem[0] = 8'h00;
    data_mem[1] = 8'h00;
    data_mem[2] = 8'h00;
    data_mem[3] = 8'h05;
    bat_write_valid_i = 1'b0;
    bat_write_spr_i = 10'b0;
    bat_write_data_i = 32'b0;
    bat_write_rsp_ready_i = 1'b0;
    start_valid_i = 1'b0;
    start_ir_i = 1'b0;
    start_dr_i = 1'b0;
    start_pr_i = 1'b0;
    redirect_valid_i = 1'b0;
    redirect_all_i = 1'b0;
    redirect_keep_pivot_i = 1'b0;
    redirect_pivot_i = '0;
    redirect_target_i = 32'b0;
    retire_ready_i = 1'b0;
    pimem_req_ready_i = 1'b0;
    pimem_rsp_valid_i = 1'b0;
    pimem_rsp_insn_i = 32'b0;
    pimem_rsp_error_i = 1'b0;
    pdmem_req_ready_i = 1'b0;
    pdmem_rsp_valid_i = 1'b0;
    pdmem_rsp_rdata_i = 32'b0;
    pdmem_rsp_error_i = 1'b0;

    // Translated program: hold the first accepted physical fetch across an
    // external redirect, then drain/discard it before fetching the target.
    phase = 1;
    reset_wrapper();
    write_bat(10'd529, 32'h4000_0002);
    write_bat(10'd528, 32'h0000_0003);
    write_bat(10'd537, 32'h8000_0002);
    write_bat(10'd536, 32'h0000_0003);
    hold_first_instruction = 1'b1;
    start_core(1'b1, 1'b1, 1'b0);
    while (!(i_state == 2 && physical_i == 1)) @(negedge clk_i);
    redirect_to(32'h0000_0080);
    hold_first_instruction = 1'b0;
    while (!halted_o && phase_retires < 6) @(posedge clk_i);
    check(halted_o && phase_retires == 6 &&
          dut.core.regfile.gpr[2] == 32'd6 &&
          dut.core.regfile.gpr[3] == 32'd6 && data_word(4) == 32'd6,
          "relocated translated load/store program state mismatch");
    check(dut.core.regfile.gpr[7] == 0 && forbidden_physical == 0 &&
          physical_d == 3 && physical_writes == 1,
          "redirect drain or physical data coverage mismatch");

    // Real mode bypasses empty BATs and preserves EA as PA with explicit WIMG.
    phase = 2;
    imem[0] = I_BYPASS;
    imem[1] = 32'b0;
    reset_wrapper();
    start_core(1'b0, 1'b0, 1'b0);
    while (!halted_o && phase_retires < 2) @(posedge clk_i);
    check(halted_o && phase_retires == 2 &&
          dut.core.regfile.gpr[4] == 32'd9,
          "actual-core real-mode bypass failed");

    // Translation-enabled empty IBAT misses locally with no physical request.
    phase = 3;
    reset_wrapper();
    begin
      integer before_physical, timeout;
      before_physical = physical_i;
      start_core(1'b1, 1'b0, 1'b0);
      timeout = 0;
      while (!translation_fault_o && timeout < 100) begin
        @(posedge clk_i);
        timeout++;
      end
      check(translation_fault_o && fault_instruction_o && fault_miss_o &&
            fault_ea_o == 0 && halted_o && physical_i == before_physical &&
            !fault_write_o && !fault_protection_o && !fault_guarded_o &&
            !fault_config_o && !fault_invalid_input_o &&
            fault_invalid_entry_o == 0 && !pimem_error_o,
            "actual-core IBAT miss or no-physical boundary mismatch");
    end

    check(retire_stalls > 0 && physical_i >= 9,
          "delayed response/grant/retirement coverage incomplete");
    $display("PASS: tb_core_bat %0d checks, %0d physical I/%0d D, %0d writes, %0d retire stalls",
             checks, physical_i, physical_d, physical_writes, retire_stalls);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
