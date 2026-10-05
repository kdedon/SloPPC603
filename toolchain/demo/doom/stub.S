/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Reset stub of the Doom images, always big-endian, at 0xfff00100. It maps
 * the image window (BAT0), the device window (DBAT1) and the 32 MiB data
 * window at 0 (BAT2), enables the caches, and enters the program at
 * 0xfff01500 through rfi with translation on; with STUB_LE it sets MSR[ILE]
 * first and enters in little-endian mode. r3 = 0 marks a fresh start. */
#define SPR_HID0 1008

    .text
    .globl _stub
_stub:
    li 0,0
    mtspr 528,0
    mtspr 530,0
    mtspr 532,0
    mtspr 534,0
    mtspr 536,0
    mtspr 538,0
    mtspr 540,0
    mtspr 542,0
    isync
    /* BAT0: 0xfff00000, 1 MiB, cacheable, read/write. */
    lis 5,0xfff0
    ori 5,5,0x001e
    lis 6,0xfff0
    ori 6,6,0x0002
    mtspr 529,6
    mtspr 528,5
    mtspr 537,6
    mtspr 536,5
    /* DBAT1: 0xf0000000, 4 MiB, inhibited and guarded. */
    lis 5,0xf000
    ori 5,5,0x007e
    lis 6,0xf000
    ori 6,6,0x002a
    mtspr 539,6
    mtspr 538,5
    /* BAT2: 0x00000000, 32 MiB, cacheable, read/write. */
    li 5,0x03fe
    li 6,0x0002
    mtspr 533,6
    mtspr 532,5
    mtspr 541,6
    mtspr 540,5
    isync
    /* Invalidate and enable the instruction cache, then the data cache. */
    li 5,0
    ori 5,5,0x8800
    mtspr SPR_HID0,5
    li 5,0
    ori 5,5,0x8000
    mtspr SPR_HID0,5
    isync
    sync
    ori 5,5,0x4400
    mtspr SPR_HID0,5
    li 5,0
    ori 5,5,0xc000
    mtspr SPR_HID0,5
    isync
    mfmsr 5
#ifdef STUB_LE
    oris 5,5,0x0001
    mtmsr 5
    isync
    ori 5,5,0x0031
#else
    ori 5,5,0x0030
#endif
    mtsrr1 5
    lis 4,0xfff0
    ori 4,4,0x1500
    mtsrr0 4
    li 3,0
    rfi
