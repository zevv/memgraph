
import std/[tables, strutils, posix, times, os, syncio, math, posix]
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
    debug: bool
    # Runtime
    ffmpeg: File
    blockSize: int
    allocations: Table[uint64, csize_t]
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


proc log(g: Grapher, s: string) =
  if g.debug:
    stderr.write "\e[1;34m[memgraph ", s, "]\e[0m\n"

proc wrn(g: Grapher, s: string) =
  stderr.write "\e[1;31m[memgraph ", s, "]\e[0m\n"


proc start_ffmpeg(g: Grapher, fname: string) =
  if fname != "":
    g.log "writing video to " & fname
    var cmd = "ffmpeg"
    cmd.add " -f rawvideo -vcodec rawvideo"
    cmd.add " -s " & $width & "x" & $height
    cmd.add " -pix_fmt bgra -r " & $fps
    cmd.add " -i - "
    cmd.add " -c:v libx264 -pix_fmt yuv420p -b:v 995328k "
    cmd.add " -y"
    cmd.add " -loglevel warning"
    cmd.add " " & fname
    g.ffmpeg = popen(cmd.cstring, "w")


proc hilbert(n: int): tuple[x, y: int] =

  const
    transform_table = [[0,1,2,3],[0,2,1,3],[3,2,1,0],[3,1,2,0]]
    locations = [0,1,3,2]
    transforms = [1,0,0,3]

  var x = 0
  var y = 0
  var trans = 0
  var i = 16

  while i >= 0:
    let m = (n shr i) and 3
    let bits = transform_table[trans][locations[m]]
    x = (x shl 1) or ((bits shr 1) and 1)
    y = (y shl 1) or ((bits shr 0) and 1)
    trans = trans xor transforms[m]
    i -= 2
  (x, y)


proc calcHilbertMap(): seq[int] =
  for idx in 0..<width*height:
    let (x, y) = hilbert(idx)
    result.add y*width + x


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


proc setMap(g: Grapher, p: uint64, size: csize_t, tid: int) =

  let p = p mod g.memMax
  let nblocks = size.int div g.blockSize
  var idx = p.int div g.blockSize
  let color = if tid != 0: colorMap[tid mod 10] else: 0xff000000'u32
  const hilbertMap = calcHilbertMap()
    
  if g.space == Hilbert:
    for i in 0..nBlocks:
      if idx < idxMax:
        let idx2 = hilbertMap[idx]
        g.pixels[idx2] = color
        inc idx
  else:
    for i in 0..nBlocks:
      if idx < idxMax:
        g.pixels[idx] = color
        inc idx


# Handle one alloc/free record

proc handle_rec(g: Grapher, rec: Record) =

  if rec.size > 0:
    # Handle alloc
    g.allocations[rec.p] = rec.size.csize_t
    g.setMap(rec.p, rec.size, rec.tid)

  else:
    # Handle free
    let size = g.allocations.getOrDefault(rec.p)
    g.setMap(rec.p, size, 0)
    g.allocations.del rec.p


proc newGrapher(): Grapher =
  Grapher(memmax: 64 * 1024 * 1024)


proc initGui(g: Grapher) =
  g.win = createWindow("memgraph", WindowPosUndefined, WindowPosUndefined, width, height, 0)
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


# Grapher main loop: read records from hook and process

proc run(g: Grapher, fd: cint) =
  
  g.log "memMax: " & $(g.memMax div 1024) & " kB"

  discard fcntl(fd, F_SETFL, fcntl(0, F_GETFL) or O_NONBLOCK)
  signal(SIGPIPE, SIG_IGN)

  g.blockSize = (g.memMax div idxMax).int
  g.start_ffmpeg(g.videoPath)

  g.drawMap()

  g.t_draw = epochTime()

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
      g.t_draw += 1.0 / fps

  var blocks = g.allocations.len
  var bytes: csize_t
  for _, b in g.allocations: bytes += b
  g.log "done, " & $bytes & " still allocated in " & $blocks & " blocks"


proc usage() =
  echo "usage: memgraph [options] <cmd> [cmd options]"
  echo ""
  echo "options:"
  echo "  -d  --debug        enable debug logging"
  echo "  -h  --help         show help"
  echo "  -m  --memmax=MB    set max memory size [64]"
  echo "  -v  --video=FNAME  write video to FNAME. Must be .mp4"
  echo "  -s  --space=SPACE  set 2D space mapping (hilbert,linear) [hilbert]"


proc parseCmdLine(g: Grapher) =
  var g = g # Nim bug?
  let parser = peg parser:
    parser <- (*opt * cmd * !1)
    sep <- '\x1f'
    eq <- ?{'=',':','\x1f'}
    opt <- (optDebug | optMemMax | optVideo | optHelp | optSpace) * sep
    optDebug <- ("-d" | "--debug"):
      g.debug = true
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
    if g.argv.len == 0:
      usage()
      quit 0
  except:
    echo "Error parsing command line: ", getCurrentExceptionMsg()
    echo ""
    usage()
    quit 1


proc main() =
 
  var g = newGrapher()
  g.parseCmdLine()
  g.initGui()

  # Put the injector library in a tmp file
  var soDir = getenv("XDG_RUNTIME_DIR")
  if soDir == "": soDir = "/tmp"
  let soFile = soDir & "/libmemgraph.so." & $getuid()
  writeFile(soFile, libmemgraph)
  g.log "injecting " & soFile

  # Ensure the shlib is usable at this place
  let p = dlopen(soFile, RTLD_NOW)
  if p.isNil:
    g.wrn $dlerror()
    quit 1
  else:
    discard dlclose(p)
  
  # Create the pipe for passing alloc info
  var fds: array[2, cint]
  discard pipe(fds)

  # Fork and exec child
  g.log "starting subprocess: " & g.argv.join(" ")
  let pid = fork()
  if pid == 0:
    discard close(fds[0])
    putEnv("LD_PRELOAD", soFile)
    putEnv("MEMGRAPH_FD_PIPE", $fds[1])
    let r = execvp(g.argv[0], allocCstringArray g.argv)
    echo "Error running ", g.argv[0], ": ", strerror(errno)
    exitnow(-1)

  # Run the grapher GUI
  discard close(fds[1])
  g.run(fds[0])
   
  # Cleanup
  removeFile(soFile)


main()

