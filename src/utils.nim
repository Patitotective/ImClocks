import std/[strutils, strformat, enumutils, typetraits, macros, os]

import chroma
import niprefs
import stopwatch
import stb_image/read as stbi
import nimgl/[imgui, glfw, opengl]

export enumutils

type
  SwState* = enum
    Running
    Stopped
    Paused

  App* = ref object
    win*: GLFWWindow
    font*: ptr ImFont
    bigFont*: ptr ImFont
    prefs*: Prefs
    config*: PObjectType # Prefs table
    cache*: PObjectType # Settings cache

    # Variables
    sw*: Stopwatch
    swState*: SwState
    startBtnText*: string
    lapBtnText*: string

    time*: array[3, int32] # For the timer
    timeMs*: int # time in milliseconds for countback
    timer*: Stopwatch
    timerState*: SwState

    currentZone*: int32
    filter*: ImGuiTextFilter

  SettingTypes* = enum
    Input # Input text
    Check # Checkbox
    Slider # Int slider
    FSlider # Float slider
    Spin # Int spin
    FSpin # Float spin
    Combo
    Radio # Radio button
    Color3 # Color edit RGB
    Color4 # Color edit RGBA
    Section

  ImageData* = tuple[image: seq[byte], width, height: int]

# To be able to print large holey enums
macro enumFullRange*(a: typed): untyped =
  newNimNode(nnkBracket).add(a.getType[1][1..^1])

iterator items*(T: typedesc[HoleyEnum]): T =
  for x in T.enumFullRange:
    yield x

proc getEnumValues*[T: enum](): seq[string] = 
  for i in T:
    result.add $i

proc parseEnum*[T: enum](node: PrefsNode): T = 
  case node.kind:
  of PInt:
    result = T(node.getInt())
  of PString:
    try:
      result = parseEnum[T](node.getString().capitalizeAscii())
    except:
      raise newException(ValueError, &"Invalid enum value {node.getString()} for {$T}. Valid values are {$getEnumValues[T]()}")
  else:
    raise newException(ValueError, &"Invalid kind {node.kind} for an enum. Valid kinds are PInt or PString")

proc makeFlags*[T: enum](flags: varargs[T]): T =
  ## Mix multiple flags of a specific enum
  var res = 0
  for x in flags:
    res = res or int(x)

  result = T res

proc getFlags*[T: enum](node: PrefsNode): T = 
  ## Similar to parseEnum but this one mixes multiple enum values if node.kind == PSeq
  case node.kind:
  of PString, PInt:
    result = parseEnum[T](node)
  of PSeq:
    var flags: seq[T]
    for i in node.getSeq():
      flags.add parseEnum[T](i)

    result = makeFlags(flags)
  else:
    raise newException(ValueError, "Invalid kind {node.kind} for {$T} enum. Valid kinds are PInt, PString or PSeq") 

proc parseColor3*(node: PrefsNode): array[3, float32] = 
  case node.kind
  of PString:
    let color = node.getString().parseHtmlColor()
    result[0] = color.r
    result[1] = color.g
    result[2] = color.b 
  of PSeq:
    result[0] = node[0].getFloat()
    result[1] = node[1].getFloat()
    result[2] = node[2].getFloat()
  else:
    raise newException(ValueError, &"Invalid color RGB {node}")

proc parseColor4*(node: PrefsNode): array[4, float32] = 
  case node.kind
  of PString:
    let color = node.getString().replace("#").parseHexAlpha()
    result[0] = color.r
    result[1] = color.g
    result[2] = color.b 
    result[3] = color.a
  of PSeq:
    result[0] = node[0].getFloat()
    result[1] = node[1].getFloat()
    result[2] = node[2].getFloat()
    result[3] = node[3].getFloat()
  else:
    raise newException(ValueError, &"Invalid color RGBA {node}")

proc igVec2*(x, y: float32): ImVec2 = ImVec2(x: x, y: y)

proc igVec4*(x, y, z, w: float32): ImVec4 = ImVec4(x: x, y: y, z: z, w: w)

proc igVec4*(color: Color): ImVec4 = ImVec4(x: color.r, y: color.g, z: color.b, w: color.a)

proc initGLFWImage*(data: ImageData): GLFWImage = 
  result = GLFWImage(pixels: cast[ptr cuchar](data.image[0].unsafeAddr), width: int32 data.width, height: int32 data.height)

proc readImage*(path: string): ImageData = 
  var channels: int
  result.image = stbi.load(path, result.width, result.height, channels, stbi.Default)

proc loadTextureFromData*(data: var ImageData, outTexture: var GLuint) =
    # Create a OpenGL texture identifier
    glGenTextures(1, outTexture.addr)
    glBindTexture(GL_TEXTURE_2D, outTexture)

    # Setup filtering parameters for display
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE.GLint) # This is required on WebGL for non power-of-two textures
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE.GLint) # Same

    # Upload pixels into texture
    # if defined(GL_UNPACK_ROW_LENGTH) && !defined(__EMSCRIPTEN__)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)

    glTexImage2D(GL_TEXTURE_2D, GLint 0, GL_RGBA.GLint, GLsizei data.width, GLsizei data.height, GLint 0, GL_RGBA, GL_UNSIGNED_BYTE, data.image[0].addr)

proc igHelpMarker*(text: string) = 
  igTextDisabled("(?)")
  if igIsItemHovered():
    igBeginTooltip()
    igPushTextWrapPos(igGetFontSize() * 35.0)
    igTextUnformatted(text)
    igPopTextWrapPos()
    igEndTooltip()

proc newImFontConfig*(mergeMode = false): ImFontConfig =
  result.fontDataOwnedByAtlas = true
  result.fontNo = 0
  result.oversampleH = 3
  result.oversampleV = 1
  result.pixelSnapH = true
  result.glyphMaxAdvanceX = float.high
  result.rasterizerMultiply = 1.0
  result.mergeMode = mergeMode

proc formatTime*(ms: int64, includeMs: bool = true): string = 
  let
    days = ms div (1000 * 60 * 60 * 24)
    hours = (ms div (1000 * 60 * 60)) mod 24
    minutes = (ms div (1000 * 60)) mod 60
    seconds = (ms div 1000) mod 60
    milliseconds = (ms div 10) mod 100 # Rest of milliseconds

  if days > 0:
    result = &"{days:02} {hours:02}:{minutes:02}:{seconds:02}"
  else:
    result = &"{hours:02}:{minutes:02}:{seconds:02}"

  if includeMs:
    result.add &".{milliseconds:02}"

proc centerCursorX*(width: float32, align: float = 0.5f) = 
  var avail: ImVec2

  igGetContentRegionAvailNonUDT(avail.addr)
  
  let off = (avail.x - width) * align
  
  if off > 0:
    igSetCursorPosX(igGetCursorPosX() + off)

proc centerCursorY*(height: float32, align: float = 0.5f) = 
  var avail: ImVec2

  igGetContentRegionAvailNonUDT(avail.addr)
  
  let off = (avail.y - height) * align
  
  if off > 0:
    igSetCursorPosY(igGetCursorPosY() + off)

proc centerCursor*(size: ImVec2, alignX: float = 0.5f, alignY: float = 0.5f) = 
  centerCursorX(size.x, alignX)
  centerCursorY(size.y, alignY)

proc igCalcTextSize*(text: cstring, text_end: cstring = nil, hide_text_after_double_hash: bool = false, wrap_width: float32 = -1.0'f32): ImVec2 = 
  igCalcTextSizeNonUDT(result.addr, text, text_end, hide_text_after_double_hash, wrap_width)

proc myParseInt*(s: string): int = 
  var s = s.replace("\x00", "")

  if s.len == 0: return 0

  try:
    if s[0] == '-':
      result = -s[1..s.high].parseInt()
    else:
      if '-' in s:
        s = s.replace("-", "")
      result = s.parseInt()
  except ValueError:
    result = 0  

proc vInputInt*(label: cstring, val: var int32, step: int32 = 1, min: int32 = 0, max: int32 = 1024) = 
  var
    buf = intToStr(val, ($max).len)
    incBtnDisabled = false
    decBtnDisabled = false
  
  let width = igCalcTextSize($max).x + (igGetStyle().framePadding.x * 2)

  igBeginGroup()

  if val >= max:
    incBtnDisabled = true
    igPushItemFlag(ImGuiItemFlags.Disabled, true)
    igPushStyleVar(ImGuiStyleVar.Alpha, igGetStyle().alpha * 0.6)

  if igButton(&"+##+{label}", igVec2(width, 0)):
    if val < max:
      inc val, step

  if incBtnDisabled:
    igPopStyleVar()
    igPopItemFlag()

  igSetNextItemWidth(width)

  if igInputText(label, buf, uint(($max).len + 1), makeFlags(CharsDecimal, AutoSelectAll)):
    val = myParseInt(buf).int32
    if val < min:
      val = min

  if val <= min:
    decBtnDisabled = true
    igPushItemFlag(ImGuiItemFlags.Disabled, true)
    igPushStyleVar(ImGuiStyleVar.Alpha, igGetStyle().alpha * 0.6)

  if igButton(&"-##-{label}", igVec2(width, 0)):
    if val > min:
      dec val, step

  if decBtnDisabled:
    igPopStyleVar()
    igPopItemFlag()
  
  igEndGroup()

proc deleted*[T](list: seq[T], i: Natural): seq[T] = 
  result = list
  result.delete(i)
