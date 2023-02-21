
NIMFLAGS += --debugger:native
NIMFLAGS += --panics:off
NIMFLAGS += -d:usemalloc -d:danger

all: libmemgraph.so memgraph

libmemgraph.so: libmemgraph.nim Makefile
	nim c $(NIMFLAGS) --app:lib --out:libmemgraph.so libmemgraph.nim

memgraph: memgraph.nim Makefile
	nim c $(NIMFLAGS) --out:memgraph memgraph.nim 

clean:
	rm -f libmemgraph.so
