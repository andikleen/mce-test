#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void)
{
	void *p = malloc(0x100000);

	printf("allocating 1M bytes of memory\n");
	while (1) {
		memset(p, 0, 0x100000);
	}
	return 0;
}
