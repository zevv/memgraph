
import std / [tables, strutils, posix, times, os]
import pkg / sdl2_nim / sdl
import types

const
  width = 512
  height = 512
  idxMax = width * height
  blockSize = 128
  memMax = idxMax * blockSize


type

  Grapher = object
    allocations: Table[pointer, csize_t]
    heapStart: uint
    bytesAllocated: uint
    win: sdl.Window
    rend: sdl.Renderer
    tex: sdl.Texture
    map: ptr UncheckedArray[uint8]
    t_draw: float




proc hilbert(n: cint, xp, yp: ptr cint) =

  const
    transform_table = [[0,1,2,3],[0,2,1,3],[3,2,1,0],[3,1,2,0]]
    locations = [0,1,3,2]
    transforms = [1,0,0,3]

  var
    x, y, trans: int
    i = 30

  while i >= 0:
    let m = (n shr i) and 3
    let bits = transform_table[trans][locations[m]]
    x = (x shl 1) or ((bits shr 1) and 1)
    y = (y shl 1) or ((bits shr 0) and 1)
    trans = trans xor transforms[m]
    i -= 2

  xp[] = x
  yp[] = y
                      


proc setPoint(g: var Grapher, idx: int, val: uint8) =
  if idx < idxMax:
    var x, y: cint
    hilbert(idx, x.addr, y.addr)
    g.map[y*width + x] = val


proc setMap(g: var Grapher, p: pointer, size: csize_t, val: uint8) =
  let pu = cast[uint](p)
  # TODO: the mod is a hack, this needs to able to handle multiple heaps
  let rp = (pu - g.heapStart) mod memMax

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
      break

  while true:
    var recs: array[32, Record]
    let r = read(fd, recs.addr, recs.sizeof)

    if r > 0:
      let nrecs = r div Record.sizeof
      for i in 0..<nrecs:
        g.handle_rec(recs[i])
    elif r == 0:
      break;
    else:
      os.sleep(50)

    let t_now = epochTime()
    if t_now >= g.t_draw:
      g.drawMap()
      g.t_draw = t_now + 0.05

  log "done"


proc grapher*(fd: cint) =
  try:
    grapher2(fd)
  except:
    log "exception: " & getCurrentExceptionMsg()




