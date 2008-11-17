/*
 * Some utility functions
 *
 * Copyright (C) Intel Corp., 2008
 *     Author: Huang Ying <ying.huang@intel.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#include <stdarg.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#include "util.h"

void error_exit(char *fmt, ...)
{
	va_list ap;

	fprintf(stderr, "Error: ");
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	if (errno)
		fprintf(stderr, ", %s\n", strerror(errno));
	else
		fprintf(stderr, "\n");
	exit(-1);
}

