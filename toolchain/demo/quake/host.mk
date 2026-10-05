# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Host build of the Quake smoke run (quake/hostmain.c), the reference the
# processor's smoke frames are compared with. quakegeneric needs a 32-bit
# target; SSE arithmetic keeps single and double rounding as on PowerPC.
# Run from toolchain/: make -f demo/quake/host.mk [QUAKE_SMOKE_FRAMES=n]; it
# writes build/demo/quake/host/<n>/. 0
# plays one whole timedemo pass with the real clock.
QUAKE_SMOKE_FRAMES ?= 8
HOSTCC32 ?= gcc -m32
QG := build/demo/src/quakegeneric/source
QH := build/demo/quake/host/$(QUAKE_SMOKE_FRAMES)
include demo/quake/engine.mk

$(QH)/quake-host: $(addprefix $(QG)/,$(addsuffix .c,$(QUAKE_ENGINE))) demo/quake/qport.c \
		demo/quake/hostmain.c demo/quake/qport.h demo/quake/host.mk
	mkdir -p $(QH)/id1
	$(HOSTCC32) -O1 -w -msse2 -mfpmath=sse -ffp-contract=off -fsigned-char -fno-strict-aliasing \
	  $(if $(filter-out 0,$(QUAKE_SMOKE_FRAMES)),-DQUAKE_SMOKE_FRAMES=$(QUAKE_SMOKE_FRAMES)) \
	  -I$(QG) -Idemo/quake $(filter %.c,$^) -lm -o $@
	ln -sf $(abspath build/demo/pak/pak0.pak) $(QH)/id1/pak0.pak
	cd $(QH) && ./quake-host > host.log
