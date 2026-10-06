/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
#ifndef DOOM_CTYPE_H
#define DOOM_CTYPE_H
int isdigit(int c);
int isalpha(int c);
int isalnum(int c);
int isspace(int c);
int isupper(int c);
int islower(int c);
int isprint(int c);
int ispunct(int c);
int isxdigit(int c);
int iscntrl(int c);
int toupper(int c);
int tolower(int c);
#endif
