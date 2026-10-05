# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Quake timedemo images (docs/BENCHMARKS.md#quake), included by demo/Makefile.
# quakegeneric and the Amiga PowerPC sources come from demo/fetch-quake.sh;
# musl's libm and the soft-float routines from fetch-benchmarks.sh. Each
# variant builds the engine once and links the looping benchmark and a smoke
# image that stops at timedemo frame QUAKE_SMOKE_FRAMES with a frame checksum:
#   be     hard float, big-endian, the PowerPC assembly renderer
#   le     hard float, little-endian, C
#   sf     soft float, big-endian, C
#   bec    hard float, big-endian, C (smoke only, for comparison)
QUAKE_SMOKE_FRAMES ?= 8
QG := $(SRC)/quakegeneric/source
AQ := $(SRC)/amigaquake/Quake
QM := $(OUT)/quake
QUAKE_VARIANTS := be le sf bec
QUAKE_ENGINE := cd_null chase cl_demo cl_input cl_main cl_parse cl_tent cmd common console crc cvar \
	d_edge d_fill d_init d_modech d_part d_polyse d_scan d_sky d_sprite d_surf d_vars d_zpoint \
	draw host_cmd host in_null keys mathlib menu model net_loop net_main net_none net_vcr nonintel \
	pr_cmds pr_edict pr_exec r_aclip r_alias r_bsp r_draw r_edge r_efrag r_light r_main r_misc \
	r_part r_sky r_sprite r_surf r_vars sbar screen snd_null sv_main sv_move sv_phys sv_user view \
	wad world zone quakegeneric
QUAKE_ASM := d_scanPPC r_surfPPC d_polysetPPC d_edgePPC r_edgePPC r_drawPPC r_aliasPPC r_aclipPPC \
	d_skyPPC d_surfPPC mathlibPPC r_miscPPC r_bspPPC r_lightPPC fconstPPC
QUAKE_LIBM := sin cos __sin __cos __rem_pio2 __rem_pio2_large pow pow_data exp_data sqrt sqrt_data \
	floor ceil floorf ceilf sqrtf tan __tan atan atan2 scalbn __math_oflow __math_uflow __math_xflow \
	__math_invalid __math_invalidf __math_divzero

quake_endian = $(if $(filter le,$(1)),little,big)
quake_float = $(if $(filter sf,$(1)),soft,hard)
QUAKE_ARCH = -mcpu=603e -m32 -m$(call quake_float,$(1))-float -m$(call quake_endian,$(1))-endian \
	-msdata=none -mlong-double-64
QUAKE_INC = -nostdinc -isystem $(GCC_INC) -Idemo/quake/include -Idemo/doom/include -Idemo/quake \
	-Idemo/doom
# Signed char as on the x86 host the reference frame comes from.
QUAKE_CFLAGS = -O2 -g0 $(call QUAKE_ARCH,$(1)) -fsigned-char -fno-strict-aliasing -fno-stack-protector \
	-fno-pic -fno-pie -fno-ident -ffunction-sections -fdata-sections -ffile-prefix-map=$(CURDIR)=. \
	$(QUAKE_INC) -DPLAT_WAD_NAME='"pak0.pak"' -DPLAT_WAD_MAX=0x02800000u
QUAKE_LIBM_CFLAGS = -O2 -g0 $(call QUAKE_ARCH,$(1)) -fno-pic -fno-ident -ffunction-sections -ffreestanding -std=c99 -w \
	-fno-tree-loop-distribute-patterns -nostdinc -isystem $(GCC_INC) -Idemo/libc -Idemo/include \
	-include features.h -Idemo/libc -I$(SRC)/libm/src/internal -I$(SRC)/libm/src/math
QUAKE_SOFTFP = $(call QUAKE_CFLAGS,$(1)) -w -I$(SRC)/softfp/libgcc/config/rs6000 \
	-I$(SRC)/softfp/libgcc/soft-fp -I$(SRC)/softfp/include
QUAKE_OWN = $(OWN_CFLAGS) -fno-builtin -fno-tree-loop-distribute-patterns
QUAKE_IMAGES := $(addprefix $(QM)/,ppc603e-quake.bin ppc603e-quake-le.bin ppc603e-quake-sf.bin \
	ppc603e-quake-smoke.bin ppc603e-quake-le-smoke.bin ppc603e-quake-sf-smoke.bin \
	ppc603e-quake-bec-smoke.bin)
QUAKE_HDRS := $(wildcard demo/quake/include/*.h demo/doom/include/*.h demo/doom/include/sys/*.h) \
	demo/doom/plat.h demo/quake/qport.h

.PHONY: quake
quake: $(QUAKE_IMAGES)

$(addprefix $(QM)/,$(addsuffix /eng,$(QUAKE_VARIANTS))):
	mkdir -p $@
.PRECIOUS: $(QM)/%.elf

# The assembly variant compiles the engine without the functions the
# PowerPC sources replace (quake/asmpatch.py).
$(QM)/be/src.stamp: demo/quake/asmpatch.py $(addprefix $(QG)/,$(addsuffix .c,$(QUAKE_ENGINE))) | $(QM)/be/eng
	$(PYTHON) demo/quake/asmpatch.py $(QG) $(QM)/be/src
	touch $@
$(QM)/be/eng/%.o: $(QM)/be/src.stamp $(QUAKE_HDRS)
	$(CC) $(call QUAKE_CFLAGS,be) -I$(QG) -w -c $(QM)/be/src/$*.c -o $@
define quake-c-engine
$(QM)/$(1)/eng/%.o: $(QG)/%.c $(QUAKE_HDRS) | $(QM)/$(1)/eng
	$$(CC) $$(call QUAKE_CFLAGS,$(1)) -I$(QG) -w -c $$< -o $$@
endef
$(foreach v,le sf bec,$(eval $(call quake-c-engine,$(v))))

# Struct offsets of the assembly, from the engine's own headers.
$(QM)/be/quakedefPPC.i: demo/quake/asmoffsets.py $(AQ)/quakeasmheaders.gen $(QM)/be/src.stamp
	$(PYTHON) demo/quake/asmoffsets.py $(AQ)/quakeasmheaders.gen $(QM)/be/src $@ -- \
	  $(CC) $(call QUAKE_CFLAGS,be) -I$(QM)/be/src -I$(QG) -w
# GNU as form of the vasm-syntax sources (quake/asmconv.py).
$(QM)/be/asm/%.s: $(AQ)/%.s demo/quake/asmconv.py
	@mkdir -p $(@D)
	$(PYTHON) demo/quake/asmconv.py $< $@
$(QM)/be/asm/macrosPPC.i: $(AQ)/macrosPPC.i demo/quake/asmconv.py
	@mkdir -p $(@D)
	$(PYTHON) demo/quake/asmconv.py $< $@
$(QM)/be/asm/%.o: $(QM)/be/asm/%.s $(QM)/be/asm/macrosPPC.i $(QM)/be/quakedefPPC.i
	$(CC) $(call QUAKE_ARCH,be) -Wa,-I$(QM)/be/asm -Wa,-I$(QM)/be -c -x assembler $< -o $@

define quake-variant
$(QM)/$(1)/libm/%.o: $(SRC)/libm/src/math/%.c | $(QM)/$(1)/eng
	@mkdir -p $$(@D)
	$$(CC) $$(call QUAKE_LIBM_CFLAGS,$(1)) -c $$< -o $$@
$(QM)/$(1)/libm.a: $(addprefix $(QM)/$(1)/libm/,$(addsuffix .o,$(QUAKE_LIBM)))
	rm -f $$@
	$$(AR) rcs $$@ $$^
$(QM)/$(1)/softfp/%.o: $(SRC)/softfp/libgcc/soft-fp/%.c | $(QM)/$(1)/eng
	@mkdir -p $$(@D)
	$$(CC) $$(call QUAKE_SOFTFP,$(1)) -c $$< -o $$@
$(QM)/$(1)/softfp.a: $(addprefix $(QM)/$(1)/softfp/,$(addsuffix .o,$(SOFTFP_SRC)))
	rm -f $$@
	$$(AR) rcs $$@ $$^
$(QM)/$(1)/libc.o: demo/doom/libc.c $(QUAKE_HDRS) | $(QM)/$(1)/eng
	$$(CC) $$(call QUAKE_CFLAGS,$(1)) $(QUAKE_OWN) -c $$< -o $$@
$(QM)/$(1)/qlibc.o: demo/quake/qlibc.c $(QUAKE_HDRS) | $(QM)/$(1)/eng
	$$(CC) $$(call QUAKE_CFLAGS,$(1)) $(QUAKE_OWN) -c $$< -o $$@
$(QM)/$(1)/dimath.o: demo/doom/dimath.c | $(QM)/$(1)/eng
	$$(CC) $$(call QUAKE_CFLAGS,$(1)) $(QUAKE_OWN) -c $$< -o $$@
$(QM)/$(1)/font.o: demo/font.c demo/soc.h | $(QM)/$(1)/eng
	$$(CC) $$(CFLAGS) -m$(call quake_endian,$(1))-endian $(OWN_CFLAGS) -c $$< -o $$@
$(QM)/$(1)/start.o: demo/doom/start.S | $(QM)/$(1)/eng
	$$(CC) $$(call QUAKE_ARCH,$(1)) -c $$< -o $$@
$(QM)/$(1)/setjmp.o: demo/quake/setjmp.S | $(QM)/$(1)/eng
	$$(CC) $$(call QUAKE_ARCH,$(1)) -c $$< -o $$@
$(QM)/$(1)/platform.o: demo/quake/platform.c $(QUAKE_HDRS) | $(QM)/$(1)/eng
	$$(CC) $$(call QUAKE_CFLAGS,$(1)) $(QUAKE_OWN) -c $$< -o $$@
$(QM)/$(1)/qport.o: demo/quake/qport.c $(QUAKE_HDRS) | $(QM)/$(1)/eng
	$$(CC) $$(call QUAKE_CFLAGS,$(1)) -I$(QG) -w -c $$< -o $$@
$(QM)/$(1)/qport-smoke.o: demo/quake/qport.c $(QUAKE_HDRS) demo/quake/quake.mk | $(QM)/$(1)/eng
	$$(CC) $$(call QUAKE_CFLAGS,$(1)) -I$(QG) -w -DQUAKE_SMOKE_FRAMES=$(QUAKE_SMOKE_FRAMES) -c $$< -o $$@
$(QM)/stub-$(1).o: demo/doom/stub.S | $(QM)/$(1)/eng
	$$(CC) -mcpu=603e -m32 -mbig-endian $(if $(filter le,$(1)),-DSTUB_LE) \
	  $(if $(filter sf,$(1)),,-DSTUB_FP) -c $$< -o $$@
$(QM)/stub-$(1).bin: $(QM)/stub-$(1).o
	$$(OBJCOPY) -O binary -j .text $$< $$@
QUAKE_OBJ_$(1) := $(QM)/$(1)/start.o $(QM)/$(1)/setjmp.o \
	$(addprefix $(QM)/$(1)/eng/,$(addsuffix .o,$(QUAKE_ENGINE))) $(QM)/$(1)/platform.o \
	$(QM)/$(1)/libc.o $(QM)/$(1)/qlibc.o $(QM)/$(1)/dimath.o $(QM)/$(1)/font.o \
	$(if $(filter be,$(1)),$(addprefix $(QM)/be/asm/,$(addsuffix .o,$(QUAKE_ASM)))) \
	$(QM)/$(1)/libm.a $(QM)/$(1)/softfp.a
$(QM)/quake-$(1).elf: $$(QUAKE_OBJ_$(1)) $(QM)/$(1)/qport.o demo/doom/doom.ld
	$$(call QUAKE_LINK,$(1))
$(QM)/quake-$(1)-smoke.elf: $$(QUAKE_OBJ_$(1)) $(QM)/$(1)/qport-smoke.o demo/doom/doom.ld
	$$(call QUAKE_LINK,$(1))
endef
QUAKE_LINK = $(CC) $(call QUAKE_ARCH,$(1)) -nostdlib -nostartfiles -no-pie -Wl,--build-id=none \
	-Wl,--gc-sections -Wl,--no-warn-rwx-segments -Wl,-T,demo/doom/doom.ld -Wl,-Map,$(@:.elf=.map) \
	$(filter %.o,$^) $(filter %.a,$^) $(filter %.a,$^) -o $@
$(foreach v,$(QUAKE_VARIANTS),$(eval $(call quake-variant,$(v))))

# objcopy starts the binary at the vectors, 0xfff00200.
define quake-image
	$(OBJCOPY) -O binary $< $@.body
	$(PYTHON) demo/doom/mkimage.py $(1) $(word 2,$^) $@.body 0xfff00200 $@
	rm -f $@.body
endef
$(QM)/ppc603e-quake.bin: $(QM)/quake-be.elf $(QM)/stub-be.bin demo/doom/mkimage.py
	$(call quake-image,)
$(QM)/ppc603e-quake-smoke.bin: $(QM)/quake-be-smoke.elf $(QM)/stub-be.bin demo/doom/mkimage.py
	$(call quake-image,)
$(QM)/ppc603e-quake-le.bin: $(QM)/quake-le.elf $(QM)/stub-le.bin demo/doom/mkimage.py
	$(call quake-image,--le)
$(QM)/ppc603e-quake-le-smoke.bin: $(QM)/quake-le-smoke.elf $(QM)/stub-le.bin demo/doom/mkimage.py
	$(call quake-image,--le)
$(QM)/ppc603e-quake-sf.bin: $(QM)/quake-sf.elf $(QM)/stub-sf.bin demo/doom/mkimage.py
	$(call quake-image,)
$(QM)/ppc603e-quake-sf-smoke.bin: $(QM)/quake-sf-smoke.elf $(QM)/stub-sf.bin demo/doom/mkimage.py
	$(call quake-image,)
$(QM)/ppc603e-quake-bec-smoke.bin: $(QM)/quake-bec-smoke.elf $(QM)/stub-bec.bin demo/doom/mkimage.py
	$(call quake-image,)
