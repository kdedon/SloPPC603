#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Optional finite four-state CNTLZW record projection check, not full IU conformance."""
from pathlib import Path
import argparse
import hashlib
import re
import shutil
import subprocess
import tempfile

FROZEN_TREE = r"""      function automatic logic [5:0] count_leading_zeros(input logic [31:0] value);
        logic [5:0] count [32];
        logic [5:0] high, low;
        for (int i = 0; i < 32; i++) count[i] = {5'b0, !value[31 - i]};
        for (int level = 0; level < 5; level++) begin
          for (int group = 0; group < (16 >> level); group++) begin
            high = count[2 * group];
            low = count[2 * group + 1];
            if (!high[level]) count[group] = high;
            else if (low[level]) count[group] = high << 1;
            else count[group] = high | low;
          end
        end
        return count[0];
      endfunction"""

FROZEN_CR = r"""  assign result_o.cr0 = !held.ctrl.write_cr_field ? 4'b0 :
    held_compare ? {!compare_gt && !compare_eq, compare_gt, compare_eq,
                    held.ctrl.so_in} : {
    record_value[31],
    !record_value[31] && (record_value != 0),
    record_value == 0,
    held.ctrl.write_ov_so ? final_so : held.ctrl.so_in
  };"""

FROZEN_ARM = r"""            alu_value = {26'b0, leading_zeros};
            record_value = {26'b0, leading_zeros};
          end
"""

ALLOWED_ARM = r"""            alu_value = {26'b0, leading_zeros};
            // The count is zero exactly when the source MSB is one.
            // Unknown MSBs retain the count tree's original predicates.
            case (held.a[31])
              1'b0: record_value = 32'd1;
              1'b1: record_value = 32'd0;
              default: record_value = {26'b0, leading_zeros};
            endcase
          end
"""

PACKAGE_SHA256 = '64897d2f8bff3dbc6e0247f6b89d773eb80627bedfe6397173870a81964d58ee'

NORMALIZED_IU_SHA256 = 'aa233e4410492acc75d4bc011fcccf0f49dbdd21ec0adc82d0140cf6bc32188e'

TEMPLATE = r"""// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
module tb_cntlzw_record_fourstate;
  typedef struct packed {logic write_cr_field,write_ov_so,so_in;} ctrl_t;
  typedef struct packed {ctrl_t ctrl;logic[31:0]a;} held_t;
  held_t held;
  logic held_compare,compare_gt,compare_eq,final_so;
  logic[5:0]leading_zeros,candidate_count;
  logic[31:0]alu_value,record_value,old_record,new_record;
  logic[3:0]q,old_cr;
  logic states[4];
  integer checks,operands,known_counts,msb0_changed,msb1,x_fallback,z_fallback;
@REFERENCE_TREE@
@CANDIDATE_TREE@
  task automatic check(input logic[31:0] value);
    held.a=value; leading_zeros=count_leading_zeros(value);
    candidate_count=count_leading_zeros_candidate(value);
@REFERENCE_ARM@
    old_record=record_value;
@CANDIDATE_ARM@
    new_record=record_value;
    assert(candidate_count===leading_zeros) else $fatal(1,"GPR count changed");
    operands++;
    assert(alu_value==={26'b0,candidate_count}) else $fatal(1,"GPR count changed");
    if(value[31]===1'b0 && leading_zeros>6'd1 && old_record!==new_record) msb0_changed++;
    if(value[31]===1'b1) begin
      assert(leading_zeros===6'd0) else $fatal(1,"MSB1 count notzero");msb1++;
    end
    if(value[31]===1'bx || value[31]===1'bz) begin
      assert(new_record===old_record) else $fatal(1,"unknown MSB fallback changed");
      if(value[31]===1'bx) x_fallback++;else z_fallback++;
    end
    for(int w=0;w<4;w++) for(int o=0;o<4;o++)
      for(int so=0;so<4;so++) for(int fs=0;fs<4;fs++) begin
        held.ctrl.write_cr_field=states[w];held.ctrl.write_ov_so=states[o];
        held.ctrl.so_in=states[so];final_so=states[fs];
        record_value=old_record;
@REFERENCE_CR@
        old_cr=q;record_value=new_record;
@CANDIDATE_CR@
        assert(q===old_cr) else $fatal(1,"CR mismatch A=%b count=%b old=%b new=%b",value,leading_zeros,old_cr,q);
        checks++;
      end
  endtask
  initial begin
    logic[31:0] v;
    checks=0;operands=0;known_counts=0;msb0_changed=0;msb1=0;x_fallback=0;z_fallback=0;
    states[0]=0;states[1]=1;states[2]=1'bx;states[3]=1'bz;
    held_compare=0;compare_gt=0;compare_eq=0;
    assert($isunknown(states[2]) && $isunknown(states[3])) else $fatal(1,"requires fourstate");
    for(int leading=0;leading<=32;leading++) begin
      v=leading==32?32'b0:32'h80000000>>leading;
      assert(count_leading_zeros(v)===6'(leading)) else $fatal(1,"independent leading count mismatch %0d",leading);
      known_counts++;check(v);
    end
    for(int top=0;top<4;top++) for(int bitpos=0;bitpos<31;bitpos++)
      for(int lower=0;lower<4;lower++) begin
        v='0;v[31]=states[top];v[bitpos]=states[lower];check(v);
        v='1;v[31]=states[top];v[bitpos]=states[lower];check(v);
      end
    for(int top=0;top<4;top++) for(int lower=0;lower<4;lower++) begin
      v={32{states[lower]}};v[31]=states[top];check(v);
    end
    assert(checks==266496 && operands==1041 && known_counts==33) else $fatal(1,"matrix incomplete");
    assert(msb0_changed>0 && msb1>0 && x_fallback>0 && z_fallback>0) else $fatal(1,"missing source-arm coverage");
    $display("coverage known33=%0d MSB0surrogate=%0d MSB1=%0d Xfallback=%0d Zfallback=%0d",known_counts,msb0_changed,msb1,x_fallback,z_fallback);
    $display("PASS extracted CNTLZW/CR finite fourstate: %0d checks",checks);$finish;
  end
endmodule
`default_nettype wire
"""

def extract(pattern, source):
    found = re.findall(pattern, source, re.S)
    if len(found) != 1:
        raise ValueError("expected exactly one source equation: " + pattern)
    return found[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=Path(__file__).resolve().parents[1] / "build/cntlzw-record-proof")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    package = (repo / "rtl/ppc_pkg.sv").read_bytes()
    if hashlib.sha256(package).hexdigest() != PACKAGE_SHA256:
        raise ValueError("package changed; review fixture field widths and opcode/type semantics")
    package_text = package.decode()
    # The reduced fixture's fields must retain the production declarations.
    ctrl = extract(r"  typedef struct packed \{([^{}]*?)\} iu_ctrl_t;", package_text)
    issue = extract(r"  typedef struct packed \{([^{}]*?)\} issue_packet_t;", package_text)
    for field in ("write_cr_field", "write_ov_so", "so_in"):
        if len(re.findall(r"^    logic " + field + r";\s*$", ctrl, re.M)) != 1:
            raise ValueError("fixture requires one-bit iu_ctrl_t." + field)
    if not re.search(r"^    iu_ctrl_t ctrl;\s*$", issue, re.M):
        raise ValueError("issue packet no longer contains iu_ctrl_t ctrl")
    if not re.search(r"^    logic \[31:0\] a;\s*$", issue, re.M):
        raise ValueError("fixture requires 32-bit issue_packet_t.a")
    source = (repo / "rtl/ppc_iu.sv").read_text()
    tree = extract(r"      function automatic logic \[5:0\] count_leading_zeros.*?      endfunction", source)
    cr = extract(r"  assign result_o.cr0 =.*?\n  };", source)
    arm = extract(r"          ALU_CNTLZW: begin\n(.*?)          ALU_EXTSB: begin", source)
    if tree != FROZEN_TREE or cr != FROZEN_CR or arm != ALLOWED_ARM:
        raise ValueError("IU tree/CR/CNT arm differs from the reviewed projection")
    original = source.replace(arm, FROZEN_ARM, 1)
    if hashlib.sha256(original.encode()).hexdigest() != NORMALIZED_IU_SHA256:
        raise ValueError("IU has changes outside the allowed record-only arm; review and refresh frozen contract")
    if re.findall(r"            alu_value = .*?;", arm) != re.findall(r"            alu_value = .*?;", FROZEN_ARM):
        raise ValueError("GPR count assignment changed")
    replacements = {
        "@REFERENCE_TREE@": FROZEN_TREE,
        "@CANDIDATE_TREE@": tree.replace("count_leading_zeros", "count_leading_zeros_candidate"),
        "@REFERENCE_ARM@": FROZEN_ARM.rstrip()[:-3],
        "@CANDIDATE_ARM@": arm.rstrip()[:-3].replace("leading_zeros", "candidate_count"),
        "@REFERENCE_CR@": FROZEN_CR.replace("assign result_o.cr0 =", "q ="),
        "@CANDIDATE_CR@": cr.replace("assign result_o.cr0 =", "q ="),
    }
    fixture = TEMPLATE
    for key, value in replacements.items():
        fixture = fixture.replace(key, value)
    if re.search(r"@[A-Z_]+@", fixture):
        raise ValueError("unexpanded fixture placeholder")
    for executable in ("iverilog", "vvp"):
        if shutil.which(executable) is None:
            raise ValueError("optional proof requires " + executable)
    args.build_dir.mkdir(parents=True, exist_ok=True)
    # Remove only this invocation's owned fixture/vvp after both processes exit.
    with tempfile.TemporaryDirectory(prefix="run-", dir=args.build_dir) as run:
        run = Path(run)
        sv = run / "tb_cntlzw_record_fourstate.sv"
        output = run / "proof.vvp"
        sv.write_text(fixture)
        subprocess.run(["iverilog", "-g2012", "-s", "tb_cntlzw_record_fourstate", "-o", str(output), str(sv)], check=True, timeout=30)
        subprocess.run(["vvp", str(output)], check=True, timeout=30)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise SystemExit("CNTLZW record proof failed: " + str(error))
