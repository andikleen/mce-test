/*
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
 */

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
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
 * get information about address from /proc/{pid}/pagemap
 */
unsigned long long vtop(unsigned long long addr)
{
	struct pagemaps pinfo;
	unsigned int pinfo_size = sizeof pinfo;
	long offset;
	int fd, pgmask;
	char pagemapname[64];

	if (!pagesize)
		pagesize = getpagesize();
	offset = addr / pagesize * pinfo_size;
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
	if (!pinfo.present)
		return ~0ull;
	pgmask = (1 << pinfo.pgshift) - 1;
	return (pinfo.pfn << pinfo.pgshift) | (addr & pgmask);
}

int main()
{
	char *p;
	long total, i;
	unsigned long long phys, newphys;

	p = mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	if (p == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	*p = '*'; /* make kernel allocate page */
	phys = vtop((unsigned long long)p);

	printf("allocated page: virtual = %p physical = 0x%llx\n", p, phys);
	fflush(stdout);

	for (;;) {
		for (i = 0; i < pagesize; i += sizeof(int)) {
			total += *(int*)(p + i);
			*(int*)(p + i) = total;
		}

		newphys = vtop((unsigned long long)p);
		if (phys == newphys) {
			for (i = 0; i < pagesize; i += sizeof(int)) {
				total += *(int*)(p + i);
				*(int*)(p + i) = i;
			}
			sleep(2);
			newphys = vtop((unsigned long long)p);
			if (phys != newphys) {
				printf("Page was replaced. New physical address = 0x%llx\n", newphys);
				fflush(stdout);
				phys = newphys;
			}
		} else {
			printf("Page was replaced. New physical address = 0x%llx\n", newphys);
			fflush(stdout);
			phys = newphys;
		}
	}
}
