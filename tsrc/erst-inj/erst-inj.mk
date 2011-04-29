CFLAGS := -g -Wall

erst-inject: erst-inj/erst-inject.c
	${CC} ${CFLAGS} -o erst-inject erst-inj/erst-inject.c
