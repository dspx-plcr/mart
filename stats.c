#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/types.h>
#include <sys/wait.h>

#define ARR_SZ(a) (sizeof(a)/sizeof((a)[0]))
#define PI (355.0/113.0)

struct stats {
	char *name;
	unsigned char protver;
	size_t nplayers;
	long long *money;
	char buf[32];
	size_t bufsz;
};

/* TODO: alloc all up front? */
struct stats *
st_new(const char *name)
{
	struct stats *res;
	long long *money;

	if ((res = malloc(sizeof(struct stats))) == NULL)
		return NULL;
	if ((res->name = strdup(name)) == NULL)
		goto free_res;
	/* TODO: Don't hardcode this */
	res->nplayers = 4;
	if ((res->money = malloc(sizeof(long long) * res->nplayers)) == NULL)
		goto free_name;
	memset(res->money, 0, sizeof(long long) * res->nplayers);
	res->bufsz = 0;

	return res;

free_name:
	free(res->name);
free_res:
	free(res);
	return NULL;
}

int
parse_command(struct stats *st)
{
	long long money;
	size_t player;

	if (st->buf[0] != 'm')
		goto exit;

	if (sscanf(st->buf+1, "%lldp%zu", &money, &player) < 0) {
		fprintf(stderr, "couldn't parse cmd\n");
		return -1;
	}
	if (player > st->nplayers) {
		fprintf(stderr, "player number too high: %zu\n", player);
		return -1;
	}
	st->money[player] += money;

exit:
	st->bufsz = 0;
	return 0;
}

/* TODO: We don't want this guy */
struct hare_slice {
	const char *data;
	size_t len;
	size_t cap;
};

int
st_input(struct stats *st, struct hare_slice slice, size_t size)
{
	const char *buf = slice.data;
	const char *ptr;

	while (size > 0) {
		ptr = buf;
		while (ptr < buf + size && *ptr != '\n')
			ptr++;
		if (ARR_SZ(st->buf) - st->bufsz < ptr - buf)
			return -1;

		memcpy(st->buf + st->bufsz, buf, ptr - buf);
		st->bufsz += ptr - buf;
		st->buf[st->bufsz] = 0;

		if (ptr == buf + size)
			return 0;

		if (parse_command(st))
			return -2;
		size -= ptr - buf + 1;
		buf = ptr + 1;
	}

	return 0;
}

int
st_plot(struct stats *st)
{
	int fds[2];
	FILE *gplot;
	pid_t pid;
	size_t x;
	int status;

	if (pipe(fds) < 0)
		return -1;

	pid = fork();
	if (pid < 0) 
		return -1;
	if (!pid) {
		close(1);
		close(2);
		if (dup2(fds[0], 0) < 0)
			return -1;
		execlp("gnuplot", "gnuplot", NULL);
		exit(1);
	}

	close(fds[0]);
	gplot = fdopen(fds[1], "w");
	if (gplot == NULL)
		return -1;

	fprintf(gplot, "set title \"Basic Example\"\n");
	fprintf(gplot, "set terminal svg\n");
	fprintf(gplot, "set output \"%s\"\n", st->name);
	fprintf(gplot, "set key off\n");
	fprintf(gplot, "set style fill solid 1.0\n");
	fprintf(gplot, "set offsets 0.5, 0.5, graph 0.1, 0\n");
	fprintf(gplot, "set auto fix\n");
	fprintf(gplot, "set xtics 1\n");
	fprintf(gplot, "set yrange [*<0]\n");
	fprintf(gplot, "plot \"-\" with boxes fc \"#808080\"\n");
	for (x = 0; x < st->nplayers; x++) {
		fprintf(gplot, "%zu %lld\n", x, st->money[x]);
	}
	fprintf(gplot, "e\n");
	fprintf(gplot, "quit\n");
	fflush(gplot);
	fclose(gplot);

	if (waitpid(pid, &status, 0) < 0)
		return -1;

	if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
		errno = 0;
		return -1;
	}

	return 0;
}
