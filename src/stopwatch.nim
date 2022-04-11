import std/monotimes

type
  Ticks = int64
  Nanos = int64
  Stopwatch* = object
    running: bool
    startTicks: Ticks
    recordLaps*: bool
    previousLap: Ticks
    laps*: seq[Ticks]
    total: Nanos

proc getTicks*(): Ticks = 
  getMonotime().ticks

## Converts nanoseconds to microseconds
proc usecs*(nsecs: int64): int64 =
  return (nsecs div 1_000).int64


## Converts nanoseconds to microseconds
proc msecs*(nsecs: int64): int64 =
  return (nsecs div 1_000_000).int64

## Converts nanoseconds to seconds (represented as a float)
proc secs*(nsecs: int64): float =
  return nsecs.float / 1_000_000_000.0

proc initStopwatch*(recordLaps: bool = true): Stopwatch =
  result = Stopwatch(
    running: false,
    startTicks: 0,
    recordLaps: recordLaps,
    previousLap: 0,
    laps: @[],
    total: 0
  )

## This will return either the length of the current lap (if `stop()` has not
## been called, or the time of the previously measured lap.  The return value is
## in nanoseconds.  If no laps have been run yet, then this will return 0.
##
## If lapping is turned off then this will act the same as `totalNsecs()`
##
## See also: `usecs()`, `msecs()`, `secs()`
proc nsecs*(sw: var Stopwatch): int64 =
  let curTicks = getTicks()

  if sw.running:
    # Return current lap
    return (curTicks - sw.startTicks).int64
  elif not sw.recordLaps:
    # Lapping is off
    return sw.previousLap.int64
  elif sw.laps.len != 0:
    # Return previous lap
    return sw.previousLap.int64
  else:
    # No laps yet
    return 0

## The same as `nsecs()`, except the return value is in microseconds.
##
## See also: `nsecs()`, `msecs()`, `secs()`
proc usecs*(sw: var Stopwatch): int64 =
  return usecs(sw.nsecs)


## The same as `nsecs()`, except the return value is in milliseconds.
##
## See also: `nsecs()`, `usecs()`, `secs()`
proc msecs*(sw: var Stopwatch): int64 =
  return msecs(sw.nsecs)


## The same as `nsecs()`, except the return value is in seconds (as floats).
##
## See also: `nsecs()`, `usecs()`, `msecs()`
proc secs*(sw: var Stopwatch): float =
  return secs(sw.nsecs)


## This returns the time of all laps combined, plus the current lap (if
## Stopwatch is running).  The return value is in nanoseconds.
##
## See also: `totalUsecs()`, `totalMsecs()`, `totalSecs()`
proc totalNsecs*(sw: var Stopwatch): int64 =
  let curTicks = getTicks()

  if sw.running:
    # Return total + current lap
    return (sw.total + (curTicks - sw.startTicks)).int64
  else:
    return sw.total.int64


## The same as `totalNsecs()`, except the return value is in microseconds.
##
## See also: `totalNsecs()`, `totalMsecs()`, `totalSecs()`
proc totalUsecs*(sw: var Stopwatch): int64 =
  return usecs(sw.totalNsecs)


## The same as `totalNsecs()`, except the return value is in milliseconds.
##
## See also: `totalNsecs()`, `totalUsecs()`,`totalSecs()`
proc totalMsecs*(sw: var Stopwatch): int64 =
  return msecs(sw.totalNsecs)


## The same as `totalNsecs()`, except the return value is in seconds (as a
## float).
##
## See also: `totalNsecs()`, `totalUsecs()`, `totalMsecs()`
proc totalSecs*(sw: var Stopwatch): float =
  return secs(sw.totalNsecs)


## Checks to see if the Stopwatch is measuring time.
proc running*(sw: var Stopwatch): bool =
  return sw.running

## Makes the Stopwatch measure time.  Will do nothing if the Stopwatch is
## already doing that.
proc start*(sw: var Stopwatch) =
  # If we are already running, ignore
  if sw.running:
    return

  # Start the lap
  sw.running = true
  sw.startTicks = getTicks()


## Makes the Stopwatch stop measuring time.  It will record the lap it has
## taken.  If the Stopwatch wasn't running before, nothing will happen
proc stop*(sw: var Stopwatch, lap: bool = true) =
  # First thing, measure the time
  let stopTicks = getTicks()

  # If not running, ignore
  if not sw.running:
    return

  # Get lap time
  let lapTime = stopTicks - sw.startTicks
  
  # Save it to the laps
  if lap and sw.recordLaps:
    sw.laps.add(lapTime.Ticks)
  
  sw.previousLap = lapTime.Ticks

  # Add it to the accum
  sw.total += lapTime

  # Reset timer state
  sw.running = false
  sw.startTicks = 0

## Clears out the state of the Stopwatch.  This deletes all of the lap data (if
## lapping is enabled) and will stop the stopwatch.
proc reset*(sw: var Stopwatch) =
  sw.running = false
  sw.startTicks = 0
  sw.previousLap = 0
  sw.total = 0

  # Clear the laps
  if sw.recordLaps:
    sw.laps.setLen(0)


## This function will clear out the state of the Stopwatch and tell it to start
## recording time.  It is the same as calling reset() then start().
proc restart*(sw: var Stopwatch) =
  sw.reset()
  sw.start()


## This clears out all of the lap records from a Stopwatch.  This will not
## effect the current lap (if one is being measured).
##
## If lapping is disabled nothing will happen.
proc clearLaps(sw: var Stopwatch) =
  # Check for no laps
  if not sw.recordLaps:
    return

  sw.laps.setLen(0)
  sw.total = 0
  sw.previousLap = 0.Ticks
