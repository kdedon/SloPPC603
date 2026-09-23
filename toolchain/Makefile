CROSS ?= powerpc-linux-gnu-
BUILD_DIR ?= build

CC := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
READELF := $(CROSS)readelf
PYTHON ?= python3

COMMON_CFLAGS := -std=c11 -O2 -g0 -ffreestanding -fno-builtin \
	-fno-stack-protector -fno-pic -fno-pie -fno-ident -ffunction-sections \
	-fdata-sections -ffile-prefix-map=$(CURDIR)=. -mcpu=603e -m32 \
	-msdata=none -msoft-float -Wall -Wextra -Werror
COMMON_ASFLAGS := -ffreestanding -fno-pic -fno-pie -mcpu=603e -m32 -msdata=none
COMMON_LDFLAGS := -nostdlib -nostartfiles -no-pie -Wl,--build-id=none \
	-Wl,--gc-sections -Wl,-T,link.ld

.PHONY: all be le check repro versions probe clean rtl-smoke

all: be le versions
be: $(BUILD_DIR)/be/smoke.elf $(BUILD_DIR)/be/smoke.bin $(BUILD_DIR)/be/smoke.dump
le: $(BUILD_DIR)/le/smoke.elf $(BUILD_DIR)/le/smoke.bin $(BUILD_DIR)/le/smoke.dump

$(BUILD_DIR)/be $(BUILD_DIR)/le:
	mkdir -p $@

$(BUILD_DIR)/be/crt0.o: crt0.S | $(BUILD_DIR)/be
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@

$(BUILD_DIR)/le/crt0.o: crt0.S | $(BUILD_DIR)/le
	$(CC) $(COMMON_ASFLAGS) -mlittle-endian -c $< -o $@

$(BUILD_DIR)/be/smoke.o: smoke.c | $(BUILD_DIR)/be
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@

$(BUILD_DIR)/le/smoke.o: smoke.c | $(BUILD_DIR)/le
	$(CC) $(COMMON_CFLAGS) -mlittle-endian -c $< -o $@

$(BUILD_DIR)/be/smoke.elf: $(BUILD_DIR)/be/crt0.o $(BUILD_DIR)/be/smoke.o link.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(COMMON_LDFLAGS) \
		-Wl,-Map,$(BUILD_DIR)/be/smoke.map $(filter %.o,$^) -o $@

$(BUILD_DIR)/le/smoke.elf: $(BUILD_DIR)/le/crt0.o $(BUILD_DIR)/le/smoke.o link.ld
	$(CC) $(COMMON_CFLAGS) -mlittle-endian $(COMMON_LDFLAGS) \
		-Wl,-Map,$(BUILD_DIR)/le/smoke.map $(filter %.o,$^) -o $@

$(BUILD_DIR)/%/smoke.bin: $(BUILD_DIR)/%/smoke.elf
	$(OBJCOPY) -O binary --remove-section=.comment $< $@

$(BUILD_DIR)/%/smoke.dump: $(BUILD_DIR)/%/smoke.elf
	cd $(dir $@) && $(OBJDUMP) -dr -s -t smoke.elf > smoke.dump

check: all
	$(PYTHON) check_artifacts.py \
		$(BUILD_DIR)/be/smoke.elf $(BUILD_DIR)/be/smoke.dump \
		$(BUILD_DIR)/le/smoke.elf $(BUILD_DIR)/le/smoke.dump

versions: | $(BUILD_DIR)
	{ \
		$(CC) --version | sed -n '1p'; \
		$(OBJDUMP) --version | sed -n '1p'; \
		$(PYTHON) --version; \
	} > $(BUILD_DIR)/tool-versions.txt

$(BUILD_DIR):
	mkdir -p $@

repro:
	./verify-repro.sh

probe:
	@for tool in $(CC) $(OBJCOPY) $(OBJDUMP) $(READELF) $(PYTHON); do \
		if command -v "$$tool" >/dev/null 2>&1; then \
			printf 'FOUND   %-32s %s\n' "$$tool" "$$(command -v "$$tool")"; \
		else \
			printf 'MISSING %-32s\n' "$$tool"; \
		fi; \
	done

clean:
	rm -rf -- "$(BUILD_DIR)"

# Optional compiler + Verilator acceptance gate; LE execution is unsupported.
rtl-smoke: be
	$(PYTHON) run-rtl-smoke.py --elf $(BUILD_DIR)/be/smoke.elf --build-dir $(BUILD_DIR)/rtl-smoke

.PHONY: alignment rtl-alignment
alignment: $(BUILD_DIR)/alignment/smoke.elf $(BUILD_DIR)/alignment/smoke.bin $(BUILD_DIR)/alignment/smoke.dump
$(BUILD_DIR)/alignment:
	mkdir -p $@
$(BUILD_DIR)/alignment/crt0.o: crt0.S | $(BUILD_DIR)/alignment
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_ALIGNMENT_SMOKE -c $< -o $@
$(BUILD_DIR)/alignment/main.o: alignment-smoke.c | $(BUILD_DIR)/alignment
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/alignment/handler.o: alignment-handler.S | $(BUILD_DIR)/alignment
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/alignment/smoke.elf: $(BUILD_DIR)/alignment/crt0.o $(BUILD_DIR)/alignment/main.o $(BUILD_DIR)/alignment/handler.o alignment.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,alignment.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/alignment/smoke.map $(filter %.o,$^) -o $@
rtl-alignment: alignment
	$(PYTHON) run-rtl-smoke.py --elf $(BUILD_DIR)/alignment/smoke.elf --build-dir $(BUILD_DIR)/rtl-alignment

.PHONY: fetch-fault rtl-fetch-fault
fetch-fault: $(BUILD_DIR)/fetch-fault/smoke.elf $(BUILD_DIR)/fetch-fault/smoke.bin $(BUILD_DIR)/fetch-fault/smoke.dump
$(BUILD_DIR)/fetch-fault:
	mkdir -p $@
$(BUILD_DIR)/fetch-fault/crt0.o: crt0.S | $(BUILD_DIR)/fetch-fault
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_FETCH_SMOKE -c $< -o $@
$(BUILD_DIR)/fetch-fault/main.o: fetch-smoke.c | $(BUILD_DIR)/fetch-fault
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/fetch-fault/handler.o: fetch-handler.S | $(BUILD_DIR)/fetch-fault
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/fetch-fault/smoke.elf: $(BUILD_DIR)/fetch-fault/crt0.o $(BUILD_DIR)/fetch-fault/main.o $(BUILD_DIR)/fetch-fault/handler.o fetch-fault.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,fetch-fault.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/fetch-fault/smoke.map $(filter %.o,$^) -o $@
rtl-fetch-fault: fetch-fault
	$(PYTHON) run-rtl-smoke.py --profile fetch-fault --elf $(BUILD_DIR)/fetch-fault/smoke.elf --build-dir $(BUILD_DIR)/rtl-fetch-fault

.PHONY: live-context rtl-live-context
live-context: $(BUILD_DIR)/live-context/smoke.elf $(BUILD_DIR)/live-context/smoke.bin $(BUILD_DIR)/live-context/smoke.dump
$(BUILD_DIR)/live-context:
	mkdir -p $@
$(BUILD_DIR)/live-context/crt0.o: crt0.S | $(BUILD_DIR)/live-context
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_LIVE_SMOKE -c $< -o $@
$(BUILD_DIR)/live-context/main.o: live-smoke.c | $(BUILD_DIR)/live-context
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/live-context/handler.o: live-handler.S | $(BUILD_DIR)/live-context
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/live-context/smoke.elf: $(BUILD_DIR)/live-context/crt0.o $(BUILD_DIR)/live-context/main.o $(BUILD_DIR)/live-context/handler.o live-context.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,live-context.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/live-context/smoke.map $(filter %.o,$^) -o $@
rtl-live-context: live-context
	$(PYTHON) run-rtl-smoke.py --profile live-context --elf $(BUILD_DIR)/live-context/smoke.elf --build-dir $(BUILD_DIR)/rtl-live-context

.PHONY: external-interrupt rtl-external-interrupt
external-interrupt: $(BUILD_DIR)/external-interrupt/smoke.elf $(BUILD_DIR)/external-interrupt/smoke.bin $(BUILD_DIR)/external-interrupt/smoke.dump
$(BUILD_DIR)/external-interrupt:
	mkdir -p $@
$(BUILD_DIR)/external-interrupt/crt0.o: crt0.S | $(BUILD_DIR)/external-interrupt
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_IRQ_SMOKE -c $< -o $@
$(BUILD_DIR)/external-interrupt/main.o: interrupt-smoke.c | $(BUILD_DIR)/external-interrupt
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/external-interrupt/handler.o: interrupt-handler.S | $(BUILD_DIR)/external-interrupt
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/external-interrupt/smoke.elf: $(BUILD_DIR)/external-interrupt/crt0.o $(BUILD_DIR)/external-interrupt/main.o $(BUILD_DIR)/external-interrupt/handler.o interrupt.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,interrupt.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/external-interrupt/smoke.map $(filter %.o,$^) -o $@
rtl-external-interrupt: external-interrupt
	$(PYTHON) run-rtl-smoke.py --profile external-interrupt --elf $(BUILD_DIR)/external-interrupt/smoke.elf --build-dir $(BUILD_DIR)/rtl-external-interrupt

.PHONY: timer rtl-timer
timer: $(BUILD_DIR)/timer/smoke.elf $(BUILD_DIR)/timer/smoke.bin $(BUILD_DIR)/timer/smoke.dump
$(BUILD_DIR)/timer:
	mkdir -p $@
$(BUILD_DIR)/timer/crt0.o: crt0.S | $(BUILD_DIR)/timer
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_TIMER_SMOKE -c $< -o $@
$(BUILD_DIR)/timer/main.o: timer-smoke.c | $(BUILD_DIR)/timer
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/timer/handler.o: timer-handler.S | $(BUILD_DIR)/timer
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/timer/smoke.elf: $(BUILD_DIR)/timer/crt0.o $(BUILD_DIR)/timer/main.o $(BUILD_DIR)/timer/handler.o timer.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,timer.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/timer/smoke.map $(filter %.o,$^) -o $@
rtl-timer: timer
	$(PYTHON) run-rtl-smoke.py --profile timer --elf $(BUILD_DIR)/timer/smoke.elf --build-dir $(BUILD_DIR)/rtl-timer

.PHONY: runtime-bat rtl-runtime-bat
runtime-bat: $(BUILD_DIR)/runtime-bat/smoke.elf $(BUILD_DIR)/runtime-bat/smoke.bin $(BUILD_DIR)/runtime-bat/smoke.dump
$(BUILD_DIR)/runtime-bat:
	mkdir -p $@
$(BUILD_DIR)/runtime-bat/crt0.o: crt0.S | $(BUILD_DIR)/runtime-bat
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_RUNTIME_BAT_SMOKE -c $< -o $@
$(BUILD_DIR)/runtime-bat/main.o: runtime-bat-smoke.c | $(BUILD_DIR)/runtime-bat
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/runtime-bat/handler.o: timer-handler.S | $(BUILD_DIR)/runtime-bat
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/runtime-bat/smoke.elf: $(BUILD_DIR)/runtime-bat/crt0.o $(BUILD_DIR)/runtime-bat/main.o $(BUILD_DIR)/runtime-bat/handler.o runtime-bat.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,runtime-bat.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/runtime-bat/smoke.map $(filter %.o,$^) -o $@
rtl-runtime-bat: runtime-bat
	$(PYTHON) run-rtl-smoke.py --profile runtime-bat --elf $(BUILD_DIR)/runtime-bat/smoke.elf --build-dir $(BUILD_DIR)/rtl-runtime-bat

.PHONY: dsi rtl-dsi
dsi: $(BUILD_DIR)/dsi/smoke.elf $(BUILD_DIR)/dsi/smoke.bin $(BUILD_DIR)/dsi/smoke.dump
$(BUILD_DIR)/dsi:
	mkdir -p $@
$(BUILD_DIR)/dsi/crt0.o: crt0.S | $(BUILD_DIR)/dsi
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_DSI_SMOKE -c $< -o $@
$(BUILD_DIR)/dsi/main.o: dsi-smoke.c | $(BUILD_DIR)/dsi
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/dsi/handler.o: dsi-handler.S | $(BUILD_DIR)/dsi
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/dsi/smoke.elf: $(BUILD_DIR)/dsi/crt0.o $(BUILD_DIR)/dsi/main.o $(BUILD_DIR)/dsi/handler.o dsi.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,dsi.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/dsi/smoke.map $(filter %.o,$^) -o $@
rtl-dsi: dsi
	$(PYTHON) run-rtl-smoke.py --profile dsi --elf $(BUILD_DIR)/dsi/smoke.elf --build-dir $(BUILD_DIR)/rtl-dsi

.PHONY: segment rtl-segment
segment: $(BUILD_DIR)/segment/smoke.elf $(BUILD_DIR)/segment/smoke.bin $(BUILD_DIR)/segment/smoke.dump
$(BUILD_DIR)/segment:
	mkdir -p $@
$(BUILD_DIR)/segment/crt0.o: crt0.S | $(BUILD_DIR)/segment
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_SEGMENT_SMOKE -c $< -o $@
$(BUILD_DIR)/segment/main.o: segment-smoke.c | $(BUILD_DIR)/segment
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/segment/handler.o: timer-handler.S | $(BUILD_DIR)/segment
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/segment/smoke.elf: $(BUILD_DIR)/segment/crt0.o $(BUILD_DIR)/segment/main.o $(BUILD_DIR)/segment/handler.o segment.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,segment.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/segment/smoke.map $(filter %.o,$^) -o $@
rtl-segment: segment
	$(PYTHON) run-rtl-smoke.py --profile segment --elf $(BUILD_DIR)/segment/smoke.elf --build-dir $(BUILD_DIR)/rtl-segment

.PHONY: page rtl-page
page: $(BUILD_DIR)/page/smoke.elf $(BUILD_DIR)/page/smoke.bin $(BUILD_DIR)/page/smoke.dump
$(BUILD_DIR)/page:
	mkdir -p $@
$(BUILD_DIR)/page/crt0.o: crt0.S | $(BUILD_DIR)/page
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_PAGE_SMOKE -c $< -o $@
$(BUILD_DIR)/page/main.o: page-smoke.c | $(BUILD_DIR)/page
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/page/handler.o: timer-handler.S | $(BUILD_DIR)/page
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/page/smoke.elf: $(BUILD_DIR)/page/crt0.o $(BUILD_DIR)/page/main.o $(BUILD_DIR)/page/handler.o $(BUILD_DIR)/page/probe.o page.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,page.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/page/smoke.map $(filter %.o,$^) -o $@
rtl-page: page
	$(PYTHON) run-rtl-smoke.py --profile page --elf $(BUILD_DIR)/page/smoke.elf --build-dir $(BUILD_DIR)/rtl-page
$(BUILD_DIR)/page/probe.o: page-probe.S | $(BUILD_DIR)/page
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@

.PHONY: tlbie rtl-tlbie
tlbie: $(BUILD_DIR)/tlbie/smoke.elf $(BUILD_DIR)/tlbie/smoke.bin $(BUILD_DIR)/tlbie/smoke.dump
$(BUILD_DIR)/tlbie:
	mkdir -p $@
$(BUILD_DIR)/tlbie/crt0.o: crt0.S | $(BUILD_DIR)/tlbie
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_TLBIE_SMOKE -c $< -o $@
$(BUILD_DIR)/tlbie/main.o: tlbie-smoke.c | $(BUILD_DIR)/tlbie
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/tlbie/handler.o: timer-handler.S | $(BUILD_DIR)/tlbie
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/tlbie/smoke.elf: $(BUILD_DIR)/tlbie/crt0.o $(BUILD_DIR)/tlbie/main.o $(BUILD_DIR)/tlbie/handler.o $(BUILD_DIR)/tlbie/probe.o tlbie.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,tlbie.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/tlbie/smoke.map $(filter %.o,$^) -o $@
rtl-tlbie: tlbie
	$(PYTHON) run-rtl-smoke.py --profile tlbie --elf $(BUILD_DIR)/tlbie/smoke.elf --build-dir $(BUILD_DIR)/rtl-tlbie
$(BUILD_DIR)/tlbie/probe.o: tlbie-probe.S | $(BUILD_DIR)/tlbie
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@

.PHONY: tlbload rtl-tlbload
tlbload: $(BUILD_DIR)/tlbload/smoke.elf $(BUILD_DIR)/tlbload/smoke.bin $(BUILD_DIR)/tlbload/smoke.dump
$(BUILD_DIR)/tlbload:
	mkdir -p $@
$(BUILD_DIR)/tlbload/crt0.o: crt0.S | $(BUILD_DIR)/tlbload
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_TLBLOAD_SMOKE -c $< -o $@
$(BUILD_DIR)/tlbload/main.o: tlbload-smoke.c | $(BUILD_DIR)/tlbload
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/tlbload/handler.o: timer-handler.S | $(BUILD_DIR)/tlbload
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/tlbload/smoke.elf: $(BUILD_DIR)/tlbload/crt0.o $(BUILD_DIR)/tlbload/main.o $(BUILD_DIR)/tlbload/handler.o $(BUILD_DIR)/tlbload/probe.o tlbload.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,tlbload.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/tlbload/smoke.map $(filter %.o,$^) -o $@
rtl-tlbload: tlbload
	$(PYTHON) run-rtl-smoke.py --profile tlbload --elf $(BUILD_DIR)/tlbload/smoke.elf --build-dir $(BUILD_DIR)/rtl-tlbload
$(BUILD_DIR)/tlbload/probe.o: tlbie-probe.S | $(BUILD_DIR)/tlbload
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@

.PHONY: page-dsi rtl-page-dsi
page-dsi: $(BUILD_DIR)/page-dsi/smoke.elf $(BUILD_DIR)/page-dsi/smoke.bin $(BUILD_DIR)/page-dsi/smoke.dump
$(BUILD_DIR)/page-dsi:
	mkdir -p $@
$(BUILD_DIR)/page-dsi/crt0.o: crt0.S | $(BUILD_DIR)/page-dsi
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_PAGE_DSI_SMOKE -c $< -o $@
$(BUILD_DIR)/page-dsi/main.o: page-dsi-smoke.c | $(BUILD_DIR)/page-dsi
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/page-dsi/handler.o: page-dsi-handler.S | $(BUILD_DIR)/page-dsi
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/page-dsi/smoke.elf: $(BUILD_DIR)/page-dsi/crt0.o $(BUILD_DIR)/page-dsi/main.o $(BUILD_DIR)/page-dsi/handler.o page-dsi.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,page-dsi.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/page-dsi/smoke.map $(filter %.o,$^) -o $@
rtl-page-dsi: page-dsi
	$(PYTHON) run-rtl-smoke.py --profile page-dsi --elf $(BUILD_DIR)/page-dsi/smoke.elf --build-dir $(BUILD_DIR)/rtl-page-dsi

.PHONY: page-isi rtl-page-isi
page-isi: $(BUILD_DIR)/page-isi/smoke.elf $(BUILD_DIR)/page-isi/smoke.bin $(BUILD_DIR)/page-isi/smoke.dump
$(BUILD_DIR)/page-isi:
	mkdir -p $@
$(BUILD_DIR)/page-isi/crt0.o: crt0.S | $(BUILD_DIR)/page-isi
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_PAGE_ISI_SMOKE -c $< -o $@
$(BUILD_DIR)/page-isi/main.o: page-isi-smoke.c | $(BUILD_DIR)/page-isi
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/page-isi/handler.o: page-isi-handler.S | $(BUILD_DIR)/page-isi
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/page-isi/probe.o: page-probe.S | $(BUILD_DIR)/page-isi
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/page-isi/smoke.elf: $(BUILD_DIR)/page-isi/crt0.o $(BUILD_DIR)/page-isi/main.o $(BUILD_DIR)/page-isi/handler.o $(BUILD_DIR)/page-isi/probe.o page-isi.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,page-isi.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/page-isi/smoke.map $(filter %.o,$^) -o $@
rtl-page-isi: page-isi
	$(PYTHON) run-rtl-smoke.py --profile page-isi --elf $(BUILD_DIR)/page-isi/smoke.elf --build-dir $(BUILD_DIR)/rtl-page-isi

.PHONY: page-miss rtl-page-miss
page-miss: $(BUILD_DIR)/page-miss/smoke.elf $(BUILD_DIR)/page-miss/smoke.bin $(BUILD_DIR)/page-miss/smoke.dump
$(BUILD_DIR)/page-miss:
	mkdir -p $@
$(BUILD_DIR)/page-miss/crt0.o: crt0.S | $(BUILD_DIR)/page-miss
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_TLBLOAD_SMOKE -c $< -o $@
$(BUILD_DIR)/page-miss/main.o: tlbload-smoke.c | $(BUILD_DIR)/page-miss
	$(CC) $(COMMON_CFLAGS) -mbig-endian -DPAGE_MISS_STORE_PROBE -c $< -o $@
$(BUILD_DIR)/page-miss/handler.o: timer-handler.S | $(BUILD_DIR)/page-miss
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/page-miss/smoke.elf: $(BUILD_DIR)/page-miss/crt0.o $(BUILD_DIR)/page-miss/main.o $(BUILD_DIR)/page-miss/handler.o $(BUILD_DIR)/page-miss/probe.o tlbload.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,tlbload.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/page-miss/smoke.map $(filter %.o,$^) -o $@
rtl-page-miss: page-miss
	$(PYTHON) run-rtl-smoke.py --profile page-miss --elf $(BUILD_DIR)/page-miss/smoke.elf --build-dir $(BUILD_DIR)/rtl-page-miss
$(BUILD_DIR)/page-miss/probe.o: page-miss-probe.S tlbie-probe.S | $(BUILD_DIR)/page-miss
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@

.PHONY: sdr1 rtl-sdr1
sdr1: $(BUILD_DIR)/sdr1/smoke.elf $(BUILD_DIR)/sdr1/smoke.bin $(BUILD_DIR)/sdr1/smoke.dump
$(BUILD_DIR)/sdr1:
	mkdir -p $@
$(BUILD_DIR)/sdr1/crt0.o: crt0.S | $(BUILD_DIR)/sdr1
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_LIVE_SMOKE -c $< -o $@
$(BUILD_DIR)/sdr1/main.o: sdr1-smoke.c | $(BUILD_DIR)/sdr1
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/sdr1/smoke.elf: $(BUILD_DIR)/sdr1/crt0.o $(BUILD_DIR)/sdr1/main.o mmu-state.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,mmu-state.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/sdr1/smoke.map $(filter %.o,$^) -o $@
rtl-sdr1: sdr1
	$(PYTHON) run-rtl-smoke.py --profile sdr1 --elf $(BUILD_DIR)/sdr1/smoke.elf --build-dir $(BUILD_DIR)/rtl-sdr1

.PHONY: tgpr rtl-tgpr
tgpr: $(BUILD_DIR)/tgpr/smoke.elf $(BUILD_DIR)/tgpr/smoke.bin $(BUILD_DIR)/tgpr/smoke.dump
$(BUILD_DIR)/tgpr:
	mkdir -p $@
$(BUILD_DIR)/tgpr/crt0.o: crt0.S | $(BUILD_DIR)/tgpr
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_LIVE_SMOKE -c $< -o $@
$(BUILD_DIR)/tgpr/main.o: tgpr-smoke.c | $(BUILD_DIR)/tgpr
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/tgpr/smoke.elf: $(BUILD_DIR)/tgpr/crt0.o $(BUILD_DIR)/tgpr/main.o $(BUILD_DIR)/tgpr/probe.o mmu-state.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,mmu-state.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/tgpr/smoke.map $(filter %.o,$^) -o $@
rtl-tgpr: tgpr
	$(PYTHON) run-rtl-smoke.py --profile tgpr --elf $(BUILD_DIR)/tgpr/smoke.elf --build-dir $(BUILD_DIR)/rtl-tgpr
$(BUILD_DIR)/tgpr/probe.o: tgpr-probe.S | $(BUILD_DIR)/tgpr
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@

.PHONY: miss-entry rtl-miss-entry
miss-entry: $(BUILD_DIR)/miss-entry/smoke.elf $(BUILD_DIR)/miss-entry/smoke.bin $(BUILD_DIR)/miss-entry/smoke.dump
$(BUILD_DIR)/miss-entry:
	mkdir -p $@
$(BUILD_DIR)/miss-entry/crt0.o: crt0.S | $(BUILD_DIR)/miss-entry
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_PAGE_ISI_SMOKE -c $< -o $@
$(BUILD_DIR)/miss-entry/main.o: miss-entry-smoke.c | $(BUILD_DIR)/miss-entry
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/miss-entry/handler.o: miss-entry-handler.S | $(BUILD_DIR)/miss-entry
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/miss-entry/probe.o: page-probe.S | $(BUILD_DIR)/miss-entry
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/miss-entry/smoke.elf: $(BUILD_DIR)/miss-entry/crt0.o $(BUILD_DIR)/miss-entry/main.o $(BUILD_DIR)/miss-entry/handler.o $(BUILD_DIR)/miss-entry/probe.o miss-entry.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,miss-entry.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/miss-entry/smoke.map $(filter %.o,$^) -o $@
rtl-miss-entry: miss-entry
	$(PYTHON) run-rtl-smoke.py --profile miss-entry --elf $(BUILD_DIR)/miss-entry/smoke.elf --build-dir $(BUILD_DIR)/rtl-miss-entry

.PHONY: table-search rtl-table-search
table-search: $(BUILD_DIR)/table-search/smoke.elf $(BUILD_DIR)/table-search/smoke.bin $(BUILD_DIR)/table-search/smoke.dump
$(BUILD_DIR)/table-search:
	mkdir -p $@
$(BUILD_DIR)/table-search/crt0.o: crt0.S | $(BUILD_DIR)/table-search
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_PAGE_ISI_SMOKE -c $< -o $@
$(BUILD_DIR)/table-search/main.o: table-search-smoke.c | $(BUILD_DIR)/table-search
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/table-search/handler.o: table-search-handler.S | $(BUILD_DIR)/table-search
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/table-search/probe.o: page-probe.S | $(BUILD_DIR)/table-search
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/table-search/smoke.elf: $(BUILD_DIR)/table-search/crt0.o $(BUILD_DIR)/table-search/main.o $(BUILD_DIR)/table-search/handler.o $(BUILD_DIR)/table-search/probe.o table-search.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,table-search.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/table-search/smoke.map $(filter %.o,$^) -o $@
rtl-table-search: table-search
	$(PYTHON) run-rtl-smoke.py --profile table-search --elf $(BUILD_DIR)/table-search/smoke.elf --build-dir $(BUILD_DIR)/rtl-table-search

.PHONY: table-fault rtl-table-fault
table-fault: $(BUILD_DIR)/table-fault/smoke.elf $(BUILD_DIR)/table-fault/smoke.bin $(BUILD_DIR)/table-fault/smoke.dump
$(BUILD_DIR)/table-fault:
	mkdir -p $@
$(BUILD_DIR)/table-fault/crt0.o: crt0.S | $(BUILD_DIR)/table-fault
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -DENABLE_PAGE_ISI_SMOKE -c $< -o $@
$(BUILD_DIR)/table-fault/main.o: table-fault-smoke.c | $(BUILD_DIR)/table-fault
	$(CC) $(COMMON_CFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/table-fault/handler.o: table-search-handler.S | $(BUILD_DIR)/table-fault
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/table-fault/vector.o: table-fault-vector.S | $(BUILD_DIR)/table-fault
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/table-fault/probe.o: page-probe.S | $(BUILD_DIR)/table-fault
	$(CC) $(COMMON_ASFLAGS) -mbig-endian -c $< -o $@
$(BUILD_DIR)/table-fault/smoke.elf: $(BUILD_DIR)/table-fault/crt0.o $(BUILD_DIR)/table-fault/main.o $(BUILD_DIR)/table-fault/handler.o $(BUILD_DIR)/table-fault/vector.o $(BUILD_DIR)/table-fault/probe.o table-fault.ld
	$(CC) $(COMMON_CFLAGS) -mbig-endian $(subst link.ld,table-fault.ld,$(COMMON_LDFLAGS)) \
		-Wl,-Map,$(BUILD_DIR)/table-fault/smoke.map $(filter %.o,$^) -o $@
rtl-table-fault: table-fault
	$(PYTHON) run-rtl-smoke.py --profile table-fault --elf $(BUILD_DIR)/table-fault/smoke.elf --build-dir $(BUILD_DIR)/rtl-table-fault

.PHONY: rtl-table-search-bus rtl-table-fault-bus
rtl-table-search-bus: table-search
	$(PYTHON) run-rtl-smoke.py --profile table-search-bus --elf $(BUILD_DIR)/table-search/smoke.elf --build-dir $(BUILD_DIR)/rtl-table-search-bus
rtl-table-fault-bus: table-fault
	$(PYTHON) run-rtl-smoke.py --profile table-fault-bus --elf $(BUILD_DIR)/table-fault/smoke.elf --build-dir $(BUILD_DIR)/rtl-table-fault-bus

.PHONY: rtl-table-search-cached rtl-table-fault-cached
rtl-table-search-cached: table-search
	$(PYTHON) run-rtl-smoke.py --profile table-search-cached --elf $(BUILD_DIR)/table-search/smoke.elf --build-dir $(BUILD_DIR)/rtl-table-search-cached
rtl-table-fault-cached: table-fault
	$(PYTHON) run-rtl-smoke.py --profile table-fault-cached --elf $(BUILD_DIR)/table-fault/smoke.elf --build-dir $(BUILD_DIR)/rtl-table-fault-cached
