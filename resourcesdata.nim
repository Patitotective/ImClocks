import std/[tables, sugar]
import niprefs

type Resources* = Table[string, string]

const configPath = "config.niprefs"
let config {.compileTime.} = readPrefs(configPath)

const resourcesPaths = [
  configPath, 
  config["iconPath"].getString(), 
  config["stylePath"].getString(), 
  config["fontPath"].getString(), 
  config["iconFontPath"].getString()
]

const resources* =
  when defined(release):
    collect:
      for path in resourcesPaths:
        {path: slurp(path)}
  else:
    initTable[string, string]()

proc getData*(res: Resources, path: string): string = 
  when defined(release):
    res[path]
  else:
    readFile(path)
