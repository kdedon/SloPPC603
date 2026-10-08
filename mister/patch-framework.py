#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Patch the fetched MiSTer framework for this core.

sys_top's audio_out is placed only when MISTER_DISABLE_AUDIO is undefined;
otherwise its outputs are tied low. This core produces no audio, and the block
costs about 700 ALMs the core needs to fit. Usage: patch-framework.py <sys_top.v>
"""
import sys

path = sys.argv[1]
text = open(path).read()
head = "audio_out audio_out\n(\n"
tail = "\t.spdif(spdif)\n);\n"
if text.count(head) != 1 or text.count(tail) != 1:
    sys.exit("patch-framework: audio_out instance not found exactly once")
off = """`ifdef MISTER_DISABLE_AUDIO
assign HDMI_SCLK  = 1'b0;
assign HDMI_LRCLK = 1'b0;
assign HDMI_I2S   = 1'b0;
assign spdif      = 1'b0;
`ifndef MISTER_DUAL_SDRAM
assign analog_l   = 1'b0;
assign analog_r   = 1'b0;
`endif
`else
"""
text = text.replace(head, off + head).replace(tail, tail + "`endif\n")
open(path, "w").write(text)
