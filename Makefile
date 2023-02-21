
NIMFLAGS += --debugger:native
NIMFLAGS += --panics:off
NIMFLAGS += -d:usemalloc -d:danger

libmemgraph.so: memgraph.nim Makefile
	nim c $(NIMFLAGS) --app:lib memgraph.nim

clean:
	rm -f libmemgraph.so
