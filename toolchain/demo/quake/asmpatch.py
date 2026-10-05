#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Copies the quakegeneric engine sources for the build with the Amiga
PowerPC assembly renderer: the C definitions of the functions the assembly
provides are removed, as the original port's '#if !defined(PPCASM)' blocks
do, file-scope variables the assembly reads lose 'static', and the span
drawer follows d_subdiv16 (16-pixel perspective steps) as the original
engine's assembly builds do. Every edit must apply exactly once.

Usage: asmpatch.py engine-dir out-dir"""
import os
import re
import sys

ASM = {
    'd_edge.c': ['D_CalcGradients', 'D_DrawSurfaces'],
    'd_polyse.c': ['D_PolysetDrawSpans8', 'D_PolysetRecursiveTriangle', 'D_PolysetSetUpForLineScan',
                   'D_PolysetCalcGradients', 'D_PolysetScanLeftEdge', 'D_DrawNonSubdiv',
                   'D_DrawSubdiv'],
    'd_scan.c': ['D_WarpScreen', 'Turbulent8', 'D_DrawSpans8', 'D_DrawZSpans'],
    'd_sky.c': ['D_DrawSkyScans8'],
    'd_surf.c': ['D_CacheSurface'],
    'mathlib.c': ['anglemod', 'BoxOnPlaneSide', 'AngleVectors', 'VectorMA', 'CrossProduct', 'Length',
                  'VectorNormalize', 'VectorInverse', 'VectorScale', 'FloorDivMod'],
    'r_aclip.c': ['R_Alias_clip_left', 'R_Alias_clip_right', 'R_Alias_clip_top',
                  'R_Alias_clip_bottom', 'R_AliasClip'],
    'r_alias.c': ['R_AliasTransformVector', 'R_AliasTransformFinalVert', 'R_AliasProjectFinalVert'],
    'r_bsp.c': ['R_RotateBmodel'],
    'r_draw.c': ['R_EmitEdge', 'R_ClipEdge'],
    'r_edge.c': ['R_InsertNewEdges', 'R_RemoveEdges', 'R_StepActiveU', 'R_GenerateSpans'],
    'r_light.c': ['RecursiveLightPoint'],
    'r_misc.c': ['TransformVector'],
    'r_surf.c': ['R_DrawSurfaceBlock8_mip0', 'R_DrawSurfaceBlock8_mip1', 'R_DrawSurfaceBlock8_mip2',
                 'R_DrawSurfaceBlock8_mip3'],
}
UNSTATIC = {
    'd_edge.c': ['miplevel'],
    'r_alias.c': ['ziscale'],
    'r_draw.c': ['makeleftedge'],
}
REPLACE = {
    'd_init.c': [('d_drawspans = D_DrawSpans8;',
                  'd_drawspans = d_subdiv16.value ? D_DrawSpans16 : D_DrawSpans8;')],
}


def remove_function(text, name):
    m = re.search(r'^[A-Za-z_][\w \t\*]*\b%s[ \t]*\([^;{]*\)\s*\{' % name, text, re.M)
    if not m:
        sys.exit(f'asmpatch: no definition of {name}')
    depth, i = 0, m.end() - 1
    while True:
        depth += {'{': 1, '}': -1}.get(text[i], 0)
        i += 1
        if depth == 0:
            break
    text = text[:m.start()] + f'/* {name}: PowerPC assembly */' + text[i:]
    # Static prototypes would now name undefined functions.
    return re.sub(r'^static([ \t][^;{]*\b%s[ \t]*\()' % name, r'extern\1', text, flags=re.M)


def main(argv):
    if len(argv) != 2:
        sys.exit(__doc__)
    src, out = argv
    os.makedirs(out, exist_ok=True)
    for name in os.listdir(src):
        if name.endswith(('.c', '.h')):
            with open(os.path.join(src, name), "rb") as f:
                data = f.read()
            with open(os.path.join(out, name), "wb") as f:
                f.write(data)
    for name in sorted(set(ASM) | set(UNSTATIC) | set(REPLACE)):
        path = os.path.join(out, name)
        text = open(path, encoding='latin-1').read()
        for fn in ASM.get(name, []):
            text = remove_function(text, fn)
        for var in UNSTATIC.get(name, []):
            text, n = re.subn(r'^static([ \t][^;(]*\b%s\b)' % var, r'\1', text, flags=re.M)
            if n != 1:
                sys.exit(f'asmpatch: {name}: {var} declared static {n} times')
        for old, new in REPLACE.get(name, []):
            if text.count(old) != 1:
                sys.exit(f'asmpatch: {name}: {old!r} found {text.count(old)} times')
            text = text.replace(old, new)
        open(path, 'w', encoding='latin-1').write(text)


if __name__ == '__main__':
    main(sys.argv[1:])
