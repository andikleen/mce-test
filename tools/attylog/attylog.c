/* attylog.c: a simple tty logger */

#include <termios.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void err(const char *msg)
{
	perror(msg);
	exit(1);
}

#define ERR_ON(cond, msg)			\
	do {					\
		if (cond)			\
			err(msg);		\
	} while (0);

struct termios otio;

void setup_serial(void)
{
	int ret;
	struct termios tio;

	memset(&tio, 0, sizeof(tio));
	tio.c_cflag = B115200 | CRTSCTS | CS8 | CLOCAL | CREAD;
	tio.c_iflag = IGNPAR | ICRNL | IGNCR;
	tio.c_oflag = 0;
	tio.c_lflag = ICANON;

	ret = tcgetattr(0, &otio);
	ERR_ON(ret, "setup_serial");
	ret = tcflush(0, TCIFLUSH);
	ERR_ON(ret, "setup_serial");
	ret = tcsetattr(0, TCSANOW, &tio);
	ERR_ON(ret, "setup_serial");
}

void reset_serial(void)
{
	tcflush(0, TCIFLUSH);
	tcsetattr(0, TCSANOW, &otio);
}

void on_alarm(int signo)
{
}

void setup_timer(void)
{
	int ret;
	struct sigaction sa, osa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_alarm;
	ret = sigaction(SIGALRM, &sa, &osa);
	ERR_ON(ret, "setup_timer");
	ret = alarm(5);
	ERR_ON(ret, "setup_timer");
}

void on_term(int signo)
{
}

void setup_signal(void)
{
	int ret;
	struct sigaction sa, osa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_term;
	ret = sigaction(SIGTERM, &sa, &osa);
	ERR_ON(ret, "setup_signal");
}

void do_log(void)
{
	int ret;
	char buf[80];

	while (1) {
		ret = read(0, buf, sizeof(buf));
		if (ret == -1) {
			/* timeout */
			if (errno == EINTR)
				break;
			err("read");
		}
		ret = write(1, buf, ret);
		ERR_ON(ret == -1, "write");
	}
}

int main(int argc, char *argv[])
{
	setup_serial();
	//setup_timer();
	setup_signal();
	do_log();
	reset_serial();
	return 0;
}
