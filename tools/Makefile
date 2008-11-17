
all:
	$(MAKE) -C attylog
	cp attylog/attylog ../bin
	$(MAKE) -C readcore
	cp readcore/readcore ../bin

clean:
	$(MAKE) -C attylog clean
	rm -f ../bin/attylog
	$(MAKE) -C readcore clean
	rm -f ../bin/readcore
