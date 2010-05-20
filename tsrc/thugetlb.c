/*
 * Test program for memory error handling for hugepages
 * Author: Naoya Horiguchi <n-horiguchi@ah.jp.nec.com>
 */
#include <stdlib.h>
#include <stdio.h>
#include <string.h> 
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/mman.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/sem.h>
#include <sys/types.h>
#include <sys/prctl.h>

#define FILE_BASE  "test"

#define HPAGE_SIZE (2UL*1024*1024)
#define BUF_SIZE   256
#define PROTECTION (PROT_READ | PROT_WRITE)

#ifndef SHM_HUGETLB
#define SHM_HUGETLB 04000
#endif

/* Control early_kill/late_kill */
#define PR_MCE_KILL 33
#define PR_MCE_KILL_CLEAR   0
#define PR_MCE_KILL_SET     1
#define PR_MCE_KILL_LATE    0
#define PR_MCE_KILL_EARLY   1
#define PR_MCE_KILL_DEFAULT 2
#define PR_MCE_KILL_GET 34

int PS; /* Page size */
int file_size; /* Memory allocation size (hugepage unit) */
/* Error injection position (page offset from the first hugepage head) */
int corrupt_page;
char filename[BUF_SIZE] = "/test";
char filepath[BUF_SIZE];

#define DEB printf("DEBUG [%d:%s:%d]\n", getpid(), __FILE__, __LINE__);

static void usage(void)
{
	printf(
"./thugetlb [-m memory] [-o offset] [-f file] [-xeSAaFpch] hugetlbfs_directory\n"
"            -m|--memory size(hugepage unit)    Size of hugetlbfs file\n"
"            -o|--offset offset(page unit)      Position of error injection\n"
"            -x|--inject                        Error injection switch\n"
"            -e|--early-kill                    Set PR_MCE_KILL_EARLY\n"
"            -S|--shm                           Use shmem with SHM_HUGETLB\n"
"            -A|--anonymous                     Use MAP_ANONYMOUS\n"
"            -a|--avoid-touch                   Avoid touching error page\n"
"            -F|--fork\n"
"            -p|--private\n"
"            -c|--cow\n"
"            -f|--filename string\n"
"            -h|--help\n"
"\n"
	);
}

/*
 * semaphore get/put wrapper
 */
int get_semaphore(int sem_id, struct sembuf *sembuffer)
{
	sembuffer->sem_num = 0;
	sembuffer->sem_op  = -1;
	sembuffer->sem_flg = SEM_UNDO;
	return semop(sem_id, sembuffer, 1);
}

int put_semaphore(int sem_id, struct sembuf *sembuffer)
{
	sembuffer->sem_num = 0;
	sembuffer->sem_op  = 1;
	sembuffer->sem_flg = SEM_UNDO;
	return semop(sem_id, sembuffer, 1);
}

static int avoid_hpage(void *addr, int flag, char *avoid)
{
	return flag == 1 && addr == avoid;
}

static void write_bytes(char *addr, int flag, char *avoid)
{
	int i, j;
	for (i = 0; i < file_size; i++) {
		if (avoid_hpage(addr + i * HPAGE_SIZE, flag, avoid))
			continue;
		for (j = 0; j < HPAGE_SIZE; j++) {
			*(addr + i * HPAGE_SIZE + j) = (char)('a' +
							      ((i + j) % 26));
		}
	}
}

static void read_bytes(char *addr, int flag, char *avoid)
{
	int i, j;

	for (i = 0; i < file_size; i++) {
		if (avoid_hpage(addr + i * HPAGE_SIZE, flag, avoid))
			continue;
		for (j = 0; j < HPAGE_SIZE; j++) {
			if (*(addr + i * HPAGE_SIZE + j) != (char)('a' +
							   ((i + j) % 26))) {
				printf("Mismatch at %u\n", i + j);
				break;
			}
		}
	}
}

static struct option opts[] = {
	{ "memory"          , 1, NULL, 'm' },
	{ "offset"          , 1, NULL, 'o' },
	{ "inject"          , 0, NULL, 'x' },
	{ "early_kill"      , 0, NULL, 'e' },
	{ "shm"             , 0, NULL, 'S' },
	{ "anonymous"       , 0, NULL, 'A' },
	{ "avoid-touch"     , 0, NULL, 'a' },
	{ "fork"            , 0, NULL, 'F' },
	{ "private"         , 0, NULL, 'p' },
	{ "cow"             , 0, NULL, 'c' },
	{ "filename"        , 1, NULL, 'f' },
	{ "help"            , 0, NULL, 'h' },
	{ NULL              , 0, NULL,  0  }
};

int main(int argc, char *argv[])
{
	void *addr;
	int i;
	int ret;
	int fd = 0;
	int shmid;
	int semid;
	int semaphore;
	int inject = 0;
	int early_kill = 0;
	int avoid_touch = 0;
	int anonflag = 0;
	int shmflag = 0;
	int shmkey = 0;
	int forkflag = 0;
	int privateflag = 0;
	int cowflag = 0;
	char c;
	pid_t pid = 0;
	void *expected_addr = NULL;
	struct sembuf sembuffer;

	PS = getpagesize();
	file_size = 1;
	corrupt_page = -1;

	if (argc == 1) {
		usage();
		exit(EXIT_FAILURE);
	}

	while ((c = getopt_long(argc, argv,
				"m:o:xeSAaFpcf:h", opts, NULL)) != -1) {
		switch (c) {
		case 'm':
			file_size = strtol(optarg, NULL, 10);
			break;
		case 'o':
			corrupt_page = strtol(optarg, NULL, 10);
			break;
		case 'x':
			inject = 1;
			break;
		case 'e':
			early_kill = 1;
			break;
		case 'S':
			shmflag = 1;
			break;
		case 'A':
			anonflag = 1;
			break;
		case 'a':
			avoid_touch = 1;
			break;
		case 'F':
			forkflag = 1;
			break;
		case 'p':
			privateflag = 1;
			break;
		case 'c':
			cowflag = 1;
			break;
		case 'f':
			strcat(filename, optarg);
			shmkey = strtol(optarg, NULL, 10);
			break;
		case 'h':
			usage();
			exit(EXIT_SUCCESS);
		default:
			usage();
			exit(EXIT_FAILURE);
		}
	}

	if (inject && corrupt_page * PS > file_size * HPAGE_SIZE)
		err("Target page is out of range.\n");

	if (avoid_touch && corrupt_page == -1)
		err("Avoid which page?\n");

	/* Construct file name */
	if (access(argv[argc - 1], F_OK) == -1) {
		usage();
		exit(EXIT_FAILURE);
	} else {
		strcpy(filepath, argv[argc - 1]);
		strcat(filepath, filename);
	}

	if (shmflag) {
		if ((shmid = shmget(shmkey, file_size * HPAGE_SIZE,
				    SHM_HUGETLB | IPC_CREAT | SHM_R | SHM_W)) < 0)
			err("shmget");
		addr = shmat(shmid, (void *)0x0UL, 0);
		if (addr == (char *)-1) {
			perror("Shared memory attach failure");
			shmctl(shmid, IPC_RMID, NULL);
			exit(2);
		}
	} else if (anonflag) {
		int mapflag = MAP_ANONYMOUS | 0x40000; /* MAP_HUGETLB */
		if (privateflag)
			mapflag |= MAP_PRIVATE;
		else
			mapflag |= MAP_SHARED;
		if ((addr = mmap(0, file_size * HPAGE_SIZE,
				 PROTECTION, mapflag, -1, 0)) == MAP_FAILED)
			err("mmap");
	} else {
		int mapflag = MAP_SHARED;
		if (privateflag)
			mapflag = MAP_PRIVATE;
		if ((fd = open(filepath, O_CREAT | O_RDWR, 0777)) < 0)
			err("Open failed");
		if ((addr = mmap(0, file_size * HPAGE_SIZE,
				 PROTECTION, mapflag, fd, 0)) == MAP_FAILED) {
			unlink(filepath);
			err("mmap");
		}
	}

	if (corrupt_page != -1)
		expected_addr = (void *)(addr + corrupt_page / 512 * HPAGE_SIZE);

	if (forkflag) {
		semid = semget(IPC_PRIVATE, 1, 0666|IPC_CREAT);
		if (semid == -1) {
			perror("semget");
			goto cleanout;
		}
		semaphore = semctl(semid, 0, SETVAL, 1);
		if (semaphore == -1) {
			perror("semctl");
			goto cleanout;
		}
		if (get_semaphore(semid, &sembuffer)) {
			perror("get_semaphore");
			goto cleanout;
		}
	}

	write_bytes(addr, 0, 0);
	read_bytes(addr, 0, 0);

	if (early_kill)
		prctl(PR_MCE_KILL, PR_MCE_KILL_SET, PR_MCE_KILL_EARLY,
		      NULL, NULL);

	/*
	 * Intended order:
	 *   1. Child COWs
	 *   2. Parent madvise()s
	 *   3. Child exit()s
	 */
	if (forkflag) {
		pid = fork();
		if (!pid) {
			/* Semaphore is already held */
			if (cowflag) {
				write_bytes(addr, 0, expected_addr);
				read_bytes(addr, 0, expected_addr);
			}
			if (put_semaphore(semid, &sembuffer))
				err("put_semaphore");
			usleep(1000);
			/* Wait for madvise() to be done */
			if (get_semaphore(semid, &sembuffer))
				err("put_semaphore");
			if (put_semaphore(semid, &sembuffer))
				err("put_semaphore");
			return 0;
		}
	}

	/* Wait for COW */
	if (forkflag && get_semaphore(semid, &sembuffer)) {
		perror("get_semaphore");
		goto cleanout;
	}

	if (inject && corrupt_page != -1) {
		ret = madvise(addr + corrupt_page * PS, PS, 100);
		if (ret) {
			printf("madivise return %d :", ret);
			perror("madvise");
			goto cleanout;
		}
	}

	if (forkflag && put_semaphore(semid, &sembuffer)) {
		perror("put_semaphore");
		goto cleanout;
	}

	write_bytes(addr, avoid_touch, expected_addr);
	read_bytes(addr, avoid_touch, expected_addr);

	if (forkflag)
		if (wait(&i) == -1)
			err("wait");
cleanout:
	if (shmflag) {
		if (shmdt((const void *)addr) != 0) {
			err("Detach failure");
			shmctl(shmid, IPC_RMID, NULL);
			exit(EXIT_FAILURE);
		}
		shmctl(shmid, IPC_RMID, NULL);
	} else {
		if (munmap(addr, file_size * HPAGE_SIZE))
			err("munmap");
		if (close(fd))
			err("close");
		if (!anonflag && unlink(filepath))
			err("unlink");
	}

	return 0;
}
