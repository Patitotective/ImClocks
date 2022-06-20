import std/[typetraits, strformat, enumutils, monotimes, strutils, strscans, macros, times, os]
import chroma
import niprefs
import stopwatch
import tinydialogs
import stb_image/read as stbi
import nimgl/[imgui, glfw, opengl]

import icons, sound
import ../resourcesdata

export enumutils

type
  SwState* = enum
    Running
    Stopped
    Paused

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
    ChooseFile
    Section

  ImageData* = tuple[image: seq[byte], width, height: int]

  App* = object
    win*: GLFWWindow
    font*, bigFont*: ptr ImFont
    prefs*: Prefs
    cache*: TomlValueRef # Settings cache
    config*: TomlValueRef # Prefs table

    # Variables
    sw*: Stopwatch
    swState*: SwState
    lapBtnText*: string
    startBtnText*: string

    timeMs*: int # time in milliseconds for countback
    timer*: Stopwatch
    playAlarm*: bool
    alarmSound*: Sound
    alarmVoice*: Voice
    timerState*: SwState
    time*: array[3, int32] # When selecting the time
    monotimeStart*: Monotime

    timezones*: seq[string]
    currentZone*: int32
    zoneBuffer*: string

proc `+`*(vec1, vec2: ImVec2): ImVec2 = 
  ImVec2(x: vec1.x + vec2.x, y: vec1.y + vec2.y)

proc `-`*(vec1, vec2: ImVec2): ImVec2 = 
  ImVec2(x: vec1.x - vec2.x, y: vec1.y - vec2.y)

proc `*`*(vec1, vec2: ImVec2): ImVec2 = 
  ImVec2(x: vec1.x * vec2.x, y: vec1.y * vec2.y)

proc `/`*(vec1, vec2: ImVec2): ImVec2 = 
  ImVec2(x: vec1.x / vec2.x, y: vec1.y / vec2.y)

proc `+`*(vec: ImVec2, val: float32): ImVec2 = 
  ImVec2(x: vec.x + val, y: vec.y + val)

proc `-`*(vec: ImVec2, val: float32): ImVec2 = 
  ImVec2(x: vec.x - val, y: vec.y - val)

proc `*`*(vec: ImVec2, val: float32): ImVec2 = 
  ImVec2(x: vec.x * val, y: vec.y * val)

proc `/`*(vec: ImVec2, val: float32): ImVec2 = 
  ImVec2(x: vec.x / val, y: vec.y / val)

proc `+=`*(vec1: var ImVec2, vec2: ImVec2) = 
  vec1.x += vec2.x
  vec1.y += vec2.y

proc `-=`*(vec1: var ImVec2, vec2: ImVec2) = 
  vec1.x -= vec2.x
  vec1.y -= vec2.y

proc `*=`*(vec1: var ImVec2, vec2: ImVec2) = 
  vec1.x *= vec2.x
  vec1.y *= vec2.y

proc `/=`*(vec1: var ImVec2, vec2: ImVec2) = 
  vec1.x /= vec2.x
  vec1.y /= vec2.y

proc igVec2*(x, y: float32): ImVec2 = ImVec2(x: x, y: y)

proc igVec4*(x, y, z, w: float32): ImVec4 = ImVec4(x: x, y: y, z: z, w: w)

proc igVec4*(color: Color): ImVec4 = ImVec4(x: color.r, y: color.g, z: color.b, w: color.a)

proc igHSV*(h, s, v: float32, a: float32 = 1f): ImColor = 
  result.addr.hSVNonUDT(h, s, v, a)

proc igGetContentRegionAvail*(): ImVec2 = 
  igGetContentRegionAvailNonUDT(result.addr)

proc igGetWindowPos*(): ImVec2 = 
  igGetWindowPosNonUDT(result.addr)

proc igCalcTextSize*(text: cstring, text_end: cstring = nil, hide_text_after_double_hash: bool = false, wrap_width: float32 = -1.0'f32): ImVec2 = 
  igCalcTextSizeNonUDT(result.addr, text, text_end, hide_text_after_double_hash, wrap_width)

proc igCalcFrameSize*(text: string): ImVec2 = 
  igCalcTextSize(cstring text) + (igGetStyle().framePadding * 2)

proc igColorConvertU32ToFloat4*(color: uint32): ImVec4 = 
  igColorConvertU32ToFloat4NonUDT(result.addr, color)

proc igGetMouseDragDelta*(button = 0.ImGuiMouseButton, lock_threshold = -1f): ImVec2 = 
  igGetMouseDragDeltaNonUDT(result.addr, button, lock_threshold)

proc getCenter*(self: ptr ImGuiViewport): ImVec2 = 
  getCenterNonUDT(result.addr, self)

proc igCenterCursorX*(width: float32, align: float = 0.5f, avail = igGetContentRegionAvail().x) = 
  let off = (avail - width) * align
  
  if off > 0:
    igSetCursorPosX(igGetCursorPosX() + off)

proc igCenterCursorY*(height: float32, align: float = 0.5f, avail = igGetContentRegionAvail().y) = 
  let off = (avail - height) * align
  
  if off > 0:
    igSetCursorPosY(igGetCursorPosY() + off)

proc igCenterCursor*(size: ImVec2, alignX: float = 0.5f, alignY: float = 0.5f, avail = igGetContentRegionAvail()) = 
  igCenterCursorX(size.x, alignX, avail.x)
  igCenterCursorY(size.y, alignY, avail.y)

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

proc igAddFontFromMemoryTTF*(self: ptr ImFontAtlas, data: string, size_pixels: float32, font_cfg: ptr ImFontConfig = nil, glyph_ranges: ptr ImWchar = nil): ptr ImFont {.discardable.} = 
  let igFontStr = cast[cstring](igMemAlloc(data.len.uint))
  igFontStr[0].unsafeAddr.copyMem(data[0].unsafeAddr, data.len)
  result = self.addFontFromMemoryTTF(igFontStr, data.len.int32, sizePixels, font_cfg, glyph_ranges)

# To be able to print large holey enums
macro enumFullRange*(a: typed): untyped =
  newNimNode(nnkBracket).add(a.getType[1][1..^1])

iterator items*(T: typedesc[HoleyEnum]): T =
  for x in T.enumFullRange:
    yield x

proc getEnumValues*[T: enum](): seq[string] = 
  for i in T:
    result.add $i

proc parseEnum*[T: enum](node: TomlValueRef): T = 
  assert node.kind == TomlKind.String

  try:
    result = parseEnum[T](node.getString().capitalizeAscii())
  except:
    raise newException(ValueError, &"Invalid enum value {node.getString()} for {$T}. Valid values are {$getEnumValues[T]()}")

proc makeFlags*[T: enum](flags: varargs[T]): T =
  ## Mix multiple flags of a specific enum
  var res = 0
  for x in flags:
    res = res or int(x)

  result = T res

proc getFlags*[T: enum](node: TomlValueRef): T = 
  ## Similar to parseEnum but this one mixes multiple enum values if node.kind == PSeq
  case node.kind:
  of TomlKind.String, TomlKind.Int:
    result = parseEnum[T](node)
  of TomlKind.Array:
    var flags: seq[T]
    for i in node.getArray():
      flags.add parseEnum[T](i)

    result = makeFlags(flags)
  else:
    raise newException(ValueError, "Invalid kind {node.kind} for {$T} enum. Valid kinds are PInt, PString or PSeq") 

proc parseColor3*(node: TomlValueRef): array[3, float32] = 
  assert not node.isNil and node.kind in {TomlKind.String, TomlKind.Array}

  case node.kind
  of TomlKind.String:
    let color = node.getString().parseHtmlColor()
    result[0] = color.r
    result[1] = color.g
    result[2] = color.b 
  of TomlKind.Array:
    assert node.len == 3
    result[0] = node[0].getFloat()
    result[1] = node[1].getFloat()
    result[2] = node[2].getFloat()
  else:
    raise newException(ValueError, &"Invalid color RGB {node}")

proc parseColor4*(node: TomlValueRef): array[4, float32] = 
  assert not node.isNil and node.kind in {TomlKind.String, TomlKind.Array}

  case node.kind
  of TomlKind.String:
    let color = node.getString().parseHtmlColor()
    result[0] = color.r
    result[1] = color.g
    result[2] = color.b 
    result[3] = color.a
  of TomlKind.Array:
    assert node.len == 4
    result[0] = node[0].getFloat()
    result[1] = node[1].getFloat()
    result[2] = node[2].getFloat()
    result[3] = node[3].getFloat()
  else:
    raise newException(ValueError, &"Invalid color RGBA {node}")

proc initGLFWImage*(data: ImageData): GLFWImage = 
  result = GLFWImage(pixels: cast[ptr cuchar](data.image[0].unsafeAddr), width: int32 data.width, height: int32 data.height)

proc readImageFromMemory*(data: string): ImageData = 
  var channels: int
  result.image = stbi.loadFromMemory(cast[seq[byte]](data), result.width, result.height, channels, stbi.Default)

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

proc openURL*(url: string) = 
  when defined(MacOS) or defined(MacOSX):
    discard execShellCmd("open " & url)
  elif defined(Windows):
    discard execShellCmd("start " & url)
  else:
    discard execShellCmd("xdg-open " & url)

proc removeInside*(text: string, open, close: char): tuple[text: string, inside: string] = 
  ## Remove the characters inside open..close from text, return text and the removed characters
  runnableExamples:
    assert "Hello<World>".removeInside('<', '>') == ("Hello", "World")
  var inside = false
  for i in text:
    if i == open:
      inside = true
      continue

    if not inside:
      result.text.add i

    if i == close:
      inside = false

    if inside:
      result.inside.add i

proc initSettings*(app: var App, settings: TomlValueRef, parent = "", overwrite = false) = 
  ## Init the settings defined in config["settings"] and the cache.
  for name, data in settings: 
    let settingType = parseEnum[SettingTypes](data["type"])
    if settingType == Section:
      app.initSettings(data["content"], parent = name, overwrite)
    
    elif parent.len > 0:

      if parent notin app.prefs or overwrite:
        app.prefs[parent] = newTTable()
      if name notin app.prefs[parent] or overwrite:
        app.prefs{parent, name} = data["default"]

      app.cache{parent, name} = app.prefs{parent, name}
    else:
      if name notin app.prefs or overwrite:
        app.prefs[name] = data["default"]
      
      app.cache[name] = app.prefs[name]

proc pushString*(str: var string, val: string) = 
  if val.len < str.len:
    str[0..val.len] = val & '\0'
  else:
    str[0..str.high] = val[0..str.high]

proc newString*(length: int, default: string): string = 
  result = newString(length)
  result.pushString(default)

proc cleanString*(str: string): string = 
  if '\0' in str:
    str[0..<str.find('\0')].strip()
  else:
    str.strip()

proc formatTime*(ms: int64, includeMs: bool = true): string = 
  var
    negative = false
    ms = ms

  if ms < 0:
    negative = true
    ms *= -1
  
  let
    days = ms div (1000 * 60 * 60 * 24)
    hours = (ms div (1000 * 60 * 60)) mod 24
    minutes = (ms div (1000 * 60)) mod 60
    seconds = (ms div 1000) mod 60
    milliseconds = (ms div 10) mod 100 # Rest of milliseconds

  if negative:
    result.add "-"

  if days > 0:
    result.add &"{days:02} {hours:02}:{minutes:02}:{seconds:02}"
  else:
    result.add &"{hours:02}:{minutes:02}:{seconds:02}"

  if includeMs:
    result.add &".{milliseconds:02}"

proc vInputInt*(label: cstring, val: var int32, step: int32 = 1, min: int32 = 0, max: int32 = 1024) = 
  let width = igCalcTextSize(cstring $max).x + (igGetStyle().framePadding.x * 2)
  
  var buf = intToStr(val, ($max).len)
  var decBtnDisabled, incBtnDisabled = false

  igBeginGroup()

  if val >= max:
    incBtnDisabled = true
    igBeginDisabled()

  if igButton(cstring &"{FA_Plus}##p{label}", igVec2(width, 0)):
    if val < max:
      inc val, step

  if incBtnDisabled:
    igEndDisabled()

  igSetNextItemWidth(width)

  if igInputText(label, cstring buf, uint(($max).len + 1), makeFlags(CharsDecimal, AutoSelectAll)):
    let (ok, num) = scanTuple(buf, "$i")
    if ok:
      if num < min:
        val = min
      elif num > max:
        val = max
      else:
        val = int32 num

  if val <= min:
    decBtnDisabled = true
    igBeginDisabled()

  if igButton(cstring &"{FA_Minus}##m{label}", igVec2(width, 0)):
    if val > min:
      dec val, step

  if decBtnDisabled:
    igEndDisabled()
  
  igEndGroup()

proc getData*(path: string): string = 
  when defined(release):
    resources[path]
  else:
    readFile(path)

proc getData*(node: TomlValueRef): string = 
  node.getString().getData()

proc updatePrefs*(app: var App) = 
  if app.prefs["alarmPath"].getString().len > 0:
    if app.prefs["alarmPath"].getString().fileExists():
      try:
        app.alarmSound = loadSoundFile(app.prefs["alarmPath"].getString())
      except SoundError:
        notifyPopup("Could not load alarm", getCurrentExceptionMsg(), "error")
    else:
      notifyPopup("Could not find alarm", "Could not find " & app.prefs["alarmPath"].getString(), "warning")
  else: # Load default alarm
    app.alarmSound = loadSoundBytes(app.config["alarmPath"].getString(), app.config["alarmPath"].getData())
