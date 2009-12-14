LSRC := ../linux
BROWSER := firefox

CFLAGS += -I ${LSRC}/arch/x86/kernel/cpu/mcheck/ -g -Wall

KFLAGS := -I ./kinclude

EXE := tinjpage tsimpleinj tkillpoison tprctl tsoft tsoftinj
EXEKERNEL := tring ttable

OBJ := $(addsuffix .o,${EXE})
OBJKERNEL := $(addsuffix .o,${EXEKERNEL})

all: standalone

standalone: ${EXE}

kernel: ${EXEKERNEL}

tcases: tcases.c ${LSRC}/arch/x86/kernel/cpu/mcheck/mce-severity.c ${LSRC}/arch/x86/kernel/cpu/mcheck/mce-internal.h
	${CC} ${CFLAGS} ${KFLAGS} -o tcases tcases.c

ttable: ttable.c ${LSRC}/arch/x86/kernel/cpu/mcheck/mce-severity.c ${LSRC}/arch/x86/kernel/cpu/mcheck/mce-internal.h
	${CC} ${CFLAGS} ${KFLAGS} -o ttable ttable.c

tprctl: tprctl.o

tring: tring.o 

tring : LDFLAGS += -lpthread

x.html: ttable
	./ttable ${TFLAGS} > x.html

.PHONY: see

see: x.html
	${BROWSER} x.html

tinjpage: LDFLAGS += -lpthread

.PHONY: clean distclean

clean:
	rm -f ${EXE} ${OBJ}
	rm -f ${EXEKERNEL} ${OBJKERNEL}
	rm -f x.html

distclean: clean


