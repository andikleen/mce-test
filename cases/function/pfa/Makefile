# pread needs:
# _XOPEN_SOURCE >= 500 || /* Since glibc 2.12: */ _POSIX_C_SOURCE >= 200809L
# but this hides MAP_ANONYMOUS which comes back via _BSD_SOURCE
CFLAGS := -g -Wall -D _BSD_SOURCE -D _XOPEN_SOURCE=500

all: pfa busy
pfa: pfa.o
busy: busy.o

install: all

clean:
	rm -f *.o pfa busy
