all:
	$(MAKE) -C tools
	$(MAKE) -C cases

clean:
	$(MAKE) -C tools clean
	$(MAKE) -C cases clean
	$(MAKE) reset

install:
	$(MAKE) -C tools install
	$(MAKE) -C cases install

reset:
	rm -rf bin/*
	rm -rf work/*

