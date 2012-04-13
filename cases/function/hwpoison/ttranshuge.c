/*
 * ttranshuge.c: hwpoison test for THP(Transparent Huge Page).
 *
 * Copyright (C) 2011, FUJITSU LIMITED.
 *   Author: Jin Dongming <jin.dongming@css.cn.fujitsu.com>
 *
 * This program is released under the GPLv2.
 *
 * This program is based on tinject.c and thugetlb.c in tsrc/ directory
 * in mcetest tool.
 */

/*
 * Even if THP is supported by Kernel, it could not be sure all the pages
 * you gotten belong to THP.
 *
 * Following is the structure of the memory mapped by mmap()
 * when the requested memory size is 8M and the THP's size is 2M,
 *     O: means page belongs to 4k page;
 *     T: means page belongs to THP.
 *             Base             .....                   (Base + Size)
 *     Size :  0M . . . . . 2M . . . . . 4M . . . . . 6M . . . . . 8M
 *     case0:  OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
 *             No THP.
 *     case1:  OOOOOOOTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTOOOOOO
 *             Mixed with THP where it is possible.
 *     case2:  OOOOOOOOOOOOOOOOOOOOOOOOOOTTTTTTTTTTTTTTTTTTTTTTTTTT
 *             Mixed with THP only some part of where it is possible.
 *     case3:  TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT
 *             All pages are belong to THP.
 *
 * So the function find_thp_addr() could not be sure the calculated
 * address is the address of THP. And in the above structure,
 * the right address of THP could not be gotten in case 0 and 2 and
 * could be gotten in case 1 and 3 only.
 *
 * According to my experience, the most case gotten by APL is case 1.
 * So this program is made based on the case 1.
 * 
 * To improve the rate of THP mapped by mmap(), it is better to do
 * hwpoison test:
 *     - After reboot immediately.
 *       Because there is a lot of freed memory.
 *     - In the system which has plenty of memory prepared.
 *       This can avoid hwpoison test failure caused by not enough memory.
 */

#define _GNU_SOURCE 1
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include <unistd.h>
#include <getopt.h>
#include <signal.h>

#include <sys/prctl.h>
#include <sys/mman.h>
#include <sys/wait.h>

/*
 * This file supposes the following as default.
 *     Regular Page Size  :  4K(4096Bytes)
 *     THP's Size         :  2M(2UL * 1024 *1024Bytes)
 *     Poisoned Page Size :  4K(4096Bytes)
 */
#define DEFAULT_PS			4096UL
#define PS_MASK(ps_size)		((unsigned long)(ps_size -1))
#define DEFAULT_THP_SIZE		0x200000UL
#define THP_MASK(thp_size)		((unsigned long)(thp_size - 1))

#define REQ_MEM_SIZE			(8UL * 1024 * 1024)

#define MADV_POISON			100
#define MADV_HUGEPAGE			14

#define PR_MCE_KILL			33
#define PR_MCE_KILL_SET			1
#define PR_MCE_KILL_EARLY		1
#define PR_MCE_KILL_LATE		0

#define THP_SUCCESS			0
#define THP_FAILURE			-1

#define print_err(fmt, ...)		printf("[ERROR] "fmt, ##__VA_ARGS__)
#define print_success(fmt, ...)		printf("[SUCCESS] "fmt, ##__VA_ARGS__)
#define print_failure(fmt, ...)		printf("[FAILURE] "fmt, ##__VA_ARGS__)

static char *corrupt_page_addr;
static char *mem_addr;

static unsigned int early_kill = 0;
static unsigned int avoid_touch = 0;

static int corrupt_page = -1;

static unsigned long thp_addr = 0;

static void print_prep_info(void)
{
	printf("\n%s Poison Test of THP.\n\n"
		"Information:\n"
		"    PID %d\n"
		"    PS(page size) 0x%lx\n"
		"    mmap()'ed Memory Address %p; size 0x%lx\n"
		"    THP(Transparent Huge Page) Address 0x%lx; size 0x%lx\n"
		"    %s Page Poison Test At %p\n\n",

		early_kill ? "Early Kill" : "Late Kill",
		getpid(),
		DEFAULT_PS,
		mem_addr, REQ_MEM_SIZE,
		thp_addr, DEFAULT_THP_SIZE,
		(corrupt_page == 0) ? "Head" : "Tail", corrupt_page_addr
	);
}

/*
 * Usage:
 *     If avoid_flag == 1,
 *         access all the memory except one DEFAULT_PS size memory
 *         after the address in global variable corrupt_page_addr;
 *     else
 *         access all the memory from addr to (addr + size).
 */
static int read_mem(char *addr, unsigned long size, int avoid_flag)
{
	int ret = 0;
	unsigned long i = 0;

	for (i = 0; i < size; i++) {
		if ((avoid_flag) &&
		    ((addr + i) >= corrupt_page_addr) &&
		    ((addr + i) < (corrupt_page_addr + DEFAULT_PS)))
			continue;

		if (*(addr + i) != (char)('a' + (i % 26))) {
			print_err("Mismatch at 0x%lx.\n",
					(unsigned long)(addr + i));
			ret = -1;
			break;
		}
	}

	return ret;
}

static void write_mem(char *addr, unsigned long size)
{
	int i = 0;

	for (i = 0; i < size; i++) {
		*(addr + i) = (char)('a' + (i % 26));
	}
}

/*
 * Usage:
 *     Use MADV_HUGEPAGE to make sure the page could be mapped as THP
 *     when /sys/kernel/mm/transparent_hugepage/enabled is set with
 *     madvise.
 *
 * Note:
 *     MADV_HUGEPAGE must be set between mmap and read/write operation.
 *     And it must follow mmap(). Please refer to patches of
 *     MADV_HUGEPAGE about THP for more details.
 *
 * Patch Information:
 *     Title: thp: khugepaged: make khugepaged aware about madvise
 *     commit 60ab3244ec85c44276c585a2a20d3750402e1cf4
 */
static int request_thp_with_madvise(unsigned long start)
{
	unsigned long madvise_addr = start & ~PS_MASK(DEFAULT_PS);
	unsigned long madvise_size = REQ_MEM_SIZE - (start % DEFAULT_PS);

	return madvise((void *)madvise_addr, madvise_size, MADV_HUGEPAGE);
}

/*
 * Usage:
 *     This function is used for getting the address of first THP.
 *
 * Note:
 *     This function could not make sure the address is the address of THP
 *     really. Please refer to the explanation of mmap() of THP
 *     at the head of this file.
 */
static unsigned long find_thp_addr(unsigned long start, unsigned long size)
{
	unsigned long thp_align_addr = (start + (DEFAULT_THP_SIZE - 1)) &
					~THP_MASK(DEFAULT_THP_SIZE);

	if ((thp_align_addr >= start) &&
	    ((thp_align_addr + DEFAULT_THP_SIZE) < (start + size)))
		return thp_align_addr;

	return 0;
}

static int prep_memory_map(void)
{
	mem_addr = (char *)mmap(NULL, REQ_MEM_SIZE, PROT_WRITE | PROT_READ,
				MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (mem_addr == NULL) {
		print_err("Failed to mmap requested memory: size 0x%lx.\n",
				REQ_MEM_SIZE);
		return THP_FAILURE;
	}

	return THP_SUCCESS;
}

static int prep_injection(void)
{
	/* enabled(=madvise) in /sys/kernel/mm/transparent_hugepage/. */
	if (request_thp_with_madvise((unsigned long)mem_addr) < 0) {
		print_err("Failed to request THP for [madvise] in enabled.\n");
		return THP_FAILURE;
	}

	write_mem(mem_addr, REQ_MEM_SIZE);
	if (read_mem(mem_addr, REQ_MEM_SIZE, 0) < 0) {
		print_err("Data is Mismatched(prep_injection).\n");
		return THP_FAILURE;
	}

	/* find the address of THP. */
	thp_addr = find_thp_addr((unsigned long)mem_addr, REQ_MEM_SIZE);
	if (!thp_addr) {
		print_err("No THP mapped.\n");
		return THP_FAILURE;
	}

	/* Calculate the address of the page which will be poisoned */
	if (corrupt_page < 0)
		corrupt_page = 0;

	corrupt_page_addr = (char *)(thp_addr + corrupt_page * DEFAULT_PS);

	/* Process will be killed here by kernel(SIGBUS AO). */
	prctl(PR_MCE_KILL, PR_MCE_KILL_SET,
		early_kill ? PR_MCE_KILL_EARLY : PR_MCE_KILL_LATE,
		NULL, NULL);

	return THP_SUCCESS;
}

static int do_injection(void)
{
	/* Early Kill */
	if (madvise((void *)corrupt_page_addr, DEFAULT_PS, MADV_POISON) != 0) {
		print_err("Failed to poison at 0x%p.\n", corrupt_page_addr);
		printf("[INFO] Please check the authority of current user.\n");
		return THP_FAILURE;
	}

	return THP_SUCCESS;
}

static int post_injection(void)
{

	if (early_kill) {
		print_err("Failed to be killed by SIGBUS(Action Optional).\n");
		return THP_FAILURE;
	}

	/* Late Kill */
	if (read_mem(mem_addr, REQ_MEM_SIZE, avoid_touch) < 0) {
		print_err("Data is Mismatched(do_injection).\n");
		return THP_FAILURE;
	}

	if (!avoid_touch) {
		print_err("Failed to be killed by SIGBUS(Action Required).\n");
		return THP_FAILURE;
	}

	return THP_SUCCESS;
}

static void post_memory_map()
{
	munmap(mem_addr, REQ_MEM_SIZE);
}

static void usage(char *program)
{
	printf("%s [-o offset] [-ea]\n"
" Usage:\n"
"	-o|--offset offset(page unit)	Position of error injection from the first THP.\n"
"	-e|--early-kill			Set PR_MCE_KILL_EARLY(default NOT early-kill).\n"
"	-a|--avoid-touch		Avoid touching error page(page unit) and\n"
"					only used when early-kill is not set.\n"
"	-h|--help\n\n"
" Examples:\n"
"	1. Inject the 2nd page(4k) of THP and early killed.\n"
"	%s -o 1 -e\n\n"
"	2. Inject the 4th page(4k) of THP, late killed and untouched.\n"
"	%s --offset 3 --avoid-touch\n\n"
" Note:\n"
"	Options				Default set\n"
"	early-kill			no\n"
"	offset				0(head page)\n"
"	avoid-touch			no\n\n"
	, program, program, program);
}

static struct option opts[] = {
	{ "offset"		, 1, NULL, 'o' },
	{ "avoid-touch"		, 0, NULL, 'a' },
	{ "early-kill"		, 0, NULL, 'e' },
	{ "help"		, 0, NULL, 'h' },
	{ NULL			, 0, NULL,  0  }
};

static void get_options_or_die(int argc, char *argv[])
{
	char c;

	while ((c = getopt_long(argc, argv, "o:aeh", opts, NULL)) != -1) {
		switch (c) {
		case 'o':
			corrupt_page = strtol(optarg, NULL, 10);
			break;
		case 'a':
			avoid_touch = 1;
			break;
		case 'e':
			early_kill = 1;
			break;
		case 'h':
			usage(argv[0]);
			exit(0);
		default:
			print_err("Wrong options, please check options!\n");
			usage(argv[0]);
			exit(1);
		}
	}

	if ((avoid_touch) && (corrupt_page == -1)) {
		print_err("Avoid which page?\n");
		usage(argv[0]);
		exit(1);
	}
}

int main(int argc, char *argv[])
{
	int ret = THP_FAILURE;
	pid_t child;
	siginfo_t sig;

	/*
	 * 1. Options check.
	 */
	get_options_or_die(argc, argv);

	/* Fork a child process for test */
	child = fork();
	if (child < 0) {
		print_err("Failed to fork child process.\n");
		return THP_FAILURE;
	}

	if (child == 0) {
		/* Child process */

		int ret = THP_FAILURE;

		signal(SIGBUS, SIG_DFL);

		/*
		 * 2. Groundwork for hwpoison injection.
		 */
		if (prep_memory_map() == THP_FAILURE)
			_exit(1);

		if (prep_injection() == THP_FAILURE)
			goto free_mem;

		/* Print the prepared information before hwpoison injection. */
		print_prep_info();

		/*
		 * 3. Hwpoison Injection.
		 */
		if (do_injection() == THP_FAILURE)
			goto free_mem;

		if (post_injection() == THP_FAILURE)
			goto free_mem;

		ret = THP_SUCCESS;
free_mem:
		post_memory_map();

		if (ret == THP_SUCCESS)
			_exit(0);

		_exit(1);
	}

	/* Parent process */

	if (waitid(P_PID, child, &sig, WEXITED) < 0) {
		print_err("Failed to wait child process.\n");
		return THP_FAILURE;
	}

	/*
	 * 4. Check the result of hwpoison injection.
	 */
	if (avoid_touch) {
		if (sig.si_code == CLD_EXITED && sig.si_status == 0) {
			print_success("Child process survived.\n");
			ret = THP_SUCCESS;
		} else
			print_failure("Child process could not survive.\n");
	} else {
		if (sig.si_code == CLD_KILLED && sig.si_status == SIGBUS) {
			print_success("Child process was killed by SIGBUS.\n");
			ret = THP_SUCCESS;
		} else
			print_failure("Child process could not be killed"
					" by SIGBUS.\n");
	}

	return ret;
}
