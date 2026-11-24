#!/bin/sh
# Draws every state of the Power Flow widget, without installing it.
# Output: widget/build/states-dark.png and widget/build/states-light.png.
# The cases are in Preview/States.swift. Needs the Xcode command line tools.
set -eu
cd "$(dirname "$0")"

mkdir -p build
xcrun swiftc -O -parse-as-library -target arm64-apple-macos14.0 \
    Sources/PowerSample.swift Sources/Views.swift Preview/States.swift -o build/states
./build/states build
