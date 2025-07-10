#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define ARR_SZ(x) (sizeof(x)/sizeof((x)[0]))
#define	N_STRATS (ARR_SZ(all_strats))
#define NUM_FDS (N_STRATS*N_STRATS*N_STRATS*N_STRATS)

static const char *all_strats[] = {
	"Expected Return",
	"First Card, All In",
	"Random"
};

static char *
game_name(size_t s1, size_t s2, size_t s3, size_t s4)
{
	static size_t maxlen = 0;
	char *res, *ptr;
	size_t pos, i;

	if (!maxlen)
		for (i = 0; i < N_STRATS; i++)
			if (strlen(all_strats[i]) > maxlen)
				maxlen = strlen(all_strats[i]);
	res = malloc(maxlen*4 + 3*3 + 1);
	if (!res) err(1, "couldn't malloc game_name");
	ptr = res;

	pos = 0;
	strcpy(ptr, all_strats[s1]);
	pos += strlen(all_strats[s1]);
	ptr += pos;
	while (pos++ < maxlen) *ptr++ = ' ';
	strcpy(ptr, " | ");
	ptr += 3;
	pos = 0;

	pos = 0;
	strcpy(ptr, all_strats[s2]);
	pos += strlen(all_strats[s2]);
	ptr += pos;
	while (pos++ < maxlen) *ptr++ = ' ';
	strcpy(ptr, " | ");
	ptr += 3;
	pos = 0;

	pos = 0;
	strcpy(ptr, all_strats[s3]);
	pos += strlen(all_strats[s3]);
	ptr += pos;
	while (pos++ < maxlen) *ptr++ = ' ';
	strcpy(ptr, " | ");
	ptr += 3;
	pos = 0;

	strcpy(ptr, all_strats[s4]);

	return res;
}

static char *
make_arg(const char *base, const char *strat)
{
	char *res;
	res = malloc(strlen(base) + strlen(strat) + 1);
	if (!res) err(1, "couldn't malloc strategy");
	strcpy(res, base);
	strcpy(res+strlen(base), strat);
	res[strlen(base)+strlen(strat)] = 0;
	return res;
}

static int
run_process(size_t s1, size_t s2, size_t s3, size_t s4)
{
	pid_t pid;
	int fds[2];
	char *logname, *gamename;
	char *args[] = {
		"mart",
		"-strategy:",
		"-strategy:",
		"-strategy:",
		"-strategy:",
		"-log:logs/",
		"-n:100",
		NULL
	};

	if (pipe(fds) < 0)
		err(1, "couldn't pipe");
	if (fcntl(fds[0], F_SETFL, O_NONBLOCK) < 0)
		err(1, "couldn't make pipe non-blocking");

	pid = fork();
	if (pid < 0)
		err(1, "couldn't fork");
	if (pid) {
		close(fds[1]);
		return fds[0];
	}
	close(fds[0]);

	args[1] = make_arg(args[1], all_strats[s1]);
	args[2] = make_arg(args[2], all_strats[s2]);
	args[3] = make_arg(args[3], all_strats[s3]);
	args[4] = make_arg(args[4], all_strats[s4]);

	gamename = game_name(s1, s2, s3, s4);
	logname = malloc(strlen(gamename) + strlen(args[5]) + 1);
	if (!logname) err(1, "couldn't malloc logname");
	strcpy(logname, args[5]);
	strcpy(logname+strlen(args[5]), gamename);
	logname[strlen(args[5])+strlen(gamename)] = 0;
	free(gamename);
	args[5] = logname;

	if (dup2(fds[1], 1) < 0)
		err(1, "couldn't dup in child");

	execv("./mart", args);
	err(1, "execv failed");
}

int
main(void)
{
	size_t i, j, k, l;
	struct pollfd pfds[NUM_FDS];
	nfds_t numfds = NUM_FDS;
	size_t pos = 0;

	for (i = 0; i < N_STRATS; i++)
		for (j = 0; j < N_STRATS; j++)
			for (k = 0; k < N_STRATS; k++)
				for (l = 0; l < N_STRATS; l++) {
					pfds[pos].fd = run_process(i, j, k, l);
					pfds[pos].events = POLLPRI | POLLIN;
					pos++;
				}


	while (numfds > 0) {
		int n = poll(pfds, numfds, -1);
		if (n == 0) continue;
		if (n < -1) err(1, "couldn't poll fds");

		for (i = 0; i < numfds; i++) {
			ssize_t num;
			char buf[1024];

			if (pfds[i].revents & POLLERR)
				err(1, "couldn't poll buf"); 
			num = read(pfds[i].fd, buf, ARR_SZ(buf));
			if (num < 0 && errno != EAGAIN)
				err(1, "couldn't read from fd");
			if (num < 0) continue;
			if (!num) {
				if (i + 1 < numfds)
					memmove(pfds+i, pfds+i+1, numfds-i);
				numfds--;
				i--;
				continue;
			}
			write(1, buf, num);
			fflush(stdout);
		}
	}
}
