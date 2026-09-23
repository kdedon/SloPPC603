// Direct source-backed checks for the standalone exception-state controller.
/* verilator lint_off BLKSEQ */
module tb_exception_state;
  localparam logic [3:0] EVENT_SC              = 4'd0;
  localparam logic [3:0] EVENT_PROGRAM_ILLEGAL = 4'd1;
  localparam logic [3:0] EVENT_PROGRAM_PRIV    = 4'd2;
  localparam logic [3:0] EVENT_RFI              = 4'd3;
  localparam logic [3:0] EVENT_ALIGNMENT        = 4'd4;
  localparam logic [3:0] EVENT_ISI              = 4'd5;
  localparam logic [3:0] EVENT_DSI              = 4'd8;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic event_valid, event_ready;
  logic [3:0] event_kind;
  logic [2:0] event_isi_cause;
  logic [31:0] event_pc;
  logic rfi_pending_exception;
  logic result_valid, result_ready, result_supported, result_is_exception;
  logic [31:0] result_target;
  logic state_load_valid, state_load_ready;
  logic [2:0] state_load_enable;
  logic [31:0] state_load_msr, state_load_srr0, state_load_srr1;
  logic [31:0] msr, srr0, srr1;
  int checks = 0;

  ppc_exception_state dut (
    .clk_i(clk), .rst_ni(rst_n),
    .event_valid_i(event_valid), .event_ready_o(event_ready),
    .event_kind_i(event_kind), .event_pc_i(event_pc),
    .event_isi_cause_i(event_isi_cause),
    .event_miss_cr0_i('0), .event_miss_key_i(1'b0), .event_miss_way_i(1'b0),
    .rfi_pending_exception_i(rfi_pending_exception),
    .result_valid_o(result_valid), .result_ready_i(result_ready),
    .result_supported_o(result_supported),
    .result_is_exception_o(result_is_exception),
    .result_target_o(result_target),
    .state_load_valid_i(state_load_valid),
    .state_load_ready_o(state_load_ready),
    .state_load_enable_i(state_load_enable),
    .state_load_msr_i(state_load_msr),
    .state_load_srr0_i(state_load_srr0),
    .state_load_srr1_i(state_load_srr1),
    .msr_o(msr), .srr0_o(srr0), .srr1_o(srr1)
  );

  task automatic require(input logic condition, input string message);
    if (!condition) $fatal(1, "%s", message);
    checks++;
  endtask

  task automatic clear_inputs;
    event_valid = 1'b0;
    event_kind = EVENT_SC;
    event_isi_cause = 3'b0;
    event_pc = 32'b0;
    rfi_pending_exception = 1'b0;
    result_ready = 1'b0;
    state_load_valid = 1'b0;
    state_load_enable = 3'b0;
    state_load_msr = 32'b0;
    state_load_srr0 = 32'b0;
    state_load_srr1 = 32'b0;
  endtask

  task automatic load_state(
    input logic [2:0] enables,
    input logic [31:0] new_msr,
    input logic [31:0] new_srr0,
    input logic [31:0] new_srr1
  );
    @(negedge clk);
    state_load_valid = 1'b1;
    state_load_enable = enables;
    state_load_msr = new_msr;
    state_load_srr0 = new_srr0;
    state_load_srr1 = new_srr1;
    #1;
    require(state_load_ready, "committed state load was not accepted");
    @(posedge clk);
    #1;
    state_load_valid = 1'b0;
  endtask

  task automatic accept_event(
    input logic [3:0] kind,
    input logic [31:0] pc,
    input logic pending,
    input logic [2:0] isi_cause = 3'b0
  );
    @(negedge clk);
    event_valid = 1'b1;
    event_kind = kind;
    event_isi_cause = isi_cause;
    event_pc = pc;
    rfi_pending_exception = pending;
    #1;
    require(event_ready, "event was not accepted into empty result slot");
    @(posedge clk);
    #1;
    event_valid = 1'b0;
    rfi_pending_exception = 1'b0;
    require(result_valid, "accepted event did not produce a result");
  endtask

  task automatic consume_result;
    @(negedge clk);
    result_ready = 1'b1;
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    require(!result_valid, "accepted result was not removed");
  endtask

  initial begin
    logic [31:0] held_msr, held_srr0, held_srr1, held_target;

    clear_inputs();
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    require(msr == 0 && srr0 == 0 && srr1 == 0 && !result_valid,
            "reset state is not the configured zero state");
    require(event_ready && state_load_ready,
            "idle controller did not advertise both acceptance paths");

    // An accepted SC changes architectural state at event acceptance. Its
    // result may then stall without a second state transition.
    load_state(3'b111, 32'hfffd_ffff, 32'hdead_beef, 32'h1357_9bdf);
    require(msr == 32'hfffd_ffff && srr0 == 32'hdead_beef &&
            srr1 == 32'h1357_9bdf, "atomic state preload failed");
    accept_event(EVENT_SC, 32'hffff_fffc, 1'b0);
    require(result_supported && result_is_exception &&
            result_target == 32'hfff0_0c00, "SC result/vector is wrong");
    require(srr0 == 32'h0000_0000, "SC PC+4 wraparound is wrong");
    require(srr1 == 32'h87c0_ffff,
            "SC SRR1 save/exception-field clearing is wrong");
    require(msr == 32'hfff9_10cd, "SC exception MSR transform is wrong");

    held_msr = msr;
    held_srr0 = srr0;
    held_srr1 = srr1;
    held_target = result_target;
    @(negedge clk);
    event_valid = 1'b1;
    event_kind = EVENT_PROGRAM_ILLEGAL;
    event_pc = 32'h0000_1234;
    state_load_valid = 1'b1;
    state_load_enable = 3'b111;
    state_load_msr = 32'h0123_4567;
    state_load_srr0 = 32'h89ab_cdef;
    state_load_srr1 = 32'hfedc_ba98;
    #1;
    require(!event_ready && !state_load_ready,
            "stalled result admitted another transaction");
    repeat (2) begin
      @(posedge clk);
      #1;
      require(result_valid && result_supported && result_is_exception &&
              result_target == held_target, "stalled result changed");
      require(msr == held_msr && srr0 == held_srr0 && srr1 == held_srr1,
              "stalled result repeated or admitted a state transition");
    end

    // A held event is accepted on result turnover. The event has priority
    // over a simultaneous committed-state load.
    @(negedge clk);
    result_ready = 1'b1;
    #1;
    require(event_ready && !state_load_ready,
            "turnover/event priority is wrong");
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    event_valid = 1'b0;
    state_load_valid = 1'b0;
    require(result_valid && result_supported && result_is_exception &&
            result_target == 32'hfff0_0700,
            "turnover did not replace SC result with program result");
    require(srr0 == 32'h0000_1234 && srr1 == 32'h87c8_10cd,
            "illegal program exception saved state/cause incorrectly");
    require(msr == 32'hfff9_10cd,
            "turnover used colliding state-load data");
    consume_result();

    // Privileged and illegal causes are distinct and only one is installed.
    load_state(3'b111, 32'h0000_0040, 32'h1111_1111, 32'h2222_2222);
    accept_event(EVENT_PROGRAM_PRIV, 32'h0000_2000, 1'b0);
    require(result_supported && result_is_exception &&
            result_target == 32'hfff0_0700, "privileged vector is wrong");
    require(srr0 == 32'h0000_2000 && srr1 == 32'h0004_0040,
            "privileged program SRR state is wrong");
    consume_result();

    // Table 4-13: fault PC (not PC+4), only low MSR half saved, IP vector.
    // Unlike SC/program events, alignment clears all upper SRR1 bits.
    for (int prefix = 0; prefix < 2; prefix++) begin
      load_state(3'b111, prefix != 0 ? 32'hfffd_ffff : 32'h0000_8002,
                 32'h1111_1111, 32'h2222_2222);
      accept_event(EVENT_ALIGNMENT, 32'h0000_2ffc, 1'b0);
      require(result_supported && result_is_exception &&
              result_target == (prefix != 0 ? 32'hfff0_0600 : 32'h0000_0600),
              "alignment exception vector/IP selection is wrong");
      require(srr0 == 32'h0000_2ffc &&
              srr1 == (prefix != 0 ? 32'h0000_ffff : 32'h0000_8002),
              "alignment fault PC/MSR low-half save is wrong");
      require(msr == (prefix != 0 ? 32'hfff9_10cd : 32'b0),
              "alignment exception entry MSR transform is wrong");
      held_msr=msr;held_srr0=srr0;held_srr1=srr1;held_target=result_target;
      repeat(3) begin
        @(posedge clk);#1;
        require(result_valid && result_target == held_target &&
                !event_ready && !state_load_ready && msr == held_msr &&
                srr0 == held_srr0 && srr1 == held_srr1,
                "held alignment result changed or admitted another event");
      end
      consume_result();
    end

    // MPC603e UM Table 4-11: precise data fault PC, low MSR half only,
    // and both IP prefixes. Data EA/syndrome are owned by the core's DAR/DSISR.
    for (int prefix = 0; prefix < 2; prefix++) begin
      load_state(3'b111, prefix != 0 ? 32'hfffd_ffff : 32'h0000_8002,
                 32'h1111_1111, 32'h2222_2222);
      accept_event(EVENT_DSI, 32'h0000_2ffc, 1'b0);
      require(result_supported && result_is_exception &&
              result_target == (prefix != 0 ? 32'hfff0_0300 : 32'h0000_0300),
              "DSI vector/IP selection is wrong");
      require(srr0 == 32'h0000_2ffc &&
              srr1 == (prefix != 0 ? 32'h0000_ffff : 32'h0000_8002),
              "DSI fault PC/low MSR save is wrong");
      require(msr == (prefix != 0 ? 32'hfff9_10cd : 32'b0),
              "DSI exception entry MSR transform is wrong");
      held_msr=msr;held_srr0=srr0;held_srr1=srr1;held_target=result_target;
      repeat(3) begin
        @(posedge clk);#1;
        require(result_valid && result_target == held_target &&
                !event_ready && !state_load_ready && msr == held_msr &&
                srr0 == held_srr0 && srr1 == held_srr1,
                "held DSI result changed or admitted another event");
      end
      consume_result();
    end

    // PEM Table 6-10 / 603e Table 4-5: one ISI cause, full-function MSR
    // fields retained, requested fault PC, and the IP-selected vector.
    for (int cause = 1; cause <= 2; cause++) begin
      for (int prefix = 0; prefix < 2; prefix++) begin
        load_state(3'b111, prefix != 0 ? 32'hfffd_ffff : 32'h87c0_8002,
                   32'hdead_beef, 32'h1234_5678);
        accept_event(EVENT_ISI, 32'h0000_2340, 1'b0, 3'(cause));
        require(result_supported && result_is_exception &&
                result_target == (prefix != 0 ? 32'hfff0_0400 : 32'h0000_0400),
                "ISI IP-selected vector is wrong");
        require(srr0 == 32'h0000_2340 &&
                srr1 == ((prefix != 0 ? 32'h87c0_ffff : 32'h87c0_8002) |
                         (cause == 1 ? 32'h0800_0000 : 32'h1000_0000)),
                "ISI original PC/MSR mask/single cause is wrong");
        require(msr == (prefix != 0 ? 32'hfff9_10cd : 32'h87c0_0000),
                "ISI entry MSR transform is wrong");
        held_msr=msr;held_srr0=srr0;held_srr1=srr1;held_target=result_target;
        @(negedge clk); event_isi_cause = 3'(3-cause);
        repeat(3) begin
          @(posedge clk);#1;
          require(result_valid && result_supported && result_is_exception &&
                  result_target == held_target && msr == held_msr &&
                  srr0 == held_srr0 && srr1 == held_srr1,
                  "held ISI cause/state changed with live inputs");
        end
        consume_result();
      end
    end
    // Neither FETCH_OK nor reserved causes authorize an ISI event.
    for (int cause = 0; cause < 8; cause++) begin
      if (cause != 1 && cause != 2) begin
        accept_event(EVENT_ISI, 32'h0000_2340, 1'b0, 3'(cause));
        require(!result_supported && !result_is_exception && result_target == 0 &&
                msr == held_msr && srr0 == held_srr0 && srr1 == held_srr1,
                "invalid ISI selector changed architectural state");
        consume_result();
      end
    end

    // External IRQ Table 4-12 saves the next PC and ONLY the low MSR half.
    for(int prefix=0;prefix<2;prefix++) begin
      load_state(3'b111,(prefix != 0) ? 32'h87c08070 : 32'h87c08030,32'h1111,32'h2222);
      accept_event(4'd6,32'h2340,1'b0);
      require(result_supported && result_is_exception &&
              result_target==((prefix != 0) ? 32'hfff00500 : 32'h500),"IRQ vector/IP selection");
      require(srr0==32'h2340 && srr1==((prefix != 0) ? 32'h8070 : 32'h8030) &&
              msr==((prefix != 0) ? 32'h87c00040 : 32'h87c00000),"IRQ next PC/low-half save/entry MSR");
      held_msr=msr;held_srr0=srr0;held_srr1=srr1;held_target=result_target;
      repeat(3)begin
        @(posedge clk);#1;
        require(result_valid && result_target==held_target && msr==held_msr &&
                srr0==held_srr0 && srr1==held_srr1,"held IRQ result changed state");
      end
      consume_result();
    end
    for(int rejected=0;rejected<2;rejected++)begin
      load_state(3'b001,(rejected != 0) ? 32'h00028000 : 32'h00000000,0,0);
      held_msr=msr;held_srr0=srr0;held_srr1=srr1;
      accept_event(4'd6,32'h2340,1'b0);
      require(!result_supported && !result_is_exception && result_target==0 &&
              msr==held_msr && srr0==held_srr0 && srr1==held_srr1,"masked/TGPR IRQ mutated state");
      consume_result();
    end

    // DEC differs from external IRQ: full-function MSR fields are saved.
    for(int prefix=0;prefix<2;prefix++)begin
      load_state(3'b111,(prefix!=0)?32'h87c08070:32'h87c08030,32'h1111,32'h2222);
      accept_event(4'd7,32'h3450,1'b0);
      require(result_supported && result_is_exception &&
              result_target==((prefix!=0)?32'hfff00900:32'h900),"DEC vector/IP selection");
      require(srr0==32'h3450 && srr1==((prefix!=0)?32'h87c08070:32'h87c08030) &&
              msr==((prefix!=0)?32'h87c00040:32'h87c00000),"DEC full saved MSR differs from IRQ mask");
      held_msr=msr;held_srr0=srr0;held_srr1=srr1;held_target=result_target;
      repeat(3)begin
        @(posedge clk);#1;
        require(result_valid && result_target==held_target && msr==held_msr &&
                srr0==held_srr0 && srr1==held_srr1,"held DEC result changed state");
      end
      consume_result();
    end
    for(int rejected=0;rejected<2;rejected++)begin
      load_state(3'b001,(rejected!=0)?32'h00028000:32'h00000000,0,0);
      held_msr=msr;held_srr0=srr0;held_srr1=srr1;
      accept_event(4'd7,32'h3450,1'b0);
      require(!result_supported && !result_is_exception && result_target==0 &&
              msr==held_msr && srr0==held_srr0 && srr1==held_srr1,"masked/TGPR DEC mutated state");
      consume_result();
    end

    // Supervisor RFI restores the 603e state subset, preserves partial
    // function bits, clears TGPR, and aligns the saved target.
    load_state(3'b111, 32'h7802_0000, 32'h1234_567b, 32'h87c0_ff73);
    accept_event(EVENT_RFI, 32'h0000_3000, 1'b0);
    require(result_supported && !result_is_exception &&
            result_target == 32'h1234_5678, "RFI target alignment is wrong");
    require(msr == 32'hffc0_ff73, "RFI masked MSR restore/TGPR clear is wrong");
    require(srr0 == 32'h1234_567b && srr1 == 32'h87c0_ff73,
            "RFI unexpectedly modified save/restore registers");
    consume_result();

    // RFI in problem state is a privileged-instruction program exception.
    load_state(3'b111, 32'h0000_4040, 32'haaaa_aaaa, 32'h5555_5555);
    accept_event(EVENT_RFI, 32'h0000_4000, 1'b0);
    require(result_supported && result_is_exception &&
            result_target == 32'hfff0_0700,
            "problem-state RFI did not take the program vector");
    require(msr == 32'h0000_0040 && srr0 == 32'h0000_4000 &&
            srr1 == 32'h0004_4040,
            "problem-state RFI did not save a privileged cause");
    consume_result();

    // A pending exception enabled by RFI requires priority arbitration this
    // unit does not implement. Reject it and preserve every state register.
    load_state(3'b111, 32'h0100_0000, 32'h0000_5003, 32'h87c0_0073);
    held_msr = msr;
    held_srr0 = srr0;
    held_srr1 = srr1;
    accept_event(EVENT_RFI, 32'h0000_5000, 1'b1);
    require(!result_supported && !result_is_exception && result_target == 0,
            "pending-exception RFI was not explicitly rejected");
    require(msr == held_msr && srr0 == held_srr0 && srr1 == held_srr1,
            "rejected pending-exception RFI changed state");
    consume_result();

    // Misaligned boundaries, unknown causes, and nested non-RFI events in
    // TGPR mode are explicit no-state-change rejections.
    accept_event(EVENT_SC, 32'h0000_6002, 1'b0);
    require(!result_supported && result_target == 0,
            "misaligned committed boundary was accepted");
    require(msr == held_msr && srr0 == held_srr0 && srr1 == held_srr1,
            "misaligned event changed state");
    consume_result();

    // Unknown four-bit selectors preserve the committed state.
    held_msr=msr;held_srr0=srr0;held_srr1=srr1;
    accept_event(4'd9, 32'h0000_6000, 1'b0);
    require(!result_supported && !result_is_exception && result_target==0 &&
            msr==held_msr && srr0==held_srr0 && srr1==held_srr1,
            "unknown event kind changed architectural state");
    consume_result();

    load_state(3'b001, 32'h0002_0000, 32'b0, 32'b0);
    held_srr0 = srr0;
    held_srr1 = srr1;
    accept_event(EVENT_PROGRAM_ILLEGAL, 32'h0000_7000, 1'b0);
    require(!result_supported && msr == 32'h0002_0000 &&
            srr0 == held_srr0 && srr1 == held_srr1,
            "TGPR-mode nested program event was not rejected");
    consume_result();

    // Individual state-load enables are atomic and do not imply mtmsr/mtspr
    // decode semantics.
    load_state(3'b010, 32'hffff_ffff, 32'h0bad_f00d, 32'hffff_ffff);
    require(msr == 32'h0002_0000 && srr0 == 32'h0bad_f00d &&
            srr1 == held_srr1, "state load enable mask is wrong");

    // Reset cancels a held result and restores all configured reset values.
    load_state(3'b001, 32'h0000_0000, 32'b0, 32'b0);
    accept_event(EVENT_SC, 32'h0000_8000, 1'b0);
    require(result_valid, "reset fixture did not create a held result");
    @(negedge clk);
    rst_n = 1'b0;
    #1;
    require(!result_valid && !event_ready && !state_load_ready,
            "reset assertion did not immediately cancel handshakes");
    @(posedge clk);
    #1;
    require(!result_valid && msr == 0 && srr0 == 0 && srr1 == 0,
            "reset did not cancel result and restore state");
    require(!event_ready && !state_load_ready,
            "acceptance remained enabled during sampled reset");

    $display("tb_exception_state: PASS (%0d checks)", checks);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
