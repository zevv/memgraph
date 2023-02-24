
import std/[tables, strutils, posix, times, os, syncio, math]
import pkg/sdl2_nim/sdl
import pkg/npeg
import types

type

  Space = enum Hilbert, Linear

  Grapher = ref object
    # Configuration
    memMax: uint64
    videoPath: string
    argv: seq[string]
    space: Space
    # Runtime
    ffmpeg: File
    blockSize: int
    allocations: Table[uint64, csize_t]
    bytesAllocated: uint
    win: sdl.Window
    rend: sdl.Renderer
    tex: sdl.Texture
    texDark: sdl.Texture
    texAccum: sdl.Texture
    pixels: ptr UncheckedArray[uint32]
    t_draw: float
    t_exit: float


const
  width = 512
  height = 512
  idxMax = width * height
  fps = 30.0
  libmemgraph = readFile("libmemgraph.so")
  colorMap = [
    0xff00BDEB'u32, 0xff00BDEB'u32, 0xff0096FF'u32, 0xffE427FF'u32, 0xffFF00D5'u32,
    0xffFF4454'u32, 0xffDB7B00'u32, 0xff8F9C00'u32, 0xff00B300'u32, 0xff00C083'u32,
  ]


proc log(s: string) =
  stderr.write "\e[1;34m[memgraph ", s, "]\e[0m\n"


proc start_ffmpeg(fname: string): File =
  if fname != "":
    log "writing video to " & fname
    var cmd = "ffmpeg"
    cmd.add " -f rawvideo -vcodec rawvideo"
    cmd.add " -s " & $width & "x" & $height
    cmd.add " -pix_fmt bgra -r " & $fps
    cmd.add " -i - "
    cmd.add " -c:v libx264 -pix_fmt yuv420p -b:v 995328k "
    cmd.add " -y"
    cmd.add " -loglevel warning"
    cmd.add " " & fname
    #log cmd
    result = popen(cmd.cstring, "w")


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


template checkSdl(v: int) =
  doAssert(v == 0)


proc drawMap(g: Grapher) =

  # Unlock so the texture can be used
  g.tex.unlockTexture()
  
  # Render the allocation map to the accum tex
  checkSdl g.rend.setRenderTarget(g.texAccum)
  checkSdl g.rend.renderCopy(g.texDark, nil, nil);
  checkSdl g.rend.renderCopy(g.tex, nil, nil);
 
  # Copy the accum tex to the output render
  checkSdl g.rend.setRenderTarget(nil)
  checkSdl g.rend.renderCopy(g.texAccum, nil, nil);
  g.rend.renderPresent()
  
  # Send frame to ffmpeg encoder
  if not g.ffmpeg.isNil:
    var buf: array[width * height, uint32]
    checkSdl g.rend.setRenderTarget(g.texAccum)
    checkSdl g.rend.renderReadPixels(nil, PIXELFORMAT_BGRA32, cast[pointer](buf[0].addr), width * 4);
    let w = g.ffmpeg.writeBuffer(buf[0].addr, sizeof(buf));

  # Get a pointer to the pixel buffer
  var pixels: pointer
  var pitch: cint
  checkSdl g.tex.lockTexture(nil, pixels.addr, pitch.addr)
  g.pixels = cast[ptr UncheckedArray[uint32]](pixels)

  # Clear pixel buffer
  zeroMem(g.pixels, width * height * 4)


proc setPoint(g: Grapher, idx: int, val: uint32) =
  if idx < idxMax:
    var x, y: int
    if g.space == Hilbert:
      hilbert(idx, x, y)
      g.pixels[y*width + x] = val
    else:
      g.pixels[idx] = val


proc setMap(g: Grapher, p: uint64, size: csize_t, tid: int) =
  let 
    p = p mod g.memMax
    nblocks = size.int div g.blockSize
    idx = p.int div g.blockSize

  for i in 0..nBlocks:
    var color: uint32 = if tid != 0:
      colorMap[tid mod 10]
    else:
      0xff000000'u32
    g.setPoint(idx+i, color)


# Handle one alloc/free record

proc handle_rec(g: Grapher, rec: Record) =

  if rec.size > 0:
    # Handle alloc
    g.bytesAllocated += rec.size
    g.allocations[rec.p] = rec.size.csize_t
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


proc newGrapher(): Grapher =
  var g = Grapher()

  g.memMax = 64 * 1024 * 1024
  g.win = createWindow("memgraph", WindowPosUndefined, WindowPosUndefined, 512, 512, 0)
  g.rend = createRenderer(g.win, -1, sdl.RendererAccelerated and sdl.RendererPresentVsync)
  g.tex = createTexture(g.rend, PIXELFORMAT_BGRA32, TEXTUREACCESS_STREAMING, width, height)
  g.texDark = createTexture(g.rend, PIXELFORMAT_BGRA32, TEXTUREACCESS_TARGET, width, height)
  g.texAccum = createTexture(g.rend, PIXELFORMAT_BGRA32, TEXTUREACCESS_TARGET, width, height)
  
  checkSdl g.tex.setTextureBlendMode(BLENDMODE_BLEND)
  checkSdl g.texDark.setTextureBlendMode(BLENDMODE_BLEND)
  checkSdl g.texAccum.setTextureBlendMode(BLENDMODE_BLEND)
  checkSdl g.rend.setRenderDrawBlendMode(BLENDMODE_BLEND)

  checkSdl g.rend.setRenderTarget(g.texDark)
  checkSdl g.rend.setRenderDrawColor(0, 0, 0, 1)
  checkSdl g.rend.renderClear()
  checkSdl g.rend.setRenderTarget(nil)

  return g


# Grapher main loop: read records from hook and process

proc run(g: Grapher, fd: cint) =
  
  log "start"
  log "memMax: " & $(g.memMax div 1024) & " kB"

  discard fcntl(fd, F_SETFL, fcntl(0, F_GETFL) or O_NONBLOCK)
  signal(SIGPIPE, SIG_IGN)

  g.blockSize = (g.memMax div idxMax).int
  g.ffmpeg = start_ffmpeg(g.videoPath)

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
      os.sleep(1)

    else:
      os.sleep(1)

    let t_now = epochTime()

    if g.t_exit != 0 and t_now > g.t_exit:
      break

    if t_now >= g.t_draw:
      g.drawMap()
      g.t_draw = t_now + 1.0 / fps

  log "done"


proc usage() =
  echo "usage: memgraph [options] <cmd> [cmd options]"
  echo ""
  echo "options:"
  echo "  -h  --help         show help"
  echo "  -m  --memmax=MB    set max memory size [64]"
  echo "  -v  --video=FNAME  write video to FNAME. Must be .mp4"
  echo "  -s  --space=SPACE  set 2D space mapping [hilbert]"
  echo ""
  echo "available 2D space mappings:"
  echo "  hilbert, linear"


proc parseCmdLine(g: Grapher) =
  var g = g # Nim bug?
  let parser = peg parser:
    parser <- (*opt * cmd * !1) | E"Syntax error"
    sep <- '\x1f'
    eq <- ?{'=',':','\x1f'}
    opt <- (optMemMax | optVideo | optHelp | optSpace) * sep
    optMemMax <- ("-m" | "--memmax") * eq * (>+Digit | E"Not a number"):
      g.memMax = parseInt($1).uint64 * 1024 * 1024
    optVideo <- ("-v" | "--video") * eq * >+(1-sep):
      g.videoPath = $1
    optSpace <- ("-s" | "--space") * eq * (hilbert | linear | E"Unknown 2D space")
    hilbert <- "hilbert" | "h":
      g.space = Hilbert
    linear <- "linear" | "l":
      g.space = Linear
    optHelp <- ("-h" | "--help"):
      usage(); quit(0)
    cmd <- >(!"-" * +1):
      g.argv = split($1, '\x1f')

  try:
    discard parser.match(commandLineParams().join("\x1f"))
  except:
    echo "Error parsing command line: ", getCurrentExceptionMsg()
    echo ""
    usage()
    quit 1


proc main() =
 
  var g = newGrapher()
  g.parseCmdLine()

  # Put the injector library in a tmp file
  let tmpfile = "/tmp/libmemgraph.so." & $getuid()
  writeFile(tmpfile, libmemgraph)
  
  # Create the pipe for passing alloc info
  var fds: array[2, cint]
  discard pipe(fds)

  # Fork and exec child
  let pid = fork()
  if pid == 0:
    discard close(fds[0])
    var env = @[
      "LD_PRELOAD=" & tmpfile,
      "MEMGRAPH_FD_PIPE=" & $fds[1]
    ]
    for k, v in envPairs():
      env.add k & "=" & v
    let r = execvpe(g.argv[0], allocCstringArray g.argv, allocCstringArray env)
    echo "Error running ", g.argv[0], ": ", strerror(errno)
    exitnow(-1)

  # Run the grapher GUI
  discard close(fds[1])
  g.run(fds[0])
   
  # Cleanup
  removeFile(tmpfile)


main()

