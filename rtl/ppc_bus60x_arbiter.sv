// Fair single-entry router from the core's separate instruction/data channels
// to one scalar 60x adapter request/response channel.
module ppc_bus60x_arbiter (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        imem_req_valid_i,
  output logic        imem_req_ready_o,
  input  logic [31:0] imem_req_addr_i,
  output logic        imem_rsp_valid_o,
  input  logic        imem_rsp_ready_i,
  output logic [31:0] imem_rsp_insn_o,

  input  logic        dmem_req_valid_i,
  output logic        dmem_req_ready_o,
  input  logic        dmem_req_write_i,
  input  logic [31:0] dmem_req_addr_i,
  input  logic [31:0] dmem_req_wdata_i,
  input  logic [3:0]  dmem_req_wstrb_i,
  output logic        dmem_rsp_valid_o,
  input  logic        dmem_rsp_ready_i,
  output logic [31:0] dmem_rsp_rdata_o,
  output logic        dmem_rsp_error_o,

  output logic        bus_req_valid_o,
  input  logic        bus_req_ready_i,
  output logic        bus_req_instruction_o,
  output logic        bus_req_write_o,
  output logic [31:0] bus_req_addr_o,
  output logic [31:0] bus_req_wdata_o,
  output logic [3:0]  bus_req_wstrb_o,
  input  logic        bus_rsp_valid_i,
  output logic        bus_rsp_ready_o,
  input  logic [31:0] bus_rsp_rdata_i,
  input  logic        bus_rsp_error_i,

  output logic        ifetch_error_o,
  output logic        busy_o
);
  typedef enum logic [1:0] {
    ROUTER_IDLE,
    ROUTER_OFFER,
    ROUTER_RESPONSE,
    ROUTER_IFETCH_FATAL
  } router_state_t;

  router_state_t state_q;
  logic owner_instruction_q;
  logic last_grant_data_q;
  logic request_instruction_q;
  logic request_write_q;
  logic [31:0] request_addr_q;
  logic [31:0] request_wdata_q;
  logic [3:0] request_wstrb_q;
  logic ifetch_error_q;
  logic choose_instruction, choose_data;

  always_comb begin
    choose_instruction = 1'b0;
    choose_data = 1'b0;
    if (rst_ni && (state_q == ROUTER_IDLE) && !ifetch_error_q) begin
      if (imem_req_valid_i && dmem_req_valid_i) begin
        // Grant the side opposite the most recent accepted request.
        choose_instruction = last_grant_data_q;
        choose_data = !last_grant_data_q;
      end else begin
        choose_instruction = imem_req_valid_i;
        choose_data = dmem_req_valid_i;
      end
    end

    imem_req_ready_o = choose_instruction;
    dmem_req_ready_o = choose_data;

    bus_req_valid_o = rst_ni && (state_q == ROUTER_OFFER);
    bus_req_instruction_o = request_instruction_q;
    bus_req_write_o = request_write_q;
    bus_req_addr_o = request_addr_q;
    bus_req_wdata_o = request_wdata_q;
    bus_req_wstrb_o = request_wstrb_q;

    imem_rsp_valid_o = 1'b0;
    imem_rsp_insn_o = bus_rsp_rdata_i;
    dmem_rsp_valid_o = 1'b0;
    dmem_rsp_rdata_o = bus_rsp_rdata_i;
    dmem_rsp_error_o = bus_rsp_error_i;
    bus_rsp_ready_o = 1'b0;

    if (rst_ni && (state_q == ROUTER_RESPONSE)) begin
      if (owner_instruction_q) begin
        if (bus_rsp_valid_i && bus_rsp_error_i) begin
          // Consume an instruction error without manufacturing an instruction
          // response.  The state machine enters a reset-only transport stop.
          bus_rsp_ready_o = 1'b1;
        end else begin
          imem_rsp_valid_o = bus_rsp_valid_i;
          bus_rsp_ready_o = imem_rsp_ready_i;
        end
      end else begin
        dmem_rsp_valid_o = bus_rsp_valid_i;
        bus_rsp_ready_o = dmem_rsp_ready_i;
      end
    end

    ifetch_error_o = rst_ni && ifetch_error_q;
    busy_o = rst_ni && (state_q != ROUTER_IDLE);
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= ROUTER_IDLE;
      owner_instruction_q <= 1'b0;
      last_grant_data_q <= 1'b1;
      request_instruction_q <= 1'b0;
      request_write_q <= 1'b0;
      request_addr_q <= 32'b0;
      request_wdata_q <= 32'b0;
      request_wstrb_q <= 4'b0;
      ifetch_error_q <= 1'b0;
    end else begin
      unique case (state_q)
        ROUTER_IDLE: begin
          if (choose_instruction) begin
            owner_instruction_q <= 1'b1;
            last_grant_data_q <= 1'b0;
            request_instruction_q <= 1'b1;
            request_write_q <= 1'b0;
            request_addr_q <= imem_req_addr_i;
            request_wdata_q <= 32'b0;
            request_wstrb_q <= 4'b1111;
            state_q <= ROUTER_OFFER;
          end else if (choose_data) begin
            owner_instruction_q <= 1'b0;
            last_grant_data_q <= 1'b1;
            request_instruction_q <= 1'b0;
            request_write_q <= dmem_req_write_i;
            request_addr_q <= dmem_req_addr_i;
            request_wdata_q <= dmem_req_wdata_i;
            request_wstrb_q <= dmem_req_wstrb_i;
            state_q <= ROUTER_OFFER;
          end
        end

        ROUTER_OFFER: begin
          if (bus_req_valid_o && bus_req_ready_i)
            state_q <= ROUTER_RESPONSE;
        end

        ROUTER_RESPONSE: begin
          if (bus_rsp_valid_i && bus_rsp_ready_o) begin
            if (owner_instruction_q && bus_rsp_error_i) begin
              ifetch_error_q <= 1'b1;
              state_q <= ROUTER_IFETCH_FATAL;
            end else begin
              state_q <= ROUTER_IDLE;
            end
          end
        end

        ROUTER_IFETCH_FATAL: begin
          state_q <= ROUTER_IFETCH_FATAL;
        end

        default: begin
          ifetch_error_q <= 1'b1;
          state_q <= ROUTER_IFETCH_FATAL;
        end
      endcase
    end
  end
endmodule
