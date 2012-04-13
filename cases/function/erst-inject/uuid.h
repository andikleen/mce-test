#ifndef _LINUX_GUID_H_
#define _LINUX_GUID_H_

#include <string.h>
#include <stdio.h>

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;

typedef unsigned char __u8;
typedef unsigned short __u16;
typedef unsigned int __u32;
typedef unsigned long long __u64;

typedef struct {
       u8 b[16];
} lguid_t;

#define LGUID(a, b, c, d0, d1, d2, d3, d4, d5, d6, d7)                 \
((lguid_t)                                                             \
{{ (a) & 0xff, ((a) >> 8) & 0xff, ((a) >> 16) & 0xff, ((a) >> 24) & 0xff, \
   (b) & 0xff, ((b) >> 8) & 0xff,                                      \
   (c) & 0xff, ((c) >> 8) & 0xff,                                      \
   (d0), (d1), (d2), (d3), (d4), (d5), (d6), (d7) }})

#endif
