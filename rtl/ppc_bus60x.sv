// Bounded 64-bit 60x bus master for the scalar data-memory port.
//
// This block deliberately serializes address and data tenures.  It implements
// one outstanding, non-burst, cache-inhibited transaction and normal (late)
// DRTRY read confirmation.  Pin parity, snooping, caches, pipelining and the
// 32-bit data-bus mode are outside this profile.
module ppc_bus60x (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        req_valid_i,
  output logic        req_ready_o,
  input  logic        req_instruction_i,
  input  logic        req_write_i,
  input  logic [31:0] req_addr_i,
  input  logic [31:0] req_wdata_i,
  input  logic [3:0]  req_wstrb_i,
  output logic        rsp_valid_o,
  input  logic        rsp_ready_i,
  output logic [31:0] rsp_rdata_o,
  output logic        rsp_error_o,
  output logic        busy_o,
  output logic        protocol_error_o,

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
  typedef enum logic [3:0] {
    BUS_IDLE,
    BUS_ADDR_REQUEST,
    BUS_ADDR_TRANSFER,
    BUS_ADDR_WAIT,
    BUS_ADDR_RETRY_SAMPLE,
    BUS_RETRY_GAP,
    BUS_DATA_REQUEST,
    BUS_DATA_TRANSFER,
    BUS_DATA_RELEASE,
    BUS_READ_CONFIRM,
    BUS_READ_REPLACEMENT,
    BUS_READ_REPLACEMENT_CONFIRM
  } bus_state_t;

  bus_state_t state_q;

  logic        request_write_q;
  logic        request_instruction_q;
  logic [31:0] request_addr_q;
  logic [31:0] request_wdata_q;
  logic [3:0]  request_wstrb_q;
  logic [2:0]  request_size_q;

  logic [31:0] pending_rdata_q;
  logic        pending_error_q;
  logic        rsp_valid_q;
  logic [31:0] rsp_rdata_q;
  logic        rsp_error_q;
  logic        protocol_error_q;

  // Set on the rising edge that samples AACK/TA.  The opposite-edge flops
  // deassert the owned busy indication for one half clock before its OE drops.
  logic addr_release_pending_q, data_release_pending_q;
  logic addr_release_half_q, data_release_half_q;

  logic request_shape_valid;
  logic [1:0] request_byte_offset;
  logic [2:0] request_size;
  integer byte_index;
  integer lane_index;

  function automatic logic [31:0] selected_read_word(
    input logic [63:0] bus_data,
    input logic        word_half,
    input logic [3:0]  byte_enable
  );
    logic [31:0] result;
    integer core_byte;
    integer bus_lane;
    begin
      result = 32'b0;
      for (core_byte = 0; core_byte < 4; core_byte = core_byte + 1) begin
        bus_lane = (word_half ? 4 : 0) + core_byte;
        if (byte_enable[3-core_byte])
          result[31-(8*core_byte) -: 8] = bus_data[63-(8*bus_lane) -: 8];
      end
      return result;
    end
  endfunction

  always_comb begin
    request_shape_valid = 1'b1;
    request_byte_offset = 2'b00;
    request_size = 3'b000;
    unique case (req_wstrb_i)
      4'b1000: begin request_byte_offset = 2'd0; request_size = 3'd1; end
      4'b0100: begin request_byte_offset = 2'd1; request_size = 3'd1; end
      4'b0010: begin request_byte_offset = 2'd2; request_size = 3'd1; end
      4'b0001: begin request_byte_offset = 2'd3; request_size = 3'd1; end
      4'b1100: begin request_byte_offset = 2'd0; request_size = 3'd2; end
      4'b0011: begin request_byte_offset = 2'd2; request_size = 3'd2; end
      4'b1111: begin request_byte_offset = 2'd0; request_size = 3'd4; end
      default: begin request_shape_valid = 1'b0; request_byte_offset = 2'b00; request_size = 3'b000; end
    endcase
    if (req_addr_i[1:0] != 2'b00)
      request_shape_valid = 1'b0;
    if (req_instruction_i && (req_write_i || (req_wstrb_i != 4'b1111)))
      request_shape_valid = 1'b0;
  end

  always_comb begin
    req_ready_o = rst_ni && (state_q == BUS_IDLE) && !rsp_valid_q;
    rsp_valid_o = rst_ni && rsp_valid_q;
    rsp_rdata_o = rsp_rdata_q;
    rsp_error_o = rsp_error_q;
    protocol_error_o = rst_ni && protocol_error_q;
    busy_o = rst_ni && ((state_q != BUS_IDLE) || rsp_valid_q);

    br_n_o = (rst_ni && (state_q == BUS_ADDR_REQUEST)) ? 1'b0 : 1'b1;

    abb_oe_o = rst_ni && ((state_q == BUS_ADDR_TRANSFER) ||
                          (state_q == BUS_ADDR_WAIT) ||
                          (state_q == BUS_ADDR_RETRY_SAMPLE));
    abb_n_o = addr_release_half_q ? 1'b1 : 1'b0;
    ts_oe_o = abb_oe_o;
    ts_n_o = (state_q == BUS_ADDR_TRANSFER) ? 1'b0 : 1'b1;
    addr_oe_o = abb_oe_o;

    a_o = request_addr_q;
    tt_o = request_write_q ? 5'b00010 : 5'b01010;
    tbst_n_o = 1'b1;
    tsiz_o = request_size_q;
    tc_o = request_instruction_q ? 2'b10 : 2'b00;
    ci_n_o = 1'b0;
    wt_n_o = 1'b1;
    gbl_n_o = 1'b1;
    cse_o = 2'b00;

    dbb_oe_o = rst_ni && ((state_q == BUS_DATA_TRANSFER) ||
                          (state_q == BUS_DATA_RELEASE) ||
                          (state_q == BUS_READ_CONFIRM));
    dbb_n_o = data_release_half_q ? 1'b1 : 1'b0;
    d_oe_o = rst_ni && request_write_q &&
             ((state_q == BUS_DATA_TRANSFER) ||
              (state_q == BUS_DATA_RELEASE));
    d_o = 64'b0;
    for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
      lane_index = (request_addr_q[2] ? 4 : 0) + byte_index;
      if (request_wstrb_q[3-byte_index])
        d_o[63-(8*lane_index) -: 8] = request_wdata_q[31-(8*byte_index) -: 8];
    end
  end

  // Physical ABB/DBB release is modeled at the falling edge.  OE remains
  // asserted until the following rising edge, avoiding a combinational clock
  // dependency while still providing the documented half-clock negation.
  always_ff @(negedge clk_i) begin
    if (!rst_ni) begin
      addr_release_half_q <= 1'b0;
      data_release_half_q <= 1'b0;
    end else begin
      addr_release_half_q <= addr_release_pending_q;
      data_release_half_q <= data_release_pending_q;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= BUS_IDLE;
      request_write_q <= 1'b0;
      request_instruction_q <= 1'b0;
      request_addr_q <= 32'b0;
      request_wdata_q <= 32'b0;
      request_wstrb_q <= 4'b0;
      request_size_q <= 3'b0;
      pending_rdata_q <= 32'b0;
      pending_error_q <= 1'b0;
      rsp_valid_q <= 1'b0;
      rsp_rdata_q <= 32'b0;
      rsp_error_q <= 1'b0;
      protocol_error_q <= 1'b0;
      addr_release_pending_q <= 1'b0;
      data_release_pending_q <= 1'b0;
    end else begin
      if (rsp_valid_q && rsp_ready_i)
        rsp_valid_q <= 1'b0;

      unique case (state_q)
        BUS_IDLE: begin
          addr_release_pending_q <= 1'b0;
          data_release_pending_q <= 1'b0;
          if (req_valid_i && req_ready_o) begin
            if (!request_shape_valid) begin
              rsp_valid_q <= 1'b1;
              rsp_rdata_q <= 32'b0;
              rsp_error_q <= 1'b1;
              protocol_error_q <= 1'b1;
            end else begin
              request_write_q <= req_write_i;
              request_instruction_q <= req_instruction_i;
              request_addr_q <= req_addr_i + {30'b0, request_byte_offset};
              request_wdata_q <= req_wdata_i;
              request_wstrb_q <= req_wstrb_i;
              request_size_q <= request_size;
              pending_rdata_q <= 32'b0;
              pending_error_q <= 1'b0;
              state_q <= BUS_ADDR_REQUEST;
            end
          end
        end

        BUS_ADDR_REQUEST: begin
          if (!bg_n_i && abb_n_i && artry_n_i)
            state_q <= BUS_ADDR_TRANSFER;
        end

        BUS_ADDR_TRANSFER: begin
          if (!aack_n_i) begin
            addr_release_pending_q <= 1'b1;
            state_q <= BUS_ADDR_RETRY_SAMPLE;
          end else begin
            state_q <= BUS_ADDR_WAIT;
          end
        end

        BUS_ADDR_WAIT: begin
          if (!aack_n_i) begin
            addr_release_pending_q <= 1'b1;
            state_q <= BUS_ADDR_RETRY_SAMPLE;
          end
        end

        BUS_ADDR_RETRY_SAMPLE: begin
          addr_release_pending_q <= 1'b0;
          if (!artry_n_i)
            state_q <= BUS_RETRY_GAP;
          else
            state_q <= BUS_DATA_REQUEST;
        end

        BUS_RETRY_GAP: begin
          state_q <= BUS_ADDR_REQUEST;
        end

        BUS_DATA_REQUEST: begin
          if (!dbg_n_i && dbb_n_i && drtry_n_i && artry_n_i)
            state_q <= BUS_DATA_TRANSFER;
        end

        BUS_DATA_TRANSFER: begin
          if (!tea_n_i) begin
            pending_rdata_q <= 32'b0;
            pending_error_q <= 1'b1;
            data_release_pending_q <= 1'b1;
            state_q <= BUS_DATA_RELEASE;
          end else if (!drtry_n_i) begin
            // DRTRY cannot qualify a read before a provisional TA, and has no
            // transaction meaning for a write in this bounded profile.
            if (!request_write_q) begin
              pending_rdata_q <= 32'b0;
              pending_error_q <= 1'b1;
              protocol_error_q <= 1'b1;
              data_release_pending_q <= 1'b1;
              state_q <= BUS_DATA_RELEASE;
            end else if (!ta_n_i) begin
              pending_rdata_q <= 32'b0;
              pending_error_q <= 1'b0;
              data_release_pending_q <= 1'b1;
              state_q <= BUS_DATA_RELEASE;
            end
          end else if (!ta_n_i) begin
            data_release_pending_q <= 1'b1;
            if (request_write_q) begin
              pending_rdata_q <= 32'b0;
              pending_error_q <= 1'b0;
              state_q <= BUS_DATA_RELEASE;
            end else begin
              pending_rdata_q <= selected_read_word(
                d_i, request_addr_q[2], request_wstrb_q);
              pending_error_q <= 1'b0;
              state_q <= BUS_READ_CONFIRM;
            end
          end
        end

        BUS_DATA_RELEASE: begin
          data_release_pending_q <= 1'b0;
          rsp_valid_q <= 1'b1;
          rsp_rdata_q <= pending_rdata_q;
          rsp_error_q <= pending_error_q;
          state_q <= BUS_IDLE;
        end

        BUS_READ_CONFIRM: begin
          data_release_pending_q <= 1'b0;
          if (!tea_n_i) begin
            rsp_valid_q <= 1'b1;
            rsp_rdata_q <= 32'b0;
            rsp_error_q <= 1'b1;
            state_q <= BUS_IDLE;
          end else if (!drtry_n_i) begin
            // DRTRY judges the preceding provisional beat.  TA may identify
            // its replacement on this same edge; retain that new candidate
            // for confirmation on the following edge.
            if (!ta_n_i) begin
              pending_rdata_q <= selected_read_word(
                d_i, request_addr_q[2], request_wstrb_q);
              state_q <= BUS_READ_REPLACEMENT_CONFIRM;
            end else begin
              state_q <= BUS_READ_REPLACEMENT;
            end
          end else begin
            rsp_valid_q <= 1'b1;
            rsp_rdata_q <= pending_rdata_q;
            rsp_error_q <= 1'b0;
            state_q <= BUS_IDLE;
          end
        end

        BUS_READ_REPLACEMENT: begin
          if (!tea_n_i) begin
            rsp_valid_q <= 1'b1;
            rsp_rdata_q <= 32'b0;
            rsp_error_q <= 1'b1;
            state_q <= BUS_IDLE;
          end else if (drtry_n_i) begin
            // Normal-mode DRTRY may negate only after a replacement beat has
            // been identified by TA.
            rsp_valid_q <= 1'b1;
            rsp_rdata_q <= 32'b0;
            rsp_error_q <= 1'b1;
            protocol_error_q <= 1'b1;
            state_q <= BUS_IDLE;
          end else if (!ta_n_i) begin
            pending_rdata_q <= selected_read_word(
              d_i, request_addr_q[2], request_wstrb_q);
            state_q <= BUS_READ_REPLACEMENT_CONFIRM;
          end
        end

        BUS_READ_REPLACEMENT_CONFIRM: begin
          if (!tea_n_i) begin
            rsp_valid_q <= 1'b1;
            rsp_rdata_q <= 32'b0;
            rsp_error_q <= 1'b1;
            state_q <= BUS_IDLE;
          end else if (!drtry_n_i) begin
            // A stream of provisional replacements is legal: the current
            // DRTRY cancels the previous candidate while same-edge TA can
            // install the next one.
            if (!ta_n_i) begin
              pending_rdata_q <= selected_read_word(
                d_i, request_addr_q[2], request_wstrb_q);
              state_q <= BUS_READ_REPLACEMENT_CONFIRM;
            end else begin
              state_q <= BUS_READ_REPLACEMENT;
            end
          end else begin
            rsp_valid_q <= 1'b1;
            rsp_rdata_q <= pending_rdata_q;
            rsp_error_q <= 1'b0;
            state_q <= BUS_IDLE;
          end
        end

        default: begin
          state_q <= BUS_IDLE;
          protocol_error_q <= 1'b1;
        end
      endcase
    end
  end
endmodule
