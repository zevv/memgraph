
import std / [tables, strutils, posix, times, os, syncio]
import pkg / sdl2_nim / sdl
import types

const
  width = 512
  height = 512
  idxMax = width * height
  blockSize = 8192
  memMax = idxMax * blockSize
  fps = 20.0
  interval = 1.0 / fps


type

  Grapher = object
    allocations: Table[pointer, csize_t]
    heapStart: uint
    bytesAllocated: uint
    win: sdl.Window
    rend: sdl.Renderer
    tex: sdl.Texture
    pixels: ptr UncheckedArray[uint32]
    t_draw: float
    t_exit: float
    ffmpeg: File


proc start_ffmpeg(): File =
  let fname = getEnv("MEMGRAPH_MP4")
  if fname != "":
    var cmd = "ffmpeg"
    cmd.add " -f rawvideo -vcodec rawvideo"
    cmd.add " -s " & $width & "x" & $height
    cmd.add " -pix_fmt rgba -r " & $fps
    cmd.add " -i - "
    cmd.add " -an -c:v libx264 -pix_fmt yuv420p -b:v 995328k "
    cmd.add " -y"
    cmd.add " -loglevel warning"
    cmd.add " " & fname
    log cmd
    result = popen(cmd.cstring, "w")


proc log(s: string) =
  stderr.write "\e[1;34m[memgraph ", s, "]\e[0m\n"


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
                      


proc setPoint(g: var Grapher, idx: int, val: uint32) =
  if idx < idxMax:
    var x, y: cint
    when true:
      hilbert(idx, x.addr, y.addr)
      g.pixels[y*width + x] = val
    else:
      g.pixels[idx] = val


proc setMap(g: var Grapher, p: pointer, size: csize_t, val: uint8) =
  let pRel = cast[uint](p) - g.heapStart

  if not g.pixels.isNil and pRel < memMax:
    let nblocks = size.int div blockSize
    let idx = pRel.int div blockSize

    for i in 0..nBlocks:
      if idx >= 0 and idx < idxMax:
        if val == 0:
          g.setPoint(idx+i, 0x222222)
        else:
          g.setPoint(idx+i, 0xcccccc)



proc drawMap(g: var Grapher) =

  g.tex.unlockTexture()

  discard g.rend.renderCopy(g.tex, nil, nil);
  g.rend.renderPresent

  var pixels: pointer
  var pitch: cint
  discard g.tex.lockTexture(nil, pixels.addr, pitch.addr)

  g.pixels = cast[ptr UncheckedArray[uint32]](pixels)
  log $(g.bytesAllocated div 1024) & " kB in " & $g.allocations.len & " blocks"

  if not g.ffmpeg.isNil:
    let w = g.ffmpeg.writeBuffer(cast[pointer](g.pixels), 4 * width * height)



# Handle one alloc/free record

proc handle_rec(g: var Grapher, rec: Record) =

  #echo rec.p.repr, " ", rec.size

  if g.heapStart == 0:
    g.heapStart = cast[uint](rec.p)

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
    else:
      log "unknown " & rec.p.repr



# Grapher main loop: read records from hook and process

proc grapher(fd: cint) =

  discard fcntl(fd, F_SETFL, fcntl(0, F_GETFL) and not O_NONBLOCK)
  
  log "start"
  log "memMax: " & $(memMax div 1024) & " kB"

  signal(SIGPIPE, SIG_IGN)

  var g = Grapher()

  g.win = createWindow("memgraph", WindowPosUndefined, WindowPosUndefined, 1024, 1024, 0)
  g.rend = createRenderer(g.win, -1, sdl.RendererAccelerated and sdl.RendererPresentVsync)
  g.tex = createTexture(g.rend, PIXELFORMAT_BGRA32, TEXTUREACCESS_STREAMING, width, height)
  g.ffmpeg = start_ffmpeg()

  while true:
    var recs: array[256, Record]
    let r = read(fd, recs.addr, recs.sizeof)

    if r > 0:
      let nrecs = r div Record.sizeof
      for i in 0..<nrecs:
        g.handle_rec(recs[i])
    elif r == 0:
      if g.t_exit == 0.0:
        g.t_exit = epochTime() + 1
      os.sleep(int(interval * 1000))
    else:
      os.sleep(int(interval * 1000))

    let t_now = epochTime()

    if g.t_exit != 0 and t_now > g.t_exit:
      break

    if t_now >= g.t_draw:
      g.drawMap()
      g.t_draw = t_now + interval

  log "done"


grapher(0)
