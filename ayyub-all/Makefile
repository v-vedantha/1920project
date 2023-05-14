.DEFAULT_GOAL := all
BUILD_DIR=build
<<<<<<< HEAD
BINARY_NAME= top_pipelined#PPPTest CacheTest MessageRouterTest MessageFifoTest #multicycle top_bsv top_pipelined DelayLine MainMem Beveren MessageFifoTest
=======
BINARY_NAME=top_pipelined # DelayLine MainMem # Beveren CacheTest PPPTest MessageRouterTest MessageFifoTest multicycle top_bsv
>>>>>>> 2e365086819167b1aa2652f0c896dc2e644c5cd3
BSC_FLAGS=--aggressive-conditions --show-schedule -vdir $(BUILD_DIR) -bdir $(BUILD_DIR) -simdir $(BUILD_DIR) -o 

.PHONY: clean all $(BINARY_NAME)

$(BINARY_NAME):
	mkdir -p $(BUILD_DIR)
	bsc $(BSC_FLAGS) $@ -sim -g mk$@ -u $@.bsv
	bsc $(BSC_FLAGS) $@ -sim -e mk$@

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(BINARY_NAME)
	rm -f *.so
	rm -f *.sched

all: clean $(BINARY_NAME)

