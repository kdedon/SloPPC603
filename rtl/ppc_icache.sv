`default_nettype none
// Physically addressed 603e-shaped instruction cache with line refill.
//
// Lookup cycle: the set index reads all four tag RAMs (MLAB, asynchronous)
// and all four data RAMs (M10K, registered) at once. The next cycle selects
// the word with the registered one-hot hit. The LRU update is registered and
// applied a cycle after the hit. A new lookup is accepted on the edge that
// consumes the previous response, so hits stream one per cycle.
module ppc_icache (
  input  logic         clk_i,
  input  logic         rst_ni,

  input  logic         fetch_valid_i,
  output logic         fetch_ready_o,
  input  logic [31:0]  fetch_addr_i,
  output logic         fetch_rsp_valid_o,
  input  logic         fetch_rsp_ready_i,
  output logic [31:0]  fetch_rsp_insn_o,
  output logic         fetch_rsp_error_o,

  input  logic         kill_i,
  input  logic         invalidate_i,
  output logic         invalidate_done_o,

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
  localparam int SET_COUNT = 128;
  localparam int WAY_COUNT = 4;
  localparam int LINE_BYTES = 32;
  localparam int OFFSET_BITS = $clog2(LINE_BYTES);
  localparam int WORD_BITS = $clog2(LINE_BYTES / 4);
  localparam int SET_BITS = $clog2(SET_COUNT);
  localparam int WAY_BITS = $clog2(WAY_COUNT);
  localparam int TAG_BITS = 32 - SET_BITS - OFFSET_BITS;
  localparam int LRU_BITS = WAY_COUNT * WAY_BITS;
  // Each data RAM row is half a line: four words.
  localparam int HALF_BITS = LINE_BYTES * 4;
  localparam logic [WAY_BITS-1:0] LRU_RANK = WAY_BITS'(WAY_COUNT - 1);

  typedef enum logic [2:0] {
    IC_IDLE,
    IC_REFILL_REQUEST,
    IC_REFILL_WAIT,
    IC_INSTALL,
    IC_REFILL_DRAIN
  } icache_state_t;

  icache_state_t state_q;
  // Rank zero is MRU and rank three is LRU; a valid set's ranks are a
  // permutation. The RAM holds no reset state: the first fill of an
  // all-invalid set seeds ranks {0,1,2,3} before the touch.
  typedef logic [WAY_COUNT-1:0][WAY_BITS-1:0] lru_ranks_t;
  localparam lru_ranks_t LRU_SEED = {2'd3, 2'd2, 2'd1, 2'd0};

  // A way is valid when its set's flop and its bit in the way-valid RAM are
  // both set. Flash invalidate and reset clear only the 128 set flops; the
  // first install into a cleared set rewrites all four way bits.
  logic [SET_COUNT-1:0] set_valid_q;
  logic [WAY_COUNT-1:0] way_valid_rdata, way_valid_wdata, victim_onehot;
  logic [WAY_COUNT-1:0][TAG_BITS-1:0] tag_rdata;
  logic [WAY_COUNT-1:0][HALF_BITS-1:0] data_rdata;
  logic [WAY_COUNT-1:0] tag_we, data_we;
  logic [SET_BITS:0] data_waddr;
  logic [HALF_BITS-1:0] data_wdata, line_half1_q;
  logic data_re;
  lru_ranks_t lru_rdata, lru_wdata;
  logic [SET_BITS-1:0] lru_raddr;

  logic rsp_valid_q, rsp_error_q;
  // A RAM response selects rsp_way_q with rsp_insn_q zero; any other
  // response has rsp_way_q zero. The output is one AND-OR.
  logic [31:0] rsp_insn_q;
  logic [WAY_COUNT-1:0] rsp_way_q;
  logic [1:0] rsp_word_q;
  logic [31:3] miss_addr_q;
  logic [SET_BITS-1:0] miss_set_q;
  logic [TAG_BITS-1:0] miss_tag_q;
  logic [WORD_BITS-1:0] miss_word_q;
  logic [WAY_BITS-1:0] victim_way_q;
  // The miss set's valid bits cannot change before its install: only the
  // install and an aborting invalidate write them.
  logic [WAY_COUNT-1:0] miss_valid_q;
  logic invalidate_done_q, hit_q, miss_q, protocol_error_q;
  logic upd_valid_q, upd_seed_q;
  logic [SET_BITS-1:0] upd_set_q;
  logic [WAY_BITS-1:0] upd_way_q;

  logic accept, install_ok;
  logic [SET_BITS-1:0] lookup_set;
  logic [TAG_BITS-1:0] lookup_tag;
  logic [WORD_BITS-1:0] lookup_word;
  logic [WAY_COUNT-1:0] lookup_valid, lookup_hit_way;
  logic lookup_hit;
  logic [WAY_BITS-1:0] lookup_way, victim_way;
  logic [31:0] ram_insn;

  function automatic logic [31:0] select_word(
    input logic [255:0] line,
    input logic [2:0] word_index
  );
    return line[255 - 32*word_index -: 32];
  endfunction

  function automatic logic [31:0] select_half_word(
    input logic [HALF_BITS-1:0] half,
    input logic [1:0] word_index
  );
    return half[HALF_BITS-1 - 32*word_index -: 32];
  endfunction

  // Move one way to MRU and age exactly the ways that were newer.
  function automatic lru_ranks_t lru_touch(
    input lru_ranks_t ranks,
    input logic [WAY_BITS-1:0] way
  );
    lru_ranks_t result;
    for (int w = 0; w < WAY_COUNT; w++) begin
      if (WAY_BITS'(w) == way) result[w] = '0;
      else if (ranks[w] < ranks[way]) result[w] = ranks[w] + 1'b1;
      else result[w] = ranks[w];
    end
    return result;
  endfunction

  assign lookup_set = fetch_addr_i[OFFSET_BITS +: SET_BITS];
  assign lookup_tag = fetch_addr_i[31 -: TAG_BITS];
  assign lookup_word = fetch_addr_i[2 +: WORD_BITS];
  assign accept = fetch_valid_i && fetch_ready_o;

  // Every accepted aligned lookup reads all ways; a miss ignores the data.
  // Reads happen only in IDLE and writes only in WAIT/INSTALL.
  assign data_re = accept && fetch_addr_i[1:0] == 2'b00;
  assign install_ok = rst_ni && !kill_i && !invalidate_i;
  assign data_waddr = {miss_set_q, state_q == IC_INSTALL};
  assign data_wdata = state_q == IC_INSTALL ? line_half1_q :
                                              line_rsp_line_i[255 -: HALF_BITS];
  assign lru_raddr = upd_valid_q ? upd_set_q : miss_set_q;
  assign lru_wdata = lru_touch(upd_seed_q ? LRU_SEED : lru_rdata, upd_way_q);

  genvar way;
  generate
  for (way = 0; way < WAY_COUNT; way = way + 1) begin : g_way
    assign tag_we[way] = install_ok && state_q == IC_INSTALL &&
                         victim_way_q == WAY_BITS'(way);
    assign data_we[way] = install_ok && victim_way_q == WAY_BITS'(way) &&
      (state_q == IC_INSTALL ||
       (state_q == IC_REFILL_WAIT && line_rsp_valid_i && !line_rsp_error_i));

    ppc_ram_lut #(.DEPTH(SET_COUNT), .WIDTH(TAG_BITS)) tag_ram (
      .clk_i, .we_i(tag_we[way]), .waddr_i(miss_set_q), .wdata_i(miss_tag_q),
      .raddr_i(lookup_set), .rdata_o(tag_rdata[way])
    );
    ppc_ram_sdp #(.DEPTH(2*SET_COUNT), .WIDTH(HALF_BITS)) data_ram (
      .clk_i, .we_i(data_we[way]), .waddr_i(data_waddr), .wdata_i(data_wdata),
      .re_i(data_re), .raddr_i({lookup_set, lookup_word[2]}),
      .rdata_o(data_rdata[way])
    );

    assign lookup_valid[way] = set_valid_q[lookup_set] &&
                               way_valid_rdata[way];
    assign victim_onehot[way] = victim_way_q == WAY_BITS'(way);
    assign lookup_hit_way[way] = lookup_valid[way] &&
                                 tag_rdata[way] == lookup_tag;
  end
  endgenerate

  assign way_valid_wdata = miss_valid_q | victim_onehot;
  ppc_ram_lut #(.DEPTH(SET_COUNT), .WIDTH(WAY_COUNT)) way_valid_ram (
    .clk_i, .we_i(install_ok && state_q == IC_INSTALL), .waddr_i(miss_set_q),
    .wdata_i(way_valid_wdata), .raddr_i(lookup_set),
    .rdata_o(way_valid_rdata)
  );

  ppc_ram_lut #(.DEPTH(SET_COUNT), .WIDTH(LRU_BITS)) lru_ram (
    .clk_i, .we_i(upd_valid_q), .waddr_i(upd_set_q), .wdata_i(lru_wdata),
    .raddr_i(lru_raddr), .rdata_o(lru_rdata)
  );

  always_comb begin
    lookup_hit = |lookup_hit_way;
    lookup_way = '0;
    for (int w = 0; w < WAY_COUNT; w++)
      if (lookup_hit_way[w]) lookup_way = lookup_way | WAY_BITS'(w);

    ram_insn = '0;
    for (int w = 0; w < WAY_COUNT; w++)
      if (rsp_way_q[w]) ram_insn = ram_insn | select_half_word(data_rdata[w], rsp_word_q);

    // Fill the lowest invalid way first, else the strict-LRU way.
    victim_way = '0;
    if (&miss_valid_q) begin
      for (int w = WAY_COUNT - 1; w >= 0; w--)
        if (lru_rdata[w] == LRU_RANK) victim_way = WAY_BITS'(w);
    end else begin
      for (int w = WAY_COUNT - 1; w >= 0; w--)
        if (!miss_valid_q[w]) victim_way = WAY_BITS'(w);
    end
  end

  always_comb begin
    fetch_ready_o = rst_ni && state_q == IC_IDLE &&
                    (!rsp_valid_q || fetch_rsp_ready_i) &&
                    !kill_i && !invalidate_i;
    fetch_rsp_valid_o = rst_ni && rsp_valid_q && !kill_i && !invalidate_i;
    fetch_rsp_insn_o = rsp_insn_q | ram_insn;
    fetch_rsp_error_o = rsp_error_q;

    line_req_valid_o = rst_ni && state_q == IC_REFILL_REQUEST &&
                       !kill_i && !invalidate_i;
    line_req_line_addr_o = {miss_addr_q[31:5], 5'b00000};
    line_req_critical_dw_o = miss_addr_q[4:3];
    line_req_instruction_o = 1'b1;
    line_rsp_ready_o = rst_ni &&
                       (state_q == IC_REFILL_WAIT ||
                        state_q == IC_REFILL_DRAIN);

    busy_o = rst_ni && (state_q != IC_IDLE || rsp_valid_q);
    invalidate_done_o = rst_ni && invalidate_done_q;
    hit_o = rst_ni && hit_q;
    miss_o = rst_ni && miss_q;
    protocol_error_o = rst_ni && protocol_error_q;
  end

  // The second half of an accepted line waits one cycle for the write port.
  always_ff @(posedge clk_i) begin
    if (state_q == IC_REFILL_WAIT && line_rsp_valid_i)
      line_half1_q <= line_rsp_line_i[HALF_BITS-1:0];
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= IC_IDLE;
      rsp_valid_q <= 1'b0;
      rsp_error_q <= 1'b0;
      rsp_insn_q <= 32'b0;
      rsp_way_q <= '0;
      rsp_word_q <= '0;
      miss_addr_q <= 29'b0;
      miss_set_q <= '0;
      miss_tag_q <= '0;
      miss_word_q <= '0;
      miss_valid_q <= '0;
      victim_way_q <= '0;
      invalidate_done_q <= 1'b0;
      hit_q <= 1'b0;
      miss_q <= 1'b0;
      protocol_error_q <= 1'b0;
      set_valid_q <= '0;
      upd_valid_q <= 1'b0;
      upd_seed_q <= 1'b0;
      upd_set_q <= '0;
      upd_way_q <= '0;
    end else begin
      invalidate_done_q <= 1'b0;
      hit_q <= 1'b0;
      miss_q <= 1'b0;
      upd_valid_q <= 1'b0;
      if (rsp_valid_q && fetch_rsp_ready_i)
        rsp_valid_q <= 1'b0;

      if (invalidate_i) begin
        // This is the bounded flash-invalidate command.  A refill already
        // accepted by the line transport is drained but never installed.
        set_valid_q <= '0;
        rsp_valid_q <= 1'b0;
        invalidate_done_q <= 1'b1;
        if (state_q == IC_REFILL_WAIT && !line_rsp_valid_i)
          state_q <= IC_REFILL_DRAIN;
        else if (state_q == IC_REFILL_DRAIN && !line_rsp_valid_i)
          state_q <= IC_REFILL_DRAIN;
        else
          state_q <= IC_IDLE;
      end else if (kill_i) begin
        // Offered but unaccepted refill requests are retracted.  Accepted
        // transactions are drained to preserve the line channel contract.
        rsp_valid_q <= 1'b0;
        if (state_q == IC_REFILL_WAIT && !line_rsp_valid_i)
          state_q <= IC_REFILL_DRAIN;
        else if (state_q == IC_REFILL_DRAIN && !line_rsp_valid_i)
          state_q <= IC_REFILL_DRAIN;
        else
          state_q <= IC_IDLE;
      end else begin
        unique case (state_q)
          IC_IDLE: begin
            if (accept) begin
              if (fetch_addr_i[1:0] != 2'b00) begin
                rsp_way_q <= '0;
                rsp_insn_q <= 32'b0;
                rsp_error_q <= 1'b1;
                rsp_valid_q <= 1'b1;
                protocol_error_q <= 1'b1;
              end else if (lookup_hit) begin
                rsp_way_q <= lookup_hit_way;
                rsp_word_q <= lookup_word[1:0];
                rsp_insn_q <= 32'b0;
                rsp_error_q <= 1'b0;
                rsp_valid_q <= 1'b1;
                hit_q <= 1'b1;
                upd_valid_q <= 1'b1;
                upd_seed_q <= 1'b0;
                upd_set_q <= lookup_set;
                upd_way_q <= lookup_way;
              end else begin
                miss_addr_q <= fetch_addr_i[31:3];
                miss_set_q <= lookup_set;
                miss_tag_q <= lookup_tag;
                miss_word_q <= lookup_word;
                miss_valid_q <= lookup_valid;
                miss_q <= 1'b1;
                state_q <= IC_REFILL_REQUEST;
              end
            end
          end

          IC_REFILL_REQUEST: begin
            // Victim choice waits a cycle so a preceding hit's LRU update
            // has landed.
            victim_way_q <= victim_way;
            if (line_req_valid_o && line_req_ready_i)
              state_q <= IC_REFILL_WAIT;
          end

          IC_REFILL_WAIT: begin
            if (line_rsp_valid_i && line_rsp_ready_o) begin
              rsp_way_q <= '0;
              rsp_error_q <= line_rsp_error_i;
              rsp_valid_q <= 1'b1;
              if (line_rsp_error_i) begin
                rsp_insn_q <= 32'b0;
                state_q <= IC_IDLE;
              end else begin
                rsp_insn_q <= select_word(line_rsp_line_i, miss_word_q);
                state_q <= IC_INSTALL;
              end
            end
          end

          IC_INSTALL: begin
            set_valid_q[miss_set_q] <= 1'b1;
            upd_valid_q <= 1'b1;
            upd_seed_q <= ~|miss_valid_q;
            upd_set_q <= miss_set_q;
            upd_way_q <= victim_way_q;
            state_q <= IC_IDLE;
          end

          IC_REFILL_DRAIN: begin
            if (line_rsp_valid_i && line_rsp_ready_o)
              state_q <= IC_IDLE;
          end

          default: begin
            state_q <= IC_IDLE;
            protocol_error_q <= 1'b1;
          end
        endcase
      end
    end
  end

  // synthesis translate_off
  always_ff @(posedge clk_i) begin
    if (rst_ni && accept)
      assert ($onehot0(lookup_hit_way))
        else $error("instruction cache holds one line in two ways");
  end
  // synthesis translate_on
endmodule
`default_nettype wire
