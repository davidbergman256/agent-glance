#!/bin/sh
# Runs `swift test` with Command Line Tools' Swift Testing framework on the search paths (no Xcode needed).
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift build --product agent-glance-hook -q && exec swift test -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
