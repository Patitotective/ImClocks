import std/[strutils, sequtils, algorithm, enumerate, strformat, browsers, monotimes, times, os]

import timezones
import chroma
import imstyle
import niprefs
import stopwatch
import nimgl/[opengl, glfw]
import nimgl/imgui, nimgl/imgui/[impl_opengl, impl_glfw]

import src/[utils, icons]

const
  resourcesDir = "data"
  configPath = "config.niprefs"
  red = "#ED333B".parseHtmlColor()
  blue = "#3584E4".parseHtmlColor()

proc getPath(path: string): string = 
  # When running on an AppImage get the path from the AppImage resources
  when defined(appImage):
    result = getEnv"APPDIR" / resourcesDir / path.extractFilename()
  else:
    result = getAppDir() / path

proc getPath(path: PrefsNode): string = 
  path.getString().getPath()

proc drawAboutModal(app: var App) = 
  var center: ImVec2
  getCenterNonUDT(center.addr, igGetMainViewport())
  igSetNextWindowPos(center, Always, igVec2(0.5f, 0.5f))

  if igBeginPopupModal("About " & app.config["name"].getString(), flags = makeFlags(AlwaysAutoResize)):

    # Display icon image
    var
      texture: GLuint
      image = app.config["iconPath"].getPath().readImage()
    image.loadTextureFromData(texture)
    
    igImage(cast[ptr ImTextureID](texture), igVec2(64, 64)) # Or igVec2(image.width.float32, image.height.float32)

    igSameLine()
    
    igPushTextWrapPos(250)
    igTextWrapped(app.config["comment"].getString())
    igPopTextWrapPos()

    igSpacing()

    igTextWrapped("Credits: " & app.config["authors"].getSeq().mapIt(it.getString()).join(", "))

    if igButton("Ok"):
      igCloseCurrentPopup()

    igSameLine()

    igText(app.config["version"].getString())

    igEndPopup()

proc drawAddTzModal(app: var App) = 
  var center: ImVec2
  getCenterNonUDT(center.addr, igGetMainViewport())
  igSetNextWindowPos(center, Always, igVec2(0.5f, 0.5f))

  if igBeginPopupModal("Add Timezone", flags = makeFlags(AlwaysAutoResize)):
    let items = getDefaultTzDb().tzNames.sorted
    app.filter.addr.draw("##filter")

    if igBeginListBox("##timezones"):
      for e, item in items:
        if not app.filter.addr.passFilter(item): continue

        let isSelected = app.currentZone == e
        if igSelectable(item, isSelected):
          app.currentZone = e.int32

        if isSelected:
          igSetItemDefaultFocus()

      igEndListBox()

    if igButton("Add"):
      app.prefs["timezones"] = app.prefs["timezones"].getSeq() & items[app.currentZone].newPString()
      igCloseCurrentPopup()

    igSameLine()

    if igButton("Cancel"):
      igCloseCurrentPopup()

    igEndPopup()

proc drawWorldTab(app: var App) = 
  var selected = -1

  for e, name in enumerate(app.prefs["timezones"]):
    let
      dt = now().inZone(name.getString().tz)
      offset = (now().utcOffset() div 3600) - (dt.utcOffset() div 3600)

    var utc: string

    if offset == 0:
      utc = "Current timezone"
    elif offset > 0:
      utc = &"{offset} hours later"
    elif offset < 0:
      utc = &"{offset * -1} hours earlier"

    if igSelectable(&"{name.getString()}: {utc}", selected == e):
      selected = e

    if igBeginPopupContextItem():
      if igButton(FA_TrashO & " Remove"):
        app.prefs["timezones"] = app.prefs["timezones"].getSeq().deleted(e)
      igEndPopup()

    igSameLine()

    centerCursorX(dt.getClockStr().igCalcTextSize().x, 1)

    igText(dt.getClockStr())

    if igIsItemHovered():
      igSetTooltip(dt.format("yyyy-MM-dd HH:mm:ss 'UTC'zz"))

  if app.prefs["timezones"].getSeq().len == 0:
    igText("No timezones")

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
    # app.sw.rmLap(app.sw.laps.high)
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
    app.startBtnText = "Start"
    app.lapBtnText = "Lap"
    app.swState = Stopped
    app.sw.reset()

proc drawSwTab(app: var App) = 
  igPushFont(app.bigFont)
  let
    style = igGetStyle()
    time = app.sw.totalMsecs.formatTime()
  var
    height: float32
    btnsSize: ImVec2
    timeTextSize = time.igCalcTextSize()
    lapBtnDisabled = false
    startBtnSize = app.startBtnText.igCalcTextSize()

  startBtnSize.x += style.framePadding.x * 2

  btnsSize.x += startBtnSize.x * 2 + style.itemSpacing.x
  btnsSize.y += startBtnSize.y

  startBtnSize.y = 0 # So it calculates it

  height += timeTextSize.y + btnsSize.y

  centerCursorY(height + 50)

  centerCursorX(timeTextSize.x)

  igText(app.sw.totalMsecs.formatTime())

  centerCursorX(btnsSize.x)

  if igButton(app.startBtnText, startBtnSize):
    app.startSw()

  igSameLine()

  if app.swState == Stopped:
    lapBtnDisabled = true
    igPushItemFlag(ImGuiItemFlags.Disabled, true)
    igPushStyleVar(ImGuiStyleVar.Alpha, igGetStyle().alpha * 0.6)

  if igButton(app.lapBtnText, startBtnSize):
    app.lapSw()

  if lapBtnDisabled:
    igPopStyleVar()
    igPopItemFlag()

  igPopFont()

  igSpacing()

  # Laps table
  if app.sw.laps.len > 0 and igBeginTable("laps", 3, makeFlags(ImGuiTableFlags.NoClip, BordersOuter, BordersInnerH)):
    for e in countdown(app.sw.laps.high, app.sw.laps.low):
      igTableNextRow()

      igTableNextColumn()
      igText(app.sw.laps[e].msecs.formatTime())

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

        centerCursorX(igCalcTextSize(text).x)

        igTextColored(color, text)

      igTableNextColumn()
      
      # Align right
      igSetCursorPosX(igGetCursorPosX() + igGetColumnWidth() - igCalcTextSize(&"Lap {e+1}").x - igGetScrollX() - 2 * igGetStyle().itemSpacing.x)
      
      igText(&"Lap {e+1}")

    igEndTable()

  igEndTabItem()

proc startTimer(app: var App) = 
  app.timeMs = app.time[0] * 3600000 + app.time[1] * 60000 + app.time[2] * 1000
  app.timeMs += 500
  app.timer.start()
  app.timerState = Running

proc drawTimerEnd(app: var App) = 
  let
    style = igGetStyle()
    time = formatTime(app.timeMs - app.timer.totalMsecs, includeMs = false)

  # When alarm is playing and odd seconds
  var redTime = not app.stopAlarm and (getMonotime() - app.monotimeStart).inSeconds mod 2 == 1

  var
    height: float32
    btnsSize: ImVec2
    timeTextSize = igCalcTextSize(time)
    restartBtnSize = igCalcTextSize("Restart")

  restartBtnSize.x += style.framePadding.x * 2

  btnsSize.x += restartBtnSize.x * 2
  btnsSize.y += restartBtnSize.y

  restartBtnSize.y = 0

  height += timeTextSize.y + btnsSize.y

  centerCursorY(height + 50)

  centerCursorX(igCalcTextSize(time).x + style.framePadding.x * 2)
  
  if redTime:
    igTextColored(red.igVec4(), time)
  else:
    igTextColored(igGetStyle().colors[ImGuiCol.Text.ord], time)

  if not app.stopAlarm:
    centerCursorX(igCalcTextSize("Stop " & FA_Stop).x)

    igPushStyleColor(ImGuiCol.Button, red.igVec4())
    igPushStyleColor(ImGuiCol.ButtonHovered, red.darken(0.1).igVec4())

    if igButton("Stop " & FA_Stop):
      app.stopAlarm = true
      app.timer.stop()

    igPopStyleColor(2)

  centerCursorX(btnsSize.x)

  if igButton("Restart", restartBtnSize):
    app.stopAlarm = true
    app.timer.reset()
    app.startTimer()

  igSameLine()

  if igButton("New", restartBtnSize):
    app.stopAlarm = true
    app.timer.reset()
    app.timerState = Stopped

proc drawTimerPause(app: var App) = 
  let
    style = igGetStyle()
    time = formatTime(app.timeMs - app.timer.totalMsecs, includeMs = false)

  var
    height: float32
    btnsSize: ImVec2
    timeTextSize = igCalcTextSize(time)
    stopBtnSize = igCalcTextSize("Stop " & FA_Stop)

  stopBtnSize.x += style.framePadding.x * 2

  btnsSize.x += stopBtnSize.x * 2
  btnsSize.y += stopBtnSize.y

  stopBtnSize.y = 0

  height += timeTextSize.y + btnsSize.y

  centerCursorY(height + 50)

  centerCursorX(igCalcTextSize(time).x + style.framePadding.x * 2)
  igText(time)

  centerCursorX(btnsSize.x)

  if igButton("Resume", stopBtnSize):
    app.startTimer()

  igSameLine()

  if igButton("Stop " & FA_Stop, stopBtnSize):
    app.timer.reset()
    app.timerState = Stopped

proc drawTimerStop(app: var App) = 
  let style = igGetStyle()
  var
    playBtnDisabled = false
    width = igCalcTextSize("99").x + (style.framePadding.x * 2)
  
  width *= 3
  width += style.itemSpacing.x * 2

  centerCursor(igVec2(width, 150))

  vInputInt("##hours", app.time[0], max = 99)
  igSameLine()
  vInputInt("##minutes", app.time[1], max = 59)
  igSameLine()
  vInputInt("##seconds", app.time[2], max = 59)

  igSpacing()

  centerCursorX(igCalcTextSize("Play " & FA_Play).x + style.framePadding.x * 2)

  if app.time.foldl(a + b) == 0:
    playBtnDisabled = true
    igPushItemFlag(ImGuiItemFlags.Disabled, true)
    igPushStyleVar(ImGuiStyleVar.Alpha, igGetStyle().alpha * 0.6)

  if igButton("Play " & FA_Play):  
    app.startTimer()

  if playBtnDisabled:
    igPopStyleVar()
    igPopItemFlag()

proc drawTimerRunning(app: var App) = 
  let
    style = igGetStyle()
    time = formatTime(app.timeMs - app.timer.totalMsecs, includeMs = false)
  var
    height: float32
    pauseBtnSize = igCalcTextSize("Pause " & FA_Pause)
    timeTextSize = igCalcTextSize(time)

  if app.timeMs - app.timer.totalMsecs <= 0:

    if not app.alarmThread.running and not app.stopAlarm:
      app.alarmThread.createThread(
        proc(data: (string, ptr bool)) = discard playAudio(data[0], 5000, data[1]), 
        (app.config["alarmPath"].getPath(), app.stopAlarm.addr)
      )

    app.drawTimerEnd()
  else:
    app.stopAlarm = false
    height += timeTextSize.y + pauseBtnSize.y
    centerCursorY(height + 50)

    centerCursorX(timeTextSize.x + style.framePadding.x * 2)
    igText(time)

    igSpacing()

    centerCursorX(pauseBtnSize.x + style.framePadding.x * 2)

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

proc drawMenuBar(app: var App) =
  var openAbout, openAddTz = false

  if igBeginMenuBar():
    if igBeginMenu("File"):
      if igMenuItem("Quit " & FA_Times, "Ctrl+Q"):
        app.win.setWindowShouldClose(true)
      igEndMenu()

    if igBeginMenu("Edit"):
      igMenuItem("Add Timezone", "", openAddTz.addr)
      if igMenuItem(&"{app.startBtnText} Stopwatch"):
        app.startSw()
      if igMenuItem(&"{app.lapBtnText} Stopwatch", enabled = app.swState != Stopped):
        app.lapSw()
      
      igEndMenu()

    if igBeginMenu("About"):
      if igMenuItem("Website " & FA_Heart):
        app.config["website"].getString().openDefaultBrowser()

      igMenuItem("About " & app.config["name"].getString(), shortcut = nil, p_selected = openAbout.addr)

      igEndMenu() 

    igEndMenuBar()

  # See https://github.com/ocornut/imgui/issues/331#issuecomment-751372071
  if openAbout:
    igOpenPopup("About " & app.config["name"].getString())
  if openAddTz:
    igOpenPopup("Add Timezone")

  # These modals will only get drawn when igOpenPopup(name) are called, respectly
  app.drawAboutModal()
  app.drawAddTzModal()

proc drawMain(app: var App) = # Draw the main window
  let viewport = igGetMainViewport()
  igSetNextWindowPos(viewport.pos)
  igSetNextWindowSize(viewport.size)

  igBegin(app.config["name"].getString(), flags = makeFlags(ImGuiWindowFlags.NoResize, ImGuiWindowFlags.NoSavedSettings, NoMove, NoDecoration, MenuBar))

  app.drawMenuBar()

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

proc display(app: var App) = # Called in the main loop
  glfwPollEvents()

  igOpenGL3NewFrame()
  igGlfwNewFrame()
  igNewFrame()

  app.drawMain()

  igRender()

  let bgColor = igGetStyle().colors[WindowBg.ord]
  glClearColor(bgColor.x, bgColor.y, bgColor.z, bgColor.w)
  glClear(GL_COLOR_BUFFER_BIT)

  igOpenGL3RenderDrawData(igGetDrawData())  

proc initWindow(app: var App) = 
  glfwWindowHint(GLFWContextVersionMajor, 3)
  glfwWindowHint(GLFWContextVersionMinor, 3)
  glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE)
  glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
  glfwWindowHint(GLFWResizable, GLFW_TRUE)
  
  app.win = glfwCreateWindow(
    app.prefs["win/width"].getInt().int32, 
    app.prefs["win/height"].getInt().int32, 
    app.config["name"].getString(), 
    icon = false # Do not use default icon
  )

  if app.win == nil:
    quit(-1)

  # Set the window icon
  var icon = initGLFWImage(app.config["iconPath"].getPath().readImage())
  app.win.setWindowIcon(1, icon.addr)

  app.win.setWindowSizeLimits(app.config["minSize"][0].getInt().int32, app.config["minSize"][1].getInt().int32, GLFW_DONT_CARE, GLFW_DONT_CARE) # minWidth, minHeight, maxWidth, maxHeight
  app.win.setWindowPos(app.prefs["win/x"].getInt().int32, app.prefs["win/y"].getInt().int32)

  app.win.makeContextCurrent()

proc initPrefs(app: var App) = 
  when defined(appImage):
    # Put prefsPath right next to the AppImage
    let prefsPath = getEnv"APPIMAGE".parentDir / app.config["prefsPath"].getString()
  else:
    let prefsPath = getAppDir() / app.config["prefsPath"].getString()
  
  app.prefs = toPrefs({
    timezones: [],
    win: {
      x: 0,
      y: 0,
      width: 500,
      height: 500
    }
  }).initPrefs(prefsPath)

proc initApp*(config: PObjectType): App = 
  result = App(config: config, sw: stopwatch(), swState: Stopped, startBtnText: "Start", lapBtnText: "Lap", timerState: Stopped)
  result.initPrefs()

proc terminate(app: var App) = 
  var x, y, width, height: int32

  app.win.getWindowPos(x.addr, y.addr)
  app.win.getWindowSize(width.addr, height.addr)
  
  app.prefs["win/x"] = x
  app.prefs["win/y"] = y
  app.prefs["win/width"] = width
  app.prefs["win/height"] = height

  app.win.destroyWindow()

proc main() =
  var app = initApp(configPath.getPath().readPrefs())

  doAssert glfwInit()

  app.initWindow()

  doAssert glInit()

  let context = igCreateContext()
  let io = igGetIO()
  io.iniFilename = nil # Disable ini file

  app.font = io.fonts.addFontFromFileTTF(app.config["fontPath"].getPath(), app.config["fontSize"].getFloat())

  # Add ForkAwesome icon font
  var config = utils.newImFontConfig(mergeMode = true)
  var ranges = [FA_Min.uint16,  FA_Max.uint16]
  io.fonts.addFontFromFileTTF(app.config["iconFontPath"].getPath(), app.config["fontSize"].getFloat(), config.addr, ranges[0].addr)

  app.bigFont = io.fonts.addFontFromFileTTF(app.config["fontPath"].getPath(), app.config["fontSize"].getFloat()+5)

  io.fonts.addFontFromFileTTF(app.config["iconFontPath"].getPath(), app.config["fontSize"].getFloat(), config.addr, ranges[0].addr)

  doAssert igGlfwInitForOpenGL(app.win, true)
  doAssert igOpenGL3Init()

  setIgStyle(app.config["stylePath"].getPath()) # Load application style

  while not app.win.windowShouldClose:
    app.display()
    app.win.swapBuffers()

  igOpenGL3Shutdown()
  igGlfwShutdown()
  context.igDestroyContext()

  app.terminate()
  
  glfwTerminate()

when isMainModule:
  main()
