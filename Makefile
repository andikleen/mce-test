
all:
	$(MAKE) -C tools
	$(MAKE) -C tsrc
	$(MAKE) -C stress

clean:
	$(MAKE) -C tools clean
	$(MAKE) -C tsrc clean
	$(MAKE) -C stress clean
	$(MAKE) reset

distclean:
	$(MAKE) -C tools distclean
	$(MAKE) -C tsrc distclean
	$(MAKE) -C stress distclean
	$(MAKE) reset

reset:
	rm -rf work/*
	rm -rf results/*

test:
	$(MAKE) reset
	./drivers/simple/driver.sh simple.conf
	./drivers/kdump/driver.sh kdump.conf
	$(MAKE) -C tsrc test

test-simple:
	$(MAKE) reset
	./drivers/simple/driver.sh simple.conf
	$(MAKE) -C tsrc test
