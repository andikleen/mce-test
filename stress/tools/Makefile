SUBDIRS ?= fs-metadata page-poisoning

all:
	@for i in ${SUBDIRS}; do        \
		${MAKE} -C $$i $@;      \
	done

clean:
	@for i in ${SUBDIRS}; do        \
		${MAKE} -C $$i $@;      \
	done
	rm -rf tmp result

distclean:
	@for i in ${SUBDIRS}; do        \
		${MAKE} -C $$i $@;      \
	done
