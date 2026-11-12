#!/bin/zsh
set -eu
repo_dir="${0:A:h:h}"
mkdir -p "$repo_dir/Shortcuts" "$repo_dir/.build/unsigned"
/usr/bin/xcrun swift "$repo_dir/scripts/generate-shortcuts.swift" "$repo_dir" "$repo_dir/Shortcuts"
for mode in On Off; do
    /bin/cp "$repo_dir/Shortcuts/Keep Mac Awake $mode.plist" "$repo_dir/.build/unsigned/Keep Mac Awake $mode.shortcut"
    /usr/bin/shortcuts sign --mode anyone \
        --input "$repo_dir/.build/unsigned/Keep Mac Awake $mode.shortcut" \
        --output "$repo_dir/Shortcuts/Keep Mac Awake $mode.shortcut"
done
