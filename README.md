
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

## Configuration

Configuration for memgraph is passed by environment variables.

- `MEMGRAPH_MEM_MAX=N`: Configure the maximum memory size to be displayed in the graph, setting in MB; when
  not specified, the default is 1024MB

- `MEMGRAPH_MP4=PATH`: Record the graph to mp4 format, write the result to the file `PATH`


### Misc

For threaded programs, glibc will default to use more than one heap arena. This speeds
up the allocator, but can generate confusing memgraph output. Set the following environment
variable to make glib use only the main heap arena, which is shared by all threads:

```
GLIBC_TUNABLES=glibc.malloc.arena_max=1
````

