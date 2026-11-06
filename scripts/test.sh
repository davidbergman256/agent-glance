#!/bin/sh
# Runs `swift test` with Command Line Tools' Swift Testing framework on the search paths (no Xcode needed).
: "${DEVELOPER_DIR:=/Library/Developer/CommandLineTools}"; export DEVELOPER_DIR  # pin the toolchain these scripts were written for
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift build --product agent-glance-hook -q && exec swift test -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
