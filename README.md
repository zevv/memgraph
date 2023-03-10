
# Memgraph

> "_It's like rainbow brite vomited all over my screen._"

![Graph](/img/duc.gif)
![Graph](/img/tmillions.gif)

Memgraph is a little tool to inspect and visualize the heap usage of your
applications; it will give you a good idea of the general allocation behavior
of your code and show things like fragmentation, garbage collection behavior,
leaking rates, interaction between threads, etc.

Memgraph traces all memory allocations by injecting a tiny shared library that
overrides `malloc()` and `free()` and friends. Every allocation is drawn in
real time in a little gui window with the relative addresses mapped to 2D
hilbert space; where different colors will be used for different threads. The
brightness of the allocations fades with time, showing you which allocations
are new and which have been around for some time.

Memgraph is not a proper profiler, nor does it provide precise instrumentation.
Instead it relies on the power of your own visual cortex to get a proper "feel"
about the application's behavior.

As a bonus, the displayed graph can be recorded to a video for sharing with
your friends and family.


## Install

Memgraph is written in Nim, so you will need to have the nim compiler and
nimble tool available on your system.


## Dependencies

- A fairly recent version of the Nim compiler
- SDL2 libraries + header files, (`libsdl2-dev` or similar)
- Nim libraries sdl2_nim and npeg (will be downloaded by Nimble for you)
- Optionally, a working installation of ffmpeg for recording videos


## Building

```
nimble develop
make
```


## Usage

Just run `memgraph`, followed by your program and its optional arguments:

```
usage: memgraph [options] <cmd> [cmd options]

options:
  -h  --help         show help
  -m  --memmax=MB    set max memory size [64]
  -v  --video=FNAME  write video to FNAME. Must be .mp4
  -s  --space=SPACE  set 2D space mapping [hilbert]

available 2D space mappings:
  hilbert, linear
```

This is a nice example command to see memgraph at work:

```
./memgraph -m 1 find / -xdev
```


## Configuration

Memgraph has a few options which can be configured with command line
arguments:

- `-m  --memmax=MB    set max memory size [64]`

  Configure the maximum memory size to be displayed in the graph, 
  the number in megabytes; when not specified, the default is 1024 (1Gb)

- `-v  --video=FNAME  write video to FNAME. Must be .mp4`

  Record the graph to mp4 format, write the result to the file `PATH`.
  To use this option you need a working installation of ffmpeg on your machine.

- `-s  --space=SPACE  set 2D space mapping [hilbert]`

  Configure the way for mapping memory addresses to a pixel on the screen. 
  The default setting is `hilbert, which provides nice locality.


## Miscellaneous

### Non-default allocators

Memgraph only works for applications that use the default C libraries
allocation functions `malloc()`, `calloc()`, `realloc()` and `free()`. Some
applications try to outsmart the default allocators by providing their own
implementation instead, so memgraph will not be able to hook into those and
graph your memory. Notably, Nim programs are default compiled with the internal
Nim allocator. If you want to profile Nim code, make sure to compile it with
the `-d:usemalloc` flag.


### Glibc heap arenas

For threaded programs, glibc will default to use more than one heap arena. This speeds
up the allocator, but can generate confusing memgraph output. Set the following environment
variable to make glib use only the main heap arena, which is shared by all threads:

```
GLIBC_TUNABLES=glibc.malloc.arena_max=1
````


### Under the hood

Memgraph consists of two parts: one small shared library that gets injected
before starting your program using LD_PRELOAD, and the gui program that
displays the memory allocations.


```
  +----------------+
  |    your app    |
  +----------------+             +--------------+
  | libmemgraph.so | ---pipe---> | memgraph gui |  [ ---pipe---> ffmpeg ]
  +----------------+             +--------------+
  |      libc      |
  +----------------+
```


