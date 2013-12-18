#define _GNU_SOURCE 1
#include <stdlib.h>
#include <sys/mman.h>
#include <fcntl.h>
#include "hugepage.h"

#define HPAGE_SIZE (2UL*1024*1024)

#define MADV_SOFT_OFFLINE	101

int main(int argc, char *argv[])
{
	int PS = getpagesize();
	int nr_hugepages;
	void *addr;
	int ret;

	nr_hugepages = strtol(argv[1], NULL, 10);
	addr = alloc_anonymous_hugepage(nr_hugepages * HPAGE_SIZE, 0);
	write_hugepage(addr, nr_hugepages, NULL);
	ret = madvise(addr, PS, MADV_SOFT_OFFLINE);
	free_anonymous_hugepage(addr, nr_hugepages * HPAGE_SIZE);
	return ret;
}
