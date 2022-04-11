# Package

version          = "0.1.0"
author           = "Patitotective"
description      = "A simple ImGui clocks application"
license          = "MIT"
namedBin["main"] = "ImClocks"
binDir           = "build"
installFiles     = @["config.niprefs", "assets/icon.png", "assets/style.niprefs", "assets/ProggyVector Regular.ttf"]

# Dependencies

requires "nim >= 1.6.2"
requires "nake >= 1.9.4"
requires "timezones >= 0.5.4"
requires "chroma >= 0.2.4"
requires "niprefs >= 0.1.2"
requires "https://github.com/Patitotective/ImStyle >= 0.1.0"
requires "nimgl >= 1.3.2"
requires "stb_image >= 2.5"
requires "https://github.com/define-private-public/stopwatch >= 3.5"
