
import std / [tables, strutils, posix, times]
import pkg / sdl2_nim / sdl

const
  width = 512
  height = 512
  idxMax = width * height
  blockSize = 64
  memMax = idxMax * blockSize


type

  State = enum Init, Hooking, Hooked, Running

  Record = object
    p: pointer
    size: csize_t

  Grapher = object
    allocations: Table[pointer, csize_t]
    heapstart: uint
    bytesAllocated: uint
    win: sdl.Window
    rend: sdl.Renderer
    tex: sdl.Texture
    map: ptr UncheckedArray[uint8]
    t_draw: float


var
  state: State = Init
  fd_pipe: cint



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




{.emit:"""

static int transform_table[4][4] = {{0,1,2,3},{0,2,1,3},{3,2,1,0},{3,1,2,0}};
static int locations[4] = {0,1,3,2};
static int transforms[4] = {1,0,0,3};
                      
void hilbert(int n, int *xp, int *yp)
{                     
        int x=0,y=0;
        int trans=0;
        int i;      
      
        for(i=30;i>=0;i-=2)
        {          
                int m=(n>>i)&3;
                int bits=transform_table[trans][locations[m]];
                x=(x<<1)|((bits>>1)&1);
                y=(y<<1)|(bits&1);
                trans^=transforms[m];
        }

        *xp=x; *yp=y;                          
}
  
""".}


proc hilbert(n: cint, xp, yp: ptr cint) {.importc.}


proc setPoint(g: var Grapher, idx: int, val: uint8) =
  if idx < idxMax:
    var x, y: cint
    hilbert(idx, x.addr, y.addr)
    g.map[y*width + x] = val


proc setMap(g: var Grapher, p: pointer, size: csize_t, val: uint8) =

  let rp = cast[uint](p) - g.heapstart

  if not g.map.isNil and rp < memMax:
    let nblocks = size.int div blockSize
    let idx = rp.int div blockSize

    for i in 0..<nBlocks:
      if idx >= 0 and idx < idxMax:
        if val == 0:
          g.setPoint(idx+i, 0x01)
        else:
          g.setPoint(idx+i, 0xff)



proc drawMap(g: var Grapher) =

  g.tex.unlockTexture()

  discard g.rend.renderCopy(g.tex, nil, nil);
  g.rend.renderPresent

  var pixels: pointer
  var pitch: cint
  discard g.tex.lockTexture(nil, pixels.addr, pitch.addr)

  g.map = cast[ptr UncheckedArray[uint8]](pixels)




# Handle one alloc/free record

proc handle_rec(g: var Grapher, rec: Record) =

  if rec.size > 0:
    # Handle alloc
    g.bytesAllocated += rec.size
    g.allocations[rec.p] = rec.size
    g.setMap(rec.p, rec.size, 1)

  else:
    # Handle free
    var size: int
    if rec.p in g.allocations:
      let size = g.allocations[rec.p]
      g.bytesAllocated -= size
      g.setMap(rec.p, size, 0)
      g.allocations.del rec.p


proc log(s: string) =
  stderr.write "[memgraph ", s, "]\n"

# Grapher main loop: read records from hook and process

proc grapher2(fd: cint) =
  
  log "start"
  log "memMax: " & $memMax

  signal(SIGPIPE, SIG_IGN)

  var g = Grapher()

  g.win = createWindow("memgraph", WindowPosUndefined, WindowPosUndefined, width, height, 0)
  g.rend = createRenderer(g.win, -1, sdl.RendererAccelerated and sdl.RendererPresentVsync)
  g.tex = createTexture(g.rend, PIXELFORMAT_RGB332, TEXTUREACCESS_STREAMING, width, height)

    
  # Find the start of the heap
  for l in lines("/proc/self/maps"):
    if l.contains("[heap]"):
      let ps = l.split("-")
      g.heapStart = fromHex[int](ps[0]).uint

  while true:
    var recs: array[32, Record]
    let r = read(fd, recs.addr, recs.sizeof)
    if r <= 0:
      break

    let nrecs = r div Record.sizeof
    for i in 0..<nrecs:
      g.handle_rec(recs[i])

    let t_now = epochTime()
    if t_now >= g.t_draw:
      g.drawMap()
      g.t_draw = t_now + 0.05

  log "done"


proc grapher(fd: cint) =
  try:
    grapher2(fd)
  except:
    log "exception: " & getCurrentExceptionMsg()


# Send record with alloc/free info to grapher

proc sendRec(rec: Record) =
  discard write(fd_pipe, rec.addr, rec.sizeof)

proc mark_alloc(p: pointer, size: csize_t) =
  if state == Running:
    sendrec Record(p: p, size: size)

proc mark_free(p: pointer) =
  if state == Running:
    sendrec Record(p: p, size: 0)


var calls = 0

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

    inc calls
    if calls == 256:
      # Open pipe
      var fds: array[2, cint]
      discard pipe(fds)
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

