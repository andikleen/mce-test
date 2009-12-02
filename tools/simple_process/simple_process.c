#include <stdio.h>
#include <stdlib.h>

void main(void)
{
    void *p = malloc(128);
    memset(p, 0, 128);
    printf("alloc 128 mem\n"); 
    while (1)
    {
      sleep(1);
    }
}



