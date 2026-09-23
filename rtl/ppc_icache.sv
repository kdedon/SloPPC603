// Bounded 603e-shaped instruction-cache storage and refill controller.
// Addresses are already physical.  This module does not perform translation,
// permission checking, scalar bypass, or critical-word forwarding.
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
  localparam integer SET_COUNT = 128;
  localparam integer WAY_COUNT = 4;

  typedef enum logic [1:0] {
    IC_IDLE,
    IC_REFILL_REQUEST,
    IC_REFILL_WAIT,
    IC_REFILL_DRAIN
  } icache_state_t;

  icache_state_t state_q;
  logic [WAY_COUNT-1:0][SET_COUNT-1:0][19:0] tag_mem;
  // One synchronous-read line RAM. Flattening {way, set} keeps the data path
  // independent of the register-based tag lookup and permits FPGA block RAM.
  // Neither the RAM nor its output register is reset; valid tags own visibility.
  logic [255:0] data_mem [0:WAY_COUNT*SET_COUNT-1];
  logic [255:0] data_read_q;
  logic data_read_enable, data_write_enable;
  logic rsp_from_ram_q;
  logic [2:0] hit_word_q;
  logic [WAY_COUNT-1:0][SET_COUNT-1:0] valid_mem;
  // Rank zero is MRU and rank three is LRU.  Every set remains a permutation.
  logic [WAY_COUNT-1:0][SET_COUNT-1:0][1:0] lru_rank_mem;

  logic rsp_valid_q, rsp_error_q;
  logic [31:0] rsp_insn_q;
  logic [31:3] miss_addr_q;
  logic [6:0] miss_set_q;
  logic [19:0] miss_tag_q;
  logic [2:0] miss_word_q;
  logic [1:0] victim_way_q;
  logic invalidate_done_q, hit_q, miss_q, protocol_error_q;

  logic lookup_hit;
  logic [1:0] lookup_way;
  logic [1:0] lookup_victim;
  logic [6:0] lookup_set;
  logic [19:0] lookup_tag;
  logic [2:0] lookup_word;
  logic found_invalid;
  logic found_lru;

  function automatic logic [31:0] select_word(
    input logic [255:0] line,
    input logic [2:0] word_index
  );
    unique case (word_index)
      3'd0: return line[255:224];
      3'd1: return line[223:192];
      3'd2: return line[191:160];
      3'd3: return line[159:128];
      3'd4: return line[127:96];
      3'd5: return line[95:64];
      3'd6: return line[63:32];
      3'd7: return line[31:0];
    endcase
  endfunction

  assign data_read_enable = fetch_valid_i && fetch_ready_o &&
                            fetch_addr_i[1:0] == 2'b00 && lookup_hit;
  assign data_write_enable = rst_ni && !kill_i && !invalidate_i &&
                             state_q == IC_REFILL_WAIT &&
                             line_rsp_valid_i && !line_rsp_error_i;

  // Reads and writes are mutually exclusive: a hit is accepted only while
  // idle, whereas a refill installs only in REFILL_WAIT. No read-during-write
  // behavior or bypass logic is required. A held response disables all reads.
  always_ff @(posedge clk_i) begin
    if (data_write_enable)
      data_mem[{victim_way_q, miss_set_q}] <= line_rsp_line_i;
    if (data_read_enable)
      data_read_q <= data_mem[{lookup_way, lookup_set}];
  end

  always_comb begin
    lookup_set = fetch_addr_i[11:5];
    lookup_tag = fetch_addr_i[31:12];
    lookup_word = fetch_addr_i[4:2];
    lookup_hit = 1'b0;
    lookup_way = 2'b00;
    for (integer way = 0; way < WAY_COUNT; way++) begin
      if (!lookup_hit && valid_mem[way][lookup_set] &&
          tag_mem[way][lookup_set] == lookup_tag) begin
        lookup_hit = 1'b1;
        lookup_way = 2'(way);
      end
    end

    // An invalid way avoids evicting a valid line.  Once all four ways are
    // valid, strict LRU rank three is selected.
    lookup_victim = 2'b00;
    found_invalid = 1'b0;
    for (integer way = 0; way < WAY_COUNT; way++) begin
      if (!found_invalid && !valid_mem[way][lookup_set]) begin
        lookup_victim = 2'(way);
        found_invalid = 1'b1;
      end
    end
    found_lru = 1'b0;
    if (!found_invalid) begin
      for (integer way = 0; way < WAY_COUNT; way++) begin
        if (!found_lru && lru_rank_mem[way][lookup_set] == 2'd3) begin
          lookup_victim = 2'(way);
          found_lru = 1'b1;
        end
      end
    end
  end

  always_comb begin
    fetch_ready_o = rst_ni && state_q == IC_IDLE && !rsp_valid_q &&
                    !kill_i && !invalidate_i;
    fetch_rsp_valid_o = rst_ni && rsp_valid_q && !kill_i && !invalidate_i;
    fetch_rsp_insn_o = rsp_from_ram_q ? select_word(data_read_q, hit_word_q) :
                                      rsp_insn_q;
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

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= IC_IDLE;
      rsp_valid_q <= 1'b0;
      rsp_error_q <= 1'b0;
      rsp_insn_q <= 32'b0;
      rsp_from_ram_q <= 1'b0;
      hit_word_q <= 3'b0;
      miss_addr_q <= 29'b0;
      miss_set_q <= 7'b0;
      miss_tag_q <= 20'b0;
      miss_word_q <= 3'b0;
      victim_way_q <= 2'b0;
      invalidate_done_q <= 1'b0;
      hit_q <= 1'b0;
      miss_q <= 1'b0;
      protocol_error_q <= 1'b0;
      valid_mem <= '0;
      for (integer way = 0; way < WAY_COUNT; way++) begin
        tag_mem[way] <= '0;
        lru_rank_mem[way] <= {SET_COUNT{2'(way)}};
      end
    end else begin
      invalidate_done_q <= 1'b0;
      hit_q <= 1'b0;
      miss_q <= 1'b0;
      if (rsp_valid_q && fetch_rsp_ready_i)
        rsp_valid_q <= 1'b0;

      if (invalidate_i) begin
        // This is the bounded flash-invalidate command.  A refill already
        // accepted by the line transport is drained but never installed.
        valid_mem <= '0;
        for (integer way = 0; way < WAY_COUNT; way++)
          lru_rank_mem[way] <= {SET_COUNT{2'(way)}};
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
            if (fetch_valid_i && fetch_ready_o) begin
              if (fetch_addr_i[1:0] != 2'b00) begin
                rsp_from_ram_q <= 1'b0;
                rsp_insn_q <= 32'b0;
                rsp_error_q <= 1'b1;
                rsp_valid_q <= 1'b1;
                protocol_error_q <= 1'b1;
              end else if (lookup_hit) begin
                rsp_from_ram_q <= 1'b1;
                hit_word_q <= lookup_word;
                rsp_error_q <= 1'b0;
                rsp_valid_q <= 1'b1;
                hit_q <= 1'b1;
                for (integer way = 0; way < WAY_COUNT; way++) begin
                  if (2'(way) == lookup_way)
                    lru_rank_mem[way][lookup_set] <= 2'd0;
                  else if (lru_rank_mem[way][lookup_set] <
                           lru_rank_mem[lookup_way][lookup_set])
                    lru_rank_mem[way][lookup_set] <=
                      lru_rank_mem[way][lookup_set] + 2'd1;
                end
              end else begin
                miss_addr_q <= fetch_addr_i[31:3];
                miss_set_q <= lookup_set;
                miss_tag_q <= lookup_tag;
                miss_word_q <= lookup_word;
                victim_way_q <= lookup_victim;
                miss_q <= 1'b1;
                state_q <= IC_REFILL_REQUEST;
              end
            end
          end

          IC_REFILL_REQUEST: begin
            if (line_req_valid_o && line_req_ready_i)
              state_q <= IC_REFILL_WAIT;
          end

          IC_REFILL_WAIT: begin
            if (line_rsp_valid_i && line_rsp_ready_o) begin
              rsp_from_ram_q <= 1'b0;
              rsp_error_q <= line_rsp_error_i;
              rsp_valid_q <= 1'b1;
              if (line_rsp_error_i) begin
                rsp_insn_q <= 32'b0;
              end else begin
                tag_mem[victim_way_q][miss_set_q] <= miss_tag_q;
                valid_mem[victim_way_q][miss_set_q] <= 1'b1;
                rsp_insn_q <= select_word(line_rsp_line_i, miss_word_q);
                for (integer way = 0; way < WAY_COUNT; way++) begin
                  if (2'(way) == victim_way_q)
                    lru_rank_mem[way][miss_set_q] <= 2'd0;
                  else if (lru_rank_mem[way][miss_set_q] <
                           lru_rank_mem[victim_way_q][miss_set_q])
                    lru_rank_mem[way][miss_set_q] <=
                      lru_rank_mem[way][miss_set_q] + 2'd1;
                end
              end
              state_q <= IC_IDLE;
            end
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
endmodule
