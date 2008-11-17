/*
 * vmcore memory image accessing functions
 *
 * Copyright (C) NEC Corporation., 2006, 2007
 *
 * Copyright (C) Intel Corp., 2008
 *     Author: Huang Ying <ying.huang@intel.com>
 *
 * Revised from vmcore accessing function from makedumpfile.
 *                                            - Huang Ying 2008/08/28
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <elf.h>

#include "mem_image.h"
#include "util.h"

struct pt_load {
	loff_t			offset;
	unsigned long long	pstart;
	unsigned long long	pend;
	unsigned long long	vstart;
	unsigned long long	vend;
};

struct mem_image
{
	struct pt_load *ptloads;
	int nptload;
	int elf_fd;
};

static void get_elf64_phdr(int fd, int num, Elf64_Phdr *phdr)
{
	off_t off, offret;
	int ret;

	off = sizeof(Elf64_Ehdr) + sizeof(Elf64_Phdr) * num;
	offret = lseek(fd, off, SEEK_SET);
	ERROR_EXIT_ON(offret == (off_t)-1, "Fail to seek");
	ret = read(fd, phdr, sizeof(Elf64_Phdr));
	ERROR_EXIT_ON(ret != sizeof(Elf64_Phdr), "Cannot read Elf64_Phdr");
}

static void get_elf32_phdr(int fd, int num, Elf32_Phdr *phdr)
{
	off_t off, offret;
	int ret;

	off = sizeof(Elf32_Ehdr) + sizeof(Elf32_Phdr) * num;
	offret = lseek(fd, off, SEEK_SET);
	ERROR_EXIT_ON(offret == (off_t)-1, "Fail to seek");
	ret = read(fd, phdr, sizeof(Elf32_Phdr));
	ERROR_EXIT_ON(ret != sizeof(Elf32_Phdr), "Cannot read Elf32_Phdr");
}

struct mem_image *mi_open(const char *image_file_name)
{
	struct mem_image *mi;
	struct pt_load *ptload;
	int i, ret;
	Elf64_Ehdr ehdr64;
	Elf64_Phdr load64;
	Elf32_Ehdr ehdr32;
	Elf32_Phdr load32;
	off_t offret;
	const off_t failed = (off_t)-1;

	mi = calloc(1, sizeof(struct mem_image));
	ERROR_EXIT_ON(!mi, "Cannot allocate mem_image");

	mi->elf_fd = open(image_file_name, O_RDWR);
	ERROR_EXIT_ON(mi->elf_fd == -1, "Cannot open image file: %s",
		      image_file_name);

	ret = read(mi->elf_fd, &ehdr64, sizeof(Elf64_Ehdr));
	ERROR_EXIT_ON(ret!= sizeof(Elf64_Ehdr), "Can't read");

	offret = lseek(mi->elf_fd, 0, SEEK_SET);
	ERROR_EXIT_ON(offret == failed, "Fail to seek");
	ret = read(mi->elf_fd, &ehdr32, sizeof(Elf32_Ehdr));
	ERROR_EXIT_ON(ret!= sizeof(Elf32_Ehdr), "Can't read");

	mi->nptload = 0;
	if ((ehdr64.e_ident[EI_CLASS] == ELFCLASS64)
	    && (ehdr32.e_ident[EI_CLASS] != ELFCLASS32)) {
		for (i = 0; i < ehdr64.e_phnum; i++) {
			get_elf64_phdr(mi->elf_fd, i, &load64);
			if (load64.p_type == PT_LOAD)
				mi->nptload++;
		}

		mi->ptloads = calloc(mi->nptload, sizeof(struct pt_load));
		ERROR_EXIT_ON(!mi->ptloads, "Cannot allocate for mem_image");

		ptload = mi->ptloads;
		for (i = 0; i < ehdr64.e_phnum; i++) {
			get_elf64_phdr(mi->elf_fd, i, &load64);
			if (load64.p_type == PT_LOAD) {
				ptload->pstart = load64.p_paddr;
				ptload->pend = load64.p_paddr+load64.p_filesz;
				ptload->vstart = load64.p_vaddr;
				ptload->vend = load64.p_vaddr+load64.p_filesz;
				ptload->offset = load64.p_offset;
				ptload++;
			}
		}
	} else if ((ehdr64.e_ident[EI_CLASS] != ELFCLASS64)
	    && (ehdr32.e_ident[EI_CLASS] == ELFCLASS32)) {
		for (i = 0; i < ehdr32.e_phnum; i++) {
			get_elf32_phdr(mi->elf_fd, i, &load32);
			if (load32.p_type == PT_LOAD)
				mi->nptload++;
		}

		mi->ptloads = calloc(mi->nptload, sizeof(struct pt_load));
		ERROR_EXIT_ON(!mi->ptloads, "Cannot allocate for mem_image");

		ptload = mi->ptloads;
		for (i = 0; i < ehdr32.e_phnum; i++) {
			get_elf32_phdr(mi->elf_fd, i, &load32);
			if (load32.p_type == PT_LOAD) {
				ptload->pstart = load32.p_paddr;
				ptload->pend = load32.p_paddr+load32.p_filesz;
				ptload->vstart = load32.p_vaddr;
				ptload->vend = load32.p_vaddr+load32.p_filesz;
				ptload->offset = load32.p_offset;
				ptload++;
			}
		}
	} else
		ERROR_EXIT("Can't get valid ehdr.\n");

	return mi;
}

off_t mi_paddr_to_offset(struct mem_image *mi, unsigned long paddr,
				unsigned long size)
{
	int i;
	struct pt_load *p;

	for (i = 0; i < mi->nptload; i++) {
		p = mi->ptloads + i;
		if (p->pstart <= paddr &&
		    p->pend >= paddr + size)
			return p->offset + (paddr - p->pstart);
	}
	error_exit("Can not find paddr 0x%lx.\n", paddr);
	return 0;
}

off_t mi_vaddr_to_offset(struct mem_image *mi, unsigned long vaddr,
				unsigned long size)
{
	int i;
	struct pt_load *p;

	for (i = 0; i < mi->nptload; i++) {
		p = mi->ptloads + i;
		if (vaddr >= p->vstart &&
		    vaddr + size <= p->vend)
			return p->offset + (vaddr - p->vstart);
	}
	error_exit("Can not find vaddr 0x%lx.\n", vaddr);
	return 0;
}

void __mi_vread_mem(struct mem_image *mi, unsigned long vaddr,
		    void *buf, unsigned long size)
{
	off_t off, offret;
	int ret;

	off = mi_vaddr_to_offset(mi, vaddr, size);
	offret = lseek(mi->elf_fd, off, SEEK_SET);
	ERROR_EXIT_ON(offret == (off_t)-1, "Fail to seek");
	ret = read(mi->elf_fd, buf, size);
	ERROR_EXIT_ON(ret != size, "Cannot read mem");
}

void mi_close(struct mem_image *mi)
{
	close(mi->elf_fd);
	free(mi->ptloads);
	free(mi);
}

void *mi_vread_mem(struct mem_image *mi, const void *vaddr, size_t len)
{
	void *buf = malloc(len);

	ERROR_EXIT_ON(!buf, "Can not allocate memory in vread_mem");
	__mi_vread_mem(mi, (unsigned long)vaddr, buf, len);
	return buf;
}

uint32_t mi_vread_u32(struct mem_image *mi, const void *vaddr)
{
	uint32_t u32;
	__mi_vread_mem(mi, (unsigned long)vaddr, &u32, sizeof(u32));
	return u32;
}

uint64_t mi_vread_u64(struct mem_image *mi, const void *vaddr)
{
	uint64_t u64;
	__mi_vread_mem(mi, (unsigned long)vaddr, &u64, sizeof(u64));
	return u64;
}

char *mi_vread_string(struct mem_image *mi, const void *vaddr)
{
	char ch;
	size_t len = 0;

	do {
		__mi_vread_mem(mi, (unsigned long)vaddr + len, &ch, 1);
		len++;
	} while (ch);

	return mi_vread_mem(mi, vaddr, len);
}
