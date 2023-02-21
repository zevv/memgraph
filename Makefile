
NIMFLAGS += --debugger:native
NIMFLAGS += -d:usemalloc
NIMFLAGS += -d:danger

all: libmemgraph.so memgraph

libmemgraph.so: libmemgraph.nim types.nim Makefile
	nim c $(NIMFLAGS) --app:lib --out:libmemgraph.so libmemgraph.nim

memgraph: memgraph.nim types.nim Makefile
	nim c $(NIMFLAGS) --out:memgraph memgraph.nim 

clean:
	rm -f libmemgraph.so
