import std/os
import soloud

var so: ptr Soloud

type
  SoundError* = object of ValueError
  Sound* = ref object
    handle: ptr AudioSource
  Voice* = distinct cuint

template checkErr(details: string, body: untyped) =
  let err = body
  if err != 0: raise newException(SoundError, details & ": " & $so.SoloudGetErrorString(err))

proc initAudio*() =
  so = SoloudCreate()
  checkErr("Failed to initialize"): so.SoloudInit()
  # echo "Initialized SoLoud v" & $so.SoloudGetVersion() & " w/ " & $so.SoloudGetBackendString()

proc getAudioBufferSize*(): int = so.SoloudGetBackendBufferSize().int

proc getAudioSampleRate*(): int = so.SoloudGetBackendSampleRate().int

proc loadSoundFile*(path: string): Sound =
  let handle = WavCreate()
  checkErr(path): handle.WavLoad(path)
  return Sound(handle: handle)

proc loadSoundBytes*(path: string, data: string): Sound =
  let handle = WavCreate()
  checkErr(path): handle.WavLoadMemEx(cast[ptr cuchar](data.cstring), data.len.cuint, 1, 0)
  return Sound(handle: handle)

proc play*(sound: Sound, pitch = 1.0f, volume = 1.0f, pan = 0f, loop = false): Voice {.discardable.} =
  #handle may not exist due to failed loading
  if sound.handle.isNil: return

  let id = so.SoloudPlay(sound.handle)
  if volume != 1.0: so.SoloudSetVolume(id, volume)
  if pan != 0f: so.SoloudSetPan(id, pan)
  if pitch != 1.0: discard so.SoloudSetRelativePlaySpeed(id, pitch)
  if loop: so.SoloudSetLooping(id, 1)
  return id.Voice

proc length*(sound: Sound): float =
  return WavGetLength(cast[ptr Wav](sound.handle)).float

proc stop*(v: Voice) {.inline.} = so.SoloudStop(v.cuint)
proc pause*(v: Voice) {.inline.} = so.SoloudSetPause(v.cuint, 1)
proc resume*(v: Voice) {.inline.} = so.SoloudSetPause(v.cuint, 0)
proc seek*(v: Voice, pos: float) {.inline.} = discard so.SoloudSeek(v.cuint, pos.cdouble)

proc valid*(v: Voice): bool {.inline.} = so.SoloudIsValidVoiceHandle(v.cuint).bool
proc paused*(v: Voice): bool {.inline.} = so.SoloudGetPause(v.cuint).bool
proc playing*(v: Voice): bool {.inline.} = not v.paused
proc volume*(v: Voice): float32 {.inline.} = so.SoloudGetVolume(v.cuint).float32
proc pitch*(v: Voice): float32 {.inline.} = discard so.SoloudGetRelativePlaySpeed(v.cuint).float32
proc loopCount*(v: Voice): int {.inline.} = so.SoloudGetLoopCount(v.cuint).int

proc `paused=`*(v: Voice, value: bool) {.inline.} = so.SoloudSetPause(v.cuint, value.cint)
proc `volume=`*(v: Voice, value: float32) {.inline.} = so.SoloudSetVolume(v.cuint, value)
proc `pitch=`*(v: Voice, value: float32) {.inline.} = discard so.SoloudSetRelativePlaySpeed(v.cuint, value)
proc `pan=`*(v: Voice, value: float32) {.inline.} = so.SoloudSetPan(v.cuint, value)

# loadSoundFile("../assets/alarm.ogg").play()
# loadSoundBytes("../assets/alarm.ogg", readFile("../assets/alarm.ogg")).play()
# sleep(5000)
