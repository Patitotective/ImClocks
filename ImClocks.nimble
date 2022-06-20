# Package

version          = "0.2.0"
author           = "Patitotective"
description      = "A simple Dear ImGui clocks application"
license          = "MIT"
namedBin["main"] = "ImClocks"

# Dependencies

requires "nim >= 1.6.2"
requires "nake >= 1.9.4"
requires "nimgl >= 1.3.2"
requires "chroma >= 0.2.4"
requires "imstyle >= 0.3.2"
requires "niprefs >= 0.3.4"
requires "stb_image >= 2.5"
requires "stopwatch >= 3.6"
requires "timezones >= 0.5.4"
requires "tinydialogs >= 0.1.1"
requires "https://github.com/Anuken/nimsoloud >= 1.0.0"

import std/[strformat, os]

let arch = if existsEnv("ARCH"): getEnv("ARCH") else: "amd64"
let outPath = if existsEnv("OUTPATH"): getEnv("OUTPATH") else: &"{namedBin[\"main\"]}-{version}-{arch}" & (when defined(Windows): ".exe" else: "")
let flags = getEnv("FLAGS")

task buildApp, "Build the application":
  exec "nimble install -d -y"
  exec fmt"nim cpp -d:release --app:gui --out:{outPath} --cpu:{arch} {flags} main.nim"

task runApp, "Build and run the application":
  exec "nimble buildApp"

  exec fmt"./{outPath}"

