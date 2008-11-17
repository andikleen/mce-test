EXEC_NAME = readcore
OBJS = readcore.o mem_image.o util.o
SRC = readcore.c mem_image.c util.c

CC = gcc
CFLAGS = -Wall -O2
LDFLAGS =
LIBS =

$(EXEC_NAME) : $(OBJS)
	$(CC) -o $@ $(LDFLAGS) $^ $(LIBS)

clean :
	rm -rf $(EXEC_NAME) $(OBJS)

distclean: clean
	rm -f ${DISTCLEAN} *~
	rm -f .depend

depend: .depend

.depend: ${SRC}
	${CC} -MM -DDEPS_RUN -I. ${SRC} ${GENSRC} > .depend.X && \
		mv .depend.X .depend

Makefile: .depend

include .depend
