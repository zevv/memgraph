
NIMFLAGS += -d:usemalloc -d:danger

libmemgraph.so: memgraph.nim
	nim c $(NIMFLAGS) --app:lib memgraph.nim

clean:
	rm -f libmemgraph.so
