LSRC := ../linux
BROWSER := links -g

CFLAGS += -I ${LSRC}/arch/x86/kernel/cpu/mcheck/ -g -Wall

all: tcases tinjpage tkillpoison ttable

tcases: tcases.c ${LSRC}/arch/x86/kernel/cpu/mcheck/mce-severity.c ${LSRC}/arch/x86/kernel/cpu/mcheck/mce-internal.h
	${CC} ${CFLAGS} -o tcases tcases.c

ttable: ttable.c ${LSRC}/arch/x86/kernel/cpu/mcheck/mce-severity.c ${LSRC}/arch/x86/kernel/cpu/mcheck/mce-internal.h
	${CC} ${CFLAGS} -o ttable ttable.c

x.html: ttable
	./ttable ${TFLAGS} > x.html

.PHONY: see

see: x.html
	${BROWSER} x.html

tinjpage: LDFLAGS += -lpthread

.PHONY: clean

clean:
	rm -f tcases ttable x.html tinjpage	
	rm -f tkillpoison tring

