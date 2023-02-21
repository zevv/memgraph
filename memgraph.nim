
import tables
import strutils
import posix

import types

type

  State = enum Init, Hooking, Hooked, Grapher

const
  memMax = 512 * 1024
  blockSize = 2048
  idxMax = memMax div blockSize

var
  state: State = Init
  allocations: Table[pointer, csize_t]
  heapstart: uint
  map: array[idxMax, uint8]
  fd_pipe: cint




const RTLD_NEXT = cast[pointer](-1)
proc dlsym(handle: pointer, symbol: cstring): pointer {.importc,header:"dlfcn.h".}
proc strtol(nptr: cstring, endptr: pointer, base: int): clong {.importc,header:"stdlib.h".}

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


# Update allocation age map

proc setMap(p: pointer, size: csize_t, val: uint8) =

  let rp = cast[uint](p) - heapstart

  if rp < memMax:
    let nblocks = size.int div blockSize
    let idx = rp.int div blockSize

    for i in 0..<nBlocks:
      if idx >= 0 and idx < idxMax:
        map[idx+i] = val


proc drawMap() =
  for i in map:
    stdout.write($i)
  stdout.write("\n")


# Handle one alloc/free record

proc handle_rec(rec: Record) =

  if rec.size > 0:
    # Handle alloc
    echo "alloc ", rec.p.repr, " ", rec.size
    allocations[rec.p] = rec.size
    setMap(rec.p, rec.size, 1)

  else:
    # Handle free
    var size: int
    if rec.p in allocations:
      setMap(rec.p, allocations[rec.p], 0)
      allocations.del rec.p

  #drawMap()


# Grapher main loop: read records from hook and process

proc grapher(fd: cint) =

  while true:
    var recs: array[32, Record]
    let r = read(fd, recs.addr, recs.sizeof)
    if r <= 0:
      echo "read error"
      break

    let nrecs = r div Record.sizeof
    for i in 0..<nrecs:
      handle_rec(recs[i])


# Send record with alloc/free info to grapher

proc sendRec(rec: Record) =
  discard write(fd_pipe, rec.addr, rec.sizeof)

proc mark_alloc(p: pointer, size: csize_t) =
  if state == Hooked:
    sendrec Record(p: p, size: size)

proc mark_free(p: pointer) =
  if state == Hooked:
    sendrec Record(p: p, size: 0)


# Install LD_PRELOAD hooks and fork grapher

proc installHook() =

  if state != Init:
    return

  state = Hooking

  # Hook LD_PRELOAD functions
  malloc_real = cast[fnMalloc](dlsym(RTLD_NEXT, "malloc"))
  calloc_real = cast[fnCalloc](dlsym(RTLD_NEXT, "calloc"))
  realloc_real = cast[fnRealloc](dlsym(RTLD_NEXT, "realloc"))
  free_real = cast[fnFree](dlsym(RTLD_NEXT, "free"))
    
  # Find the start of the heap
  for l in lines("/proc/self/maps"):
    if l.contains("[heap]"):
      heapstart = strtol(l.cstring, nil, 16).uint

  # Open pipe
  var fds: array[2, cint]
  discard pipe(fds)
  fd_pipe = fds[1]

  # Fork grapher process
  if fork() == 0:
    state = Grapher
    grapher(fds[0])
    exitnow(0)
  else:
    # Mark hook complete
    state = Hooked


# LD_PRELOAD hooks

proc malloc*(size: csize_t): pointer {.exportc,dynlib.} =
  installHook()
  result = malloc_real(size)
  mark_alloc(result, size)

proc calloc*(nmemb, size: csize_t): pointer {.exportc,dynlib.} =
  installHook()
  result = calloc_real(nmemb, size)
  mark_alloc(result, size * nmemb)

proc realloc*(p: pointer, size: csize_t): pointer {.exportc,dynlib.} =
  installHook()
  if not p.isNil:
    mark_free(p)
  result = realloc_real(p, size)
  mark_alloc(result, size)

proc free*(p: pointer) {.exportc,dynlib.} =
  installHook()
  mark_free(p)
  free_real(p)

