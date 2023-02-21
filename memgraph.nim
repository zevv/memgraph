
import std / [tables, strutils, posix, times, os, syncio]
import pkg / sdl2_nim / sdl
import types

type

  Grapher = object
    allocations: Table[pointer, csize_t]
    bytesAllocated: uint
    win: sdl.Window
    rend: sdl.Renderer
    tex: sdl.Texture
    pixels: ptr UncheckedArray[uint32]
    t_draw: float
    t_exit: float
    ffmpeg: File


const
  width = 512
  height = 512
  idxMax = width * height
  fps = 30.0
  interval = 1.0 / fps
  colorMap = [
    0x00BDEB, 0x00BDEB, 0x0096FF, 0xE427FF, 0xFF00D5,
    0xFF4454, 0xDB7B00, 0x8F9C00, 0x00B300, 0x00C083,
  ]


var
  memMaxDefault = "1024"
  memMax: uint = (getEnv("MEMGRAPH_MEM_MAX", memMaxDefault).parseInt() * 1024 * 1024).uint
  blockSize = (memMax div idxMax).int


proc start_ffmpeg(): File =
  let fname = getEnv("MEMGRAPH_MP4")
  if fname != "":
    var cmd = "ffmpeg"
    cmd.add " -f rawvideo -vcodec rawvideo"
    cmd.add " -s " & $width & "x" & $height
    cmd.add " -pix_fmt bgra -r " & $fps
    cmd.add " -i - "
    #cmd.add " -i http://zevv.nl/div/.old/memgraph.mp3"
    cmd.add " -c:v libx264 -pix_fmt yuv420p -b:v 995328k "
    #cmd.add " -c:a copy"
    #cmd.add " -shortest"
    #cmd.add " -map 0:0 -map 1:0"
    cmd.add " -y"
    cmd.add " -loglevel warning"
    cmd.add " " & fname
    log cmd
    result = popen(cmd.cstring, "w")


proc log(s: string) =
  stderr.write "\e[1;34m[memgraph ", s, "]\e[0m\n"


proc hilbert(n: int, x, y: var int) =

  const
    transform_table = [[0,1,2,3],[0,2,1,3],[3,2,1,0],[3,1,2,0]]
    locations = [0,1,3,2]
    transforms = [1,0,0,3]

  x = 0
  y = 0
  var trans = 0
  var i = 16

  while i >= 0:
    let m = (n shr i) and 3
    let bits = transform_table[trans][locations[m]]
    x = (x shl 1) or ((bits shr 1) and 1)
    y = (y shl 1) or ((bits shr 0) and 1)
    trans = trans xor transforms[m]
    i -= 2


proc drawMap(g: var Grapher) =

  g.tex.unlockTexture()

  discard g.rend.renderCopy(g.tex, nil, nil);
  g.rend.renderPresent

  var pixels: pointer
  var pitch: cint
  discard g.tex.lockTexture(nil, pixels.addr, pitch.addr)

  g.pixels = cast[ptr UncheckedArray[uint32]](pixels)
  #log $(g.bytesAllocated div 1024) & " kB in " & $g.allocations.len & " blocks"

  if not g.ffmpeg.isNil:
    let w = g.ffmpeg.writeBuffer(cast[pointer](g.pixels), 4 * width * height)


proc setPoint(g: var Grapher, idx: int, val: uint32) =
  if idx < idxMax:
    var x, y: int
    when true:
      hilbert(idx, x, y)
      g.pixels[y*width + x] = val
    else:
      g.pixels[idx] = val


proc setMap(g: var Grapher, p: pointer, size: csize_t, val: int) =
  let pRel = cast[uint](p) mod memMax

  if not g.pixels.isNil and pRel < memMax:
    let nblocks = size.int div blockSize
    let idx = pRel.int div blockSize

    for i in 0..nBlocks:
      if idx >= 0 and idx < idxMax:
        if val == 0:
          g.setPoint(idx+i, 0x222222)
        else:
          let color = colorMap[val mod 10]
          g.setPoint(idx+i, color.uint32)


# Handle one alloc/free record

proc handle_rec(g: var Grapher, rec: Record) =

  if rec.size > 0:
    # Handle alloc
    g.bytesAllocated += rec.size
    g.allocations[rec.p] = rec.size
    g.setMap(rec.p, rec.size, rec.tid)

  else:
    # Handle free
    var size: int
    if rec.p in g.allocations:
      let size = g.allocations[rec.p]
      g.bytesAllocated -= size
      g.setMap(rec.p, size, 0)
      g.allocations.del rec.p
    else:
      log "free unknown addr " & rec.p.repr


# Grapher main loop: read records from hook and process

proc grapher(fd: cint) =
  
  log "start"
  log "memMax: " & $(memMax div 1024) & " kB"

  discard fcntl(fd, F_SETFL, fcntl(0, F_GETFL) and not O_NONBLOCK)
  signal(SIGPIPE, SIG_IGN)

  var g = Grapher()

  g.win = createWindow("memgraph", WindowPosUndefined, WindowPosUndefined, 1024, 1024, 0)
  g.rend = createRenderer(g.win, -1, sdl.RendererAccelerated and sdl.RendererPresentVsync)
  g.tex = createTexture(g.rend, PIXELFORMAT_BGRA32, TEXTUREACCESS_STREAMING, width, height)
  g.ffmpeg = start_ffmpeg()

  g.drawMap()

  while true:
    var recs: array[2048, Record]
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

