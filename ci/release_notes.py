#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Write markdown release notes from build summaries, the pins and git metadata."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from summary_table import detail, table  # noqa: E402


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True, check=False).stdout.strip()


def pin(path, pattern):
    match = re.search(pattern, (REPO / path).read_text(), re.MULTILINE)
    return match.group(1) if match else "unknown"


def repo_url(explicit):
    url = explicit
    if not url and os.environ.get("GITHUB_REPOSITORY"):
        url = f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{os.environ['GITHUB_REPOSITORY']}"
    if not url:
        url = git("remote", "get-url", "origin")
    url = re.sub(r"^git@([^:]+):", r"https://\1/", url)
    return re.sub(r"\.git$", "", url)


def embench_source(url, commit, embench):
    """GPL-3.0 section 6 source pointer for the Embench image, as plain text."""
    return "\n".join([
        "ppc603e-embench.bin: corresponding source",
        "",
        "ppc603e-embench.bin holds Embench-IoT object code (GPL-3.0-or-later), so the image is",
        "GPL-3.0. Its corresponding source, offered under GPL-3.0 section 6(d) from the same",
        "place as the image:",
        "",
        f"- Embench-IoT: https://github.com/embench/embench-iot/tree/{embench}",
        f"- Build scripts, glue and runtime: {url}/tree/{commit}",
        "  (toolchain/demo/fetch-benchmarks.sh, then",
        "  toolchain/build-in-container.sh -f demo/Makefile mister-images)",
        f"- Pinned compiler and runtime sources: {url}/blob/{commit}/docs/BENCHMARKS.md",
        "- All of the above fetched: ppc603e-source.tar.gz, published next to the image.",
        ""])


def doom_source(url, commit, doomgeneric, wad_sha):
    """GPL-2.0 source pointer for the Doom images, as plain text."""
    return "\n".join([
        "ppc603e-doom.bin, ppc603e-doom-le.bin: corresponding source",
        "",
        "The Doom images hold doomgeneric object code (GPL-2.0), so they are GPL-2.0. Their",
        "complete corresponding source is published with them (GPL-2.0 section 3(a)):",
        "",
        f"- doomgeneric: https://github.com/ozkl/doomgeneric/tree/{doomgeneric}",
        f"- Platform layer, C library and build scripts: {url}/tree/{commit}",
        "  (toolchain/demo/fetch-benchmarks.sh, toolchain/demo/fetch-doom.sh, then",
        "  toolchain/build-in-container.sh -f demo/Makefile mister-images)",
        "- All of the above fetched: ppc603e-source.tar.gz, published next to the images.",
        "",
        "DOOM1.WAD is not part of the images or of the source archive. It is id Software's",
        "shareware Doom v1.9 IWAD, published unmodified as its own file under the shareware",
        f"terms (free redistribution of the unmodified file, not for sale); SHA-256 {wad_sha}.",
        ""])


def quake_source(url, commit, quakegeneric, amiga_sha, pak_sha):
    """GPL-2.0 source pointer for the Quake images, as plain text."""
    return "\n".join([
        "ppc603e-quake.bin, ppc603e-quake-le.bin, ppc603e-quake-sf.bin: corresponding source",
        "",
        "The Quake images hold quakegeneric object code (GPL-2.0), and ppc603e-quake.bin also",
        "PowerPC assembly from Frank Wille's Amiga Quake 1.09 v2.30 source (GPL-2.0: \"Quake is",
        "published under the GNU Public License\", QuakeMOS.readme of that release), so they are",
        "GPL-2.0. Their complete corresponding source is published with them (GPL-2.0 section 3(a)):",
        "",
        f"- quakegeneric: https://github.com/erysdren/quakegeneric/tree/{quakegeneric}",
        "- Amiga Quake source: http://server.owl.de/~frank/quake1/2.30/Quake_src.lha",
        f"  (SHA-256 {amiga_sha})",
        f"- Platform layer, C library, conversion scripts and build scripts: {url}/tree/{commit}",
        "  (toolchain/demo/fetch-benchmarks.sh, toolchain/demo/fetch-quake.sh, then",
        "  toolchain/build-in-container.sh -f demo/Makefile mister-images)",
        "- All of the above fetched, the Amiga archives included: ppc603e-source.tar.gz,",
        "  published next to the images.",
        "",
        "pak0.pak is not part of the images or of the source archive. It is id Software's",
        "Quake v1.06 shareware data file, published unmodified as its own file under the shareware",
        f"terms (free redistribution of the unmodified file, not for sale); SHA-256 {pak_sha}.",
        ""])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summaries", nargs="*", type=Path)
    parser.add_argument("--title", default="", help="defaults to the tag or 'Unstable build'")
    parser.add_argument("--tag", default="")
    parser.add_argument("--since", default="", help="list commits since this ref")
    parser.add_argument("--repo-url", default="")
    parser.add_argument("--unstable", action="store_true")
    parser.add_argument("--images", nargs="*", type=Path, default=[], help="published program images")
    parser.add_argument("--embench-source", type=Path, help="also write the Embench image's source pointer here")
    parser.add_argument("--doom-source", type=Path, help="also write the Doom images' source pointer here")
    parser.add_argument("--quake-source", type=Path, help="also write the Quake images' source pointer here")
    args = parser.parse_args()

    summaries = [json.loads(path.read_text()) for path in args.summaries]
    commit = git("rev-parse", "HEAD")
    url = repo_url(args.repo_url)
    framework = pin("mister/fetch-framework.sh", r"^commit=([0-9a-f]{40})")
    embench = pin("toolchain/demo/fetch-benchmarks.sh", r"embench/embench-iot/([0-9a-f]{40})")
    doomgeneric = pin("toolchain/demo/fetch-doom.sh", r"ozkl/doomgeneric/tree/([0-9a-f]{40})")
    wad_sha = pin("toolchain/demo/fetch-doom.sh", r"^  ([0-9a-f]{64})$")
    quakegeneric = pin("toolchain/demo/fetch-quake.sh", r"erysdren/quakegeneric/tree/([0-9a-f]{40})")
    amiga_sha = pin("toolchain/demo/fetch-quake.sh", r"Quake_src\.lha \\\n  ([0-9a-f]{64})$")
    pak_sha = pin("toolchain/demo/fetch-quake.sh", r"id1/pak0\.pak\" \\\n  ([0-9a-f]{64})$")
    pins =dict(line.split("=", 1) for line in (REPO / "ci/pins.env").read_text().splitlines()
                if "=" in line and not line.startswith("#"))
    images = sorted(args.images, key=lambda path: path.name)
    names = [s["name"] for s in summaries] + [path.name for path in images]
    if args.embench_source:
        args.embench_source.write_text(embench_source(url, commit, embench))
    if args.doom_source:
        args.doom_source.write_text(doom_source(url, commit, doomgeneric, wad_sha))
    if args.quake_source:
        args.quake_source.write_text(quake_source(url, commit, quakegeneric, amiga_sha, pak_sha))

    out = [f"# {args.title or args.tag or 'Unstable build'}", ""]
    if args.unstable:
        out += ["Rolling build of `main`. Not a release: unverified on hardware and replaced by the next push.", ""]
    out += [f"Commit [`{commit[:12]}`]({url}/tree/{commit}), {git('show', '-s', '--format=%cs', commit)}: "
            f"{git('show', '-s', '--format=%s', commit)}", ""]
    stale = sorted({s["name"] for s in summaries if s["commit"] != commit or s["dirty"]})
    if stale:
        out += [f"**Warning:** built from another commit or a modified tree: {', '.join(stale)}.", ""]

    if summaries:
        out += ["## Fit and timing", "", "Slack in ns, worst over clocks and corners; each build's own SDC is the gate.",
                "", table(summaries), "", "<details><summary>Slack per clock and corner</summary>", "",
                detail(summaries), "", "</details>", ""]

    if images:
        out += ["## Program images", "",
                "Copy to `games/PPC603e/` on the SD card and open one with the core's OSD entry "
                f"`Load program` ([MiSTer core]({url}/blob/{commit}/docs/MISTER_CORE.md#loading-programs)).",
                "", "| File | SHA-256 |", "| --- | --- |"]
        out += [f"| `{path.name}` | `{hashlib.sha256(path.read_bytes()).hexdigest()}` |" for path in images]
        out += [""]

    out += ["## Pins", "",
            "| Input | Pin |", "| --- | --- |",
            f"| Quartus Prime Lite 17.0.2 | `{pins.get('QUARTUS_IMAGE_PIN', 'unknown')}` |",
            f"| Cross-compiler base | `{pins.get('TOOLCHAIN_BASE_IMAGE', 'unknown')}`, Debian snapshot "
            f"`{pins.get('TOOLCHAIN_DEBIAN_SNAPSHOT', 'unknown')}` |",
            f"| DingusPPC (comparison only) | `{pin('sim/cosim/reference_checkout.py', r'^LAST_VERIFIED = .([0-9a-f]{40}).')}` |",
            f"| MiSTer framework `sys/` (GPL-2.0) | [`{framework[:12]}`]"
            f"(https://github.com/MiSTer-devel/Template_MiSTer/tree/{framework}/sys) |", ""]

    out += ["## Licences", "",
            f"The core is GPL-2.0-or-later. A MiSTer `.rbf` also contains the MiSTer framework (GPL-2.0), so a distributed "
            f"`.rbf` is covered by GPL-2.0. Its corresponding source is this repository at "
            f"[`{commit[:12]}`]({url}/tree/{commit}) and the framework at "
            f"[`{framework[:12]}`](https://github.com/MiSTer-devel/Template_MiSTer/tree/{framework}).", ""]
    if any("embench" in name for name in names):
        out += ["**GPL-3.0 build:** the Embench bitstream's program RAM, or the Embench program image, holds "
                "Embench-IoT object code (GPL-3.0-or-later), so that file is GPL-3.0. Source offer: its "
                "corresponding source, offered from the same place as the image under GPL-3.0 section 6(d), is "
                f"this repository at [`{commit[:12]}`]({url}/tree/{commit}), Embench-IoT at "
                f"[`{embench[:12]}`](https://github.com/embench/embench-iot/tree/{embench}), and the pinned "
                "compiler and runtime sources listed in `docs/BENCHMARKS.md`; the attached "
                "`ppc603e-source.tar.gz` holds all of them and `ppc603e-embench.SOURCE.txt` "
                "lists them. Check that the combination with the GPL-2.0 "
                "framework is acceptable before redistributing an Embench bitstream.", ""]
    if any("doom" in name for name in names):
        out += ["**Doom:** `ppc603e-doom.bin` (big-endian) and `ppc603e-doom-le.bin` (little-endian) hold "
                "doomgeneric object code (GPL-2.0), so they are GPL-2.0; their corresponding source is this "
                f"repository at [`{commit[:12]}`]({url}/tree/{commit}), doomgeneric at "
                f"[`{doomgeneric[:12]}`](https://github.com/ozkl/doomgeneric/tree/{doomgeneric}) and the "
                "soft-float sources listed in `docs/BENCHMARKS.md`, all in the attached "
                "`ppc603e-source.tar.gz` and listed in `ppc603e-doom.SOURCE.txt`. `DOOM1.WAD` is id Software's "
                "shareware Doom v1.9 IWAD, distributed unmodified as its own file under the shareware terms "
                f"(free redistribution of the unmodified file, not for sale); SHA-256 `{wad_sha}`. Load it with "
                "`Load data` for the big-endian image or `Load data (little-endian)` for the little-endian "
                "one, then load the program.", ""]
    if any("quake" in name for name in names):
        out += ["**Quake:** `ppc603e-quake.bin` (hard float, big-endian, PowerPC assembly renderer), "
                "`ppc603e-quake-le.bin` (hard float, little-endian) and `ppc603e-quake-sf.bin` (soft float, "
                "any core) run a looping `timedemo demo1`. They hold quakegeneric object code (GPL-2.0), and the "
                "first also assembly from Frank Wille's Amiga Quake 1.09 v2.30 source (GPL-2.0), so they are "
                f"GPL-2.0; their corresponding source is this repository at [`{commit[:12]}`]({url}/tree/{commit}), "
                f"quakegeneric at [`{quakegeneric[:12]}`](https://github.com/erysdren/quakegeneric/tree/"
                f"{quakegeneric}), the Amiga source archive (SHA-256 `{amiga_sha}`) and the runtime sources "
                "listed in `docs/BENCHMARKS.md`, all in the attached `ppc603e-source.tar.gz` and listed in "
                "`ppc603e-quake.SOURCE.txt`. `pak0.pak` is id Software's Quake v1.06 shareware data file, "
                "distributed unmodified as its own file under the shareware terms (free redistribution of the "
                f"unmodified file, not for sale); SHA-256 `{pak_sha}`. Load it with `Load data` for the "
                "big-endian images or `Load data (little-endian)` for the little-endian one, then load the "
                "program.", ""]
    if any("nbench" in name for name in names):
        out += ["**nbench build:** BYTE's nbench code carries no stated licence. The nbench bitstream or image "
                "is for measurement; do not redistribute it without checking the terms.", ""]

    if args.since:
        log = git("log", "--no-merges", "--format=- %s (`%h`)", f"{args.since}..{commit}")
        out += [f"## Changes since {args.since}", "", log or "None.", ""]
    print("\n".join(out).rstrip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
