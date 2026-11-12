#!/bin/zsh
set -eu
repo_dir="${0:A:h:h}"
app_dir="${1:-$repo_dir/.build/Mac Awake.app}"
mkdir -p "$app_dir/Contents/MacOS"
/usr/bin/xcrun swiftc -swift-version 5 -O -framework AppKit \
    -target "$(/usr/bin/uname -m)-apple-macos14.0" \
    "$repo_dir/Sources/main.swift" -o "$app_dir/Contents/MacOS/MacAwake"
/bin/cp "$repo_dir/Sources/Info.plist" "$app_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app_dir"
"$app_dir/Contents/MacOS/MacAwake" --self-test
/usr/bin/codesign --verify --strict "$app_dir"
print "Built $app_dir"
