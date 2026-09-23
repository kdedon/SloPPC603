// Independent SPR encoding oracle for the CPU-programmable BAT profile.
/* verilator lint_off BLKSEQ */
module tb_runtime_bat_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t runtime, runtime_timers, legacy, baseline;
  logic unused_outputs;
  int checks = 0;
  int accepted_bat = 0;
  int rejected_bat = 0;

  assign unused_outputs = ^{runtime, runtime_timers, legacy, baseline};
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1), .ENABLE_RUNTIME_BAT(1'b1)) runtime_decode (
    .insn_i(insn), .uop_o(runtime));
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1), .ENABLE_TIMERS(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1)) runtime_timer_decode (
    .insn_i(insn), .uop_o(runtime_timers));
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1)) legacy_decode (
    .insn_i(insn), .uop_o(legacy));
  ppc_decode baseline_decode (.insn_i(insn), .uop_o(baseline));

  // SPR[4:0] precedes SPR[9:5] in the instruction word.
  function automatic logic [31:0] encode(
    input int xo, input int regno, input int selector, input bit rc);
    return (32'd31 << 26) | (32'(regno) << 21) |
      ((32'(selector) & 32'd31) << 16) |
      ((32'(selector) >> 5) << 11) | (32'(xo) << 1) | 32'(rc);
  endfunction

  function automatic bit old_selector(input int selector);
    return selector == 1 || selector == 8 || selector == 9 ||
      selector == 18 || selector == 19 || selector == 26 ||
      selector == 27 || (selector >= 272 && selector <= 275);
  endfunction

  function automatic bit timer_selector(input int selector, input bit read_form);
    return selector == 22 || (read_form && (selector == 268 || selector == 269)) ||
      (!read_form && (selector == 284 || selector == 285));
  endfunction

  task automatic check(input logic condition, input string message_text);
    checks++;
    if (!condition)
      $fatal(1, "runtime BAT decode %s word=%08x selector=%0d xo=%0d",
        message_text, insn, {insn[15:11], insn[20:16]}, insn[10:1]);
  endtask

  initial begin
    check(IQ_DEPTH > 0, "configured frontend");
    for (int regno = 0; regno < 32; regno++) begin
      for (int selector = 0; selector < 1024; selector++) begin
        for (int form = 0; form < 3; form++) begin
          for (int rc = 0; rc < 2; rc++) begin
            bit reading, bat, expected_runtime, expected_timers;
            bit expected_legacy, expected_baseline;
            int xo;
            reading = form != 2;
            xo = form == 0 ? 339 : form == 1 ? 371 : 467;
            bat = selector >= 528 && selector <= 543;
            expected_runtime = rc == 0 && (old_selector(selector) || bat);
            expected_timers = rc == 0 &&
              (old_selector(selector) || bat || timer_selector(selector, reading));
            expected_legacy = rc == 0 && old_selector(selector) &&
              (form != 1 || selector == 1);
            expected_baseline = rc == 0 && form != 1 &&
              (selector == 8 || selector == 9);

            insn = encode(xo, regno, selector, 1'(rc));
            #1;
            check(runtime.illegal == !expected_runtime,
              "runtime selector or Rc acceptance");
            check(runtime_timers.illegal == !expected_timers,
              "timer plus runtime selector acceptance");
            check(legacy.illegal == !expected_legacy,
              "legacy profile acceptance changed");
            check(baseline.illegal == !expected_baseline,
              "default profile acceptance changed");
            if (bat) begin
              check(legacy.illegal && baseline.illegal,
                "BAT selector escaped feature gate");
              check(!runtime.mem_update && !runtime.write_xer &&
                !runtime.write_ca && !runtime.write_ov_so && !runtime.write_cr0 &&
                !runtime.write_cr_fields && !runtime.write_cr_bit &&
                !runtime.branch_lk,
                "BAT form acquired unrelated effects");
              if (rc == 0) begin
                accepted_bat++;
                check(!runtime.illegal && runtime.spr == 10'(selector) &&
                  runtime.special_op == (reading ? SPECIAL_MFSPR : SPECIAL_MTSPR),
                  "BAT split selector or form identity");
                check(runtime.gpr_write == reading &&
                  runtime.dst == 5'(regno) && runtime.src_a == 5'(regno) &&
                  !runtime.needs_flags && !runtime.use_imm && !runtime.zero_a,
                  "BAT source, destination, or dependency permission");
                check(runtime_timers == runtime,
                  "timer option changed BAT read alias or write");
              end else begin
                rejected_bat++;
                check(runtime.illegal && !runtime.gpr_write &&
                  runtime.special_op == SPECIAL_NONE,
                  "reserved Rc admitted BAT operation");
              end
            end else if (!expected_runtime) begin
              check(!runtime.gpr_write && runtime.special_op == SPECIAL_NONE,
                "unsupported selector acquired destination");
            end
          end
        end
      end
    end
    $display("PASS runtime BAT decode checks=%0d accepted_bat=%0d rejected_bat=%0d",
      checks, accepted_bat, rejected_bat);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
