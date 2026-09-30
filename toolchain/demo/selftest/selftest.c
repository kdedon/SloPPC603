/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Opcode self-test (docs/SELFTEST.md). Runs every generated case, prints a
 * summary and each failure on the console, and draws the results as pages
 * of cells. With an input device present, it waits on each page: arrows
 * select a cell, whose details show below the grid; A or Enter turns the
 * page, B or Esc turns back. Without one, it draws every page in turn and
 * exits with the number of failed cases. Cases that need an FPU run only
 * when the MODE register reports one. */
#include "soc.h"
#include "selftest.h"
#include "cases.h"

/* The first case to run, and ST_PROGRESS to print each case number:
 * debugging aids. */
#ifndef ST_FIRST
#define ST_FIRST 0
#endif

/* Cell geometry, in text cells. */
#define CELL_W 10
#define NAME_W 8
#define DETAIL_ROWS 8

static uint32_t in_st[ST_NFIELDS] __attribute__((aligned(8)));
static uint32_t act_st[ST_NFIELDS] __attribute__((aligned(8)));
static uint32_t exp_st[ST_NFIELDS], mask_st[ST_NFIELDS];
uint32_t st_fp;
/* The cases this processor runs, and per case the differing fields (255
 * at most); both by position in that list. */
static uint16_t idx[ST_NCASES];
static uint8_t result[ST_NCASES];
static int ncases, grid_cols, grid_rows, per_page, pages;

static void st_init(void)
{
  uint32_t msr;
  /* Machine checks are taken, not checkstops. */
  __asm__ volatile("mfmsr %0" : "=r"(msr));
  msr |= 0x1000;
  __asm__ volatile("mtmsr %0; isync" : : "r"(msr));
  /* Segment 3 is direct-store (T = 1); the others are empty. */
  for (uint32_t sr = 0; sr < 16; sr++)
    __asm__ volatile("mtsrin %0,%1" : : "r"(sr == 3 ? 0x80000000u : 0), "r"(sr << 28));
  /* Empty TLB: one tlbie per congruence class. */
  for (uint32_t i = 0; i < 64; i++) __asm__ volatile("tlbie %0" : : "r"(i << 12));
  __asm__ volatile("sync; tlbsync; sync; isync");
  /* RAM valid in problem state too (Vp), for the user-mode cases. */
  __asm__ volatile("mtspr 528,%0; mtspr 536,%0; isync" : : "r"(0xfff0001fu));
  /* DBAT2: 0x10020000 read-only alias of 0xfff20000; IBAT2: 0x20020000
   * with no access. 128 KiB, supervisor and user valid. */
  __asm__ volatile("mtspr 541,%0; mtspr 540,%1; mtspr 533,%2; mtspr 532,%3; isync"
                   : : "r"(0xfff20001u), "r"(0x10020003u), "r"(0xfff20000u), "r"(0x20020003u));
#if ST_HAVE_EAR
  __asm__ volatile("mtspr 282,%0" : : "r"(0));
#endif
}

/* Runs case n into act_st; returns the number of differing fields. */
static int run_case(int n)
{
  const struct st_case *c = &st_cases[n];
  uint32_t base = (uint32_t)c->code;
  for (int f = 0; f < ST_NFIELDS; f++) in_st[f] = st_default[f];
  for (int k = 0; k < c->in_n; k++) {
    const struct st_kv *kv = &st_kv[c->in_first + k];
    in_st[kv->field & ST_FIELD] = kv->value + (kv->field & ST_REL ? base : 0);
  }
  for (int f = 0; f < ST_NFIELDS; f++) {
    exp_st[f] = in_st[f];
    mask_st[f] = 0xffffffffu;
  }
  exp_st[F_VEC] = exp_st[F_SRR0] = exp_st[F_SRR1] = 0;
  for (int k = 0; k < c->ex_n; k++) {
    const struct st_kv *kv = &st_kv[c->ex_first + k];
    exp_st[kv->field & ST_FIELD] = kv->value + (kv->field & ST_REL ? base : 0);
    mask_st[kv->field & ST_FIELD] = kv->mask;
  }
  for (int i = 0; i < ST_BUF_WORDS; i++) ST_BUF[i] = in_st[F_BUF + i];
  st_enter(in_st, act_st, c->code);
  /* The sc at st_done ends the case: its SRR1 is the case's MSR. */
  if (act_st[F_VEC] == 0xc00 && act_st[F_SRR0] == (uint32_t)st_done + 4) {
    act_st[F_MSR] = act_st[F_SRR1];
    act_st[F_VEC] = act_st[F_SRR0] = act_st[F_SRR1] = 0;
  }
  for (int i = 0; i < ST_BUF_WORDS; i++) act_st[F_BUF + i] = ST_BUF[i];
  /* Without an FPU the runner leaves the FP state alone. */
  if (!st_fp)
    for (int f = F_FPR; f <= F_FPSCR; f++) act_st[f] = in_st[f];
  int bad = 0;
  for (int f = 0; f < ST_NFIELDS; f++)
    if ((act_st[f] ^ exp_st[f]) & mask_st[f]) bad++;
  return bad;
}

static int differs(int f) { return ((act_st[f] ^ exp_st[f]) & mask_st[f]) != 0; }

/* The register classes that differ, as a short list. */
static void diff_classes(char *out, int size)
{
  static const struct { const char *name; int first, last; } cls[] = {
    {"GPR", 0, 31}, {"CR", F_CR, F_CR}, {"XER", F_XER, F_XER}, {"LR", F_LR, F_LR},
    {"CTR", F_CTR, F_CTR}, {"VEC", F_VEC, F_VEC}, {"SRR", F_SRR0, F_SRR1},
    {"MSR", F_MSR, F_MSR}, {"DAR", F_DAR, F_DSISR}, {"MEM", F_BUF, F_FPR - 1},
    {"FPR", F_FPR, F_FPSCR - 1}, {"FPSCR", F_FPSCR, F_FPSCR}};
  int len = 0;
  out[0] = 0;
  for (unsigned i = 0; i < sizeof cls / sizeof cls[0]; i++)
    for (int f = cls[i].first; f <= cls[i].last; f++)
      if (differs(f)) {
        len += snprintf(out + len, (size_t)(size - len), "%s%s", len ? " " : "", cls[i].name);
        break;
      }
}

static void report_failure(int n)
{
  const struct st_case *c = &st_cases[n];
  char cls[64];
  run_case(n);
  diff_classes(cls, sizeof cls);
  printf("FAIL %d %s %s: %s [%s]\n", n, st_group_name[c->group], c->name, c->text, cls);
  for (int f = 0; f < ST_NFIELDS; f++)
    if (differs(f))
      printf("  %-5s exp %08lx got %08lx mask %08lx\n", st_field_name[f],
             (unsigned long)exp_st[f], (unsigned long)act_st[f], (unsigned long)mask_st[f]);
}

/* ---- screen ------------------------------------------------------------------ */

static const uint8_t glyph_pass[8] = {0x00, 0x03, 0x06, 0xcc, 0x78, 0x30, 0x00, 0x00};
static const uint8_t glyph_fail[8] = {0x00, 0x66, 0x3c, 0x18, 0x3c, 0x66, 0x00, 0x00};

static void put_glyph(int col, int row, const uint8_t *g, uint8_t fg, uint8_t bg)
{
  int s = con_scale;
  for (int y = 0; y < 8 * s; y++) {
    volatile uint8_t *p = fb_pixels + (row * con_cell + y) * fb_stride + col * con_cell;
    for (int x = 0; x < con_cell; x++) p[x] = ((g[y / s] << (x / s)) & 0x80) ? fg : bg;
  }
}

/* s cut or padded to exactly w characters. */
static void fit(char *out, const char *s, int w)
{
  int i = 0;
  for (; i < w && s[i]; i++) out[i] = s[i];
  for (; i < w; i++) out[i] = ' ';
  out[w] = 0;
}

/* Text at a cell position, cleared to the right edge. */
static void put_text(int col, int row, uint8_t fg, uint8_t bg, const char *s)
{
  char buf[256];
  int room = con_cols - col;
  if (room <= 0) return;
  fit(buf, s, room < 255 ? room : 255);
  con_color(fg, bg);
  con_goto(col, row);
  con_puts(buf);
}

static void cell_pos(int n, int *col, int *row)
{
  int k = n % per_page;
  *col = (k % grid_cols) * CELL_W;
  *row = 2 + k / grid_cols;
}

static void draw_cell(int s, int selected)
{
  char name[NAME_W + 1];
  int col, row;
  cell_pos(s, &col, &row);
  uint8_t bg = selected ? 1 : 0;
  fit(name, st_cases[idx[s]].name, NAME_W);
  put_glyph(col, row, result[s] ? glyph_fail : glyph_pass, result[s] ? 12 : 10, bg);
  con_color(result[s] ? 15 : 7, bg);
  con_goto(col + 1, row);
  con_puts(name);
}

static void draw_details(int s)
{
  int n = idx[s];
  const struct st_case *c = &st_cases[n];
  int top = con_rows - 1 - DETAIL_ROWS;
  char line[256], cls[64];
  fb_rect(0, top * con_cell, fb_width, DETAIL_ROWS * con_cell, 0);
  snprintf(line, sizeof line, "#%d %s  %s  %s", n, st_group_name[c->group], c->name,
           result[s] ? "FAIL" : "pass");
  put_text(0, top, result[s] ? 12 : 10, 0, line);
  put_text(0, top + 1, 15, 0, c->text);
  /* Operands: the case's inputs. */
  int len = snprintf(line, sizeof line, "in");
  for (int k = 0; k < c->in_n && len < (int)sizeof line - 24; k++) {
    const struct st_kv *kv = &st_kv[c->in_first + k];
    len += snprintf(line + len, sizeof line - (size_t)len, " %s=%lx%s",
                    st_field_name[kv->field & ST_FIELD], (unsigned long)kv->value,
                    kv->field & ST_REL ? "+pc" : "");
  }
  put_text(0, top + 2, 7, 0, line);
  if (!result[s]) return;
  run_case(n);
  diff_classes(cls, sizeof cls);
  snprintf(line, sizeof line, "differ: %s", cls);
  put_text(0, top + 3, 14, 0, line);
  int row = top + 4, shown = 0;
  for (int f = 0; f < ST_NFIELDS; f++) {
    if (!differs(f)) continue;
    if (row == con_rows - 2 && result[s] - shown > 1) {
      snprintf(line, sizeof line, "+%d more", result[s] - shown);
      put_text(0, row, 7, 0, line);
      break;
    }
    if (row > con_rows - 2) break;
    snprintf(line, sizeof line, "%-5s exp %08lx got %08lx", st_field_name[f],
             (unsigned long)exp_st[f], (unsigned long)act_st[f]);
    put_text(0, row++, 15, 0, line);
    shown++;
  }
}

static void draw_page(int page, int failed_total, uint32_t pvr)
{
  char line[128];
  int first = page * per_page, last = first + per_page;
  if (last > ncases) last = ncases;
  int bad = 0;
  for (int s = first; s < last; s++) bad += result[s] != 0;
  fb_clear(0);
  snprintf(line, sizeof line, "PPC self-test %s PVR %08lx", ST_VARIANT, (unsigned long)pvr);
  put_text(0, 0, 15, 0, line);
  snprintf(line, sizeof line, "all %d/%d pass  page %d/%d pass", ncases - failed_total,
           ncases, last - first - bad, last - first);
  put_text(0, 1, failed_total ? 12 : 10, 0, line);
  for (int s = first; s < last; s++) draw_cell(s, 0);
  snprintf(line, sizeof line, "page %d/%d - press A or Enter", page + 1, pages);
  put_text(0, con_rows - 1, 14, 0, line);
}

static uint32_t wait_press(uint32_t *held)
{
  for (;;) {
    uint32_t now = SOC_INPUT & 0x3f;
    uint32_t pressed = now & ~*held;
    *held = now;
    if (pressed) return pressed;
  }
}

static void interactive(int failed_total, uint32_t pvr)
{
  int page = 0, sel = 0;
  uint32_t held = SOC_INPUT & 0x3f;
  /* Start at the first failure. */
  for (int s = 0; s < ncases; s++)
    if (result[s]) { page = s / per_page; sel = s; break; }
  for (;;) {
    int first = page * per_page, count = ncases - first;
    if (count > per_page) count = per_page;
    if (sel < first || sel >= first + count) sel = first;
    draw_page(page, failed_total, pvr);
    draw_cell(sel, 1);
    draw_details(sel);
    for (;;) {
      uint32_t p = wait_press(&held);
      int k = sel - first, next = k;
      if (p & SOC_IN_A) { page = (page + 1) % pages; break; }
      if (p & SOC_IN_B) { page = (page + pages - 1) % pages; break; }
      if (p & SOC_IN_RIGHT) next = k + 1;
      else if (p & SOC_IN_LEFT) next = k - 1;
      else if (p & SOC_IN_DOWN) next = k + grid_cols;
      else if (p & SOC_IN_UP) next = k - grid_cols;
      if (next < 0 || next >= count || next == k) continue;
      draw_cell(sel, 0);
      sel = first + next;
      draw_cell(sel, 1);
      draw_details(sel);
    }
  }
}

int main(void)
{
  int group_pass[ST_NGROUPS] = {0}, group_all[ST_NGROUPS] = {0}, failed = 0;
  uint32_t pvr;
  __asm__ volatile("mfspr %0,287" : "=r"(pvr));
  st_fp = (SOC_MODE & SOC_MODE_FPU) != 0;
  st_init();
  for (int n = ST_FIRST; n < ST_NCASES; n++)
    if (st_fp || !st_cases[n].fpu) idx[ncases++] = (uint16_t)n;
  for (int s = 0; s < ncases; s++) {
    int n = idx[s];
#ifdef ST_PROGRESS
    printf("case %d\n", n);
#endif
    int bad = run_case(n);
    result[s] = (uint8_t)(bad > 255 ? 255 : bad);
    group_all[st_cases[n].group]++;
    if (bad) failed++;
    else group_pass[st_cases[n].group]++;
  }
  printf("selftest %s PVR %08lx %s: %d cases, %d pass, %d fail\n", ST_VARIANT,
         (unsigned long)pvr, st_fp ? "FPU" : "no FPU", ncases, ncases - failed, failed);
  for (int g = 0; g < ST_NGROUPS; g++)
    printf("  %-7s %d/%d\n", st_group_name[g], group_pass[g], group_all[g]);
  for (int s = 0; s < ncases; s++)
    if (result[s]) report_failure(idx[s]);

  fb_init();
  fb_palette_default();
  con_screen(1);
  con_console(0);
  con_window(0);
  grid_cols = con_cols / CELL_W;
  grid_rows = con_rows - 3 - DETAIL_ROWS;
  per_page = grid_cols * grid_rows;
  pages = (ncases + per_page - 1) / per_page;
  if (SOC_INPUT & SOC_IN_PRESENT) {
    SOC_EXIT = (uint32_t)failed;
    interactive(failed, pvr);
  }
  for (int p = 0; p < pages; p++) draw_page(p, failed, pvr);
  con_screen(0);
  con_console(1);
  printf("selftest %s: %d pages drawn\n", ST_VARIANT, pages);
  return failed;
}
