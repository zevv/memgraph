
import std/posix
import std/envvars
import posix/linux
import grapher
import types

type
  State = enum Init, Hooking, Hooked, Running, Disabled

var
  state: State = Init
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
  if state == Running:
    sendrec Record(p: p, size: size)

proc mark_free(p: pointer) =
  if state == Running:
    sendrec Record(p: p, size: 0)



# Install LD_PRELOAD hooks and fork grapher

proc installHooks() =

  if state == Init:
 
    state = Hooking

    proc dlsym(handle: pointer, symbol: cstring): pointer {.importc,header:"dlfcn.h".}
    const RTLD_NEXT = cast[pointer](-1)

    # Hook LD_PRELOAD functions
    malloc_real = cast[fnMalloc](dlsym(RTLD_NEXT, "malloc"))
    calloc_real = cast[fnCalloc](dlsym(RTLD_NEXT, "calloc"))
    realloc_real = cast[fnRealloc](dlsym(RTLD_NEXT, "realloc"))
    free_real = cast[fnFree](dlsym(RTLD_NEXT, "free"))

    state = Hooked

  if state == Hooked:

    delEnv("LD_PRELOAD")

    # TODO: This is a hack: dlopen() is used by nim to open the SDL
    # library, but dlopen() itself calls malloc. Ignore the first few
    # calls before starting the graphing gui for now.

    inc calls
    if calls == 256:
      # Open pipe
      var fds: array[2, cint]
      discard pipe2(fds, O_NONBLOCK)
      fd_pipe = fds[1]

      # Fork grapher process
      if fork() == 0:
        discard close(fds[1])
        grapher(fds[0])
        exitnow(0)
      else:
        discard close(fds[0])
        state = Running


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
  mark_free(p)
  free_real(p)

