
import std/posix
import posix/linux
import types

type
  fnMalloc = proc(size: csize_t): pointer {.cdecl.}
  fnCalloc = proc(nmemb, size: csize_t): pointer {.cdecl.}
  fnFree = proc(p: pointer) {.cdecl.}
  fnRealloc = proc(p: pointer, size: csize_t): pointer {.cdecl.}

var
  fd_pipe: cint
  calls: int
  tid {.threadvar.}: int
  hooked: bool

  malloc_real {.exportc.}: fnMalloc
  calloc_real {.exportc.}: fnCalloc
  realloc_real {.exportc.}: fnRealloc
  free_real {.exportc.} : fnFree

proc atoi(s: cstring): cint {.importc, header: "<stdlib.h>".}
proc getenv(c: cstring): cstring {.importc, header: "<stdlib.h>".}

# Send record with alloc/free info to grapher

proc sendRec(rec: Record) =
  if fd_pipe != 0:
    discard write(fd_pipe, rec.addr, rec.sizeof)

proc mark_alloc(p: pointer, size: csize_t) =
  if tid == 0:
    tid = getThreadId()
  sendRec Record(p: cast[uint64](p), size: size.uint32, tid: tid)

proc mark_free(p: pointer) =
  sendRec Record(p: cast[uint64](p), size: 0.uint32, tid: tid)


# Install LD_PRELOAD hooks

proc installHooks() =

  if not hooked:

    proc dlsym(handle: pointer, symbol: cstring): pointer {.importc,header:"dlfcn.h".}
    const RTLD_NEXT = cast[pointer](-1)

    malloc_real = cast[fnMalloc](dlsym(RTLD_NEXT, "malloc"))
    calloc_real = cast[fnCalloc](dlsym(RTLD_NEXT, "calloc"))
    realloc_real = cast[fnRealloc](dlsym(RTLD_NEXT, "realloc"))
    free_real = cast[fnFree](dlsym(RTLD_NEXT, "free"))
   
    let e = getenv("MEMGRAPH_FD_PIPE")
    if not e.isNil:
      fd_pipe = atoi(e)

    hooked = true


# LD_PRELOAD hooks

proc malloc*(size: csize_t): pointer {.exportc,dynlib.} =
  installHooks()
  result = malloc_real(size)
  mark_alloc(result, size)

proc calloc*(nmemb, size: csize_t): pointer {.exportc,dynlib.} =
  installHooks()
  result = calloc_real(nmemb, size)
  mark_alloc(result, size * nmemb)

proc realloc*(p: pointer, size: csize_t): pointer {.exportc,dynlib.} =
  installHooks()
  if not p.isNil:
    mark_free(p)
  result = realloc_real(p, size)
  mark_alloc(result, size)

proc free*(p: pointer) {.exportc,dynlib.} =
  installHooks()
  if not p.isNil:
    mark_free(p)
  free_real(p)

