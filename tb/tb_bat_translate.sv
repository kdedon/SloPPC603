module tb_bat_translate;
  logic valid, instruction, write_access, ir, dr, pr;
  logic [31:0] ea;
  logic [3:0][31:0] batu, batl;
  logic allow_access, bypass, hit, miss, protection, guarded_fault;
  logic config_error, invalid_input, overlap;
  logic [3:0] invalid_entry, match_bits;
  logic [1:0] hit_index, pp;
  logic [31:0] pa;
  logic [3:0] wimg;
  integer checks = 0;
  logic [31:0] random_state = 32'h603e1234;
  typedef struct packed {
    logic [8:0] status;
    logic [3:0] bad;
    logic [3:0] matched;
    logic [1:0] index;
    logic [31:0] physical;
    logic [3:0] attributes;
    logic [1:0] protection;
  } observation_t;
  observation_t actual;
  assign actual = {allow_access, bypass, hit, miss, protection, guarded_fault,
                   config_error, invalid_input, overlap, invalid_entry, match_bits,
                   hit_index, pa, wimg, pp};

  ppc_bat_translate dut (
    .valid_i(valid), .instruction_i(instruction), .write_i(write_access),
    .ea_i(ea), .msr_ir_i(ir), .msr_dr_i(dr), .msr_pr_i(pr),
    .batu_i(batu), .batl_i(batl), .allow_o(allow_access), .bypass_o(bypass),
    .bat_hit_o(hit), .bat_miss_o(miss), .protection_fault_o(protection),
    .guarded_fault_o(guarded_fault), .config_error_o(config_error),
    .invalid_input_o(invalid_input), .invalid_entry_o(invalid_entry),
    .overlap_o(overlap), .match_o(match_bits), .hit_index_o(hit_index),
    .pa_o(pa), .wimg_o(wimg), .pp_o(pp)
  );

  // Independent arithmetic oracle: integer intervals and modulo offsets,
  // rather than the RTL address-mask match/OR/overlap implementation.
  function automatic observation_t expected;
    observation_t e;
    longint unsigned size [4], base [4], physical_base [4];
    logic [3:0] enabled;
    logic bad_input, collide, denied, guarded;
    integer chosen;
    e = '0;
    enabled = '0;
    collide = 1'b0;
    chosen = -1;
    bad_input = instruction && write_access;
    denied = 1'b0;
    guarded = 1'b0;
    for (integer i = 0; i < 4; i++) begin
      size[i] = 0;
      base[i] = (64'(batu[i]) / 64'h20000) * 64'h20000;
      physical_base[i] = (64'(batl[i]) / 64'h20000) * 64'h20000;
      enabled[i] = batu[i][1:0] != 0;
      for (integer power = 0; power < 12; power++)
        if (((batu[i] / 4) % 2048) + 1 == (32'd1 << power))
          size[i] = 64'd131072 << power;
      if (enabled[i]) begin
        e.bad[i] = size[i] == 0 || (batu[i] & 32'h0001e000) != 0 ||
                   (batl[i] & 32'h0001ff84) != 0 ||
                   (instruction && (batl[i] & 32'h40) != 0);
        if (size[i] != 0)
          e.bad[i] |= base[i] % size[i] != 0 || physical_base[i] % size[i] != 0;
      end
    end
    for (integer i = 0; i < 4; i++)
      for (integer j = i + 1; j < 4; j++)
        if (enabled[i] && enabled[j] && !e.bad[i] && !e.bad[j] &&
            (batu[i][1:0] & batu[j][1:0]) != 0 &&
            base[i] < base[j] + size[j] && base[j] < base[i] + size[i])
          collide = 1'b1;
    e.status[0] = collide;
    e.status[1] = bad_input;
    e.status[2] = (|e.bad) || collide || bad_input;
    if (!e.status[2]) begin
      if (!(instruction ? ir : dr)) begin
        e.status[8:7] = 2'b11;
        e.physical = ea;
        e.attributes = instruction ? 4'h1 : 4'h3;
      end else begin
        for (integer i = 0; i < 4; i++)
          if ((pr ? batu[i][0] : batu[i][1]) &&
              64'(ea) >= base[i] && 64'(ea) < base[i] + size[i]) begin
            e.matched[i] = 1'b1;
            chosen = i;
          end
        if (chosen < 0)
          e.status[5] = 1'b1;
        else begin
          e.status[6] = 1'b1;
          e.index = 2'(chosen);
          e.protection = 2'(batl[chosen] % 4);
          e.attributes = 4'((batl[chosen] / 8) % 16);
          case (e.protection)
            2'd0: denied = 1'b1;
            2'd1, 2'd3: denied = write_access;
            2'd2: denied = 1'b0;
          endcase
          guarded = instruction && e.attributes[0];
          e.status[4] = denied;
          e.status[3] = guarded;
          e.status[8] = !denied && !guarded;
          if (e.status[8])
            e.physical = 32'(physical_base[chosen] + (64'(ea) - base[chosen]));
        end
      end
    end
    if (!valid) e = '0;
    return e;
  endfunction

  task automatic check(input logic ok, input string label_text);
    checks++;
    if (!ok)
      $fatal(1, "%s check=%0d ea=%08x I/W/IR/DR/PR=%b%b%b%b%b U=%h L=%h actual=%h expected=%h",
             label_text, checks, ea, instruction, write_access, ir, dr, pr,
             batu, batl, actual, expected());
  endtask

  task automatic verify(input string label_text);
    #1;
    check(actual == expected(), label_text);
    check(!(allow_access && (miss || protection || guarded_fault || config_error)),
          "fault/miss never grants physical access");
    check(allow_access || pa == 0, "denied PA is zero");
  endtask

  task automatic defaults;
    valid = 1'b1;
    instruction = 1'b0;
    write_access = 1'b0;
    ir = 1'b1;
    dr = 1'b1;
    pr = 1'b0;
    ea = 0;
    batu = '0;
    batl = '0;
  endtask

  function automatic logic [31:0] random32;
    random_state = random_state * 32'd1664525 + 32'd1013904223;
    return random_state;
  endfunction

  initial begin : run
    logic [31:0] size_bytes, offset, base_e, base_p;
    logic [4:0] sample;
    integer slot, power;
    string vector_path;
    integer fd, fields, vector_count;
    logic [5:0] controls;
    observation_t vector_expected;
    defaults();
    // Literal 128 KiB supervisor RW mapping and endian-neutral byte offset.
    batu[2] = 32'h80000002;
    batl[2] = 32'h1000002a;
    ea = 32'h80012345;
    verify("literal 128KiB relocation");
    check(allow_access && hit && hit_index == 2 && pa == 32'h10012345 &&
          wimg == 4'h5 && pp == 2, "literal PA/index/WIMG/PP");
    ea = 32'h80020000;
    verify("exclusive upper boundary");
    check(miss && !hit, "literal boundary misses, never identity maps");
    ea = 32'h80000000;
    pr = 1;
    verify("Vs does not apply in user mode");
    check(miss && !protection, "privilege validity miss is not protection fault");
    pr = 0;
    batl[2] = 32'h10000001;
    write_access = 1;
    verify("literal read-only store");
    check(hit && protection && !allow_access, "PP01 store fault");
    instruction = 1;
    write_access = 0;
    batl[2] = 32'h1000000a;
    verify("603e IBAT guarded fault");
    check(hit && guarded_fault && !protection, "specific G denial");
    ir = 0;
    verify("real instruction bypass ignores guarded protection");
    check(bypass && allow_access && pa == ea && wimg == 1, "literal real I mode");
    instruction = 0;
    dr = 0;
    verify("real data attributes");
    check(bypass && wimg == 3, "literal real D mode");

    // All twelve legal sizes, all four slots, both sides of boundaries,
    // near-4GiB ranges, every privilege/protection combination.
    for (integer p = 0; p < 12; p++) begin
      size_bytes = 32'h20000 << p;
      for (integer s = 0; s < 4; s++) begin
        for (integer edge_case = 0; edge_case < 6; edge_case++) begin
          defaults();
          base_e = 32'hf0000000;
          base_p = 32'h40000000;
          batu[s] = base_e | (((32'd1 << p) - 1) << 2) | 3;
          batl[s] = base_p | 2;
          case (edge_case)
            0: ea = base_e - 1;
            1: ea = base_e;
            2: ea = base_e + 1;
            3: ea = base_e + size_bytes / 2;
            4: ea = base_e + size_bytes - 1;
            default: ea = base_e + size_bytes;
          endcase
          verify("all sizes/slots/boundaries");
        end
      end
      for (integer v = 0; v < 4; v++)
        for (integer mode = 0; mode < 2; mode++)
          for (integer prot = 0; prot < 4; prot++)
            for (integer operation = 0; operation < 3; operation++) begin
              defaults();
              batu[0] = 32'h80000000 | (((32'd1 << p) - 1) << 2) | 32'(v);
              batl[0] = 32'h10000000 | 32'(prot);
              ea = 32'h80000001;
              pr = 1'(mode);
              instruction = operation == 2;
              write_access = operation == 1;
              verify("all privilege validity/PP/read-write-fetch combinations");
            end
    end

    // Exhaust all 2048 BL values, both reserved-register regions, and base
    // alignment errors. Inactive register garbage remains ignored.
    for (integer bl = 0; bl < 2048; bl++) begin
      defaults();
      batu[0] = (32'(bl) << 2) | 3;
      batl[0] = 2;
      verify("every BL encoding");
    end
    for (integer bit_index = 0; bit_index < 32; bit_index++) begin
      defaults();
      batu[0] = 32'h80000003;
      batl[0] = 32'h10000002;
      batu[0] |= 32'd1 << bit_index;
      ea = 32'h80000000;
      verify("upper single-bit mutations");
      batu[0] = 32'h80000003;
      batl[0] |= 32'd1 << bit_index;
      verify("lower single-bit mutations");
    end
    defaults();
    batu[0] = 32'h80020007;
    batl[0] = 32'h10000002;
    verify("unaligned effective 256KiB base");
    check(config_error && invalid_entry == 1, "reject malformed BEPI");
    batu[0] = 32'h80000007;
    batl[0] = 32'h10020002;
    verify("unaligned physical 256KiB base");
    check(config_error && invalid_entry == 1, "reject malformed BRPN");
    batu[0] = 32'hfffffffc;
    batl[0] = 32'hffffffff;
    verify("inactive garbage is ignored");
    check(!config_error && miss, "inactive entries do not poison bank");

    // Overlap includes containment and privilege intersections even away
    // from the request, with translation disabled. Adjacent ranges are legal.
    defaults();
    batu[0] = 32'h80000007;
    batu[1] = 32'h80020003;
    batl[0] = 32'h10000002;
    batl[1] = 32'h20000002;
    ea = 0;
    dr = 0;
    verify("overlap independent of current address/translation enable");
    check(config_error && overlap && !bypass, "local overlap rejection");
    batu[0][1:0] = 2;
    batu[1][1:0] = 1;
    dr = 1;
    ea = 32'h80020055;
    verify("disjoint privilege mappings supervisor");
    check(allow_access && pa == 32'h10020055, "supervisor interval selection");
    pr = 1;
    verify("disjoint privilege mappings user");
    check(allow_access && pa == 32'h20000055, "user interval selection");
    batu[1] = 32'h80040003;
    verify("adjacent effective intervals");
    check(!config_error, "exclusive range end permits adjacency");

    defaults();
    batu[0] = 32'h80000003;
    batu[1] = 32'h90000003;
    batl[0] = 32'h10000002;
    batl[1] = 32'h10000002;
    ea = 32'h80005678;
    verify("first effective alias to shared physical range");
    check(allow_access && pa == 32'h10005678 && hit_index == 0,
          "literal first physical alias");
    ea = 32'h90005678;
    verify("second effective alias to shared physical range");
    check(allow_access && pa == 32'h10005678 && hit_index == 1 && !overlap,
          "physical aliases do not constitute effective-range overlap");

    for (integer attrs = 0; attrs < 16; attrs++)
      for (integer kind = 0; kind < 2; kind++) begin
        defaults();
        instruction = 1'(kind);
        batu[0] = 3;
        batl[0] = (32'(attrs) << 3) | 2;
        verify("all WIMG profiles and instruction-specific W/G handling");
      end
    defaults();
    instruction = 1;
    write_access = 1;
    ir = 0;
    verify("instruction-write invalid input even in real mode");
    check(config_error && invalid_input, "invalid transaction combination rejected");
    valid = 0;
    batu = '1;
    batl = '1;
    verify("idle suppresses all outputs");
    check(actual == 0, "valid gating");

    for (integer iteration = 0; iteration < 2000; iteration++) begin
      defaults();
      sample = 5'(random32());
      instruction = sample[0];
      write_access = !instruction && sample[1];
      pr = sample[2]; ir = sample[3]; dr = sample[4];
      for (integer s = 0; s < 4; s++) begin
        power = int'(random32() % 12);
        size_bytes = 32'h20000 << power;
        base_e = (random32() / size_bytes) * size_bytes;
        base_p = (random32() / size_bytes) * size_bytes;
        batu[s] = base_e | (((32'd1 << power) - 1) << 2) | (random32() % 4);
        batl[s] = base_p | (random32() % 128 & 32'h7b);
      end
      slot = int'(random32() % 4);
      size_bytes = (((batu[slot] >> 2) & 2047) + 1) * 131072;
      offset = random32() % size_bytes;
      ea = (batu[slot] / 131072) * 131072 + offset;
      verify("seeded interval/modulo crosscheck");
    end

    // Optional independent external corpus. Each line: controls[5:0] hex
    // {valid,I,write,IR,DR,PR}, EA, U0 L0 U1 L1 U2 L2 U3 L3,
    // expected packed observation (57 bits; field order documented above).
    vector_count = 0;
    if ($value$plusargs("VECTORS=%s", vector_path)) begin
      fd = $fopen(vector_path, "r");
      check(fd != 0, "open external vector file");
      while (!$feof(fd)) begin
        fields = $fscanf(fd, "%h %h %h %h %h %h %h %h %h %h %h\n",
                         controls, ea, batu[0], batl[0], batu[1], batl[1],
                         batu[2], batl[2], batu[3], batl[3], vector_expected);
        check(fields == 11, "external vector row has eleven hex fields");
        {valid, instruction, write_access, ir, dr, pr} = controls;
        #1;
        check(actual == vector_expected, "independent external vector");
        vector_count++;
      end
      $fclose(fd);
      check(vector_count > 0, "external corpus is nonempty");
    end
    $display("PASS: BAT translation %0d checks, external vectors=%0d", checks, vector_count);
    $finish;
  end
endmodule
