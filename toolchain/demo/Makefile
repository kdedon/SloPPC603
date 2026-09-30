# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Demo system firmware. Run from toolchain/ with -f demo/Makefile, normally in
# the pinned container (build-in-container.sh -f demo/Makefile all). Benchmark
# sources come from demo/fetch-benchmarks.sh, run on the host first.
CROSS ?= powerpc-linux-gnu-
BUILD_DIR ?= build
OUT := $(BUILD_DIR)/demo
SRC := $(OUT)/src
CC := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
PYTHON ?= python3

DHRY_RUNS ?= 2000
CM_ITERATIONS ?= 10

ARCH := -mcpu=603e -m32 -mbig-endian -msoft-float -msdata=none
CFLAGS := -O2 -g0 $(ARCH) -ffreestanding -fno-builtin -fno-stack-protector -fno-pic \
	-fno-pie -fno-ident -ffunction-sections -fdata-sections \
	-ffile-prefix-map=$(CURDIR)=. -Idemo -Idemo/include
OWN_CFLAGS := -std=gnu11 -Wall -Wextra -Werror
# The runtime must not turn its own loops into calls to itself.
RT_CFLAGS := $(OWN_CFLAGS) -fno-tree-loop-distribute-patterns
# K&R sources, compiled as published.
DHRY_CFLAGS := -std=gnu89 -w -DDEMO_DHRYSTONE -DHZ=50000000 -I$(SRC)/dhrystone
CM_CFLAGS := -std=gnu11 -w -DITERATIONS=$(CM_ITERATIONS) -Idemo/coremark -I$(SRC)/coremark \
	'-DCOMPILER_FLAGS="-O2 -mcpu=603e -msoft-float -fno-builtin"'
LDFLAGS := $(ARCH) -nostdlib -nostartfiles -no-pie -Wl,--build-id=none -Wl,--gc-sections -Wl,--no-warn-rwx-segments \
	-Wl,-T,demo/demo.ld

RT_OBJ := $(OUT)/crt0.o $(OUT)/rt.o $(OUT)/font.o
CM_SRC := core_list_join core_main core_matrix core_state core_util

.PHONY: all hello dhrystone coremark mister
all: hello dhrystone coremark
hello: $(OUT)/hello.hex
dhrystone: $(OUT)/dhrystone.hex
coremark: $(OUT)/coremark.hex

$(OUT) $(OUT)/cm:
	mkdir -p $@

$(OUT)/crt0.o: demo/crt0.S | $(OUT)
	$(CC) $(ARCH) -c $< -o $@
$(OUT)/rt.o: demo/rt.c demo/soc.h | $(OUT)
	$(CC) $(CFLAGS) $(RT_CFLAGS) -c $< -o $@
$(OUT)/font.o: demo/font.c demo/soc.h | $(OUT)
	$(CC) $(CFLAGS) $(OWN_CFLAGS) -c $< -o $@
$(OUT)/nofloat.o: demo/nofloat.c demo/soc.h | $(OUT)
	$(CC) $(CFLAGS) $(OWN_CFLAGS) -c $< -o $@
$(OUT)/hello.o: demo/hello.c demo/soc.h demo/mandel.h | $(OUT)
	$(CC) $(CFLAGS) $(OWN_CFLAGS) -c $< -o $@

$(OUT)/dhry_1.o: $(SRC)/dhrystone/dhry_1.c | $(OUT)
	$(CC) $(CFLAGS) $(DHRY_CFLAGS) -Dmain=dhry_main -c $< -o $@
$(OUT)/dhry_2.o: $(SRC)/dhrystone/dhry_2.c | $(OUT)
	$(CC) $(CFLAGS) $(DHRY_CFLAGS) -c $< -o $@
$(OUT)/dhry_glue.o: demo/dhry_glue.c demo/soc.h | $(OUT)
	$(CC) $(CFLAGS) $(DHRY_CFLAGS) -DDHRY_RUNS=$(DHRY_RUNS) -c $< -o $@

$(OUT)/cm/core_main.o: $(SRC)/coremark/core_main.c | $(OUT)/cm
	$(CC) $(CFLAGS) $(CM_CFLAGS) -Dmain=coremark_main -c $< -o $@
$(OUT)/cm/%.o: $(SRC)/coremark/%.c | $(OUT)/cm
	$(CC) $(CFLAGS) $(CM_CFLAGS) -c $< -o $@
$(OUT)/cm/core_portme.o: demo/coremark/core_portme.c demo/coremark/core_portme.h | $(OUT)/cm
	$(CC) $(CFLAGS) $(CM_CFLAGS) -c $< -o $@

$(OUT)/hello.elf: $(RT_OBJ) $(OUT)/hello.o demo/demo.ld
$(OUT)/dhrystone.elf: $(RT_OBJ) $(OUT)/dhry_1.o $(OUT)/dhry_2.o $(OUT)/dhry_glue.o $(OUT)/nofloat.o demo/demo.ld
$(OUT)/coremark.elf: $(RT_OBJ) $(addprefix $(OUT)/cm/,$(addsuffix .o,$(CM_SRC) core_portme)) demo/demo.ld

# MiSTer image: all three programs behind a selector (demo/mister.c), with
# run lengths set at run time and the data section copied at start-up.
GIT_SHORT ?= unknown
MI := $(OUT)/mister
MISTER_OBJ := $(RT_OBJ) $(OUT)/nofloat.o $(MI)/mister.o $(MI)/hello.o $(MI)/dhry_1.o \
	$(OUT)/dhry_2.o $(MI)/dhry_glue.o $(addprefix $(OUT)/cm/,$(addsuffix .o,$(CM_SRC))) \
	$(MI)/core_portme.o
mister: $(OUT)/mister.hex

$(MI):
	mkdir -p $@
$(MI)/mister.o: demo/mister.c demo/soc.h FORCE | $(MI)
	$(CC) $(CFLAGS) $(OWN_CFLAGS) '-DGIT_SHORT="$(GIT_SHORT)"' -c $< -o $@
$(MI)/hello.o: demo/hello.c demo/soc.h demo/mandel.h | $(MI)
	$(CC) $(CFLAGS) $(OWN_CFLAGS) -Dmain=hello_main -c $< -o $@
# An HZ above any run length keeps Dhrystone's floating-point rate printout
# off; the glue computes the rates in integers.
$(MI)/dhry_1.o: $(SRC)/dhrystone/dhry_1.c | $(MI)
	$(CC) $(CFLAGS) $(DHRY_CFLAGS) -UHZ -DHZ=1000000000 -Dmain=dhry_main -c $< -o $@
$(MI)/dhry_glue.o: demo/dhry_glue.c demo/soc.h | $(MI)
	$(CC) $(CFLAGS) $(DHRY_CFLAGS) -Dmain=dhry_demo -c $< -o $@
$(MI)/core_portme.o: demo/coremark/core_portme.c demo/coremark/core_portme.h | $(MI)
	$(CC) $(CFLAGS) $(CM_CFLAGS) -Dmain=coremark_demo -c $< -o $@
$(OUT)/mister.elf: LDFLAGS := $(subst demo/demo.ld,demo/mister.ld,$(LDFLAGS))
$(OUT)/mister.elf: $(MISTER_OBJ) demo/mister.ld
.PHONY: FORCE
FORCE:

# The processor has no FPU: reject any floating-point instruction.
$(OUT)/%.elf:
	$(CC) $(LDFLAGS) -Wl,-Map,$(OUT)/$*.map $(filter %.o,$^) -lgcc -o $@
	$(OBJDUMP) -d $@ > $(OUT)/$*.dump
	@if awk -F'\t' 'NF >= 3 {print $$3}' $(OUT)/$*.dump | grep -Eq '^(f[a-z]|lf|stf|mffs|mtfs)'; then \
	  echo "$@: floating-point instruction in image" >&2; rm -f $@; exit 1; fi

$(OUT)/%.hex: $(OUT)/%.elf demo/bin2hex64.py
	$(OBJCOPY) -O binary $< $(OUT)/$*.bin
	$(PYTHON) demo/bin2hex64.py $(OUT)/$*.bin 0x100 $@
