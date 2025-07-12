#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <sys/types.h>
#include <sys/wait.h>

#define ARR_SZ(a) (sizeof(a)/sizeof((a)[0]))
#define PI (355.0/113.0)

int
st_plot(void)
{
	int fds[2];
	FILE *gplot;
	pid_t pid;
	double x;
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
	fprintf(gplot, "set output \"out.svg\"\n");
	fprintf(gplot, "plot \"-\"\n");
	for (x = 0; x < 2*PI; x += PI/100)
		fprintf(gplot, "%0.3f %0.3f\n", x, sin(x));
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
