CFLAGS := -g -Wall
LDFLAGS +=

OBJ := attylog.o
SRC := attylog.c
CLEAN := ${OBJ} ${GENSRC} attylog
DISTCLEAN := .depend .gdb_history

.PHONY: clean depend

attylog: ${OBJ}

clean:
	rm -f ${CLEAN}

distclean: clean
	rm -f ${DISTCLEAN} *~

depend: .depend

.depend: ${SRC} ${GENSRC}
	${CC} -MM -DDEPS_RUN -I. ${SRC} ${GENSRC} > .depend.X && \
		mv .depend.X .depend

Makefile: .depend

include .depend
