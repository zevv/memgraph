
import std/posix
import std/envvars
import posix/linux
import types

var
  fd_pipe: cint
  calls: int

type
  fnMalloc = proc(size: csize_t): pointer {.cdecl.}
  fnCalloc = proc(nmemb, size: csize_t): pointer {.cdecl.}
  fnFree = proc(p: pointer) {.cdecl.}
  fnRealloc = proc(p: pointer, size: csize_t): pointer {.cdecl.}

var
  malloc_real {.exportc.}: fnMalloc
  calloc_real {.exportc.}: fnCalloc
  realloc_real {.exportc.}: fnRealloc
  free_real {.exportc.} : fnFree


# Send record with alloc/free info to grapher

proc sendRec(rec: Record) =
  discard write(fd_pipe, rec.addr, rec.sizeof)

proc mark_alloc(p: pointer, size: csize_t) =
  sendRec Record(p: p, size: size)

proc mark_free(p: pointer) =
  sendRec Record(p: p, size: 0)


# Install LD_PRELOAD hooks and fork grapher

proc installHooks() =

  proc dlsym(handle: pointer, symbol: cstring): pointer {.importc,header:"dlfcn.h".}
  const RTLD_NEXT = cast[pointer](-1)

  # Hook LD_PRELOAD functions
  malloc_real = cast[fnMalloc](dlsym(RTLD_NEXT, "malloc"))
  calloc_real = cast[fnCalloc](dlsym(RTLD_NEXT, "calloc"))
  realloc_real = cast[fnRealloc](dlsym(RTLD_NEXT, "realloc"))
  free_real = cast[fnFree](dlsym(RTLD_NEXT, "free"))

  # Open pipes
  var fds: array[2, cint]
  discard pipe(fds)
    
  # Fork grapher process
  delEnv("LD_PRELOAD")
  if fork() == 0:
    discard dup2(fds[0], 0)
    discard close(fds[0])
    discard close(fds[1])
    discard execlp("memgraph", "memgraph", nil)
    echo "error execing memgraph: ", $strerror(errno)
    exitnow(0)
  else:
    discard close(fds[0])
    fd_pipe = fds[1]


# LD_PRELOAD hooks

{.emit:" void init(void) __attribute__((constructor)); ".}

proc init() {.cdecl,exportc.} =
  installHooks()

proc malloc*(size: csize_t): pointer {.exportc,dynlib.} =
  result = malloc_real(size)
  mark_alloc(result, size)

proc calloc*(nmemb, size: csize_t): pointer {.exportc,dynlib.} =
  result = calloc_real(nmemb, size)
  mark_alloc(result, size * nmemb)

proc realloc*(p: pointer, size: csize_t): pointer {.exportc,dynlib.} =
  mark_free(p)
  result = realloc_real(p, size)
  mark_alloc(result, size)

proc free*(p: pointer) {.exportc,dynlib.} =
  mark_free(p)
  free_real(p)

