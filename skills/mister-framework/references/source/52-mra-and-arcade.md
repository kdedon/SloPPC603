# MRA and Arcade Cores

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer` f35083f3b40d, `Main_MiSTer` 136737b4bed4, `MkDocs_MiSTer` 9033bd292fdc, `Distribution_MiSTer` beb65fea786d
> Load with: [21-hps-io-ioctl-and-download.md](21-hps-io-ioctl-and-download.md), [11-conf-str.md](11-conf-str.md), [40-video.md](40-video.md)
> Status mix: [C] [V] [O] [I]

## 1. Purpose & one-line summary

An MRA is an XML manifest that tells `Main_MiSTer` how to assemble an arcade ROM image at boot — concatenating parts pulled from MAME-format ZIPs, applying byte-mux/interleave, and streaming the result to the FPGA on a chosen `ioctl_index`. The arcade core consumes that stream the same way any core consumes an `ioctl_download`, but with the assembly logic moved off-FPGA into the MRA spec. `arcade_video.v` is an unrelated `sys/` helper that wraps `video_mixer` for cores with a packed-RGB pixel bus and an optional CW/CCW screen-rotation framebuffer.

## 2. The contract (must-obey)

- The XML root element is `<misterromdescription>`. [C] ([[`MkDocs_MiSTer/docs/developer/mra.md:17-95`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L17-L95)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L17-L95))
- `<rbf>` names the core RBF (no path, no `.rbf` extension); MiSTer launches that core after assembly. [C] ([[`MkDocs_MiSTer/docs/developer/mra.md:115`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L115)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L115))
- `<setname>` overrides the core's CONF_STR ID for per-romset settings (saves, dips). [C] ([[`MkDocs_MiSTer/docs/developer/mra.md:112`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L112)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L112))
- Each `<rom>` block emits one ioctl download; the `index` attribute is passed verbatim to `user_io_set_index(...)` before the data stream. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:327-367`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L327-L367)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L327-L367))
- `<rom index="0">` is the main game ROM; `index="1"`..`index="n"` deliver side-channel data (game-select byte, region byte, etc.) and the core reads them by gating on `ioctl_index`. [V] ([[`MkDocs_MiSTer/docs/developer/mra.md:38-43`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L38-L43)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L38-L43))
- `<part>` elements inside a `<rom>` are concatenated into `romdata[]` in document order; the offset where any part lands depends entirely on the size of every preceding sibling. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:853-880`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L853-L880)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L853-L880))
- A `<part>` is either a file reference (has `name=`, optional `zip=`, `offset=`, `length=`, `crc=`, `map=`) or inline hex content (text body, optional `repeat=` byte count). [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:572-590`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L572-L590)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L572-L590))
- File references resolve against `<rom zip="...">` unless the `<part>` carries its own `zip=` attribute, which overrides for that part only. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:882-895`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L882-L895)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L882-L895))
- The `<rom zip>` attribute accepts a `|`-separated list of ZIP names; the loader walks the list until one ZIP yields the file. [V] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:890-915`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L890-L915)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L890-L915))
- `<part crc="...">`: 8-hex-digit CRC32 of the file inside the ZIP; if a name does not match, the loader falls back to selecting by CRC. [C] ([[`MkDocs_MiSTer/docs/developer/mra.md:123`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L123)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L123))
- `<part repeat="N">XX</part>` repeats the inline hex sequence `XX...` for `N` bytes total (N is byte count, not iteration count); decimal by default, hex with `0x` prefix. [C] ([[`MkDocs_MiSTer/docs/developer/mra.md:124`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L124)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L124))
- `<part map="HHHH">` (hex-digit string, 4-16 nibbles) selects which input bytes of an interleaved stream go to which output lane; `1` picks byte 0, `2` picks byte 1, etc., `0` skips. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:230-283`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L230-L283)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L230-L283))
- `<interleave output="N">` (with N in `{8,16,24,32,40,48,56,64}`) is required around a sibling group of `map=`-bearing parts and sets the output-word width for byte-multiplexing. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:749-774`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L749-L774)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L749-L774))
- `<patch offset="O">` followed by hex bytes overwrites the assembled ROM at byte offset `O` for the length of the inline content; runs after all parts in that `<rom>` are concatenated. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:312-325`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L312-L325)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L312-L325))
- `<rom md5="...">`: lowercase 32-char MD5 of the fully-assembled stream; mismatch aborts unless `md5="none"` or the attribute is absent. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:800-846`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L800-L846)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L800-L846))
- A second `<rom index="0">` block, if present, is tried only when the first one fails its MD5 check — it is a fallback set, not an additional stream. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:836-841`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L836-L841)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L836-L841))
- `<switches default="b0,b1,b2,...">`: hex bytes, leftmost = bits 7:0, second = bits 15:8, etc.; loaded into the working DIP state at startup. [C] ([[`MkDocs_MiSTer/docs/developer/mra.md:140-146`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L140-L146)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L140-L146))
- `<dip bits="b"|"b,e">`: declares one OSD item covering bit `b` (single) or `b..e` (range); range size is `e-b+1` and the OSD writes those bits into a 64-bit DIP word. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:633-650`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L633-L650)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L633-L650))
- The current DIP word is shipped to the core on `ioctl_index=254` whenever DIPs change. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:120-130`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L120-L130)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L120-L130))
- `<nvram index="I" size="S">` enables `ioctl_upload` of `S` bytes on the OSD "Save Settings" action via `ioctl_index=I` and replay on next boot. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:62-113`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L62-L113)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L62-L113))
- `<romstruct>`, `<remark>`, `<about>`, `<category>`, `<year>`, `<manufacturer>`, `<region>`, `<homebrew>`, `<bootleg>`, `<series>`, `<rotation>`, `<flip>`, `<resolution>`, `<players>`, `<joystick>`, `<num_buttons>`, `<mratimestamp>`, `<mameversion>` are metadata only — recorded by the loader but not propagated to the FPGA. [O] ([[`MkDocs_MiSTer/docs/developer/mra.md:117-120`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L117-L120)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L117-L120))
- `<buttons names="..." default="...">` overrides the OSD's per-button label and default mapping for the joystick bits the core reports (names map to `joystick_X[4..]`, leaving bits 0-3 for directions). [C] ([[`MkDocs_MiSTer/docs/developer/mra.md:116`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L116)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L116))
- XML lexing is performed by the embedded sxmlc 4.2.7 library — generic SAX-style parser, MRA semantics live entirely in `mra_loader.cpp`. [O] ([[`Main_MiSTer/sxmlc.h:30-33`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/sxmlc.h#L30-L33)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/sxmlc.h#L30-L33))
- `arcade_video.v` is purely a video helper: it converts a packed `RGB_in[DW-1:0]` (`DW` ∈ {6,8,9,12,18,24}) into 8R8G8B, fixes HS/VS sync edges with `sync_fix`, then drives the framework's `video_mixer` with scandoubler/HQ2x/gamma options. It does not parse MRA or touch ioctl. [C] ([[`Template_MiSTer/sys/arcade_video.v:29-143`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/arcade_video.v#L29-L143)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/arcade_video.v#L29-L143))

## 3. Elements & attributes reference

```xml
<!-- https://github.com/MiSTer-devel/Distribution_MiSTer/blob/beb65fea786d3c897221724cfe797cc193965b27/_Arcade/Asteroids.mra#L1-L18 -->
<misterromdescription>
    <name>Asteroids (rev 4)</name>
    <mameversion>0220</mameversion>
    <setname>asteroid</setname>
    <year>1979</year>
    <manufacturer>Atari</manufacturer>
    <rbf>asteroids</rbf>
    <rom index="0" zip="asteroid.zip" md5="1bcd2899e3f92d2824a2ac9def2d3286">
        <part crc="b503eaf7" name="035145-04e.ef2"/>
        <part crc="25233192" name="035144-04e.h2"/>
        <part crc="312caa02" name="035143-02.j2"/>
        <part crc="8b71fd9e" name="035127-02.np3"/>
        <part crc="97953db8" name="034602-01.c8"/>
    </rom>
</misterromdescription>
```

| Element | Where | Attributes (req?) | Body | Produces |
| --- | --- | --- | --- | --- |
| `<misterromdescription>` | root | — | child elements | parser entry. [C] |
| `<rbf>` | root | — | text: RBF basename | core to launch. [C] |
| `<setname>` | root | — | text | overrides CONF_STR ID for saves/DIPs. [C] |
| `<name>` | root | — | text | OSD display title. [V] |
| `<mratimestamp>`, `<mameversion>`, `<year>`, `<manufacturer>`, `<category>` | root | — | text | metadata only. [O] |
| `<buttons>` | root | `names=` (no), `default=` (no) | — | OSD button labels & defaults. [C] |
| `<rom>` | root | `index=` (yes for non-zero), `zip=` (when parts use files), `md5=` (no), `address=` (no), `type=` (no, advisory) | child `<part>`/`<interleave>`/`<patch>` | one ioctl download stream tagged with `ioctl_index`. [C] |
| `<part>` (file ref) | inside `<rom>` or `<interleave>` | `name=` (yes), `zip=` (no, overrides parent), `crc=` (no), `offset=` (no), `length=` (no), `map=` (no), `repeat=` (no) | empty | file bytes appended to `romdata[]`. [C] |
| `<part>` (inline) | inside `<rom>` or `<interleave>` | `repeat=` (no, byte count) | hex text body | literal bytes appended. [C] |
| `<interleave>` | inside `<rom>` | `output=` (yes, bits ∈ {8..64} mod 8), `input=` (no, default 8) | child `<part>` group | sets byte-mux unit width for siblings. [C] |
| `<patch>` | inside `<rom>` | `offset=` (yes), `operation=` (no; `"xor"` or absent) | hex text body | overwrites or XORs `romdata[offset..]` after concatenation. [C] |
| `<switches>` | root | `default=` (no, hex byte list), `base=` (no, OSD numbering base) | child `<dip>` | DIP defaults & set declaration. [C] |
| `<dip>` | inside `<switches>` | `bits=` (yes, `b` or `b,e`), `name=` (yes), `ids=` (yes, comma list), `values=` (no, comma list) | — | one OSD DIP entry; appends to 64-bit DIP word. [C] |
| `<nvram>` | root | `index=` (yes), `size=` (yes) | — | enables save/restore via `ioctl_index` on Save Settings. [C] |
| `<romstruct>`, `<remark>`, `<about>`, `<region>`, `<homebrew>`, `<bootleg>`, `<version>`, `<alternative>`, `<platform>`, `<series>`, `<resolution>`, `<rotation>`, `<flip>`, `<players>`, `<joystick>`, `<special_controls>`, `<num_buttons>`, `<parent>` | root | — | text | metadata, ignored by FPGA-side. [O] |

- `index="0"` is the conventional main-ROM stream; the core reads it as `ioctl_download && !ioctl_index`. [V] ([[`MkDocs_MiSTer/docs/developer/mra.md:121`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L121)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L121))
- `index="1"` (and higher non-reserved indices) carry side-channel bytes the core reads with an explicit `ioctl_index==N` gate. [V] ([[`MkDocs_MiSTer/docs/developer/mra.md:38-43`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L38-L43)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L38-L43), [`99-105`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L99-L105))
- `index="254"` is reserved by the framework for the DIP word push and must not appear as a `<rom>` index. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:125-127`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L125-L127)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L125-L127))
- `<rom address="0xADDR">` (when present) sends the assembled ROM directly into FPGA-mapped memory at `ADDR` via `shmem_put` instead of through the ioctl stream — used by cores that want a DMA-style load. [O] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:340-346`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L340-L346)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L340-L346))
- `<part map=>` outside an `<interleave>` parent still works but is rare; the loader expands `unitlen` from the `map` string length and emits a sparse stream. [I] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:600-609`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L600-L609)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L600-L609))
- `<part crc>` only meaningful when `name` is also set; CRC32 is matched against the ZIP's central directory and is used to recover when the upstream MAME zip renames a file. [C] ([[`MkDocs_MiSTer/docs/developer/mra.md:123`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L123)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L123))
- `<part offset>` and `<part length>` apply to the source file, not to `romdata[]`; the source is seeked to `offset` and at most `length` bytes are read. [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:285-310`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L285-L310)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L285-L310))
- Inline `<part>` hex content tolerates whitespace, commas, tabs, and `\r\n` between byte pairs. [O] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:402-419`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L402-L419)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L402-L419))

## 4. Sequencing & timing

MRA assembly is HPS-side and runs once at core launch. No FPGA clock domains are involved during XML parsing; only the final ioctl streams are on `clk_sys`.

```
HPS:  parse XML --+--> for each <rom>:
                  |        rom_start(index)
                  |        for each <part>: read file or hex, append to romdata[]
                  |                          (apply map/interleave byte-mux into romdata[])
                  |        for each <patch>: memcpy or XOR into romdata[offset..]
                  |        MD5(romdata) ?= <rom md5="..">  ---no---> retry next <rom index="0"> if any
                  |                                                  else flag error, stop
                  |        user_io_set_index(<rom index>)
                  |        user_io_set_download(1, address?len:0)
                  |        chunked user_io_file_tx_data(romdata, ...)   <-- streamed to FPGA
                  |        user_io_set_download(0)
                  |
                  +--> for <nvram>:    user_io_set_index(<nvram index>)
                  |                    user_io_file_tx_data(nvram_blob, size)  (if file exists)
                  |
                  +--> for <switches>: collect DIP layout; later
                                       user_io_set_index(254)
                                       user_io_file_tx_data(&dip_cur, sizeof(dip_cur))

FPGA: hps_io drives ioctl_download, ioctl_wr, ioctl_addr, ioctl_dout, ioctl_index.
      Core typically does:
        always @(posedge clk_sys) if (ioctl_wr && !ioctl_index) rom[ioctl_addr] <= ioctl_dout;
        always @(posedge clk_sys) if (ioctl_wr && ioctl_index==1) tno <= ioctl_dout[3:0];
        always @(posedge clk_sys) if (ioctl_wr && ioctl_index==254 && !ioctl_addr[24:3])
                                     sw[ioctl_addr[2:0]] <= ioctl_dout;
```

Order guarantees:
- All `<part>` siblings under one `<rom>` are streamed contiguously — `ioctl_addr` counts from 0 to `len-1` for that stream.
- `<patch>` is applied to `romdata[]` *before* the stream goes out, so the FPGA never sees the pre-patch image.
- Different `<rom>` blocks are independent ioctl streams: `ioctl_download` goes low between them, `ioctl_index` changes, then `ioctl_download` goes high again. The core sees them as discrete transactions, not one concatenated transfer.
- `<switches>` and `<nvram>` push happen during init too, but on their own `ioctl_index` values (254 and the declared NVRAM index respectively).

Byte-mux example for `<interleave output="32">` with four sibling `<part>`s carrying `map="0001"`, `map="0010"`, `map="0100"`, `map="1000"`: each file contributes one byte per 32-bit unit, the four bytes interleaved to lane 0, 1, 2, 3 respectively. The loader pre-sizes the buffer by replicating `romlen[0]` into `romlen[1..7]` (mra_loader.cpp:607-608, 773) so writes at the higher offsets don't reallocate per-byte.

## 5. Minimal working pattern

The Pac-Man (Midway) MRA is the canonical compact example — single `<rom index="0">`, a fallback ZIP list, and a full `<switches>`/`<dip>` block.

```xml
<!-- https://github.com/MiSTer-devel/Distribution_MiSTer/blob/beb65fea786d3c897221724cfe797cc193965b27/_Arcade/_alternatives/_Pac-Man/Pac-Man (Midway).mra#L1-L36 -->
<misterromdescription>
    <name>Pac-Man (Midway)</name>
    <mameversion>0218</mameversion>
    <setname>pacman</setname>
    <mratimestamp>20200225084106</mratimestamp>
    <year>1980</year>
    <manufacturer>Namco (Midway license)</manufacturer>
    <category>Maze / Pac-Man</category>
    <rotation>vertical (cw)</rotation>
    <rbf>pacman</rbf>
    <switches default="FF,FF,C9">
        <dip bits="15"    name="Cabinet" ids="Cocktail,Upright"/>
        <dip bits="16,17" name="Coinage" ids="2c/1cr,1c/1cr,1c/2cr,Free Play" values="3,1,2,0"/>
        <dip bits="18,19" name="Lives" ids="1,2,3,5"/>
        <dip bits="20,21" name="Bonus Life After" ids="10000,15000,20000,None"/>
        <dip bits="22"    name="Difficulty" ids="Hard,Normal"/>
    </switches>
    <rom index="0" zip="puckman.zip|pacman.zip" md5="ce706464631f450f385314c90876321d">
        <part crc="c1e6ab10" name="pacman.6e"/>
        <part crc="1a6fb2d4" name="pacman.6f"/>
        <part crc="bcdd1beb" name="pacman.6h"/>
        <part crc="817d94e3" name="pacman.6j"/>
        <part crc="c1e6ab10" name="pacman.6e"/>
        <part crc="1a6fb2d4" name="pacman.6f"/>
        <part crc="bcdd1beb" name="pacman.6h"/>
        <part crc="817d94e3" name="pacman.6j"/>
        <part crc="0c944964" name="pacman.5e"/>
        <part crc="958fedf9" name="pacman.5f"/>
        <part crc="958fedf9" name="pacman.5f"/>
        <part crc="958fedf9" name="pacman.5f"/>
        <part crc="a9cc86bf" name="82s126.1m"/>
        <part crc="3eb3a8e4" name="82s126.4a"/>
        <part crc="77245b66" name="82s126.3m"/>
        <part crc="2fc650bd" name="82s123.7f"/>
    </rom>
</misterromdescription>
```

Annotation:
- `<rbf>pacman</rbf>` → `_Arcade/cores/pacman.rbf` is launched.
- `<rom index="0" zip="puckman.zip|pacman.zip">` → MiSTer tries `/games/mame/puckman.zip` first, then `/games/mame/pacman.zip`.
- Each `<part name="...">` appends that file's full content to `romdata[]`. Repeated `pacman.6e/6f/6h/6j` lines mirror the ROM image into a second 16K window because the original board decoded address bit `A14` as a mirror.
- After all parts are appended, MD5 must equal `ce70...321d`; mismatch aborts.
- The 24-bit DIP word starts at `FF FF C9` (byte 0 → bits 7:0, byte 1 → bits 15:8, byte 2 → bits 23:16). DIP edits via the OSD update bits 15..22 inside that word and push the result on `ioctl_index=254`.

A second compact example showing `<interleave>` byte-mux (Crater Raider, MCR3 hardware, 4-way 32-bit word):

```xml
<!-- https://github.com/MiSTer-devel/Distribution_MiSTer/blob/beb65fea786d3c897221724cfe797cc193965b27/_Arcade/Crater Raider.mra#L50-L59 -->
<interleave output="32">
    <part crc="579a8e36" map="0001" name="crvid.a4"></part>
    <part crc="2c2f5b29" map="0001" name="crvid.a3"></part>
    <part crc="5bf954e0" map="0010" name="crvid.a6"></part>
    <part crc="9bdec312" map="0010" name="crvid.a5"></part>
    <part crc="4b913498" map="0100" name="crvid.a8"></part>
    <part crc="9fa307d5" map="0100" name="crvid.a7"></part>
    <part crc="7a22d6bc" map="1000" name="crvid.a10"></part>
    <part crc="811f152d" map="1000" name="crvid.a9"></part>
</interleave>
```

And an embedded-fill pattern from the same file (Crater Raider line 44):

```xml
<!-- https://github.com/MiSTer-devel/Distribution_MiSTer/blob/beb65fea786d3c897221724cfe797cc193965b27/_Arcade/Crater Raider.mra#L44 -->
<part repeat="0x4000">FF</part>
```

That inserts 0x4000 bytes of `0xFF` into `romdata[]` — useful for filling unmapped windows so subsequent parts land at the correct offset.

## 6. Common variations across cores

[deferred — reference cores not fetched]

Framework-implied invariants that do not depend on a specific core:

- Console cores (e.g., NES, SNES, Genesis) do not use MRA. They mount a single ROM via the OSD file picker and the file moves through `hps_io` ioctl as a single stream tagged with the slot's ioctl index. The MRA assembly path is exclusive to arcade cores launched from `_Arcade/*.mra`. [I] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:1-50`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L1-L50)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L1-L50))
- An arcade core with multiple ROM streams declares multiple `<rom>` blocks with different `index` values; the core reads each on its own `ioctl_index==N` gate. The `<rom index="1">` "game-select byte" idiom in the MRA docs is one such case — a one-byte stream carrying the variant ID for multi-game cores like Pac-Man derivatives or Druaga/Mappy on the same RBF. [V] ([[`MkDocs_MiSTer/docs/developer/mra.md:38-43`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L38-L43)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L38-L43), [`99-105`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L99-L105))
- A core can mix MRA-assembled ROM (FPGA load via ioctl) and DDR-targeted load by setting `<rom address="0x...">`. The HPS writes via `shmem_put` directly into the FPGA-visible DDR window instead of pushing through `ioctl_file_tx_data`. Used when ROM is too large to live in fabric BRAM and the core wires its address bus directly to DDR. [O] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:340-346`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L340-L346)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L340-L346))
- The `arcade_video.v` helper is optional even for arcade cores: cores can wire `video_mixer` or `ascal` directly. Cores that use it commit to one of the supported packed-RGB widths (6, 8, 9, 12, 18, 24). [V] ([[`Template_MiSTer/sys/arcade_video.v:21-29`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/arcade_video.v#L21-L29)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/arcade_video.v#L21-L29))
- `<switches>`/`<dip>` is independent of CONF_STR `O[..]` bits but writes a *separate* 64-bit DIP word delivered on `ioctl_index=254`. Cores that want both must keep the bit spaces disjoint (see §7 A.3 and `11-conf-str.md`). [C] ([[`Main_MiSTer/support/arcade/mra_loader.cpp:120-130`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L120-L130)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L120-L130))

## 7. Anti-patterns

### A.1 Wrong `<part>` order

- **Symptom:** ROM looks correct in size and MD5 may even match if you regenerated it, but the core jumps to garbage, shows wrong tiles, or hangs at boot.
- **Cause:** Parts are concatenated in document order and the core's address decoder is hardcoded to specific offsets. Swapping two `<part>` lines moves every byte after the swap by the size delta.
- **Fix:** Take part order from the upstream `mame/src/mame/drivers/*.cpp` `ROM_LOAD` sequence (or copy from a known-good MRA for the same hardware). Verify with the `<rom md5>` against a trusted reference.
- **Citation:** [[`Main_MiSTer/support/arcade/mra_loader.cpp:853-880`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L853-L880)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L853-L880)

### A.2 `<part repeat="N">` treated as iteration count

- **Symptom:** Inline fill region is the wrong size; later parts misaligned by a small offset; "ROM #0: file_finish: 0xN bytes sent" log line shows wrong total.
- **Cause:** `repeat` is the total byte length to emit, not the number of times to repeat the literal. `<part repeat="3">FF</part>` emits 3 bytes; `<part repeat="0x4000">FF</part>` emits 16384 bytes. The literal `FF` is the fill pattern, replayed as needed.
- **Fix:** Use the byte count you actually want. For non-`FF` fills, the literal can be a multi-byte sequence — `<part repeat="0x10">DEADBEEF</part>` emits 16 bytes by truncating the 4-byte pattern.
- **Citation:** [[`MkDocs_MiSTer/docs/developer/mra.md:124`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L124)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L124); [[`Main_MiSTer/support/arcade/mra_loader.cpp:584-586`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L584-L586)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L584-L586), [`900-934`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L900-L934)

### A.3 DIP `<dip bits>` overlapping a CONF_STR `O[..]` bit

- **Symptom:** Changing one OSD option silently flips another; status bits drift; behaviour depends on which OSD entry was touched last.
- **Cause:** CONF_STR `O[N]` writes the framework `status[N]` word; `<dip bits="N">` writes the same numeric bit but in a *different* word that arrives on `ioctl_index=254`. If the core wires both into the same destination register or if the developer chose the same bit index, the two channels race.
- **Fix:** Reserve disjoint bit ranges in your core. Common convention: `status[31:0]` for CONF_STR options, MRA DIPs land in their own `sw[8]` register array gated on `ioctl_index==254`. Do not redeclare the same setting in both layers. See `11-conf-str.md` for the CONF_STR side and `21-hps-io-ioctl-and-download.md` for the ioctl path.
- **Citation:** [[`Main_MiSTer/support/arcade/mra_loader.cpp:120-130`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L120-L130)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L120-L130); [[`MkDocs_MiSTer/docs/developer/mra.md:132-138`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L132-L138)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md#L132-L138)

### A.4 No ZIP-list fallback when MAME renames files

- **Symptom:** Existing MRA stops loading after a MAME version bump; "file not found" error referencing a file name that does still exist (under a different ZIP).
- **Cause:** MAME renames its ZIPs across versions (e.g., `puckman.zip` ↔ `pacman.zip`). A `<rom zip="pacman.zip">` with no fallback fails when the user has the older ZIP name.
- **Fix:** Use the pipe-list form `<rom zip="puckman.zip|pacman.zip">`. The loader walks left-to-right and uses the first ZIP that resolves the part. Also set `<part crc="...">` so the loader can pick the right file by CRC even if MAME renamed a single ROM inside the ZIP.
- **Citation:** [[`Main_MiSTer/support/arcade/mra_loader.cpp:882-921`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L882-L921)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L882-L921)

### A.5 `map` without an `<interleave>` parent

- **Symptom:** ROM image is sparse / mostly zeros / the core indexes correct bytes but they read as 0xFF or 0x00; size of `romdata[]` is unexpectedly large.
- **Cause:** A `<part map=>` outside `<interleave>` triggers the "8-stream pre-sized" path: the loader replicates `romlen[0]` into `romlen[1..7]` once at parse time (line 607), but each `map` byte still lands at its own lane offset. Without sibling parts filling the other lanes, those bytes stay as whatever was already in `romdata[]` (often unmapped/zero or the previous data's tail).
- **Fix:** Wrap byte-multiplexed parts in `<interleave output="N">` with `N` matching the total lane width. For a single-lane copy without interleaving, omit `map` entirely.
- **Citation:** [[`Main_MiSTer/support/arcade/mra_loader.cpp:600-609`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L600-L609)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L600-L609), [`749-774`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L749-L774)

## 8. Verification

- Run the core from the Linux console: `/media/fat/MiSTer rbffilename mrafilename`. The loader prints each part's offset and final size, the MD5 verdict, and `file_finish: 0xN bytes sent to FPGA` for each `<rom>` block. ([[`Main_MiSTer/support/arcade/mra_loader.cpp:367`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L367)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L367))
- The `Assembling ROM #N` / `Loading` / `Sending` progress messages appear on the OSD; absence or partial progress points to a missing ZIP / wrong file name. ([[`Main_MiSTer/support/arcade/mra_loader.cpp:351-354`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L351-L354)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L351-L354), [`776`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp#L776))
- MD5 mismatch is logged as `*** Checksum mismatch` with both the declared and the computed digest. Set `md5="none"` during development to bypass the check, but never ship that way.
- For DIP issues: confirm the OSD shows the expected entries from `<switches>`; toggle and watch `sw[]` updates inside the core in simulation by driving `ioctl_index=254` with crafted addresses (low 3 bits select the byte lane, see the example in `developer/mra.md:135-138`).
- For interleave issues: dump the first few hundred bytes of `romdata[]` and compare against the MAME hardware spec. Mismatches usually look like adjacent bytes swapped (wrong `map` nibble order) or every other byte zero (missing sibling `<part>` for that lane).
- For `arcade_video.v`: verify `CE_PIXEL` aligns with `ce_pix` rising edges and that `RGB_in` is sampled on the cycle after `ce_pix=1`. The internal `RGB_fix` register adds one CE-cycle latency. ([[`Template_MiSTer/sys/arcade_video.v:63-77`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/arcade_video.v#L63-L77)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/arcade_video.v#L63-L77))

## 9. Provenance footer

- [[`Template_MiSTer/sys/arcade_video.v`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/arcade_video.v)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/arcade_video.v) — used for §2, §6, §8
- [[`Distribution_MiSTer/_Arcade/Asteroids.mra`](https://github.com/MiSTer-devel/Distribution_MiSTer/blob/beb65fea786d3c897221724cfe797cc193965b27/_Arcade/Asteroids.mra)](https://github.com/MiSTer-devel/Distribution_MiSTer/blob/beb65fea786d3c897221724cfe797cc193965b27/_Arcade/Asteroids.mra) — used for §3 (skeleton excerpt)
- [`Distribution_MiSTer/_Arcade/_alternatives/_Pac-Man/Pac-Man (Midway).mra`](https://github.com/MiSTer-devel/Distribution_MiSTer/blob/beb65fea786d3c897221724cfe797cc193965b27/_Arcade/_alternatives/_Pac-Man/Pac-Man (Midway).mra) — used for §5 (minimal pattern)
- [`Distribution_MiSTer/_Arcade/Crater Raider.mra`](https://github.com/MiSTer-devel/Distribution_MiSTer/blob/beb65fea786d3c897221724cfe797cc193965b27/_Arcade/Crater Raider.mra) — used for §5 (interleave & repeat-fill excerpts)
- [[`MkDocs_MiSTer/docs/developer/mra.md`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mra.md) — used for §1, §2, §3, §4, §6, §7
- [[`MkDocs_MiSTer/docs/developer/mrasetnames.md`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mrasetnames.md)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mrasetnames.md) — used for §2 (setname/rbf coupling), §6
- [[`Main_MiSTer/support/arcade/mra_loader.cpp`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/support/arcade/mra_loader.cpp) — used for §2, §3, §4, §6, §7, §8 (primary parser semantics)
- [[`Main_MiSTer/sxmlc.h`](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/sxmlc.h)](https://github.com/MiSTer-devel/Main_MiSTer/blob/136737b4bed4d5ba58216efdcede0094ae8e8041/sxmlc.h) — used for §2 (lexer identity)
