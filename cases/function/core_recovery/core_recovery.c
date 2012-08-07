/*
 * Set up to get zapped by a machine check (injected elsewhere)
 * To use this test case please ensure your SUT(System Under Test)
 * can support MCE/SRAR.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation; version 2.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should find a copy of v2 of the GNU General Public License somewhere on
 * your Linux system; if not, write to the Free Software Foundation, Inc., 59
 * Temple Place, Suite 330, Boston, MA 02111-1307 USA.
 *
 * Copyright (C) 2012 Intel corporation
 *
 * Author:
 *    Tony Luck <tony.luck@intel.com>
 *    Gong Chen <gong.chen@intel.com>
 */

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <fcntl.h>
#include <getopt.h>
#include <sys/mman.h>

/*
 * Definition of /proc/pid/pagemap
 * Bits 0-54  page frame number (PFN) if present
 * Bits 0-4   swap type if swapped
 * Bits 5-54  swap offset if swapped
 * Bits 55-60 page shift (page size = 1<<page shift)
 * Bit  61    reserved for future use
 * Bit  62    page swapped
 * Bit  63    page present
 */

struct pagemaps {
	unsigned long long	pfn:55;
	unsigned long long	pgshift:6;
	unsigned long long	rsvd:1;
	unsigned long long	swapped:1;
	unsigned long long	present:1;
};

static int pagesize;

/*
 * dummyfunc size should be less than one page after complied,
 * otherwise, caller will not return from this function
 */
void dummyfunc(void)
{
	int fatarray[64];

	fatarray[0] = 0xdeadbeaf;
	fatarray[8] = 0xdeadbeaf;
	fatarray[16] = 0xdeadbeaf;
	fatarray[32] = 0xdeadbeaf;
}

/*
 * get information about address from /proc/{pid}/pagemap
 */
unsigned long long vtop(unsigned long long addr)
{
	struct pagemaps pinfo;
	unsigned int pinfo_size = sizeof pinfo;
	long offset = addr / pagesize * pinfo_size;
	int fd, pgmask;
	char pagemapname[64];

	sprintf(pagemapname, "/proc/%d/pagemap", getpid());
	fd = open(pagemapname, O_RDONLY);
	if (fd == -1) {
		perror(pagemapname);
		return 0;
	}
	if (pread(fd, (void*)&pinfo, pinfo_size, offset) != pinfo_size) {
		perror(pagemapname);
		close(fd);
		return 0;
	}
	close(fd);
	pgmask = (1 << pinfo.pgshift) - 1;
	return (pinfo.pfn << pinfo.pgshift) | (addr & pgmask);
}

static void usage(void)
{
	printf(
"core_recovery [options]\n"
"	-d|--data		Inject data error(DCU error) under user context\n"
"	-i|--instruction	Inject instruction error(IFU error) under user context\n"
"	-h|--help		Show this usage message\n"
	);
}

static const struct option opts[] = {
        { "data"	, 0, NULL, 'd' },
        { "instruction"	, 0, NULL, 'i' },
	{ "help"	, 0, NULL, 'h' },
        { NULL		, 0, NULL, 0 }
};

int main(int argc, char **argv)
{
	unsigned long long phys;
	long total;
	char *buf, answer[16];
	int c, i;
	int iflag = 0, dflag = 0;
	time_t	now;

	if (argc <= 1) {
		usage();
		return 0;
	}

	pagesize = getpagesize();

        while ((c = getopt_long(argc, argv, "dih", opts, NULL)) != -1) {
		switch (c) {
		case 'd':
			dflag = 1;
			break;
		case 'i':
			iflag = 1;
			break;
		case 'h':
		default:
			usage();
			return 0;
		}
	}

	buf = mmap(NULL, pagesize, PROT_READ|PROT_WRITE|PROT_EXEC,
		MAP_ANONYMOUS|MAP_PRIVATE|MAP_LOCKED, -1, 0);

	if (buf == MAP_FAILED) {
		fprintf(stderr, "Can't get a single page of memory!\n");
		return 1;
	}
	memset(buf, '*', pagesize);
	phys = vtop((unsigned long long)buf);
	if (phys == 0) {
		fprintf(stderr, "Can't get physical address of the page!\n");
		return 1;
	}

	if (iflag)
		memcpy(buf, (void*)dummyfunc, pagesize);

	printf("physical address of (0x%llx) = 0x%llx\n"
		"Hit any key to trigger error: ", (unsigned long long)buf, phys);
	fflush(stdout);
	read(0, answer, 16);
	now = time(NULL);
	printf("Access time at %s\n", ctime(&now));

	if (iflag) {
		void (*f)(void) = (void (*)(void))buf;

		while (1) f() ;
	}

	if (dflag) {
		while (1) {
			for (i = 0; i < pagesize; i += sizeof(int))
				total += *(int*)(buf + i);
		}
	}

	return 0;
}
