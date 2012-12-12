# pread needs:
# _XOPEN_SOURCE >= 500 || /* Since glibc 2.12: */ _POSIX_C_SOURCE >= 200809L
# but this hides MAP_ANONYMOUS which comes back via _BSD_SOURCE
CFLAGS := -Wall -D _BSD_SOURCE -D _XOPEN_SOURCE=500

core_recovery: core_recovery.o

install: core_recovery

clean:
	rm -f core_recovery *.o
