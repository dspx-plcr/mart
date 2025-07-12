MART_SRC = confs.odin game.odin mart.odin strats.odin
RUNNER_SRC = runner.ha
LDFLAGS = \
	-lm -L. -lstats

runner: mart $(RUNNER_SRC) libstats.a
	rm -rf $(XDG_CACHE_HOME)/hare
	hare build $(LDFLAGS) $(RUNNER_SRC)

.c.o:
	cc -c $^

libstats.a: stats.o
	ar -r libstats.a stats.o

mart: $(MART_SRC)
	odin build .

clean:
	rm -rf logs runner mart
