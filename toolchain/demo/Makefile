# SPDX-License-Identifier: GPL-2.0-or-later
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
AR := $(CROSS)ar
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

.PHONY: all hello dhrystone coremark mister benchmarks nbench nbench-full embench embench-full \
	mister-nbench mister-embench whetstone whetstone-full whetstone-hf whetstone-hf-full \
	mister-whetstone mister-whetstone-hf mister-fpu
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
$(OUT)/mister.elf: $(MISTER_OBJ) demo/mister.ld demo/mister-sections.ld
.PHONY: FORCE
FORCE:

# ---- nbench and Embench-IoT (docs/BENCHMARKS.md) ---------------------------
# Fetched sources on a small C library (demo/libc), musl's libm and GCC's
# soft-fp routines; the toolchain's libgcc has only hard-float versions.
# <name> images run short fixed sizes for simulation; <name>-full images
# run the reference sizes (nbench scaled to fit, see the document).
GCC_INC = $(shell $(CC) -print-file-name=include)
BENCH_CFLAGS = $(subst -Idemo -Idemo/include,-nostdinc -isystem $(GCC_INC) -Idemo/libc -Idemo/include -Idemo,$(CFLAGS)) \
	-mlong-double-64
FP_OBJ := demo/Makefile $(OUT)/bench.o $(OUT)/libc.o $(OUT)/libm.a $(OUT)/softfp.a
BENCH_IMAGES := nbench nbench-full embench embench-full whetstone whetstone-full whetstone-hf \
	whetstone-hf-full
benchmarks: $(BENCH_IMAGES)
# A smaller stack leaves the RAM to code, data and heap; the programs check
# their stack depth. The symbol must precede the linker script.
$(OUT)/nbench.elf $(OUT)/nbench-full.elf: LDFLAGS := -Wl,--defsym=__stack_size=0x2000 $(LDFLAGS)
$(OUT)/embench.elf $(OUT)/embench-full.elf: LDFLAGS := -Wl,--defsym=__stack_size=0x6000 $(LDFLAGS)

$(OUT)/bench.o: demo/bench.c demo/bench.h demo/soc.h | $(OUT)
	$(CC) $(BENCH_CFLAGS) $(OWN_CFLAGS) -c $< -o $@
$(OUT)/libc.o: demo/libc/libc.c $(wildcard demo/libc/*.h) demo/soc.h | $(OUT)
	$(CC) $(BENCH_CFLAGS) $(RT_CFLAGS) -c $< -o $@

SOFTFP_SRC := adddf3 subdf3 muldf3 divdf3 negdf2 eqdf2 gedf2 ledf2 unorddf2 \
	floatsidf floatunsidf floatdidf floatundidf fixdfsi fixunsdfsi fixdfdi fixunsdfdi \
	extendsfdf2 truncdfsf2 addsf3 subsf3 mulsf3 divsf3 negsf2 eqsf2 gesf2 lesf2 unordsf2 \
	floatsisf floatunsisf floatdisf floatundisf fixsfsi fixunssfsi fixsfdi fixunssfdi
SOFTFP_CFLAGS = $(BENCH_CFLAGS) -w -I$(SRC)/softfp/libgcc/config/rs6000 \
	-I$(SRC)/softfp/libgcc/soft-fp -I$(SRC)/softfp/include
$(OUT)/softfp:
	mkdir -p $@
$(OUT)/softfp/%.o: $(SRC)/softfp/libgcc/soft-fp/%.c | $(OUT)/softfp
	$(CC) $(SOFTFP_CFLAGS) -c $< -o $@
$(OUT)/softfp.a: $(addprefix $(OUT)/softfp/,$(addsuffix .o,$(SOFTFP_SRC)))
	rm -f $@
	$(AR) rcs $@ $^

LIBM_SRC := sin cos __sin __cos __rem_pio2 __rem_pio2_large exp exp_data pow pow_data \
	log log_data sqrt sqrt_data fabs floor acos atan scalbn __math_oflow __math_uflow \
	__math_xflow __math_invalid __math_divzero
LIBM_CFLAGS = $(BENCH_CFLAGS) -std=c99 -w -fno-tree-loop-distribute-patterns -include features.h \
	-I$(SRC)/libm/src/internal -I$(SRC)/libm/src/math
$(OUT)/libm:
	mkdir -p $@
$(OUT)/libm/%.o: $(SRC)/libm/src/math/%.c | $(OUT)/libm
	$(CC) $(LIBM_CFLAGS) -c $< -o $@
$(OUT)/libm.a: $(addprefix $(OUT)/libm/,$(addsuffix .o,$(LIBM_SRC)))
	rm -f $@
	$(AR) rcs $@ $^

# nbench: nbench1.c is built with DEBUG for its sort, IDEA and Huffman
# checks, once per variant: LU decomposition is NB_LU_N square instead of
# 101 (memory). The short image shrinks LU and assignment further.
NB_LU_N ?= 90
NB_SMOKE_LU_N ?= 16
NB_SMOKE_ASSIGN_N ?= 21
NB_SECS ?= 2
NB := $(OUT)/nb
NB_CFLAGS = $(BENCH_CFLAGS) -std=gnu89 -w -DDEMO_NBENCH -Idemo/nbench -I$(SRC)/nbench
# nbench0.h declares the upstream driver's static functions, replaced here.
NB_GLUE_CFLAGS = $(BENCH_CFLAGS) $(OWN_CFLAGS) -Wno-unused-function -I$(NB) -Idemo/nbench \
	-I$(SRC)/nbench -DNB_SECS=$(NB_SECS)
# The bitfield test addresses bits below 262,140 only: 8192 words cover them
# (the reference allocates 32768).
NB_full := -DNB_LU_N=$(NB_LU_N) -DNB_NUMARRAYSIZE=8111 -DNB_STRARRAYSIZE=8111 \
	-DNB_BITFARRAYSIZE=8192 -DNB_BITOPS=30 -DNB_EMFARRAYSIZE=3000 -DNB_FOURIERSIZE=100 \
	-DNB_IDEAARRAYSIZE=4000 -DNB_HUFFARRAYSIZE=5000
NB_smoke := -DNB_SMOKE -DNB_LU_N=$(NB_SMOKE_LU_N) -DNB_NUMARRAYSIZE=1000 -DNB_STRARRAYSIZE=1000 \
	-DNB_BITFARRAYSIZE=8192 -DNB_BITOPS=3 -DNB_EMFARRAYSIZE=100 -DNB_FOURIERSIZE=2 \
	-DNB_IDEAARRAYSIZE=400 -DNB_HUFFARRAYSIZE=500
NB_LU_full = $(NB_LU_N)
NB_LU_smoke = $(NB_SMOKE_LU_N)
NB_ASSIGN_full = 101
NB_ASSIGN_smoke = $(NB_SMOKE_ASSIGN_N)
nbench: $(OUT)/nbench.hex
nbench-full: $(OUT)/nbench-full.hex

$(NB) $(NB)/smoke $(NB)/full:
	mkdir -p $@
$(NB)/%/nbench1.c: $(SRC)/nbench/nbench1.c $(SRC)/nbench/nbench1.h demo/Makefile | $(NB)/%
	cp $< $@
	sed -e 's/^#define LUARRAYROWS 101L/#define LUARRAYROWS $(NB_LU_$*)L/' \
	    -e 's/^#define LUARRAYCOLS 101L/#define LUARRAYCOLS $(NB_LU_$*)L/' \
	    -e 's/^#define ASSIGNROWS 101L/#define ASSIGNROWS $(NB_ASSIGN_$*)L/' \
	    -e 's/^#define ASSIGNCOLS 101L/#define ASSIGNCOLS $(NB_ASSIGN_$*)L/' \
	    $(SRC)/nbench/nbench1.h > $(NB)/$*/nbench1.h
	grep -q '^#define LUARRAYROWS $(NB_LU_$*)L' $(NB)/$*/nbench1.h
	grep -q '^#define ASSIGNCOLS $(NB_ASSIGN_$*)L' $(NB)/$*/nbench1.h
$(NB)/%/nbench1.o: $(NB)/%/nbench1.c
	$(CC) $(NB_CFLAGS) -DDEBUG -c $< -o $@
$(NB)/%.o: $(SRC)/nbench/%.c | $(NB)
	$(CC) $(NB_CFLAGS) -c $< -o $@
$(NB)/nnet_dat.h: $(SRC)/nbench/NNET.DAT demo/bench_gen.py | $(NB)
	$(PYTHON) demo/bench_gen.py cstring nnet_dat $< $@
$(NB)/%/glue.o: demo/nbench/nbench_glue.c $(NB)/nnet_dat.h demo/bench.h demo/soc.h demo/Makefile | $(NB)/%
	$(CC) $(NB_GLUE_CFLAGS) $(NB_$*) -c $< -o $@
$(OUT)/nbench.elf: $(RT_OBJ) $(NB)/smoke/nbench1.o $(NB)/smoke/glue.o $(NB)/emfloat.o $(NB)/misc.o \
	$(FP_OBJ) demo/demo.ld
$(OUT)/nbench-full.elf: $(RT_OBJ) $(NB)/full/nbench1.o $(NB)/full/glue.o $(NB)/emfloat.o $(NB)/misc.o \
	$(FP_OBJ) demo/demo.ld

# Embench-IoT 1.0: every benchmark in one image (demo/embench/build.sh).
# EMB_DIV divides the repeat counts: 16 for simulation, 1 for the full run.
EMB_NAMES := aha-mont64 crc32 cubic edn huffbench matmult-int minver nbody nettle-aes \
	nettle-sha256 nsichneu picojpeg qrduino sglib-combined slre st statemate ud wikisort
EMB_SMOKE_DIV ?= 16
EMB_CFLAGS = $(BENCH_CFLAGS) -std=gnu99 -w
EMB_DEPS := demo/Makefile demo/embench/build.sh $(wildcard demo/libc/*.h) $(SRC)/embench/support/beebsc.c
embench: $(OUT)/embench.hex
embench-full: $(OUT)/embench-full.hex

$(OUT)/emb-smoke/benchmarks.o: $(EMB_DEPS) | $(OUT)
	OBJCOPY=$(OBJCOPY) demo/embench/build.sh $(OUT)/emb-smoke $(SRC)/embench $(EMB_SMOKE_DIV) \
	  $(EMB_NAMES) -- $(CC) $(EMB_CFLAGS)
$(OUT)/emb-full/benchmarks.o: $(EMB_DEPS) | $(OUT)
	OBJCOPY=$(OBJCOPY) demo/embench/build.sh $(OUT)/emb-full $(SRC)/embench 1 \
	  $(EMB_NAMES) -- $(CC) $(EMB_CFLAGS)
$(OUT)/emb_table.h: demo/bench_gen.py $(SRC)/embench/baseline-data/speed.json | $(OUT)
	$(PYTHON) demo/bench_gen.py embench $(SRC)/embench $@ $(EMB_NAMES)
$(OUT)/emb-smoke/glue.o: demo/embench/embench_glue.c $(OUT)/emb_table.h demo/bench.h $(OUT)/emb-smoke/benchmarks.o demo/Makefile
	$(CC) $(BENCH_CFLAGS) $(OWN_CFLAGS) -I$(OUT) -DEMB_DIV=$(EMB_SMOKE_DIV) -c $< -o $@
$(OUT)/emb-full/glue.o: demo/embench/embench_glue.c $(OUT)/emb_table.h demo/bench.h $(OUT)/emb-full/benchmarks.o demo/Makefile
	$(CC) $(BENCH_CFLAGS) $(OWN_CFLAGS) -I$(OUT) -DEMB_DIV=1 -c $< -o $@
$(OUT)/embench.elf: $(RT_OBJ) $(OUT)/emb-smoke/benchmarks.o $(OUT)/emb-smoke/glue.o $(FP_OBJ) demo/demo.ld
$(OUT)/embench-full.elf: $(RT_OBJ) $(OUT)/emb-full/benchmarks.o $(OUT)/emb-full/glue.o $(FP_OBJ) demo/demo.ld

# MiSTer benchmark suite images: the full sizes in 256 KiB, data copied at
# start-up. The -smoke images link the simulation sizes the same way.
MISTER_BENCH_LD := $(subst demo/demo.ld,demo/mister-bench.ld,$(LDFLAGS))
MISTER_BENCH_DEPS := $(FP_OBJ) demo/mister-bench.ld demo/mister-sections.ld
mister-nbench: $(OUT)/mister-nbench.hex $(OUT)/mister-nbench-smoke.hex
mister-embench: $(OUT)/mister-embench.hex $(OUT)/mister-embench-smoke.hex
$(OUT)/mister-nbench.elf $(OUT)/mister-nbench-smoke.elf: \
	LDFLAGS := -Wl,--defsym=__stack_size=0x2000 $(MISTER_BENCH_LD)
$(OUT)/mister-embench.elf $(OUT)/mister-embench-smoke.elf: \
	LDFLAGS := -Wl,--defsym=__stack_size=0x5000 $(MISTER_BENCH_LD)
$(OUT)/mister-nbench.elf: $(RT_OBJ) $(NB)/full/nbench1.o $(NB)/full/glue.o $(NB)/emfloat.o \
	$(NB)/misc.o $(MISTER_BENCH_DEPS)
$(OUT)/mister-nbench-smoke.elf: $(RT_OBJ) $(NB)/smoke/nbench1.o $(NB)/smoke/glue.o \
	$(NB)/emfloat.o $(NB)/misc.o $(MISTER_BENCH_DEPS)
$(OUT)/mister-embench.elf: $(RT_OBJ) $(OUT)/emb-full/benchmarks.o $(OUT)/emb-full/glue.o \
	$(MISTER_BENCH_DEPS)
$(OUT)/mister-embench-smoke.elf: $(RT_OBJ) $(OUT)/emb-smoke/benchmarks.o \
	$(OUT)/emb-smoke/glue.o $(MISTER_BENCH_DEPS)

# ---- Whetstone (docs/BENCHMARKS.md) -------------------------------------------
# The netlib C Whetstone, built soft-float for the processor without an FPU
# and hard-float (-hf) for ENABLE_FPU builds. A hard-float image recompiles
# everything that passes doubles and links the toolchain's hard-float libgcc
# instead of soft-fp. The short images run WHET_SMOKE_LOOP once; the full
# ones repeat WHET_LOOP for at least WHET_SECS seconds.
WHET_SMOKE_LOOP ?= 2
WHET_LOOP ?= 100
WHET_SECS ?= 10
WH := $(OUT)/whet
HF := $(OUT)/hf
ARCH_HF := $(subst -msoft-float,-mhard-float,$(ARCH))
HF_CFLAGS = $(subst -msoft-float,-mhard-float,$(CFLAGS))
HF_BENCH_CFLAGS = $(subst -msoft-float,-mhard-float,$(BENCH_CFLAGS))
WHET_CFLAGS := -std=gnu89 -w -DPRINTOUT -Dmain=whet_main -Dprintf=whet_printf -Dtime=whet_time \
	-Datol=whet_atol -Dstderr=0
WHET_GLUE_DEPS = demo/whetstone/whet_glue.c demo/bench.h demo/soc.h demo/Makefile
WHET_smoke = -DWHET_SECS=0
WHET_full = -DWHET_SECS=$(WHET_SECS)
WHET_LOOP_smoke = $(WHET_SMOKE_LOOP)
WHET_LOOP_full = $(WHET_LOOP)
HF_RT_OBJ := $(HF)/crt0.o $(HF)/rt.o $(HF)/font.o
HF_FP_OBJ := demo/Makefile $(HF)/bench.o $(HF)/libc.o $(HF)/libm.a
HF_IMAGES := whetstone-hf whetstone-hf-full mister-whetstone-hf mister-whetstone-hf-smoke \
	mister-fpu
whetstone: $(OUT)/whetstone.hex
whetstone-full: $(OUT)/whetstone-full.hex
whetstone-hf: $(OUT)/whetstone-hf.hex
whetstone-hf-full: $(OUT)/whetstone-hf-full.hex
mister-whetstone: $(OUT)/mister-whetstone.hex $(OUT)/mister-whetstone-smoke.hex
mister-whetstone-hf: $(OUT)/mister-whetstone-hf.hex $(OUT)/mister-whetstone-hf-smoke.hex

$(WH)/smoke $(WH)/full $(HF) $(HF)/libm:
	mkdir -p $@
$(WH)/%/whet_ref.h: $(SRC)/whetstone/whetstone.c demo/bench_gen.py demo/Makefile | $(WH)/%
	$(PYTHON) demo/bench_gen.py whetstone $< $(WHET_LOOP_$*) $@
$(WH)/whetstone.o: $(SRC)/whetstone/whetstone.c | $(WH)/smoke
	$(CC) $(BENCH_CFLAGS) $(WHET_CFLAGS) -c $< -o $@
$(WH)/whetstone-hf.o: $(SRC)/whetstone/whetstone.c | $(WH)/smoke
	$(CC) $(HF_BENCH_CFLAGS) $(WHET_CFLAGS) -c $< -o $@
$(WH)/%/glue.o: $(WHET_GLUE_DEPS) $(WH)/%/whet_ref.h
	$(CC) $(BENCH_CFLAGS) $(OWN_CFLAGS) -I$(WH)/$* $(WHET_$*) -c $< -o $@
$(WH)/%/glue-hf.o: $(WHET_GLUE_DEPS) $(WH)/%/whet_ref.h
	$(CC) $(HF_BENCH_CFLAGS) $(OWN_CFLAGS) -I$(WH)/$* $(WHET_$*) -c $< -o $@

$(HF)/crt0.o: demo/crt0.S | $(HF)
	$(CC) $(ARCH_HF) -DCRT0_FP -c $< -o $@
$(HF)/rt.o: demo/rt.c demo/soc.h | $(HF)
	$(CC) $(HF_CFLAGS) $(RT_CFLAGS) -c $< -o $@
$(HF)/font.o: demo/font.c demo/soc.h | $(HF)
	$(CC) $(HF_CFLAGS) $(OWN_CFLAGS) -c $< -o $@
$(HF)/bench.o: demo/bench.c demo/bench.h demo/soc.h | $(HF)
	$(CC) $(HF_BENCH_CFLAGS) $(OWN_CFLAGS) -c $< -o $@
$(HF)/libc.o: demo/libc/libc.c $(wildcard demo/libc/*.h) demo/soc.h | $(HF)
	$(CC) $(HF_BENCH_CFLAGS) $(RT_CFLAGS) -c $< -o $@
$(HF)/libm/%.o: $(SRC)/libm/src/math/%.c | $(HF)/libm
	$(CC) $(subst -msoft-float,-mhard-float,$(LIBM_CFLAGS)) -c $< -o $@
$(HF)/libm.a: $(addprefix $(HF)/libm/,$(addsuffix .o,$(LIBM_SRC)))
	rm -f $@
	$(AR) rcs $@ $^

$(OUT)/whetstone.elf: $(RT_OBJ) $(WH)/whetstone.o $(WH)/smoke/glue.o $(FP_OBJ) demo/demo.ld
$(OUT)/whetstone-full.elf: $(RT_OBJ) $(WH)/whetstone.o $(WH)/full/glue.o $(FP_OBJ) demo/demo.ld
$(OUT)/whetstone-hf.elf: $(HF_RT_OBJ) $(WH)/whetstone-hf.o $(WH)/smoke/glue-hf.o $(HF_FP_OBJ) \
	demo/demo.ld
$(OUT)/whetstone-hf-full.elf: $(HF_RT_OBJ) $(WH)/whetstone-hf.o $(WH)/full/glue-hf.o $(HF_FP_OBJ) \
	demo/demo.ld
$(OUT)/mister-whetstone.elf $(OUT)/mister-whetstone-smoke.elf \
$(OUT)/mister-whetstone-hf.elf $(OUT)/mister-whetstone-hf-smoke.elf: LDFLAGS := $(MISTER_BENCH_LD)
$(OUT)/mister-whetstone.elf: $(RT_OBJ) $(WH)/whetstone.o $(WH)/full/glue.o $(MISTER_BENCH_DEPS)
$(OUT)/mister-whetstone-smoke.elf: $(RT_OBJ) $(WH)/whetstone.o $(WH)/smoke/glue.o \
	$(MISTER_BENCH_DEPS)
$(OUT)/mister-whetstone-hf.elf: $(HF_RT_OBJ) $(WH)/whetstone-hf.o $(WH)/full/glue-hf.o \
	$(HF_FP_OBJ) demo/mister-bench.ld demo/mister-sections.ld
$(OUT)/mister-whetstone-hf-smoke.elf: $(HF_RT_OBJ) $(WH)/whetstone-hf.o $(WH)/smoke/glue-hf.o \
	$(HF_FP_OBJ) demo/mister-bench.ld demo/mister-sections.ld
# FPU MiSTer image (mister/build.sh --fpu): the MiSTer image's integer
# objects unchanged, plus Whetstone and the double-precision Mandelbrot set
# built hard-float, in the same RAM. The Whetstone glue carries both LOOPs'
# reference values; the run length picks one at run time.
mister-fpu: $(OUT)/mister-fpu.hex
$(MI)/mister-fpu.o: demo/mister.c demo/soc.h FORCE | $(MI)
	$(CC) $(CFLAGS) $(OWN_CFLAGS) -DMISTER_FPU '-DGIT_SHORT="$(GIT_SHORT)"' -c $< -o $@
# No contraction: the host checksum tool computes the same roundings.
$(MI)/fmandel.o: demo/fmandel.c demo/soc.h demo/mandel.h | $(MI)
	$(CC) $(HF_CFLAGS) $(OWN_CFLAGS) -ffp-contract=off -c $< -o $@
$(WH)/full/whet_ref_smoke.h: $(SRC)/whetstone/whetstone.c demo/bench_gen.py demo/Makefile | $(WH)/full
	$(PYTHON) demo/bench_gen.py whetstone $< $(WHET_SMOKE_LOOP) $@ whet_smoke
$(WH)/full/glue-demo.o: $(WHET_GLUE_DEPS) $(WH)/full/whet_ref.h $(WH)/full/whet_ref_smoke.h
	$(CC) $(HF_BENCH_CFLAGS) $(OWN_CFLAGS) -I$(WH)/full -DWHET_DEMO $(WHET_full) -c $< -o $@
$(OUT)/mister-fpu.elf: LDFLAGS := -Wl,--no-warn-mismatch $(subst demo/demo.ld,demo/mister.ld,$(LDFLAGS))
$(OUT)/mister-fpu.elf: $(HF)/crt0.o $(filter-out $(OUT)/crt0.o $(MI)/mister.o,$(MISTER_OBJ)) \
	$(MI)/mister-fpu.o $(MI)/fmandel.o $(WH)/whetstone-hf.o $(WH)/full/glue-demo.o $(HF_FP_OBJ) \
	demo/mister.ld demo/mister-sections.ld
# Hard-float images: the same link without the floating-point check.
$(addprefix $(OUT)/,$(addsuffix .elf,$(HF_IMAGES))): $(OUT)/%.elf:
	$(CC) $(subst -msoft-float,-mhard-float,$(LDFLAGS)) -Wl,-Map,$(OUT)/$*.map $(filter %.o,$^) \
	  -Wl,--start-group $(filter %.a,$^) -Wl,--end-group -lgcc -o $@
	$(OBJDUMP) -d $@ > $(OUT)/$*.dump

# ---- opcode self-test (docs/SELFTEST.md) -------------------------------------
# One image per variant; the cases and expected values come from gen.py, and
# check_enc.py compares its instruction words with the assembler's. The
# MiSTer image is the 603e image. FP opcodes are the cases' own, so these
# images skip the floating-point check below.
ST := $(OUT)/selftest
ST_LDFLAGS := $(subst demo/demo.ld,demo/selftest/selftest.ld,$(LDFLAGS))
ST_OBJ := $(ST)/crt0.o $(ST)/runner.o $(OUT)/rt.o $(OUT)/font.o
# Extra definitions for selftest.c, e.g. ST_DEFS=-DST_FIRST=900.
ST_DEFS ?=
.PHONY: selftest mister-selftest
selftest: $(OUT)/selftest.hex $(OUT)/selftest-602.hex
mister-selftest: $(OUT)/mister-selftest.hex

.PRECIOUS: $(ST)/%/cases.h $(ST)/%/cases.S $(ST)/%/check.S
$(ST):
	mkdir -p $@
$(ST)/%/cases.h $(ST)/%/cases.S $(ST)/%/check.S: demo/selftest/gen.py ../sim/spec/isa.json
	$(PYTHON) demo/selftest/gen.py $* ../sim/spec/isa.json $(ST)/$*
$(ST)/crt0.o: demo/crt0.S | $(ST)
	$(CC) $(ARCH) -DCRT0_OWN_VECTORS -c $< -o $@
$(ST)/runner.o: demo/selftest/runner.S | $(ST)
	$(CC) $(ARCH) -c $< -o $@
$(ST)/%/cases.o: $(ST)/%/cases.S
	$(CC) $(ARCH) -c $< -o $@
$(ST)/%/check.ok: $(ST)/%/check.S $(ST)/%/cases.S demo/selftest/check_enc.py
	$(CC) $(ARCH) -Wa,-many -c $(ST)/$*/check.S -o $(ST)/$*/check.o
	$(OBJCOPY) -O binary -j .text $(ST)/$*/check.o $(ST)/$*/check.bin
	$(PYTHON) demo/selftest/check_enc.py $(ST)/$*/check.bin $(ST)/$*/cases.S
	touch $@
$(ST)/%/selftest.o: demo/selftest/selftest.c demo/selftest/selftest.h demo/soc.h $(ST)/%/cases.h
	$(CC) $(CFLAGS) $(OWN_CFLAGS) $(ST_DEFS) -I$(ST)/$* -Idemo/selftest -c $< -o $@
$(OUT)/selftest.elf: $(ST_OBJ) $(ST)/603e/selftest.o $(ST)/603e/cases.o $(ST)/603e/check.ok \
	demo/selftest/selftest.ld demo/mister-sections.ld
	$(CC) $(ST_LDFLAGS) -Wl,-Map,$(OUT)/selftest.map $(filter %.o,$^) -lgcc -o $@
	$(OBJDUMP) -d $@ > $(OUT)/selftest.dump
$(OUT)/selftest-602.elf: $(ST_OBJ) $(ST)/602/selftest.o $(ST)/602/cases.o $(ST)/602/check.ok \
	demo/selftest/selftest.ld demo/mister-sections.ld
	$(CC) $(ST_LDFLAGS) -Wl,-Map,$(OUT)/selftest-602.map $(filter %.o,$^) -lgcc -o $@
	$(OBJDUMP) -d $@ > $(OUT)/selftest-602.dump
$(OUT)/mister-selftest.hex: $(OUT)/selftest.hex
	cp $< $@

# ---- loadable MiSTer images (docs/MISTER_CORE.md#loading-programs) ----------
# The suite images as memory images of the RAM from 0xfff00000, for the
# core's Load program entry: the 256 bytes below the reset vector are zero.
# mister-images writes the full sizes to MISTER_IMAGES_DIR (the repository's
# build/ by default); mister-images-smoke the simulation sizes to $(OUT)/images.
MISTER_IMAGES_DIR ?= ../build/mister/images
MISTER_IMAGE_NAMES := selftest embench nbench whetstone whetstone-hf
.PHONY: mister-images mister-images-smoke
mister-images: $(addprefix $(MISTER_IMAGES_DIR)/ppc603e-,$(addsuffix .bin,$(MISTER_IMAGE_NAMES)))
mister-images-smoke: $(OUT)/images/ppc603e-selftest-smoke.bin \
	$(addprefix $(OUT)/images/ppc603e-,$(addsuffix -smoke.bin,$(filter-out selftest,$(MISTER_IMAGE_NAMES))))
define memory-image
	mkdir -p $(@D)
	$(OBJCOPY) -O binary $< $@.body
	head -c 256 /dev/zero | cat - $@.body > $@
	rm -f $@.body
endef
$(MISTER_IMAGES_DIR)/ppc603e-selftest.bin $(OUT)/images/ppc603e-selftest-smoke.bin: $(OUT)/selftest.elf
	$(memory-image)
$(MISTER_IMAGES_DIR)/ppc603e-%.bin: $(OUT)/mister-%.elf
	$(memory-image)
$(OUT)/images/ppc603e-%.bin: $(OUT)/mister-%.elf
	$(memory-image)

# The processor has no FPU: reject any floating-point instruction.
$(OUT)/%.elf:
	$(CC) $(LDFLAGS) -Wl,-Map,$(OUT)/$*.map $(filter %.o,$^) \
	  -Wl,--start-group $(filter %.a,$^) -Wl,--end-group -lgcc -o $@
	$(OBJDUMP) -d $@ > $(OUT)/$*.dump
	@if awk -F'\t' 'NF >= 3 {print $$3}' $(OUT)/$*.dump | grep -Eq '^(f[a-z]|lf|stf|mffs|mtfs)'; then \
	  echo "$@: floating-point instruction in image" >&2; rm -f $@; exit 1; fi

$(OUT)/%.hex: $(OUT)/%.elf demo/bin2hex64.py
	$(OBJCOPY) -O binary $< $(OUT)/$*.bin
	$(PYTHON) demo/bin2hex64.py $(OUT)/$*.bin 0x100 $@
