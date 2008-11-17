/*
 * Copyright (C) Intel Corp., 2008
 *     Author: Huang Ying <ying.huang@intel.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>

#include "mem_image.h"
#include "util.h"

struct mem_image *mimg;

void usage(void)
{
	printf("Usage: readcore -a <addr> -l <len> <crash core>\n"
	       "       readcore -a <addr> -s <crash core>\n"
	       "       readcore -h\n"
	       "read some data from crash core.\n"
	       "\n"
	       "-a		virtual address to read\n"
	       "-l		length to read\n"
	       "-s		read a string\n"
	       "-h		Print this help.\n"
	       "<crash core>	Crash core.\n");
	printf("\n");
}

int main(int argc, char *argv[])
{
	int opt, fileind, str = 0;
	unsigned long vaddr = 0, len = 0;
	char *endptr, *data;

	while ((opt = getopt(argc, argv, "a:hl:s")) != -1) {
		switch (opt) {
		case 'a':
			vaddr = strtoul(optarg, &endptr, 0);
			ERROR_EXIT_ON(*endptr, "Invalid address");
			break;
		case 'l':
			len = strtoul(optarg, &endptr, 0);
			ERROR_EXIT_ON(*endptr, "Invalid length");
			break;
		case 's':
			str = 1;
			break;
		case 'h':
			usage();
			return 0;
		default:
			ERROR_EXIT("Unknown option %c", opt);
			break;
		}
	}
	fileind = optind;

	ERROR_EXIT_ON(fileind >= argc, "No crash core file specified!");
	ERROR_EXIT_ON(!vaddr, "No virtual address specified!");
	ERROR_EXIT_ON(!len && !str, "Please specify data length or string!");

	mimg = mi_open(argv[fileind]);
	if (len) {
		data = mi_vread_mem(mimg, (void *)vaddr, len);
		fwrite(data, len, 1, stdout);
	} else {
		data = mi_vread_string(mimg, (void *)vaddr);
		puts(data);
	}
	free(data);
	mi_close(mimg);

	return 0;
}
