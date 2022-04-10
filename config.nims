switch("threads", "on")
switch("backend", "cpp")
switch("warning", "HoleEnumConv:off")
switch("warning", "CStringConv:off")
when defined(linux):
  switch("passL", "-ldl -lm -lpthread")
