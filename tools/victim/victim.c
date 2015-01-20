/*
 * Victim
 *
 * Victim workes under user context, which provides target memory chunk for
 * error injection. It can be used for all kinds of error types, including
 * Corrected error and Uncorrected error(IFU/DCU).
 *
 * Here is an simple example for DCU:
 * Mmap one page memory and returns starting address, and then translate
 * virtual address to physical address. Caller like shell script can
 * inject UC error (error type 0x10 in EINJ table) on returned physical
 * address. Meanwhile, victim continues to read/write on returned memory
 * space to trigger DCU happening ASAP.
 *
 * Copyright (C) 2015, Intel Corp.
 *
 * Author:
 *    Zhilong Liu <zhilongx.liu@intel.com>
 *
 * Date:
 *    01/15 2015
 *
 * History:  Revision history
 *           None
 */

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <getopt.h>
#include <string.h>
#include <time.h>

/*
 * Use below macros to make this a non-trivial sized function.
 */
#define PLUS10 (ifunc_ret++, ifunc_ret++, ifunc_ret++, ifunc_ret++, \
		ifunc_ret++, ifunc_ret++, ifunc_ret++, ifunc_ret++, \
		ifunc_ret++, ifunc_ret++)
#define PLUS100 (PLUS10, PLUS10, PLUS10, PLUS10, PLUS10, PLUS10, \
		PLUS10, PLUS10, PLUS10, PLUS10)
#define PLUS1000 (PLUS100, PLUS100, PLUS100, PLUS100, PLUS100, \
		PLUS100, PLUS100, PLUS100, PLUS100, PLUS100)

static int pagesize;

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

/* Don't let compiler optimize away access to this */
volatile int ifunc_ret;

int ifunc(void)
{
	ifunc_ret = 0;

	PLUS1000;

	return ifunc_ret;
}

/*
 * get information about address from /proc/{pid}/pagemap
 */
unsigned long long vtop(unsigned long long addr)
{
	struct pagemaps pinfo;
	unsigned int pinfo_size = sizeof(pinfo);
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
	if (pread(fd, (void *)&pinfo, pinfo_size, offset) != pinfo_size) {
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

static void usage(void)
{
	printf(
"victim [options]\n"
"       -d|--data		Inject data error(DCU error) under user context\n"
"       -i|--instruction	Inject instruction error(IFU error) under user context\n"
"	-p|--pfa		Inject memory CE consecutivelly under user context to trigger pfa\n"
"       -h|--help		Show this usage message\n"
	);
}

static const struct option opts[] = {
	{ "data",        0, NULL, 'd' },
	{ "instruction", 0, NULL, 'i' },
	{ "pfa",         0, NULL, 'p' },
	{ "help",        0, NULL, 'h' },
	{ NULL,          0, NULL,  0 }
};

void trigger_ifu(void)
{
	time_t now;
	char answer[16];
	unsigned long long phys;
	void (*f)(void) = (void (*)(void))ifunc;

	phys = vtop((unsigned long long)f);
	printf("physical address of (%p) = 0x%llx\n"
		"Hit any key to trigger error: ", f, phys);
	fflush(stdout);
	read(0, answer, 16);
	now = time(NULL);
	printf("Access time at %s\n", ctime(&now));
	while (1)
		f();
}

void trigger_dcu(unsigned long long virt, unsigned long long phys)
{
	int i;
	long total;
	time_t now;
	char answer[16];

	printf("physical address of (0x%llx) = 0x%llx\n"
		"Hit any key to trigger error: ", virt, phys);
	fflush(stdout);
	read(0, answer, 16);
	now = time(NULL);
	printf("Access time at %s\n", ctime(&now));
	while (1) {
		for (i = 0; i < pagesize; i += sizeof(int))
			total += *(int *)(virt + i);
	}
}

/*
 * test PFA when inject CE(0x8) consecutivelly
 */
void trigger_pfa(unsigned long long virt, unsigned long long phys)
{
	int i;
	long total;
	unsigned long long newphys;

	printf("physical address of (0x%llx) = 0x%llx\n", virt, phys);
	fflush(stdout);
	while (1) {
		for (i = 0; i < pagesize; i += sizeof(int)) {
			total += *(int *)(virt + i);
			*(int *)(virt + i) = total;
		}

		newphys = vtop(virt);
		if (phys == newphys) {
			for (i = 0; i < pagesize; i += sizeof(int)) {
				total += *(int *)(virt + i);
				*(int *)(virt + i) = i;
			}
			sleep(2);
			newphys = vtop(virt);
			if (phys != newphys) {
				printf("Page was replaced. New phys addr = 0x%llx\n",
						newphys);
				fflush(stdout);
				phys = newphys;
			}
		} else {
			printf("Page was replaced. New phys addr = 0x%llx\n",
					newphys);
			fflush(stdout);
			phys = newphys;
		}
	}
}

int main(int argc, char **argv)
{
	int c;
	char *p;
	unsigned long long phys;

	if (argc <= 1) {
		usage();
		return 0;
	}

	pagesize = getpagesize();
	/* only RD/WR permission needed */
	p = mmap(NULL, pagesize, PROT_READ|PROT_WRITE,
			MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	if (p == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	/* make sure that kernel does allocate page */
	memset(p, '*', pagesize);
	phys = vtop((unsigned long long)p);

	while ((c = getopt_long(argc, argv, "diph", opts, NULL)) != -1) {
		switch (c) {
		case 'd':
			trigger_dcu((unsigned long long)p, phys);
			break;
		case 'i':
			trigger_ifu();
			break;
		case 'p':
			trigger_pfa((unsigned long long)p, phys);
			break;
		case 'h':
		default:
			usage();
			return 0;
		}
	}

	return 0;
}
