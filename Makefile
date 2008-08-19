
all:
	$(MAKE) -C tools

clean:
	$(MAKE) -C tools clean
	$(MAKE) reset

reset:
	rm -rf work/*
	rm -rf results/*

test:
	$(MAKE) reset
	./drivers/simple/driver.sh simple.conf
