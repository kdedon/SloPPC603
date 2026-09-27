`default_nettype none
module ss_fpu_candidate (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        req,
    output logic        rdy,
    output logic        fin,
    input  logic        flush,
    input  logic        stall,
    input  logic [3:0]  fop,
    input  logic        sdi,
    input  logic        sdo,
    input  logic [1:0]  rd,
    input  logic [63:0] fs1,
    input  logic [63:0] fs2,
    output logic [63:0] fd,
    output logic [1:0]  fcc,
    output logic [4:0]  exc,
    output logic        unf,
    output logic [53:0] raw_significand,
    output logic [12:0] raw_exponent,
    output logic        raw_sign,
    output logic        round_guard,
    output logic        round_sticky,
    output logic        round_increment,
    output logic [3:0] invalid_causes
);
    logic idle_unused;

    fpu_calc arithmetic (
        .clk(clk), .reset_n(reset_n), .req(req), .rdy(rdy), .fin(fin),
        .flush(flush), .stall(stall), .idle(idle_unused),
        .fop(fop), .sdi(sdi), .sdo(sdo), .rd(rd), .tem(5'b00000),
        .fs1(fs1), .fs2(fs2), .fd(fd), .fcc(fcc), .exc(exc), .unf(unf),
        .raw_significand(raw_significand), .raw_exponent(raw_exponent),
        .raw_sign(raw_sign), .round_guard(round_guard),
        .round_sticky(round_sticky), .round_increment(round_increment),
        .invalid_causes(invalid_causes)
    );
endmodule
`default_nettype wire
