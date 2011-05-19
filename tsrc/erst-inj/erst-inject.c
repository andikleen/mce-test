/*
 * Error Record Serialization Table(ERST) is used to save and retrieve hardware
 * error information to and from a persistent store, such as flash or NVRAM.
 *
 * This test case is used to test ERST operation including read/write/clean.
 * To be sure of loading erst-dbg module before executing this test.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; version 2.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should find a copy of v2 of the GNU General Public License somewhere
 * on your Linux system; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 *
 * Copyright (C) 2011, Intel Corp.
 * Author: Chen Gong <gong.chen@intel.com>
 *
 * Original written by Huang Ying <ying.huang@intel.com>
 * Updated by Chen Gong <gong.chen@intel.com>
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/ioctl.h>

#include "cper.h"

#define ERST_DEV "/dev/erst_dbg"

#define APEI_ERST_CLEAR_RECORD         _IOW('E', 1, u64)
#define APEI_ERST_GET_RECORD_COUNT     _IOR('E', 2, u32)

#define CPER_CREATOR_LINUX						\
	LGUID(0x94DB0E05, 0xEE60, 0x42D8, 0x91, 0xA5, 0xC6, 0xC0,	\
			0x02, 0x41, 0x6C, 0x6A)

#define ERROR_EXIT_ON(check, fmt, x...)					\
	do {								\
		if (check)						\
			error_exit(fmt, ## x);				\
	} while (0)

void error_exit(char *fmt, ...)
{
	va_list ap;

	fprintf(stderr, "Error: ");
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);

	if (errno)
		fprintf(stderr, ", errno: %d (%s)\n", errno, strerror(errno));
	else
		fprintf(stderr, "\n");
	exit(-1);
}

void inject(int fd, u64 record_id)
{
	int rc;
	unsigned int len;
	struct cper_record_header *rcd_hdr;
	struct cper_section_descriptor *sec_hdr;
	struct cper_sec_mem_err *mem_err;

	len = sizeof(*rcd_hdr) + sizeof(*sec_hdr) + sizeof(*mem_err);
	printf("sizes: %lu, %lu, %lu\n", sizeof(*rcd_hdr), sizeof(*sec_hdr),
			sizeof(*mem_err));
	rcd_hdr = malloc(len);
	ERROR_EXIT_ON(!rcd_hdr, "Can not alloc mem");

#define LE 0

	sec_hdr = (void *)(rcd_hdr + 1);
	mem_err = (void *)(sec_hdr + 1);

	memset(rcd_hdr, 0, sizeof(*rcd_hdr));
#if 0
	memcpy(rcd_hdr->signature, "REPC", 4);
#else
	memcpy(rcd_hdr->signature, "CPER", 4);
#endif
	rcd_hdr->revision = 0x0100;
	rcd_hdr->signature_end = 0xffffffff;
	rcd_hdr->error_severity = CPER_SER_FATAL;
	rcd_hdr->validation_bits = 0;
	rcd_hdr->creator_id = CPER_CREATOR_LINUX;
	rcd_hdr->notification_type = CPER_NOTIFY_NMI;
	rcd_hdr->section_count = 1;
	rcd_hdr->record_length = len;
	rcd_hdr->record_id = record_id;
#if LE
	memcpy(&rcd_hdr->persistence_information, "RE", 2);
#else
	memcpy(&rcd_hdr->persistence_information, "ER", 2);
#endif

	memset(sec_hdr, 0, sizeof(*sec_hdr));
	sec_hdr->section_offset = (void *)mem_err - (void *)rcd_hdr;
	sec_hdr->section_length = sizeof(*mem_err);
	sec_hdr->revision = 0x0100;
	sec_hdr->validation_bits = 0;
	sec_hdr->flags = 0;
	sec_hdr->section_type = CPER_SEC_PLATFORM_MEM;
	sec_hdr->section_severity = CPER_SER_FATAL;

	memset(mem_err, 0, sizeof(*mem_err));
	mem_err->validation_bits = 0x6;
	mem_err->physical_addr = 0x2000;
	mem_err->physical_addr_mask = ~0xfffULL;

	rc = write(fd, rcd_hdr, len);
	ERROR_EXIT_ON(rc != len, "Error inject: %d", rc);

	free(rcd_hdr);
}

#define POLL_BUF_SIZ           (1024 * 1024)

int poll(int fd)
{
	int rc;
	struct cper_record_header *rcd_hdr;
	struct cper_section_descriptor *sec_hdr;
	struct cper_sec_mem_err *mem_err;

	rcd_hdr = malloc(POLL_BUF_SIZ);
	ERROR_EXIT_ON(!rcd_hdr, "Can not alloc mem");

	rc = read(fd, rcd_hdr, POLL_BUF_SIZ);
	ERROR_EXIT_ON(rc < 0, "Error poll: %d", rc);

	sec_hdr = (void *)(rcd_hdr + 1);
	mem_err = (void *)(sec_hdr + 1);

	printf("rc: %d\n", rc);

	printf("rcd sig: %4s\n", rcd_hdr->signature);
	printf("rcd id: 0x%llx\n", rcd_hdr->record_id);

	free(rcd_hdr);

	return rc;
}

void clear(int fd, u64 record_id)
{
	int rc;

	printf("clear an error record: id = 0x%llx\n", record_id);

	rc = ioctl(fd, APEI_ERST_CLEAR_RECORD, &record_id);
	ERROR_EXIT_ON(rc, "Error clear: %d", rc);
}

void get_record_count(int fd, u32 *record_count)
{
	int rc;
	rc = ioctl(fd, APEI_ERST_GET_RECORD_COUNT, record_count);
	ERROR_EXIT_ON(rc, "Error get record count: %d", rc);

	printf("total error record count: %u\n", *record_count);
}

enum {
	ERST_INJECT,
	ERST_POLL,
	ERST_CLEAR,
	ERST_COUNT,
	ERST_MAX = 255
};

void usage()
{
	printf("Usage: ./erst-inject [option] <id>\n");
	printf("PAY ATTENTION, <id> is hexadecimal.\n");
	printf("\tp\treturn all error records in the ERST\n");
	printf("\ti\twrite an error record to be persisted into one item with <id>\n");
	printf("\tc\tclean specific error record with <id>\n");
	printf("\tn\treturn error records count in the ERST\n");
	printf("\nExample:\t ./erst-inject -p\n");
	printf("\t\t ./erst-inject -i 0x1234567\n");
	printf("\t\t ./erst-inject -c 5050\n");
	printf("\t\t ./erst-inject -n\n");
}

int main(int argc, char *argv[])
{
	int fd;
	int todo = ERST_MAX;
	int opt;
	u64 record_id = 0x12345678;
	u32 record_count;

	if (argc == 1) {
		usage();
		exit(0);
	}

	while ((opt = getopt(argc, argv, "pi:c:n")) != -1) {
		switch (opt) {
		case 'p':
			todo = ERST_POLL;
			break;
		case 'i':
			todo = ERST_INJECT;
			record_id = strtoull(optarg, NULL, 16);
			break;
		case 'c':
			todo = ERST_CLEAR;
			record_id = strtoull(optarg, NULL, 16);
			break;
		case 'n':
			todo = ERST_COUNT;
			break;
		}
	}

	fd = open(ERST_DEV, O_RDWR);
	ERROR_EXIT_ON(fd < 0, "Can not open dev file");

	switch (todo) {
	case ERST_INJECT:
		inject(fd, record_id);
		break;
	case ERST_POLL:
		while (poll(fd));
		break;
	case ERST_CLEAR:
		clear(fd, record_id);
		break;
	case ERST_COUNT:
		get_record_count(fd, &record_count);
		break;
	case ERST_MAX:
		usage();
		break;
	}

	close(fd);

	return 0;
}
