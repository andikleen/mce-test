CFLAGS := -g -Wall
LDFLAGS := -g

export CFLAGS
export LDFLAGS

all:
	mkdir -p bin
	$(MAKE) -C tools install

clean:
	$(MAKE) -C tools clean
	rm -rf bin log result runtest hwpoison
