CFLAGS += -I -g -Wall

EXE := tinjpage tsimpleinj tkillpoison tprctl tsoft tsoftinj
EXE += thugetlb ttranshuge

OBJ := $(addsuffix .o,${EXE})

all: ${EXE}

install: all
	cp ttranshuge ../../../bin/

tinjpage: LDFLAGS += -pthread

clean:
	rm -f ${EXE} ${OBJ}
	rm -f unpoison-failed offlined
	rm -f ~test* ~poison*

