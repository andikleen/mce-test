CFLAGS := -g -Wall

ltp-pan: ltp-pan.o zoolib.o splitstr.o

install: ltp-pan
	cp -f ltp-pan ../../bin
clean:
	rm -f *.o ltp-pan
