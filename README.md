
# Memgraph

![Graph](/img/duc.gif)
![Graph](/img/tmillions.gif)

Memgraph is a little tool to inspect and visualize the heap usage of your
applications; it will give you a good idea of the general allocation behavior
of your code and show things like fragmentation, garbage collection behavior,
interaction between threads, etc.

Memgraph traces all memory allocations by injecting a tiny shared library that
overrides `malloc()` and `free()` and friends. Every allocation is real time in
a little gui window with the relative addresses mapped to 2D hilbert space;
where appropriate different colors will be used for different threads.

This is not a profiler or provide precise instrumentation, but relies on the
power of your own visual cortex to get a proper "feel" about the application's
behavior.

Optionally, the displayed graph can be recorded to a `.mp4` video for sharing
with your friends and family.


```
  +----------------+
  |     your app   |
  +----------------+             +--------------+
  | libmemgraph.so | ---pipe---> | memgraph gui |  [ ---pipe---> ffmpeg ]
  +----------------+             +--------------+
  |      libc      |
  +----------------+
```


## Install

Memgraph is written in Nim, so you will need to have the nim compiler and
nimble tool available on your system.

## Dependencies

- Nim, a fairly recent version
- Nim sdl2_nim SDL2 glue library
- Optionally, a working installation of ffmpeg for recording videos

## Building

```
nimble develop
make
```

## Usage

`libmemgraph.so` is a shared library that overrids `malloc()`, `free()` and
friends. It will fork and run the `memgraph` and send info for all allocations.
You will need to make sure that the `memgraph` gui binary is in your PATH.

```
PATH=$PATH:. LD_PRELOAD=./libmemgraph.so find /
```

I might provide a wrapper shell script one day, or integrate this functionality
into the `memgraph` binary.


## Configuration

Configuration for memgraph is passed by environment variables.

- `MEMGRAPH_MEM_MAX=N`: Configure the maximum memory size to be displayed in the graph, 
  the number in megabytes; when not specified, the default is 1024 (1Gb)

- `MEMGRAPH_MP4=PATH`: Record the graph to mp4 format, write the result to the file `PATH`


### Miscellaneous

For threaded programs, glibc will default to use more than one heap arena. This speeds
up the allocator, but can generate confusing memgraph output. Set the following environment
variable to make glib use only the main heap arena, which is shared by all threads:

```
GLIBC_TUNABLES=glibc.malloc.arena_max=1
````

