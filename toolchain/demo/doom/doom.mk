# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Doom timedemo images (docs/BENCHMARKS.md#doom), included by demo/Makefile.
# doomgeneric comes from demo/fetch-doom.sh; the soft-float routines from
# fetch-benchmarks.sh. Each byte order (be, le) builds the engine once and
# links two images: the looping benchmark and a smoke image that stops at
# gametic DOOM_SMOKE_TICS with a frame checksum. Images are memory images of
# the 1 MiB window with the big-endian reset stub at 0x100 (doom/mkimage.py).
DOOM_SMOKE_TICS ?= 6
DG := $(SRC)/doomgeneric/doomgeneric
DM := $(OUT)/doom
DOOM_ENGINE := dummy am_map doomdef doomstat dstrings d_event d_items d_iwad d_loop d_main d_mode \
	d_net f_finale f_wipe g_game hu_lib hu_stuff info i_cdmus i_endoom i_joystick i_scale i_sound \
	i_system i_timer memio m_argv m_bbox m_cheat m_config m_controls m_fixed m_menu m_misc m_random \
	p_ceilng p_doors p_enemy p_floor p_inter p_lights p_map p_maputl p_mobj p_plats p_pspr p_saveg \
	p_setup p_sight p_spec p_switch p_telept p_tick p_user r_bsp r_data r_draw r_main r_plane r_segs \
	r_sky r_things sha1 sounds statdump st_lib st_stuff s_sound tables v_video wi_stuff w_checksum \
	w_file w_main w_wad z_zone w_file_stdc i_input i_video doomgeneric
# Signed char as on the x86 host the reference frame comes from.
DOOM_ARCH = -mcpu=603e -m32 -msoft-float -msdata=none -mlong-double-64
DOOM_CFLAGS = -O2 -g0 $(DOOM_ARCH) -fsigned-char -fno-strict-aliasing -fno-stack-protector \
	-fno-pic -fno-pie -fno-ident -ffunction-sections -fdata-sections -ffile-prefix-map=$(CURDIR)=. \
	-nostdinc -isystem $(GCC_INC) -Idemo/doom/include -Idemo/doom -I$(DG) \
	-DCMAP256 -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200
DOOM_OWN = $(OWN_CFLAGS) -fno-builtin -fno-tree-loop-distribute-patterns
DOOM_SOFTFP = $(subst -msoft-float,-msoft-float -nostdinc -isystem $(GCC_INC) -Idemo/doom/include,$(DOOM_ARCH)) \
	-O2 -w -fno-pic -I$(SRC)/softfp/libgcc/config/rs6000 -I$(SRC)/softfp/libgcc/soft-fp \
	-I$(SRC)/softfp/include
DOOM_IMAGES := $(addprefix $(DM)/,ppc603e-doom.bin ppc603e-doom-le.bin ppc603e-doom-smoke.bin \
	ppc603e-doom-le-smoke.bin)
DOOM_HDRS := $(wildcard demo/doom/include/*.h demo/doom/include/sys/*.h) demo/doom/plat.h

.PHONY: doom
doom: $(DOOM_IMAGES)

$(DM)/be/eng $(DM)/le/eng $(DM)/be/softfp $(DM)/le/softfp:
	mkdir -p $@
.PRECIOUS: $(DM)/%/eng/ $(DM)/%.elf
$(DM)/be/eng/%.o: $(DG)/%.c $(DOOM_HDRS) | $(DM)/be/eng
	$(CC) $(DOOM_CFLAGS) -mbig-endian -w -c $< -o $@
$(DM)/le/eng/%.o: $(DG)/%.c $(DOOM_HDRS) | $(DM)/le/eng
	$(CC) $(DOOM_CFLAGS) -mlittle-endian -w -c $< -o $@
$(DM)/be/softfp/%.o: $(SRC)/softfp/libgcc/soft-fp/%.c | $(DM)/be/softfp
	$(CC) $(DOOM_SOFTFP) -mbig-endian -c $< -o $@
$(DM)/le/softfp/%.o: $(SRC)/softfp/libgcc/soft-fp/%.c | $(DM)/le/softfp
	$(CC) $(DOOM_SOFTFP) -mlittle-endian -c $< -o $@
$(DM)/%/softfp.a: $(foreach s,$(SOFTFP_SRC),$(DM)/%/softfp/$(s).o)
	rm -f $@
	$(AR) rcs $@ $^

$(DM)/%/libc.o: demo/doom/libc.c $(DOOM_HDRS) | $(DM)/%/eng
	$(CC) $(DOOM_CFLAGS) -m$(if $(filter le,$*),little,big)-endian $(DOOM_OWN) -c $< -o $@
$(DM)/%/dimath.o: demo/doom/dimath.c | $(DM)/%/eng
	$(CC) $(DOOM_CFLAGS) -m$(if $(filter le,$*),little,big)-endian $(DOOM_OWN) -c $< -o $@
$(DM)/%/font.o: demo/font.c demo/soc.h | $(DM)/%/eng
	$(CC) $(CFLAGS) -m$(if $(filter le,$*),little,big)-endian $(OWN_CFLAGS) -c $< -o $@
$(DM)/%/start.o: demo/doom/start.S | $(DM)/%/eng
	$(CC) -mcpu=603e -m32 -m$(if $(filter le,$*),little,big)-endian -c $< -o $@
$(DM)/%/platform.o: demo/doom/platform.c $(DOOM_HDRS) | $(DM)/%/eng
	$(CC) $(DOOM_CFLAGS) -m$(if $(filter le,$*),little,big)-endian $(DOOM_OWN) -c $< -o $@
$(DM)/%/platform-smoke.o: demo/doom/platform.c $(DOOM_HDRS) demo/doom/doom.mk | $(DM)/%/eng
	$(CC) $(DOOM_CFLAGS) -m$(if $(filter le,$*),little,big)-endian $(DOOM_OWN) \
	  -DDOOM_SMOKE_TICS=$(DOOM_SMOKE_TICS) -c $< -o $@
# The reset stub is big-endian in both images.
$(DM)/stub-be.o $(DM)/stub-le.o: $(DM)/stub-%.o: demo/doom/stub.S | $(DM)/be/eng
	$(CC) -mcpu=603e -m32 -mbig-endian $(if $(filter le,$*),-DSTUB_LE) -c $< -o $@
$(DM)/stub-%.bin: $(DM)/stub-%.o
	$(OBJCOPY) -O binary -j .text $< $@

DOOM_COMMON = $(DM)/$(1)/start.o $(addprefix $(DM)/$(1)/eng/,$(addsuffix .o,$(DOOM_ENGINE))) \
	$(DM)/$(1)/libc.o $(DM)/$(1)/dimath.o $(DM)/$(1)/font.o $(DM)/$(1)/softfp.a
DOOM_LINK = $(CC) $(DOOM_ARCH) -m$(2)-endian -nostdlib -nostartfiles -no-pie -Wl,--build-id=none \
	-Wl,--gc-sections -Wl,--no-warn-rwx-segments -Wl,-T,demo/doom/doom.ld -Wl,-Map,$(@:.elf=.map) \
	$(filter %.o,$^) $(filter %.a,$^) -o $@
$(DM)/doom-be.elf: $(call DOOM_COMMON,be) $(DM)/be/platform.o demo/doom/doom.ld
	$(call DOOM_LINK,be,big)
$(DM)/doom-be-smoke.elf: $(call DOOM_COMMON,be) $(DM)/be/platform-smoke.o demo/doom/doom.ld
	$(call DOOM_LINK,be,big)
$(DM)/doom-le.elf: $(call DOOM_COMMON,le) $(DM)/le/platform.o demo/doom/doom.ld
	$(call DOOM_LINK,le,little)
$(DM)/doom-le-smoke.elf: $(call DOOM_COMMON,le) $(DM)/le/platform-smoke.o demo/doom/doom.ld
	$(call DOOM_LINK,le,little)

# objcopy starts the binary at the vectors, 0xfff00200.
define doom-image
	$(OBJCOPY) -O binary $< $@.body
	$(PYTHON) demo/doom/mkimage.py $(1) $(word 2,$^) $@.body 0xfff00200 $@
	rm -f $@.body
endef
$(DM)/ppc603e-doom.bin: $(DM)/doom-be.elf $(DM)/stub-be.bin demo/doom/mkimage.py
	$(call doom-image,)
$(DM)/ppc603e-doom-smoke.bin: $(DM)/doom-be-smoke.elf $(DM)/stub-be.bin demo/doom/mkimage.py
	$(call doom-image,)
$(DM)/ppc603e-doom-le.bin: $(DM)/doom-le.elf $(DM)/stub-le.bin demo/doom/mkimage.py
	$(call doom-image,--le)
$(DM)/ppc603e-doom-le-smoke.bin: $(DM)/doom-le-smoke.elf $(DM)/stub-le.bin demo/doom/mkimage.py
	$(call doom-image,--le)
