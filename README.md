
## Building

```
make
```

## Usage

`libmemgraph.so` is a shared library that overrids `malloc()`, `free()` and friends. It will
fork and run the `memgraph` and send info for all allocations.


```
make 
PATH=$PATH:. LD_PRELOAD=./libmemgraph.so ~/sandbox/prjs/actors/tests/tmillions 
```

### Recording

Enable recording with:

```
MEMGRAPH_MP4=memgraph.mp4
```

### Heaps

For threaded programs, glibc will default to use more than one heap arena. This speeds
up the allocator, but can generate confusing memgraph output. Set the following environment
variable to make glib use only the main heap arena, which is shared by all threads:

```
GLIBC_TUNABLES=glibc.malloc.arena_max=1
````

