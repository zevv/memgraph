
example using actors tmillions:

```
cd actors
nim c -d:release -d:usemalloc --mm:arc tests/tmillions.nim
```

```
make 
PATH=$PATH:. MEMGRAPH_MP4=memgraph.mp4 LD_PRELOAD=./libmemgraph.so GLIBC_TUNABLES=glibc.malloc.arena_max=1 ~/sandbox/prjs/actors/tests/tmillions 
```

Enable recording with:

```
MEMGRAPH_MP4=memgraph.mp4
```

To make glibc behave with one heap, set this env var:

```
GLIBC_TUNABLES=glibc.malloc.arena_max=1
````

