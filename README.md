
example using actors tmillions:

```
cd actors
nim c -d:release -d:usemalloc --mm:arc tests/tmillions.nim
```

```
make 
LD_PRELOAD=./libmemgraph.so /tmp/tmillions
```

Enable recording with:

```
MEMGRAPH_MP4=memgraph.mp4
```

To make glibc behave with one heap, set this env var:

```
GLIBC_TUNABLES=glibc.malloc.mmap_max=0:glibc.malloc.arena_max=1
````

