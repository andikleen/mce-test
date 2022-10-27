/*
 * Set up to get zapped by a machine check (injected elsewhere)
 * To use this test case please ensure your SUT(System Under Test)
 * can support MCE/SRAR.
 *
 * This file is released under the GPLv2.
 *
 * Copyright (C) 2012-2015 Intel corporation
 *
 * Author:
 *    Tony Luck <tony.luck@intel.com>
 *    Gong Chen <gong.chen@intel.com>
 *    Wen Jin <wenx.jin@intel.com>
 */


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <getopt.h>
#include <errno.h>

/*
 * Definition of /proc/pid/pagemap
 * Bits 0-54  page frame number (PFN) if present
 * Bits 0-4   swap type if swapped
 * Bits 5-54  swap offset if swapped
 * Bits 55-60 page shift, the bits definition is legacy.
 * Bit  61    reserved for future use
 * Bit  62    page swapped
 * Bit  63    page present
 */

struct pagemaps {
	unsigned long long	pfn:55;
	unsigned long long	pgshift:6; /*legacy*/
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
unsigned long long vtop(unsigned long long addr, pid_t pid)
{
	struct pagemaps pinfo;
	unsigned int pinfo_size = sizeof(pinfo);
	unsigned long long offset = addr / pagesize * pinfo_size;
	int fd, pgmask;
	char pagemapname[64];

	sprintf(pagemapname, "/proc/%d/pagemap", pid);
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
	pgmask = pagesize - 1;
	return (pinfo.pfn * pagesize) | (addr & pgmask);
}

static void usage(void)
{
	printf(
"victim [options]\n"
"	-a|--address vaddr=val, pid=val	Translate process virtual address into physical address\n"
"	-d|--data			Inject data error(DCU error) under user context\n"
"	-i|--instruction		Inject instruction error(IFU error) under user context\n"
"	-k|--kick 0/1			Kick off trigger. Auto(0), Manual(1, by default)\n"
"	-p|--pfa			help to test memory PFA(Predictive Failure Analysis) function\n"
"	-h|--help			Show this usage message\n"
	);
}

static const struct option opts[] = {
	{ "address"	, 1, NULL, 'a' },
	{ "data"	, 0, NULL, 'd' },
	{ "instruction"	, 0, NULL, 'i' },
	{ "help"	, 0, NULL, 'h' },
	{ "kick"	, 1, NULL, 'k' },
	{ "pfa"		, 0, NULL, 'p' },
	{ NULL		, 0, NULL, 0 }
};

static void pfa_helper(char *p, pid_t pid, unsigned long long old_phys)
{
	int i;
	int total;
	unsigned long long new_phys;

	for (;;) {
		for (i = 0; i < pagesize; i += sizeof(int)) {
			total += *(int*)(p + i);
			*(int*)(p + i) = total;
		}

		new_phys = vtop((unsigned long long)p, pid);
		if (old_phys == new_phys) {
			for (i = 0; i < pagesize; i += sizeof(int)) {
				total += *(int*)(p + i);
				*(int*)(p + i) = i;
			}
			sleep(2);
			new_phys = vtop((unsigned long long)p, pid);
			if (old_phys != new_phys) {
				printf("Page was replaced. New physical address = 0x%llx\n", new_phys);
				fflush(stdout);
				old_phys = new_phys;
			}
		} else {
			printf("Page was replaced. New physical address = 0x%llx\n", new_phys);
			fflush(stdout);
			old_phys = new_phys;
		}
	}
}

static int parse_addr_subopts(char *subopts, unsigned long long *virt,
			      pid_t *pid)
{
	int err = 0;
	int index;
	enum {
		I_VADDR = 0,
		I_PID
	};
	char *const token[] = {
		[I_VADDR] = "vaddr",
		[I_PID] = "pid",
		NULL
	};
	char *p = subopts;
	char *subval;
	char *svaddr;
	char *spid;

	while (*p != '\0' && !err) {
		index = getsubopt(&p, token, &subval);
		switch (index) {
		case I_VADDR:
			if (subval != NULL) {
				svaddr = subval;
				break;
			} else {
				fprintf(stderr,
					"miss value for %s\n",
					token[I_VADDR]);
				err++;
				continue;
			}
		case I_PID:
			if (subval != NULL) {
				spid = subval;
				break;
			} else {
				fprintf(stderr,
					"miss value for %s\n",
					token[I_PID]);
				err++;
				continue;
			}
		default:
			err++;
			break;
		}
	}
	if (err > 0) {
		usage();
		return 1;
	}
	errno = 0;
	*virt = strtoull(svaddr, NULL, 0);
	if ((*virt == 0 && svaddr[0] != '0') || errno != 0) {
		fprintf(stderr, "Invalid virtual address: %s\n",
			svaddr);
		return 1;
	}
	errno = 0;
	*pid = strtoul(spid, NULL, 0);
	if ((*pid == 0 && spid[0] != '0') || errno != 0) {
		fprintf(stderr, "Invalid process pid number: %s\n",
			spid);
		return 1;
	}
	return 0;
}

/*
 * The "SRAR DCU" test case failed on a CLX-AP server. It's root caused
 * that the gcc v8.2.1 optimized out the access to the injected location.
 *
 * If keep "total" as a local, even mark it "volatile", the gcc v8.2.1
 * still optimizes out the memory access. Therefore, move the "total" from
 * being a local variable to a global to avoid such optimization.
 */
long total;

int main(int argc, char **argv)
{
	unsigned long long virt, phys;
	char *buf;
	int c, i;
	int iflag = 0, dflag = 0;
	int kick = 1;
	int pfa = 0;
	pid_t pid;
	const char *trigger = "./trigger_start";
	const char *trigger_flag = "trigger";
	int fd;
	int count = 100;
	char trigger_buf[16];
	char answer[16];
	time_t	now;

	if (argc <= 1) {
		usage();
		return 0;
	}

	pagesize = getpagesize();

	while ((c = getopt_long(argc, argv, "a:dihk:p", opts, NULL)) != -1) {
		switch (c) {
		case 'a':
			if (parse_addr_subopts(optarg, &virt, &pid) == 0) {
				phys = vtop(virt, pid);
				printf("physical address of (%d,0x%llx) = 0x%llx\n",
					pid, virt, phys);
				return 0;
			}
			return 1;
		case 'd':
			dflag = 1;
			break;
		case 'i':
			iflag = 1;
			break;
		case 'k':
			errno = 0;
			kick = strtol(optarg, NULL, 0);
			if ((kick == 0 && optarg[0] != '0') || errno != 0) {
				fprintf(stderr, "Invalid parameter: %s\n", optarg);
				return 1;
			}
			if (kick != 0 && kick != 1) {
				fprintf(stderr, "Invalid parameter: %s\n", optarg);
				return 1;
			}
			break;
		case 'p':
			pfa = 1;
			break;
		case 'h':
		default:
			usage();
			return 0;
		}
	}

	/* The MAP_LOCKED flag should not be used here, because it will cause a failure
	 * in KVM mce-inject test. But to prevent the mapped buffer from being swapped out,
	 * the system under test should not run in a heavy load environment.
	 */
	buf = mmap(NULL, pagesize, PROT_READ|PROT_WRITE|PROT_EXEC,
		MAP_ANONYMOUS|MAP_PRIVATE, -1, 0);

	if (buf == MAP_FAILED) {
		fprintf(stderr, "Can't get a single page of memory!\n");
		return 1;
	}
	memset(buf, '*', pagesize);
	pid = getpid();
	phys = vtop((unsigned long long)buf, pid);
	if (phys == 0) {
		fprintf(stderr, "Can't get physical address of the page!\n");
		return 1;
	}

	if (iflag)
		memcpy(buf, (void *)dummyfunc, pagesize);

	printf("physical address of (0x%llx) = 0x%llx\n",
		(unsigned long long)buf, phys);
	fflush(stdout);

	if (pfa == 1)
		pfa_helper(buf, pid, phys);

	if (kick == 0) {
		errno = 0;
		if (unlink(trigger) < 0 && errno != ENOENT) {
			fprintf(stderr, "fail to remove trigger file\n");
			return 1;
		}
		memset(trigger_buf, 0, sizeof(trigger_buf));
		while (--count) {
			if ((fd = open(trigger, O_RDONLY)) < 0) {
				sleep(1);
				continue;
			}
			if (read(fd, trigger_buf, sizeof(trigger_buf)) > 0 &&
				strstr(trigger_buf, trigger_flag) != NULL) {
				break;
			}
			sleep(1);
		}
		if (count == 0) {
			fprintf(stderr,
				"Timeout to get trigger flag file\n");
			return 1;
		}
	} else {
		printf("Hit any key to trigger error: ");
		fflush(stdout);
		read(0, answer, 16);
		now = time(NULL);
		printf("Access time at %s\n", ctime(&now));
	}

	if (iflag) {
		void (*f)(void) = (void (*)(void))buf;

		while (1) f();
	}

	if (dflag) {
		while (1) {
			for (i = 0; i < pagesize; i += sizeof(int))
				total += *(int *)(buf + i);
		}
	}

	return 0;
}
