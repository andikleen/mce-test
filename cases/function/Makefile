all:
	$(MAKE) -C erst-inject
	$(MAKE) -C pfa
	$(MAKE) -C hwpoison
	$(MAKE) -C core_recovery
#	$(MAKE) -C kvm

clean:
	$(MAKE) -C erst-inject clean
	$(MAKE) -C pfa clean
	$(MAKE) -C hwpoison clean
	$(MAKE) -C core_recovery clean
#	$(MAKE) -C kvm clean

install:
	$(MAKE) -C erst-inject install
	$(MAKE) -C pfa install
	$(MAKE) -C hwpoison install
	$(MAKE) -C core_recovery install
#	$(MAKE) -C kvm install

