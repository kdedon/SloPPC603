/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
#ifndef DOOM_UNISTD_H
#define DOOM_UNISTD_H
#include <stddef.h>
int isatty(int fd);
int usleep(unsigned usec);
int access(const char *path, int mode);
int unlink(const char *path);
#define F_OK 0
#define R_OK 4
#endif
