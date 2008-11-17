#ifndef UTIL_H
#define UTIL_H

void error_exit(char *fmt, ...);

#define ERROR_EXIT(fmt, ...)					\
	do {							\
		error_exit(fmt, ## __VA_ARGS__);		\
	} while (0)

#define ERROR_EXIT_ON(check, fmt, ...)				\
	do {							\
		if (check)					\
			error_exit(fmt, ## __VA_ARGS__);	\
	} while (0)

#endif
