#ifndef MEM_IMAGE_H
#define MEM_IMAGE_H

#include <stdint.h>

struct mem_image;

struct mem_image *mi_open(const char *image_file_name);
void mi_close(struct mem_image *mi);
void *mi_vread_mem(struct mem_image *mi, const void *vaddr, size_t len);
uint32_t mi_vread_u32(struct mem_image *mi, const void *vaddr);
uint64_t mi_vread_u64(struct mem_image *mi, const void *vaddr);
char *mi_vread_string(struct mem_image *mi, const void *vaddr);

#endif
