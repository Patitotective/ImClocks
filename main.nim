import std/[algorithm, strformat, monotimes, strutils, sequtils, times, os]

import chroma
import imstyle
import niprefs
import stopwatch
import timezones
import tinydialogs
import nimgl/[opengl, glfw]
import nimgl/imgui, nimgl/imgui/[impl_opengl, impl_glfw]

import src/[prefsmodal, utils, icons, sound]

const
  configPath = "config.toml"
  red = "#ED333B".parseHtmlColor()
  blue = "#3584E4".parseHtmlColor()

proc getCacheDir(app: App): string = 
  getCacheDir(app.config["name"].getString())

proc drawAboutModal(app: App) = 
  var center: ImVec2
  getCenterNonUDT(center.addr, igGetMainViewport())
  igSetNextWindowPos(center, Always, igVec2(0.5f, 0.5f))

  let unusedOpen = true # Passing this parameter creates a close button
  if igBeginPopupModal(cstring "About " & app.config["name"].getString(), unusedOpen.unsafeAddr, flags = makeFlags(ImGuiWindowFlags.NoResize)):
    # Display icon image
    var texture: GLuint
    var image = app.config["iconPath"].getData().readImageFromMemory()

    image.loadTextureFromData(texture)

    igImage(cast[ptr ImTextureID](texture), igVec2(64, 64)) # Or igVec2(image.width.float32, image.height.float32)
    if igIsItemHovered():
      igSetTooltip(cstring app.config["website"].getString() & " " & FA_ExternalLink)
      
      if igIsMouseClicked(ImGuiMouseButton.Left):
        app.config["website"].getString().openURL()

    igSameLine()
    
    igPushTextWrapPos(250)
    igTextWrapped(app.config["comment"].getString().cstring)
    igPopTextWrapPos()

    igSpacing()

    # To make it not clickable
    igPushItemFlag(ImGuiItemFlags.Disabled, true)
    igSelectable("Credits", true, makeFlags(ImGuiSelectableFlags.DontClosePopups))
    igPopItemFlag()

    if igBeginChild("##credits", igVec2(0, 75)):
      for author in app.config["authors"]:
        let (name, url) = block: 
          let (name,  url) = author.getString().removeInside('<', '>')
          (name.strip(),  url.strip())

        if igSelectable(cstring name) and url.len > 0:
            url.openURL()
        if igIsItemHovered() and url.len > 0:
          igSetTooltip(cstring url & " " & FA_ExternalLink)
      
      igEndChild()

    igSpacing()

    igText(app.config["version"].getString().cstring)

    igEndPopup()

proc drawAddTzModal(app: var App) = 
  var center: ImVec2
  getCenterNonUDT(center.addr, igGetMainViewport())
  igSetNextWindowPos(center, Always, igVec2(0.5f, 0.5f))

  let unusedOpen = true
  if igBeginPopupModal("Add Timezone", unusedOpen.unsafeAddr, flags = makeFlags(AlwaysAutoResize)):
    let items = getDefaultTzDb().tzNames.sorted
    igInputTextWithHint("##filter", "Filter Timezones", cstring app.zoneBuffer, 100)

    if igIsWindowFocused(ImGuiFocusedFlags.RootAndChildWindows) and not igIsAnyItemActive() and not igIsMouseClicked(ImGuiMouseButton.Left):
      igSetKeyboardFocusHere()

    if igBeginListBox("##timezones"):
      for e, item in items:
        if app.zoneBuffer.cleanString().toLowerAscii() notin item.toLowerAscii(): continue

        let isSelected = app.currentZone == e
        if igSelectable(cstring item, isSelected):
          app.currentZone = e.int32

        if isSelected:
          igSetItemDefaultFocus()

      igEndListBox()

    if igButton("Add"):
      if items[app.currentZone] notin app.timezones:
        app.timezones.add items[app.currentZone]
      igCloseCurrentPopup()

    igEndPopup()

proc drawWorldTab(app: var App) = 
  let style = igGetStyle()
  var selected = -1

  if igBeginChild("##timezones", size = igVec2(0, igGetContentRegionAvail().y - style.windowPadding.y - igGetFrameHeight() - style.itemSpacing.y)):
    for e, name in app.timezones.deepCopy():
      let
        dt = now().inZone(name.tz)
        offset = (now().utcOffset() div 3600) - (dt.utcOffset() div 3600)

      var utc: string

      if offset == 0:
        utc = "Current timezone"
      elif offset > 0:
        utc = &"{offset} hours later"
      elif offset < 0:
        utc = &"{offset * -1} hours earlier"

      if igSelectable(cstring &"{name}: {utc}", selected == e):
        selected = e
      if igIsItemActive() and not igIsItemHovered():
        let nextIdx = e + (if igGetMouseDragDelta().y < 0: -1 else: 1)
        if nextIdx >= 0 and nextIdx < app.timezones.len:
          (app.timezones[e], app.timezones[nextIdx]) = (app.timezones[nextIdx], name)
          igResetMouseDragDelta()

      if igIsItemHovered():
        igSetTooltip(cstring dt.format("yyyy-MM-dd 'UTC'zz"))

      if igBeginPopupContextItem():
        if igMenuItem(FA_TrashO & " Remove"):
          app.timezones.delete(e)
        igEndPopup()

      igSameLine()

      igCenterCursorX(igCalcTextSize(cstring dt.getClockStr()).x + (style.framePadding.x * 2), 1)

      igText(cstring dt.getClockStr())

    if app.timezones.len == 0:
      igText("No timezones")

    igEndChild()

  igSpacing()

  if igButton("Add Timezone"):
    igOpenPopup("Add Timezone")
  
  app.drawAddTzModal()

  igEndTabItem()

proc startSw(app: var App) = 
  case app.swState
  of Stopped: # Start
    app.startBtnText = "Pause " & FA_Pause
    app.lapBtnText = "Lap"
    app.swState = Running
    app.sw.start()
  of Running: # Pause
    app.startBtnText = "Resume"
    app.lapBtnText = "Clear"
    app.swState = Paused
    app.sw.recordLaps = false
    app.sw.stop()
    app.sw.recordLaps = true

  of Paused: # Resume
    app.startBtnText = "Pause " & FA_Pause
    app.lapBtnText = "Lap"
    app.swState = Running
    app.sw.start()

proc lapSw(app: var App) = 
  case app.swState
  of Stopped: discard
  of Running: # Lap
    app.sw.stop()
    app.sw.start()
  of Paused: # Clear/Stop
    app.startBtnText = "Start " & FA_Play
    app.lapBtnText = "Lap"
    app.swState = Stopped
    app.sw.reset()

proc drawSwTab(app: var App) = 
  igPushFont(app.bigFont)
  let style = igGetStyle()
  let time = app.sw.totalMsecs.formatTime()

  let height = (igGetFrameHeight() * 2) + style.itemSpacing.y
  let timeTextWidth = igCalcTextSize(cstring time).x
  let startBtnWidth = igCalcTextSize(cstring app.startBtnText).x
  let lapBtnWidth = igCalcTextSize(cstring app.lapBtnText).x
  let btnsWidth = lapBtnWidth + startBtnWidth + (style.framePadding.x * 4) + style.itemSpacing.x

  var lapBtnDisabled = false

  igCenterCursorY(height)
  igCenterCursorX(timeTextWidth)

  igText(cstring app.sw.totalMsecs.formatTime())

  igCenterCursorX(btnsWidth)

  if igButton(cstring app.startBtnText):
    app.startSw()

  igSameLine()

  if app.swState == Stopped:
    lapBtnDisabled = true
    igPushItemFlag(ImGuiItemFlags.Disabled, true)
    igPushStyleVar(ImGuiStyleVar.Alpha, igGetStyle().alpha * 0.6)

  if igButton(cstring app.lapBtnText):
    app.lapSw()

  if lapBtnDisabled:
    igPopStyleVar()
    igPopItemFlag()

  igPopFont()

  igSpacing()

  # Laps table
  if app.sw.laps.len > 0 and igBeginTable("laps", 3, makeFlags(ImGuiTableFlags.ScrollY, BordersOuter, BordersInnerH)):
    for e in countdown(app.sw.laps.high, app.sw.laps.low):
      igTableNextRow()

      igTableNextColumn()
      igText(cstring app.sw.laps[e].msecs.formatTime())

      igTableNextColumn()

      if e > 0:
        let diff = app.sw.laps[e] - app.sw.laps[e-1] # Difference
        var
          text: string
          color: ImVec4

        if diff > 0:
          text = "+" & diff.msecs.formatTime()
          color = blue.igVec4()
        else:
          text = "-" & (diff * -1).msecs.formatTime()
          color = red.igVec4()

        igCenterCursorX(igCalcTextSize(cstring text).x)

        igTextColored(color, cstring text)

      igTableNextColumn()
      
      # Align right
      igSetCursorPosX(igGetCursorPosX() + igGetColumnWidth() - igCalcTextSize(cstring &"Lap {e+1}").x - igGetScrollX() - 2 * igGetStyle().itemSpacing.x)
      
      igText(cstring &"Lap {e+1}")

    igEndTable()

  igEndTabItem()

proc startTimer(app: var App) = 
  app.timeMs = app.time[0] * 3600000 + app.time[1] * 60000 + app.time[2] * 1000
  app.timeMs += 500
  app.timer.start()
  app.timerState = Running

proc drawTimerEnd(app: var App) = 
  let style = igGetStyle()
  let time = formatTime(app.timeMs - app.timer.totalMsecs, includeMs = false)

  # When alarm is playing and odd seconds
  var redTime = app.alarmVoice.playing and (getMonotime() - app.monotimeStart).inSeconds mod 2 == 1

  let timeTextWidth = igCalcTextSize(cstring time).x
  let restartBtnWidth = igCalcTextSize("Restart").x
  let height = (igGetFrameHeight() * 2) + style.itemSpacing.y + (if app.alarmVoice.playing: igGetFrameHeight() + style.itemSpacing.y else: 0)
  let btnsWidth = (restartBtnWidth * 2) + (style.framePadding.x * 2) + style.itemSpacing.x
  
  igCenterCursorY(height)
  igCenterCursorX(timeTextWidth + (style.framePadding.x * 2))

  if redTime:
    igTextColored(red.igVec4(), cstring time)
  else:
    igTextColored(igGetColorU32(Text).igColorConvertU32ToFloat4(), cstring time)

  if app.alarmVoice.playing:
    igCenterCursorX(igCalcTextSize("Stop " & FA_Stop).x)

    igPushStyleColor(ImGuiCol.Button, red.igVec4())
    igPushStyleColor(ImGuiCol.ButtonHovered, red.darken(0.1).igVec4())

    if igButton("Stop " & FA_Stop):
      app.timer.stop()
      app.alarmVoice.pause()

    igPopStyleColor(2)
  
  igCenterCursorX(btnsWidth)

  if igButton("Restart"):
    app.playAlarm = true
    app.timer.reset()
    app.startTimer()
    app.alarmVoice.pause()

  igSameLine()

  if igButton("New", igVec2(restartBtnWidth, 0)):
    app.playAlarm = true
    app.timerState = Stopped
    app.timer.reset()
    app.alarmVoice.pause()

proc drawTimerPause(app: var App) = 
  let style = igGetStyle()
  let time = formatTime(app.timeMs - app.timer.totalMsecs, includeMs = false)

  let timeTextWidth = igCalcTextSize(cstring time).x
  let stopBtnWidth = igCalcTextSize("Stop " & FA_Stop).x
  let resumeBtnWidth = igCalcTextSize("Resume").x
  let btnsWidth = resumeBtnWidth + stopBtnWidth + (style.framePadding.x * 4) + style.itemSpacing.x
  let height = (igGetFrameHeight() * 2) + style.itemSpacing.y

  igCenterCursorY(height)

  igCenterCursorX(timeTextWidth + (style.framePadding.x * 2))
  igText(cstring time)

  igCenterCursorX(btnsWidth)

  if igButton("Resume"):
    app.startTimer()

  igSameLine()

  if igButton("Stop " & FA_Stop):
    app.timer.reset()
    app.timerState = Stopped

proc drawTimerStop(app: var App) = 
  let style = igGetStyle()
  let width = ((igCalcTextSize("99").x + (style.framePadding.x * 2)) * 3) + (style.itemSpacing.x * 2)
  let height = (igGetFrameHeight() * 4) + (style.itemSpacing.y * 3) + 2
  var startBtnDisabled = false

  igCenterCursor(igVec2(width, height))

  vInputInt("##hours", app.time[0], max = 99)
  igSameLine()
  vInputInt("##minutes", app.time[1], max = 59)
  igSameLine()
  vInputInt("##seconds", app.time[2], max = 59)

  igDummy(igVec2(0, 2))

  igCenterCursorX(igCalcTextSize("Start " & FA_Play).x + (style.framePadding.x * 2))

  if app.time.foldl(a + b) == 0:
    startBtnDisabled = true
    igBeginDisabled()

  if igButton("Start " & FA_Play):  
    app.startTimer()

  if startBtnDisabled:
    igEndDisabled()

proc drawTimerRunning(app: var App) = 
  let style = igGetStyle()
  let time = formatTime(app.timeMs - app.timer.totalMsecs, includeMs = false)

  let pauseBtnWidth = igCalcTextSize("Pause " & FA_Pause).x
  let timeTextWidth = igCalcTextSize(cstring time).x
  let height = (igGetFrameHeight() * 2) + style.itemSpacing.y

  if app.timeMs - app.timer.totalMsecs < 0:
    if app.playAlarm:
      app.playAlarm = false
      app.alarmVoice = app.alarmSound.play(volume = app.prefs["alarmVol"].getFloat(), loop = app.prefs["loopAlarm"].getBool())
      notifyPopup("Timer", "Time is over", "info")

    app.drawTimerEnd()
  else:
    igCenterCursorY(height)

    igCenterCursorX(timeTextWidth)
    igText(cstring time)

    igCenterCursorX(pauseBtnWidth)

    if igButton("Pause " & FA_Pause):
      app.timer.stop()
      app.timerState = Paused

proc drawTimerTab(app: var App) =   
  case app.timerState
  of Stopped:
    app.drawTimerStop()
  of Running:
    app.drawTimerRunning()
  of Paused:
    app.drawTimerPause()

  igEndTabItem()

proc drawMainMenuBar(app: var App) =
  var openAbout, openPrefs, openAddTz = false

  if igBeginMainMenuBar():
    if igBeginMenu("File"):
      igMenuItem("Preferences " & FA_Cog, "Ctrl+P", openPrefs.addr)
      if igMenuItem("Quit " & FA_Times, "Ctrl+Q"):
        app.win.setWindowShouldClose(true)
      igEndMenu()

    if igBeginMenu("Edit"):
      igMenuItem("Add Timezone", "", openAddTz.addr)
      if igMenuItem(cstring &"{app.startBtnText} Stopwatch"):
        app.startSw()
      if igMenuItem(cstring &"{app.lapBtnText} Stopwatch", enabled = app.swState != Stopped):
        app.lapSw()
      
      igEndMenu()

    if igBeginMenu("About"):
      if igMenuItem("Website " & FA_ExternalLink):
        app.config["website"].getString().openURL()

      igMenuItem(cstring  "About " & app.config["name"].getString(), shortcut = nil, p_selected = openAbout.addr)

      igEndMenu() 

    igEndMainMenuBar()

  # See https://github.com/ocornut/imgui/issues/331#issuecomment-751372071
  if openAbout:
    igOpenPopup(cstring "About " & app.config["name"].getString())
  if openPrefs:
    igOpenPopup("Preferences")
  if openAddTz:
    igOpenPopup("Add Timezone")

  # These modals will only get drawn when igOpenPopup(name) are called, respectly
  app.drawAboutModal()
  app.drawPrefsModal()
  app.drawAddTzModal()

proc drawMain(app: var App) = # Draw the main window
  let viewport = igGetMainViewport()  
  
  app.drawMainMenuBar()
  # Work area is the entire viewport minus main menu bar, task bars, etc.
  igSetNextWindowPos(viewport.workPos)
  igSetNextWindowSize(viewport.workSize)

  if igBegin(cstring app.config["name"].getString(), flags = makeFlags(ImGuiWindowFlags.NoResize, NoDecoration, NoMove)):
    if igBeginTabBar("Clocks"):
      if igBeginTabItem("World " & FA_Globe):
        app.drawWorldTab()

      if igBeginTabItem("Stopwatch " & FA_ClockO):
        app.drawSwTab()

      if igBeginTabItem("Timer " & FA_HourglassHalf):
        igPushFont(app.bigFont)
        app.drawTimerTab()
        igPopFont()

      igEndTabBar()

  igEnd()

proc render(app: var App) = # Called in the main loop
  # Poll and handle events (inputs, window resize, etc.)
  glfwPollEvents() # Use glfwWaitEvents() to only draw on events (more efficient)

  # Start Dear ImGui Frame
  igOpenGL3NewFrame()
  igGlfwNewFrame()
  igNewFrame()

  # Draw application
  app.drawMain()

  # Render
  igRender()

  var displayW, displayH: int32
  let bgColor = igColorConvertU32ToFloat4(uint32 WindowBg)

  app.win.getFramebufferSize(displayW.addr, displayH.addr)
  glViewport(0, 0, displayW, displayH)
  glClearColor(bgColor.x, bgColor.y, bgColor.z, bgColor.w)
  glClear(GL_COLOR_BUFFER_BIT)

  igOpenGL3RenderDrawData(igGetDrawData())  

  app.win.makeContextCurrent()
  app.win.swapBuffers()

proc initWindow(app: var App) = 
  glfwWindowHint(GLFWContextVersionMajor, 3)
  glfwWindowHint(GLFWContextVersionMinor, 3)
  glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE)
  glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
  glfwWindowHint(GLFWResizable, GLFW_TRUE)

  app.win = glfwCreateWindow(
    int32 app.prefs{"win", "width"}.getInt(), 
    int32 app.prefs{"win", "height"}.getInt(), 
    cstring app.config["name"].getString(), 
    icon = false # Do not use default icon
  )

  if app.win == nil:
    quit(-1)

  # Set the window icon
  var icon = initGLFWImage(app.config["iconPath"].getData().readImageFromMemory())
  app.win.setWindowIcon(1, icon.addr)

  app.win.setWindowSizeLimits(app.config["minSize"][0].getInt().int32, app.config["minSize"][1].getInt().int32, GLFW_DONT_CARE, GLFW_DONT_CARE) # minWidth, minHeight, maxWidth, maxHeight

  # If negative pos, center the window in the first monitor
  if app.prefs{"win", "x"}.getInt() < 0 or app.prefs{"win", "y"}.getInt() < 0:
    var monitorX, monitorY, count: int32
    let monitors = glfwGetMonitors(count.addr)
    let videoMode = monitors[0].getVideoMode()

    monitors[0].getMonitorPos(monitorX.addr, monitorY.addr)
    app.win.setWindowPos(
      monitorX + int32((videoMode.width - int app.prefs{"win", "width"}.getInt()) / 2), 
      monitorY + int32((videoMode.height - int app.prefs{"win", "height"}.getInt()) / 2)
    )
  else:
    app.win.setWindowPos(app.prefs{"win", "x"}.getInt().int32, app.prefs{"win", "y"}.getInt().int32)

proc initPrefs(app: var App) = 
  app.prefs = initPrefs(
    path = (app.getCacheDir() / app.config["name"].getString()).changeFileExt("toml"), 
    default = toToml {
      win: {
        x: -1, # Negative numbers center the window
        y: -1,
        width: 600,
        height: 650
      }, 
      timezones: [], 
    }
  )

proc initApp(config: TomlValueRef): App = 
  result = App(
    config: config, cache: newTTable(), 
    zoneBuffer: newString(100), 
    sw: stopwatch(), swState: Stopped, 
    startBtnText: "Start " & FA_Play, lapBtnText: "Lap", 
    timerState: Stopped, playAlarm: true
  )
  result.initPrefs()
  result.initSettings(result.config["settings"])

  initAudio()
  result.updatePrefs()

  for timezone in result.prefs["timezones"]:
    result.timezones.add timezone.getString()

proc terminate(app: var App) = 
  var x, y, width, height: int32

  app.win.getWindowPos(x.addr, y.addr)
  app.win.getWindowSize(width.addr, height.addr)
  
  app.prefs{"win", "x"} = x
  app.prefs{"win", "y"} = y
  app.prefs{"win", "width"} = width
  app.prefs{"win", "height"} = height

  app.prefs["timezones"] = newTArray()
  for timezone in app.timezones:
    app.prefs["timezones"].add timezone

  app.prefs.save()

proc main() =
  var app = initApp(Toml.decode(configPath.getData(), TomlValueRef))

  # Setup Window
  doAssert glfwInit()
  app.initWindow()
  
  app.win.makeContextCurrent()
  glfwSwapInterval(1) # Enable vsync

  doAssert glInit()

  # Setup Dear ImGui context
  igCreateContext()
  let io = igGetIO()
  io.iniFilename = nil # Disable .ini config file

  # Setup Dear ImGui style using ImStyle
  setStyleFromToml(Toml.decode(app.config["stylePath"].getData(), TomlValueRef))

  # Setup Platform/Renderer backends
  doAssert igGlfwInitForOpenGL(app.win, true)
  doAssert igOpenGL3Init()

  # Load fonts
  app.font = io.fonts.igAddFontFromMemoryTTF(app.config["fontPath"].getData(), app.config["fontSize"].getFloat())

  # Merge ForkAwesome icon font
  var config = utils.newImFontConfig(mergeMode = true)
  var ranges = [FA_Min.uint16,  FA_Max.uint16]

  io.fonts.igAddFontFromMemoryTTF(app.config["iconFontPath"].getData(), app.config["fontSize"].getFloat(), config.addr, ranges[0].addr)

  app.bigFont = io.fonts.igAddFontFromMemoryTTF(app.config["fontPath"].getData(), app.config["fontSize"].getFloat() + 10)

  io.fonts.igAddFontFromMemoryTTF(app.config["iconFontPath"].getData(), app.config["fontSize"].getFloat() + 6, config.addr, ranges[0].addr)

  # Main loop
  while not app.win.windowShouldClose:
    app.render()

  # Cleanup
  igOpenGL3Shutdown()
  igGlfwShutdown()
  
  igDestroyContext()
  
  app.terminate()
  app.win.destroyWindow()
  glfwTerminate()

when isMainModule:
  main()
