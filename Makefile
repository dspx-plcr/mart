MART_SRC = confs.odin game.odin mart.odin strats.odin
RUNNER_SRC = runner.ha

runner: mart $(RUNNER_SRC)
	hare build $(RUNNER_SRC)

mart: $(MART_SRC)
	odin build .

clean:
	rm -rf logs runner mart
